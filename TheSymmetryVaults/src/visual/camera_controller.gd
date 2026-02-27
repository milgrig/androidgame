## CameraController — Camera management for the puzzle viewport
##
## Handles:
## - Centering the graph in view
## - Smooth zoom in/out
## - Pan controls
## - Screen shake effects for feedback

class_name CameraController
extends Camera2D

# --- Configuration ---
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var zoom_speed: float = 0.1
@export var pan_speed: float = 400.0
@export var smooth_speed: float = 5.0

# --- Internal State ---
var _target_position: Vector2 = Vector2.ZERO
var _target_zoom: Vector2 = Vector2.ONE

# Shake
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_time: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

# Pan
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	enabled = true
	position_smoothing_enabled = true
	position_smoothing_speed = smooth_speed
	# Default: camera looks at viewport center so world coords = screen coords.
	# This keeps crystals positioned by build_positions_map() inside their zone.
	var vp: Vector2 = get_viewport_rect().size
	if vp != Vector2.ZERO:
		position = vp / 2.0
		_target_position = position


func _process(delta: float) -> void:
	# Update shake
	if _shake_time > 0.0:
		_shake_time -= delta
		var shake_factor = _shake_time / _shake_duration
		_shake_offset = Vector2(
			randf_range(-1.0, 1.0) * _shake_intensity * shake_factor,
			randf_range(-1.0, 1.0) * _shake_intensity * shake_factor
		)
	else:
		_shake_offset = _shake_offset.lerp(Vector2.ZERO, delta * 10.0)

	# Apply shake offset
	offset = _shake_offset

	# Smooth zoom
	zoom = zoom.lerp(_target_zoom, delta * smooth_speed)


func _unhandled_input(event: InputEvent) -> void:
	# Zoom with mouse wheel
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom *= (1.0 + zoom_speed)
				_target_zoom = _target_zoom.clampf(min_zoom, max_zoom)
			elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom *= (1.0 - zoom_speed)
				_target_zoom = _target_zoom.clampf(min_zoom, max_zoom)

			# Middle mouse button pan
			elif mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
				_is_panning = true
				_pan_start = mouse_event.global_position
		else:
			if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
				_is_panning = false

	# Pan with middle mouse drag
	elif event is InputEventMouseMotion and _is_panning:
		var motion = event as InputEventMouseMotion
		var pan_delta = (_pan_start - motion.global_position) / zoom
		position += pan_delta
		_target_position = position
		_pan_start = motion.global_position


# --- Public API ---

## Apply a screen shake effect
func apply_shake(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_time = duration


## Center the camera on a set of positions (e.g., all crystal positions).
## [param visible_area] — optional size of the zone where crystals are
## displayed (e.g. crystal_rect.size). Falls back to full viewport if
## Vector2.ZERO.
func center_on_points(points: Array[Vector2], margin: float = 100.0,
		visible_area: Vector2 = Vector2.ZERO) -> void:
	if points.is_empty():
		return

	var min_pos = points[0]
	var max_pos = points[0]
	for p in points:
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)

	var center = (min_pos + max_pos) / 2.0
	var size = max_pos - min_pos + Vector2(margin * 2, margin * 2)

	position = center
	_target_position = center

	# Calculate zoom to fit within visible_area (or full viewport)
	var area_size: Vector2 = visible_area if visible_area != Vector2.ZERO else get_viewport_rect().size
	var zoom_x = area_size.x / size.x if size.x > 0 else 1.0
	var zoom_y = area_size.y / size.y if size.y > 0 else 1.0
	var fit_zoom = min(zoom_x, zoom_y)
	fit_zoom = clampf(fit_zoom, min_zoom, max_zoom)

	_target_zoom = Vector2(fit_zoom, fit_zoom)
	zoom = _target_zoom


## Smoothly move camera to position
func move_to(target: Vector2, duration: float = 0.5) -> void:
	_target_position = target
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", target, duration)


## Reset camera to default state
func reset() -> void:
	_target_zoom = Vector2.ONE
	_shake_intensity = 0.0
	_shake_time = 0.0
	_shake_offset = Vector2.ZERO
