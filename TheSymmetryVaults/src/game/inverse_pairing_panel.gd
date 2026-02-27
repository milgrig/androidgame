## InversePairingPanel — UI panel for Layer 2 inverse key pairing.
##
## Displays:
##   - Title bar with progress counter
##   - Pair slots: each key + its inverse slot (matched or empty)
##   - Candidate keys pool at the bottom
##   - Visual feedback: green glow (correct), red flash (wrong)
##   - Self-inverse callout message
##
## Interaction:
##   - Tap a pair slot to select it (highlight)
##   - Tap a candidate key to attempt pairing
##   - On correct: green flash, pair locks, progress increments
##   - On wrong: red shake, feedback message
##
## Emits:
##   pair_attempted(key_sym_id, candidate_sym_id) — before validation
##   pair_result(success, key_sym_id, candidate_sym_id) — after validation
##   layer_completed() — all inverses found
class_name InversePairingPanel
extends Control

# ── Signals ──────────────────────────────────────────────────────────

signal pair_attempted(key_sym_id: String, candidate_sym_id: String)
signal pair_result(success: bool, key_sym_id: String, candidate_sym_id: String)
signal layer_completed()
signal key_selected(sym_id: String)
signal candidate_hovered(sym_id: String)

# ── Constants ────────────────────────────────────────────────────────

## Layer 2 green color scheme
const L2_GREEN := Color(0.2, 0.85, 0.4, 1.0)
const L2_GREEN_DIM := Color(0.15, 0.55, 0.3, 0.7)
const L2_GREEN_BG := Color(0.03, 0.08, 0.04, 0.9)
const L2_GREEN_BORDER := Color(0.15, 0.45, 0.25, 0.7)
const L2_GREEN_GLOW := Color(0.2, 1.0, 0.4, 0.6)

const PAIR_SLOT_HEIGHT := 36
const PAIR_SLOT_GAP := 4
const CANDIDATE_BTN_SIZE := Vector2(56, 28)
const CANDIDATE_GAP := 4

## Feedback colors
const COLOR_CORRECT := Color(0.2, 1.0, 0.4, 1.0)
const COLOR_WRONG := Color(1.0, 0.3, 0.25, 1.0)
const COLOR_SELF_INVERSE := Color(1.0, 0.85, 0.3, 1.0)

# ── State ────────────────────────────────────────────────────────────

var _inverse_mgr: InversePairManager = null
var _selected_pair_idx: int = -1  ## Currently selected pair slot
var _pair_slots: Array = []       ## Array of {panel, key_label, arrow_label, inv_label, pair}
var _candidate_btns: Dictionary = {}  ## sym_id -> Button
var _title_label: Label
var _progress_label: Label
var _instruction_label: Label
var _feedback_label: Label
var _scroll: ScrollContainer
var _slots_container: VBoxContainer
var _candidates_container: HFlowContainer
var _self_inverse_label: Label

# ── Public API ───────────────────────────────────────────────────────

## Setup the panel with an InversePairManager instance.
## rect: the Rect2 to position/size this panel within.
func setup(inverse_mgr: InversePairManager, rect: Rect2) -> void:
	_inverse_mgr = inverse_mgr
	position = rect.position
	size = rect.size
	custom_minimum_size = rect.size
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_ui()
	_populate_pairs()
	_populate_candidates()
	_update_progress()


## Refresh after external state change (e.g., loading save data).
func refresh() -> void:
	_populate_pairs()
	_populate_candidates()
	_update_progress()


# ── UI Construction ──────────────────────────────────────────────────

