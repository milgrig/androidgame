## LevelScene — Main level orchestrator.
##
## Delegates to:
## - ShuffleManager: shuffling, initial positions, seed
## - SwapManager: drag-and-drop, perform_swap, arrangement tracking
## - ValidationManager: permutation validation, target matching, key ring
##
## This class handles: load, build, connect managers, HUD, UI events.

class_name LevelScene
extends Node2D

# Preload required classes
const EchoHintSystem = preload("res://src/game/echo_hint_system.gd")
const TargetPreviewDraw = preload("res://src/visual/target_preview_draw.gd")
const InnerDoorVisualScene = preload("res://src/visual/inner_door_visual.gd")
const SubgroupSelectorScene = preload("res://src/ui/subgroup_selector.gd")
const InnerDoorPanelScene = preload("res://src/game/inner_door_panel.gd")

# --- Signals for game state integration ---
signal swap_performed(permutation: Array)
signal symmetry_found(symmetry_id: String, mapping: Array)
signal level_completed(level_id: String)
signal invalid_attempt(mapping: Array)

# --- Managers ---
var _shuffle_mgr: ShuffleManager = ShuffleManager.new()
var _swap_mgr: SwapManager = SwapManager.new()
var _validation_mgr: ValidationManager = ValidationManager.new()

# --- Scene references ---
var crystal_container: Node2D
var edge_container: Node2D
var feedback_fx: FeedbackFX
var camera: CameraController
var hud_layer: CanvasLayer
var target_preview: Control

# --- Level Data ---
var level_data: Dictionary = {}
var level_id: String = ""

# --- Crystal Management ---
var crystals: Dictionary = {}
var edges: Array[EdgeRenderer] = []
var crystal_positions: Dictionary = {}

# --- Public state (proxied from managers for backward compat) ---
var current_arrangement: Array[int]:
	get: return _shuffle_mgr.current_arrangement
	set(v): _shuffle_mgr.current_arrangement = v
var key_ring: KeyRing:
	get: return _validation_mgr.key_ring
var crystal_graph: CrystalGraph:
	get: return _validation_mgr.crystal_graph
var target_perms: Dictionary:
	get: return _validation_mgr.target_perms
var target_perm_names: Dictionary:
	get: return _validation_mgr.target_perm_names
var target_perm_descriptions: Dictionary:
	get: return _validation_mgr.target_perm_descriptions
var total_symmetries: int:
	get: return _validation_mgr.total_symmetries

# --- Agent Mode ---
var agent_mode: bool = false

# --- Tutorial / Onboarding State ---
var _instruction_panel_visible: bool = false
var _first_symmetry_celebrated: bool = false
var _swap_count: int:
	get: return _swap_mgr.swap_count
	set(v): _swap_mgr.swap_count = v

# --- Cayley / Combine Keys ---
var _show_cayley_button: bool = false
var _combine_mode: bool = false
var _combine_first_index: int = -1

# --- Generators Hint ---
var _show_generators_hint: bool = false

# --- Repeat Key (proxied) ---
var _active_repeat_key_index: int:
	get: return _swap_mgr.active_repeat_key_index
	set(v): _swap_mgr.active_repeat_key_index = v
var _repeat_animating: bool:
	get: return _swap_mgr.repeat_animating
	set(v): _swap_mgr.repeat_animating = v

# --- Shuffled Start (proxied) ---
var _shuffle_seed: int:
	get: return _shuffle_mgr.shuffle_seed
var _initial_arrangement: Array[int]:
	get: return _shuffle_mgr.initial_arrangement
var _identity_arrangement: Array[int]:
	get: return _shuffle_mgr.identity_arrangement
var _identity_found: bool:
	get: return _validation_mgr.identity_found
	set(v): _validation_mgr.identity_found = v

# --- First-key-is-identity rebasing (proxied) ---
var _first_key_relabeled: bool:
	get: return _validation_mgr.first_key_relabeled
	set(v): _validation_mgr.first_key_relabeled = v
var _rebase_inverse: Permutation:
	get: return _validation_mgr.rebase_inverse
	set(v): _validation_mgr.rebase_inverse = v

# --- Inner Doors (Act 2) ---
var _inner_door_panel = null
var _subgroup_selector = null
var _inner_door_visuals: Array = []
var _first_door_ever_opened: bool = false

# --- Echo Hint System ---
var echo_hint_system = null

# --- Preloaded scenes ---
var crystal_scene = preload("res://src/visual/crystal_node.tscn")
var edge_scene = preload("res://src/visual/edge_renderer.tscn")


func _ready() -> void:
	_setup_scene_structure()
	if level_data.is_empty():
		if GameManager.current_hall_id != "":
			var hall_path := GameManager.get_level_path(GameManager.current_hall_id)
			if hall_path != "":
				load_level_from_file(hall_path)
			else:
				push_warning("LevelScene: No level file for hall '%s'" % GameManager.current_hall_id)
				load_level_from_file("res://data/levels/act1/level_01.json")
		else:
			var saved_id := "act%d_level%02d" % [GameManager.current_act, GameManager.current_level]
			var saved_path := GameManager.get_level_path(saved_id)
			if saved_path != "":
				load_level_from_file(saved_path)
			else:
				load_level_from_file("res://data/levels/act1/level_01.json")


func _setup_scene_structure() -> void:
	edge_container = Node2D.new()
	edge_container.name = "EdgeContainer"
	add_child(edge_container)
	crystal_container = Node2D.new()
	crystal_container.name = "CrystalContainer"
	add_child(crystal_container)
	feedback_fx = FeedbackFX.new()
	feedback_fx.name = "FeedbackFX"
	add_child(feedback_fx)
	camera = CameraController.new()
	camera.name = "Camera"
	add_child(camera)
	feedback_fx.set_camera_controller(camera)
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	hud_layer.layer = 10
	add_child(hud_layer)
	_setup_hud()


func _setup_hud() -> void:
	_add_label("LevelNumberLabel", "", 12, Color(0.55, 0.6, 0.7, 0.8), Vector2(20, 8), Vector2(300, 18))
	_add_label("TitleLabel", "", 24, Color(0.8, 0.85, 0.95, 0.9), Vector2(20, 26))
	_add_label("SubtitleLabel", "", 14, Color(0.6, 0.65, 0.75, 0.7), Vector2(20, 56))
	_setup_target_preview_container()
	_add_label("CounterLabel", "Ключи: 0 / 0", 18, Color(0.7, 0.8, 0.9, 0.85), Vector2(1020, 15), Vector2(240, 30), HORIZONTAL_ALIGNMENT_RIGHT)
	_add_label("KeyRingLabel", "", 13, Color(0.6, 0.75, 0.6, 0.8), Vector2(880, 45), Vector2(400, 20), HORIZONTAL_ALIGNMENT_LEFT, true)
	_add_label("HintLabel", "", 15, Color(0.7, 0.7, 0.5, 0.0), Vector2(340, 670), Vector2(600, 40), HORIZONTAL_ALIGNMENT_CENTER)
	_setup_action_buttons()
	_add_label("StatusLabel", "", 13, Color(0.65, 0.7, 0.8, 0.7), Vector2(20, 590), Vector2(400, 25))
	_add_label("ViolationLabel", "", 14, Color(1.0, 0.4, 0.35, 0.0), Vector2(290, 640), Vector2(700, 30), HORIZONTAL_ALIGNMENT_CENTER)
	_setup_instruction_panel()
	_setup_help_button()
	_add_label("ResetHintLabel", "", 11, Color(0.6, 0.65, 0.8, 0.0), Vector2(20, 662), Vector2(120, 20))
	_add_label("CheckHintLabel", "", 11, Color(0.6, 0.65, 0.8, 0.0), Vector2(150, 662), Vector2(190, 20))
	_setup_key_buttons_container()
	_add_label("CombineLabel", "", 14, Color(0.8, 0.7, 1.0, 0.0), Vector2(290, 590), Vector2(700, 25), HORIZONTAL_ALIGNMENT_CENTER)
	_setup_generators_panel()
	_setup_complete_summary_panel()


