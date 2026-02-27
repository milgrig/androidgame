class_name MapScene
extends Node2D
## MapScene -- the world map screen showing the Hall Tree.
##
## Responsibilities:
## - Display all halls as clickable HallNodeVisual nodes
## - BFS-layout via MapLayoutEngine
## - Draw edges (Line2D) between connected halls
## - Show wing headers with progress (X / total)
## - Draw gate visuals between wings (locked/unlocked)
## - Highlight available halls, dim locked ones
## - Click on hall -> transition to LevelScene
## - Back button -> return to MainMenu
## - Camera pan/zoom to navigate the tree (scrolls for multi-wing)
## - Wing unlock animation when threshold is met

## --- Constants ---
const HALL_NODE_SCENE := preload("res://src/ui/hall_node_visual.tscn")

## Edge drawing
const EDGE_COLOR_LOCKED := Color(0.2, 0.2, 0.3, 0.3)
const EDGE_COLOR_ACTIVE := Color(0.4, 0.55, 0.8, 0.5)
const EDGE_COLOR_COMPLETED := Color(0.35, 0.7, 0.4, 0.45)
const EDGE_WIDTH := 2.5

## Gate visual
const GATE_COLOR_LOCKED := Color(0.5, 0.3, 0.2, 0.7)
const GATE_COLOR_UNLOCKED := Color(0.3, 0.7, 0.5, 0.8)
const GATE_LINE_WIDTH := 3.0
const GATE_DASH_LENGTH := 12.0
const GATE_GAP := 30.0

## Resonance visual (cross-wing)
const RESONANCE_COLOR := Color(0.6, 0.45, 0.9, 0.35)
const RESONANCE_WIDTH := 1.5

## Background
const BG_COLOR := Color(0.03, 0.03, 0.08, 1.0)

## Camera
const CAMERA_ZOOM_MIN := Vector2(0.4, 0.4)
const CAMERA_ZOOM_MAX := Vector2(2.0, 2.0)
const CAMERA_ZOOM_STEP := 0.1
const CAMERA_MARGIN := 200.0

## Wing unlock animation
const WING_UNLOCK_DURATION := 1.5

## --- State ---
var _hall_tree: HallTreeData
var _progression: HallProgressionEngine
var _hall_nodes: Dictionary = {}         ## hall_id -> HallNodeVisual
var _layout_positions: Dictionary = {}   ## hall_id -> Vector2
var _wing_headers: Dictionary = {}       ## wing_id -> header data
var _layout_total_height: float = 0.0    ## total height of the layout

## --- Scene nodes ---
var _camera: Camera2D
var _edge_canvas: Node2D
var _gate_canvas: Node2D
var _resonance_canvas: Node2D
var _node_container: Node2D
var _hud_layer: CanvasLayer
var _wing_labels_container: Node2D

## Camera drag state
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO

## Camera bounds (computed from layout)
var _camera_bounds_min: Vector2 = Vector2.ZERO
var _camera_bounds_max: Vector2 = Vector2.ZERO


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
	_draw_wing_gates()
	_draw_resonance_links()
	_create_wing_headers()
	_build_hud()
	_compute_camera_bounds()
	_center_camera_on_available()

	# Listen for wing unlock events
	if _progression:
		_progression.wing_unlocked.connect(_on_wing_unlocked)


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
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var new_pos: Vector2 = _camera.position - motion.relative / _camera.zoom
		_camera.position = _clamp_camera_position(new_pos)


## --- Scene Setup ---