func _build_ui() -> void:
	# Background panel
	var bg := Panel.new()
	bg.name = "PanelBG"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = L2_GREEN_BG
	style.border_color = L2_GREEN_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 6)
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)

	var pad := 10
	var inner_w := size.x - pad * 2

	# Title label: "Обратные ключи"
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "Обратные ключи"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", L2_GREEN)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(pad, 8)
	_title_label.size = Vector2(inner_w, 22)
	add_child(_title_label)

	# Progress label: "0 / 3 пар найдено"
	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.text = "0 / 0"
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override("font_color", L2_GREEN_DIM)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.position = Vector2(pad, 30)
	_progress_label.size = Vector2(inner_w, 18)
	add_child(_progress_label)

	# Instruction label
	_instruction_label = Label.new()
	_instruction_label.name = "InstructionLabel"
	_instruction_label.text = "Выберите ключ, затем его обратный"
	_instruction_label.add_theme_font_size_override("font_size", 10)
	_instruction_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.55, 0.7))
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.position = Vector2(pad, 48)
	_instruction_label.size = Vector2(inner_w, 14)
	add_child(_instruction_label)

	# Divider 1
	var div1 := Panel.new()
	div1.position = Vector2(pad + 20, 65)
	div1.size = Vector2(inner_w - 40, 1)
	var div_style := StyleBoxFlat.new()
	div_style.bg_color = L2_GREEN_BORDER
	div1.add_theme_stylebox_override("panel", div_style)
	add_child(div1)

	# Pair slots area (scrollable)
	var slots_area_y := 70
	var candidates_area_h := 80  # Height reserved for candidates
	var feedback_area_h := 30
	var slots_area_h := size.y - slots_area_y - candidates_area_h - feedback_area_h - pad

	_scroll = ScrollContainer.new()
	_scroll.name = "PairScroll"
	_scroll.position = Vector2(pad, slots_area_y)
	_scroll.size = Vector2(inner_w, slots_area_h)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	_slots_container = VBoxContainer.new()
	_slots_container.name = "SlotsContainer"
	_slots_container.add_theme_constant_override("separation", PAIR_SLOT_GAP)
	_slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_slots_container)

	# Divider 2
	var div2_y := slots_area_y + slots_area_h + 4
	var div2 := Panel.new()
	div2.position = Vector2(pad + 10, div2_y)
	div2.size = Vector2(inner_w - 20, 1)
	div2.add_theme_stylebox_override("panel", div_style.duplicate())
	add_child(div2)

	# "Доступные ключи" label
	var cand_title := Label.new()
	cand_title.name = "CandidatesTitle"
	cand_title.text = "Доступные ключи"
	cand_title.add_theme_font_size_override("font_size", 10)
	cand_title.add_theme_color_override("font_color", L2_GREEN_DIM)
	cand_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cand_title.position = Vector2(pad, div2_y + 4)
	cand_title.size = Vector2(inner_w, 14)
	add_child(cand_title)

	# Candidates flow container
	_candidates_container = HFlowContainer.new()
	_candidates_container.name = "CandidatesFlow"
	_candidates_container.add_theme_constant_override("h_separation", CANDIDATE_GAP)
	_candidates_container.add_theme_constant_override("v_separation", CANDIDATE_GAP)
	_candidates_container.position = Vector2(pad, div2_y + 20)
	_candidates_container.size = Vector2(inner_w, candidates_area_h - 24)
	add_child(_candidates_container)

	# Feedback label (bottom)
	_feedback_label = Label.new()
	_feedback_label.name = "FeedbackLabel"
	_feedback_label.text = ""
	_feedback_label.add_theme_font_size_override("font_size", 11)
	_feedback_label.add_theme_color_override("font_color", Color(1, 1, 1, 0))
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.position = Vector2(pad, size.y - feedback_area_h - pad)
	_feedback_label.size = Vector2(inner_w, feedback_area_h)
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_feedback_label)

	# Self-inverse callout (hidden by default)
	_self_inverse_label = Label.new()
	_self_inverse_label.name = "SelfInverseLabel"
	_self_inverse_label.text = ""
	_self_inverse_label.add_theme_font_size_override("font_size", 11)
	_self_inverse_label.add_theme_color_override("font_color", Color(1, 1, 1, 0))
	_self_inverse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_self_inverse_label.position = Vector2(pad, size.y - feedback_area_h - pad - 18)
	_self_inverse_label.size = Vector2(inner_w, 18)
	add_child(_self_inverse_label)


# ── Pair Slots ───────────────────────────────────────────────────────

func _populate_pairs() -> void:
	# Clear existing slots
	for slot in _pair_slots:
		if slot["panel"] != null and is_instance_valid(slot["panel"]):
			slot["panel"].queue_free()
	_pair_slots.clear()

	if _inverse_mgr == null:
		return

	var pairs := _inverse_mgr.get_pairs()
	for i in range(pairs.size()):
		var pair = pairs[i]  # InversePairManager.InversePair (untyped to avoid class-load order issue)
		var slot := _create_pair_slot(i, pair)
		_pair_slots.append(slot)


