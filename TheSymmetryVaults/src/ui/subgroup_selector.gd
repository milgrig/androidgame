class_name SubgroupSelector
extends PanelContainer
## SubgroupSelector — Enhanced panel for selecting keys and checking subgroups.
##
## Wraps InnerDoorPanel with visual improvements:
## - Styled dark panel with bronze/gold border
## - Each key has a mini permutation diagram (arrows showing where nodes go)
## - "ПРОВЕРИТЬ ПОДГРУППУ" button checks closure before opening
## - Visual feedback: green for valid subgroup, red + diagnostic for invalid
## - Integrates with InnerDoorVisual for on-field door animations
##
## This panel appears when the player clicks an InnerDoorVisual on the field,
## or is always visible in the HUD for Act 2 levels.

signal subgroup_validated(is_valid: bool, selected_indices: Array)
signal door_open_requested(door_id: String, selected_indices: Array)

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
var _doors_section: VBoxContainer
var _keys_section: VBoxContainer
var _check_button: Button
var _open_button: Button
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
	_inner_panel.door_opened.connect(func(did): door_open_requested.emit(did, _selected_indices))
	_inner_panel.door_attempt_failed.connect(func(_did, _r): pass)

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
	_title_label.text = "Внутренние двери"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 0.95))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_title_label)

	# Doors section
	_doors_section = VBoxContainer.new()
	_doors_section.name = "DoorsSection"
	_content.add_child(_doors_section)
	_rebuild_doors_display()

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	_content.add_child(sep)

	# Keys selection header
	var keys_header := Label.new()
	keys_header.name = "KeysHeader"
	keys_header.text = "Выберите ключи для подгруппы:"
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
	_check_button.text = "ПРОВЕРИТЬ ПОДГРУППУ"
	_check_button.add_theme_font_size_override("font_size", 13)
	_check_button.custom_minimum_size = Vector2(0, 32)
	_check_button.disabled = true
	_check_button.pressed.connect(_on_check_subgroup)
	_apply_button_style(_check_button, Color(0.15, 0.2, 0.35, 0.7), Color(0.4, 0.5, 0.8, 0.5))
	_content.add_child(_check_button)

	# Open door button
	_open_button = Button.new()
	_open_button.name = "OpenDoorBtn"
	_open_button.text = "ОТКРЫТЬ ДВЕРЬ"
	_open_button.add_theme_font_size_override("font_size", 14)
	_open_button.custom_minimum_size = Vector2(0, 36)
	_open_button.disabled = true
	_open_button.pressed.connect(_on_open_door)
	_apply_button_style(_open_button, Color(0.2, 0.15, 0.08, 0.7), Color(0.75, 0.6, 0.2, 0.6))
	_content.add_child(_open_button)

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

	var hover := style.duplicate()
	hover.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)


func _rebuild_doors_display() -> void:
	if _doors_section == null:
		return
	for child in _doors_section.get_children():
		child.queue_free()

	var door_states: Dictionary = _inner_panel.door_states if _inner_panel else {}

	for door in _doors_data:
		var did: String = door.get("id", "")
		var hint: String = door.get("visual_hint", "")
		var req_sg: String = door.get("required_subgroup", "")

		# Find subgroup order
		var sg_order: int = 0
		for sg in _subgroups_data:
			if sg.get("name", "") == req_sg:
				sg_order = sg.get("order", 0)
				break

		var is_opened: bool = door_states.get(did, "locked") == "opened"

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 24)

		# Icon
		var icon_label := Label.new()
		icon_label.text = "✅" if is_opened else "🔒"
		icon_label.add_theme_font_size_override("font_size", 14)
		icon_label.custom_minimum_size = Vector2(24, 24)
		row.add_child(icon_label)

		# Door info
		var info_label := Label.new()
		var truncated_hint := hint if hint.length() <= 35 else hint.left(32) + "..."
		info_label.text = "%s (порядок %d)" % [truncated_hint, sg_order]
		info_label.add_theme_font_size_override("font_size", 12)
		if is_opened:
			info_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.9))
		else:
			info_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 0.85))
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_label)

		_doors_section.add_child(row)


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
		var display_name := ""
		if _level_scene and _level_scene.has_method("_get_key_display_name"):
			display_name = _level_scene._get_key_display_name(i)
		else:
			display_name = "Ключ %d" % (i + 1)
		cb.text = display_name
		cb.add_theme_font_size_override("font_size", 12)
		cb.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7, 0.9))
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb_index := i
		cb.toggled.connect(func(pressed): _on_key_toggled(pressed, cb_index))
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

	# Draw the diagram via _draw callback
	var perm: Permutation = _key_ring.get_key(key_index) if _key_ring and key_index < _key_ring.count() else null
	if perm == null:
		return diagram

	# Store mapping data on the control for drawing
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

	# Draw node positions in a circle
	var positions: Array[Vector2] = []
	for i in range(n):
		var angle := (TAU / n) * i - PI / 2.0
		positions.append(center + Vector2(cos(angle), sin(angle)) * radius)

	# Draw arrows for non-fixed points
	for i in range(n):
		var target: int = mapping[i]
		if target != i:
			var from_pt := positions[i]
			var to_pt := positions[target]
			ctrl.draw_line(from_pt, to_pt, Color(0.5, 0.7, 1.0, 0.6), 1.0)

	# Draw nodes
	for i in range(n):
		var is_fixed: bool = mapping[i] == i
		var col := Color(0.4, 0.7, 0.4, 0.8) if is_fixed else Color(0.8, 0.6, 0.3, 0.9)
		ctrl.draw_circle(positions[i], 2.5, col)


