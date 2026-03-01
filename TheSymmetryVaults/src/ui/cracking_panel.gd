class_name CrackingPanel
extends Control
## CrackingPanel — Left-side panel for Layer 4 conjugation cracking.
##
## Displays:
##   1. Keyring-style subgroup list — colored dots like Layer 3 keyrings
##   2. Three-slot maneuver zone — g · h · g⁻¹ with tap-to-fill from keys
##   3. "Попытаться взломать" button — triggers animated conjugation sequence
##   4. "Нормальная" button — confirm the active subgroup is normal
##
## Signals:
##   subgroup_selected(index)    — player selected a subgroup to test
##   crack_requested(g_sym_id, h_sym_id) — player pressed "Взломать" with filled slots
##   confirm_normal_requested()  — player claims active subgroup is normal
##   g_slot_tapped()             — g slot was tapped (ready for ⊕ input)
##   h_slot_tapped()             — h slot was tapped (ready for ⊕ input)


# --- Signals ---

signal subgroup_selected(index: int)
## Emitted when the player presses "Попытаться взломать" with g and h filled.
## The controller should perform the animated sequence: home → g → h → g⁻¹
signal crack_requested(g_sym_id: String, h_sym_id: String)
signal confirm_normal_requested()
signal g_slot_tapped()
signal h_slot_tapped()


# --- Constants ---

const L4_RED := Color(0.9, 0.35, 0.3, 1.0)
const L4_RED_DIM := Color(0.65, 0.25, 0.22, 0.7)
const L4_RED_BG := Color(0.06, 0.02, 0.02, 0.8)
const L4_RED_BORDER := Color(0.5, 0.15, 0.12, 0.7)
const L4_RED_GLOW := Color(1.0, 0.4, 0.3, 0.9)
const L4_GREEN := Color(0.3, 0.9, 0.4, 0.9)
const L4_GREEN_DIM := Color(0.2, 0.6, 0.3, 0.7)
const L4_GOLD := Color(0.95, 0.80, 0.20, 1.0)

## Maneuver slot visual states
const SLOT_EMPTY_BG := Color(0.08, 0.04, 0.04, 0.6)
const SLOT_ACTIVE_BG := Color(0.12, 0.06, 0.04, 0.8)
const SLOT_FILLED_BG := Color(0.10, 0.08, 0.04, 0.9)

## Maneuver slot sizes
const MANEUVER_SLOT_SIZE := Vector2(56, 52)
const MANEUVER_DOT_SIZE := 10

## Keyring slot height tiers
const SLOT_HEIGHT_NORMAL := 54
const SLOT_HEIGHT_COMPACT := 44
const SLOT_HEIGHT_TINY := 36


# --- State ---

var _room_state: RoomState = null
var _cracking_mgr: ConjugationCrackingManager = null
var _panel_rect: Rect2 = Rect2()

## Keyring-style subgroup slot nodes
var _sg_slots: Array = []  # Array[Panel]

## Currently selected subgroup slot (-1 = none)
var _selected_sg_slot: int = -1

## Three-slot maneuver zone
var _g_slot: Panel = null       ## Slot for "g" (conjugator from G)
var _h_slot: Panel = null       ## Slot for "h" (target from H)
var _ginv_slot: Panel = null    ## Slot for "g⁻¹" (auto-filled)

## Currently filled values
var _g_sym_id: String = ""
var _h_sym_id: String = ""

## Which slot is waiting for input: "g", "h", or "" (none)
var _active_input: String = ""

## Result display
var _result_label: Label = null
var _result_equation: Label = null

## "Попытаться взломать" button
var _crack_btn: Button = null

## Confirm normal button
var _confirm_btn: Button = null

## Progress label
var _progress_label: Label = null

## Scroll container for subgroup list
var _scroll: ScrollContainer = null
var _sg_list: VBoxContainer = null

## Maneuver zone container
var _maneuver_zone: Panel = null

## Test history display
var _history_scroll: ScrollContainer = null
var _history_list: VBoxContainer = null

## Whether a crack animation is currently running
var _crack_animating: bool = false


# --- Setup ---

