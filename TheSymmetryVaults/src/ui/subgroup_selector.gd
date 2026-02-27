class_name SubgroupSelector
extends PanelContainer
## SubgroupSelector — Enhanced panel for selecting keys and finding subgroups.
##
## Wraps InnerDoorPanel with visual improvements:
## - Styled dark panel with bronze/gold border
## - Each key has a mini permutation diagram (arrows showing where nodes go)
## - "ПРОВЕРИТЬ НАБОР" button checks if selected keys form a subgroup
## - Visual feedback: green for valid subgroup, red + diagnostic for invalid
## - Found subgroups panel with progress tracking
##
## No doors, no locks — pure subgroup discovery.

signal subgroup_validated(is_valid: bool, selected_indices: Array)
signal subgroup_found_signal(sg_name: String, selected_indices: Array)

const _InnerDoorPanelClass = preload("res://src/game/inner_door_panel.gd")

# --- State ---
var _inner_panel: _InnerDoorPanelClass = null   # The logic panel
var _key_ring: KeyRing = null
var _level_scene = null
var _doors_data: Array = []
var _subgroups_data: Array = []
var _mini_diagrams: Array = []            # Array of Control nodes for key diagrams

# --- UI Nodes ---
var _scroll: ScrollContainer
var _content: VBoxContainer
var _title_label: Label
var _progress_label: Label
var _found_section: VBoxContainer
var _keys_section: VBoxContainer
var _check_button: Button
var _status_label: Label
var _key_checkboxes: Array = []           # Array[CheckBox]
var _selected_indices: Array = []

# --- Visual constants ---
const PANEL_WIDTH := 360
const PANEL_MAX_HEIGHT := 420
const MINI_DIAGRAM_SIZE := 28.0


func _ready() -> void:
	_build_panel_style()


func setup(doors_data: Array, subgroups_data: Array, key_ring_ref: KeyRing, level_scene_ref) -> void:
	_doors_data = doors_data.duplicate()
	_subgroups_data = subgroups_data.duplicate()
	_key_ring = key_ring_ref
	_level_scene = level_scene_ref

	# Create the inner logic panel (hidden — we use it for logic only)
	_inner_panel = _InnerDoorPanelClass.new()
	_inner_panel.name = "InnerLogicPanel"
	_inner_panel.visible = false
	_inner_panel.setup(doors_data, subgroups_data, key_ring_ref, level_scene_ref)
	add_child(_inner_panel)

	# Forward signals from inner panel
	_inner_panel.subgroup_found.connect(_on_inner_subgroup_found)
	_inner_panel.subgroup_check_failed.connect(_on_inner_check_failed)

	_build_ui()


func _build_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.93)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_color = Color(0.55, 0.4, 0.2, 0.7)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	size = Vector2(PANEL_WIDTH, PANEL_MAX_HEIGHT)


func _build_ui() -> void:
	# Clear existing children (except inner panel)
	for child in get_children():
		if child != _inner_panel:
			child.queue_free()

	_scroll = ScrollContainer.new()
	_scroll.name = "SelectorScroll"
	_scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 24, 0)
	_scroll.size = Vector2(PANEL_WIDTH - 24, PANEL_MAX_HEIGHT - 20)
	add_child(_scroll)

	_content = VBoxContainer.new()
	_content.name = "SelectorContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)

	# Title
	_title_label = Label.new()
	_title_label.name = "SelectorTitle"
	_title_label.text = "Поиск подгрупп"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 0.95))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_title_label)

	# Progress counter
	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.add_theme_font_size_override("font_size", 13)
	_progress_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.9, 0.9))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_progress_label)
	_update_progress_label()

	# Found subgroups section
	var found_header := Label.new()
	found_header.name = "FoundHeader"
	found_header.text = "Найденные подгруппы:"
	found_header.add_theme_font_size_override("font_size", 12)
	found_header.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6, 0.8))
	_content.add_child(found_header)

	_found_section = VBoxContainer.new()
	_found_section.name = "FoundSection"
	_content.add_child(_found_section)
	_rebuild_found_display()

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	_content.add_child(sep)

	# Keys selection header
	var keys_header := Label.new()
	keys_header.name = "KeysHeader"
	keys_header.text = "Выберите ключи для набора:"
	keys_header.add_theme_font_size_override("font_size", 13)
	keys_header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.85))
	_content.add_child(keys_header)

	# Keys section (checkboxes + mini diagrams)
	_keys_section = VBoxContainer.new()
	_keys_section.name = "KeysSection"
	_content.add_child(_keys_section)
	_rebuild_key_checkboxes()

	# Check subgroup button
	_check_button = Button.new()
	_check_button.name = "CheckSubgroupBtn"
	_check_button.text = "ПРОВЕРИТЬ НАБОР"
	_check_button.add_theme_font_size_override("font_size", 14)
	_check_button.custom_minimum_size = Vector2(0, 36)
	_check_button.disabled = true
	_check_button.pressed.connect(_on_check_subgroup)
	_apply_button_style(_check_button, Color(0.15, 0.2, 0.35, 0.7), Color(0.4, 0.5, 0.8, 0.5))
	_content.add_child(_check_button)

	# Status label
	_status_label = Label.new()
	_status_label.name = "SelectorStatus"
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.55, 0.8))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 0)
	_content.add_child(_status_label)