# --- HUD Helper: create label ---
func _add_label(lname: String, text: String, font_size: int, color: Color,
		pos: Vector2, sz: Vector2 = Vector2.ZERO, align: int = -1,
		ignore_mouse: bool = false) -> Label:
	var label = Label.new()
	label.name = lname
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.position = pos
	if sz != Vector2.ZERO:
		label.size = sz
	if align >= 0:
		label.horizontal_alignment = align
	if ignore_mouse:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(label)
	return label


func _setup_target_preview_container() -> void:
	target_preview = Control.new()
	target_preview.name = "TargetPreview"
	target_preview.position = Vector2(20, 80)
	target_preview.size = Vector2(150, 150)
	target_preview.custom_minimum_size = Vector2(150, 150)
	target_preview.visible = false
	target_preview.clip_contents = false
	target_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(target_preview)
	var target_bg = Panel.new()
	target_bg.name = "TargetBG"
	target_bg.position = Vector2.ZERO
	target_bg.size = Vector2(150, 150)
	target_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var target_style = StyleBoxFlat.new()
	target_style.bg_color = Color(0.04, 0.04, 0.08, 0.85)
	for prop in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		target_style.set(prop, 8)
	target_style.border_color = Color(0.75, 0.65, 0.2, 0.7)
	for prop in ["border_width_left", "border_width_right", "border_width_top", "border_width_bottom"]:
		target_style.set(prop, 2)
	target_bg.add_theme_stylebox_override("panel", target_style)
	target_preview.add_child(target_bg)
	var target_title_label = Label.new()
	target_title_label.name = "TargetTitle"
	target_title_label.text = "Цель"
	target_title_label.add_theme_font_size_override("font_size", 11)
	target_title_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9))
	target_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_title_label.position = Vector2(0, 2)
	target_title_label.size = Vector2(150, 16)
	target_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_preview.add_child(target_title_label)


func _setup_action_buttons() -> void:
	var reset_btn = Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = "СБРОС"
	reset_btn.add_theme_font_size_override("font_size", 14)
	reset_btn.position = Vector2(20, 620)
	reset_btn.size = Vector2(120, 40)
	reset_btn.pressed.connect(_on_reset_pressed)
	hud_layer.add_child(reset_btn)
	var check_btn = Button.new()
	check_btn.name = "CheckButton"
	check_btn.text = "ПРОВЕРИТЬ УЗОР"
	check_btn.add_theme_font_size_override("font_size", 14)
	check_btn.position = Vector2(150, 620)
	check_btn.size = Vector2(190, 40)
	check_btn.tooltip_text = "Проверить, открывает ли текущее расположение кристаллов замок.\nСоберите картинку-цель и проверьте!"
	check_btn.pressed.connect(_on_check_pressed)
	hud_layer.add_child(check_btn)


func _make_stylebox(bg: Color, corner: int, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	for prop in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, corner)
	style.border_color = border_color
	for prop in ["border_width_left", "border_width_right", "border_width_top", "border_width_bottom"]:
		style.set(prop, border_width)
	return style


func _setup_instruction_panel() -> void:
	var instr_panel = Panel.new()
	instr_panel.name = "InstructionPanel"
	instr_panel.visible = false
	instr_panel.position = Vector2(190, 130)
	instr_panel.size = Vector2(900, 370)
	instr_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.06, 0.12, 0.94), 14, Color(0.35, 0.45, 0.75, 0.6), 2))
	hud_layer.add_child(instr_panel)
	var il = func(n: String, fs: int, c: Color, p: Vector2, s: Vector2, ha: int = HORIZONTAL_ALIGNMENT_CENTER, wrap: bool = false) -> Label:
		var l = Label.new(); l.name = n; l.text = ""; l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", c); l.horizontal_alignment = ha
		l.position = p; l.size = s
		if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		instr_panel.add_child(l); return l
	il.call("InstrTitle", 22, Color(0.85, 0.9, 1.0, 1.0), Vector2(20, 18), Vector2(860, 30))
	il.call("InstrGoal", 17, Color(0.4, 0.9, 0.5, 1.0), Vector2(40, 58), Vector2(820, 28))
	il.call("InstrBody", 15, Color(0.72, 0.77, 0.88, 0.95), Vector2(50, 98), Vector2(800, 150), HORIZONTAL_ALIGNMENT_CENTER, true)
	il.call("InstrNewMechanic", 15, Color(1.0, 0.85, 0.3, 0.9), Vector2(50, 265), Vector2(800, 30))
	var dismiss = il.call("InstrDismiss", 13, Color(0.55, 0.65, 0.5, 0.75), Vector2(20, 320), Vector2(860, 25))
	dismiss.text = "Нажмите в любом месте, чтобы начать"


func _setup_help_button() -> void:
	var help_btn = Button.new()
	help_btn.name = "HelpButton"
	help_btn.text = "?"
	help_btn.add_theme_font_size_override("font_size", 18)
	help_btn.position = Vector2(1235, 15)
	help_btn.size = Vector2(35, 35)
	help_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.15, 0.18, 0.28, 0.8), 16, Color(0.4, 0.5, 0.7, 0.5), 1))
	help_btn.pressed.connect(_show_instruction_panel)
	hud_layer.add_child(help_btn)


func _setup_key_buttons_container() -> void:
	var key_buttons_container = VBoxContainer.new()
	key_buttons_container.name = "KeyButtonsContainer"
	key_buttons_container.position = Vector2(880, 65)
	key_buttons_container.size = Vector2(380, 280)
	key_buttons_container.visible = false
	key_buttons_container.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_layer.add_child(key_buttons_container)


func _setup_generators_panel() -> void:
	var gen_panel = Panel.new()
	gen_panel.name = "GeneratorsPanel"
	gen_panel.visible = false
	gen_panel.position = Vector2(340, 140)
	gen_panel.size = Vector2(600, 120)
	gen_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.08, 0.16, 0.92), 10, Color(0.5, 0.7, 0.4, 0.6), 2))
	hud_layer.add_child(gen_panel)
	var gt = Label.new(); gt.name = "GenTitle"; gt.text = "Генераторы"
	gt.add_theme_font_size_override("font_size", 18)
	gt.add_theme_color_override("font_color", Color(0.5, 0.9, 0.4, 1.0))
	gt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gt.position = Vector2(20, 12); gt.size = Vector2(560, 28)
	gen_panel.add_child(gt)
	var gb = Label.new(); gb.name = "GenBody"; gb.text = ""
	gb.add_theme_font_size_override("font_size", 14)
	gb.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.95))
	gb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gb.position = Vector2(20, 45); gb.size = Vector2(560, 60)
	gb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gen_panel.add_child(gb)