func _build_scene() -> void:
	# Edge canvas (drawn behind nodes)
	_edge_canvas = Node2D.new()
	_edge_canvas.name = "EdgeCanvas"
	_edge_canvas.z_index = 0
	add_child(_edge_canvas)

	# Gate canvas (between edges and nodes)
	_gate_canvas = Node2D.new()
	_gate_canvas.name = "GateCanvas"
	_gate_canvas.z_index = 1
	add_child(_gate_canvas)

	# Resonance canvas (subtle links between wings)
	_resonance_canvas = Node2D.new()
	_resonance_canvas.name = "ResonanceCanvas"
	_resonance_canvas.z_index = 1
	add_child(_resonance_canvas)

	# Wing label container
	_wing_labels_container = Node2D.new()
	_wing_labels_container.name = "WingLabels"
	_wing_labels_container.z_index = 2
	add_child(_wing_labels_container)

	# Node container (on top of edges)
	_node_container = Node2D.new()
	_node_container.name = "HallNodes"
	_node_container.z_index = 3
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
	var result: Dictionary = MapLayoutEngine.compute_layout(_hall_tree)
	_layout_positions = result["positions"]
	_wing_headers = result["wing_headers"]
	_layout_total_height = result.get("total_height", 800.0)


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
		var display_name: String = _get_hall_display_name(hall_id)
		var display_group: String = _get_hall_group_name(hall_id)

		node.setup(hall_id, display_name, display_group, visual_state)
		node.hall_selected.connect(_on_hall_selected)

		# Set layer badges for this hall
		var badges: Array = _get_layer_badges(hall_id)
		if badges.size() > 0:
			node.set_layer_badges(badges)

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
		var edge_color: Color = _get_edge_color(from_id, to_id)

		var line: Line2D = Line2D.new()
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

	var from_state: HallProgressionEngine.HallState = _progression.get_hall_state(from_id)
	var to_state: HallProgressionEngine.HallState = _progression.get_hall_state(to_id)

	# Both completed -> completed edge
	if from_state in [HallProgressionEngine.HallState.COMPLETED, HallProgressionEngine.HallState.PERFECT] \
		and to_state in [HallProgressionEngine.HallState.COMPLETED, HallProgressionEngine.HallState.PERFECT]:
		return EDGE_COLOR_COMPLETED

	# At least one is available -> active edge
	if from_state != HallProgressionEngine.HallState.LOCKED \
		or to_state != HallProgressionEngine.HallState.LOCKED:
		return EDGE_COLOR_ACTIVE

	return EDGE_COLOR_LOCKED


## --- Wing Gate Drawing ---

## Draw visual gate indicators between consecutive wings.
func _draw_wing_gates() -> void:
	var ordered_wings: Array = _hall_tree.get_ordered_wings()

	for i in range(1, ordered_wings.size()):
		var wing = ordered_wings[i]
		var prev_wing = ordered_wings[i - 1]

		# Position the gate between the two wings using wing header positions
		if not _wing_headers.has(wing.id) or not _wing_headers.has(prev_wing.id):
			continue

		var wing_header_pos: Vector2 = _wing_headers[wing.id]["position"]
		# Gate sits just above the wing header (between the two wing zones)
		var gate_y: float = wing_header_pos.y - GATE_GAP
		var gate_width: float = 300.0

		# Determine gate state
		var is_accessible: bool = false
		if _progression:
			is_accessible = _progression.is_wing_accessible(wing.id)

		var gate_color: Color = GATE_COLOR_UNLOCKED if is_accessible else GATE_COLOR_LOCKED

		# Draw the horizontal gate line (dashed for locked, solid for unlocked)
		var gate_line: Line2D = Line2D.new()
		gate_line.name = "Gate_%s_%s" % [prev_wing.id, wing.id]
		gate_line.add_point(Vector2(-gate_width / 2.0, gate_y))
		gate_line.add_point(Vector2(gate_width / 2.0, gate_y))
		gate_line.width = GATE_LINE_WIDTH
		gate_line.default_color = gate_color
		gate_line.antialiased = true
		_gate_canvas.add_child(gate_line)

		# Gate label showing threshold progress
		var gate_label: Label = Label.new()
		gate_label.name = "GateLabel_%s" % wing.id
		if wing.gate and wing.gate.type == "threshold":
			var progress_dict: Dictionary = {}
			if _progression:
				var source_wing_id: String = wing.gate.required_from_wing if wing.gate.required_from_wing != "" else prev_wing.id
				progress_dict = _progression.get_wing_progress(source_wing_id)
			var completed_count: int = progress_dict.get("completed", 0)
			if is_accessible:
				gate_label.text = "Gate Open"
			else:
				gate_label.text = "%d / %d" % [completed_count, wing.gate.required_halls]
		else:
			gate_label.text = "Gate Open" if is_accessible else "Locked"

		gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gate_label.add_theme_font_size_override("font_size", 12)
		gate_label.add_theme_color_override("font_color", gate_color)
		gate_label.position = Vector2(-60, gate_y - 20)
		gate_label.size = Vector2(120, 20)
		_gate_canvas.add_child(gate_label)