func _apply_button_style(btn: Button, bg: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	btn.add_theme_stylebox_override("normal", style)

	var hover: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)


func _rebuild_found_display() -> void:
	if _found_section == null:
		return
	for child in _found_section.get_children():
		child.queue_free()

	if _inner_panel == null:
		return

	var target_subgroups: Array = _inner_panel._target_subgroups
	var found: Array = _inner_panel.found_subgroups

	for sg in target_subgroups:
		var sg_name: String = sg.get("name", "")
		var sg_desc: String = sg.get("description", sg_name)
		var elements: Array = sg.get("elements", [])
		var is_found: bool = sg_name in found

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 22)

		# Status icon
		var icon_label := Label.new()
		icon_label.text = "✅" if is_found else "⬜"
		icon_label.add_theme_font_size_override("font_size", 13)
		icon_label.custom_minimum_size = Vector2(22, 22)
		row.add_child(icon_label)

		# Info
		var info_label := Label.new()
		if is_found:
			var elements_str := "{%s}" % ", ".join(elements)
			info_label.text = "%s — %s" % [sg_desc, elements_str]
			info_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.9))
		else:
			info_label.text = "%s (порядок %d)" % [sg_desc, sg.get("order", 0)]
			info_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
		info_label.add_theme_font_size_override("font_size", 11)
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(info_label)

		_found_section.add_child(row)


func _update_progress_label() -> void:
	if _progress_label and _inner_panel:
		_progress_label.text = "Подгруппы: %d / %d" % [_inner_panel.get_opened_count(), _inner_panel.get_total_count()]
	elif _progress_label:
		_progress_label.text = "Подгруппы: 0 / 0"


func _rebuild_key_checkboxes() -> void:
	if _keys_section == null:
		return
	for child in _keys_section.get_children():
		child.queue_free()
	_key_checkboxes.clear()
	_mini_diagrams.clear()
	_selected_indices.clear()

	if _key_ring == null:
		return

	for i in range(_key_ring.count()):
		var row := HBoxContainer.new()
		row.name = "KeySelectRow_%d" % i
		row.custom_minimum_size = Vector2(0, 30)

		# Checkbox
		var cb := CheckBox.new()
		cb.name = "KeyCB_%d" % i
		var display_name := _get_key_name(i)
		cb.text = display_name
		cb.add_theme_font_size_override("font_size", 12)
		cb.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7, 0.9))
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb_index := i
		cb.toggled.connect(_on_key_checkbox_toggled.bind(cb_index))
		row.add_child(cb)
		_key_checkboxes.append(cb)

		# Mini permutation diagram
		var diagram := _create_mini_diagram(i)
		row.add_child(diagram)
		_mini_diagrams.append(diagram)

		_keys_section.add_child(row)

	_update_buttons()


func _create_mini_diagram(key_index: int) -> Control:
	## Create a mini diagram showing the permutation arrows.
	var diagram := Control.new()
	diagram.name = "MiniDiagram_%d" % key_index
	diagram.custom_minimum_size = Vector2(MINI_DIAGRAM_SIZE, MINI_DIAGRAM_SIZE)
	diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var perm: Permutation = _key_ring.get_key(key_index) if _key_ring and key_index < _key_ring.count() else null
	if perm == null:
		return diagram

	diagram.set_meta("mapping", Array(perm.mapping))
	diagram.draw.connect(_draw_mini_diagram.bind(diagram))
	return diagram


