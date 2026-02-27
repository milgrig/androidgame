class_name InnerDoorPanel
extends VBoxContainer
## UI panel for the Subgroup Finding mechanic (Act 2, Levels 13-16).
## Player selects keys and checks if they form a subgroup.
## Found subgroups are tracked; win condition = all target subgroups found.
## No doors, no locks — pure subgroup discovery.

signal subgroup_found(sg_name: String)
signal subgroup_check_failed(reason: Dictionary)

# ── State ──
var subgroups_data: Array = []            # From level JSON subgroups[]
var found_subgroups: Array = []           # Names of found subgroups (target ones)
var _target_subgroups: Array = []         # Subgroup dicts where is_inner_door=true
var selected_key_indices: Array = []      # Checked key indices

# ── References ──
var key_ring: KeyRing = null
var level_scene = null                    # LevelScene reference (untyped to avoid circular)

# ── UI Elements ──
var _key_checkboxes: Array = []           # Array[CheckBox]
var _check_button: Button = null
var _status_label: Label = null
var _key_container: VBoxContainer = null
var _progress_label: Label = null
var _found_container: VBoxContainer = null
var _found_labels: Dictionary = {}        # sg_name -> Label


func setup(p_doors: Array, p_subgroups: Array, p_key_ring: KeyRing, p_level_scene) -> void:
	subgroups_data = p_subgroups.duplicate()
	key_ring = p_key_ring
	level_scene = p_level_scene

	# Build target subgroups list (is_inner_door = true)
	_target_subgroups.clear()
	found_subgroups.clear()
	for sg in subgroups_data:
		if sg.get("is_inner_door", false):
			_target_subgroups.append(sg)

	_build_ui()


func _build_ui() -> void:
	# Panel title
	var title := Label.new()
	title.name = "SubgroupPanelTitle"
	title.text = "Поиск подгрупп"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 0.9))
	add_child(title)

	# Progress counter
	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.add_theme_font_size_override("font_size", 13)
	_progress_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.9, 0.9))
	add_child(_progress_label)
	_update_progress_label()

	# Found subgroups section
	var found_title := Label.new()
	found_title.name = "FoundSubgroupsTitle"
	found_title.text = "Найденные подгруппы:"
	found_title.add_theme_font_size_override("font_size", 12)
	found_title.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6, 0.8))
	add_child(found_title)

	_found_container = VBoxContainer.new()
	_found_container.name = "FoundSubgroupsContainer"
	add_child(_found_container)
	_rebuild_found_list()

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	add_child(sep)

	# Key selection area
	var keys_title := Label.new()
	keys_title.name = "KeysSelectionTitle"
	keys_title.text = "Выберите ключи:"
	keys_title.add_theme_font_size_override("font_size", 13)
	keys_title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.8))
	add_child(keys_title)

	_key_container = VBoxContainer.new()
	_key_container.name = "KeyCheckboxContainer"
	add_child(_key_container)

	# Check button (replaces "ОТКРЫТЬ ДВЕРЬ")
	_check_button = Button.new()
	_check_button.name = "CheckSubgroupButton"
	_check_button.text = "ПРОВЕРИТЬ НАБОР"
	_check_button.add_theme_font_size_override("font_size", 14)
	_check_button.disabled = true
	_check_button.pressed.connect(_on_check_pressed)
	add_child(_check_button)

	# Status label
	_status_label = Label.new()
	_status_label.name = "SubgroupStatusLabel"
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.55, 0.8))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status_label)

	_rebuild_key_checkboxes()


func _rebuild_found_list() -> void:
	if _found_container == null:
		return
	for child in _found_container.get_children():
		child.queue_free()
	_found_labels.clear()

	for sg in _target_subgroups:
		var sg_name: String = sg.get("name", "")
		var sg_display: String = sg.get("description", sg_name)
		var elements: Array = sg.get("elements", [])
		var is_found: bool = sg_name in found_subgroups

		var label := Label.new()
		label.name = "SG_" + sg_name
		var elements_str := "{%s}" % ", ".join(elements)
		if is_found:
			label.text = "✅ %s — %s" % [sg_display, elements_str]
			label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.9))
		else:
			label.text = "⬜ %s (порядок %d)" % [sg_display, sg.get("order", 0)]
			label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
		label.add_theme_font_size_override("font_size", 11)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_found_container.add_child(label)
		_found_labels[sg_name] = label


func _update_progress_label() -> void:
	if _progress_label:
		_progress_label.text = "Подгруппы: %d / %d" % [found_subgroups.size(), _target_subgroups.size()]


func refresh_keys() -> void:
	## Called when KeyRing changes (new key found). Rebuilds key checkboxes.
	_rebuild_key_checkboxes()


