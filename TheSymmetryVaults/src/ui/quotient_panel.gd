class_name QuotientPanel
extends Control
## QuotientPanel -- Left-side panel for Layer 5 quotient group construction.
##
## Two-phase UI:
##   Phase 1 (SELECTION): Scrollable list of normal subgroups N.
##     - Non-constructed: "Собрать G/N" button -> starts assembly
##     - Constructed: coset legend + "СКЛЕИТЬ" button
##   Phase 2 (ASSEMBLY): Interactive coset slot-filling puzzle.
##     - |G/N| coset slots, slot 0 pre-filled with eN = N
##     - Player taps keys to fill slots; validation rejects wrong coset
##     - Full slot -> lock green, advance next
##     - All slots done -> assembly_completed signal
##
## Purple theme. Analogous to CrackingPanel for Layer 4.


# --- Signals ---

## Emitted when the player presses "Собрать G/N" to start assembly.
signal assembly_started(index: int)

## Emitted when all coset slots are correctly filled.
signal assembly_completed(index: int)

## Emitted when the player presses "Назад" during assembly.
signal back_to_selection()

## Emitted when the player chooses a quotient type answer in the quiz.
signal type_answer_submitted(index: int, proposed_type: String)

## Emitted when the player presses "СКЛЕИТЬ" to animate the coset merge.
signal merge_requested(index: int)

## Emitted when the player selects/taps a normal subgroup entry.
signal subgroup_selected(index: int)

## Emitted when all quotient groups have been constructed.
signal all_constructed()


# --- Constants (purple theme, matching Layer 5) ---

const L5_PURPLE := Color(0.65, 0.35, 0.90, 1.0)
const L5_PURPLE_DIM := Color(0.45, 0.25, 0.65, 0.7)
const L5_PURPLE_BG := Color(0.04, 0.02, 0.06, 0.8)
const L5_PURPLE_BORDER := Color(0.35, 0.15, 0.50, 0.7)
const L5_PURPLE_GLOW := Color(0.75, 0.45, 1.0, 0.9)
const L5_GREEN := Color(0.3, 0.9, 0.4, 0.9)
const L5_GREEN_DIM := Color(0.2, 0.7, 0.3, 0.7)
const L5_GOLD := Color(0.95, 0.80, 0.20, 0.9)

## Coset colors for map coloring (up to 12 distinct cosets)
const COSET_COLORS: Array = [
	Color(0.85, 0.45, 0.95, 0.9),   # purple-pink
	Color(0.40, 0.75, 1.00, 0.9),   # sky blue
	Color(0.95, 0.65, 0.25, 0.9),   # orange
	Color(0.40, 0.95, 0.55, 0.9),   # mint green
	Color(0.95, 0.45, 0.55, 0.9),   # coral
	Color(0.70, 0.85, 0.30, 0.9),   # lime
	Color(0.50, 0.55, 1.00, 0.9),   # lavender
	Color(0.95, 0.80, 0.30, 0.9),   # gold
	Color(0.35, 0.85, 0.85, 0.9),   # teal
	Color(0.90, 0.55, 0.70, 0.9),   # rose
	Color(0.60, 0.95, 0.80, 0.9),   # seafoam
	Color(0.80, 0.60, 0.40, 0.9),   # tan
]

## Entry heights
const ENTRY_HEIGHT_NORMAL := 120
const ENTRY_HEIGHT_EXPANDED := 260  ## After construction -- shows Cayley table

## Coset slot states
enum CosetSlotState { PREFILLED, EMPTY, FILLING, LOCKED }

## Panel phases
enum PanelPhase { SELECTION, ASSEMBLY, TYPE_QUIZ }


# --- State ---

var _room_state: RoomState = null
var _quotient_mgr = null  ## QuotientGroupManager instance
var _panel_rect: Rect2 = Rect2()

## Quotient entry nodes (one per normal subgroup, in SELECTION phase)
var _entries: Array = []  # Array[Panel]

## Currently selected subgroup index (-1 = none)
var _selected_index: int = -1

## Scroll + list containers
var _scroll: ScrollContainer = null
var _entry_list: VBoxContainer = null

## Progress label
var _progress_label: Label = null

## Current UI phase
var _current_phase: int = PanelPhase.SELECTION

## Assembly state (Phase 2)
var _assembly_sg_idx: int = -1         ## Which subgroup is being assembled
var _coset_slot_nodes: Array = []      ## Array[Panel] -- coset slot visual nodes
var _coset_slot_states: Array = []     ## Array[CosetSlotState]
var _assembly_info: Dictionary = {}    ## { num_cosets, coset_size, prefilled_elements }

## Type quiz state (Phase 3)
var _quiz_sg_idx: int = -1             ## Which subgroup is being quizzed
var _quiz_option_buttons: Array = []   ## Array[Button] -- answer option buttons
var _quiz_result: Dictionary = {}      ## { quotient_order, cosets, ... } for display


# --- Setup ---

## Build the quotient panel inside the given parent.
func setup(parent: Node, panel_rect: Rect2, room_state: RoomState,
		quotient_mgr) -> void:
	_panel_rect = panel_rect
	_room_state = room_state
	_quotient_mgr = quotient_mgr

	position = panel_rect.position
	size = panel_rect.size
	name = "QuotientPanel"

	# Build frame
	var frame: Panel = Panel.new()
	frame.name = "QuotientFrame"
	frame.position = Vector2.ZERO
	frame.size = panel_rect.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = L5_PURPLE_BG
	style.border_color = L5_PURPLE_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 8)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	# Frame title
	var title: Label = Label.new()
	title.name = "QuotientFrameTitle"
	title.text = "Факторгруппы G/N"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", L5_PURPLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(4, 5)
	title.size = Vector2(panel_rect.size.x - 8, 18)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# Progress label at the bottom
	_progress_label = Label.new()
	_progress_label.name = "QuotientProgress"
	_progress_label.add_theme_font_size_override("font_size", 10)
	_progress_label.add_theme_color_override("font_color", L5_PURPLE_DIM)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.position = Vector2(4, panel_rect.size.y - 18)
	_progress_label.size = Vector2(panel_rect.size.x - 8, 14)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_label)

	# Scrollable content area (between title and progress)
	var content_y: float = 26.0
	var content_h: float = panel_rect.size.y - content_y - 22.0

	_scroll = ScrollContainer.new()
	_scroll.name = "QuotientScroll"
	_scroll.position = Vector2(4, content_y)
	_scroll.size = Vector2(panel_rect.size.x - 8, content_h)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	_entry_list = VBoxContainer.new()
	_entry_list.name = "QuotientVBox"
	_entry_list.add_theme_constant_override("separation", 4)
	_entry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_entry_list)

	# Populate entries
	_populate_entries()

	# Initial progress
	update_progress()