## Build the cracking panel inside the given parent.
func setup(parent: Node, panel_rect: Rect2, room_state: RoomState,
		cracking_mgr: ConjugationCrackingManager) -> void:
	_panel_rect = panel_rect
	_room_state = room_state
	_cracking_mgr = cracking_mgr

	position = panel_rect.position
	size = panel_rect.size
	name = "CrackingPanel"

	# Build the frame
	var frame: Panel = Panel.new()
	frame.name = "CrackingFrame"
	frame.position = Vector2.ZERO
	frame.size = panel_rect.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.02, 0.7)
	style.border_color = L4_RED_BORDER
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
	title.name = "CrackingFrameTitle"
	title.text = "Взлом"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", L4_RED_DIM)
	title.position = Vector2(8, 3)
	title.size = Vector2(panel_rect.size.x - 16, 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var inner_w: float = panel_rect.size.x - 12.0
	var content_y: float = 20.0

	# --- Zone 1: Keyring-style subgroup selector (top ~40%) ---
	var sg_zone_h: float = _calculate_sg_zone_height()
	_build_subgroup_selector(content_y, inner_w, sg_zone_h)
	content_y += sg_zone_h + 4

	# --- Divider ---
	var div: Panel = Panel.new()
	div.position = Vector2(8, content_y)
	div.size = Vector2(inner_w - 4, 1)
	var div_style: StyleBoxFlat = StyleBoxFlat.new()
	div_style.bg_color = L4_RED_BORDER
	div.add_theme_stylebox_override("panel", div_style)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(div)
	content_y += 5

	# --- Zone 2: Three-slot maneuver zone + crack button ---
	var maneuver_h: float = _calculate_maneuver_zone_height()
	_build_maneuver_zone(content_y, inner_w, maneuver_h)
	content_y += maneuver_h + 4

	# --- Zone 3: Confirm button + progress (bottom) ---
	_build_result_zone(content_y, inner_w)


## Calculate subgroup selector zone height.
func _calculate_sg_zone_height() -> float:
	if _cracking_mgr == null:
		return 80.0
	var count: int = _cracking_mgr.get_target_subgroups().size()
	var slot_h: int = _get_sg_slot_height(count)
	var header: float = 18.0
	var desired: float = header + count * (slot_h + 3)
	# Cap at 40% of panel height
	var max_h: float = _panel_rect.size.y * 0.40
	return minf(desired, max_h)


## Calculate maneuver zone height.
func _calculate_maneuver_zone_height() -> float:
	return minf(_panel_rect.size.y * 0.38, 180.0)


## Get subgroup slot height based on count.
func _get_sg_slot_height(count: int) -> int:
	if count <= 4:
		return SLOT_HEIGHT_NORMAL
	elif count <= 7:
		return SLOT_HEIGHT_COMPACT
	else:
		return SLOT_HEIGHT_TINY


# --- Keyring-Style Subgroup Selector ---

func _build_subgroup_selector(y: float, width: float, height: float) -> void:
	if _cracking_mgr == null:
		return

	# Section title
	var sec_title: Label = Label.new()
	sec_title.name = "SGSectionTitle"
	sec_title.text = "Брелки"
	sec_title.add_theme_font_size_override("font_size", 10)
	sec_title.add_theme_color_override("font_color", L4_RED)
	sec_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec_title.position = Vector2(6, y)
	sec_title.size = Vector2(width, 14)
	sec_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sec_title)

	# Scrollable list
	_scroll = ScrollContainer.new()
	_scroll.name = "SGScroll"
	_scroll.position = Vector2(6, y + 16)
	_scroll.size = Vector2(width, height - 18)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	_sg_list = VBoxContainer.new()
	_sg_list.name = "SGList"
	_sg_list.add_theme_constant_override("separation", 3)
	_scroll.add_child(_sg_list)

	_populate_subgroup_list()


func _populate_subgroup_list() -> void:
	if _sg_list == null or _cracking_mgr == null:
		return

	# Clear existing
	for child in _sg_list.get_children():
		child.queue_free()
	_sg_slots.clear()

	var subgroups: Array = _cracking_mgr.get_target_subgroups()
	var inner_w: float = _panel_rect.size.x - 20
	var slot_h: int = _get_sg_slot_height(subgroups.size())

	for i in range(subgroups.size()):
		var sg: Dictionary = subgroups[i]
		var elements: Array = sg.get("elements", [])
		var is_classified: bool = _cracking_mgr.is_classified(i)
		var classification: Dictionary = _cracking_mgr.get_classification(i)
		var is_active: bool = (_cracking_mgr.get_active_subgroup_index() == i)

		var slot: Panel = _build_sg_slot(i, inner_w, slot_h, elements,
			is_classified, classification, is_active)
		_sg_list.add_child(slot)
		_sg_slots.append(slot)