func _setup_complete_summary_panel() -> void:
	var panel = Panel.new()
	panel.name = "CompleteSummaryPanel"
	panel.visible = false
	panel.position = Vector2(240, 60)
	panel.size = Vector2(800, 560)
	panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.07, 0.13, 0.95), 14, Color(0.3, 0.9, 0.4, 0.6), 2))
	hud_layer.add_child(panel)
	var al = func(n: String, fs: int, c: Color, p: Vector2, s: Vector2, ha: int = HORIZONTAL_ALIGNMENT_CENTER, wrap: bool = false):
		var l = Label.new(); l.name = n; l.text = ""
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", c)
		l.horizontal_alignment = ha; l.position = p; l.size = s
		if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(l)
	al.call("SummaryTitle", 24, Color(0.3, 1.0, 0.5, 1.0), Vector2(20, 16), Vector2(760, 35))
	al.call("SummaryLevelInfo", 16, Color(0.7, 0.75, 0.85, 0.9), Vector2(20, 55), Vector2(760, 25))
	al.call("SummaryGroupInfo", 15, Color(0.8, 0.75, 0.5, 0.9), Vector2(20, 82), Vector2(760, 25))
	var div = Panel.new(); div.name = "SummaryDivider"; div.position = Vector2(80, 115); div.size = Vector2(640, 2)
	var ds = StyleBoxFlat.new(); ds.bg_color = Color(0.3, 0.4, 0.6, 0.4); div.add_theme_stylebox_override("panel", ds)
	panel.add_child(div)
	al.call("SummaryKeysTitle", 14, Color(0.6, 0.7, 0.8, 0.8), Vector2(20, 125), Vector2(760, 22))
	var skl = Label.new(); skl.name = "SummaryKeysList"; skl.text = ""
	skl.add_theme_font_size_override("font_size", 14)
	skl.add_theme_color_override("font_color", Color(0.72, 0.8, 0.68, 0.95))
	skl.position = Vector2(60, 152); skl.size = Vector2(680, 240)
	skl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; panel.add_child(skl)
	al.call("SummaryLearnedNote", 13, Color(0.6, 0.65, 0.8, 0.8), Vector2(40, 400), Vector2(720, 45), HORIZONTAL_ALIGNMENT_CENTER, true)
	al.call("SummaryGenInfo", 13, Color(0.5, 0.9, 0.4, 0.85), Vector2(40, 448), Vector2(720, 40), HORIZONTAL_ALIGNMENT_CENTER, true)
	var sum_next_btn = Button.new()
	sum_next_btn.name = "SummaryNextButton"
	sum_next_btn.text = "ВЕРНУТЬСЯ НА КАРТУ" if GameManager.hall_tree != null else "СЛЕДУЮЩИЙ УРОВЕНЬ  >"
	sum_next_btn.add_theme_font_size_override("font_size", 20)
	sum_next_btn.position = Vector2(200, 495); sum_next_btn.size = Vector2(400, 50)
	sum_next_btn.visible = false
	sum_next_btn.pressed.connect(_on_next_level_pressed)
	panel.add_child(sum_next_btn)


# --- Level Loading ---

func load_level_from_file(file_path: String) -> void:
	if not FileAccess.file_exists(file_path):
		push_error("LevelScene: Level file not found: %s" % file_path)
		return
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("LevelScene: Failed to parse JSON: %s" % json.get_error_message())
		return
	level_data = json.data
	_build_level()


func load_level_from_data(data: Dictionary) -> void:
	level_data = data
	_build_level()


func _build_level() -> void:
	_clear_level()
	if level_data.is_empty():
		return

	var meta = level_data.get("meta", {})
	level_id = meta.get("id", "unknown")

	# Update HUD labels
	var lnl = hud_layer.get_node_or_null("LevelNumberLabel")
	if lnl: lnl.text = "Акт %d  ·  Уровень %d" % [meta.get("act", 1), meta.get("level", 1)]
	var tl = hud_layer.get_node_or_null("TitleLabel")
	if tl: tl.text = meta.get("title", "Без названия")
	var sl = hud_layer.get_node_or_null("SubtitleLabel")
	if sl: sl.text = meta.get("subtitle", "")

	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var edges_data = graph_data.get("edges", [])

	# Initialize managers
	_validation_mgr.setup(level_data)
	_shuffle_mgr.setup(level_id, nodes_data)

	_update_counter()

	# Build position map and create crystals
	var viewport_size = get_viewport_rect().size
	var positions_map := ShuffleManager.build_positions_map(nodes_data, viewport_size)

	for i in range(_shuffle_mgr.current_arrangement.size()):
		var crystal_id: int = _shuffle_mgr.current_arrangement[i]
		var node_data: Dictionary = {}
		for nd in nodes_data:
			if nd.get("id", -1) == crystal_id:
				node_data = nd
				break
		var crystal = crystal_scene.instantiate() as CrystalNode
		crystal.crystal_id = crystal_id
		crystal.set_crystal_color(node_data.get("color", "blue"))
		crystal.set_label(node_data.get("label", ""))
		var slot_id: int = _shuffle_mgr.identity_arrangement[i]
		var pos: Vector2 = positions_map.get(slot_id, Vector2.ZERO)
		crystal.position = pos
		crystal.set_home_position(pos)
		crystal.crystal_dropped_on.connect(_on_crystal_dropped)
		crystal.drag_started.connect(_on_crystal_drag_started)
		crystal.drag_cancelled.connect(_on_crystal_drag_cancelled)
		crystal_container.add_child(crystal)
		crystals[crystal_id] = crystal

	_setup_target_preview(nodes_data, edges_data)

	for edge_data in edges_data:
		var edge = edge_scene.instantiate() as EdgeRenderer
		var from_id: int = edge_data.get("from", 0)
		var to_id: int = edge_data.get("to", 0)
		edge.from_node_id = from_id
		edge.to_node_id = to_id
		edge.set_edge_type(edge_data.get("type", "standard"))
		edge.weight = edge_data.get("weight", 1)
		edge.directed = edge_data.get("directed", false)
		if from_id in crystals and to_id in crystals:
			edge.bind_crystals(crystals[from_id], crystals[to_id])
		edge_container.add_child(edge)
		edges.append(edge)

	var positions: Array[Vector2] = []
	for crystal in crystals.values():
		positions.append(crystal.position)
	if not positions.is_empty():
		camera.center_on_points(positions, 150.0)

	# Setup SwapManager
	_swap_mgr.setup(self, crystals, edges, feedback_fx, hud_layer, _shuffle_mgr, level_data, agent_mode)

	# Read mechanics flags
	var mechanics = level_data.get("mechanics", {})
	_show_cayley_button = mechanics.get("show_cayley_button", false)
	_show_generators_hint = mechanics.get("show_generators_hint", false)
	_combine_mode = false
	_combine_first_index = -1

	# Hide panels from previous level
	for panel_name in ["RepeatButton", "CombineButton", "GeneratorsPanel", "CompleteSummaryPanel"]:
		var node = hud_layer.get_node_or_null(panel_name)
		if node: node.visible = false

	_update_status_label()
	_setup_echo_hints()
	_start_hint_timer()

	_first_symmetry_celebrated = false
	_swap_mgr.swap_count = 0
	if not agent_mode:
		_show_instruction_panel()
		var act: int = meta.get("act", 0)
		if act == 1:
			for crystal in crystals.values():
				if crystal is CrystalNode:
					crystal.set_idle_pulse(true)
			_show_button_hints()

	# Inner Doors (Act 2)
	var inner_doors_data: Array = mechanics.get("inner_doors", [])
	var subgroups_list: Array = level_data.get("subgroups", [])
	if inner_doors_data.size() > 0 and inner_doors_data[0] is Dictionary:
		_setup_inner_doors(inner_doors_data, subgroups_list)


# --- Inner Doors (Act 2) ---

