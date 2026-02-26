class_name MapScene
extends Node2D
## MapScene -- the world map screen showing the Hall Tree.
##
## Responsibilities:
## - Display all halls as clickable HallNodeVisual nodes
## - BFS-layout via MapLayoutEngine
## - Draw edges (Line2D) between connected halls
## - Show wing headers with progress (X / total)
## - Highlight available halls, dim locked ones
## - Click on hall -> transition to LevelScene
## - Back button -> return to MainMenu
## - Camera pan/zoom to navigate the tree

## --- Constants ---
const HALL_NODE_SCENE := preload("res://src/ui/hall_node_visual.tscn")

## Edge drawing
const EDGE_COLOR_LOCKED := Color(0.2, 0.2, 0.3, 0.3)
const EDGE_COLOR_ACTIVE := Color(0.4, 0.55, 0.8, 0.5)
const EDGE_COLOR_COMPLETED := Color(0.35, 0.7, 0.4, 0.45)
const EDGE_WIDTH := 2.5

## Background
const BG_COLOR := Color(0.03, 0.03, 0.08, 1.0)

## Camera
const CAMERA_ZOOM_MIN := Vector2(0.5, 0.5)
const CAMERA_ZOOM_MAX := Vector2(2.0, 2.0)
const CAMERA_ZOOM_STEP := 0.1

## --- State ---
var _hall_tree: HallTreeData
var _progression: HallProgressionEngine
var _hall_nodes: Dictionary = {}         ## hall_id -> HallNodeVisual
var _layout_positions: Dictionary = {}   ## hall_id -> Vector2
var _wing_headers: Dictionary = {}       ## wing_id -> header data

## --- Scene nodes ---
var _camera: Camera2D
var _edge_canvas: Node2D
var _node_container: Node2D
var _hud_layer: CanvasLayer
var _wing_labels_container: Node2D

## Camera drag state
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Get hall tree and progression from GameManager
	_hall_tree = GameManager.hall_tree
	_progression = GameManager.progression

	if _hall_tree == null:
		push_error("MapScene: hall_tree is null!")
		return

	_build_scene()
	_compute_layout()
	_spawn_hall_nodes()
	_draw_edges()
	_create_wing_headers()
	_build_hud()
	_center_camera_on_available()


func _process(_delta: float) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	# Camera pan via drag
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_start = event.position
			else:
				_is_dragging = false

		# Zoom with scroll wheel
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom = clamp(
				_camera.zoom + Vector2(CAMERA_ZOOM_STEP, CAMERA_ZOOM_STEP),
				CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX
			)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom = clamp(
				_camera.zoom - Vector2(CAMERA_ZOOM_STEP, CAMERA_ZOOM_STEP),
				CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX
			)

	if event is InputEventMouseMotion and _is_dragging:
		_camera.position -= event.relative / _camera.zoom


## --- Scene Setup ---

func _build_scene() -> void:
	# Edge canvas (drawn behind nodes)
	_edge_canvas = Node2D.new()
	_edge_canvas.name = "EdgeCanvas"
	_edge_canvas.z_index = 0
	add_child(_edge_canvas)

	# Wing label container
	_wing_labels_container = Node2D.new()
	_wing_labels_container.name = "WingLabels"
	_wing_labels_container.z_index = 1
	add_child(_wing_labels_container)

	# Node container (on top of edges)
	_node_container = Node2D.new()
	_node_container.name = "HallNodes"
	_node_container.z_index = 2
	add_child(_node_container)

	# Camera
	_camera = Camera2D.new()
	_camera.name = "MapCamera"
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 5.0
	add_child(_camera)
	_camera.make_current()

	# HUD layer (fixed on screen)
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUDLayer"
	_hud_layer.layer = 10
	add_child(_hud_layer)


## --- Layout ---

func _compute_layout() -> void:
	var result := MapLayoutEngine.compute_layout(_hall_tree)
	_layout_positions = result["positions"]
	_wing_headers = result["wing_headers"]