func _rebuild_key_checkboxes() -> void:
	if _key_container == null:
		return
	# Clear existing
	for child in _key_container.get_children():
		child.queue_free()
	_key_checkboxes.clear()
	selected_key_indices.clear()

	if key_ring == null:
		return

	for i in range(key_ring.count()):
		var cb := CheckBox.new()
		cb.name = "KeyCB_%d" % i
		# Get display name via ValidationManager
		var display_name: String = _get_key_display_name(i)
		cb.text = display_name
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(_on_key_toggled.bind(i))
		_key_container.add_child(cb)
		_key_checkboxes.append(cb)

	_update_check_button_state()


func _on_key_toggled(pressed: bool, index: int) -> void:
	if pressed:
		if index not in selected_key_indices:
			selected_key_indices.append(index)
	else:
		selected_key_indices.erase(index)
	_update_check_button_state()


func _update_check_button_state() -> void:
	if _check_button == null:
		return
	var has_unfound := found_subgroups.size() < _target_subgroups.size()
	_check_button.disabled = selected_key_indices.is_empty() or not has_unfound
	_check_button.text = "ПРОВЕРИТЬ НАБОР (%d ключей)" % selected_key_indices.size() if not selected_key_indices.is_empty() else "ПРОВЕРИТЬ НАБОР"


func _on_check_pressed() -> void:
	if key_ring == null or selected_key_indices.is_empty():
		return

	# Check if selected keys form a valid subgroup
	var result: Dictionary = key_ring.check_subgroup(selected_key_indices)

	if not result["is_subgroup"]:
		# NOT a subgroup — diagnostic feedback
		var reason := _build_failure_reason(result)
		subgroup_check_failed.emit(reason)
		_show_failure_feedback(reason)
		return

	# IS a subgroup — check which target subgroup it matches
	var matched_sg: Dictionary = _find_matching_target_subgroup()

	if matched_sg.is_empty():
		# Valid subgroup but not a target one
		_status_label.text = "Это подгруппа, но не из тех, что нужно найти."
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3, 0.9))
		var tween := create_tween()
		tween.tween_interval(3.0)
		tween.tween_callback(_clear_status_label)
		return

	var sg_name: String = matched_sg.get("name", "")

	# Check if already found
	if sg_name in found_subgroups:
		_status_label.text = "Этот набор уже найден!"
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 0.9))
		var tween := create_tween()
		tween.tween_interval(2.0)
		tween.tween_callback(_clear_status_label)
		return

	# New subgroup found!
	found_subgroups.append(sg_name)
	subgroup_found.emit(sg_name)
	_show_success_feedback(matched_sg)
	_rebuild_found_list()
	_update_progress_label()
	_update_check_button_state()


func _find_matching_target_subgroup() -> Dictionary:
	## Check if the selected keys match any target subgroup.
	for sg in _target_subgroups:
		var sg_name: String = sg.get("name", "")
		if _matches_target_subgroup(sg_name):
			return sg
	return {}


func _matches_target_subgroup(sg_name: String) -> bool:
	## Check if the selected keys match the target subgroup elements.
	var target_sg: Dictionary = {}
	for sg in subgroups_data:
		if sg.get("name", "") == sg_name:
			target_sg = sg
			break
	if target_sg.is_empty():
		return false

	var target_element_ids: Array = target_sg.get("elements", [])
	if selected_key_indices.size() != target_element_ids.size():
		return false

	# Get target permutations from level data
	if level_scene == null:
		return false
	var target_perms: Dictionary = level_scene.target_perms

	# Build the set of selected rebased permutations
	var selected_rebased: Array = []  # Array[Permutation]
	var rebase_inv: Permutation = level_scene._validation_mgr.rebase_inverse if level_scene and level_scene._validation_mgr else null
	for idx in selected_key_indices:
		if idx >= 0 and idx < key_ring.count():
			var perm: Permutation = key_ring.get_key(idx)
			var rebased: Permutation = perm
			if rebase_inv != null:
				rebased = perm.compose(rebase_inv)
			selected_rebased.append(rebased)

	# Check that each target element is in the selected set
	for elem_id in target_element_ids:
		var target_p: Permutation = target_perms.get(elem_id)
		if target_p == null:
			return false
		var found_match := false
		for sel_p in selected_rebased:
			if sel_p.equals(target_p):
				found_match = true
				break
		if not found_match:
			return false
	return true


func _build_failure_reason(result: Dictionary) -> Dictionary:
	var reasons: Array = result.get("reasons", [])

	if reasons.has("missing_identity"):
		return {"reason": "no_identity",
				"message": "Набор не содержит Тождество (e) — «ничего не делать» тоже ключ! Добавьте Тождество в набор."}

	if reasons.has("missing_inverse"):
		var example := _get_inverse_example()
		return {"reason": "no_inverses",
				"message": "Не у всех ключей есть обратный. %s Каждый ключ должен иметь ОТМЕНУ в наборе!" % example}

	if reasons.has("not_closed_composition"):
		var example := _get_closure_example()
		return {"reason": "not_closed",
				"message": "Набор НЕ ЗАМКНУТ. %s\n\nПопробуйте: добавьте недостающий ключ или уберите лишние." % example}

	return {"reason": "unknown", "message": "Это не подгруппа."}