## Build one keyring-style subgroup slot with colored dots.
func _build_sg_slot(index: int, width: float, height: int, elements: Array,
		is_classified: bool, classification: Dictionary, is_active: bool) -> Panel:
	var slot: Panel = Panel.new()
	slot.name = "SGSlot_%d" % index
	slot.custom_minimum_size = Vector2(width - 4, height)
	slot.size = Vector2(width - 4, height)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	# Determine style based on state
	var slot_style: StyleBoxFlat = StyleBoxFlat.new()
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		slot_style.set(prop, 4)

	var label_color: Color
	var status_text: String = ""
	var status_color: Color = L4_RED_DIM

	if is_classified:
		if classification.get("is_normal", false):
			# Unbreakable — green
			slot_style.bg_color = Color(0.03, 0.08, 0.04, 0.8)
			slot_style.border_color = Color(0.2, 0.6, 0.3, 0.7)
			label_color = L4_GREEN
			status_text = "\u26E8"  # shield
			status_color = L4_GREEN
		else:
			# Cracked — red
			slot_style.bg_color = Color(0.08, 0.03, 0.03, 0.8)
			slot_style.border_color = L4_RED_BORDER
			label_color = L4_RED
			status_text = "\u2717"  # X mark
			status_color = L4_RED
		for prop in ["border_width_left", "border_width_right",
					"border_width_top", "border_width_bottom"]:
			slot_style.set(prop, 2)
	elif is_active:
		# Active — bright red border
		slot_style.bg_color = Color(0.10, 0.06, 0.04, 0.9)
		slot_style.border_color = L4_RED
		label_color = Color(1.0, 0.8, 0.7, 1.0)
		status_text = "\u25B6"  # triangle
		status_color = L4_RED
		for prop in ["border_width_left", "border_width_right",
					"border_width_top", "border_width_bottom"]:
			slot_style.set(prop, 2)
	else:
		# Unclassified, not active
		slot_style.bg_color = Color(0.05, 0.04, 0.04, 0.7)
		slot_style.border_color = Color(0.4, 0.25, 0.25, 0.4)
		label_color = Color(0.8, 0.7, 0.7, 0.9)
		for prop in ["border_width_left", "border_width_right",
					"border_width_top", "border_width_bottom"]:
			slot_style.set(prop, 1)

	slot.add_theme_stylebox_override("panel", slot_style)

	# Slot label "Брелок #N"
	var lbl: Label = Label.new()
	lbl.name = "SlotLabel"
	if elements.size() == 1:
		lbl.text = "Брелок #%d \u2014 Тождество" % (index + 1)
	else:
		lbl.text = "Брелок #%d (пор. %d)" % [index + 1, elements.size()]
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", label_color)
	lbl.position = Vector2(6, 2)
	lbl.size = Vector2(width - 50, 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)

	# Status indicator (right side)
	if status_text != "":
		var status: Label = Label.new()
		status.name = "StatusIcon"
		status.text = status_text
		status.add_theme_font_size_override("font_size", 11)
		status.add_theme_color_override("font_color", status_color)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status.position = Vector2(width - 40, 2)
		status.size = Vector2(30, 14)
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(status)

	# Colored key dots (like Layer 3 keyrings)
	var dots: HFlowContainer = HFlowContainer.new()
	dots.name = "KeyDots"
	dots.position = Vector2(4, 16)
	dots.size = Vector2(width - 12, height - 18)
	dots.add_theme_constant_override("h_separation", 2)
	dots.add_theme_constant_override("v_separation", 1)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(dots)

	# Add colored dot for each element (T111: skip identity key)
	for sym_id in elements:
		var room_idx_check: int = _sym_id_to_room_idx(sym_id)
		if room_idx_check == 0:
			continue  # T111: identity key never shown in UI
		var dot_btn: Button = Button.new()
		dot_btn.name = "Dot_%s" % sym_id
		dot_btn.custom_minimum_size = Vector2(20, 16)
		dot_btn.size = Vector2(20, 16)
		dot_btn.focus_mode = Control.FOCUS_NONE
		dot_btn.flat = true
		dot_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE  # pass clicks to slot

		var color: Color = _get_key_color(sym_id)

		# Inner: colored dot + number
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
		var room_idx: int = _sym_id_to_room_idx(sym_id)
		dot_lbl.text = str(room_idx) if room_idx > 0 else "e"
		dot_lbl.add_theme_font_size_override("font_size", 7)
		dot_lbl.add_theme_color_override("font_color", color)
		dot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(dot_lbl)

		# Dot style
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

	# Connect click handler
	if not is_classified:
		slot.gui_input.connect(_on_sg_slot_clicked.bind(index, elements))

	return slot


# --- Three-Slot Maneuver Zone ---