func _setup_inner_doors(doors_data: Array, subgroups_list: Array) -> void:
	_inner_door_panel = InnerDoorPanelScene.new()
	_inner_door_panel.name = "InnerDoorPanel"
	_inner_door_panel.visible = false
	_inner_door_panel.setup(doors_data, subgroups_list, key_ring, self)
	_inner_door_panel.door_opened.connect(_on_inner_door_opened)
	_inner_door_panel.door_attempt_failed.connect(_on_inner_door_failed)
	hud_layer.add_child(_inner_door_panel)
	_subgroup_selector = SubgroupSelectorScene.new()
	_subgroup_selector.name = "SubgroupSelector"
	_subgroup_selector.position = Vector2(880, 360)
	_subgroup_selector.size = Vector2(360, 340)
	_subgroup_selector.setup(doors_data, subgroups_list, key_ring, self)
	_subgroup_selector.door_open_requested.connect(_on_selector_door_open)
	_subgroup_selector.subgroup_validated.connect(_on_subgroup_validated)
	hud_layer.add_child(_subgroup_selector)
	_inner_door_visuals.clear()
	var graph_data: Dictionary = level_data.get("graph", {})
	var nodes_array: Array = graph_data.get("nodes", [])
	for door in doors_data:
		var door_visual: Node2D = InnerDoorVisualScene.new()
		var door_id: String = door.get("id", "")
		var visual_hint: String = door.get("visual_hint", "")
		var req_sg: String = door.get("required_subgroup", "")
		var sg_order: int = 0
		for sg in subgroups_list:
			if sg.get("name", "") == req_sg:
				sg_order = sg.get("order", 0)
				break
		var centroid := Vector2.ZERO
		if nodes_array.size() > 0:
			for node_data in nodes_array:
				var pos_arr: Array = node_data.get("position", [0, 0])
				centroid += Vector2(pos_arr[0], pos_arr[1])
			centroid /= float(nodes_array.size())
			centroid += Vector2(0, 60)
		door_visual.setup(door_id, visual_hint, sg_order, centroid)
		door_visual.door_clicked.connect(_on_door_visual_clicked)
		edge_container.add_child(door_visual)
		_inner_door_visuals.append(door_visual)
	_first_door_ever_opened = GameManager.get_save_flag("first_inner_door_opened", false)


func _on_selector_door_open(door_id: String, _selected_indices: Array) -> void:
	_on_inner_door_opened(door_id)

func _on_subgroup_validated(is_valid: bool, _selected_indices: Array) -> void:
	if is_valid:
		for c in crystals.values():
			if c is CrystalNode: c.play_flash()
	else:
		for dv in _inner_door_visuals:
			if dv.state == InnerDoorVisualScene.DoorState.LOCKED:
				dv.play_failure_animation()

func _on_door_visual_clicked(door_id: String) -> void:
	if _subgroup_selector:
		var tween := create_tween()
		tween.tween_property(_subgroup_selector, "modulate", Color(1.3, 1.2, 0.8, 1.0), 0.15)
		tween.tween_property(_subgroup_selector, "modulate", Color(1, 1, 1, 1), 0.4)

func _on_inner_door_opened(door_id: String) -> void:
	for dv in _inner_door_visuals:
		if dv.door_id == door_id: dv.play_unlock_animation()
	if _subgroup_selector: _subgroup_selector.refresh_doors()
	feedback_fx.play_valid_feedback(crystals.values(), edges)
	if not _first_door_ever_opened:
		_first_door_ever_opened = true
		GameManager.set_save_flag("first_inner_door_opened", true)
		_play_moment_of_understanding(door_id)
	else:
		var hint_label = hud_layer.get_node_or_null("HintLabel")
		if hint_label:
			hint_label.text = "Внутренняя дверь открыта!"
			hint_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.9))
			hint_label.visible = true
			var tween := create_tween()
			tween.tween_interval(3.0)
			tween.tween_callback(_fade_hint_label.bind(hint_label))
	_update_counter()
	if _inner_door_panel and _inner_door_panel.is_all_doors_opened() and key_ring and key_ring.is_complete():
		_on_level_complete()

func _on_inner_door_failed(door_id: String, reason: Dictionary) -> void:
	for c in crystals.values():
		if c is CrystalNode: c.play_dim()
	for dv in _inner_door_visuals:
		if dv.door_id == door_id: dv.play_failure_animation()