# --- Event handlers ---

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
	var has_locked_door := false
	if _inner_panel:
		for did in _inner_panel.door_states:
			if _inner_panel.door_states[did] == "locked":
				has_locked_door = true
				break

	if _check_button:
		_check_button.disabled = not has_selection
		_check_button.text = "ПРОВЕРИТЬ ПОДГРУППУ (%d)" % _selected_indices.size() if has_selection else "ПРОВЕРИТЬ ПОДГРУППУ"

	if _open_button:
		_open_button.disabled = true  # Only enabled after successful check
		_open_button.text = "ОТКРЫТЬ ДВЕРЬ"


func _on_check_subgroup() -> void:
	if _key_ring == null or _selected_indices.is_empty():
		return

	var result: Dictionary = _key_ring.check_subgroup(_selected_indices)
	var is_valid: bool = result.get("is_subgroup", false)

	subgroup_validated.emit(is_valid, _selected_indices.duplicate())

	if is_valid:
		_show_status("✓ Это подгруппа! Можете открыть дверь.", Color(0.3, 1.0, 0.4, 0.95))
		if _open_button:
			_open_button.disabled = false
		# Highlight checkboxes green
		for idx in _selected_indices:
			if idx < _key_checkboxes.size():
				_key_checkboxes[idx].add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.95))
	else:
		var reasons: Array = result.get("reasons", [])
		var msg := "✗ Это не подгруппа. "
		if reasons.has("missing_identity"):
			msg += "Нет Тождества (e) — «ничего не делать» тоже ключ! Добавьте его в набор."
		elif reasons.has("missing_inverse"):
			var inv_example := _get_inverse_example_text()
			msg += "Не у всех ключей есть обратный. %s Каждый ключ должен иметь ОТМЕНУ!" % inv_example
		elif reasons.has("not_closed_composition"):
			var closure_example := _get_closure_example_text()
			msg += "Набор НЕ ЗАМКНУТ. %s Попробуйте добавить недостающий ключ!" % closure_example
		_show_status(msg, Color(1.0, 0.4, 0.3, 0.95))
		if _open_button:
			_open_button.disabled = true


func _get_closure_example_text() -> String:
	## Generate a specific example showing which composition fails.
	if _key_ring == null or _selected_indices.size() < 2:
		return "Комбинация двух ключей даёт ключ вне набора."

	# Try to find a concrete counterexample
	for i in _selected_indices:
		for j in _selected_indices:
			if i >= _key_ring.count() or j >= _key_ring.count():
				continue
			var key_a: Permutation = _key_ring.get_key(i)
			var key_b: Permutation = _key_ring.get_key(j)
			var product: Permutation = key_a.compose(key_b)

			# Check if product is in selected subset
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

		# Check if inverse is in subset
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
	## Get display name for a key.
	if _level_scene and _level_scene.has_method("_get_key_display_name"):
		return _level_scene._get_key_display_name(index)
	return "Ключ %d" % (index + 1)


func _on_open_door() -> void:
	if _inner_panel == null:
		return
	# Sync selection and trigger open
	_inner_panel.set_selected_keys(_selected_indices)
	_inner_panel._on_open_pressed()
	# Refresh displays
	_rebuild_doors_display()
	_update_buttons()
	# Reset checkbox colors
	for cb in _key_checkboxes:
		cb.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7, 0.9))


func _show_status(text: String, color: Color) -> void:
	if _status_label:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", color)
		# Auto-clear after delay
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


func refresh_doors() -> void:
	_rebuild_doors_display()


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