func _build_maneuver_zone(y: float, width: float, height: float) -> void:
	_maneuver_zone = Panel.new()
	_maneuver_zone.name = "ManeuverZone"
	_maneuver_zone.position = Vector2(6, y)
	_maneuver_zone.size = Vector2(width, height)
	_maneuver_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mz_style: StyleBoxFlat = StyleBoxFlat.new()
	mz_style.bg_color = Color(0.04, 0.02, 0.02, 0.5)
	mz_style.border_color = Color(0, 0, 0, 0)
	_maneuver_zone.add_theme_stylebox_override("panel", mz_style)
	add_child(_maneuver_zone)

	# Section title
	var sec_title: Label = Label.new()
	sec_title.name = "ManeuverTitle"
	sec_title.text = "g \u00B7 h \u00B7 g\u207B\u00B9"
	sec_title.add_theme_font_size_override("font_size", 12)
	sec_title.add_theme_color_override("font_color", L4_RED)
	sec_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec_title.position = Vector2(0, 2)
	sec_title.size = Vector2(width, 16)
	sec_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maneuver_zone.add_child(sec_title)

	# Three slots side by side
	var slot_gap: float = 6.0
	var total_slots_w: float = MANEUVER_SLOT_SIZE.x * 3 + slot_gap * 2
	var start_x: float = (width - total_slots_w) / 2.0
	var slots_y: float = 22.0

	_g_slot = _build_maneuver_slot("g", start_x, slots_y, "g", "\u2295")
	_maneuver_zone.add_child(_g_slot)

	# Dot separator 1
	var dot1: Label = Label.new()
	dot1.text = "\u00B7"
	dot1.add_theme_font_size_override("font_size", 16)
	dot1.add_theme_color_override("font_color", L4_RED_DIM)
	dot1.position = Vector2(start_x + MANEUVER_SLOT_SIZE.x + 1, slots_y + 14)
	dot1.size = Vector2(slot_gap - 2, 20)
	dot1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maneuver_zone.add_child(dot1)

	_h_slot = _build_maneuver_slot("h", start_x + MANEUVER_SLOT_SIZE.x + slot_gap,
		slots_y, "h", "\u2295")
	_maneuver_zone.add_child(_h_slot)

	# Dot separator 2
	var dot2: Label = Label.new()
	dot2.text = "\u00B7"
	dot2.add_theme_font_size_override("font_size", 16)
	dot2.add_theme_color_override("font_color", L4_RED_DIM)
	dot2.position = Vector2(start_x + (MANEUVER_SLOT_SIZE.x + slot_gap) * 2 - slot_gap + 1,
		slots_y + 14)
	dot2.size = Vector2(slot_gap - 2, 20)
	dot2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maneuver_zone.add_child(dot2)

	_ginv_slot = _build_maneuver_slot("g_inv",
		start_x + (MANEUVER_SLOT_SIZE.x + slot_gap) * 2,
		slots_y, "g\u207B\u00B9", "Авто")
	_maneuver_zone.add_child(_ginv_slot)

	# --- "Попытаться взломать" button ---
	var crack_btn_y: float = slots_y + MANEUVER_SLOT_SIZE.y + 6
	_crack_btn = Button.new()
	_crack_btn.name = "CrackBtn"
	_crack_btn.text = "\u26A1 Попытаться взломать"
	_crack_btn.add_theme_font_size_override("font_size", 11)
	var crack_btn_w: float = width * 0.90
	_crack_btn.position = Vector2((width - crack_btn_w) / 2.0, crack_btn_y)
	_crack_btn.size = Vector2(crack_btn_w, 26)
	_crack_btn.focus_mode = Control.FOCUS_NONE
	_crack_btn.visible = false  # Hidden until both g and h are filled

	var crack_style: StyleBoxFlat = StyleBoxFlat.new()
	crack_style.bg_color = Color(0.10, 0.04, 0.03, 0.9)
	crack_style.border_color = L4_RED
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		crack_style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		crack_style.set(prop, 5)
	_crack_btn.add_theme_stylebox_override("normal", crack_style)
	var crack_hover: StyleBoxFlat = crack_style.duplicate()
	crack_hover.bg_color = Color(0.15, 0.06, 0.04, 0.95)
	crack_hover.border_color = L4_RED_GLOW
	_crack_btn.add_theme_stylebox_override("hover", crack_hover)
	var crack_pressed: StyleBoxFlat = crack_style.duplicate()
	crack_pressed.bg_color = Color(0.20, 0.08, 0.05, 1.0)
	_crack_btn.add_theme_stylebox_override("pressed", crack_pressed)
	_crack_btn.add_theme_color_override("font_color", L4_RED)
	_crack_btn.pressed.connect(_on_crack_btn_pressed)
	_maneuver_zone.add_child(_crack_btn)

	# Equation label (shows the full equation after test)
	_result_equation = Label.new()
	_result_equation.name = "ResultEquation"
	_result_equation.text = ""
	_result_equation.add_theme_font_size_override("font_size", 10)
	_result_equation.add_theme_color_override("font_color", L4_RED_DIM)
	_result_equation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_equation.position = Vector2(0, crack_btn_y + 30)
	_result_equation.size = Vector2(width, 14)
	_result_equation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maneuver_zone.add_child(_result_equation)

	# Result label (shows "∈ H" or "∉ H — ВЗЛОМ!")
	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.text = ""
	_result_label.add_theme_font_size_override("font_size", 11)
	_result_label.add_theme_color_override("font_color", L4_RED_DIM)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.position = Vector2(0, crack_btn_y + 46)
	_result_label.size = Vector2(width, 16)
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maneuver_zone.add_child(_result_label)

	# Test history (compact, below result)
	var hist_y: float = crack_btn_y + 66
	var hist_h: float = height - hist_y - 4
	if hist_h > 16:
		_history_scroll = ScrollContainer.new()
		_history_scroll.name = "HistoryScroll"
		_history_scroll.position = Vector2(2, hist_y)
		_history_scroll.size = Vector2(width - 4, hist_h)
		_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_history_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_maneuver_zone.add_child(_history_scroll)

		_history_list = VBoxContainer.new()
		_history_list.name = "HistoryList"
		_history_list.add_theme_constant_override("separation", 1)
		_history_scroll.add_child(_history_list)

	# Start with g slot active
	_set_active_input("g")


