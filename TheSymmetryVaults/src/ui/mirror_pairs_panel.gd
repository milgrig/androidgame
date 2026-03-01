class_name MirrorPairsPanel
extends Control
## MirrorPairsPanel — Left-side panel for Layer 2 inverse pairing.
##
## Displays a vertical list of mirror-pair slots. Each slot has:
##   [key] ↔ [???]
## The player taps ⊕ on a key in the KeyBar to try filling the ??? slot.
## If the candidate is the correct inverse → slot locks green.
## If wrong → bounce-back animation (red flash).
## Self-inverse keys: player taps the SAME key → slot locks yellow.
##
## Mirrors the Layer 3 KeyringPanel layout pattern.
##
## Signals:
##   candidate_placed(pair_index, candidate_sym_id) — player placed a candidate


# --- Signals ---

## Emitted when player taps ⊕ to place a candidate into a mirror slot.
signal candidate_placed(pair_index: int, candidate_sym_id: String)


# --- Constants (Layer 2 green theme) ---

const L2_GREEN := Color(0.2, 0.85, 0.4, 1.0)
const L2_GREEN_DIM := Color(0.15, 0.55, 0.3, 0.7)
const L2_GREEN_BG := Color(0.02, 0.06, 0.03, 0.8)
const L2_GREEN_BORDER := Color(0.15, 0.45, 0.25, 0.7)
const L2_GREEN_GLOW := Color(0.3, 1.0, 0.5, 0.9)
const L2_LOCKED_BG := Color(0.02, 0.08, 0.03, 0.95)

const L2_SELF_COLOR := Color(1.0, 0.85, 0.3, 0.9)
const L2_SELF_BORDER := Color(0.6, 0.5, 0.15, 0.7)
const L2_SELF_BG := Color(0.06, 0.05, 0.02, 0.95)

const L2_WRONG_COLOR := Color(1.0, 0.35, 0.3, 0.9)

## Slot height tiers based on total pair count
const SLOT_HEIGHT_NORMAL := 52
const SLOT_HEIGHT_MEDIUM := 44
const SLOT_HEIGHT_COMPACT := 38

## Maximum visible slots before scrolling
const MAX_VISIBLE_SLOTS := 10


# --- State ---

var _room_state: RoomState = null
var _pair_mgr: InversePairManager = null
var _panel_rect: Rect2 = Rect2()

## Slot nodes: one per pair (from InversePairManager.pairs)
var _slots: Array = []  # Array[Panel]

## Progress label node
var _progress_label: Label = null

## Scroll container (if many pairs)
var _scroll: ScrollContainer = null

## Slot list container
var _slot_list: VBoxContainer = null

## Index of the currently active (next to fill) slot (-1 if all done)
var _active_slot: int = 0


# --- Setup ---

## Build the mirror pairs panel inside the given parent.
## panel_rect: the rectangle within which to build.
## room_state: RoomState for colors/names.
## pair_mgr: InversePairManager with pair data.
func setup(parent: Node, panel_rect: Rect2, room_state: RoomState,
		pair_mgr: InversePairManager) -> void:
	_panel_rect = panel_rect
	_room_state = room_state
	_pair_mgr = pair_mgr

	position = panel_rect.position
	size = panel_rect.size
	name = "MirrorPairsPanel"

	# Build the frame
	var frame: Panel = Panel.new()
	frame.name = "MirrorFrame"
	frame.position = Vector2.ZERO
	frame.size = panel_rect.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.03, 0.7)
	style.border_color = L2_GREEN_BORDER
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
	title.name = "MirrorFrameTitle"
	title.text = "Зеркальные пары"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", L2_GREEN_DIM)
	title.position = Vector2(8, 3)
	title.size = Vector2(panel_rect.size.x - 16, 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# Progress label at the bottom
	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.add_theme_font_size_override("font_size", 11)
	_progress_label.add_theme_color_override("font_color", L2_GREEN_DIM)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.position = Vector2(4, panel_rect.size.y - 18)
	_progress_label.size = Vector2(panel_rect.size.x - 8, 16)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_label)

	# Content area
	var content_y: float = 20.0
	var content_h: float = panel_rect.size.y - 42.0
	var content_w: float = panel_rect.size.x - 12.0

	# Determine scrolling
	var total_pairs: int = pair_mgr.get_pairs().size()
	var slot_h: int = _get_slot_height(total_pairs)
	var need_scroll: bool = total_pairs > MAX_VISIBLE_SLOTS

	# Build slot list
	_slot_list = VBoxContainer.new()
	_slot_list.name = "PairSlotList"
	_slot_list.add_theme_constant_override("separation", 3)

	if need_scroll:
		_scroll = ScrollContainer.new()
		_scroll.name = "MirrorScroll"
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

	# Build pair slots
	_build_slots(pair_mgr.get_pairs(), content_w, slot_h)

	# Update progress
	update_progress()