func _play_moment_of_understanding(door_id: String) -> void:
	var door_pos := Vector2.ZERO
	for dv in _inner_door_visuals:
		if dv.door_id == door_id: door_pos = dv.position; break
	if camera: camera.move_to(door_pos, 0.8)
	var insight_panel := Panel.new()
	insight_panel.name = "MomentOfUnderstandingPanel"
	insight_panel.position = Vector2(240, 500); insight_panel.size = Vector2(800, 120)
	insight_panel.modulate = Color(1, 1, 1, 0)
	insight_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.04, 0.1, 0.95), 12, Color(0.85, 0.75, 0.3, 0.8), 2))
	var il = func(t: String, fs: int, c: Color, p: Vector2, s: Vector2):
		var l = Label.new(); l.text = t; l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", c); l.position = p; l.size = s
		insight_panel.add_child(l)
	il.call("✨", 28, Color.WHITE, Vector2(20, 12), Vector2(40, 40))
	il.call("Вы нашли подгруппу!", 20, Color(1.0, 0.9, 0.4, 1.0), Vector2(70, 14), Vector2(700, 30))
	il.call("Эти ключи замкнуты — любая комбинация двух из них даёт третий.", 15, Color(0.8, 0.82, 0.9, 0.95), Vector2(70, 52), Vector2(700, 26))
	il.call("Это фундаментальная идея алгебры: часть структуры сама образует структуру.", 13, Color(0.65, 0.7, 0.8, 0.8), Vector2(70, 82), Vector2(700, 22))
	hud_layer.add_child(insight_panel)
	var tween := create_tween()
	tween.tween_property(insight_panel, "modulate", Color(1, 1, 1, 1), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_interval(5.0)
	tween.tween_property(insight_panel, "modulate", Color(1, 1, 1, 0), 0.8)
	tween.tween_callback(_free_if_valid.bind(insight_panel))


func _is_level_complete() -> bool:
	if not _validation_mgr.is_keys_complete():
		return false
	if _inner_door_panel != null:
		return _inner_door_panel.is_all_doors_opened()
	return true


func _clear_level() -> void:
	if _inner_door_panel: _inner_door_panel.queue_free(); _inner_door_panel = null
	if _subgroup_selector: _subgroup_selector.queue_free(); _subgroup_selector = null
	for dv in _inner_door_visuals:
		if is_instance_valid(dv): dv.queue_free()
	_inner_door_visuals.clear()
	if echo_hint_system: echo_hint_system.cleanup(); echo_hint_system.queue_free(); echo_hint_system = null
	for crystal in crystals.values(): crystal.queue_free()
	crystals.clear()
	for edge in edges: edge.queue_free()
	edges.clear()
	_shuffle_mgr.clear()
	_validation_mgr.clear()
	_swap_mgr.clear()
	var key_container = hud_layer.get_node_or_null("KeyButtonsContainer") if hud_layer else null
	if key_container:
		for child in key_container.get_children(): child.queue_free()
		key_container.visible = false


# --- Drag and Drop Handling ---

func _on_crystal_drag_started(crystal_id: int) -> void:
	_dismiss_instruction_panel()
	_notify_echo_activity()
	for id in crystals:
		if id != crystal_id:
			crystals[id].play_glow()

func _on_crystal_drag_cancelled(_crystal_id: int) -> void:
	pass

func _on_crystal_dropped(from_id: int, to_id: int) -> void:
	if from_id == to_id: return
	if not (from_id in crystals and to_id in crystals): return
	_perform_swap(crystals[from_id], crystals[to_id])

func _perform_swap(crystal_a: CrystalNode, crystal_b: CrystalNode) -> void:
	var perm := _swap_mgr.perform_swap(crystal_a, crystal_b)
	_notify_echo_activity()
	swap_performed.emit(_shuffle_mgr.current_arrangement.duplicate())
	_validate_permutation(perm)


func _validate_permutation(perm: Permutation, show_invalid_feedback: bool = false) -> void:
	var result := _validation_mgr.validate_permutation(perm)

	if result.get("match", false):
		if result.get("is_new", false):
			var sym_id: String = result["sym_id"]
			symmetry_found.emit(sym_id, perm.mapping)
			feedback_fx.play_valid_feedback(crystals.values(), edges)
			_swap_mgr.set_active_repeat_key_latest(key_ring)
			_update_counter()
			_update_keyring_display()
			_update_status_label()
			if result.get("check_perm", perm).is_identity():
				_update_target_preview_border()
			if not _first_symmetry_celebrated:
				_first_symmetry_celebrated = true
				_show_first_symmetry_message(sym_id)
			_check_triggered_hints()
			if _inner_door_panel: _inner_door_panel.refresh_keys()
			if _subgroup_selector: _subgroup_selector.refresh_keys()
			if _is_level_complete():
				_on_level_complete()
		else:
			for c in crystals.values():
				if c is CrystalNode: c.play_glow()
			_update_status_label()
		return

	# No match
	invalid_attempt.emit(perm.mapping)
	_update_status_label()
	if show_invalid_feedback:
		if crystal_graph:
			var violations := crystal_graph.find_violations(perm)
			feedback_fx.play_violation_feedback(violations, crystals, edges, crystals.values())
			_show_violation_tooltip(violations.get("summary", ""))
		else:
			feedback_fx.play_invalid_feedback(crystals.values(), edges)


func _reset_arrangement() -> void:
	_swap_mgr.reset_arrangement()

func _apply_arrangement_to_crystals() -> void:
	_swap_mgr.apply_arrangement_to_crystals()


# --- Button Handlers ---

func _on_reset_pressed() -> void:
	_reset_arrangement()
	_update_status_label()
	_notify_echo_activity()

func _on_check_pressed() -> void:
	_notify_echo_activity()
	var perm := Permutation.from_array(_shuffle_mgr.current_arrangement)
	_validate_permutation(perm, true)

func _on_combine_pressed() -> void:
	_notify_echo_activity()
	if _combine_mode: _exit_combine_mode(); return
	if key_ring == null or key_ring.count() < 2: return
	_combine_mode = true; _combine_first_index = -1
	_update_keyring_display_combine()
	var combine_label = hud_layer.get_node_or_null("CombineLabel")
	if combine_label:
		combine_label.text = "Выберите первый ключ (нажмите на номер в связке)..."
		var tween = create_tween()
		tween.tween_property(combine_label, "theme_override_colors/font_color", Color(0.8, 0.7, 1.0, 0.9), 0.25)
	var combine_btn = hud_layer.get_node_or_null("CombineButton")
	if combine_btn: combine_btn.text = "ОТМЕНА"

func _on_combine_key_selected(index: int) -> void:
	if not _combine_mode or key_ring == null: return
	if _combine_first_index < 0:
		_combine_first_index = index
		var combine_label = hud_layer.get_node_or_null("CombineLabel")
		if combine_label:
			combine_label.text = "Первый: %s. Теперь выберите второй ключ..." % _get_key_display_name(index)
		_update_keyring_display_combine()
	else:
		var first_name := _get_key_display_name(_combine_first_index)
		var second_name := _get_key_display_name(index)
		var result_perm: Permutation = key_ring.compose_keys(_combine_first_index, index)
		_exit_combine_mode()
		for sym_id in target_perms:
			if target_perms[sym_id].equals(result_perm):
				if key_ring.add_key(result_perm):
					var result_name: String = target_perm_names.get(sym_id, result_perm.to_cycle_notation())
					symmetry_found.emit(sym_id, result_perm.mapping)
					feedback_fx.play_valid_feedback(crystals.values(), edges)
					_swap_mgr.set_active_repeat_key_latest(key_ring)
					_update_counter(); _update_keyring_display(); _update_status_label()
					_show_combine_result_message(first_name, second_name, result_name, true)
					_check_triggered_hints()
					if _inner_door_panel: _inner_door_panel.refresh_keys()
					if _is_level_complete(): _on_level_complete()
				else:
					var result_name: String = target_perm_names.get(sym_id, result_perm.to_cycle_notation())
					_show_combine_result_message(first_name, second_name, result_name, false)
				return
		_show_combine_result_message(first_name, second_name, result_perm.to_cycle_notation(), false)

func _exit_combine_mode() -> void:
	_combine_mode = false; _combine_first_index = -1
	_update_keyring_display()
	var combine_label = hud_layer.get_node_or_null("CombineLabel")
	if combine_label:
		var tween = create_tween()
		tween.tween_property(combine_label, "theme_override_colors/font_color", Color(0.8, 0.7, 1.0, 0.0), 0.3)
	var combine_btn = hud_layer.get_node_or_null("CombineButton")
	if combine_btn: combine_btn.text = "СКОМБИНИРОВАТЬ"


func _get_key_display_name(index: int) -> String:
	return _validation_mgr.get_key_display_name(index)


func _update_keyring_display_combine() -> void:
	var kr_label = hud_layer.get_node_or_null("KeyRingLabel")
	if kr_label == null or key_ring == null: return
	kr_label.text = "Нажмите на ключ для выбора:"
	_rebuild_key_buttons(true)

func _show_combine_result_message(first: String, second: String, result: String, is_new: bool) -> void:
	var hint_label = hud_layer.get_node_or_null("HintLabel")
	if hint_label == null: return
	hint_label.text = ("%s + %s = %s (новый ключ найден!)" if is_new else "%s + %s = %s (уже найден)") % [first, second, result]
	var color := Color(0.3, 1.0, 0.5, 0.95) if is_new else Color(0.7, 0.7, 0.5, 0.85)
	var tween = create_tween()
	tween.tween_property(hint_label, "theme_override_colors/font_color", color, 0.3)
	tween.tween_interval(3.0)
	tween.tween_property(hint_label, "theme_override_colors/font_color", Color(0.5, 0.8, 0.5, 0.5), 1.0)


func _update_status_label() -> void:
	var status = hud_layer.get_node_or_null("StatusLabel")
	if status == null: return
	var perm := Permutation.from_array(_shuffle_mgr.current_arrangement)
	if perm.is_identity():
		var identity_discovered := key_ring != null and key_ring.contains(perm) if key_ring else false
		if identity_discovered:
			status.text = "Совпадает с целью! (ключ найден)"
			status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.9))
		else:
			status.text = "Совпадает с целью — нажмите ПРОВЕРИТЬ УЗОР!"
			status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5, 0.85))
	else:
		var is_valid := false
		for sym_id in target_perms:
			if target_perms[sym_id].equals(perm): is_valid = true; break
		if is_valid:
			status.text = "Текущее: допустимое расположение"
			status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.9))
		else:
			status.text = "Расположите кристаллы как на картинке-цели"
			status.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5, 0.7))


# --- Win Condition ---

func _on_level_complete() -> void:
	if echo_hint_system: echo_hint_system.notify_level_completed()
	for crystal in crystals.values(): crystal.set_draggable(false)
	for btn_name in ["ResetButton", "CheckButton", "RepeatButton", "CombineButton"]:
		var btn = hud_layer.get_node_or_null(btn_name)
		if btn: btn.disabled = true
	feedback_fx.play_completion_feedback(crystals.values(), edges)
	if _combine_mode: _exit_combine_mode()
	if _inner_door_panel: _inner_door_panel.visible = false
	if _subgroup_selector: _subgroup_selector.visible = false
	level_completed.emit(level_id)
	GameManager.complete_level(level_id)
	var meta = level_data.get("meta", {})
	get_tree().create_timer(1.2).timeout.connect(_show_complete_summary.bind(meta))

func _show_generators_panel() -> void:
	var gen_panel = hud_layer.get_node_or_null("GeneratorsPanel")
	if gen_panel == null: return
	var symmetries_data = level_data.get("symmetries", {})
	var generator_ids: Array = symmetries_data.get("generators", [])
	if generator_ids.is_empty(): return
	var gen_names: Array = []
	for gen_id in generator_ids:
		gen_names.append(target_perm_names.get(gen_id, gen_id))
	var gen_body = gen_panel.get_node_or_null("GenBody")
	if gen_body:
		var names_str := ", ".join(gen_names)
		if generator_ids.size() == 1:
			gen_body.text = "У этого зала один генератор: %s\nКаждый ключ можно получить, комбинируя его с самим собой." % names_str
		else:
			gen_body.text = "Генераторы этого зала: %s\nКаждый ключ можно получить, комбинируя эти %d ключа." % [names_str, generator_ids.size()]
	gen_panel.visible = true
	gen_panel.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(gen_panel, "modulate", Color(1, 1, 1, 1), 0.5)