## Build one maneuver slot (g, h, or g⁻¹).
func _build_maneuver_slot(slot_id: String, x: float, y: float,
		label_text: String, hint_text: String) -> Panel:
	var slot: Panel = Panel.new()
	slot.name = "Slot_%s" % slot_id
	slot.position = Vector2(x, y)
	slot.size = MANEUVER_SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	var slot_style: StyleBoxFlat = StyleBoxFlat.new()
	slot_style.bg_color = SLOT_EMPTY_BG
	slot_style.border_color = L4_RED_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		slot_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		slot_style.set(prop, 6)
	slot.add_theme_stylebox_override("panel", slot_style)

	# Top label (g, h, g⁻¹)
	var top_lbl: Label = Label.new()
	top_lbl.name = "TopLabel"
	top_lbl.text = label_text
	top_lbl.add_theme_font_size_override("font_size", 10)
	top_lbl.add_theme_color_override("font_color", L4_RED_DIM)
	top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_lbl.position = Vector2(2, 2)
	top_lbl.size = Vector2(MANEUVER_SLOT_SIZE.x - 4, 14)
	top_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(top_lbl)

	# Color dot (shows key color when filled)
	var dot: ColorRect = ColorRect.new()
	dot.name = "KeyDot"
	dot.position = Vector2((MANEUVER_SLOT_SIZE.x - MANEUVER_DOT_SIZE) / 2.0, 18)
	dot.size = Vector2(MANEUVER_DOT_SIZE, MANEUVER_DOT_SIZE)
	dot.color = Color(0.3, 0.2, 0.2, 0.3)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(dot)

	# Value label (shows sym_id name when filled)
	var val_lbl: Label = Label.new()
	val_lbl.name = "ValueLabel"
	val_lbl.text = hint_text
	val_lbl.add_theme_font_size_override("font_size", 9)
	val_lbl.add_theme_color_override("font_color", Color(0.5, 0.4, 0.4, 0.5))
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.position = Vector2(2, 32)
	val_lbl.size = Vector2(MANEUVER_SLOT_SIZE.x - 4, 14)
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(val_lbl)

	# Connect click handler (except g⁻¹ which is auto-filled)
	if slot_id != "g_inv":
		slot.gui_input.connect(_on_slot_clicked.bind(slot_id))

	return slot


# --- Result Zone ---

func _build_result_zone(y: float, width: float) -> void:
	# Progress label
	_progress_label = Label.new()
	_progress_label.name = "CrackingProgress"
	_progress_label.add_theme_font_size_override("font_size", 10)
	_progress_label.add_theme_color_override("font_color", L4_RED_DIM)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.position = Vector2(6, _panel_rect.size.y - 38)
	_progress_label.size = Vector2(width, 14)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_label)
	update_progress()

	# Confirm Normal button
	_confirm_btn = Button.new()
	_confirm_btn.name = "ConfirmNormalBtn"
	_confirm_btn.text = "\u26E8 Нормальная"
	_confirm_btn.add_theme_font_size_override("font_size", 11)
	var btn_w: float = width * 0.85
	_confirm_btn.position = Vector2(6 + (width - btn_w) / 2.0, _panel_rect.size.y - 56)
	_confirm_btn.size = Vector2(btn_w, 24)
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_confirm_btn.visible = false

	var cfm_style: StyleBoxFlat = StyleBoxFlat.new()
	cfm_style.bg_color = Color(0.03, 0.07, 0.04, 0.8)
	cfm_style.border_color = Color(0.2, 0.5, 0.3, 0.6)
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		cfm_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		cfm_style.set(prop, 4)
	_confirm_btn.add_theme_stylebox_override("normal", cfm_style)
	var cfm_hover: StyleBoxFlat = cfm_style.duplicate()
	cfm_hover.bg_color = Color(0.06, 0.12, 0.07, 0.9)
	cfm_hover.border_color = Color(0.3, 0.7, 0.4, 0.8)
	_confirm_btn.add_theme_stylebox_override("hover", cfm_hover)
	_confirm_btn.add_theme_color_override("font_color", L4_GREEN_DIM)
	_confirm_btn.pressed.connect(_on_confirm_normal_pressed)
	add_child(_confirm_btn)


# --- Public API ---

## Set the conjugator "g" from a ⊕ button press (g mode).
func set_g(sym_id: String) -> void:
	if _cracking_mgr == null:
		return
	_g_sym_id = sym_id
	_update_slot_display(_g_slot, sym_id, true)

	# Auto-fill g⁻¹
	var g_perm: Permutation = _cracking_mgr.get_perm(sym_id)
	if g_perm != null:
		var g_inv: Permutation = g_perm.inverse()
		var g_inv_sym_id: String = _find_sym_id_for_perm(g_inv)
		_update_slot_display(_ginv_slot, g_inv_sym_id, true)

	# Switch to h mode
	_set_active_input("h")
	h_slot_tapped.emit()

	# Show crack button if both slots are filled
	_update_crack_btn_visibility()