## --- Hall Nodes ---

func _spawn_hall_nodes() -> void:
	for hall_id in _layout_positions:
		var pos: Vector2 = _layout_positions[hall_id]

		# Create HallNodeVisual
		var node: HallNodeVisual = HALL_NODE_SCENE.instantiate()
		node.position = pos

		# Determine visual state from progression engine
		var hall_state: HallProgressionEngine.HallState
		if _progression:
			hall_state = _progression.get_hall_state(hall_id)
		else:
			hall_state = HallProgressionEngine.HallState.LOCKED

		# Map HallProgressionEngine.HallState -> HallNodeVisual.VisualState
		var visual_state: HallNodeVisual.VisualState
		match hall_state:
			HallProgressionEngine.HallState.LOCKED:
				visual_state = HallNodeVisual.VisualState.LOCKED
			HallProgressionEngine.HallState.AVAILABLE:
				visual_state = HallNodeVisual.VisualState.AVAILABLE
			HallProgressionEngine.HallState.COMPLETED:
				visual_state = HallNodeVisual.VisualState.COMPLETED
			HallProgressionEngine.HallState.PERFECT:
				visual_state = HallNodeVisual.VisualState.PERFECT
			_:
				visual_state = HallNodeVisual.VisualState.LOCKED

		# Get hall name from level data (or use hall_id as fallback)
		var display_name := _get_hall_display_name(hall_id)
		var display_group := _get_hall_group_name(hall_id)

		node.setup(hall_id, display_name, display_group, visual_state)
		node.hall_selected.connect(_on_hall_selected)

		_node_container.add_child(node)
		_hall_nodes[hall_id] = node


## --- Edge Drawing ---

func _draw_edges() -> void:
	for edge in _hall_tree.edges:
		var from_id: String = edge.from_hall
		var to_id: String = edge.to_hall

		if not _layout_positions.has(from_id) or not _layout_positions.has(to_id):
			continue

		var from_pos: Vector2 = _layout_positions[from_id]
		var to_pos: Vector2 = _layout_positions[to_id]

		# Determine edge color based on hall states
		var edge_color := _get_edge_color(from_id, to_id)

		var line := Line2D.new()
		line.name = "Edge_%s_%s" % [from_id, to_id]
		line.add_point(from_pos)
		line.add_point(to_pos)
		line.width = EDGE_WIDTH
		line.default_color = edge_color
		line.antialiased = true

		# Secret edges are dashed (drawn thinner)
		if edge.type == "secret":
			line.width = 1.5
			line.default_color.a *= 0.5

		_edge_canvas.add_child(line)


func _get_edge_color(from_id: String, to_id: String) -> Color:
	if _progression == null:
		return EDGE_COLOR_LOCKED

	var from_state := _progression.get_hall_state(from_id)
	var to_state := _progression.get_hall_state(to_id)

	# Both completed -> completed edge
	if from_state in [HallProgressionEngine.HallState.COMPLETED, HallProgressionEngine.HallState.PERFECT] \
		and to_state in [HallProgressionEngine.HallState.COMPLETED, HallProgressionEngine.HallState.PERFECT]:
		return EDGE_COLOR_COMPLETED

	# At least one is available -> active edge
	if from_state != HallProgressionEngine.HallState.LOCKED \
		or to_state != HallProgressionEngine.HallState.LOCKED:
		return EDGE_COLOR_ACTIVE

	return EDGE_COLOR_LOCKED


## --- Wing Headers ---