# ========================================================================
# Phase 1: SELECTION -- list of normal subgroups
# ========================================================================

func _populate_entries() -> void:
	if _entry_list == null or _quotient_mgr == null:
		return

	# Clear existing
	for child in _entry_list.get_children():
		child.queue_free()
	_entries.clear()

	var normal_subgroups: Array = _quotient_mgr.get_normal_subgroups()

	if normal_subgroups.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "Нет нормальных подгрупп\nдля факторизации"
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", L5_PURPLE_DIM)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_entry_list.add_child(empty_label)
		return

	var inner_w: float = _panel_rect.size.x - 16

	for i in range(normal_subgroups.size()):
		var ns: Dictionary = normal_subgroups[i]
		var is_constructed: bool = _quotient_mgr.is_constructed(i)
		var entry: Panel = _build_entry(i, ns, inner_w, is_constructed)
		_entry_list.add_child(entry)
		_entries.append(entry)


## Build a single quotient group entry.
func _build_entry(index: int, ns_data: Dictionary, width: float,
		is_constructed: bool) -> Panel:
	var entry_h: int = ENTRY_HEIGHT_EXPANDED if is_constructed else ENTRY_HEIGHT_NORMAL

	var entry: Panel = Panel.new()
	entry.name = "QuotientEntry_%d" % index
	entry.custom_minimum_size = Vector2(width, entry_h)
	entry.mouse_filter = Control.MOUSE_FILTER_STOP

	# Entry style
	var entry_style: StyleBoxFlat = StyleBoxFlat.new()
	if is_constructed:
		entry_style.bg_color = Color(0.03, 0.06, 0.04, 0.7)
		entry_style.border_color = Color(0.2, 0.6, 0.3, 0.6)
	elif _selected_index == index:
		entry_style.bg_color = Color(0.08, 0.04, 0.10, 0.9)
		entry_style.border_color = L5_PURPLE_GLOW
	else:
		entry_style.bg_color = Color(0.06, 0.03, 0.08, 0.6)
		entry_style.border_color = L5_PURPLE_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		entry_style.set(prop, 1 if not (_selected_index == index) else 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		entry_style.set(prop, 6)
	entry.add_theme_stylebox_override("panel", entry_style)

	# --- Row 1: Normal subgroup label N = {e, r1, ...} ---
	var ns_elements: Array = ns_data.get("normal_subgroup_elements", [])
	var ns_names: Array = []
	for sid in ns_elements:
		ns_names.append(_quotient_mgr.get_name(sid))

	var ns_label: Label = Label.new()
	ns_label.name = "NSLabel"
	var ns_text: String = ", ".join(ns_names)
	if ns_text.length() > 30:
		ns_text = ns_text.left(27) + "\u2026"
	ns_label.text = "N = {%s}" % ns_text
	ns_label.add_theme_font_size_override("font_size", 10)
	ns_label.add_theme_color_override("font_color", L5_PURPLE)
	ns_label.position = Vector2(6, 4)
	ns_label.size = Vector2(width - 12, 14)
	ns_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(ns_label)

	# --- Row 2: Quotient info |G/N| = X (type hidden until identified) ---
	var q_order: int = ns_data.get("quotient_order", 0)
	var q_type: String = ns_data.get("quotient_type", "?")
	var info_label: Label = Label.new()
	info_label.name = "InfoLabel"
	if is_constructed:
		info_label.text = "|G/N| = %d  (%s)" % [q_order, q_type]
	else:
		info_label.text = "|G/N| = %d  (тип: ?)" % q_order
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", L5_PURPLE_DIM)
	info_label.position = Vector2(6, 20)
	info_label.size = Vector2(width - 12, 14)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(info_label)

	# --- Row 3: Colored key dots showing N elements ---
	var dots: HFlowContainer = HFlowContainer.new()
	dots.name = "KeyDots"
	dots.position = Vector2(4, 36)
	dots.size = Vector2(width - 8, 18)
	dots.add_theme_constant_override("h_separation", 2)
	dots.add_theme_constant_override("v_separation", 1)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(dots)

	for sid in ns_elements:
		var room_idx: int = _sym_id_to_room_idx(sid)
		if room_idx == 0:
			continue  # T111: identity key never shown
		var color: Color = _get_key_color(sid)
		_build_key_dot(dots, sid, room_idx, color)

	# --- Row 4: Status + buttons ---
	var status_label: Label = Label.new()
	status_label.name = "StatusLabel"
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.position = Vector2(6, 56)
	status_label.size = Vector2(width - 12, 14)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(status_label)

	if is_constructed:
		status_label.text = "\u2713 Построена"
		status_label.add_theme_color_override("font_color", L5_GREEN)
	else:
		status_label.text = "Нажмите для сборки"
		status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.9, 0.7))

	# --- Construct / Merge buttons ---
	if is_constructed:
		# "СКЛЕИТЬ" button
		var merge_btn: Button = _build_action_button(
			"MergeBtn_%d" % index, "СКЛЕИТЬ", width, 74, L5_PURPLE, true)
		merge_btn.pressed.connect(_on_merge_pressed.bind(index))
		entry.add_child(merge_btn)

		# --- Coset color legend ---
		var legend_y: float = 100.0
		var construction: Dictionary = _quotient_mgr.get_construction(index)
		var cosets: Array = construction.get("cosets", [])
		if not cosets.is_empty():
			_build_coset_legend(entry, index, cosets, construction, width, legend_y)
	# (No "Собрать G/N" button — clicking the entry itself auto-starts assembly
	#  via subgroup_selected signal, handled by LayerModeController.)

	# Click handler for entry selection
	entry.gui_input.connect(_on_entry_clicked.bind(index))

	return entry


