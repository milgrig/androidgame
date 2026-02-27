## CrystalNode — Visual crystal with glow, color, drag-and-drop
##
## Renders a single crystal node in the puzzle graph.
## Supports drag-and-drop for swapping positions with other crystals.
## Emits signals for game state integration.
##
## Usage:
##   var crystal = crystal_node_scene.instantiate()
##   crystal.crystal_id = 0
##   crystal.set_crystal_color("red")
##   crystal.label_text = "A"
##   crystal.position = Vector2(300, 200)
##   add_child(crystal)

class_name CrystalNode
extends Node2D

# --- Signals ---
## Emitted when player starts dragging this crystal
signal crystal_grabbed(crystal_id: int)
## Emitted when this crystal is dropped onto another crystal
signal crystal_dropped_on(from_id: int, to_id: int)
## Emitted when drag starts (for UI feedback)
signal drag_started(crystal_id: int)
## Emitted when drag ends without valid drop
signal drag_cancelled(crystal_id: int)

# --- Exported Properties ---
@export var crystal_id: int = -1
@export var crystal_radius: float = 32.0
@export var label_text: String = ""
@export var draggable: bool = true

# --- Color Palette ---
## Maps color names from level JSON to actual RGBA colors
const COLOR_PALETTE := {
	"red": Color(0.95, 0.25, 0.3, 1.0),
	"blue": Color(0.3, 0.5, 1.0, 1.0),
	"green": Color(0.2, 0.85, 0.4, 1.0),
	"gold": Color(1.0, 0.85, 0.2, 1.0),
	"purple": Color(0.7, 0.3, 0.9, 1.0),
	"cyan": Color(0.2, 0.9, 0.9, 1.0),
	"orange": Color(1.0, 0.55, 0.1, 1.0),
	"white": Color(0.95, 0.95, 1.0, 1.0),
	"pink": Color(1.0, 0.5, 0.7, 1.0),
	"silver": Color(0.78, 0.8, 0.85, 1.0),
	"bronze": Color(0.8, 0.55, 0.3, 1.0),
	"magenta": Color(0.9, 0.2, 0.7, 1.0),
	"yellow": Color(1.0, 0.95, 0.3, 1.0),
}

## Default glow colors (slightly brighter/lighter than base)
const GLOW_PALETTE := {
	"red": Color(1.0, 0.4, 0.45, 0.8),
	"blue": Color(0.5, 0.7, 1.0, 0.8),
	"green": Color(0.4, 1.0, 0.6, 0.8),
	"gold": Color(1.0, 0.95, 0.5, 0.8),
	"purple": Color(0.85, 0.5, 1.0, 0.8),
	"cyan": Color(0.4, 1.0, 1.0, 0.8),
	"orange": Color(1.0, 0.7, 0.3, 0.8),
	"white": Color(1.0, 1.0, 1.0, 0.8),
	"pink": Color(1.0, 0.7, 0.85, 0.8),
	"silver": Color(0.88, 0.9, 0.95, 0.8),
	"bronze": Color(0.95, 0.7, 0.45, 0.8),
	"magenta": Color(1.0, 0.4, 0.8, 0.8),
	"yellow": Color(1.0, 1.0, 0.55, 0.8),
}

# --- Internal State ---
var _color_name: String = "blue"
var _base_color: Color = Color.WHITE
var _glow_color: Color = Color.WHITE
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _original_position: Vector2 = Vector2.ZERO
var _hover: bool = false

# Glow animation
var _glow_intensity: float = 1.0
var _pulse_time: float = 0.0
var _pulse_speed: float = 1.5
var _pulse_amplitude: float = 0.15
var _idle_pulse: bool = false  # Stronger idle pulse to hint draggability

# Feedback state
var _flash_intensity: float = 0.0
var _dim_amount: float = 0.0
var _shake_intensity: float = 0.0
var _scale_target: float = 1.0
var _violation_intensity: float = 0.0  # Red highlight for color violation

# --- Node references (set in _ready) ---
var _label: Label = null

func _ready() -> void:
	_original_position = position
	_pulse_time = randf() * TAU  # Random phase offset for pulse

	# Create the label for the crystal
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text = label_text
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_label.position = Vector2(-crystal_radius, -crystal_radius * 0.4)
	_label.size = Vector2(crystal_radius * 2, crystal_radius)
	add_child(_label)

	# Set initial z-index so crystals draw above edges
	z_index = 10