func _on_next_level_pressed() -> void:
	if GameManager.hall_tree != null: GameManager.return_to_map(); return
	var next_path: String = GameManager.get_next_level_path(level_id)
	if next_path != "":
		load_level_from_file(next_path)
	else:
		var summary = hud_layer.get_node_or_null("CompleteSummaryPanel")
		if summary:
			var learned = summary.get_node_or_null("SummaryLearnedNote")
			if learned:
				learned.text = "Поздравляем! Вы прошли все доступные уровни!"
				learned.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
			var next_btn = summary.get_node_or_null("SummaryNextButton")
			if next_btn: next_btn.visible = false


func _show_complete_summary(meta: Dictionary) -> void:
	var panel = hud_layer.get_node_or_null("CompleteSummaryPanel")
	if panel == null: return
	var st = panel.get_node_or_null("SummaryTitle")
	if st: st.text = "Зал открыт!"
	var sli = panel.get_node_or_null("SummaryLevelInfo")
	if sli: sli.text = "Уровень %d — %s" % [meta.get("level", 0), meta.get("title", "")]
	var sg = panel.get_node_or_null("SummaryGroupInfo")
	if sg: sg.text = _format_group_name(meta.get("group_name", ""), meta.get("group_order", 0))
	var sk = panel.get_node_or_null("SummaryKeysList")
	if sk: sk.text = _validation_mgr.build_summary_keys_text()
	var sln = panel.get_node_or_null("SummaryLearnedNote")
	if sln: sln.text = _get_learned_note(meta)
	var sgi = panel.get_node_or_null("SummaryGenInfo")
	if sgi:
		if _show_generators_hint: sgi.text = _get_generators_text(); sgi.visible = true
		else: sgi.text = ""; sgi.visible = false
	# Echo hint seal status
	var sum_seal = panel.get_node_or_null("SummarySealInfo")
	if sum_seal == null:
		sum_seal = Label.new(); sum_seal.name = "SummarySealInfo"
		sum_seal.add_theme_font_size_override("font_size", 14)
		sum_seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sum_seal.position = Vector2(50, 465); sum_seal.size = Vector2(700, 25)
		panel.add_child(sum_seal)
	if echo_hint_system and echo_hint_system.used_solution_hint():
		sum_seal.text = "Эхо-видение использовано — Печать совершенства потеряна"
		sum_seal.add_theme_color_override("font_color", Color(0.8, 0.5, 0.3, 0.8))
	else:
		sum_seal.text = "Печать совершенства получена"
		sum_seal.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 0.8))
	sum_seal.visible = true
	var next_btn = panel.get_node_or_null("SummaryNextButton")
	if next_btn:
		if GameManager.hall_tree != null:
			next_btn.text = "ВЕРНУТЬСЯ НА КАРТУ"; next_btn.visible = true
		else:
			next_btn.visible = GameManager.get_next_level_path(level_id) != ""
	panel.visible = true; panel.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.5)


func _build_summary_keys_text() -> String:
	return _validation_mgr.build_summary_keys_text()

func _format_group_name(group_name: String, group_order: int) -> String:
	match group_name:
		"Z2": return "2 ключа — один обмен и обратно"
		"Z3": return "3 ключа — цикл кристаллов"
		"Z4": return "4 ключа — четыре поворота квадрата"
		"Z5": return "5 ключей — пятишаговый цикл"
		"Z6": return "6 ключей — шестишаговый цикл"
		"D4": return "8 ключей — повороты и отражения квадрата"
		"V4": return "4 ключа — каждое действие отменяет само себя"
		"S3": return "6 ключей — все перестановки трёх пар"
		_: return "%d ключей" % group_order

func _get_learned_note(meta: Dictionary) -> String:
	var group_name: String = meta.get("group_name", "")
	var level_num: int = meta.get("level", 0)
	match group_name:
		"Z2":
			if level_num == 3: return "Цвета ограничивают, какие кристаллы можно менять местами."
			if level_num == 7: return "Кривой путь тоже может скрывать закономерность!"
			if level_num == 8: return "Два одинаковых скопления можно полностью поменять местами."
			return "Один обмен — сделай дважды, и всё вернётся."
		"Z3": return "Три поворота образуют цикл: каждый ведёт к следующему."
		"Z4": return "Стрелки задают направление — можно только вращать, но не отражать."
		"D4":
			if level_num == 12: return "Понадобились два разных вида ходов (поворот И отражение), чтобы получить все 8 расстановок."
			return "Без стрелок появляются отражения — число ключей удваивается!"
		"V4": return "Каждое действие здесь отменяет само себя: сделай дважды — вернёшься."
		"S3": return "Шесть способов переставить три пары — порядок ходов важен!"
		"Z5": return "Одного хода достаточно, чтобы породить все остальные — просто повторяйте."
		"Z6": return "Не каждый ход может породить все остальные — некоторые слишком малы."
		_: return ""

func _get_generators_text() -> String:
	var symmetries_data = level_data.get("symmetries", {})
	var generator_ids: Array = symmetries_data.get("generators", [])
	if generator_ids.is_empty(): return ""
	var gen_names: Array = []
	for gen_id in generator_ids:
		gen_names.append(target_perm_names.get(gen_id, gen_id))
	var names_str := ", ".join(gen_names)
	if generator_ids.size() == 1:
		return "Мастер-ключ: %s — повторяя его, можно получить все остальные ключи." % names_str
	else:
		return "Мастер-ключи: %s — комбинируя эти %d хода, можно получить все остальные." % [names_str, generator_ids.size()]


func _get_instruction_text(meta: Dictionary, mechanics: Dictionary) -> Dictionary:
	var level_num: int = meta.get("level", 1)
	var has_cayley: bool = mechanics.get("show_cayley_button", false)
	var has_generators: bool = mechanics.get("show_generators_hint", false)
	var body: String = "Кристаллы перемешаны! Расположите их как на картинке-цели в углу.\n"
	body += "Перетащите один кристалл на другой, чтобы поменять их местами.\n"
	body += "Когда соберёте — нажмите ПРОВЕРИТЬ УЗОР. Но это лишь первый ключ..."
	var new_mechanic: String = ""
	match level_num:
		1: body += "\n\nПодсказка: соберите кристаллы как на маленькой картинке слева вверху, затем нажмите ПРОВЕРИТЬ УЗОР."
		2: new_mechanic = "НОВОЕ: Стрелки на нитях! Допустимое расположение должно сохранять направления стрелок."
		3: new_mechanic = "НОВОЕ: Разные цвета! Кристаллы могут оказаться только там, где подходит цвет."
		4: body += "\n\nПомните: стрелки должны указывать в ту же сторону после обмена."
		5: new_mechanic = "НОВОЕ: Кнопка СКОМБИНИРОВАТЬ! Найдя 2+ ключа, комбинируйте их для открытия новых."
		7: body += "\n\nЭтот граф выглядит неправильным — но присмотритесь к цветам."
		8: body += "\n\nДва отдельных скопления. Одинаковы ли они изнутри?"
		9: body += "\n\nТолстые связи объединяют кристаллы в пары. Можно ли поменять целые пары?"
		10: new_mechanic = "НОВОЕ: После решения вы увидите, какие ключи — мастер-ключи, минимальный набор, порождающий все остальные."
		_:
			if has_cayley and level_num > 5:
				body += "\n\nИспользуйте СКОМБИНИРОВАТЬ, чтобы создать новые расстановки из уже найденных."
			if has_generators and level_num > 10:
				body += "\n\nИщите мастер-ключи — минимум ходов, порождающих всё остальное."
	return {"body": body, "new_mechanic": new_mechanic}


# --- HUD Updates ---