## Build the coset legend + mini-Cayley table for a constructed entry.
func _build_coset_legend(entry: Panel, index: int, cosets: Array,
		construction: Dictionary, width: float, legend_y: float) -> void:
	var legend_label: Label = Label.new()
	legend_label.name = "CosetLegendTitle"
	legend_label.text = "Смежные классы gN:"
	legend_label.add_theme_font_size_override("font_size", 9)
	legend_label.add_theme_color_override("font_color", L5_PURPLE_DIM)
	legend_label.position = Vector2(6, legend_y)
	legend_label.size = Vector2(width - 12, 12)
	legend_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(legend_label)
	legend_y += 14

	for ci in range(cosets.size()):
		var coset: Dictionary = cosets[ci]
		var rep: String = coset.get("representative", "")
		var elements: Array = coset.get("elements", [])
		var coset_color: Color = COSET_COLORS[ci % COSET_COLORS.size()]

		var coset_row: HBoxContainer = HBoxContainer.new()
		coset_row.name = "CosetRow_%d" % ci
		coset_row.position = Vector2(6, legend_y)
		coset_row.size = Vector2(width - 12, 12)
		coset_row.add_theme_constant_override("separation", 3)
		coset_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(coset_row)

		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(8, 8)
		swatch.color = coset_color
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coset_row.add_child(swatch)

		var rep_name: String = _quotient_mgr.get_name(rep)
		var elem_names: Array = []
		for e_sid in elements:
			elem_names.append(_quotient_mgr.get_name(e_sid))
		var coset_text: String = "%sN = {%s}" % [rep_name, ", ".join(elem_names)]
		if coset_text.length() > 35:
			coset_text = coset_text.left(32) + "\u2026}"

		var coset_lbl: Label = Label.new()
		coset_lbl.text = coset_text
		coset_lbl.add_theme_font_size_override("font_size", 8)
		coset_lbl.add_theme_color_override("font_color",
			Color(coset_color.r, coset_color.g, coset_color.b, 0.85))
		coset_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coset_row.add_child(coset_lbl)

		legend_y += 13

	# Mini-Cayley table
	legend_y += 4
	var table: Dictionary = construction.get("table", {})
	if not table.is_empty():
		_build_mini_cayley_table(entry, index, cosets, table, width, legend_y)


# ========================================================================
# Phase 2: ASSEMBLY -- interactive coset slot filling
# ========================================================================

## Switch panel to assembly mode for a given subgroup.
func enter_assembly_mode(sg_index: int, assembly_info: Dictionary) -> void:
	_current_phase = PanelPhase.ASSEMBLY
	_assembly_sg_idx = sg_index
	_assembly_info = assembly_info
	_coset_slot_nodes.clear()
	_coset_slot_states.clear()

	# Clear existing entry list
	if _entry_list:
		for child in _entry_list.get_children():
			child.queue_free()
	_entries.clear()

	_build_assembly_view()


## Build the assembly view with coset slots.
func _build_assembly_view() -> void:
	if _entry_list == null or _quotient_mgr == null:
		return

	var inner_w: float = _panel_rect.size.x - 16
	var num_cosets: int = _assembly_info.get("num_cosets", 0)
	var coset_size: int = _assembly_info.get("coset_size", 0)
	var prefilled: Array = _assembly_info.get("prefilled_elements", [])

	# --- "< Назад" button ---
	var back_btn: Button = Button.new()
	back_btn.name = "BackBtn"
	back_btn.text = "< Назад"
	back_btn.add_theme_font_size_override("font_size", 10)
	back_btn.custom_minimum_size = Vector2(inner_w, 24)
	back_btn.focus_mode = Control.FOCUS_NONE
	var back_style: StyleBoxFlat = StyleBoxFlat.new()
	back_style.bg_color = Color(0.06, 0.03, 0.08, 0.5)
	back_style.border_color = L5_PURPLE_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		back_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		back_style.set(prop, 4)
	back_btn.add_theme_stylebox_override("normal", back_style)
	back_btn.add_theme_color_override("font_color", L5_PURPLE_DIM)
	back_btn.pressed.connect(_on_back_pressed)
	_entry_list.add_child(back_btn)

	# --- Header: N info + instructions ---
	var ns_data: Array = _quotient_mgr.get_normal_subgroups()
	if _assembly_sg_idx >= 0 and _assembly_sg_idx < ns_data.size():
		var ns: Dictionary = ns_data[_assembly_sg_idx]
		var ns_elements: Array = ns.get("normal_subgroup_elements", [])
		var ns_names: Array = []
		for sid in ns_elements:
			ns_names.append(_quotient_mgr.get_name(sid))
		var ns_str: String = ", ".join(ns_names)
		if ns_str.length() > 30:
			ns_str = ns_str.left(27) + "\u2026"

		var header: Label = Label.new()
		header.name = "AssemblyHeader"
		header.text = "N = {%s}\nРазбей G на %d классов по %d эл." % [
			ns_str, num_cosets, coset_size]
		header.add_theme_font_size_override("font_size", 10)
		header.add_theme_color_override("font_color", L5_PURPLE)
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.custom_minimum_size = Vector2(inner_w, 30)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_entry_list.add_child(header)

	# --- Hint: "Нажми ⊕ на ключе" ---
	var hint: Label = Label.new()
	hint.name = "AssemblyHint"
	hint.text = "Нажми \u2295 на ключе, чтобы добавить"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.7, 0.5, 0.8, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(inner_w, 14)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_list.add_child(hint)

	# --- Coset slots ---
	var slot_h: int = _get_coset_slot_height(num_cosets, coset_size)

	for i in range(num_cosets):
		var initial_state: int
		if i == 0:
			initial_state = CosetSlotState.PREFILLED
		elif i == 1:
			initial_state = CosetSlotState.FILLING
		else:
			initial_state = CosetSlotState.EMPTY

		var slot: Panel = _build_coset_slot(i, inner_w, slot_h, initial_state, coset_size)
		_entry_list.add_child(slot)
		_coset_slot_nodes.append(slot)
		_coset_slot_states.append(initial_state)

	# Pre-fill slot 0 with N elements
	for sid in prefilled:
		_add_dot_to_coset_slot(0, sid)
	_update_coset_count(0)

	# Update progress
	_update_assembly_progress()


## Build a single coset slot panel.
func _build_coset_slot(index: int, width: float, height: int,
		state: int, coset_size: int) -> Panel:
	var slot: Panel = Panel.new()
	slot.name = "CosetSlot_%d" % index
	slot.custom_minimum_size = Vector2(width - 4, height)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	slot.add_theme_stylebox_override("panel", _make_coset_slot_style(state, index))

	# Slot label: "Класс #N" or "eN = N" for slot 0
	var lbl: Label = Label.new()
	lbl.name = "SlotLabel"
	if index == 0:
		lbl.text = "eN = N (авто)"
	else:
		lbl.text = "Класс #%d" % (index + 1)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color",
		COSET_COLORS[index % COSET_COLORS.size()] if state != CosetSlotState.EMPTY else L5_PURPLE_DIM)
	lbl.position = Vector2(6, 2)
	lbl.size = Vector2(width - 54, 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)

	# Status icon (right side)
	var status: Label = Label.new()
	status.name = "StatusIcon"
	status.add_theme_font_size_override("font_size", 12)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.position = Vector2(width - 50, 2)
	status.size = Vector2(40, 16)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(status)
	_apply_coset_status_icon(status, state)

	# Key dots container
	var dots: HFlowContainer = HFlowContainer.new()
	dots.name = "KeyDots"
	dots.position = Vector2(6, 18)
	dots.size = Vector2(width - 16, height - 34)
	dots.add_theme_constant_override("h_separation", 3)
	dots.add_theme_constant_override("v_separation", 2)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(dots)

	# Element count label
	var count_lbl: Label = Label.new()
	count_lbl.name = "KeyCount"
	count_lbl.text = "0 / %d" % coset_size
	count_lbl.add_theme_font_size_override("font_size", 9)
	count_lbl.add_theme_color_override("font_color", L5_PURPLE_DIM)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_lbl.position = Vector2(width - 80, height - 16)
	count_lbl.size = Vector2(68, 14)
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(count_lbl)

	return slot


