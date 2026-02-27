## FeedbackFX — Visual feedback manager for game events
##
## Orchestrates visual effects across the level:
## - Flash/shimmer on valid symmetry discovery
## - Dim/fade on invalid permutation attempt
## - Screen-wide flash overlays
## - Particle bursts
## - Screen shake via CameraController
##
## This manager coordinates effects across all CrystalNodes and EdgeRenderers
## in the current level to provide cohesive visual feedback.

class_name FeedbackFX
extends Node2D

# --- Signals ---
signal feedback_completed(feedback_type: String)

# --- Configuration ---
@export var screen_flash_duration: float = 0.4
@export var valid_color: Color = Color(1.0, 0.95, 0.6, 0.3)
@export var invalid_color: Color = Color(0.8, 0.2, 0.2, 0.2)
@export var completion_color: Color = Color(0.3, 1.0, 0.5, 0.4)

# --- Internal State ---
var _screen_flash_alpha: float = 0.0
var _screen_flash_color: Color = Color.WHITE
var _particles: Array[Dictionary] = []  # Simple particle system
var _camera_controller = null  # Reference to CameraController if available

# Particle pool
const MAX_PARTICLES := 100


## Emit feedback_completed signal (replaces lambda in timer.timeout.connect).
func _emit_feedback(feedback_type: String) -> void:
	feedback_completed.emit(feedback_type)

func _ready() -> void:
	# Draw above everything
	z_index = 50


func _process(delta: float) -> void:
	# Decay screen flash
	if _screen_flash_alpha > 0.0:
		_screen_flash_alpha = max(0.0, _screen_flash_alpha - delta / screen_flash_duration)

	# Update particles
	_update_particles(delta)

	if _screen_flash_alpha > 0.0 or _particles.size() > 0:
		queue_redraw()


func _draw() -> void:
	# Screen flash overlay
	if _screen_flash_alpha > 0.01:
		var flash = _screen_flash_color
		flash.a = _screen_flash_alpha
		# Draw a large rect covering the viewport
		var viewport_size = get_viewport_rect().size
		var rect = Rect2(-viewport_size / 2.0, viewport_size * 2.0)
		draw_rect(rect, flash)

	# Particles
	for p in _particles:
		var col: Color = p["color"]
		col.a *= p["life"] / p["max_life"]
		draw_circle(p["pos"], p["size"] * (p["life"] / p["max_life"]), col)


# --- Public API ---

## Play valid symmetry feedback — flashes all crystals and edges, screen shimmer
func play_valid_feedback(crystals: Array, edges: Array) -> void:
	# Flash all crystals
	for crystal in crystals:
		if crystal is CrystalNode:
			crystal.play_flash()

	# Flash all edges
	for edge in edges:
		if edge is EdgeRenderer:
			edge.play_flash()

	# Screen flash
	_screen_flash_color = valid_color
	_screen_flash_alpha = 0.6

	# Spawn particles around each crystal
	for crystal in crystals:
		if crystal is CrystalNode:
			_spawn_burst(crystal.position, crystal._glow_color, 8)

	# Camera shake (subtle)
	if _camera_controller:
		_camera_controller.apply_shake(2.0, 0.2)

	# Emit completion signal after delay
	var timer = get_tree().create_timer(0.5)
	timer.timeout.connect(_emit_feedback.bind("valid"))


## Play invalid attempt feedback — dims all crystals and edges, red screen flash
func play_invalid_feedback(crystals: Array, edges: Array) -> void:
	# Dim all crystals
	for crystal in crystals:
		if crystal is CrystalNode:
			crystal.play_dim()

	# Dim all edges
	for edge in edges:
		if edge is EdgeRenderer:
			edge.play_dim()

	# Red screen flash
	_screen_flash_color = invalid_color
	_screen_flash_alpha = 0.4

	# Camera shake (more pronounced)
	if _camera_controller:
		_camera_controller.apply_shake(4.0, 0.3)

	var timer = get_tree().create_timer(0.6)
	timer.timeout.connect(_emit_feedback.bind("invalid"))