func _create_pair_slot(idx: int, pair) -> Dictionary:  # pair: InversePair
	var slot_panel := Panel.new()
	slot_panel.name = "PairSlot_%d" % idx
	slot_panel.custom_minimum_size = Vector2(0, PAIR_SLOT_HEIGHT)
	slot_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Style depends on state
	_apply_slot_style(slot_panel, pair, false)

	# Inner HBoxContainer
	var hbox := HBoxContainer.new()
	hbox.name = "Content"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 6)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_child(hbox)

	# Key name (left side)
	var key_label := Label.new()
	key_label.name = "KeyLabel"
	key_label.text = _format_key_name(pair.key_sym_id, pair.key_name)
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.add_theme_color_override("font_color", L2_GREEN if not pair.is_identity else L2_GREEN_DIM)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(key_label)

	# Arrow
	var arrow_label := Label.new()
	arrow_label.name = "ArrowLabel"
	arrow_label.text = "↔"
	arrow_label.add_theme_font_size_override("font_size", 14)
	arrow_label.add_theme_color_override("font_color", L2_GREEN_DIM)
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_label.custom_minimum_size = Vector2(24, 0)
	arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(arrow_label)

	# Inverse name (right side) or placeholder
	var inv_label := Label.new()
	inv_label.name = "InvLabel"
	if pair.paired:
		inv_label.text = _format_key_name(pair.inverse_sym_id, pair.inverse_name)
		if pair.is_identity:
			inv_label.add_theme_color_override("font_color", L2_GREEN_DIM)
		else:
			inv_label.add_theme_color_override("font_color", COLOR_CORRECT)
	else:
		inv_label.text = "  ???  "
		inv_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.5, 0.5))
	inv_label.add_theme_font_size_override("font_size", 12)
	inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	inv_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(inv_label)

	# Status icon
	var status_label := Label.new()
	status_label.name = "StatusIcon"
	if pair.paired:
		status_label.text = "✓"
		status_label.add_theme_color_override("font_color", COLOR_CORRECT if not pair.is_identity else L2_GREEN_DIM)
	else:
		status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.custom_minimum_size = Vector2(20, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(status_label)

	_slots_container.add_child(slot_panel)

	# Click handler — select this pair
	if not pair.paired and not pair.is_identity:
		slot_panel.gui_input.connect(_on_pair_slot_input.bind(idx))

	return {
		"panel": slot_panel,
		"key_label": key_label,
		"arrow_label": arrow_label,
		"inv_label": inv_label,
		"status": status_label,
		"pair": pair,
	}


func _apply_slot_style(panel: Panel, pair, is_selected: bool) -> void:  # pair: InversePair
	var style := StyleBoxFlat.new()
	if pair.paired:
		# Completed pair — subtle green bg
		style.bg_color = Color(0.05, 0.15, 0.08, 0.6)
		style.border_color = Color(0.15, 0.4, 0.2, 0.5)
	elif is_selected:
		# Selected — bright green border, slightly brighter bg
		style.bg_color = Color(0.06, 0.15, 0.08, 0.8)
		style.border_color = L2_GREEN
	elif pair.is_identity:
		# Identity — dim
		style.bg_color = Color(0.04, 0.06, 0.04, 0.5)
		style.border_color = Color(0.12, 0.2, 0.14, 0.3)
	else:
		# Unmatched — default
		style.bg_color = Color(0.04, 0.08, 0.05, 0.6)
		style.border_color = L2_GREEN_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		style.set(prop, 1 if not is_selected else 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 4)
	panel.add_theme_stylebox_override("panel", style)


# ── Candidate Keys Pool ─────────────────────────────────────────────

func _populate_candidates() -> void:
	# Clear existing
	for child in _candidates_container.get_children():
		child.queue_free()
	_candidate_btns.clear()

	if _inverse_mgr == null:
		return

	var all_ids := _inverse_mgr.get_all_sym_ids()
	for sym_id in all_ids:
		var btn := _create_candidate_button(sym_id)
		_candidates_container.add_child(btn)
		_candidate_btns[sym_id] = btn


func _create_candidate_button(sym_id: String) -> Button:
	var btn := Button.new()
	btn.name = "Cand_%s" % sym_id
	btn.text = sym_id
	btn.custom_minimum_size = CANDIDATE_BTN_SIZE
	btn.add_theme_font_size_override("font_size", 11)
	btn.focus_mode = Control.FOCUS_NONE

	# Green-themed style
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.05, 0.12, 0.07, 0.7)
	normal_style.border_color = L2_GREEN_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		normal_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		normal_style.set(prop, 4)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.08, 0.2, 0.1, 0.8)
	hover_style.border_color = L2_GREEN
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.1, 0.25, 0.12, 0.9)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_color_override("font_color", L2_GREEN)
	btn.add_theme_color_override("font_hover_color", Color(0.3, 1.0, 0.5, 1.0))

	btn.pressed.connect(_on_candidate_pressed.bind(sym_id))
	btn.mouse_entered.connect(_on_candidate_hover.bind(sym_id))
	btn.mouse_exited.connect(_on_candidate_hover_end)

	return btn