## Set the target "h" from an ⊕ button press (h mode).
func set_h(sym_id: String) -> void:
	if _cracking_mgr == null:
		return

	# T116: validate h is in the active subgroup H (defense-in-depth)
	var sg_idx: int = _cracking_mgr.get_active_subgroup_index()
	var sg_elements: Array = _cracking_mgr.get_subgroup_elements(sg_idx)
	if not sg_elements.has(sym_id):
		push_warning("CrackingPanel.set_h: sym_id '%s' not in active subgroup H" % sym_id)
		return

	_h_sym_id = sym_id
	_update_slot_display(_h_slot, sym_id, true)

	# Switch to g mode
	_set_active_input("g")
	g_slot_tapped.emit()

	# Show crack button if both slots are filled
	_update_crack_btn_visibility()


## Show the conjugation result in the panel (called after animated sequence).
func show_result(g_sym_id: String, h_sym_id: String, result: Dictionary) -> void:
	if _cracking_mgr == null:
		return

	var g_name: String = _cracking_mgr.get_name(g_sym_id)
	var h_name: String = _cracking_mgr.get_name(h_sym_id)
	var r_name: String = result.get("result_name", "?")
	var stayed_in: bool = result.get("stayed_in", false)

	# Update equation
	if _result_equation:
		_result_equation.text = "%s \u00B7 %s \u00B7 %s\u207B\u00B9 = %s" % [
			g_name, h_name, g_name, r_name]

	# Update result label
	if _result_label:
		if stayed_in:
			_result_label.text = "= %s \u2208 H  \u2713" % r_name
			_result_label.add_theme_color_override("font_color", L4_GREEN)
		else:
			_result_label.text = "= %s \u2209 H  \u2014 \u0412\u0417\u041B\u041E\u041C!" % r_name
			_result_label.add_theme_color_override("font_color", L4_RED)

	# Flash maneuver zone
	_flash_maneuver_zone(stayed_in)

	# Add to history
	_add_history_entry(g_name, h_name, r_name, stayed_in)

	# Unlock UI after animation
	_crack_animating = false

	# Reset slots for next test (after brief delay)
	var scene_root: Node = _find_scene_root()
	if scene_root:
		var tw: Tween = scene_root.create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(_reset_slots)


## Refresh the panel after state changes (subgroup classified, etc.)
func refresh() -> void:
	_populate_subgroup_list()
	update_progress()

	# Show/hide confirm button
	if _confirm_btn and _cracking_mgr:
		_confirm_btn.visible = (_cracking_mgr.get_active_subgroup_index() >= 0)

	# Update maneuver zone title with active subgroup info
	if _maneuver_zone:
		var title_lbl = _maneuver_zone.get_node_or_null("ManeuverTitle")
		if title_lbl and _cracking_mgr:
			var active: int = _cracking_mgr.get_active_subgroup_index()
			if active >= 0:
				title_lbl.text = "g \u00B7 h \u00B7 g\u207B\u00B9"
				title_lbl.add_theme_color_override("font_color", L4_RED)
			else:
				title_lbl.text = "\u2190 \u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0431\u0440\u0435\u043B\u043E\u043A"
				title_lbl.add_theme_color_override("font_color", L4_RED_DIM)

	# Clear history when switching subgroups
	_clear_history()
	_reset_slots()


## Update the progress label.
func update_progress() -> void:
	if _progress_label == null or _cracking_mgr == null:
		return
	var p: Dictionary = _cracking_mgr.get_progress()
	var normal: int = p.get("normal_count", 0)
	var cracked: int = p.get("cracked_count", 0)
	_progress_label.text = "%d/%d  (\u26E8%d  \u2717%d)" % [
		p["classified"], p["total"], normal, cracked]
	if p["classified"] >= p["total"]:
		_progress_label.add_theme_color_override("font_color", L4_RED)
	else:
		_progress_label.add_theme_color_override("font_color", L4_RED_DIM)


## Show glow animation for confirmed normal.
func show_normal_confirmed() -> void:
	if _confirm_btn:
		_confirm_btn.text = "\u26E8 \u041D\u043E\u0440\u043C\u0430\u043B\u044C\u043D\u0430\u044F!"
		_confirm_btn.add_theme_color_override("font_color", L4_GREEN)
		var scene_root: Node = _find_scene_root()
		if scene_root:
			var tw: Tween = scene_root.create_tween()
			tw.tween_property(_confirm_btn, "modulate",
				Color(1.3, 1.5, 1.3, 1.0), 0.3)
			tw.tween_property(_confirm_btn, "modulate",
				Color(1.0, 1.0, 1.0, 1.0), 0.5)


