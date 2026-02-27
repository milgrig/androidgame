## KeyBar — Horizontal key panel at the bottom of the screen.
##
## Each key = a button coloured to its room. Clicking a key emits
## key_pressed so the game can apply the corresponding permutation.
##
## Layout adapts to the number of keys:
##   <=12  — single row with spacing
##   13-24 — compact grid, smaller buttons
##   >24   — wrapped in a ScrollContainer
##
## Signals:
##   key_pressed(key_idx)  — a discovered key was clicked
##   key_hovered(key_idx)  — mouse entered a key (-1 on leave)

class_name KeyBar
extends Control

# ── Signals ──────────────────────────────────────────────────────────

## Emitted when the player clicks a discovered key button.
signal key_pressed(key_idx: int)

## Emitted on mouse enter (key_idx >= 0) or mouse leave (key_idx == -1).
signal key_hovered(key_idx: int)

# ── Constants ────────────────────────────────────────────────────────

const GOLD := Color(0.788, 0.659, 0.298, 1.0)     # #c9a84c
const PANEL_BG := Color(0.043, 0.043, 0.078, 1.0)  # #0b0b14
const BORDER_COLOR := Color(0.094, 0.094, 0.157, 1.0)  # #181828
const DIM_COLOR := Color(0.353, 0.353, 0.416, 1.0)  # #5a5a6a

## Home symbol (house glyph) used instead of "0"
const HOME_GLYPH := "\u2302"  # ⌂

# ── Layout thresholds ────────────────────────────────────────────────

const COMPACT_THRESHOLD := 12   # > 12 keys → compact mode
const SCROLL_THRESHOLD  := 24   # > 24 keys → scroll mode

# Button sizes per tier
const BTN_SIZE_NORMAL  := Vector2(48, 28)
const BTN_SIZE_COMPACT := Vector2(38, 24)
const BTN_GAP_NORMAL   := 4
const BTN_GAP_COMPACT  := 3
const BTN_FONT_NORMAL  := 10
const BTN_FONT_COMPACT := 9
const DOT_SIZE_NORMAL  := 8
const DOT_SIZE_COMPACT := 6

# ── Nodes ────────────────────────────────────────────────────────────

var _panel: PanelContainer
var _scroll: ScrollContainer        # only created when >24 keys
var _flow: HFlowContainer
var _buttons: Array = []             # Array[Button]

# ── State (cached for efficient updates) ─────────────────────────────

var _total_keys: int = 0
var _current_room: int = -1

## Whether Home (key 0) is visible. Set to false at level start;
## becomes true after the first correct permutation is discovered.
var home_visible: bool = false

## Layer 2 pairing state: room_index -> {partner: int, is_self_inverse: bool}
var _pair_data: Dictionary = {}
## Overlay for drawing pair bracket lines between paired keys
var _pair_overlay: Control = null
## Whether Layer 2 pairing mode is active
var _layer2_active: bool = false

## Layer 2 green colors
const L2_PAIR_COLOR := Color(0.2, 0.85, 0.4, 0.7)
const L2_SELF_COLOR := Color(1.0, 0.85, 0.3, 0.7)
const L2_PAIRED_BORDER := Color(0.2, 0.85, 0.4, 0.5)
const L2_SELF_BORDER := Color(1.0, 0.85, 0.3, 0.5)


# ── Lifecycle ────────────────────────────────────────────────────────

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()


# ── Public API ───────────────────────────────────────────────────────