## Determine slot height based on count.
func _get_slot_height(count: int) -> int:
	if count <= 6:
		return SLOT_HEIGHT_NORMAL
	elif count <= 10:
		return SLOT_HEIGHT_MEDIUM
	else:
		return SLOT_HEIGHT_COMPACT


## Build all pair slots.
func _build_slots(pairs: Array, width: float, slot_h: int) -> void:
	_slots.clear()
	for i in range(pairs.size()):
		var pair = pairs[i]
		var slot: Panel = _build_one_slot(i, pair, width, slot_h)
		_slot_list.add_child(slot)
		_slots.append(slot)

	# Mark first unpaired as active
	_find_next_active()


## Build one mirror-pair slot: [key_dot key_name] ↔ [???]
func _build_one_slot(index: int, pair, width: float, height: int) -> Panel:
	var slot: Panel = Panel.new()
	slot.name = "MirrorSlot_%d" % index
	slot.custom_minimum_size = Vector2(width - 4, height)
	slot.size = Vector2(width - 4, height)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Default empty style
	slot.add_theme_stylebox_override("panel", _make_slot_style("empty"))

	# --- Left side: the key (always shown) ---
	var key_color: Color = _get_key_color(pair.key_sym_id)
	var key_room_idx: int = _sym_id_to_room_idx(pair.key_sym_id)

	# Key colored dot
	var key_dot: ColorRect = ColorRect.new()
	key_dot.name = "KeyDot"
	key_dot.custom_minimum_size = Vector2(10, 10)
	key_dot.size = Vector2(10, 10)
	key_dot.color = key_color
	key_dot.position = Vector2(6, (height - 10) / 2.0)
	key_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(key_dot)

	# Key number label
	var key_lbl: Label = Label.new()
	key_lbl.name = "KeyLabel"
	key_lbl.text = str(key_room_idx)
	key_lbl.add_theme_font_size_override("font_size", 12)
	key_lbl.add_theme_color_override("font_color", key_color)
	key_lbl.position = Vector2(20, (height - 16) / 2.0)
	key_lbl.size = Vector2(30, 16)
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(key_lbl)

	# --- Center: arrow ↔ ---
	var arrow: Label = Label.new()
	arrow.name = "Arrow"
	arrow.text = "↔"
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.add_theme_color_override("font_color", L2_GREEN_DIM)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var arrow_x: float = width * 0.38
	arrow.position = Vector2(arrow_x, (height - 18) / 2.0)
	arrow.size = Vector2(24, 18)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(arrow)

	# --- Right side: mirror slot (??? or filled) ---
	var mirror_placeholder: Label = Label.new()
	mirror_placeholder.name = "MirrorPlaceholder"
	mirror_placeholder.text = "???"
	mirror_placeholder.add_theme_font_size_override("font_size", 12)
	mirror_placeholder.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.5))
	mirror_placeholder.position = Vector2(arrow_x + 28, (height - 16) / 2.0)
	mirror_placeholder.size = Vector2(width - arrow_x - 36, 16)
	mirror_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(mirror_placeholder)

	# Mirror dot (hidden, shown when filled)
	var mirror_dot: ColorRect = ColorRect.new()
	mirror_dot.name = "MirrorDot"
	mirror_dot.custom_minimum_size = Vector2(10, 10)
	mirror_dot.size = Vector2(10, 10)
	mirror_dot.color = Color.WHITE
	mirror_dot.position = Vector2(arrow_x + 28, (height - 10) / 2.0)
	mirror_dot.visible = false
	mirror_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(mirror_dot)

	# Mirror number label (hidden)
	var mirror_lbl: Label = Label.new()
	mirror_lbl.name = "MirrorLabel"
	mirror_lbl.text = ""
	mirror_lbl.add_theme_font_size_override("font_size", 12)
	mirror_lbl.position = Vector2(arrow_x + 42, (height - 16) / 2.0)
	mirror_lbl.size = Vector2(40, 16)
	mirror_lbl.visible = false
	mirror_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(mirror_lbl)

	# Status icon (right side)
	var status: Label = Label.new()
	status.name = "StatusIcon"
	status.text = ""
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", L2_GREEN_DIM)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.position = Vector2(width - 46, (height - 16) / 2.0)
	status.size = Vector2(36, 16)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(status)

	# If pair already matched (restoring from save), lock immediately
	if pair.paired:
		_apply_locked_visual(index, pair)

	return slot


# --- Slot Styles ---