## Add a dot to a coset slot after successful validation.
func add_element_to_slot(slot_idx: int, sym_id: String) -> void:
	if slot_idx < 0 or slot_idx >= _coset_slot_nodes.size():
		return
	_add_dot_to_coset_slot(slot_idx, sym_id)
	_update_coset_count(slot_idx)


## Lock a coset slot (all elements filled).
func lock_coset_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _coset_slot_nodes.size():
		return
	_coset_slot_states[slot_idx] = CosetSlotState.LOCKED
	_update_coset_slot_visual(slot_idx, CosetSlotState.LOCKED)

	# Activate next slot
	var next: int = slot_idx + 1
	if next < _coset_slot_nodes.size() and _coset_slot_states[next] == CosetSlotState.EMPTY:
		_coset_slot_states[next] = CosetSlotState.FILLING
		_update_coset_slot_visual(next, CosetSlotState.FILLING)

	# Play glow animation
	_play_coset_glow(slot_idx)
	_update_assembly_progress()


## Show red flash rejection on the active slot.
func show_rejection_flash(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _coset_slot_nodes.size():
		return
	var slot: Panel = _coset_slot_nodes[slot_idx]
	if slot == null or not is_instance_valid(slot):
		return
	var flash_style: StyleBoxFlat = _make_coset_slot_style(CosetSlotState.FILLING, slot_idx)
	flash_style.border_color = Color(1.0, 0.3, 0.2, 0.9)
	flash_style.bg_color = Color(0.15, 0.03, 0.03, 0.7)
	slot.add_theme_stylebox_override("panel", flash_style)

	var scene_root: Node = _find_scene_root()
	if scene_root:
		var tw: Tween = scene_root.create_tween()
		tw.tween_interval(0.4)
		tw.tween_callback(_update_coset_slot_visual.bind(slot_idx, CosetSlotState.FILLING))


## Show duplicate flash (orange) on the active slot.
func show_duplicate_flash(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _coset_slot_nodes.size():
		return
	var slot: Panel = _coset_slot_nodes[slot_idx]
	if slot == null or not is_instance_valid(slot):
		return
	var flash_style: StyleBoxFlat = _make_coset_slot_style(CosetSlotState.FILLING, slot_idx)
	flash_style.border_color = Color(1.0, 0.6, 0.2, 0.9)
	flash_style.bg_color = Color(0.12, 0.08, 0.03, 0.7)
	slot.add_theme_stylebox_override("panel", flash_style)

	var scene_root: Node = _find_scene_root()
	if scene_root:
		var tw: Tween = scene_root.create_tween()
		tw.tween_interval(0.5)
		tw.tween_callback(_update_coset_slot_visual.bind(slot_idx, CosetSlotState.FILLING))


## Return to selection phase.
func exit_assembly_mode() -> void:
	_current_phase = PanelPhase.SELECTION
	_assembly_sg_idx = -1
	_coset_slot_nodes.clear()
	_coset_slot_states.clear()
	_assembly_info.clear()
	_populate_entries()
	update_progress()


## Check if panel is in assembly mode.
func is_in_assembly_mode() -> bool:
	return _current_phase == PanelPhase.ASSEMBLY


## Check if panel is in type quiz mode.
func is_in_type_quiz_mode() -> bool:
	return _current_phase == PanelPhase.TYPE_QUIZ


## Get the assembly subgroup index.
func get_assembly_sg_index() -> int:
	return _assembly_sg_idx


## Get the quiz subgroup index.
func get_quiz_sg_index() -> int:
	return _quiz_sg_idx


# ========================================================================
# Phase 3: TYPE_QUIZ -- player identifies the quotient group type
# ========================================================================

## Switch panel to type quiz mode after cosets are assembled.
## cosets_info: { quotient_order: int, cosets: Array, ... }
## options: Array[String] of type options (shuffled, includes correct answer)
func enter_type_quiz_mode(sg_index: int, cosets_info: Dictionary,
		options: Array) -> void:
	_current_phase = PanelPhase.TYPE_QUIZ
	_quiz_sg_idx = sg_index
	_quiz_option_buttons.clear()
	_quiz_result = cosets_info

	# Clear existing entry list
	if _entry_list:
		for child in _entry_list.get_children():
			child.queue_free()
	_entries.clear()
	_coset_slot_nodes.clear()
	_coset_slot_states.clear()

	_build_type_quiz_view(options)


## Build the type quiz view.
func _build_type_quiz_view(options: Array) -> void:
	if _entry_list == null or _quotient_mgr == null:
		return

	var inner_w: float = _panel_rect.size.x - 16
	var q_order: int = _quiz_result.get("quotient_order", 0)
	var cosets: Array = _quiz_result.get("cosets", [])

	# --- Coset summary header ---
	var header: Label = Label.new()
	header.name = "QuizHeader"
	header.text = "Классы смежности собраны!"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", L5_GREEN)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.custom_minimum_size = Vector2(inner_w, 20)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_list.add_child(header)

	# --- Mini coset legend ---
	var legend: Label = Label.new()
	legend.name = "QuizLegend"
	legend.text = "G/N: %d классов (порядок %d)" % [cosets.size(), q_order]
	legend.add_theme_font_size_override("font_size", 10)
	legend.add_theme_color_override("font_color", L5_PURPLE)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.custom_minimum_size = Vector2(inner_w, 16)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_list.add_child(legend)

	# --- Coset color swatches ---
	var swatch_row: HFlowContainer = HFlowContainer.new()
	swatch_row.name = "CosetSwatches"
	swatch_row.custom_minimum_size = Vector2(inner_w, 18)
	swatch_row.add_theme_constant_override("h_separation", 3)
	swatch_row.add_theme_constant_override("v_separation", 2)
	swatch_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_list.add_child(swatch_row)

	for ci in range(cosets.size()):
		var coset: Dictionary = cosets[ci]
		var rep: String = coset.get("representative", "")
		var rep_name: String = _quotient_mgr.get_name(rep) if _quotient_mgr else rep
		var coset_color: Color = COSET_COLORS[ci % COSET_COLORS.size()]

		var swatch_box: HBoxContainer = HBoxContainer.new()
		swatch_box.add_theme_constant_override("separation", 2)
		swatch_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(8, 8)
		swatch.color = coset_color
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch_box.add_child(swatch)

		var s_lbl: Label = Label.new()
		s_lbl.text = rep_name
		s_lbl.add_theme_font_size_override("font_size", 8)
		s_lbl.add_theme_color_override("font_color",
			Color(coset_color.r, coset_color.g, coset_color.b, 0.85))
		s_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch_box.add_child(s_lbl)

		swatch_row.add_child(swatch_box)

	# --- Spacer ---
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(inner_w, 8)
	_entry_list.add_child(spacer)

	# --- Question ---
	var question: Label = Label.new()
	question.name = "QuizQuestion"
	question.text = "Какая это группа?"
	question.add_theme_font_size_override("font_size", 14)
	question.add_theme_color_override("font_color", L5_GOLD)
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.custom_minimum_size = Vector2(inner_w, 24)
	question.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_list.add_child(question)

	# --- Answer option buttons ---
	for i in range(options.size()):
		var option_text: String = options[i]
		var btn: Button = _build_quiz_option_button(option_text, inner_w, i)
		_entry_list.add_child(btn)
		_quiz_option_buttons.append(btn)

	# --- Hint ---
	var hint: Label = Label.new()
	hint.name = "QuizHint"
	hint.text = "Подсказка: порядок = %d" % q_order
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.6, 0.4, 0.7, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(inner_w, 14)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_list.add_child(hint)

	# Update progress
	if _progress_label:
		_progress_label.text = "Определи тип G/N"
		_progress_label.add_theme_color_override("font_color", L5_GOLD)


## Build a single quiz option button.
func _build_quiz_option_button(option_text: String, width: float,
		index: int) -> Button:
	var btn: Button = Button.new()
	btn.name = "QuizOption_%d" % index
	btn.text = option_text
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(width - 8, 36)
	btn.focus_mode = Control.FOCUS_NONE

	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.06, 0.04, 0.10, 0.85)
	btn_style.border_color = L5_PURPLE
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		btn_style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		btn_style.set(prop, 8)
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover: StyleBoxFlat = btn_style.duplicate()
	btn_hover.bg_color = Color(0.10, 0.06, 0.16, 0.95)
	btn_hover.border_color = L5_PURPLE_GLOW
	btn.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed: StyleBoxFlat = btn_style.duplicate()
	btn_pressed.bg_color = Color(0.14, 0.08, 0.20, 1.0)
	btn.add_theme_stylebox_override("pressed", btn_pressed)

	btn.add_theme_color_override("font_color", L5_PURPLE_GLOW)

	btn.pressed.connect(_on_quiz_option_pressed.bind(option_text))

	return btn


## Handle quiz option button press.
func _on_quiz_option_pressed(proposed_type: String) -> void:
	type_answer_submitted.emit(_quiz_sg_idx, proposed_type)


## Show correct answer feedback on the quiz (green flash + disable buttons).
func show_quiz_correct(correct_type: String) -> void:
	# Flash all buttons: highlight correct one green, disable all
	for btn in _quiz_option_buttons:
		if btn == null or not is_instance_valid(btn):
			continue
		btn.disabled = true
		if btn.text == correct_type:
			var correct_style: StyleBoxFlat = StyleBoxFlat.new()
			correct_style.bg_color = Color(0.05, 0.12, 0.06, 0.9)
			correct_style.border_color = L5_GREEN
			for prop in ["border_width_left", "border_width_right",
						"border_width_top", "border_width_bottom"]:
				correct_style.set(prop, 3)
			for prop in ["corner_radius_top_left", "corner_radius_top_right",
						"corner_radius_bottom_left", "corner_radius_bottom_right"]:
				correct_style.set(prop, 8)
			btn.add_theme_stylebox_override("normal", correct_style)
			btn.add_theme_stylebox_override("disabled", correct_style)
			btn.add_theme_color_override("font_color", L5_GREEN)
			btn.add_theme_color_override("font_color_disabled", L5_GREEN)
			btn.text = "\u2713 " + correct_type
		else:
			btn.add_theme_color_override("font_color_disabled",
				Color(0.4, 0.3, 0.5, 0.4))

	# Update question label
	var q_lbl = _entry_list.get_node_or_null("QuizQuestion") if _entry_list else null
	if q_lbl:
		q_lbl.text = "G/N \u2245 %s" % correct_type
		q_lbl.add_theme_color_override("font_color", L5_GREEN)

	if _progress_label:
		_progress_label.text = "Тип определён!"
		_progress_label.add_theme_color_override("font_color", L5_GREEN)

	# Glow animation on correct button
	var scene_root: Node = _find_scene_root()
	if scene_root:
		for btn in _quiz_option_buttons:
			if btn != null and is_instance_valid(btn) and btn.text.begins_with("\u2713"):
				var tw: Tween = scene_root.create_tween()
				tw.tween_property(btn, "modulate", Color(1.3, 1.5, 1.3, 1.0), 0.3)
				tw.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)
				break


