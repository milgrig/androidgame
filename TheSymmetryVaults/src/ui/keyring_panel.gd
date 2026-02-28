class_name KeyringPanel
extends Control
## KeyringPanel — Left-side panel for Layer 3 keyring assembly.
##
## Displays a vertical list of keyring slots. Each slot represents a subgroup
## the player needs to discover by adding keys (group elements) to it.
## Slots transition through three states: EMPTY -> FILLING -> LOCKED.
##
## Signals:
##   key_removed(sym_id)  — player tapped a key inside a slot to remove it


# --- Signals ---

## Emitted when a key is tapped inside a FILLING slot (to remove it).
signal key_removed(sym_id: String)

## Emitted when a locked slot is tapped (to show subgroup on map).
## elements: the sym_ids of the subgroup. Empty array = deselect.
signal slot_selected(elements: Array)


# --- Constants ---

const L3_GOLD := Color(0.95, 0.80, 0.20, 1.0)
const L3_GOLD_DIM := Color(0.70, 0.60, 0.15, 0.7)
const L3_GOLD_BG := Color(0.06, 0.05, 0.02, 0.8)
const L3_GOLD_BORDER := Color(0.55, 0.45, 0.10, 0.7)
const L3_GOLD_GLOW := Color(1.0, 0.90, 0.30, 0.9)
const L3_LOCKED_BG := Color(0.08, 0.07, 0.02, 0.95)

## Slot height tiers based on total slot count
const SLOT_HEIGHT_NORMAL := 72
const SLOT_HEIGHT_MEDIUM := 58
const SLOT_HEIGHT_COMPACT := 50
const SLOT_HEIGHT_TINY := 44

## Maximum visible slots before scrolling
const MAX_VISIBLE_SLOTS := 8


# --- State ---

## Reference to room_state (for colors and names)
var _room_state: RoomState = null

## Reference to KeyringAssemblyManager
var _assembly_mgr: KeyringAssemblyManager = null

## Panel dimensions
var _panel_rect: Rect2 = Rect2()

## Slot nodes
var _slots: Array = []  # Array[Panel] — the slot panel nodes

## Progress label node
var _progress_label: Label = null

## Scroll container (only if many slots)
var _scroll: ScrollContainer = null

## Slot list container
var _slot_list: VBoxContainer = null

## Currently selected locked slot index (-1 = none)
var _selected_slot: int = -1


# --- Setup ---

## Build the keyring panel inside the given parent (CanvasLayer).
## panel_rect: the rectangle within which to build the panel.
## room_state: RoomState for colors/names.
## assembly_mgr: KeyringAssemblyManager for state.
func setup(parent: Node, panel_rect: Rect2, room_state: RoomState,
		assembly_mgr: KeyringAssemblyManager) -> void:
	_panel_rect = panel_rect
	_room_state = room_state
	_assembly_mgr = assembly_mgr

	# Position and size of this Control
	position = panel_rect.position
	size = panel_rect.size
	name = "KeyringPanel"

	# Build the frame panel
	var frame: Panel = Panel.new()
	frame.name = "KeyringFrame"
	frame.position = Vector2.ZERO
	frame.size = panel_rect.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.7)
	style.border_color = L3_GOLD_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 6)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	# Frame title
	var title: Label = Label.new()
	title.name = "KeyringFrameTitle"
	title.text = "Брелки"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", L3_GOLD_DIM)
	title.position = Vector2(8, 3)
	title.size = Vector2(panel_rect.size.x - 16, 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# Progress label at the bottom
	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.add_theme_font_size_override("font_size", 11)
	_progress_label.add_theme_color_override("font_color", L3_GOLD_DIM)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.position = Vector2(4, panel_rect.size.y - 18)
	_progress_label.size = Vector2(panel_rect.size.x - 8, 16)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_label)

	# Content area (between title and progress label)
	var content_y: float = 20.0
	var content_h: float = panel_rect.size.y - 42.0  # 20 top + 22 bottom
	var content_w: float = panel_rect.size.x - 12.0  # 6px padding each side

	# Determine if we need scrolling
	var total_slots: int = assembly_mgr.get_total_count()
	var slot_h: int = _get_slot_height(total_slots)
	var need_scroll: bool = total_slots > MAX_VISIBLE_SLOTS

	# Build slot list container
	_slot_list = VBoxContainer.new()
	_slot_list.name = "SlotList"
	_slot_list.add_theme_constant_override("separation", 3)

	if need_scroll:
		_scroll = ScrollContainer.new()
		_scroll.name = "KeyringScroll"
		_scroll.position = Vector2(6, content_y)
		_scroll.size = Vector2(content_w, content_h)
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		add_child(_scroll)
		_scroll.add_child(_slot_list)
	else:
		_slot_list.position = Vector2(6, content_y)
		_slot_list.size = Vector2(content_w, content_h)
		add_child(_slot_list)

	# Build slots
	_build_slots(total_slots, content_w, slot_h)

	# Update progress
	update_progress()


