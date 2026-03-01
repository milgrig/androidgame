class_name QuotientPanel
extends Control
## QuotientPanel — Left-side panel for Layer 5 quotient group construction.
##
## Displays:
##   1. Scrollable list of normal subgroups N found in Layer 4
##   2. For each N: element labels, |G/N| info, "Построить G/N" button
##   3. After construction: coset coloring legend + mini-Cayley table
##   4. "СКЛЕИТЬ" button — triggers merge animation (cosets → single nodes)
##   5. Progress: Факторгруппы: X / Y
##   6. Auto-complete for levels without normal subgroups
##
## Purple theme. Analogous to CrackingPanel for Layer 4.
##
## Signals:
##   construct_requested(index)     — player pressed "Построить G/N"
##   merge_requested(index)         — player pressed "СКЛЕИТЬ" (animate coset merge)
##   subgroup_selected(index)       — player tapped a normal subgroup entry
##   all_constructed()              — all quotient groups done (forwarded)


# --- Signals ---

## Emitted when the player presses "Построить G/N" for a given normal subgroup.
signal construct_requested(index: int)

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
const ENTRY_HEIGHT_EXPANDED := 260  ## After construction — shows Cayley table


# --- State ---

var _room_state: RoomState = null
var _quotient_mgr: QuotientGroupManager = null
var _panel_rect: Rect2 = Rect2()

## Quotient entry nodes (one per normal subgroup)
var _entries: Array = []  # Array[Panel]

## Currently selected subgroup index (-1 = none)
var _selected_index: int = -1

## Scroll + list containers
var _scroll: ScrollContainer = null
var _entry_list: VBoxContainer = null

## Progress label
var _progress_label: Label = null


# --- Setup ---

## Build the quotient panel inside the given parent.
func setup(parent: Node, panel_rect: Rect2, room_state: RoomState,
		quotient_mgr: QuotientGroupManager) -> void:
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


# --- Entry Population ---

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
	# Use display names (truncate if too many)
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

	# --- Row 2: Quotient info |G/N| = X (type) ---
	var q_order: int = ns_data.get("quotient_order", 0)
	var q_type: String = ns_data.get("quotient_type", "?")
	var info_label: Label = Label.new()
	info_label.name = "InfoLabel"
	info_label.text = "|G/N| = %d  (%s)" % [q_order, q_type]
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
		var dot_btn: Button = Button.new()
		dot_btn.name = "Dot_%s" % sid
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
		dots.add_child(dot_btn)

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
		status_label.text = "Нажмите для построения"
		status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.9, 0.7))

	# --- Construct / Merge buttons ---
	if is_constructed:
		# "СКЛЕИТЬ" button (triggers coset merge animation)
		var merge_btn: Button = _build_action_button(
			"MergeBtn_%d" % index, "СКЛЕИТЬ", width, 74, L5_PURPLE, true)
		merge_btn.pressed.connect(_on_merge_pressed.bind(index))
		entry.add_child(merge_btn)

		# --- Coset color legend ---
		var legend_y: float = 100.0
		var construction: Dictionary = _quotient_mgr.get_construction(index)
		var cosets: Array = construction.get("cosets", [])
		if not cosets.is_empty():
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

				# Color swatch
				var swatch: ColorRect = ColorRect.new()
				swatch.custom_minimum_size = Vector2(8, 8)
				swatch.color = coset_color
				swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
				coset_row.add_child(swatch)

				# Coset elements label
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

			# --- Mini-Cayley table for the quotient group ---
			legend_y += 4
			var table: Dictionary = construction.get("table", {})
			if not table.is_empty():
				_build_mini_cayley_table(entry, index, cosets, table, width, legend_y)

	else:
		# "Построить G/N" button
		var construct_btn: Button = _build_action_button(
			"ConstructBtn_%d" % index, "Построить G/N", width, 76, L5_PURPLE, false)
		construct_btn.pressed.connect(_on_construct_pressed.bind(index))
		entry.add_child(construct_btn)

	# Click handler for entry selection (visual highlight + coset coloring)
	entry.gui_input.connect(_on_entry_clicked.bind(index))

	return entry


## Build a styled action button (construct or merge).
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

## Build a compact multiplication table for the quotient group G/N.
## Each cell shows the product coset representative, colored by coset color.
func _build_mini_cayley_table(entry: Panel, _index: int, cosets: Array,
		table: Dictionary, width: float, y_start: float) -> void:
	var reps: Array = []
	var rep_to_color: Dictionary = {}  ## rep -> Color (coset color)
	for ci in range(cosets.size()):
		var rep: String = cosets[ci]["representative"]
		reps.append(rep)
		rep_to_color[rep] = COSET_COLORS[ci % COSET_COLORS.size()]

	var count: int = reps.size()
	if count == 0:
		return

	# Table title
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

	# Calculate cell sizes
	var table_y: float = y_start + 14
	var margin: float = 6.0
	var available_w: float = width - margin * 2
	var cell_sz: float = minf(floorf(available_w / (count + 1)), 26.0)
	var font_sz: int = 7 if count > 4 else 8

	# Header row: blank + rep names
	var header_x: float = margin + cell_sz  # Skip the "·" corner cell
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

	# Corner cell "·"
	var corner: Label = Label.new()
	corner.text = "\u00B7"
	corner.add_theme_font_size_override("font_size", font_sz + 2)
	corner.add_theme_color_override("font_color", L5_PURPLE_DIM)
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	corner.position = Vector2(margin, table_y)
	corner.size = Vector2(cell_sz, cell_sz)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(corner)

	# Data rows
	for ri in range(count):
		var row_y: float = table_y + (ri + 1) * cell_sz

		# Row header
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

		# Cells: table[rep_a][rep_b]
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

	# Update entry minimum height to accommodate the table
	var total_table_h: float = (count + 1) * cell_sz + 16
	var needed_h: float = y_start + total_table_h
	if needed_h > entry.custom_minimum_size.y:
		entry.custom_minimum_size.y = needed_h


# --- Public API ---

## Refresh the panel to match current QuotientGroupManager state.
func refresh() -> void:
	_populate_entries()
	update_progress()


## Update the progress label.
func update_progress() -> void:
	if _progress_label == null or _quotient_mgr == null:
		return
	var p: Dictionary = _quotient_mgr.get_progress()
	_progress_label.text = "Факторгруппы: %d / %d" % [p["constructed"], p["total"]]
	if p["constructed"] >= p["total"] and p["total"] > 0:
		_progress_label.add_theme_color_override("font_color", L5_GREEN)
	else:
		_progress_label.add_theme_color_override("font_color", L5_PURPLE_DIM)


## Get coset colors for a given normal subgroup (for map coloring).
## Returns: {sym_id: Color} — mapping each element to its coset's color.
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
	_quotient_mgr = null
	_room_state = null


# --- Event Handlers ---

## Handle click on a quotient entry (select / deselect).
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

	# Refresh visual selection
	_populate_entries()


## Handle "Построить G/N" button press.
func _on_construct_pressed(index: int) -> void:
	construct_requested.emit(index)


## Handle "СКЛЕИТЬ" button press.
func _on_merge_pressed(index: int) -> void:
	merge_requested.emit(index)


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