func _create_wing_headers() -> void:
	for wing_id in _wing_headers:
		var header_data: Dictionary = _wing_headers[wing_id]
		var header_pos: Vector2 = header_data["position"]

		# Wing name label
		var name_label := Label.new()
		name_label.text = header_data["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 28)
		name_label.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0, 0.9))
		name_label.position = Vector2(header_pos.x - 200, header_pos.y)
		name_label.size = Vector2(400, 40)
		_wing_labels_container.add_child(name_label)

		# Subtitle label
		var sub_label := Label.new()
		sub_label.text = header_data["subtitle"]
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.add_theme_font_size_override("font_size", 16)
		sub_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7, 0.65))
		sub_label.position = Vector2(header_pos.x - 200, header_pos.y + 35)
		sub_label.size = Vector2(400, 25)
		_wing_labels_container.add_child(sub_label)

		# Progress label (X / total)
		var progress := _get_wing_progress_text(wing_id)
		var progress_label := Label.new()
		progress_label.name = "WingProgress_%s" % wing_id
		progress_label.text = progress
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_label.add_theme_font_size_override("font_size", 14)
		progress_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 0.7))
		progress_label.position = Vector2(header_pos.x - 100, header_pos.y + 60)
		progress_label.size = Vector2(200, 20)
		_wing_labels_container.add_child(progress_label)


## --- HUD ---

func _build_hud() -> void:
	# Title bar background
	var title_bg := ColorRect.new()
	title_bg.name = "TitleBG"
	title_bg.color = Color(0.03, 0.04, 0.1, 0.85)
	title_bg.position = Vector2(0, 0)
	title_bg.size = Vector2(1280, 55)
	_hud_layer.add_child(title_bg)

	# Map title
	var title := Label.new()
	title.name = "MapTitle"
	title.text = "Карта залов"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(440, 8)
	title.size = Vector2(400, 40)
	_hud_layer.add_child(title)

	# Back button
	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "< Меню"
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9, 0.9))
	back_btn.position = Vector2(15, 10)
	back_btn.size = Vector2(100, 36)
	_apply_button_style(back_btn)
	back_btn.pressed.connect(_on_back_pressed)
	_hud_layer.add_child(back_btn)

	# Wing progress display (bottom bar)
	var bottom_bg := ColorRect.new()
	bottom_bg.name = "BottomBG"
	bottom_bg.color = Color(0.03, 0.04, 0.1, 0.75)
	bottom_bg.position = Vector2(0, 680)
	bottom_bg.size = Vector2(1280, 40)
	_hud_layer.add_child(bottom_bg)

	# Overall progress text
	var progress_text := Label.new()
	progress_text.name = "OverallProgress"
	progress_text.text = _get_overall_progress_text()
	progress_text.add_theme_font_size_override("font_size", 14)
	progress_text.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 0.8))
	progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress_text.position = Vector2(340, 685)
	progress_text.size = Vector2(600, 30)
	_hud_layer.add_child(progress_text)

	# Legend (right side)
	var legend := _create_legend()
	legend.position = Vector2(1080, 10)
	_hud_layer.add_child(legend)


func _create_legend() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.name = "Legend"
	container.add_theme_constant_override("separation", 2)

	var items := [
		{"text": "Доступен", "color": HallNodeVisual.STATE_COLORS[HallNodeVisual.VisualState.AVAILABLE]},
		{"text": "Пройден", "color": HallNodeVisual.STATE_COLORS[HallNodeVisual.VisualState.COMPLETED]},
		{"text": "Идеально", "color": HallNodeVisual.STATE_COLORS[HallNodeVisual.VisualState.PERFECT]},
		{"text": "Закрыт", "color": HallNodeVisual.STATE_COLORS[HallNodeVisual.VisualState.LOCKED]},
	]

	for item in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var dot := ColorRect.new()
		dot.color = item["color"]
		dot.custom_minimum_size = Vector2(10, 10)
		row.add_child(dot)

		var lbl := Label.new()
		lbl.text = item["text"]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
		row.add_child(lbl)

		container.add_child(row)

	return container


## --- Interaction ---

func _on_hall_selected(hall_id: String) -> void:
	enter_hall(hall_id)


func _on_back_pressed() -> void:
	GameManager.return_to_menu()