## Determine slot height based on count.
func _get_slot_height(count: int) -> int:
	if count <= 5:
		return SLOT_HEIGHT_NORMAL
	elif count <= 8:
		return SLOT_HEIGHT_MEDIUM
	elif count <= 10:
		return SLOT_HEIGHT_COMPACT
	else:
		return SLOT_HEIGHT_TINY


## Build all slot panels.
func _build_slots(count: int, width: float, slot_h: int) -> void:
	_slots.clear()
	for i in range(count):
		var slot: Panel = _build_one_slot(i, width, slot_h)
		_slot_list.add_child(slot)
		_slots.append(slot)

	# Mark the first slot as active
	if _slots.size() > 0:
		_update_slot_visual(0, SlotState.FILLING)


## Build one keyring slot panel.
func _build_one_slot(index: int, width: float, height: int) -> Panel:
	var slot: Panel = Panel.new()
	slot.name = "KeyringSlot_%d" % index
	slot.custom_minimum_size = Vector2(width - 4, height)
	slot.size = Vector2(width - 4, height)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style — dashed-look (empty state)
	slot.add_theme_stylebox_override("panel", _make_slot_style(SlotState.EMPTY))

	# Slot label "Брелок #N"
	var lbl: Label = Label.new()
	lbl.name = "SlotLabel"
	lbl.text = "Брелок #%d" % (index + 1)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.3, 0.6))
	lbl.position = Vector2(6, 2)
	lbl.size = Vector2(width - 50, 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)

	# Status indicator (right side: arrow for active, lock for locked)
	var status: Label = Label.new()
	status.name = "StatusIcon"
	status.text = ""
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", L3_GOLD_DIM)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.position = Vector2(width - 46, 2)
	status.size = Vector2(36, 16)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(status)

	# Key dots container (HFlowContainer for the colored key dots)
	var dots: HFlowContainer = HFlowContainer.new()
	dots.name = "KeyDots"
	dots.position = Vector2(6, 18)
	dots.size = Vector2(width - 16, height - 22)
	dots.add_theme_constant_override("h_separation", 3)
	dots.add_theme_constant_override("v_separation", 2)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(dots)

	# Key count label
	var count_lbl: Label = Label.new()
	count_lbl.name = "KeyCount"
	count_lbl.text = ""
	count_lbl.add_theme_font_size_override("font_size", 9)
	count_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.3, 0.5))
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_lbl.position = Vector2(width - 80, height - 16)
	count_lbl.size = Vector2(68, 14)
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(count_lbl)

	return slot


## Slot visual states.
enum SlotState { EMPTY, FILLING, LOCKED }


## Create a StyleBoxFlat for a slot state.
func _make_slot_style(state: SlotState) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	match state:
		SlotState.EMPTY:
			s.bg_color = Color(0.04, 0.04, 0.06, 0.4)
			s.border_color = Color(0.3, 0.28, 0.15, 0.3)
		SlotState.FILLING:
			s.bg_color = Color(0.05, 0.05, 0.03, 0.7)
			s.border_color = L3_GOLD_BORDER
		SlotState.LOCKED:
			s.bg_color = L3_LOCKED_BG
			s.border_color = L3_GOLD
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		s.set(prop, 1 if state == SlotState.EMPTY else 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(prop, 4)
	return s


## Update a slot's visual appearance.
func _update_slot_visual(slot_index: int, state: SlotState) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]

	# Update style
	slot.add_theme_stylebox_override("panel", _make_slot_style(state))

	# Update label colors
	var lbl = slot.get_node_or_null("SlotLabel")
	var status = slot.get_node_or_null("StatusIcon")

	match state:
		SlotState.EMPTY:
			if lbl:
				lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.3, 0.5))
			if status:
				status.text = ""
		SlotState.FILLING:
			if lbl:
				lbl.add_theme_color_override("font_color", L3_GOLD_DIM)
			if status:
				status.text = "<-"
				status.add_theme_color_override("font_color", L3_GOLD)
		SlotState.LOCKED:
			if lbl:
				lbl.add_theme_color_override("font_color", L3_GOLD)
			if status:
				status.text = "OK"
				status.add_theme_color_override("font_color", L3_GOLD)


# --- Public API ---