func _make_slot_style(state: String) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	match state:
		"empty":
			s.bg_color = Color(0.03, 0.05, 0.04, 0.4)
			s.border_color = Color(0.15, 0.25, 0.15, 0.3)
		"active":
			s.bg_color = Color(0.03, 0.06, 0.04, 0.7)
			s.border_color = L2_GREEN_BORDER
		"locked":
			s.bg_color = L2_LOCKED_BG
			s.border_color = L2_GREEN
		"locked_self":
			s.bg_color = L2_SELF_BG
			s.border_color = L2_SELF_BORDER
		"wrong":
			s.bg_color = Color(0.1, 0.03, 0.03, 0.7)
			s.border_color = L2_WRONG_COLOR
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		s.set(prop, 1 if state == "empty" else 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(prop, 4)
	return s


# --- Public API ---

## Try to place a candidate key into the current active slot.
## Called by LayerModeController when player taps ⊕ on a key.
## Returns: {success: bool, pair_index: int, is_self_inverse: bool}
func try_place_candidate(candidate_sym_id: String) -> Dictionary:
	if _pair_mgr == null or _active_slot < 0:
		return {"success": false, "pair_index": -1, "is_self_inverse": false}

	var pairs: Array = _pair_mgr.get_pairs()
	if _active_slot >= pairs.size():
		return {"success": false, "pair_index": -1, "is_self_inverse": false}

	var pair = pairs[_active_slot]

	# Use InversePairManager to validate
	var result: Dictionary = _pair_mgr.try_pair(pair.key_sym_id, candidate_sym_id)

	if result["success"]:
		# Correct! Lock this slot
		_apply_locked_visual(_active_slot, pair)
		_play_slot_glow(_active_slot)
		_find_next_active()
		update_progress()
		return {"success": true, "pair_index": _active_slot, "is_self_inverse": pair.is_self_inverse}
	else:
		# Wrong! Show bounce-back flash
		_show_wrong_flash(_active_slot, candidate_sym_id)
		return {"success": false, "pair_index": _active_slot, "is_self_inverse": false,
				"result_name": result.get("result_name", "")}


## Try to place candidate into ANY unpaired slot (not just active).
## This allows the player to solve pairs in any order.
func try_place_candidate_any(candidate_sym_id: String) -> Dictionary:
	if _pair_mgr == null:
		return {"success": false, "pair_index": -1, "is_self_inverse": false}

	var pairs: Array = _pair_mgr.get_pairs()

	# Try each unpaired slot
	for i in range(pairs.size()):
		var pair = pairs[i]
		if pair.paired:
			continue

		var result: Dictionary = _pair_mgr.try_pair(pair.key_sym_id, candidate_sym_id)
		if result["success"]:
			_apply_locked_visual(i, pair)
			_play_slot_glow(i)
			# Bidirectional: if the reverse pair was also auto-paired, lock its slot too
			if not pair.is_self_inverse:
				var refreshed_pairs: Array = _pair_mgr.get_pairs()
				for j in range(refreshed_pairs.size()):
					if j != i and refreshed_pairs[j].paired and j < _slots.size():
						var ph = _slots[j].get_node_or_null("MirrorPlaceholder")
						if ph and ph.visible:
							# This slot just got auto-paired (bidirectional) — lock it
							_apply_locked_visual(j, refreshed_pairs[j])
							_play_slot_glow(j)
			_find_next_active()
			update_progress()
			return {"success": true, "pair_index": i, "is_self_inverse": pair.is_self_inverse}

	# No match found — flash on active slot
	if _active_slot >= 0 and _active_slot < _slots.size():
		_show_wrong_flash(_active_slot, candidate_sym_id)
	return {"success": false, "pair_index": -1, "is_self_inverse": false}


## Update the progress label.
func update_progress() -> void:
	if _progress_label == null or _pair_mgr == null:
		return
	var p: Dictionary = _pair_mgr.get_progress()
	_progress_label.text = "Пары: %d / %d" % [p["matched"], p["total"]]
	if p["matched"] >= p["total"]:
		_progress_label.add_theme_color_override("font_color", L2_GREEN)
	else:
		_progress_label.add_theme_color_override("font_color", L2_GREEN_DIM)


## Refresh from pair_mgr state (e.g. after restoring from save).
func refresh_from_state() -> void:
	if _pair_mgr == null:
		return
	var pairs: Array = _pair_mgr.get_pairs()
	for i in range(mini(pairs.size(), _slots.size())):
		if pairs[i].paired:
			_apply_locked_visual(i, pairs[i])
	_find_next_active()
	update_progress()


## Cleanup.
func cleanup() -> void:
	_slots.clear()
	_pair_mgr = null
	_room_state = null


# --- Internal ---

## Apply locked visual to a slot (pair found).
func _apply_locked_visual(slot_index: int, pair) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]
	var is_self: bool = pair.is_self_inverse

	# Update style
	slot.add_theme_stylebox_override("panel",
		_make_slot_style("locked_self" if is_self else "locked"))

	# Show the mirror key
	var inv_color: Color = _get_key_color(pair.inverse_sym_id)
	var inv_room_idx: int = _sym_id_to_room_idx(pair.inverse_sym_id)

	var mirror_dot = slot.get_node_or_null("MirrorDot")
	if mirror_dot:
		mirror_dot.color = inv_color
		mirror_dot.visible = true

	var mirror_lbl = slot.get_node_or_null("MirrorLabel")
	if mirror_lbl:
		mirror_lbl.text = str(inv_room_idx)
		var accent: Color = L2_SELF_COLOR if is_self else L2_GREEN
		mirror_lbl.add_theme_color_override("font_color", accent)
		mirror_lbl.visible = true

	# Hide placeholder
	var placeholder = slot.get_node_or_null("MirrorPlaceholder")
	if placeholder:
		placeholder.visible = false

	# Update arrow color
	var arrow = slot.get_node_or_null("Arrow")
	if arrow:
		var accent: Color = L2_SELF_COLOR if is_self else L2_GREEN
		arrow.add_theme_color_override("font_color", accent)

	# Status icon
	var status = slot.get_node_or_null("StatusIcon")
	if status:
		if is_self:
			status.text = "↻"
			status.add_theme_color_override("font_color", L2_SELF_COLOR)
		else:
			status.text = "✓"
			status.add_theme_color_override("font_color", L2_GREEN)