## Navigate to a level scene for the given hall.
func enter_hall(hall_id: String) -> void:
	var level_path := GameManager.get_level_path(hall_id)
	if level_path == "":
		push_warning("MapScene: No level file for hall '%s'" % hall_id)
		return

	# Store the hall_id for LevelScene to know which hall it's playing
	GameManager.current_hall_id = hall_id

	# Transition to LevelScene
	get_tree().change_scene_to_file("res://src/game/level_scene.tscn")


## Refresh all node states (called after returning from a level).
func refresh_states() -> void:
	for hall_id in _hall_nodes:
		var node: HallNodeVisual = _hall_nodes[hall_id]
		var hall_state := _progression.get_hall_state(hall_id)
		var visual_state: HallNodeVisual.VisualState
		match hall_state:
			HallProgressionEngine.HallState.LOCKED:
				visual_state = HallNodeVisual.VisualState.LOCKED
			HallProgressionEngine.HallState.AVAILABLE:
				visual_state = HallNodeVisual.VisualState.AVAILABLE
			HallProgressionEngine.HallState.COMPLETED:
				visual_state = HallNodeVisual.VisualState.COMPLETED
			HallProgressionEngine.HallState.PERFECT:
				visual_state = HallNodeVisual.VisualState.PERFECT
			_:
				visual_state = HallNodeVisual.VisualState.LOCKED
		node.set_visual_state(visual_state)


## --- Camera ---

func _center_camera_on_available() -> void:
	# Find the first available hall and center camera on it
	if _progression == null:
		return

	var available := _progression.get_available_halls()
	if available.is_empty():
		# Center on first start hall
		if not _hall_tree.wings.is_empty():
			var first_wing = _hall_tree.wings[0]
			if not first_wing.start_halls.is_empty():
				available = [first_wing.start_halls[0]]

	if not available.is_empty() and _layout_positions.has(available[0]):
		_camera.position = _layout_positions[available[0]]
	elif not _layout_positions.is_empty():
		# Fallback: center on first node
		_camera.position = _layout_positions.values()[0]


## --- Helper Methods ---

func _get_hall_display_name(hall_id: String) -> String:
	# Try to get name from level JSON meta
	var level_path := GameManager.get_level_path(hall_id)
	if level_path != "":
		var meta := _read_level_meta(level_path)
		if meta.has("title"):
			return meta["title"]
	# Fallback: format hall_id
	return hall_id.replace("_", " ").capitalize()


func _get_hall_group_name(hall_id: String) -> String:
	var level_path := GameManager.get_level_path(hall_id)
	if level_path != "":
		var meta := _read_level_meta(level_path)
		return meta.get("group_name", "")
	return ""


func _read_level_meta(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data.get("meta", {})
	return {}


func _get_wing_progress_text(wing_id: String) -> String:
	if _progression == null:
		return ""
	var progress := _progression.get_wing_progress(wing_id)
	return "%d / %d залов открыто" % [progress["completed"], progress["total"]]


func _get_overall_progress_text() -> String:
	if _progression == null:
		return ""

	var total_completed := 0
	var total_halls := 0

	for wing in _hall_tree.wings:
		var progress := _progression.get_wing_progress(wing.id)
		total_completed += progress["completed"]
		total_halls += progress["total"]

	return "Общий прогресс: %d / %d залов" % [total_completed, total_halls]


func _apply_button_style(btn: Button) -> void:
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.08, 0.1, 0.18, 0.85)
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.border_color = Color(0.3, 0.4, 0.65, 0.5)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.12, 0.15, 0.25, 0.95)
	style_hover.corner_radius_top_left = 6
	style_hover.corner_radius_top_right = 6
	style_hover.corner_radius_bottom_left = 6
	style_hover.corner_radius_bottom_right = 6
	style_hover.border_color = Color(0.4, 0.55, 0.85, 0.8)
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