## Rebuild all key buttons from room_state.
## Call this after setup or whenever discovery changes.
func rebuild(room_state: RoomState) -> void:
	_clear_buttons()
	if room_state == null or room_state.group_order == 0:
		return

	_total_keys = room_state.group_order
	_current_room = room_state.current_room

	# Determine layout tier
	var compact: bool = _total_keys > COMPACT_THRESHOLD
	var need_scroll: bool = _total_keys > SCROLL_THRESHOLD

	var btn_size: Vector2 = BTN_SIZE_COMPACT if compact else BTN_SIZE_NORMAL
	var btn_gap: int = BTN_GAP_COMPACT if compact else BTN_GAP_NORMAL
	var font_sz: int = BTN_FONT_COMPACT if compact else BTN_FONT_NORMAL
	var dot_sz: int = DOT_SIZE_COMPACT if compact else DOT_SIZE_NORMAL

	# Ensure scroll container exists when needed
	_ensure_scroll(need_scroll)

	# Configure flow container
	_flow.add_theme_constant_override("h_separation", btn_gap)
	_flow.add_theme_constant_override("v_separation", btn_gap)

	for i in range(_total_keys):
		# Hide Home (key 0) until home_visible is set
		if i == 0 and not home_visible:
			_buttons.append(null)  # placeholder to keep indices aligned
			continue

		var color: Color = room_state.colors[i] if i < room_state.colors.size() else Color.WHITE
		var is_discovered: bool = room_state.is_discovered(i)
		var is_current: bool = (i == _current_room)

		var btn := _make_key_button(i, color, is_discovered, is_current,
				btn_size, font_sz, dot_sz)
		_flow.add_child(btn)
		_buttons.append(btn)


## Efficiently update visual state without full rebuild.
## Use after a key press, room change, or single discovery.
func update_state(room_state: RoomState) -> void:
	if room_state == null:
		return
	_current_room = room_state.current_room
	for i in range(mini(_buttons.size(), room_state.group_order)):
		var btn = _buttons[i]
		if btn == null:
			continue  # Home placeholder when hidden
		var is_discovered: bool = room_state.is_discovered(i)
		var is_current: bool = (i == _current_room)
		_apply_button_state(btn, i, room_state.colors[i], is_discovered, is_current)


## Reveal the Home key (index 0). Call when the first correct
## permutation is found — mirrors RoomMapPanel.home_visible logic.
## Triggers a full rebuild to insert the Home button.
func reveal_home(room_state: RoomState) -> void:
	if home_visible:
		return
	home_visible = true
	rebuild(room_state)


## Update Layer 2 pairing visualization on existing buttons.
## Called by LayerModeController after each inverse pair is matched.
## room_state: RoomState for sym_id → room_index mapping
## pair_mgr: InversePairManager with current pairing state
func update_layer2_pairs(room_state: RoomState, pair_mgr: InversePairManager) -> void:
	if room_state == null or pair_mgr == null:
		return
	_layer2_active = true

	# Rebuild _pair_data from InversePairManager's pairs
	_pair_data.clear()
	var pairs: Array = pair_mgr.get_pairs()
	for pair in pairs:
		if not pair.paired:
			continue  # Only show matched pairs

		# Map sym_ids → room indices
		var key_idx: int = _sym_id_to_room_idx(pair.key_sym_id, room_state)
		var inv_idx: int = _sym_id_to_room_idx(pair.inverse_sym_id, room_state)
		if key_idx < 0 or inv_idx < 0:
			continue

		_pair_data[key_idx] = {"partner": inv_idx, "is_self_inverse": pair.is_self_inverse}
		if not pair.is_self_inverse:
			_pair_data[inv_idx] = {"partner": key_idx, "is_self_inverse": false}

	# Apply pairing visuals to each button
	for i in range(_buttons.size()):
		var btn = _buttons[i]
		if btn == null or not is_instance_valid(btn):
			continue
		if _pair_data.has(i):
			var info: Dictionary = _pair_data[i]
			var is_self_inv: bool = info["is_self_inverse"]
			_apply_paired_style(btn, i, room_state, is_self_inv)


## Clear Layer 2 pairing state and restore default button styles.
func clear_layer2_pairs() -> void:
	_pair_data.clear()
	_layer2_active = false
	if _pair_overlay != null and is_instance_valid(_pair_overlay):
		_pair_overlay.queue_free()
		_pair_overlay = null