func _update_counter() -> void:
	var counter = hud_layer.get_node_or_null("CounterLabel")
	if counter:
		var found_count := key_ring.count() if key_ring else 0
		var counter_text := "Ключи: %d / %d" % [found_count, total_symmetries]
		if _inner_door_panel:
			counter_text += " | Двери: %d / %d" % [_inner_door_panel.get_opened_count(), _inner_door_panel.get_total_count()]
		counter.text = counter_text
	var repeat_btn = hud_layer.get_node_or_null("RepeatButton")
	if repeat_btn:
		var should_show := key_ring != null and key_ring.count() >= 1
		repeat_btn.visible = should_show
		if should_show: _update_repeat_button_text()
	var combine_btn = hud_layer.get_node_or_null("CombineButton")
	if combine_btn:
		combine_btn.visible = _show_cayley_button and key_ring != null and key_ring.count() >= 2

func _update_keyring_display() -> void:
	var kr_label = hud_layer.get_node_or_null("KeyRingLabel")
	if kr_label == null or key_ring == null: return
	kr_label.text = "Найденные ключи:"
	_rebuild_key_buttons(false)

func _show_violation_tooltip(text: String) -> void:
	var viol_label = hud_layer.get_node_or_null("ViolationLabel")
	if viol_label == null or text == "": return
	var tween = create_tween()
	viol_label.text = text
	tween.tween_property(viol_label, "theme_override_colors/font_color", Color(1.0, 0.4, 0.35, 0.9), 0.25)
	tween.tween_interval(1.8)
	tween.tween_property(viol_label, "theme_override_colors/font_color", Color(1.0, 0.4, 0.35, 0.0), 0.6)


# --- Tutorial / Onboarding ---

func _show_instruction_panel() -> void:
	var panel = hud_layer.get_node_or_null("InstructionPanel")
	if panel == null: return
	var meta = level_data.get("meta", {})
	var mechanics = level_data.get("mechanics", {})
	var it = panel.get_node_or_null("InstrTitle")
	if it: it.text = "Уровень %d — %s" % [meta.get("level", 1), meta.get("title", "")]
	var ig = panel.get_node_or_null("InstrGoal")
	if ig: ig.text = "Найдите все %d ключей, чтобы открыть этот зал" % meta.get("group_order", 1)
	var texts := _get_instruction_text(meta, mechanics)
	var ib = panel.get_node_or_null("InstrBody")
	if ib: ib.text = texts["body"]
	var inew = panel.get_node_or_null("InstrNewMechanic")
	if inew: inew.text = texts["new_mechanic"]; inew.visible = texts["new_mechanic"] != ""
	panel.visible = true; panel.modulate = Color(1, 1, 1, 1)
	_instruction_panel_visible = true
	for crystal in crystals.values():
		if crystal is CrystalNode: crystal.set_draggable(false)

func _dismiss_instruction_panel() -> void:
	if not _instruction_panel_visible: return
	var panel = hud_layer.get_node_or_null("InstructionPanel")
	if panel:
		var tween = create_tween()
		tween.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.3)
		tween.tween_callback(_hide_node.bind(panel))
	_instruction_panel_visible = false
	for crystal in crystals.values():
		if crystal is CrystalNode: crystal.set_draggable(true)

func _input(event: InputEvent) -> void:
	if _instruction_panel_visible:
		if event is InputEventMouseButton and event.pressed:
			_dismiss_instruction_panel()
			get_viewport().set_input_as_handled()
			return


# --- Key Buttons ---

func _rebuild_key_buttons(combine_mode_active: bool) -> void:
	var container = hud_layer.get_node_or_null("KeyButtonsContainer")
	if container == null or key_ring == null: return
	for child in container.get_children(): child.queue_free()
	if key_ring.count() == 0: container.visible = false; return
	container.visible = true
	for i in range(key_ring.count()):
		var display_name := _get_key_display_name(i)
		var row = HBoxContainer.new()
		row.name = "KeyRow_%d" % i
		row.custom_minimum_size = Vector2(380, 28)
		var label = Label.new()
		label.text = "[%d] %s" % [i + 1, display_name]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6, 0.9))
		label.custom_minimum_size = Vector2(220, 24)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var repeat_btn = Button.new()
		repeat_btn.name = "RepeatBtn_%d" % i
		repeat_btn.text = "▶ Повторить"
		repeat_btn.add_theme_font_size_override("font_size", 11)
		repeat_btn.custom_minimum_size = Vector2(120, 24)
		var cb_index := i
		repeat_btn.pressed.connect(_on_repeat_key_clicked.bind(cb_index))
		repeat_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.12, 0.18, 0.28, 0.6), 4, Color.TRANSPARENT, 0))
		repeat_btn.add_theme_stylebox_override("hover", _make_stylebox(Color(0.18, 0.28, 0.42, 0.7), 4, Color.TRANSPARENT, 0))
		repeat_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 0.9))
		row.add_child(repeat_btn)
		container.add_child(row)


func _on_key_button_clicked(index: int) -> void:
	if _combine_mode: return
	_swap_mgr.active_repeat_key_index = index
	_update_repeat_button_text()
	_rebuild_key_buttons(false)
	_notify_echo_activity()


# --- Repeat Key ---

func _update_repeat_button_text() -> void:
	var repeat_btn = hud_layer.get_node_or_null("RepeatButton")
	if repeat_btn == null: return
	if _swap_mgr.active_repeat_key_index < 0 or key_ring == null or _swap_mgr.active_repeat_key_index >= key_ring.count():
		repeat_btn.text = "ПОВТОРИТЬ"; return
	var name := _get_key_display_name(_swap_mgr.active_repeat_key_index)
	if name.length() > 14: name = name.substr(0, 12) + ".."
	repeat_btn.text = "ПОВТОРИТЬ: %s" % name

func _on_repeat_key_clicked(key_index: int) -> void:
	_notify_echo_activity()
	if _swap_mgr.repeat_animating: return
	if key_ring == null or key_index < 0 or key_index >= key_ring.count(): return
	_swap_mgr.active_repeat_key_index = key_index
	_apply_repeat_key(key_index)

func _on_repeat_pressed() -> void:
	_notify_echo_activity()
	if _swap_mgr.repeat_animating: return
	if key_ring == null or _swap_mgr.active_repeat_key_index < 0 or _swap_mgr.active_repeat_key_index >= key_ring.count(): return
	_apply_repeat_key(_swap_mgr.active_repeat_key_index)

func _apply_repeat_key(key_index: int) -> void:
	_swap_mgr.apply_repeat_key(key_index, key_ring, _validation_mgr.rebase_inverse,
		Callable(self, "_on_repeat_validate"))

func _on_repeat_validate(perm: Permutation) -> void:
	_validate_permutation(perm)
	_update_status_label()

func _set_active_repeat_key_latest() -> void:
	_swap_mgr.set_active_repeat_key_latest(key_ring)


func _show_first_symmetry_message(sym_id: String) -> void:
	var hint_label = hud_layer.get_node_or_null("HintLabel")
	if hint_label == null: return
	var sym_name: String = target_perm_names.get(sym_id, "ключ")
	var found_count := key_ring.count() if key_ring else 0
	var remaining := total_symmetries - found_count
	var msg: String
	if key_ring and key_ring.count() == 1:
		msg = "Тождество найдено — первый ключ! Осталось: %d. А есть ли ДРУГИЕ правильные расположения?" % remaining
	elif sym_name == "Тождество" or sym_id == "e":
		msg = "Вы собрали картинку-цель — первый ключ найден! Осталось: %d. А есть ли ДРУГИЕ правильные расположения?" % remaining
	else:
		msg = "Новый ключ: «%s»! Это тоже допустимое расположение. Осталось найти: %d." % [sym_name, remaining]
	hint_label.text = msg
	var tween = create_tween()
	tween.tween_property(hint_label, "theme_override_colors/font_color", Color(0.3, 1.0, 0.5, 0.95), 0.3)
	tween.tween_interval(3.5)
	tween.tween_property(hint_label, "theme_override_colors/font_color", Color(0.5, 0.8, 0.5, 0.5), 1.0)