# ── Interaction ──────────────────────────────────────────────────────

func _on_pair_slot_input(event: InputEvent, pair_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_pair(pair_idx)


func _select_pair(pair_idx: int) -> void:
	# Deselect previous
	if _selected_pair_idx >= 0 and _selected_pair_idx < _pair_slots.size():
		var prev := _pair_slots[_selected_pair_idx]
		_apply_slot_style(prev["panel"], prev["pair"], false)

	_selected_pair_idx = pair_idx

	# Highlight new selection
	if pair_idx >= 0 and pair_idx < _pair_slots.size():
		var slot := _pair_slots[pair_idx]
		_apply_slot_style(slot["panel"], slot["pair"], true)
		key_selected.emit(slot["pair"].key_sym_id)
		_instruction_label.text = "Теперь выберите обратный ключ ↓"


func _on_candidate_pressed(sym_id: String) -> void:
	if _selected_pair_idx < 0 or _selected_pair_idx >= _pair_slots.size():
		# No pair selected — auto-select first unpaired
		var auto_idx := _find_first_unpaired()
		if auto_idx >= 0:
			_select_pair(auto_idx)
		else:
			_show_feedback("Сначала выберите ключ слева", Color(0.8, 0.7, 0.3, 0.9))
			return

	var slot := _pair_slots[_selected_pair_idx]
	var pair = slot["pair"]  # InversePair

	if pair.paired:
		_show_feedback("Эта пара уже найдена", L2_GREEN_DIM)
		return

	# Attempt pairing
	pair_attempted.emit(pair.key_sym_id, sym_id)
	var result := _inverse_mgr.try_pair(pair.key_sym_id, sym_id)

	if result["success"]:
		_on_pair_correct(slot, pair, sym_id, result)
	else:
		_on_pair_wrong(slot, pair, sym_id, result)


func _on_candidate_hover(sym_id: String) -> void:
	candidate_hovered.emit(sym_id)


func _on_candidate_hover_end() -> void:
	candidate_hovered.emit("")


# ── Feedback ─────────────────────────────────────────────────────────

func _on_pair_correct(slot: Dictionary, pair,  # pair: InversePair
		candidate_id: String, result: Dictionary) -> void:
	# Update slot visual
	var inv_label: Label = slot["inv_label"]
	inv_label.text = _format_key_name(pair.inverse_sym_id, pair.inverse_name)
	inv_label.add_theme_color_override("font_color", COLOR_CORRECT)

	var status: Label = slot["status"]
	status.text = "✓"
	status.add_theme_color_override("font_color", COLOR_CORRECT)

	_apply_slot_style(slot["panel"], pair, false)

	# Green glow animation on the slot
	_animate_correct_glow(slot["panel"])

	# Self-inverse callout
	if result.get("is_self_inverse", false):
		_show_self_inverse_callout(pair.key_name)

	# Feedback message
	var inv_name := _inverse_mgr.get_name(candidate_id)
	_show_feedback("%s ∘ %s = e  ✓" % [pair.key_name, inv_name], COLOR_CORRECT)

	# Also update any bidirectionally-paired slots
	_refresh_all_slots()

	# Deselect
	_selected_pair_idx = -1

	# Auto-select next unpaired
	var next := _find_first_unpaired()
	if next >= 0:
		_select_pair(next)

	# Update progress
	_update_progress()

	# Emit
	pair_result.emit(true, pair.key_sym_id, candidate_id)

	# Check completion
	if _inverse_mgr.is_complete():
		_on_all_paired()


func _on_pair_wrong(slot: Dictionary, pair,  # pair: InversePair
		candidate_id: String, result: Dictionary) -> void:
	# Red shake animation
	_animate_wrong_shake(slot["panel"])

	# Feedback message showing what the composition actually is
	var result_name: String = result.get("result_name", "?")
	var cand_name := _inverse_mgr.get_name(candidate_id)
	_show_feedback("%s ∘ %s = %s — не тождество" % [pair.key_name, cand_name, result_name], COLOR_WRONG)

	# Emit
	pair_result.emit(false, pair.key_sym_id, candidate_id)


func _on_all_paired() -> void:
	_instruction_label.text = "Все обратные найдены!"
	_instruction_label.add_theme_color_override("font_color", COLOR_CORRECT)
	_show_feedback("Каждое действие можно отменить", COLOR_CORRECT)
	layer_completed.emit()


# ── Animations ───────────────────────────────────────────────────────

func _animate_correct_glow(panel: Panel) -> void:
	# Flash green glow
	var tw := create_tween()
	tw.tween_property(panel, "modulate", Color(0.5, 1.5, 0.5, 1.0), 0.15)
	tw.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)