## Show a red flash on wrong guess, then restore.
func _show_wrong_flash(slot_index: int, candidate_sym_id: String) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]

	# Briefly show the wrong candidate
	var cand_color: Color = _get_key_color(candidate_sym_id)
	var cand_room_idx: int = _sym_id_to_room_idx(candidate_sym_id)

	var mirror_dot = slot.get_node_or_null("MirrorDot")
	if mirror_dot:
		mirror_dot.color = cand_color
		mirror_dot.visible = true

	var mirror_lbl = slot.get_node_or_null("MirrorLabel")
	if mirror_lbl:
		mirror_lbl.text = str(cand_room_idx)
		mirror_lbl.add_theme_color_override("font_color", L2_WRONG_COLOR)
		mirror_lbl.visible = true

	var placeholder = slot.get_node_or_null("MirrorPlaceholder")
	if placeholder:
		placeholder.visible = false

	# Red flash style
	slot.add_theme_stylebox_override("panel", _make_slot_style("wrong"))

	# Revert after delay
	var scene: Node = _find_scene_root()
	if scene:
		var tw: Tween = scene.create_tween()
		tw.tween_interval(0.5)
		tw.tween_callback(_revert_wrong_flash.bind(slot_index))


## Revert slot from wrong flash back to active/empty state.
func _revert_wrong_flash(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]

	# Hide mirror preview
	var mirror_dot = slot.get_node_or_null("MirrorDot")
	if mirror_dot:
		mirror_dot.visible = false
	var mirror_lbl = slot.get_node_or_null("MirrorLabel")
	if mirror_lbl:
		mirror_lbl.visible = false
	var placeholder = slot.get_node_or_null("MirrorPlaceholder")
	if placeholder:
		placeholder.visible = true

	# Restore style
	var is_active: bool = (slot_index == _active_slot)
	slot.add_theme_stylebox_override("panel",
		_make_slot_style("active" if is_active else "empty"))


## Find the next unpaired slot and mark it active.
func _find_next_active() -> void:
	_active_slot = -1
	if _pair_mgr == null:
		return
	var pairs: Array = _pair_mgr.get_pairs()
	for i in range(pairs.size()):
		if not pairs[i].paired:
			_active_slot = i
			break

	# Update visual: mark active slot, dim others
	for i in range(_slots.size()):
		if i >= pairs.size():
			continue
		if pairs[i].paired:
			continue  # already locked
		if i == _active_slot:
			_slots[i].add_theme_stylebox_override("panel", _make_slot_style("active"))
			var status = _slots[i].get_node_or_null("StatusIcon")
			if status:
				status.text = "<-"
				status.add_theme_color_override("font_color", L2_GREEN)
		else:
			_slots[i].add_theme_stylebox_override("panel", _make_slot_style("empty"))
			var status = _slots[i].get_node_or_null("StatusIcon")
			if status:
				status.text = ""


## Play a glow animation on a slot.
func _play_slot_glow(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: Panel = _slots[slot_index]
	var scene: Node = _find_scene_root()
	if scene == null:
		return
	var tw: Tween = scene.create_tween()
	tw.tween_property(slot, "modulate", Color(1.3, 1.4, 1.1, 1.0), 0.3)
	tw.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)


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


## Find the scene root for creating tweens.
func _find_scene_root() -> Node:
	var node: Node = self
	while node != null:
		if node is Node2D:
			return node
		node = node.get_parent()
	return get_tree().current_scene if get_tree() else null