func _get_closure_example() -> String:
	## Generate a specific example of a composition that gives a key outside the subset.
	if key_ring == null or selected_key_indices.size() < 2:
		return "Комбинация двух ключей даёт ключ вне набора!"

	for i in selected_key_indices:
		for j in selected_key_indices:
			if i >= key_ring.count() or j >= key_ring.count():
				continue
			var key_a: Permutation = key_ring.get_key(i)
			var key_b: Permutation = key_ring.get_key(j)
			var product: Permutation = key_a.compose(key_b)

			var found_in_subset := false
			for k in selected_key_indices:
				if k >= key_ring.count():
					continue
				var key_k: Permutation = key_ring.get_key(k)
				if product.equals(key_k):
					found_in_subset = true
					break

			if not found_in_subset:
				var name_a := _get_key_display_name(i)
				var name_b := _get_key_display_name(j)
				var product_name := "результат"
				for p in range(key_ring.count()):
					if key_ring.get_key(p).equals(product):
						product_name = _get_key_display_name(p)
						break
				return "Пример: [%s] + [%s] = [%s]\nНо [%s] НЕ в вашем наборе!" % [name_a, name_b, product_name, product_name]

	return "Комбинация двух ключей даёт ключ вне набора!"


func _get_inverse_example() -> String:
	## Generate a specific example of a key without its inverse.
	if key_ring == null or selected_key_indices.is_empty():
		return ""

	for i in selected_key_indices:
		if i >= key_ring.count():
			continue
		var key: Permutation = key_ring.get_key(i)
		var inv: Permutation = key.inverse()

		var found_inv := false
		for j in selected_key_indices:
			if j >= key_ring.count():
				continue
			var key_j: Permutation = key_ring.get_key(j)
			if inv.equals(key_j):
				found_inv = true
				break

		if not found_inv and not key.is_identity():
			var key_name := _get_key_display_name(i)
			var inv_name := "обратный ключ"
			for p in range(key_ring.count()):
				if key_ring.get_key(p).equals(inv):
					inv_name = _get_key_display_name(p)
					break
			return "Пример: [%s] нужен [%s] для отмены." % [key_name, inv_name]

	return ""


func _get_key_display_name(index: int) -> String:
	## Get display name for a key by index (delegates to ValidationManager)
	if level_scene and level_scene._validation_mgr:
		return level_scene._validation_mgr.get_key_display_name(index)
	return "Ключ %d" % (index + 1)


func _show_failure_feedback(reason: Dictionary) -> void:
	if _status_label:
		_status_label.text = reason.get("message", "Не подгруппа")
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 0.9))
		var tween := create_tween()
		tween.tween_interval(4.0)
		tween.tween_callback(_reset_status_label)


func _show_success_feedback(sg_data: Dictionary) -> void:
	var sg_name: String = sg_data.get("name", "")
	var sg_desc: String = sg_data.get("description", sg_name)
	var elements: Array = sg_data.get("elements", [])
	var elements_str := "{%s}" % ", ".join(elements)
	var msg := "Подгруппа найдена: %s — %s" % [sg_desc, elements_str]
	if _status_label:
		_status_label.text = msg
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.9))


func is_all_doors_opened() -> bool:
	## Backward compat: all target subgroups found = level complete.
	return found_subgroups.size() >= _target_subgroups.size()


func get_opened_count() -> int:
	return found_subgroups.size()


func get_total_count() -> int:
	return _target_subgroups.size()


func get_state() -> Dictionary:
	## Serializable state for Agent Bridge / save system.
	var target_names: Array = []
	for sg in _target_subgroups:
		target_names.append(sg.get("name", ""))
	return {
		"found_subgroups": found_subgroups.duplicate(),
		"target_subgroups": target_names,
		"selected_keys": selected_key_indices.duplicate(),
		"all_found": is_all_doors_opened(),
		"found_count": get_opened_count(),
		"total_count": get_total_count(),
	}


## Clear status label text — used as tween callback (avoids lambda/Stack underflow).
func _clear_status_label() -> void:
	if _status_label:
		_status_label.text = ""


## Reset status label to default style — used as tween callback (avoids lambda/Stack underflow).
func _reset_status_label() -> void:
	if _status_label:
		_status_label.text = ""
		_status_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.55, 0.8))


## Programmatic API: set selected keys (used by Agent Bridge)
func set_selected_keys(indices: Array) -> void:
	selected_key_indices.clear()
	for idx in indices:
		selected_key_indices.append(int(idx))
	# Update checkboxes to reflect selection
	for i in range(_key_checkboxes.size()):
		if i < _key_checkboxes.size():
			_key_checkboxes[i].set_pressed_no_signal(i in selected_key_indices)
	_update_check_button_state()