## Add a key dot to the active slot visual.
func add_key_visual(slot_index: int, sym_id: String) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]
	var dots: HFlowContainer = slot.get_node_or_null("KeyDots")
	if dots == null:
		return

	# Create a clickable key dot
	var dot_btn: Button = Button.new()
	dot_btn.name = "KeyDot_%s" % sym_id
	dot_btn.custom_minimum_size = Vector2(22, 18)
	dot_btn.size = Vector2(22, 18)
	dot_btn.focus_mode = Control.FOCUS_NONE
	dot_btn.flat = true

	# Color from room state
	var color: Color = _get_key_color(sym_id)

	# Inner content: colored dot + tiny label
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.name = "Content"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 2)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_btn.add_child(hbox)

	var dot_rect: ColorRect = ColorRect.new()
	dot_rect.name = "Dot"
	dot_rect.custom_minimum_size = Vector2(6, 6)
	dot_rect.size = Vector2(6, 6)
	dot_rect.color = color
	dot_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot_rect)

	var dot_lbl: Label = Label.new()
	dot_lbl.name = "Lbl"
	# Find room index for this sym_id to show number
	var room_idx: int = _sym_id_to_room_idx(sym_id)
	dot_lbl.text = str(room_idx) if room_idx > 0 else "e"
	dot_lbl.add_theme_font_size_override("font_size", 8)
	dot_lbl.add_theme_color_override("font_color", color)
	dot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot_lbl)

	# Style
	var dot_style: StyleBoxFlat = StyleBoxFlat.new()
	dot_style.bg_color = Color(color.r, color.g, color.b, 0.08)
	dot_style.border_color = Color(color.r, color.g, color.b, 0.3)
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		dot_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		dot_style.set(prop, 3)
	dot_btn.add_theme_stylebox_override("normal", dot_style)

	var hover_style: StyleBoxFlat = dot_style.duplicate()
	hover_style.bg_color = Color(color.r, color.g, color.b, 0.2)
	hover_style.border_color = Color(color.r, color.g, color.b, 0.6)
	dot_btn.add_theme_stylebox_override("hover", hover_style)

	# Connect tap to remove
	dot_btn.pressed.connect(_on_dot_pressed.bind(sym_id))
	dots.add_child(dot_btn)

	# Update key count
	_update_key_count(slot_index)
	# Ensure this slot shows as FILLING
	_update_slot_visual(slot_index, SlotState.FILLING)


## Remove a key dot from a slot visual.
func remove_key_visual(slot_index: int, sym_id: String) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]
	var dots: HFlowContainer = slot.get_node_or_null("KeyDots")
	if dots == null:
		return

	var dot_name: String = "KeyDot_%s" % sym_id
	var dot = dots.get_node_or_null(dot_name)
	if dot:
		dot.queue_free()

	# Update key count (after frame so queue_free takes effect)
	_update_key_count(slot_index)

	# If no more keys, show as EMPTY (unless it's the active slot)
	if _assembly_mgr and slot_index == _assembly_mgr.get_active_slot_index():
		var keys = _assembly_mgr.get_active_keys()
		if keys.size() <= 1:  # Will be 0 after the queued free
			_update_slot_visual(slot_index, SlotState.FILLING)


## Lock a slot (subgroup found).
func lock_slot(slot_index: int, elements: Array) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	_update_slot_visual(slot_index, SlotState.LOCKED)

	# Update the label with subgroup info
	var slot: Panel = _slots[slot_index]
	var lbl = slot.get_node_or_null("SlotLabel")
	if lbl:
		if elements.size() == 1:
			lbl.text = "Брелок #%d — Тождество" % (slot_index + 1)
		elif _assembly_mgr and elements.size() == _assembly_mgr.get_all_sym_ids().size():
			lbl.text = "Брелок #%d — Вся группа" % (slot_index + 1)
		else:
			lbl.text = "Брелок #%d (пор. %d)" % [slot_index + 1, elements.size()]

	var count_lbl = slot.get_node_or_null("KeyCount")
	if count_lbl:
		count_lbl.text = "%d кл." % elements.size()
		count_lbl.add_theme_color_override("font_color", L3_GOLD_DIM)

	# Disable dot buttons in locked slot
	var dots: HFlowContainer = slot.get_node_or_null("KeyDots")
	if dots:
		for child in dots.get_children():
			if child is Button:
				child.disabled = true

	# Make locked slot clickable (to highlight subgroup on room map)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	if not slot.gui_input.is_connected(_on_locked_slot_clicked):
		slot.gui_input.connect(_on_locked_slot_clicked.bind(slot_index, elements))

	# Play glow animation
	_play_slot_glow(slot_index)

	# Activate next slot
	var next: int = slot_index + 1
	if next < _slots.size():
		_update_slot_visual(next, SlotState.FILLING)


## Update the progress label.
func update_progress() -> void:
	if _progress_label == null or _assembly_mgr == null:
		return
	var p: Dictionary = _assembly_mgr.get_progress()
	_progress_label.text = "Найдено: %d / %d" % [p["found"], p["total"]]
	if p["found"] >= p["total"]:
		_progress_label.add_theme_color_override("font_color", L3_GOLD)
	else:
		_progress_label.add_theme_color_override("font_color", L3_GOLD_DIM)