## Show wrong answer feedback on the quiz (red flash on the wrong button).
func show_quiz_wrong(proposed_type: String) -> void:
	for btn in _quiz_option_buttons:
		if btn == null or not is_instance_valid(btn):
			continue
		if btn.text == proposed_type:
			# Red flash
			var wrong_style: StyleBoxFlat = StyleBoxFlat.new()
			wrong_style.bg_color = Color(0.15, 0.03, 0.03, 0.85)
			wrong_style.border_color = Color(1.0, 0.3, 0.2, 0.9)
			for prop in ["border_width_left", "border_width_right",
						"border_width_top", "border_width_bottom"]:
				wrong_style.set(prop, 2)
			for prop in ["corner_radius_top_left", "corner_radius_top_right",
						"corner_radius_bottom_left", "corner_radius_bottom_right"]:
				wrong_style.set(prop, 8)
			btn.add_theme_stylebox_override("normal", wrong_style)
			btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 0.9))

			# Tween restore after delay
			var scene_root: Node = _find_scene_root()
			if scene_root:
				var original_style: StyleBoxFlat = StyleBoxFlat.new()
				original_style.bg_color = Color(0.06, 0.04, 0.10, 0.85)
				original_style.border_color = L5_PURPLE
				for prop in ["border_width_left", "border_width_right",
							"border_width_top", "border_width_bottom"]:
					original_style.set(prop, 2)
				for prop in ["corner_radius_top_left", "corner_radius_top_right",
							"corner_radius_bottom_left", "corner_radius_bottom_right"]:
					original_style.set(prop, 8)
				var tw: Tween = scene_root.create_tween()
				tw.tween_interval(0.5)
				tw.tween_callback(btn.add_theme_stylebox_override.bind("normal", original_style))
				tw.tween_callback(btn.add_theme_color_override.bind("font_color", L5_PURPLE_GLOW))
			break

	# Update question label with "try again" hint
	var q_lbl = _entry_list.get_node_or_null("QuizQuestion") if _entry_list else null
	if q_lbl:
		q_lbl.text = "Неверно! Попробуй ещё"
		q_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 0.9))

		var scene_root: Node = _find_scene_root()
		if scene_root:
			var tw: Tween = scene_root.create_tween()
			tw.tween_interval(1.5)
			tw.tween_callback(func():
				if q_lbl and is_instance_valid(q_lbl):
					q_lbl.text = "Какая это группа?"
					q_lbl.add_theme_color_override("font_color", L5_GOLD)
			)