## --- Cross-Wing Resonance Drawing ---

## Draw subtle visual links for resonances that span different wings.
func _draw_resonance_links() -> void:
	for resonance in _hall_tree.resonances:
		if resonance.halls.size() < 2:
			continue

		# Check if this resonance crosses wing boundaries
		var wings_involved: Dictionary = {}
		for h_id in resonance.halls:
			var wing = _hall_tree.get_hall_wing(h_id)
			if wing:
				wings_involved[wing.id] = true

		# Only draw visual for cross-wing resonances
		if wings_involved.size() < 2:
			continue

		# Check if resonance is discovered
		var is_discovered: bool = false
		if _progression:
			var discovered_list: Array = _progression.get_discovered_resonances()
			for d in discovered_list:
				if d.halls == resonance.halls:
					is_discovered = true
					break

		if not is_discovered:
			continue

		# Draw a curved line between the two halls
		var h1: String = resonance.halls[0]
		var h2: String = resonance.halls[1]

		if not _layout_positions.has(h1) or not _layout_positions.has(h2):
			continue

		var pos1: Vector2 = _layout_positions[h1]
		var pos2: Vector2 = _layout_positions[h2]

		var resonance_line: Line2D = Line2D.new()
		resonance_line.name = "Resonance_%s_%s" % [h1, h2]

		# Create a gentle curve between the two points
		var mid: Vector2 = (pos1 + pos2) / 2.0
		var offset_x: float = 80.0  # Curve offset to the right
		var curve_mid: Vector2 = Vector2(mid.x + offset_x, mid.y)
		var steps: int = 12
		for s in range(steps + 1):
			var t: float = float(s) / float(steps)
			# Quadratic Bezier: P = (1-t)^2*P0 + 2*(1-t)*t*PC + t^2*P1
			var p: Vector2 = (1.0 - t) * (1.0 - t) * pos1 + 2.0 * (1.0 - t) * t * curve_mid + t * t * pos2
			resonance_line.add_point(p)

		resonance_line.width = RESONANCE_WIDTH
		resonance_line.default_color = RESONANCE_COLOR
		resonance_line.antialiased = true
		_resonance_canvas.add_child(resonance_line)


## --- Wing Headers ---

func _create_wing_headers() -> void:
	for wing_id in _wing_headers:
		var header_data: Dictionary = _wing_headers[wing_id]
		var header_pos: Vector2 = header_data["position"]

		# Wing name label
		var name_label: Label = Label.new()
		name_label.text = header_data["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 28)
		name_label.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0, 0.9))
		name_label.position = Vector2(header_pos.x - 200, header_pos.y)
		name_label.size = Vector2(400, 40)
		_wing_labels_container.add_child(name_label)

		# Subtitle label
		var sub_label: Label = Label.new()
		sub_label.text = header_data["subtitle"]
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.add_theme_font_size_override("font_size", 16)
		sub_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7, 0.65))
		sub_label.position = Vector2(header_pos.x - 200, header_pos.y + 35)
		sub_label.size = Vector2(400, 25)
		_wing_labels_container.add_child(sub_label)

		# Progress label (X / total)
		var progress: String = _get_wing_progress_text(wing_id)
		var progress_label: Label = Label.new()
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
	var title_bg: ColorRect = ColorRect.new()
	title_bg.name = "TitleBG"
	title_bg.color = Color(0.03, 0.04, 0.1, 0.85)
	title_bg.position = Vector2(0, 0)
	title_bg.size = Vector2(1280, 55)
	_hud_layer.add_child(title_bg)

	# Map title
	var title: Label = Label.new()
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
	var back_btn: Button = Button.new()
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
	var bottom_bg: ColorRect = ColorRect.new()
	bottom_bg.name = "BottomBG"
	bottom_bg.color = Color(0.03, 0.04, 0.1, 0.75)
	bottom_bg.position = Vector2(0, 680)
	bottom_bg.size = Vector2(1280, 40)
	_hud_layer.add_child(bottom_bg)

	# Overall progress text
	var progress_text: Label = Label.new()
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
	var legend: VBoxContainer = _create_legend()
	legend.position = Vector2(1080, 10)
	_hud_layer.add_child(legend)