## Show error animation for wrong normal claim.
func show_wrong_normal() -> void:
	if _confirm_btn:
		var scene_root: Node = _find_scene_root()
		if scene_root:
			var tw: Tween = scene_root.create_tween()
			tw.tween_property(_confirm_btn, "modulate",
				Color(1.5, 0.5, 0.5, 1.0), 0.2)
			tw.tween_property(_confirm_btn, "modulate",
				Color(1.0, 1.0, 1.0, 1.0), 0.4)


## Whether a crack animation is currently in progress.
func is_crack_animating() -> bool:
	return _crack_animating


## Cleanup the panel.
func cleanup() -> void:
	_sg_slots.clear()
	_cracking_mgr = null
	_room_state = null


# --- Internal ---

## Set which slot is actively waiting for input.
func _set_active_input(slot_id: String) -> void:
	_active_input = slot_id

	# Update slot border highlighting
	_set_slot_active_style(_g_slot, slot_id == "g")
	_set_slot_active_style(_h_slot, slot_id == "h")


## Update the crack button visibility: show when both g and h are filled.
func _update_crack_btn_visibility() -> void:
	if _crack_btn == null:
		return
	_crack_btn.visible = (_g_sym_id != "" and _h_sym_id != "" and not _crack_animating)


## Update a slot's active/inactive border style.
func _set_slot_active_style(slot: Panel, is_active: bool) -> void:
	if slot == null:
		return
	var s: StyleBoxFlat = StyleBoxFlat.new()
	if is_active:
		s.bg_color = SLOT_ACTIVE_BG
		s.border_color = L4_RED_GLOW
		for prop in ["border_width_left", "border_width_right",
					"border_width_top", "border_width_bottom"]:
			s.set(prop, 2)
		s.shadow_color = Color(1.0, 0.4, 0.3, 0.2)
		s.shadow_size = 4
	else:
		s.bg_color = SLOT_EMPTY_BG
		s.border_color = L4_RED_BORDER
		for prop in ["border_width_left", "border_width_right",
					"border_width_top", "border_width_bottom"]:
			s.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(prop, 6)
	slot.add_theme_stylebox_override("panel", s)


## Update a maneuver slot display with a filled key.
func _update_slot_display(slot: Panel, sym_id: String, filled: bool) -> void:
	if slot == null:
		return

	var val_lbl = slot.get_node_or_null("ValueLabel")
	var dot = slot.get_node_or_null("KeyDot")

	if filled and sym_id != "":
		var color: Color = _get_key_color(sym_id)
		var display_name: String = _cracking_mgr.get_name(sym_id) if _cracking_mgr else sym_id
		if val_lbl:
			val_lbl.text = display_name
			val_lbl.add_theme_color_override("font_color", color)
		if dot:
			dot.color = color

		# Update slot style to "filled"
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = SLOT_FILLED_BG
		s.border_color = Color(color.r, color.g, color.b, 0.6)
		for prop in ["border_width_left", "border_width_right",
					"border_width_top", "border_width_bottom"]:
			s.set(prop, 2)
		for prop in ["corner_radius_top_left", "corner_radius_top_right",
					"corner_radius_bottom_left", "corner_radius_bottom_right"]:
			s.set(prop, 6)
		slot.add_theme_stylebox_override("panel", s)
	else:
		if val_lbl:
			val_lbl.text = ""
			val_lbl.add_theme_color_override("font_color", Color(0.5, 0.4, 0.4, 0.5))
		if dot:
			dot.color = Color(0.3, 0.2, 0.2, 0.3)


## Reset all three slots to empty.
func _reset_slots() -> void:
	_g_sym_id = ""
	_h_sym_id = ""

	# Reset g slot
	_clear_slot_display(_g_slot, "\u2295")
	# Reset h slot
	_clear_slot_display(_h_slot, "\u2295")
	# Reset g⁻¹ slot
	_clear_slot_display(_ginv_slot, "Авто")

	_set_active_input("g")
	_update_crack_btn_visibility()


## Clear a single slot's visual display.
func _clear_slot_display(slot: Panel, hint_text: String) -> void:
	if slot == null:
		return
	var val_lbl = slot.get_node_or_null("ValueLabel")
	if val_lbl:
		val_lbl.text = hint_text
		val_lbl.add_theme_color_override("font_color", Color(0.5, 0.4, 0.4, 0.5))
	var dot = slot.get_node_or_null("KeyDot")
	if dot:
		dot.color = Color(0.3, 0.2, 0.2, 0.3)


## Flash the maneuver zone green (stayed in) or red (escaped).
func _flash_maneuver_zone(stayed_in: bool) -> void:
	if _maneuver_zone == null:
		return
	var scene_root: Node = _find_scene_root()
	if scene_root == null:
		return

	var flash_color: Color
	if stayed_in:
		flash_color = Color(0.3, 1.0, 0.4, 0.15)
	else:
		flash_color = Color(1.0, 0.3, 0.2, 0.2)

	var flash_style: StyleBoxFlat = StyleBoxFlat.new()
	flash_style.bg_color = flash_color
	flash_style.border_color = Color(0, 0, 0, 0)
	_maneuver_zone.add_theme_stylebox_override("panel", flash_style)

	var tw: Tween = scene_root.create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(_reset_maneuver_bg)