## Exit type quiz mode and return to selection.
func exit_type_quiz_mode() -> void:
	_current_phase = PanelPhase.SELECTION
	_quiz_sg_idx = -1
	_quiz_option_buttons.clear()
	_quiz_result.clear()
	_populate_entries()
	update_progress()


## Restore assembly from saved state (for save/restore).
func refresh_assembly_from_state(sg_idx: int, assembly_state: Dictionary) -> void:
	var slots: Array = assembly_state.get("coset_slots", [])
	var active_idx: int = assembly_state.get("active_coset_idx", 0)
	var coset_size: int = _assembly_info.get("coset_size", 1)

	for i in range(mini(slots.size(), _coset_slot_nodes.size())):
		var slot_elements: Array = slots[i]
		for sid in slot_elements:
			if i > 0 or not _assembly_info.get("prefilled_elements", []).has(sid):
				_add_dot_to_coset_slot(i, sid)

		_update_coset_count(i)

		if i == 0:
			_coset_slot_states[i] = CosetSlotState.PREFILLED
			_update_coset_slot_visual(i, CosetSlotState.PREFILLED)
		elif slot_elements.size() >= coset_size:
			_coset_slot_states[i] = CosetSlotState.LOCKED
			_update_coset_slot_visual(i, CosetSlotState.LOCKED)
		elif i == active_idx:
			_coset_slot_states[i] = CosetSlotState.FILLING
			_update_coset_slot_visual(i, CosetSlotState.FILLING)

	_update_assembly_progress()


# --- Assembly helpers ---

func _add_dot_to_coset_slot(slot_idx: int, sym_id: String) -> void:
	if slot_idx < 0 or slot_idx >= _coset_slot_nodes.size():
		return
	var slot: Panel = _coset_slot_nodes[slot_idx]
	if slot == null or not is_instance_valid(slot):
		return
	var dots = slot.get_node_or_null("KeyDots")
	if dots == null:
		return

	var room_idx: int = _sym_id_to_room_idx(sym_id)
	var color: Color = _get_key_color(sym_id)
	var coset_color: Color = COSET_COLORS[slot_idx % COSET_COLORS.size()]

	# Use coset color for the dot background tint, key color for the dot itself
	var dot_btn: Button = Button.new()
	dot_btn.name = "Dot_%s" % sym_id
	dot_btn.custom_minimum_size = Vector2(22, 14)
	dot_btn.flat = true
	dot_btn.focus_mode = Control.FOCUS_NONE
	dot_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 1)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_btn.add_child(hbox)

	var dot_rect: ColorRect = ColorRect.new()
	dot_rect.custom_minimum_size = Vector2(5, 5)
	dot_rect.size = Vector2(5, 5)
	dot_rect.color = color
	dot_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot_rect)

	var dot_lbl: Label = Label.new()
	dot_lbl.text = str(room_idx) if room_idx > 0 else "e"
	dot_lbl.add_theme_font_size_override("font_size", 7)
	dot_lbl.add_theme_color_override("font_color", color)
	dot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot_lbl)

	var dot_style: StyleBoxFlat = StyleBoxFlat.new()
	dot_style.bg_color = Color(coset_color.r, coset_color.g, coset_color.b, 0.08)
	dot_style.border_color = Color(coset_color.r, coset_color.g, coset_color.b, 0.3)
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		dot_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		dot_style.set(prop, 2)
	dot_btn.add_theme_stylebox_override("normal", dot_style)
	dots.add_child(dot_btn)