func _create_legend() -> VBoxContainer:
	var container: VBoxContainer = VBoxContainer.new()
	container.name = "Legend"
	container.add_theme_constant_override("separation", 2)

	var items: Array = [
		{"text": "Доступен", "color": HallNodeVisual.STATE_COLORS[HallNodeVisual.VisualState.AVAILABLE]},
		{"text": "Пройден", "color": HallNodeVisual.STATE_COLORS[HallNodeVisual.VisualState.COMPLETED]},
		{"text": "Идеально", "color": HallNodeVisual.STATE_COLORS[HallNodeVisual.VisualState.PERFECT]},
		{"text": "Закрыт", "color": HallNodeVisual.STATE_COLORS[HallNodeVisual.VisualState.LOCKED]},
	]

	# Add layer legend if Layer 2 is unlocked
	if _progression and _progression.is_layer_unlocked(2):
		items.append({"text": "Слой 2", "color": HallNodeVisual.LAYER_COLORS[2]})

	for item in items:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var dot: ColorRect = ColorRect.new()
		dot.color = item["color"]
		dot.custom_minimum_size = Vector2(10, 10)
		row.add_child(dot)

		var lbl: Label = Label.new()
		lbl.text = item["text"]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
		row.add_child(lbl)

		container.add_child(row)

	return container


## --- Interaction ---

func _on_hall_selected(hall_id: String) -> void:
	# Determine which layer to enter
	var target_layer: int = _determine_target_layer(hall_id)
	enter_hall(hall_id, target_layer)


func _on_back_pressed() -> void:
	GameManager.return_to_menu()


## Determine the best layer to enter for a hall.
## Logic: if Layer 1 is completed and Layer 2 is available/in_progress, go to Layer 2.
## Otherwise, go to Layer 1 (or the highest available uncompleted layer).
func _determine_target_layer(hall_id: String) -> int:
	if _progression == null:
		return 1

	# Check each layer from 2 down to 1
	for layer in range(2, 0, -1):
		var layer_state: String = _progression.get_hall_layer_state(hall_id, layer)
		if layer_state == "available" or layer_state == "in_progress":
			return layer

	# Default: Layer 1
	return 1


## Navigate to a level scene for the given hall at the specified layer.
func enter_hall(hall_id: String, layer: int = 1) -> void:
	var level_path: String = GameManager.get_level_path(hall_id)
	if level_path == "":
		push_warning("MapScene: No level file for hall '%s'" % hall_id)
		return

	# Store the hall_id and layer for LevelScene to know which hall and layer it's playing
	GameManager.current_hall_id = hall_id
	GameManager.current_layer = layer

	# Transition to LevelScene
	get_tree().change_scene_to_file("res://src/game/level_scene.tscn")


## Refresh all node states (called after returning from a level).
func refresh_states() -> void:
	for hall_id in _hall_nodes:
		var node: HallNodeVisual = _hall_nodes[hall_id]
		var hall_state: HallProgressionEngine.HallState = _progression.get_hall_state(hall_id)
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

		# Update layer badges
		var badges: Array = _get_layer_badges(hall_id)
		if badges.size() > 0:
			node.set_layer_badges(badges)

	# Refresh gate visuals
	_refresh_gate_visuals()


## --- Wing Unlock Animation ---

func _on_wing_unlocked(wing_id: String) -> void:
	# Animate the gate opening and scroll camera to the new wing
	_animate_wing_unlock(wing_id)