func _draw_mini_diagram(ctrl: Control) -> void:
	## Draw a mini permutation diagram on the given control.
	var mapping: Array = ctrl.get_meta("mapping", [])
	if mapping.is_empty():
		return

	var n: int = mapping.size()
	var center := Vector2(MINI_DIAGRAM_SIZE / 2.0, MINI_DIAGRAM_SIZE / 2.0)
	var radius := MINI_DIAGRAM_SIZE / 2.0 - 3.0

	var positions: Array[Vector2] = []
	for i in range(n):
		var angle := (TAU / n) * i - PI / 2.0
		positions.append(center + Vector2(cos(angle), sin(angle)) * radius)

	for i in range(n):
		var target: int = mapping[i]
		if target != i:
			var from_pt: Vector2 = positions[i]
			var to_pt: Vector2 = positions[target]
			ctrl.draw_line(from_pt, to_pt, Color(0.5, 0.7, 1.0, 0.6), 1.0)

	for i in range(n):
		var is_fixed: bool = mapping[i] == i
		var col := Color(0.4, 0.7, 0.4, 0.8) if is_fixed else Color(0.8, 0.6, 0.3, 0.9)
		ctrl.draw_circle(positions[i], 2.5, col)


# --- Event handlers ---

## Forward inner panel subgroup_found to our signal (replaces lambda).
func _on_inner_subgroup_found(sg_name: String) -> void:
	subgroup_found_signal.emit(sg_name, _selected_indices)

## No-op handler for inner panel check failure (replaces lambda).
func _on_inner_check_failed(_r) -> void:
	pass

## Checkbox toggled handler with bound index (replaces lambda).
func _on_key_checkbox_toggled(pressed: bool, index: int) -> void:
	_on_key_toggled(pressed, index)

## Reset checkbox font colors after validation feedback (replaces lambda).
func _reset_checkbox_colors() -> void:
	for cb in _key_checkboxes:
		if is_instance_valid(cb):
			cb.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7, 0.9))

func _on_key_toggled(pressed: bool, index: int) -> void:
	if pressed:
		if index not in _selected_indices:
			_selected_indices.append(index)
	else:
		_selected_indices.erase(index)
	_update_buttons()
	# Sync to inner panel
	if _inner_panel:
		_inner_panel.set_selected_keys(_selected_indices)


func _update_buttons() -> void:
	var has_selection := not _selected_indices.is_empty()
	var has_unfound := _inner_panel != null and _inner_panel.get_opened_count() < _inner_panel.get_total_count()

	if _check_button:
		_check_button.disabled = not has_selection or not has_unfound
		_check_button.text = "ПРОВЕРИТЬ НАБОР (%d)" % _selected_indices.size() if has_selection else "ПРОВЕРИТЬ НАБОР"


func _on_check_subgroup() -> void:
	if _key_ring == null or _selected_indices.is_empty():
		return

	# Sync selection to inner panel and trigger check
	if _inner_panel:
		_inner_panel.set_selected_keys(_selected_indices)
		_inner_panel._on_check_pressed()

	# Read result from inner panel state
	var result: Dictionary = _key_ring.check_subgroup(_selected_indices)
	var is_valid: bool = result.get("is_subgroup", false)

	subgroup_validated.emit(is_valid, _selected_indices.duplicate())

	if is_valid:
		# Check if it was actually a new target subgroup found
		_rebuild_found_display()
		_update_progress_label()
		_update_buttons()

		# Highlight checkboxes green
		for idx in _selected_indices:
			if idx < _key_checkboxes.size():
				_key_checkboxes[idx].add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.95))

		# Show appropriate status from inner panel
		if _inner_panel and _inner_panel._status_label:
			var msg: String = _inner_panel._status_label.text
			var col: Color = _inner_panel._status_label.get_theme_color("font_color")
			_show_status(msg, col)
	else:
		var reasons: Array = result.get("reasons", [])
		var msg := "Это не подгруппа. "
		if reasons.has("missing_identity"):
			msg += "Нет Тождества (e) — «ничего не делать» тоже ключ! Добавьте его в набор."
		elif reasons.has("missing_inverse"):
			var inv_example := _get_inverse_example_text()
			msg += "Не у всех ключей есть обратный. %s Каждый ключ должен иметь ОТМЕНУ!" % inv_example
		elif reasons.has("not_closed_composition"):
			var closure_example := _get_closure_example_text()
			msg += "Набор НЕ ЗАМКНУТ. %s Попробуйте добавить недостающий ключ!" % closure_example
		_show_status(msg, Color(1.0, 0.4, 0.3, 0.95))

	# Reset checkbox colors after delay
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(_reset_checkbox_colors)