# ── Internal: shell construction ─────────────────────────────────────

func _build_shell() -> void:
	# PanelContainer as visual background
	_panel = PanelContainer.new()
	_panel.name = "KeyBarPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)  # transparent — outer frame provides bg
	style.border_color = Color(0, 0, 0, 0)
	style.border_width_top = 0
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	# Default flow container (no scroll)
	_flow = HFlowContainer.new()
	_flow.name = "KeyGrid"
	_flow.add_theme_constant_override("h_separation", BTN_GAP_NORMAL)
	_flow.add_theme_constant_override("v_separation", BTN_GAP_NORMAL)
	_panel.add_child(_flow)


## Wrap the flow inside a ScrollContainer when many keys exist.
func _ensure_scroll(need_scroll: bool) -> void:
	var has_scroll: bool = _scroll != null and is_instance_valid(_scroll)
	if need_scroll and not has_scroll:
		# Remove flow from panel, wrap in scroll
		if _flow.get_parent() == _panel:
			_panel.remove_child(_flow)
		_scroll = ScrollContainer.new()
		_scroll.name = "KeyScroll"
		_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_panel.add_child(_scroll)
		_scroll.add_child(_flow)
	elif not need_scroll and has_scroll:
		# Remove scroll wrapper
		_scroll.remove_child(_flow)
		_panel.remove_child(_scroll)
		_scroll.queue_free()
		_scroll = null
		_panel.add_child(_flow)


# ── Internal: button creation ────────────────────────────────────────

func _make_key_button(idx: int, color: Color, is_discovered: bool,
		is_current: bool, btn_size: Vector2, font_sz: int, dot_sz: int) -> Button:
	var btn := Button.new()
	btn.name = "Key_%d" % idx
	btn.custom_minimum_size = btn_size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_text = false
	btn.flat = true

	# --- Inner layout: coloured dot + number label ---
	# We use button text = "" and place children manually via an HBoxContainer
	var hbox := HBoxContainer.new()
	hbox.name = "Content"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	# Colour dot (square with rounded corners)
	var dot := ColorRect.new()
	dot.name = "Dot"
	dot.custom_minimum_size = Vector2(dot_sz, dot_sz)
	dot.size = Vector2(dot_sz, dot_sz)
	dot.color = color
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot)

	# Number label
	var lbl := Label.new()
	lbl.name = "Num"
	lbl.text = HOME_GLYPH if idx == 0 else str(idx)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	# Apply visual state (discovered / locked / current)
	_apply_button_state(btn, idx, color, is_discovered, is_current)

	# Signals
	btn.pressed.connect(_on_key_pressed.bind(idx))
	btn.mouse_entered.connect(_on_key_mouse_entered.bind(idx))
	btn.mouse_exited.connect(_on_key_mouse_exited)

	return btn


## Apply discovered/locked/current styling to a button.
func _apply_button_state(btn: Button, idx: int, color: Color,
		is_discovered: bool, is_current: bool) -> void:
	# Style boxes for normal / hover
	var border_col: Color
	var bg_alpha: float = 0.0

	if is_current:
		border_col = GOLD
	elif is_discovered:
		border_col = Color(color.r, color.g, color.b, 0.2)
	else:
		border_col = BORDER_COLOR

	# Normal style
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, bg_alpha)
	normal_style.border_color = border_col
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		normal_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		normal_style.set(prop, 3)
	btn.add_theme_stylebox_override("normal", normal_style)

	# Hover style (subtle lift effect via brighter border)
	var hover_style := normal_style.duplicate() as StyleBoxFlat
	if is_discovered:
		hover_style.border_color = Color(color.r, color.g, color.b, 0.5)
		hover_style.bg_color = Color(color.r, color.g, color.b, 0.06)
	btn.add_theme_stylebox_override("hover", hover_style)

	# Pressed style
	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	if is_discovered:
		pressed_style.bg_color = Color(color.r, color.g, color.b, 0.12)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	# Current-room glow effect via box shadow approximation
	if is_current:
		# Use expanded content margin to fake a subtle glow
		normal_style.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.2)
		normal_style.shadow_size = 8

	# Opacity & interactivity
	if is_discovered:
		btn.modulate.a = 1.0
		btn.disabled = false
	else:
		btn.modulate.a = 0.2
		btn.disabled = true

	# Label colour
	var lbl := _find_child_by_name(btn, "Num") as Label
	if lbl:
		if is_discovered:
			lbl.add_theme_color_override("font_color", color)
		else:
			lbl.add_theme_color_override("font_color", DIM_COLOR)


