class_name InnerDoorVisual
extends Node2D
## Visual representation of an inner door on the game field (Act 2).
##
## Displays a runic stone door between crystal clusters.
## States:
## - LOCKED:   Dark stone, lock icon, bronze glow
## - UNLOCKED: Open, golden glow, particles
##
## Emits door_clicked(door_id) when the player clicks on it.
## Animations: unlock celebration, failure shake + crack effect.

signal door_clicked(door_id: String)

# --- Data ---
var door_id: String = ""
var visual_hint: String = ""        # Tooltip text
var required_order: int = 0         # Number of keys needed

# --- State ---
enum DoorState { LOCKED, UNLOCKED }
var state: DoorState = DoorState.LOCKED

# --- Visual constants ---
const DOOR_WIDTH := 60.0
const DOOR_HEIGHT := 80.0
const RUNE_RADIUS := 6.0
const GLOW_RADIUS := 55.0

# State colors
const LOCKED_BODY := Color(0.2, 0.18, 0.15, 0.95)
const LOCKED_BORDER := Color(0.55, 0.4, 0.2, 0.8)        # Bronze border
const LOCKED_GLOW := Color(0.55, 0.4, 0.2, 0.15)          # Dim bronze glow
const UNLOCKED_BODY := Color(0.12, 0.1, 0.08, 0.7)
const UNLOCKED_BORDER := Color(0.85, 0.75, 0.3, 0.9)      # Gold border
const UNLOCKED_GLOW := Color(1.0, 0.85, 0.3, 0.25)        # Gold glow
const FAILURE_COLOR := Color(1.0, 0.3, 0.2, 0.8)           # Red crack

# --- Animation state ---
var _pulse_time: float = 0.0
var _is_hovered: bool = false
var _crack_alpha: float = 0.0       # For failure animation
var _unlock_particles: Array = []   # Simple particle list
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_time: float = 0.0

# --- Internal nodes ---
var _area: Area2D
var _tooltip_panel: Panel
var _tooltip_label: Label


func _ready() -> void:
	z_index = 5  # Between edges (0) and crystals (10)
	_build_visuals()


func _process(delta: float) -> void:
	_pulse_time += delta

	# Shake decay
	if _shake_time > 0.0:
		_shake_time -= delta
		var factor := _shake_time / 0.4
		_shake_offset = Vector2(
			randf_range(-4.0, 4.0) * factor,
			randf_range(-2.0, 2.0) * factor
		)
	else:
		_shake_offset = _shake_offset.lerp(Vector2.ZERO, delta * 10.0)

	# Crack decay
	if _crack_alpha > 0.0:
		_crack_alpha = maxf(0.0, _crack_alpha - delta * 0.8)

	# Update particles
	_update_particles(delta)

	# Hover scale
	var target_scale := 1.08 if _is_hovered and state == DoorState.LOCKED else 1.0
	var s := lerpf(scale.x, target_scale, delta * 8.0)
	scale = Vector2(s, s)

	queue_redraw()


func _draw() -> void:
	var offset := _shake_offset

	# Glow behind door
	var glow_color := UNLOCKED_GLOW if state == DoorState.UNLOCKED else LOCKED_GLOW
	if state == DoorState.LOCKED:
		var pulse := sin(_pulse_time * 1.5) * 0.06 + 0.15
		glow_color.a = pulse
	draw_circle(offset, GLOW_RADIUS, glow_color)

	# Door body (rounded rectangle via polygon)
	var body_color := UNLOCKED_BODY if state == DoorState.UNLOCKED else LOCKED_BODY
	var hw := DOOR_WIDTH / 2.0
	var hh := DOOR_HEIGHT / 2.0
	var body_rect := Rect2(offset + Vector2(-hw, -hh), Vector2(DOOR_WIDTH, DOOR_HEIGHT))
	draw_rect(body_rect, body_color)

	# Border
	var border_color := UNLOCKED_BORDER if state == DoorState.UNLOCKED else LOCKED_BORDER
	if state == DoorState.UNLOCKED:
		var shimmer := sin(_pulse_time * 2.5) * 0.15 + 0.85
		border_color.a = shimmer
	draw_rect(body_rect, border_color, false, 2.5)

	# Rune markings (decorative circles on the door)
	var rune_color := Color(border_color.r, border_color.g, border_color.b, border_color.a * 0.5)
	var rune_positions := [
		offset + Vector2(0, -hh * 0.5),
		offset + Vector2(-hw * 0.5, 0),
		offset + Vector2(hw * 0.5, 0),
		offset + Vector2(0, hh * 0.5),
	]
	for rp in rune_positions:
		draw_circle(rp, RUNE_RADIUS, rune_color)
		# Inner dot
		draw_circle(rp, RUNE_RADIUS * 0.4, Color(rune_color.r, rune_color.g, rune_color.b, rune_color.a * 0.8))

	# Center icon
	if state == DoorState.LOCKED:
		# Lock keyhole shape
		var keyhole_center := offset + Vector2(0, -5)
		draw_circle(keyhole_center, 8.0, Color(0.1, 0.08, 0.06, 0.9))
		draw_circle(keyhole_center, 6.0, Color(0.35, 0.28, 0.15, 0.7))
		# Keyhole slot
		var slot_points := PackedVector2Array([
			keyhole_center + Vector2(-3, 4),
			keyhole_center + Vector2(3, 4),
			keyhole_center + Vector2(2, 14),
			keyhole_center + Vector2(-2, 14),
		])
		draw_colored_polygon(slot_points, Color(0.1, 0.08, 0.06, 0.9))
	else:
		# Open — light rays from center
		var center := offset
		var ray_color := Color(1.0, 0.9, 0.5, 0.3)
		for i in range(8):
			var angle := (TAU / 8.0) * i + _pulse_time * 0.3
			var from_pt := center + Vector2(cos(angle), sin(angle)) * 5.0
			var to_pt := center + Vector2(cos(angle), sin(angle)) * 18.0
			draw_line(from_pt, to_pt, ray_color, 1.5)

	# Crack effect (on failure)
	if _crack_alpha > 0.01:
		var crack_col := Color(FAILURE_COLOR.r, FAILURE_COLOR.g, FAILURE_COLOR.b, _crack_alpha)
		# Jagged crack lines
		draw_line(offset + Vector2(-hw, -hh * 0.3), offset + Vector2(-5, 2), crack_col, 2.0)
		draw_line(offset + Vector2(-5, 2), offset + Vector2(8, -8), crack_col, 2.0)
		draw_line(offset + Vector2(8, -8), offset + Vector2(hw, hh * 0.2), crack_col, 2.0)
		# Flash overlay on the door
		var flash := Color(1.0, 0.2, 0.15, _crack_alpha * 0.3)
		draw_rect(body_rect, flash)

	# Order indicator (small text below the door)
	if state == DoorState.LOCKED and required_order > 0:
		# Draw a small badge
		var badge_pos := offset + Vector2(0, hh + 12)
		draw_circle(badge_pos, 10.0, Color(0.15, 0.12, 0.1, 0.8))
		draw_circle(badge_pos, 10.0, border_color * Color(1, 1, 1, 0.5), false, 1.5)

	# Particles
	for p in _unlock_particles:
		var col: Color = p["color"]
		col.a *= p["life"] / p["max_life"]
		draw_circle(p["pos"] + offset, p["size"] * (p["life"] / p["max_life"]), col)