func _reset_maneuver_bg() -> void:
	if _maneuver_zone == null:
		return
	var mz_style: StyleBoxFlat = StyleBoxFlat.new()
	mz_style.bg_color = Color(0.04, 0.02, 0.02, 0.5)
	mz_style.border_color = Color(0, 0, 0, 0)
	_maneuver_zone.add_theme_stylebox_override("panel", mz_style)


## Add an entry to the test history list.
func _add_history_entry(g_name: String, h_name: String,
		r_name: String, stayed_in: bool) -> void:
	if _history_list == null:
		return

	var entry: Label = Label.new()
	entry.add_theme_font_size_override("font_size", 8)
	if stayed_in:
		entry.text = "%s\u00B7%s\u00B7%s\u207B\u00B9=%s \u2208H" % [g_name, h_name, g_name, r_name]
		entry.add_theme_color_override("font_color", L4_GREEN_DIM)
	else:
		entry.text = "%s\u00B7%s\u00B7%s\u207B\u00B9=%s \u2209H" % [g_name, h_name, g_name, r_name]
		entry.add_theme_color_override("font_color", L4_RED_DIM)
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.custom_minimum_size = Vector2(0, 12)
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_history_list.add_child(entry)

	# Auto-scroll to bottom
	if _history_scroll:
		_history_scroll.call_deferred("set_v_scroll", 99999)


## Clear test history display.
func _clear_history() -> void:
	if _history_list == null:
		return
	for child in _history_list.get_children():
		child.queue_free()

	if _result_equation:
		_result_equation.text = ""
	if _result_label:
		_result_label.text = ""


# --- Event handlers ---

func _on_slot_clicked(event: InputEvent, slot_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	if _cracking_mgr == null:
		return
	if _cracking_mgr.get_active_subgroup_index() < 0:
		return  # No subgroup selected
	if _crack_animating:
		return  # Block during animation

	_set_active_input(slot_id)

	if slot_id == "g":
		g_slot_tapped.emit()
	elif slot_id == "h":
		h_slot_tapped.emit()


## Handle click on a keyring-style subgroup slot.
func _on_sg_slot_clicked(event: InputEvent, index: int, elements: Array) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _crack_animating:
		return

	# Toggle selection: deselect if already selected
	if _selected_sg_slot == index:
		_deselect_sg_slot()
		subgroup_selected.emit(-1)  # Deselect
	else:
		_deselect_sg_slot()
		_selected_sg_slot = index
		# Apply selected style (bright glow border)
		if index >= 0 and index < _sg_slots.size():
			var slot: Panel = _sg_slots[index]
			var s: StyleBoxFlat = StyleBoxFlat.new()
			s.bg_color = Color(0.14, 0.07, 0.04, 0.95)
			s.border_color = L4_RED_GLOW
			for prop in ["border_width_left", "border_width_right",
						"border_width_top", "border_width_bottom"]:
				s.set(prop, 3)
			for prop in ["corner_radius_top_left", "corner_radius_top_right",
						"corner_radius_bottom_left", "corner_radius_bottom_right"]:
				s.set(prop, 5)
			s.shadow_color = Color(0.9, 0.35, 0.3, 0.3)
			s.shadow_size = 6
			slot.add_theme_stylebox_override("panel", s)
		subgroup_selected.emit(index)


## Deselect the currently selected subgroup slot.
func _deselect_sg_slot() -> void:
	# Refresh list to restore styles (simplest way)
	_selected_sg_slot = -1


## Handle "Попытаться взломать" button press.
func _on_crack_btn_pressed() -> void:
	if _g_sym_id == "" or _h_sym_id == "":
		return
	if _crack_animating:
		return
	# Lock UI during animation
	_crack_animating = true
	_crack_btn.visible = false
	# Emit signal — controller will run the animated sequence
	crack_requested.emit(_g_sym_id, _h_sym_id)


func _on_confirm_normal_pressed() -> void:
	if _crack_animating:
		return
	confirm_normal_requested.emit()


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


func _find_sym_id_for_perm(perm: Permutation) -> String:
	if _cracking_mgr == null:
		return ""
	var all_ids: Array[String] = _cracking_mgr.get_all_sym_ids()
	for sid in all_ids:
		var p: Permutation = _cracking_mgr.get_perm(sid)
		if p != null and p.equals(perm):
			return sid
	return ""


## Find the scene root for creating tweens.
func _find_scene_root() -> Node:
	var node: Node = self
	while node != null:
		if node is Node2D:
			return node
		node = node.get_parent()
	return get_tree().current_scene if get_tree() else null