# ── Internal: helpers ────────────────────────────────────────────────

func _clear_buttons() -> void:
	for btn in _buttons:
		if btn != null and is_instance_valid(btn):
			btn.queue_free()
	_buttons.clear()


## Recursively find a child node by name (shallow search).
func _find_child_by_name(parent: Node, child_name: String) -> Node:
	# Look within immediate children and one level deeper (HBox inside Button)
	for child in parent.get_children():
		if child.name == child_name:
			return child
		for grandchild in child.get_children():
			if grandchild.name == child_name:
				return grandchild
	return null


# ── Internal: Layer 2 pairing visuals ────────────────────────────────

## Map a sym_id to a room index via RoomState.perm_ids.
func _sym_id_to_room_idx(sym_id: String, room_state: RoomState) -> int:
	for i in range(room_state.perm_ids.size()):
		if room_state.perm_ids[i] == sym_id:
			return i
	return -1


## Apply green "paired" border + checkmark to a button.
## Self-inverse keys get a yellow/gold loop indicator instead.
func _apply_paired_style(btn: Button, idx: int, room_state: RoomState,
		is_self_inverse: bool) -> void:
	var color: Color = room_state.colors[idx] if idx < room_state.colors.size() else Color.WHITE
	var pair_border: Color = L2_SELF_BORDER if is_self_inverse else L2_PAIRED_BORDER
	var pair_accent: Color = L2_SELF_COLOR if is_self_inverse else L2_PAIR_COLOR

	# Update normal style — thicker green/yellow border
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(pair_accent.r, pair_accent.g, pair_accent.b, 0.06)
	normal_style.border_color = pair_border
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		normal_style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		normal_style.set(prop, 4)
	btn.add_theme_stylebox_override("normal", normal_style)

	# Hover style — brighter green/yellow background
	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.border_color = Color(pair_accent.r, pair_accent.g, pair_accent.b, 0.8)
	hover_style.bg_color = Color(pair_accent.r, pair_accent.g, pair_accent.b, 0.12)
	btn.add_theme_stylebox_override("hover", hover_style)

	# Pressed style
	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(pair_accent.r, pair_accent.g, pair_accent.b, 0.18)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	# Add or update pair indicator label (✓ for pair, ↻ for self-inverse)
	var indicator_name := "PairMark"
	var existing = _find_child_by_name(btn, indicator_name)
	if existing != null:
		existing.queue_free()

	var hbox = _find_child_by_name(btn, "Content")
	if hbox:
		var mark := Label.new()
		mark.name = indicator_name
		mark.text = "\u21BB" if is_self_inverse else "\u2713"  # ↻ or ✓
		mark.add_theme_font_size_override("font_size", 9)
		mark.add_theme_color_override("font_color", pair_accent)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(mark)

	# Update label color to the pair accent
	var lbl := _find_child_by_name(btn, "Num") as Label
	if lbl:
		lbl.add_theme_color_override("font_color", pair_accent)


# ── Signal handlers ──────────────────────────────────────────────────

func _on_key_pressed(key_idx: int) -> void:
	key_pressed.emit(key_idx)


func _on_key_mouse_entered(key_idx: int) -> void:
	key_hovered.emit(key_idx)


func _on_key_mouse_exited() -> void:
	key_hovered.emit(-1)