func _process(delta: float) -> void:
	# Update pulse animation (stronger when idle pulse is active for onboarding)
	var effective_amplitude := _pulse_amplitude
	var effective_speed := _pulse_speed
	if _idle_pulse and not _is_dragging:
		effective_amplitude = 0.35
		effective_speed = 2.5
	_pulse_time += delta * effective_speed
	var pulse = 1.0 + effective_amplitude * sin(_pulse_time)
	_glow_intensity = pulse

	# Hover scale effect
	var target_scale = _scale_target
	if _hover and not _is_dragging:
		target_scale = 1.12
	elif _is_dragging:
		target_scale = 1.18
	scale = scale.lerp(Vector2(target_scale, target_scale), delta * 10.0)

	# Flash decay
	if _flash_intensity > 0.0:
		_flash_intensity = max(0.0, _flash_intensity - delta * 2.0)

	# Dim decay
	if _dim_amount > 0.0:
		_dim_amount = max(0.0, _dim_amount - delta * 1.5)

	# Shake decay
	if _shake_intensity > 0.0:
		_shake_intensity = max(0.0, _shake_intensity - delta * 8.0)

	# Violation decay (slower so player can see it)
	if _violation_intensity > 0.0:
		_violation_intensity = max(0.0, _violation_intensity - delta * 1.0)

	queue_redraw()


func _draw() -> void:
	# --- Outer Glow ---
	var glow_radius = crystal_radius * 1.8 * _glow_intensity
	var glow_col = _glow_color
	glow_col.a = 0.15 * _glow_intensity

	# Multi-layer glow for soft effect
	for i in range(4):
		var r = glow_radius * (1.0 - float(i) * 0.2)
		var a = glow_col.a * (1.0 - float(i) * 0.2)
		var col = glow_col
		col.a = a
		draw_circle(Vector2.ZERO, r, col)

	# --- Flash overlay (valid symmetry feedback) ---
	if _flash_intensity > 0.0:
		var flash_col = Color(1.0, 0.95, 0.6, _flash_intensity * 0.4)
		draw_circle(Vector2.ZERO, crystal_radius * 2.0, flash_col)

	# --- Violation glow (red ring for color mismatch) ---
	if _violation_intensity > 0.0:
		var v_radius = crystal_radius * 1.6 * (1.0 + _violation_intensity * 0.2)
		var v_col = Color(1.0, 0.15, 0.1, 0.35 * _violation_intensity)
		for i in range(3):
			var r = v_radius * (1.0 - float(i) * 0.15)
			var a = v_col.a * (1.0 - float(i) * 0.25)
			var col = v_col
			col.a = a
			draw_circle(Vector2.ZERO, r, col)

	# --- Crystal Body ---
	var body_color = _base_color
	# Apply dim effect
	if _dim_amount > 0.0:
		var gray = body_color.r * 0.299 + body_color.g * 0.587 + body_color.b * 0.114
		body_color = body_color.lerp(Color(gray, gray, gray, body_color.a), _dim_amount)
		body_color = body_color.darkened(_dim_amount * 0.3)

	# Apply violation tint (redden the crystal body)
	if _violation_intensity > 0.0:
		body_color = body_color.lerp(Color(1.0, 0.2, 0.15, body_color.a), _violation_intensity * 0.6)

	# Crystal shape — hexagonal approximation for gem look
	var points := PackedVector2Array()
	var num_sides := 6
	for i in range(num_sides):
		var angle = float(i) / float(num_sides) * TAU - PI / 6.0
		points.append(Vector2(cos(angle), sin(angle)) * crystal_radius)

	# Fill
	draw_colored_polygon(points, body_color)

	# Inner highlight (gem facet effect)
	var highlight_points := PackedVector2Array()
	var highlight_radius = crystal_radius * 0.6
	for i in range(num_sides):
		var angle = float(i) / float(num_sides) * TAU - PI / 6.0
		var offset = Vector2(0, -crystal_radius * 0.1)
		highlight_points.append(Vector2(cos(angle), sin(angle)) * highlight_radius + offset)
	var highlight_col = body_color.lightened(0.3)
	highlight_col.a = 0.4
	draw_colored_polygon(highlight_points, highlight_col)

	# Outline
	var outline_color = body_color.lightened(0.2)
	outline_color.a = 0.8
	for i in range(num_sides):
		draw_line(points[i], points[(i + 1) % num_sides], outline_color, 2.0, true)

	# --- Drag indicator ---
	if _is_dragging:
		var drag_outline = Color(1.0, 1.0, 1.0, 0.5)
		for i in range(num_sides):
			var p1 = points[i] * 1.1
			var p2 = points[(i + 1) % num_sides] * 1.1
			draw_line(p1, p2, drag_outline, 1.5, true)

	# --- Hover indicator ---
	if _hover and not _is_dragging:
		var hover_col = Color(1.0, 1.0, 1.0, 0.2)
		draw_circle(Vector2.ZERO, crystal_radius * 1.15, hover_col)