func _get_closure_example_text() -> String:
	## Generate a specific example showing which composition fails.
	if _key_ring == null or _selected_indices.size() < 2:
		return "Комбинация двух ключей даёт ключ вне набора."

	for i in _selected_indices:
		for j in _selected_indices:
			if i >= _key_ring.count() or j >= _key_ring.count():
				continue
			var key_a: Permutation = _key_ring.get_key(i)
			var key_b: Permutation = _key_ring.get_key(j)
			var product: Permutation = key_a.compose(key_b)

			var found_in_subset := false
			for k in _selected_indices:
				if k >= _key_ring.count():
					continue
				var key_k: Permutation = _key_ring.get_key(k)
				if product.equals(key_k):
					found_in_subset = true
					break

			if not found_in_subset:
				var name_a := _get_key_name(i)
				var name_b := _get_key_name(j)
				var product_name := "?"
				for p in range(_key_ring.count()):
					if _key_ring.get_key(p).equals(product):
						product_name = _get_key_name(p)
						break
				return "Пример: [%s] + [%s] = [%s] — НЕ в наборе!" % [name_a, name_b, product_name]

	return ""


func _get_inverse_example_text() -> String:
	## Generate a specific example of a key missing its inverse.
	if _key_ring == null or _selected_indices.is_empty():
		return ""

	for i in _selected_indices:
		if i >= _key_ring.count():
			continue
		var key: Permutation = _key_ring.get_key(i)
		var inv: Permutation = key.inverse()

		var found_inv := false
		for j in _selected_indices:
			if j >= _key_ring.count():
				continue
			if _key_ring.get_key(j).equals(inv):
				found_inv = true
				break

		if not found_inv and not key.is_identity():
			var key_name := _get_key_name(i)
			var inv_name := "?"
			for p in range(_key_ring.count()):
				if _key_ring.get_key(p).equals(inv):
					inv_name = _get_key_name(p)
					break
			return "Пример: [%s] требует [%s] для отмены." % [key_name, inv_name]

	return ""


func _get_key_name(index: int) -> String:
	## Get display name for a key (delegates to ValidationManager).
	if _level_scene and _level_scene._validation_mgr:
		return _level_scene._validation_mgr.get_key_display_name(index)
	return "Ключ %d" % (index + 1)


func _show_status(text: String, color: Color) -> void:
	if _status_label:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", color)
		var tween := create_tween()
		tween.tween_interval(4.0)
		tween.tween_callback(_reset_status_label)


## Reset status label to default — used as tween callback (avoids lambda/Stack underflow).
func _reset_status_label() -> void:
	if _status_label:
		_status_label.text = ""
		_status_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.55, 0.8))


# --- Public API ---

func refresh_keys() -> void:
	## Called when KeyRing changes. Rebuild checkboxes.
	_rebuild_key_checkboxes()
	if _inner_panel:
		_inner_panel.refresh_keys()


func refresh_found() -> void:
	## Called after subgroup found. Rebuild found list.
	_rebuild_found_display()
	_update_progress_label()
	_update_buttons()


func is_all_doors_opened() -> bool:
	return _inner_panel.is_all_doors_opened() if _inner_panel else false


func get_opened_count() -> int:
	return _inner_panel.get_opened_count() if _inner_panel else 0


func get_total_count() -> int:
	return _inner_panel.get_total_count() if _inner_panel else 0


func get_state() -> Dictionary:
	## Serializable state for Agent Bridge.
	var base := _inner_panel.get_state() if _inner_panel else {}
	base["selected_keys"] = _selected_indices.duplicate()
	return base


func set_selected_keys(indices: Array) -> void:
	## Programmatic selection (Agent Bridge).
	_selected_indices.clear()
	for idx in indices:
		_selected_indices.append(int(idx))
	# Update checkboxes
	for i in range(_key_checkboxes.size()):
		_key_checkboxes[i].set_pressed_no_signal(i in _selected_indices)
	_update_buttons()
	if _inner_panel:
		_inner_panel.set_selected_keys(_selected_indices)