func _animate_wing_unlock(wing_id: String) -> void:
	# Find the gate line for this wing
	var gate_node: Node = _gate_canvas.get_node_or_null("Gate_%s_%s" % [_get_prev_wing_id(wing_id), wing_id])
	if gate_node == null:
		# Try to find by iterating
		for child in _gate_canvas.get_children():
			if child.name.ends_with(wing_id) and child is Line2D:
				gate_node = child
				break

	# Animate gate color change (locked -> unlocked)
	if gate_node and gate_node is Line2D:
		var tween: Tween = create_tween()
		tween.tween_property(gate_node, "default_color", GATE_COLOR_UNLOCKED, WING_UNLOCK_DURATION)

	# Update gate label
	var gate_label_node: Node = _gate_canvas.get_node_or_null("GateLabel_%s" % wing_id)
	if gate_label_node and gate_label_node is Label:
		var tween2: Tween = create_tween()
		tween2.tween_callback(_set_gate_label_open.bind(gate_label_node)).set_delay(WING_UNLOCK_DURATION * 0.5)
		tween2.tween_property(gate_label_node, "theme_override_colors/font_color", GATE_COLOR_UNLOCKED, WING_UNLOCK_DURATION * 0.5)

	# After the gate opens, scroll camera to the new wing's start
	if _wing_headers.has(wing_id):
		var target_pos: Vector2 = _wing_headers[wing_id]["position"]
		target_pos.y += 150  # Offset down to see the first halls
		var tween3: Tween = create_tween()
		tween3.set_ease(Tween.EASE_IN_OUT)
		tween3.set_trans(Tween.TRANS_CUBIC)
		tween3.tween_property(_camera, "position", target_pos, WING_UNLOCK_DURATION).set_delay(WING_UNLOCK_DURATION * 0.7)

	# Refresh node states after animation
	var timer: SceneTreeTimer = get_tree().create_timer(WING_UNLOCK_DURATION + 0.5)
	timer.timeout.connect(refresh_states)


func _refresh_gate_visuals() -> void:
	# Update gate colors based on current progression state
	var ordered_wings: Array = _hall_tree.get_ordered_wings()
	for i in range(1, ordered_wings.size()):
		var wing = ordered_wings[i]
		var prev_wing = ordered_wings[i - 1]
		var is_accessible: bool = false
		if _progression:
			is_accessible = _progression.is_wing_accessible(wing.id)

		var gate_color: Color = GATE_COLOR_UNLOCKED if is_accessible else GATE_COLOR_LOCKED

		var gate_node: Node = _gate_canvas.get_node_or_null("Gate_%s_%s" % [prev_wing.id, wing.id])
		if gate_node and gate_node is Line2D:
			gate_node.default_color = gate_color

		var label_node: Node = _gate_canvas.get_node_or_null("GateLabel_%s" % wing.id)
		if label_node and label_node is Label:
			label_node.text = "Gate Open" if is_accessible else label_node.text
			label_node.add_theme_color_override("font_color", gate_color)


## --- Camera ---

func _compute_camera_bounds() -> void:
	if _layout_positions.is_empty():
		return

	var min_pos: Vector2 = Vector2(INF, INF)
	var max_pos: Vector2 = Vector2(-INF, -INF)

	for pos in _layout_positions.values():
		min_pos.x = minf(min_pos.x, pos.x)
		min_pos.y = minf(min_pos.y, pos.y)
		max_pos.x = maxf(max_pos.x, pos.x)
		max_pos.y = maxf(max_pos.y, pos.y)

	_camera_bounds_min = min_pos - Vector2(CAMERA_MARGIN, CAMERA_MARGIN)
	_camera_bounds_max = max_pos + Vector2(CAMERA_MARGIN, CAMERA_MARGIN)


func _clamp_camera_position(pos: Vector2) -> Vector2:
	if _camera_bounds_min == Vector2.ZERO and _camera_bounds_max == Vector2.ZERO:
		return pos
	return Vector2(
		clampf(pos.x, _camera_bounds_min.x, _camera_bounds_max.x),
		clampf(pos.y, _camera_bounds_min.y, _camera_bounds_max.y)
	)