func _input(event: InputEvent) -> void:
	if not draggable:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Use get_global_mouse_position() for world-space hit testing
				# (mouse_event.global_position is screen-space and breaks with camera zoom/pan)
				var world_mouse = get_global_mouse_position()
				var local_pos = to_local(world_mouse)
				if local_pos.length() <= crystal_radius * 1.2:
					_start_drag(world_mouse)
			else:
				if _is_dragging:
					_end_drag(get_global_mouse_position())

	elif event is InputEventMouseMotion:
		var world_mouse = get_global_mouse_position()
		if _is_dragging:
			_update_drag_world(world_mouse)
		else:
			# Hover detection
			var local_pos = to_local(world_mouse)
			var was_hover = _hover
			_hover = local_pos.length() <= crystal_radius * 1.2
			if _hover != was_hover:
				queue_redraw()


# --- Public API ---

## Set the crystal's color by name (from level JSON color field)
func set_crystal_color(color_name: String) -> void:
	_color_name = color_name.to_lower()
	if _color_name in COLOR_PALETTE:
		_base_color = COLOR_PALETTE[_color_name]
	else:
		push_warning("CrystalNode: Unknown color '%s', defaulting to white" % color_name)
		_base_color = Color.WHITE

	if _color_name in GLOW_PALETTE:
		_glow_color = GLOW_PALETTE[_color_name]
	else:
		_glow_color = _base_color.lightened(0.3)

	queue_redraw()


## Get the current color name
func get_crystal_color() -> String:
	return _color_name


## Play a glow pulse animation (e.g., when selected)
func play_glow() -> void:
	_glow_intensity = 2.5
	_pulse_speed = 3.0
	# Create a tween to restore
	var tween = create_tween()
	tween.tween_property(self, "_pulse_speed", 1.5, 0.8).set_ease(Tween.EASE_OUT)


## Play a dim/fade animation (invalid attempt)
func play_dim() -> void:
	_dim_amount = 1.0
	_shake_intensity = 5.0


## Play violation highlight (red tint + shake for color mismatch)
func play_violation() -> void:
	_violation_intensity = 1.0
	_shake_intensity = 6.0


## Play a flash/shimmer animation (valid symmetry found)
func play_flash() -> void:
	_flash_intensity = 1.5
	_scale_target = 1.3
	var tween = create_tween()
	tween.tween_property(self, "_scale_target", 1.0, 0.5).set_ease(Tween.EASE_OUT)


## Enable or disable drag-and-drop
func set_draggable(enabled: bool) -> void:
	draggable = enabled


## Enable/disable stronger idle pulse (used for onboarding to hint draggability)
func set_idle_pulse(enabled: bool) -> void:
	_idle_pulse = enabled


## Set the label text displayed on the crystal
func set_label(text: String) -> void:
	label_text = text
	if _label:
		_label.text = text


## Animate crystal moving to a new position (for swap animations)
func animate_to_position(target_pos: Vector2, duration: float = 0.35) -> void:
	_original_position = target_pos
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", target_pos, duration)


## Get the crystal's home position (where it should return if drag cancelled)
func get_home_position() -> Vector2:
	return _original_position


## Set home position (called after a swap completes)
func set_home_position(pos: Vector2) -> void:
	_original_position = pos


# --- Internal drag methods ---

func _start_drag(mouse_global: Vector2) -> void:
	_is_dragging = true
	_drag_offset = global_position - mouse_global
	z_index = 100  # Draw above everything while dragging
	crystal_grabbed.emit(crystal_id)
	drag_started.emit(crystal_id)


func _update_drag(event: InputEventMouseMotion) -> void:
	global_position = event.global_position + _drag_offset


func _update_drag_world(world_mouse: Vector2) -> void:
	global_position = world_mouse + _drag_offset


func _end_drag(mouse_global: Vector2) -> void:
	_is_dragging = false
	z_index = 10  # Restore normal z-index

	# Check if dropped on another crystal — this is resolved by the LevelScene
	# which listens for the signal and checks overlap
	var drop_target = _find_drop_target(mouse_global)
	if drop_target != null and drop_target != self:
		crystal_dropped_on.emit(crystal_id, drop_target.crystal_id)
	else:
		# Return to original position
		drag_cancelled.emit(crystal_id)
		animate_to_position(_original_position, 0.25)


func _find_drop_target(mouse_global: Vector2) -> CrystalNode:
	# Find other CrystalNode instances that overlap with drop position
	var parent = get_parent()
	if parent == null:
		return null

	for child in parent.get_children():
		if child is CrystalNode and child != self:
			var dist = child.global_position.distance_to(mouse_global)
			if dist <= child.crystal_radius * 1.5:
				return child

	return null
