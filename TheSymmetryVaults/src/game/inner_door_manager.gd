## InnerDoorManager — Manages Act 2 subgroup finding, events, and moment of understanding.

class_name InnerDoorManager
extends RefCounted

const InnerDoorVisualScene = preload("res://src/visual/inner_door_visual.gd")
const SubgroupSelectorScene = preload("res://src/ui/subgroup_selector.gd")
const InnerDoorPanelScene = preload("res://src/game/inner_door_panel.gd")

var panel = null          # InnerDoorPanel instance
var selector = null       # SubgroupSelector instance
var visuals: Array = []   # Array[InnerDoorVisual]
var first_ever_opened: bool = false


func setup(doors_data: Array, subgroups_list: Array, key_ring: KeyRing,
		level_scene: Node2D, hud_layer: CanvasLayer, edge_container: Node2D,
		level_data: Dictionary,
		on_opened: Callable, on_failed: Callable,
		on_selector_open: Callable, on_validated: Callable) -> void:
	panel = InnerDoorPanelScene.new()
	panel.name = "InnerDoorPanel"; panel.visible = false
	panel.setup(doors_data, subgroups_list, key_ring, level_scene)
	panel.subgroup_found.connect(on_opened)
	panel.subgroup_check_failed.connect(_on_panel_check_failed.bind(on_failed))
	hud_layer.add_child(panel)

	selector = SubgroupSelectorScene.new()
	selector.name = "SubgroupSelector"
	selector.position = Vector2(880, 360); selector.size = Vector2(360, 340)
	selector.setup(doors_data, subgroups_list, key_ring, level_scene)
	selector.subgroup_found_signal.connect(_on_selector_found.bind(on_selector_open))
	selector.subgroup_validated.connect(on_validated)
	hud_layer.add_child(selector)

	visuals.clear()
	var nodes_array: Array = level_data.get("graph", {}).get("nodes", [])
	for door in doors_data:
		var dv: Node2D = InnerDoorVisualScene.new()
		var req_sg: String = door.get("required_subgroup", "")
		var sg_order: int = 0
		for sg in subgroups_list:
			if sg.get("name", "") == req_sg: sg_order = sg.get("order", 0); break
		var centroid: Vector2 = Vector2.ZERO
		if nodes_array.size() > 0:
			for nd in nodes_array:
				var pa = nd.get("position", [0, 0])
				centroid += Vector2(pa[0], pa[1])
			centroid = centroid / float(nodes_array.size()) + Vector2(0, 60)
		dv.setup(door.get("id", ""), door.get("visual_hint", ""), sg_order, centroid)
		dv.door_clicked.connect(_on_door_visual_clicked)
		edge_container.add_child(dv); visuals.append(dv)
	first_ever_opened = GameManager.get_save_flag("first_inner_door_opened", false)


func cleanup() -> void:
	if panel: panel.queue_free(); panel = null
	if selector: selector.queue_free(); selector = null
	for dv in visuals:
		if is_instance_valid(dv): dv.queue_free()
	visuals.clear()


func on_door_opened(door_id: String, scene: Node2D, feedback_fx: FeedbackFX,
		crystals: Dictionary, edges: Array, hud_layer: CanvasLayer, camera) -> void:
	# door_id is now sg_name; find matching visual by required_subgroup
	for dv in visuals:
		if dv.door_id == door_id: dv.play_unlock_animation()
		else:
			# Also check if door's required_subgroup matches the sg_name
			pass
	if selector: selector.refresh_found()
	feedback_fx.play_valid_feedback(crystals.values(), edges)
	if not first_ever_opened:
		first_ever_opened = true
		GameManager.set_save_flag("first_inner_door_opened", true)
		_play_moment_of_understanding(door_id, scene, hud_layer, camera)
	else:
		var hl = hud_layer.get_node_or_null("HintLabel")
		if hl:
			hl.text = "Подгруппа найдена!"
			hl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.9)); hl.visible = true
			var tw: Tween = scene.create_tween(); tw.tween_interval(3.0)
			tw.tween_callback(_fade_hint_label.bind(hl))


func on_door_failed(door_id: String, crystals: Dictionary) -> void:
	for c in crystals.values():
		if c is CrystalNode: c.play_dim()
	for dv in visuals:
		if dv.door_id == door_id: dv.play_failure_animation()


func on_subgroup_validated(is_valid: bool, crystals: Dictionary) -> void:
	if is_valid:
		for c in crystals.values():
			if c is CrystalNode: c.play_flash()
	else:
		for dv in visuals:
			if dv.state == InnerDoorVisualScene.DoorState.LOCKED: dv.play_failure_animation()


func is_all_doors_opened() -> bool:
	return panel != null and panel.is_all_doors_opened()


func _on_door_visual_clicked(door_id: String) -> void:
	if selector:
		# Will be handled by scene — just highlight selector
		pass


func _play_moment_of_understanding(door_id: String, scene: Node2D,
		hud_layer: CanvasLayer, camera) -> void:
	var door_pos: Vector2 = Vector2.ZERO
	for dv in visuals:
		if dv.door_id == door_id: door_pos = dv.position; break
	if camera: camera.move_to(door_pos, 0.8)
	var ip: Panel = Panel.new(); ip.name = "MomentOfUnderstandingPanel"
	ip.position = Vector2(240, 500); ip.size = Vector2(800, 120)
	ip.modulate = Color(1, 1, 1, 0)
	ip.add_theme_stylebox_override("panel", HudBuilder.make_stylebox(
		Color(0.05, 0.04, 0.1, 0.95), 12, Color(0.85, 0.75, 0.3, 0.8), 2))
	for t in [["✨", 28, Color.WHITE, Vector2(20, 12), Vector2(40, 40)],
			["Вы нашли подгруппу!", 20, Color(1.0, 0.9, 0.4, 1.0), Vector2(70, 14), Vector2(700, 30)],
			["Эти ключи замкнуты — любая комбинация двух из них даёт третий.", 15, Color(0.8, 0.82, 0.9, 0.95), Vector2(70, 52), Vector2(700, 26)],
			["Это фундаментальная идея алгебры: часть структуры сама образует структуру.", 13, Color(0.65, 0.7, 0.8, 0.8), Vector2(70, 82), Vector2(700, 22)]]:
		HudBuilder.add_label(ip, "", t[0], t[1], t[2], t[3], t[4])
	hud_layer.add_child(ip)
	var tw: Tween = scene.create_tween()
	tw.tween_property(ip, "modulate", Color(1, 1, 1, 1), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(5.0); tw.tween_property(ip, "modulate", Color(1, 1, 1, 0), 0.8)
	tw.tween_callback(_free_node.bind(ip))


## Forward panel check failure to the on_failed callback (replaces lambda).
func _on_panel_check_failed(reason, on_failed: Callable) -> void:
	on_failed.call("", reason)

## Forward selector found signal to the on_selector_open callback (replaces lambda).
func _on_selector_found(sg_name: String, _si, on_selector_open: Callable) -> void:
	on_selector_open.call(sg_name, _si)

## Fade out a hint label (replaces lambda in tween_callback).
func _fade_hint_label(hl: Label) -> void:
	if is_instance_valid(hl):
		hl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5, 0.0))

## Free a node if still valid (replaces lambda in tween_callback).
func _free_node(node: Node) -> void:
	if is_instance_valid(node): node.queue_free()