func _center_camera_on_available() -> void:
	# Find the first available hall and center camera on it
	if _progression == null:
		return

	var available: Array[String] = _progression.get_available_halls()
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

## Get layer badge data for a hall. Returns array of {layer, state}.
## Only includes badges for layers that are relevant (not all locked).
func _get_layer_badges(hall_id: String) -> Array:
	if _progression == null:
		return []

	var badges: Array = []
	var hall_state: HallProgressionEngine.HallState = _progression.get_hall_state(hall_id)

	# Layer 1 badge — always show for non-locked halls
	if hall_state != HallProgressionEngine.HallState.LOCKED:
		var l1_state: String
		match hall_state:
			HallProgressionEngine.HallState.AVAILABLE:
				l1_state = "available"
			HallProgressionEngine.HallState.COMPLETED:
				l1_state = "completed"
			HallProgressionEngine.HallState.PERFECT:
				l1_state = "perfect"
			_:
				l1_state = "locked"
		badges.append({"layer": 1, "state": l1_state})

	# Layer 2+ badges — show if layer is globally unlocked
	for layer in range(2, 6):
		var layer_state: String = _progression.get_hall_layer_state(hall_id, layer)
		if layer_state == "locked":
			# Only show locked badge if the previous layer is completed
			# (so user can see "next layer coming")
			if layer == 2 and (hall_state == HallProgressionEngine.HallState.COMPLETED or hall_state == HallProgressionEngine.HallState.PERFECT):
				if _progression.is_layer_unlocked(layer):
					badges.append({"layer": layer, "state": "available"})
				else:
					badges.append({"layer": layer, "state": "locked"})
			break  # Don't show higher layers if this one is locked
		else:
			badges.append({"layer": layer, "state": layer_state})

	# Only return badges if there's more than just Layer 1
	# (to avoid cluttering halls that only have Layer 1)
	if badges.size() <= 1:
		return []
	return badges


func _get_hall_display_name(hall_id: String) -> String:
	# Try to get name from level JSON meta
	var level_path: String = GameManager.get_level_path(hall_id)
	if level_path != "":
		var meta: Dictionary = _read_level_meta(level_path)
		if meta.has("title"):
			return meta["title"]
	# Fallback: format hall_id
	return hall_id.replace("_", " ").capitalize()


func _get_hall_group_name(hall_id: String) -> String:
	var level_path: String = GameManager.get_level_path(hall_id)
	if level_path != "":
		var meta: Dictionary = _read_level_meta(level_path)
		return meta.get("group_name", "")
	return ""


func _read_level_meta(file_path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data.get("meta", {})
	return {}


func _get_wing_progress_text(wing_id: String) -> String:
	if _progression == null:
		return ""
	var progress: Dictionary = _progression.get_wing_progress(wing_id)
	return "%d / %d залов открыто" % [progress["completed"], progress["total"]]


func _get_overall_progress_text() -> String:
	if _progression == null:
		return ""

	var total_completed: int = 0
	var total_halls: int = 0

	for wing in _hall_tree.wings:
		var progress: Dictionary = _progression.get_wing_progress(wing.id)
		total_completed += progress["completed"]
		total_halls += progress["total"]

	return "Общий прогресс: %d / %d залов" % [total_completed, total_halls]


func _get_prev_wing_id(wing_id: String) -> String:
	var wing: WingData = _hall_tree.get_wing(wing_id)
	if wing == null:
		return ""
	for w in _hall_tree.wings:
		if w.order == wing.order - 1:
			return w.id
	return ""


func _apply_button_style(btn: Button) -> void:
	var style_normal: StyleBoxFlat = StyleBoxFlat.new()
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

	var style_hover: StyleBoxFlat = StyleBoxFlat.new()
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


## Set gate label text to "Gate Open" — used as tween callback (avoids lambda/Stack underflow).
func _set_gate_label_open(label_node: Label) -> void:
	if label_node and is_instance_valid(label_node):
		label_node.text = "Gate Open"