func _show_button_hints() -> void:
	var reset_hint = hud_layer.get_node_or_null("ResetHintLabel")
	if reset_hint:
		reset_hint.text = "Вернуть к началу"
		create_tween().tween_property(reset_hint, "theme_override_colors/font_color", Color(0.6, 0.65, 0.8, 0.7), 1.5)
	var check_hint = hud_layer.get_node_or_null("CheckHintLabel")
	if check_hint:
		check_hint.text = "Проверить расстановку"
		create_tween().tween_property(check_hint, "theme_override_colors/font_color", Color(0.6, 0.65, 0.8, 0.7), 1.5)


# --- Echo Hint System ---

func _setup_echo_hints() -> void:
	if echo_hint_system: echo_hint_system.cleanup(); echo_hint_system.queue_free(); echo_hint_system = null
	echo_hint_system = EchoHintSystem.new()
	echo_hint_system.name = "EchoHintSystem"
	add_child(echo_hint_system)
	echo_hint_system.setup(level_data, hud_layer, crystals)
	echo_hint_system.hint_shown.connect(_on_echo_hint_shown)
	echo_hint_system.perfect_seal_lost.connect(_on_perfect_seal_lost)

func _on_echo_hint_shown(level: int, text: String) -> void:
	pass

func _on_perfect_seal_lost() -> void:
	pass

func _notify_echo_activity() -> void:
	if echo_hint_system: echo_hint_system.notify_player_action()


# --- Legacy Hints ---

var _hint_timer: Timer = null

func _start_hint_timer() -> void:
	pass

func _check_triggered_hints() -> void:
	if key_ring == null: return
	var hints = level_data.get("hints", [])
	var found_count := key_ring.count()
	for hint in hints:
		var trigger: String = hint.get("trigger", "")
		var text: String = hint.get("text", "")
		if text.is_empty(): continue
		if trigger == "after_first_valid" and found_count == 1:
			get_tree().create_timer(4.5).timeout.connect(_show_hint.bind(text))
		elif trigger.begins_with("after_") and trigger.ends_with("_found"):
			var num_str := trigger.trim_prefix("after_").trim_suffix("_found")
			if num_str.is_valid_int():
				if found_count == int(num_str): _show_hint(text)

func _show_hint(text: String) -> void:
	var hint_label = hud_layer.get_node_or_null("HintLabel")
	if hint_label:
		hint_label.text = text
		create_tween().tween_property(hint_label, "theme_override_colors/font_color", Color(0.7, 0.7, 0.5, 0.8), 1.0)


# --- Public API ---

func get_current_permutation() -> Permutation:
	return Permutation.from_array(_shuffle_mgr.current_arrangement)

func get_key_ring() -> KeyRing:
	return key_ring

func get_crystal_graph() -> CrystalGraph:
	return crystal_graph

func get_crystals() -> Dictionary:
	return crystals

func get_edges() -> Array[EdgeRenderer]:
	return edges

func get_feedback_fx() -> FeedbackFX:
	return feedback_fx


# --- Agent API ---

func perform_swap_by_id(from_id: int, to_id: int) -> Dictionary:
	if from_id == to_id:
		return {"result": "no_op", "reason": "same_crystal"}
	if not (from_id in crystals and to_id in crystals):
		return {"result": "error", "reason": "invalid_crystal_id", "available_ids": crystals.keys()}
	var crystal_a = crystals[from_id]
	var crystal_b = crystals[to_id]
	if not crystal_a.draggable or not crystal_b.draggable:
		return {"result": "error", "reason": "crystal_not_draggable"}
	_perform_swap(crystal_a, crystal_b)
	return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement)}

func submit_permutation(mapping: Array) -> Dictionary:
	var n := crystal_graph.node_count() if crystal_graph else 0
	if mapping.size() != n:
		return {"result": "error", "reason": "wrong_size", "expected": n, "got": mapping.size()}
	var perm := Permutation.from_array(mapping)
	if not perm.is_valid():
		return {"result": "error", "reason": "invalid_permutation"}
	_shuffle_mgr.set_arrangement(mapping)
	_swap_mgr.apply_arrangement_to_crystals()
	_validate_permutation(perm, true)
	return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement)}

func agent_reset() -> Dictionary:
	_reset_arrangement()
	_update_status_label()
	return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement)}

func agent_check_current() -> Dictionary:
	var perm := Permutation.from_array(_shuffle_mgr.current_arrangement)
	_validate_permutation(perm, true)
	return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement),
			"is_automorphism": crystal_graph.is_automorphism(perm) if crystal_graph else false}

func agent_repeat_key(key_index: int) -> Dictionary:
	if key_ring == null or key_index < 0 or key_index >= key_ring.count():
		return {"result": "error", "reason": "invalid_key_index",
				"available_range": [0, key_ring.count() - 1] if key_ring else []}
	_swap_mgr.active_repeat_key_index = key_index
	_apply_repeat_key(key_index)
	return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement),
			"key_index": key_index, "key_name": _get_key_display_name(key_index)}


# --- Utility callbacks for tweens ---

func _hide_node(node: Node) -> void:
	if is_instance_valid(node): node.visible = false

func _free_if_valid(node: Node) -> void:
	if is_instance_valid(node): node.queue_free()

func _fade_hint_label(label: Label) -> void:
	if is_instance_valid(label): label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5, 0.0))


# --- Target Preview ---

func _setup_target_preview(nodes_data: Array, edges_data: Array) -> void:
	if target_preview == null:
		push_warning("LevelScene: target_preview is null — recreating")
		target_preview = Control.new()
		target_preview.name = "TargetPreview"
		target_preview.position = Vector2(20, 80)
		target_preview.size = Vector2(150, 150)
		target_preview.custom_minimum_size = Vector2(150, 150)
		target_preview.clip_contents = false
		target_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(target_preview)
		var bg = Panel.new(); bg.name = "TargetBG"
		bg.position = Vector2.ZERO; bg.size = Vector2(150, 150)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_theme_stylebox_override("panel", _make_stylebox(Color(0.04, 0.04, 0.08, 0.85), 8, Color(0.75, 0.65, 0.2, 0.7), 2))
		target_preview.add_child(bg)
		var tl = Label.new(); tl.name = "TargetTitle"; tl.text = "Цель"
		tl.add_theme_font_size_override("font_size", 11)
		tl.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.position = Vector2(0, 2); tl.size = Vector2(150, 16)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target_preview.add_child(tl)
	var old_draw = target_preview.get_node_or_null("TargetGraphDraw")
	if old_draw: target_preview.remove_child(old_draw); old_draw.queue_free()
	target_preview.visible = true
	var draw_node = TargetPreviewDraw.new()
	draw_node.name = "TargetGraphDraw"
	draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_node.position = Vector2(5, 18); draw_node.size = Vector2(140, 127)
	draw_node.custom_minimum_size = Vector2(140, 127)
	target_preview.add_child(draw_node)
	draw_node.setup(nodes_data, edges_data, Vector2(140, 127))
	_update_target_preview_border()

func _update_target_preview_border() -> void:
	if target_preview == null: return
	var target_bg = target_preview.get_node_or_null("TargetBG")
	if target_bg == null: return
	var style: StyleBoxFlat = target_bg.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null: return
	var new_style := style.duplicate() as StyleBoxFlat
	new_style.border_color = Color(0.3, 0.9, 0.4, 0.7) if _identity_found else Color(0.75, 0.65, 0.2, 0.7)
	target_bg.add_theme_stylebox_override("panel", new_style)
	var title_label = target_preview.get_node_or_null("TargetTitle")
	if title_label:
		if _identity_found:
			title_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 0.9))
			title_label.text = "Цель ✓"
		else:
			title_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9))
			title_label.text = "Цель"
