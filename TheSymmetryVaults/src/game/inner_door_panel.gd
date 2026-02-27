class_name InnerDoorPanel
extends VBoxContainer
## UI panel for the Inner Doors mechanic (Act 2, Levels 13-16).
## Displays doors, allows key selection via checkboxes, validates subgroup closure.
## Only visible when the level has inner_doors defined.

signal door_opened(door_id: String)
signal door_attempt_failed(door_id: String, reason: Dictionary)

# ── State ──
var doors_data: Array = []               # From level JSON mechanics.inner_doors[]
var subgroups_data: Array = []            # From level JSON subgroups[]
var door_states: Dictionary = {}          # door_id -> "locked" | "opened"
var selected_key_indices: Array = []      # Checked key indices

# ── References ──
var key_ring: KeyRing = null
var level_scene = null                    # LevelScene reference (untyped to avoid circular)

# ── UI Elements ──
var _door_labels: Dictionary = {}         # door_id -> Label
var _key_checkboxes: Array = []           # Array[CheckBox]
var _open_button: Button = null
var _status_label: Label = null
var _key_container: VBoxContainer = null
var _doors_container: VBoxContainer = null


func setup(p_doors: Array, p_subgroups: Array, p_key_ring: KeyRing, p_level_scene) -> void:
	doors_data = p_doors.duplicate()
	subgroups_data = p_subgroups.duplicate()
	key_ring = p_key_ring
	level_scene = p_level_scene

	# Initialize door states
	door_states.clear()
	for door in doors_data:
		door_states[door.get("id", "")] = "locked"

	_build_ui()


func _build_ui() -> void:
	# Panel title
	var title := Label.new()
	title.name = "DoorPanelTitle"
	title.text = "Внутренние двери"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 0.9))
	add_child(title)

	# Doors list
	_doors_container = VBoxContainer.new()
	_doors_container.name = "DoorsContainer"
	add_child(_doors_container)
	_rebuild_door_list()

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

	# Open button
	_open_button = Button.new()
	_open_button.name = "OpenDoorButton"
	_open_button.text = "ОТКРЫТЬ ДВЕРЬ"
	_open_button.add_theme_font_size_override("font_size", 14)
	_open_button.disabled = true
	_open_button.pressed.connect(_on_open_pressed)
	add_child(_open_button)

	# Status label
	_status_label = Label.new()
	_status_label.name = "DoorStatusLabel"
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.55, 0.8))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status_label)

	_rebuild_key_checkboxes()


func _rebuild_door_list() -> void:
	# Clear existing
	for child in _doors_container.get_children():
		child.queue_free()
	_door_labels.clear()

	for door in doors_data:
		var door_id: String = door.get("id", "")
		var req_sg_name: String = door.get("required_subgroup", "")

		# Find the subgroup info
		var sg_order: int = 0
		for sg in subgroups_data:
			if sg.get("name", "") == req_sg_name:
				sg_order = sg.get("order", 0)
				break

		var label := Label.new()
		label.name = "Door_" + door_id
		var state_icon: String = "🔒" if door_states.get(door_id, "locked") == "locked" else "✅"
		var hint: String = door.get("visual_hint", "")
		if hint.length() > 40:
			hint = hint.left(37) + "..."
		label.text = "%s %s (порядок %d)" % [state_icon, hint, sg_order]
		label.add_theme_font_size_override("font_size", 12)
		if door_states.get(door_id, "locked") == "opened":
			label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.9))
		else:
			label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 0.85))
		_doors_container.add_child(label)
		_door_labels[door_id] = label


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
		# Get display name from level scene
		var display_name: String = ""
		if level_scene and level_scene.has_method("_get_key_display_name"):
			display_name = level_scene._get_key_display_name(i)
		else:
			display_name = "Ключ %d" % i
		cb.text = display_name
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(_on_key_toggled.bind(i))
		_key_container.add_child(cb)
		_key_checkboxes.append(cb)

	_update_open_button_state()


func _on_key_toggled(pressed: bool, index: int) -> void:
	if pressed:
		if index not in selected_key_indices:
			selected_key_indices.append(index)
	else:
		selected_key_indices.erase(index)
	_update_open_button_state()


func _update_open_button_state() -> void:
	if _open_button == null:
		return
	# Enable open button only if at least 1 key is selected and there are locked doors
	var has_locked := false
	for door_id in door_states:
		if door_states[door_id] == "locked":
			has_locked = true
			break
	_open_button.disabled = selected_key_indices.is_empty() or not has_locked
	_open_button.text = "ОТКРЫТЬ ДВЕРЬ (%d ключей)" % selected_key_indices.size() if not selected_key_indices.is_empty() else "ОТКРЫТЬ ДВЕРЬ"