## Play violation feedback — highlights specific edges/crystals that break structure.
## violations: Dictionary from CrystalGraph.find_violations()
## crystals_dict: {crystal_id -> CrystalNode}
## edges_list: Array[EdgeRenderer]
func play_violation_feedback(violations: Dictionary, crystals_dict: Dictionary,
		edges_list: Array, all_crystals: Array) -> void:
	# Dim everything first to draw attention to violations
	for crystal in all_crystals:
		if crystal is CrystalNode:
			crystal.play_dim()
	for edge in edges_list:
		if edge is EdgeRenderer:
			edge.play_dim()

	# Highlight crystals with color violations (red pulse)
	var color_violations: Array = violations.get("color_violations", [])
	for cv in color_violations:
		var node_id: int = cv["node_id"]
		var mapped_id: int = cv["mapped_id"]
		if node_id in crystals_dict:
			crystals_dict[node_id].play_violation()
		if mapped_id in crystals_dict:
			crystals_dict[mapped_id].play_violation()

	# Highlight violated edges (red flash)
	var edge_violations: Array = violations.get("edge_violations", [])
	for ev in edge_violations:
		var from_id: int = ev["from"]
		var to_id: int = ev["to"]
		# Find the edge renderer that connects these nodes
		for edge in edges_list:
			if edge is EdgeRenderer:
				if (edge.from_node_id == from_id and edge.to_node_id == to_id) or \
				   (edge.from_node_id == to_id and edge.to_node_id == from_id):
					edge.play_violation()
					break

	# Subtle red screen flash (less intense than full invalid)
	_screen_flash_color = Color(0.9, 0.15, 0.1, 0.15)
	_screen_flash_alpha = 0.3

	# Gentle camera shake
	if _camera_controller:
		_camera_controller.apply_shake(2.5, 0.2)

	# Spawn a few red particles at violated nodes
	for cv in color_violations:
		var node_id: int = cv["node_id"]
		if node_id in crystals_dict:
			_spawn_burst(crystals_dict[node_id].position, Color(1.0, 0.2, 0.15, 0.7), 4)

	var timer = get_tree().create_timer(0.8)
	timer.timeout.connect(_emit_feedback.bind("violation"))


## Play level completion celebration
func play_completion_feedback(crystals: Array, edges: Array) -> void:
	# Big flash
	_screen_flash_color = completion_color
	_screen_flash_alpha = 0.8

	# Flash all crystals with extra intensity
	for crystal in crystals:
		if crystal is CrystalNode:
			crystal.play_flash()
			crystal.play_glow()
			# Big particle burst
			_spawn_burst(crystal.position, crystal._glow_color, 16)

	# Flash edges
	for edge in edges:
		if edge is EdgeRenderer:
			edge.play_flash()

	# Satisfying camera shake
	if _camera_controller:
		_camera_controller.apply_shake(3.0, 0.4)

	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(_emit_feedback.bind("completion"))


## Play feedback for a specific crystal pair swap
func play_swap_feedback(crystal_a: CrystalNode, crystal_b: CrystalNode) -> void:
	# Spawn trail particles between the two crystals
	var mid = (crystal_a.position + crystal_b.position) / 2.0
	_spawn_burst(mid, Color(1.0, 1.0, 1.0, 0.6), 6)


## Set the camera controller reference for screen shake
func set_camera_controller(controller) -> void:
	_camera_controller = controller


# --- Particle System ---

func _spawn_burst(center: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		if _particles.size() >= MAX_PARTICLES:
			_particles.pop_front()

		var angle = randf() * TAU
		var speed = randf_range(40.0, 120.0)
		var life = randf_range(0.3, 0.8)

		_particles.append({
			"pos": center,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": color.lightened(randf() * 0.3),
			"size": randf_range(2.0, 5.0),
			"life": life,
			"max_life": life,
		})


func _update_particles(delta: float) -> void:
	var to_remove := []
	for i in range(_particles.size()):
		var p = _particles[i]
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.95  # Friction
		p["life"] -= delta
		if p["life"] <= 0.0:
			to_remove.append(i)

	# Remove dead particles (reverse order)
	for i in range(to_remove.size() - 1, -1, -1):
		_particles.remove_at(to_remove[i])