## Refresh the entire panel from assembly manager state.
## Call after restoring from save.
func refresh_from_state() -> void:
	if _assembly_mgr == null:
		return

	# Clear all dot containers
	for slot in _slots:
		var dots: HFlowContainer = slot.get_node_or_null("KeyDots") if is_instance_valid(slot) else null
		if dots:
			for child in dots.get_children():
				child.queue_free()

	# Rebuild locked slots
	var found: Array = _assembly_mgr.get_found_subgroups()
	for i in range(found.size()):
		if i < _slots.size():
			# Add dots for found subgroup
			for sym_id in found[i]:
				add_key_visual(i, sym_id)
			lock_slot(i, found[i])

	# Rebuild active slot
	var active_idx: int = _assembly_mgr.get_active_slot_index()
	var active_keys: Array[String] = _assembly_mgr.get_active_keys()
	if active_idx < _slots.size():
		_update_slot_visual(active_idx, SlotState.FILLING)
		for sym_id in active_keys:
			add_key_visual(active_idx, sym_id)

	update_progress()


## Show duplicate feedback on a slot (orange flash).
func show_duplicate_flash(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]

	# Flash orange then return to FILLING
	var flash_style: StyleBoxFlat = _make_slot_style(SlotState.FILLING)
	flash_style.border_color = Color(1.0, 0.6, 0.2, 0.9)
	flash_style.bg_color = Color(0.15, 0.08, 0.02, 0.7)
	slot.add_theme_stylebox_override("panel", flash_style)

	# Return to normal after delay
	var parent_scene: Node = _find_scene_root()
	if parent_scene:
		var tw: Tween = parent_scene.create_tween()
		tw.tween_interval(0.5)
		tw.tween_callback(_update_slot_visual.bind(slot_index, SlotState.FILLING))


## Cleanup the panel.
func cleanup() -> void:
	_slots.clear()
	_assembly_mgr = null
	_room_state = null


# --- Internal helpers ---

## Get the color for a sym_id via room_state.
func _get_key_color(sym_id: String) -> Color:
	if _room_state == null:
		return Color.WHITE
	var idx: int = _sym_id_to_room_idx(sym_id)
	if idx >= 0 and idx < _room_state.colors.size():
		return _room_state.colors[idx]
	return Color.WHITE


## Map sym_id to room index.
func _sym_id_to_room_idx(sym_id: String) -> int:
	if _room_state == null:
		return -1
	for i in range(_room_state.perm_ids.size()):
		if _room_state.perm_ids[i] == sym_id:
			return i
	return -1


## Update the key count label for a slot.
func _update_key_count(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]
	var dots: HFlowContainer = slot.get_node_or_null("KeyDots")
	var count_lbl = slot.get_node_or_null("KeyCount")
	if dots and count_lbl:
		var count: int = dots.get_child_count()
		count_lbl.text = "%d кл." % count if count > 0 else ""


## Play a gold glow animation on a slot.
func _play_slot_glow(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]

	var parent_scene: Node = _find_scene_root()
	if parent_scene == null:
		return

	# Pulse the modulate brightness
	var tw: Tween = parent_scene.create_tween()
	tw.tween_property(slot, "modulate", Color(1.3, 1.2, 0.8, 1.0), 0.3)
	tw.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)


## Handle dot button press (remove key from active slot).
func _on_dot_pressed(sym_id: String) -> void:
	key_removed.emit(sym_id)


## Handle locked slot click — toggle selection and emit signal for room map.
func _on_locked_slot_clicked(event: InputEvent, slot_index: int, elements: Array) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	# Toggle: deselect if already selected, otherwise select new
	if _selected_slot == slot_index:
		_deselect_slot()
		slot_selected.emit([])
	else:
		_deselect_slot()  # deselect previous
		_selected_slot = slot_index
		_apply_selected_style(slot_index)
		slot_selected.emit(elements)


## Apply a bright gold "selected" border to a locked slot.
func _apply_selected_style(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.10, 0.03, 0.95)
	s.border_color = Color(1.0, 0.90, 0.30, 0.9)
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		s.set(prop, 3)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(prop, 5)
	# Outer glow via shadow
	s.shadow_color = Color(0.95, 0.80, 0.20, 0.3)
	s.shadow_size = 6
	slot.add_theme_stylebox_override("panel", s)


## Deselect the currently selected slot, restoring its locked style.
func _deselect_slot() -> void:
	if _selected_slot >= 0 and _selected_slot < _slots.size():
		_update_slot_visual(_selected_slot, SlotState.LOCKED)
	_selected_slot = -1


## Find the scene root for creating tweens.
func _find_scene_root() -> Node:
	var node: Node = self
	while node != null:
		if node is Node2D:
			return node
		node = node.get_parent()
	return get_tree().current_scene if get_tree() else null