func _update_coset_count(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _coset_slot_nodes.size():
		return
	var slot: Panel = _coset_slot_nodes[slot_idx]
	if slot == null or not is_instance_valid(slot):
		return
	var count_lbl = slot.get_node_or_null("KeyCount")
	var dots = slot.get_node_or_null("KeyDots")
	if count_lbl == null or dots == null:
		return
	var coset_size: int = _assembly_info.get("coset_size", 1)
	var current: int = dots.get_child_count()
	count_lbl.text = "%d / %d" % [current, coset_size]
	if current >= coset_size:
		count_lbl.add_theme_color_override("font_color", L5_GREEN)
	else:
		count_lbl.add_theme_color_override("font_color", L5_PURPLE_DIM)


func _update_coset_slot_visual(slot_idx: int, state: int) -> void:
	if slot_idx < 0 or slot_idx >= _coset_slot_nodes.size():
		return
	var slot: Panel = _coset_slot_nodes[slot_idx]
	if slot == null or not is_instance_valid(slot):
		return
	slot.add_theme_stylebox_override("panel", _make_coset_slot_style(state, slot_idx))

	var status = slot.get_node_or_null("StatusIcon")
	if status:
		_apply_coset_status_icon(status, state)

	var lbl = slot.get_node_or_null("SlotLabel")
	if lbl:
		match state:
			CosetSlotState.LOCKED:
				lbl.add_theme_color_override("font_color", L5_GREEN)
			CosetSlotState.FILLING:
				lbl.add_theme_color_override("font_color",
					COSET_COLORS[slot_idx % COSET_COLORS.size()])
			CosetSlotState.PREFILLED:
				lbl.add_theme_color_override("font_color", L5_PURPLE)
			_:
				lbl.add_theme_color_override("font_color", L5_PURPLE_DIM)


func _make_coset_slot_style(state: int, slot_idx: int = 0) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	var coset_color: Color = COSET_COLORS[slot_idx % COSET_COLORS.size()]
	match state:
		CosetSlotState.PREFILLED:
			s.bg_color = Color(0.06, 0.03, 0.08, 0.8)
			s.border_color = L5_PURPLE
		CosetSlotState.EMPTY:
			s.bg_color = Color(0.04, 0.02, 0.06, 0.4)
			s.border_color = Color(0.3, 0.15, 0.35, 0.3)
		CosetSlotState.FILLING:
			s.bg_color = Color(0.06, 0.04, 0.08, 0.7)
			s.border_color = L5_GOLD
		CosetSlotState.LOCKED:
			s.bg_color = Color(0.03, 0.06, 0.04, 0.8)
			s.border_color = L5_GREEN
	var bw: int = 1 if state == CosetSlotState.EMPTY else 2
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		s.set(prop, bw)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(prop, 4)
	return s


func _apply_coset_status_icon(status: Label, state: int) -> void:
	match state:
		CosetSlotState.PREFILLED:
			status.text = "\u2713"
			status.add_theme_color_override("font_color", L5_PURPLE)
		CosetSlotState.EMPTY:
			status.text = ""
		CosetSlotState.FILLING:
			status.text = "\u2190"
			status.add_theme_color_override("font_color", L5_GOLD)
		CosetSlotState.LOCKED:
			status.text = "\u2713"
			status.add_theme_color_override("font_color", L5_GREEN)


func _play_coset_glow(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _coset_slot_nodes.size():
		return
	var slot: Panel = _coset_slot_nodes[slot_idx]
	if slot == null or not is_instance_valid(slot):
		return
	var scene_root: Node = _find_scene_root()
	if scene_root == null:
		return
	var tw: Tween = scene_root.create_tween()
	tw.tween_property(slot, "modulate", Color(1.3, 1.5, 1.3, 1.0), 0.3)
	tw.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)


func _update_assembly_progress() -> void:
	if _progress_label == null:
		return
	var locked_count: int = 0
	var total: int = _coset_slot_states.size()
	for state in _coset_slot_states:
		if state == CosetSlotState.LOCKED or state == CosetSlotState.PREFILLED:
			locked_count += 1
	_progress_label.text = "Классы: %d / %d" % [locked_count, total]
	if locked_count >= total and total > 0:
		_progress_label.add_theme_color_override("font_color", L5_GREEN)
	else:
		_progress_label.add_theme_color_override("font_color", L5_PURPLE_DIM)


func _get_coset_slot_height(num_cosets: int, coset_size: int) -> int:
	# Scale slot height based on how many slots and elements per slot
	if num_cosets <= 3 and coset_size <= 4:
		return 60
	elif num_cosets <= 4:
		return 52
	elif num_cosets <= 6:
		return 44
	else:
		return 38


# ========================================================================
# Shared: action button builder, key dot, mini-Cayley, helpers
# ========================================================================

func _build_key_dot(parent: Node, sym_id: String, room_idx: int, color: Color) -> void:
	var dot_btn: Button = Button.new()
	dot_btn.name = "Dot_%s" % sym_id
	dot_btn.custom_minimum_size = Vector2(20, 14)
	dot_btn.flat = true
	dot_btn.focus_mode = Control.FOCUS_NONE
	dot_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 1)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_btn.add_child(hbox)

	var dot_rect: ColorRect = ColorRect.new()
	dot_rect.custom_minimum_size = Vector2(5, 5)
	dot_rect.size = Vector2(5, 5)
	dot_rect.color = color
	dot_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot_rect)

	var dot_lbl: Label = Label.new()
	dot_lbl.text = str(room_idx) if room_idx > 0 else "e"
	dot_lbl.add_theme_font_size_override("font_size", 7)
	dot_lbl.add_theme_color_override("font_color", color)
	dot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot_lbl)

	var dot_style: StyleBoxFlat = StyleBoxFlat.new()
	dot_style.bg_color = Color(color.r, color.g, color.b, 0.06)
	dot_style.border_color = Color(color.r, color.g, color.b, 0.25)
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		dot_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		dot_style.set(prop, 2)
	dot_btn.add_theme_stylebox_override("normal", dot_style)
	parent.add_child(dot_btn)


## Build a styled action button (assemble or merge).
func _build_action_button(btn_name: String, text: String, parent_w: float,
		y: float, accent: Color, is_merge: bool) -> Button:
	var btn: Button = Button.new()
	btn.name = btn_name
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12 if is_merge else 13)
	var btn_w: float = minf(parent_w - 16, 180.0)
	btn.position = Vector2((parent_w - btn_w) / 2.0, y)
	btn.size = Vector2(btn_w, 30)
	btn.focus_mode = Control.FOCUS_NONE

	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	if is_merge:
		btn_style.bg_color = Color(0.06, 0.03, 0.10, 0.9)
		btn_style.border_color = L5_PURPLE_GLOW
	else:
		btn_style.bg_color = Color(0.08, 0.04, 0.12, 0.9)
		btn_style.border_color = accent
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		btn_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		btn_style.set(prop, 6)
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover: StyleBoxFlat = btn_style.duplicate()
	btn_hover.bg_color = Color(0.12, 0.06, 0.18, 0.95)
	btn_hover.border_color = L5_PURPLE_GLOW
	btn.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed: StyleBoxFlat = btn_style.duplicate()
	btn_pressed.bg_color = Color(0.16, 0.08, 0.22, 1.0)
	btn.add_theme_stylebox_override("pressed", btn_pressed)

	btn.add_theme_color_override("font_color", accent)

	return btn


# --- Mini-Cayley Table ---