func _on_open_pressed() -> void:
	if key_ring == null or selected_key_indices.is_empty():
		return

	# Check if selected keys form a valid subgroup
	var result: Dictionary = key_ring.check_subgroup(selected_key_indices)

	if not result["is_subgroup"]:
		# NOT a subgroup — diagnostic feedback
		var reason := _build_failure_reason(result)
		# Try all doors and emit failure for the first locked one
		for door in doors_data:
			var door_id: String = door.get("id", "")
			if door_states.get(door_id, "locked") == "locked":
				door_attempt_failed.emit(door_id, reason)
				break
		_show_failure_feedback(reason)
		return

	# IS a subgroup — check which door(s) it matches
	var matched_door: Dictionary = {}
	for door in doors_data:
		var door_id: String = door.get("id", "")
		if door_states.get(door_id, "locked") != "locked":
			continue  # Already opened

		var req_sg_name: String = door.get("required_subgroup", "")
		if _matches_target_subgroup(req_sg_name):
			matched_door = door
			break

	if not matched_door.is_empty():
		# Correct subgroup found for a door!
		var door_id: String = matched_door.get("id", "")
		door_states[door_id] = "opened"
		door_opened.emit(door_id)
		_show_success_feedback(matched_door)
		_rebuild_door_list()
		_update_open_button_state()
	else:
		# Valid subgroup but doesn't match any locked door
		_status_label.text = "Это подгруппа, но не подходит ни к одной закрытой двери."
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3, 0.9))
		# Clear after delay
		var tween := create_tween()
		tween.tween_interval(3.0)
		tween.tween_callback(_clear_status_label)


func _matches_target_subgroup(sg_name: String) -> bool:
	## Check if the selected keys match the target subgroup elements.
	# Find the subgroup definition
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
	for idx in selected_key_indices:
		if idx >= 0 and idx < key_ring.count():
			var perm: Permutation = key_ring.get_key(idx)
			var rebased: Permutation = perm
			if level_scene._rebase_inverse != null:
				rebased = perm.compose(level_scene._rebase_inverse)
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
	var missing_elements: Array = result.get("missing_elements", [])

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

	# Try to find a concrete example
	for i in selected_key_indices:
		for j in selected_key_indices:
			if i >= key_ring.count() or j >= key_ring.count():
				continue
			var key_a: Permutation = key_ring.get_key(i)
			var key_b: Permutation = key_ring.get_key(j)
			var product: Permutation = key_a.compose(key_b)

			# Check if product is in selected subset
			var found_in_subset := false
			for k in selected_key_indices:
				if k >= key_ring.count():
					continue
				var key_k: Permutation = key_ring.get_key(k)
				if product.equals(key_k):
					found_in_subset = true
					break

			if not found_in_subset:
				# Found an example! Get display names
				var name_a := _get_key_display_name(i)
				var name_b := _get_key_display_name(j)
				# Try to find the product in all keys
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

	# Find a key without inverse
	for i in selected_key_indices:
		if i >= key_ring.count():
			continue
		var key: Permutation = key_ring.get_key(i)
		var inv: Permutation = key.inverse()

		# Check if inverse is in selected subset
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
			# Try to find inverse in all keys
			var inv_name := "обратный ключ"
			for p in range(key_ring.count()):
				if key_ring.get_key(p).equals(inv):
					inv_name = _get_key_display_name(p)
					break
			return "Пример: [%s] нужен [%s] для отмены." % [key_name, inv_name]

	return ""


func _get_key_display_name(index: int) -> String:
	## Get display name for a key by index (uses level_scene method if available)
	if level_scene and level_scene.has_method("_get_key_display_name"):
		return level_scene._get_key_display_name(index)
	return "Ключ %d" % (index + 1)


func _show_failure_feedback(reason: Dictionary) -> void:
	if _status_label:
		_status_label.text = reason.get("message", "Не подгруппа")
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 0.9))
		# Clear after delay
		var tween := create_tween()
		tween.tween_interval(4.0)
		tween.tween_callback(_reset_status_label)


func _show_success_feedback(door_data: Dictionary) -> void:
	var msg: String = door_data.get("unlock_message", "Дверь открыта!")
	if _status_label:
		_status_label.text = msg
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.9))


func is_all_doors_opened() -> bool:
	for door_id in door_states:
		if door_states[door_id] != "opened":
			return false
	return true


func get_opened_count() -> int:
	var count := 0
	for door_id in door_states:
		if door_states[door_id] == "opened":
			count += 1
	return count


func get_total_count() -> int:
	return doors_data.size()


func get_state() -> Dictionary:
	## Serializable state for Agent Bridge / save system.
	return {
		"doors": door_states.duplicate(),
		"selected_keys": selected_key_indices.duplicate(),
		"all_opened": is_all_doors_opened(),
		"opened_count": get_opened_count(),
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
	_update_open_button_state()