# --- Public API ---

func setup(p_door_id: String, p_visual_hint: String, p_required_order: int, p_position: Vector2) -> void:
	door_id = p_door_id
	visual_hint = p_visual_hint
	required_order = p_required_order
	position = p_position


func set_door_state(new_state: DoorState) -> void:
	state = new_state
	queue_redraw()


func play_unlock_animation() -> void:
	## Celebrate: door opens with particles and glow.
	state = DoorState.UNLOCKED
	# Particle burst
	_spawn_burst(Vector2.ZERO, Color(1.0, 0.9, 0.4, 0.9), 20)
	_spawn_burst(Vector2.ZERO, Color(0.4, 1.0, 0.5, 0.7), 12)
	queue_redraw()


func play_failure_animation() -> void:
	## Shake + crack on failed attempt.
	_crack_alpha = 1.0
	_shake_time = 0.4
	# Red particles
	_spawn_burst(Vector2.ZERO, Color(1.0, 0.3, 0.2, 0.8), 8)
	queue_redraw()


func get_door_state() -> DoorState:
	return state


# --- Tooltip ---

func _build_visuals() -> void:
	# Click area
	_area = Area2D.new()
	_area.name = "DoorClickArea"
	_area.input_pickable = true
	add_child(_area)

	var collision := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(DOOR_WIDTH + 16, DOOR_HEIGHT + 16)
	collision.shape = rect_shape
	_area.add_child(collision)

	_area.input_event.connect(_on_area_input)
	_area.mouse_entered.connect(_on_mouse_entered)
	_area.mouse_exited.connect(_on_mouse_exited)

	# Tooltip panel (shown on hover)
	_tooltip_panel = Panel.new()
	_tooltip_panel.name = "DoorTooltip"
	_tooltip_panel.visible = false
	_tooltip_panel.position = Vector2(DOOR_WIDTH / 2.0 + 10, -40)
	_tooltip_panel.size = Vector2(220, 50)
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.92)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_color = Color(0.55, 0.4, 0.2, 0.6)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	_tooltip_panel.add_theme_stylebox_override("panel", style)

	# We need a CanvasLayer or direct child for the tooltip
	# Since we're on Node2D, add as child (will follow door position)
	add_child(_tooltip_panel)

	_tooltip_label = Label.new()
	_tooltip_label.name = "TooltipText"
	_tooltip_label.text = ""
	_tooltip_label.add_theme_font_size_override("font_size", 11)
	_tooltip_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6, 0.9))
	_tooltip_label.position = Vector2(8, 4)
	_tooltip_label.size = Vector2(204, 42)
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_label)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		door_clicked.emit(door_id)


func _on_mouse_entered() -> void:
	_is_hovered = true
	if _tooltip_panel:
		if state == DoorState.LOCKED:
			_tooltip_label.text = "%s\nТребуется %d ключей" % [visual_hint, required_order]
		else:
			_tooltip_label.text = "Дверь открыта!"
		_tooltip_panel.visible = true


func _on_mouse_exited() -> void:
	_is_hovered = false
	if _tooltip_panel:
		_tooltip_panel.visible = false


# --- Particles ---

func _spawn_burst(center: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		if _unlock_particles.size() >= 60:
			_unlock_particles.pop_front()
		var angle := randf() * TAU
		var speed := randf_range(30.0, 100.0)
		var life := randf_range(0.4, 1.0)
		_unlock_particles.append({
			"pos": center,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": color.lightened(randf() * 0.3),
			"size": randf_range(2.0, 4.5),
			"life": life,
			"max_life": life,
		})


func _update_particles(delta: float) -> void:
	var to_remove := []
	for i in range(_unlock_particles.size()):
		var p = _unlock_particles[i]
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.94
		p["life"] -= delta
		if p["life"] <= 0.0:
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		_unlock_particles.remove_at(to_remove[i])