func _animate_wrong_shake(panel: Panel) -> void:
	# Horizontal shake
	var original_pos := panel.position
	var tw := create_tween()
	tw.tween_property(panel, "position", original_pos + Vector2(8, 0), 0.05)
	tw.tween_property(panel, "position", original_pos + Vector2(-8, 0), 0.05)
	tw.tween_property(panel, "position", original_pos + Vector2(5, 0), 0.05)
	tw.tween_property(panel, "position", original_pos + Vector2(-5, 0), 0.05)
	tw.tween_property(panel, "position", original_pos, 0.05)

	# Flash red
	var tw2 := create_tween()
	tw2.tween_property(panel, "modulate", Color(1.5, 0.5, 0.5, 1.0), 0.1)
	tw2.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.3)


func _show_feedback(text: String, color: Color) -> void:
	_feedback_label.text = text
	var tw := create_tween()
	tw.tween_property(_feedback_label, "theme_override_colors/font_color", color, 0.2)
	tw.tween_interval(3.0)
	tw.tween_property(_feedback_label, "theme_override_colors/font_color", Color(color.r, color.g, color.b, 0.0), 1.0)


func _show_self_inverse_callout(key_name: String) -> void:
	_self_inverse_label.text = "↻ %s — сам себе обратный! (s ∘ s = e)" % key_name
	var tw := create_tween()
	tw.tween_property(_self_inverse_label, "theme_override_colors/font_color", COLOR_SELF_INVERSE, 0.3)
	tw.tween_interval(4.0)
	tw.tween_property(_self_inverse_label, "theme_override_colors/font_color", Color(1, 1, 1, 0), 1.5)


# ── Helpers ──────────────────────────────────────────────────────────

func _format_key_name(sym_id: String, name: String) -> String:
	if name.length() > 12:
		return sym_id
	return "%s" % name


func _update_progress() -> void:
	if _inverse_mgr == null:
		return
	var p := _inverse_mgr.get_progress()
	_progress_label.text = "%d / %d пар найдено" % [p["matched"], p["total"]]


func _find_first_unpaired() -> int:
	for i in range(_pair_slots.size()):
		var pair = _pair_slots[i]["pair"]  # InversePair
		if not pair.paired and not pair.is_identity:
			return i
	return -1


func _refresh_all_slots() -> void:
	## Refresh all slot visuals to reflect latest pair state.
	var pairs := _inverse_mgr.get_pairs()
	for i in range(mini(_pair_slots.size(), pairs.size())):
		var slot := _pair_slots[i]
		var pair = pairs[i]  # InversePair
		slot["pair"] = pair
		if pair.paired:
			slot["inv_label"].text = _format_key_name(pair.inverse_sym_id, pair.inverse_name)
			slot["inv_label"].add_theme_color_override("font_color", COLOR_CORRECT if not pair.is_identity else L2_GREEN_DIM)
			slot["status"].text = "✓"
			slot["status"].add_theme_color_override("font_color", COLOR_CORRECT if not pair.is_identity else L2_GREEN_DIM)
			_apply_slot_style(slot["panel"], pair, false)