func _build_mini_cayley_table(entry: Panel, _index: int, cosets: Array,
		table: Dictionary, width: float, y_start: float) -> void:
	var reps: Array = []
	var rep_to_color: Dictionary = {}
	for ci in range(cosets.size()):
		var rep: String = cosets[ci]["representative"]
		reps.append(rep)
		rep_to_color[rep] = COSET_COLORS[ci % COSET_COLORS.size()]

	var count: int = reps.size()
	if count == 0:
		return

	var table_title: Label = Label.new()
	table_title.name = "CayleyTitle"
	table_title.text = "Таблица Кэли G/N"
	table_title.add_theme_font_size_override("font_size", 9)
	table_title.add_theme_color_override("font_color", L5_PURPLE_DIM)
	table_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	table_title.position = Vector2(4, y_start)
	table_title.size = Vector2(width - 8, 12)
	table_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(table_title)

	var table_y: float = y_start + 14
	var margin: float = 6.0
	var available_w: float = width - margin * 2
	var cell_sz: float = minf(floorf(available_w / (count + 1)), 26.0)
	var font_sz: int = 7 if count > 4 else 8

	var header_x: float = margin + cell_sz
	for ci in range(count):
		var rep_name: String = _quotient_mgr.get_name(reps[ci])
		if rep_name.length() > 3:
			rep_name = rep_name.left(3)
		var h_lbl: Label = Label.new()
		h_lbl.text = rep_name
		h_lbl.add_theme_font_size_override("font_size", font_sz)
		h_lbl.add_theme_color_override("font_color", rep_to_color[reps[ci]])
		h_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h_lbl.position = Vector2(header_x + ci * cell_sz, table_y)
		h_lbl.size = Vector2(cell_sz, cell_sz)
		h_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(h_lbl)

	var corner: Label = Label.new()
	corner.text = "\u00B7"
	corner.add_theme_font_size_override("font_size", font_sz + 2)
	corner.add_theme_color_override("font_color", L5_PURPLE_DIM)
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	corner.position = Vector2(margin, table_y)
	corner.size = Vector2(cell_sz, cell_sz)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(corner)

	for ri in range(count):
		var row_y: float = table_y + (ri + 1) * cell_sz
		var rep_name: String = _quotient_mgr.get_name(reps[ri])
		if rep_name.length() > 3:
			rep_name = rep_name.left(3)
		var r_lbl: Label = Label.new()
		r_lbl.text = rep_name
		r_lbl.add_theme_font_size_override("font_size", font_sz)
		r_lbl.add_theme_color_override("font_color", rep_to_color[reps[ri]])
		r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r_lbl.position = Vector2(margin, row_y)
		r_lbl.size = Vector2(cell_sz, cell_sz)
		r_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(r_lbl)

		for ci in range(count):
			var result_rep: String = table.get(reps[ri], {}).get(reps[ci], "")
			var r_name: String = _quotient_mgr.get_name(result_rep) if result_rep != "" else "?"
			if r_name.length() > 3:
				r_name = r_name.left(3)
			var cell_color: Color = rep_to_color.get(result_rep, L5_PURPLE_DIM)

			var cell: Label = Label.new()
			cell.text = r_name
			cell.add_theme_font_size_override("font_size", font_sz)
			cell.add_theme_color_override("font_color",
				Color(cell_color.r, cell_color.g, cell_color.b, 0.85))
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.position = Vector2(header_x + ci * cell_sz, row_y)
			cell.size = Vector2(cell_sz, cell_sz)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			entry.add_child(cell)

	var total_table_h: float = (count + 1) * cell_sz + 16
	var needed_h: float = y_start + total_table_h
	if needed_h > entry.custom_minimum_size.y:
		entry.custom_minimum_size.y = needed_h


# ========================================================================
# Public API (shared between phases)
# ========================================================================

## Refresh the panel to match current QuotientGroupManager state.
func refresh() -> void:
	if _current_phase == PanelPhase.ASSEMBLY:
		return  # Don't refresh during assembly
	if _current_phase == PanelPhase.TYPE_QUIZ:
		return  # Don't refresh during quiz
	_populate_entries()
	update_progress()


## Update the progress label.
func update_progress() -> void:
	if _progress_label == null or _quotient_mgr == null:
		return
	if _current_phase == PanelPhase.ASSEMBLY:
		_update_assembly_progress()
		return
	var p: Dictionary = _quotient_mgr.get_progress()
	_progress_label.text = "Факторгруппы: %d / %d" % [p["constructed"], p["total"]]
	if p["constructed"] >= p["total"] and p["total"] > 0:
		_progress_label.add_theme_color_override("font_color", L5_GREEN)
	else:
		_progress_label.add_theme_color_override("font_color", L5_PURPLE_DIM)


## Get coset colors for a given normal subgroup (for map coloring).
func get_coset_color_map(subgroup_index: int) -> Dictionary:
	if _quotient_mgr == null:
		return {}

	var cosets: Array = _quotient_mgr.compute_cosets(subgroup_index)
	var color_map: Dictionary = {}
	for ci in range(cosets.size()):
		var coset_color: Color = COSET_COLORS[ci % COSET_COLORS.size()]
		var elements: Array = cosets[ci].get("elements", [])
		for sid in elements:
			color_map[sid] = coset_color
	return color_map


## Get the currently selected subgroup index.
func get_selected_index() -> int:
	return _selected_index


## Show success glow on a constructed entry.
func show_construction_success(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry: Panel = _entries[index]
	if entry == null or not is_instance_valid(entry):
		return
	var scene_root: Node = _find_scene_root()
	if scene_root == null:
		return
	var tw: Tween = scene_root.create_tween()
	tw.tween_property(entry, "modulate", Color(1.3, 1.5, 1.3, 1.0), 0.3)
	tw.tween_property(entry, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)


## Show error flash on an entry.
func show_construction_error(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry: Panel = _entries[index]
	if entry == null or not is_instance_valid(entry):
		return
	var scene_root: Node = _find_scene_root()
	if scene_root == null:
		return
	var tw: Tween = scene_root.create_tween()
	tw.tween_property(entry, "modulate", Color(1.5, 0.5, 0.5, 1.0), 0.2)
	tw.tween_property(entry, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)


## Cleanup.
func cleanup() -> void:
	_entries.clear()
	_coset_slot_nodes.clear()
	_coset_slot_states.clear()
	_quiz_option_buttons.clear()
	_quiz_result.clear()
	_quotient_mgr = null
	_room_state = null


# --- Event Handlers ---

func _on_entry_clicked(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	if _selected_index == index:
		_selected_index = -1
		subgroup_selected.emit(-1)
	else:
		_selected_index = index
		subgroup_selected.emit(index)

	_populate_entries()


func _on_assemble_pressed(index: int) -> void:
	assembly_started.emit(index)


func _on_merge_pressed(index: int) -> void:
	merge_requested.emit(index)


func _on_back_pressed() -> void:
	back_to_selection.emit()


# --- Color helpers ---

func _get_key_color(sym_id: String) -> Color:
	if _room_state == null:
		return Color.WHITE
	var idx: int = _sym_id_to_room_idx(sym_id)
	if idx >= 0 and idx < _room_state.colors.size():
		return _room_state.colors[idx]
	return Color.WHITE


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
