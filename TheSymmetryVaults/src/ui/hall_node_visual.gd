class_name HallNodeVisual
extends Node2D
## Visual representation of a single hall on the world map.
##
## Displays a crystal-shaped node with 4 visual states:
## - LOCKED:    Grey, lock icon, no interaction
## - AVAILABLE: Bright blue, pulsing glow, clickable
## - COMPLETED: Green checkmark, golden tint, clickable
## - PERFECT:   Gold shimmer, star icon, clickable
##
## Emits hall_selected(hall_id) when clicked.

signal hall_selected(hall_id: String)

## States mirror HallProgressionEngine.HallState
enum VisualState {
	LOCKED,
	AVAILABLE,
	COMPLETED,
	PERFECT,
}

## --- Data ---
var hall_id: String = ""
var hall_name: String = ""
var group_name: String = ""
var state: VisualState = VisualState.LOCKED

## Layer badge data: Array of {layer: int, state: String, color: Color}
var _layer_badges: Array = []

## --- Visual components (created in _ready) ---
var _crystal_shape: Node2D      ## Custom-drawn crystal polygon
var _label: Label               ## Hall name label
var _state_icon: Label          ## Unicode icon for state
var _hover_panel: Panel         ## Tooltip panel on hover
var _area: Area2D               ## Click detection area
var _badge_container: Node2D    ## Container for layer badge dots

## --- Animation state ---
var _pulse_time: float = 0.0
var _is_hovered: bool = false
var _base_scale := Vector2(1.0, 1.0)

## Crystal visual constants
const CRYSTAL_RADIUS := 28.0
const CRYSTAL_SIDES := 6
const HOVER_SCALE := 1.15

## State-dependent colors
const STATE_COLORS := {
	VisualState.LOCKED:    Color(0.25, 0.25, 0.35, 0.5),
	VisualState.AVAILABLE: Color(0.4, 0.65, 1.0, 1.0),
	VisualState.COMPLETED: Color(0.35, 0.85, 0.45, 1.0),
	VisualState.PERFECT:   Color(1.0, 0.85, 0.3, 1.0),
}

const STATE_GLOW_COLORS := {
	VisualState.LOCKED:    Color(0.15, 0.15, 0.2, 0.0),
	VisualState.AVAILABLE: Color(0.3, 0.5, 1.0, 0.4),
	VisualState.COMPLETED: Color(0.3, 0.7, 0.4, 0.25),
	VisualState.PERFECT:   Color(1.0, 0.8, 0.2, 0.35),
}

const STATE_ICONS := {
	VisualState.LOCKED:    "🔒",   # Lock
	VisualState.AVAILABLE: "✨",    # Sparkles
	VisualState.COMPLETED: "✔",    # Checkmark
	VisualState.PERFECT:   "⭐",    # Star
}

const STATE_EDGE_COLORS := {
	VisualState.LOCKED:    Color(0.3, 0.3, 0.4, 0.3),
	VisualState.AVAILABLE: Color(0.5, 0.7, 1.0, 0.8),
	VisualState.COMPLETED: Color(0.4, 0.8, 0.5, 0.7),
	VisualState.PERFECT:   Color(1.0, 0.9, 0.4, 0.8),
}

## Layer badge colors (by layer number)
const LAYER_COLORS := {
	1: Color(0.4, 0.65, 1.0, 1.0),   # Blue  — Layer 1
	2: Color(0.2, 0.85, 0.4, 1.0),   # Green — Layer 2
	3: Color(1.0, 0.85, 0.3, 1.0),   # Gold  — Layer 3
	4: Color(0.9, 0.35, 0.3, 1.0),   # Red   — Layer 4
	5: Color(0.7, 0.4, 0.9, 1.0),    # Purple— Layer 5
}

## Layer badge state icons
const LAYER_STATE_ICONS := {
	"locked":      "🔒",
	"available":   "·",
	"in_progress": "▶",
	"completed":   "✓",
	"perfect":     "⭐",
}

const BADGE_RADIUS := 6.0
const BADGE_GAP := 16.0


func _ready() -> void:
	_build_visuals()


func _process(delta: float) -> void:
	_pulse_time += delta

	# Pulse animation for AVAILABLE state
	if state == VisualState.AVAILABLE:
		var pulse := sin(_pulse_time * 2.5) * 0.08 + 1.0
		_crystal_shape.scale = _base_scale * pulse

	# Gold shimmer for PERFECT state
	if state == VisualState.PERFECT:
		var shimmer := sin(_pulse_time * 3.0) * 0.04 + 1.0
		_crystal_shape.scale = _base_scale * shimmer

	# Hover scale interpolation
	var target_scale := HOVER_SCALE if _is_hovered else 1.0
	var current := scale.x
	var new_val := lerpf(current, target_scale, delta * 10.0)
	scale = Vector2(new_val, new_val)

	_crystal_shape.queue_redraw()
	if _badge_container and not _layer_badges.is_empty():
		_badge_container.queue_redraw()


## Initialize this node with hall data.
func setup(p_hall_id: String, p_hall_name: String, p_group_name: String, p_state: VisualState) -> void:
	hall_id = p_hall_id
	hall_name = p_hall_name
	group_name = p_group_name
	set_visual_state(p_state)


## Set layer badges. badges = Array of {layer: int, state: String}
## state is one of: "locked", "available", "in_progress", "completed", "perfect"
func set_layer_badges(badges: Array) -> void:
	_layer_badges = badges
	_update_badge_visuals()


## Update the visual state.
func set_visual_state(new_state: VisualState) -> void:
	state = new_state
	if is_inside_tree():
		_update_visuals()


## --- Build visuals ---

func _build_visuals() -> void:
	# Crystal shape (drawn via _draw override)
	_crystal_shape = Node2D.new()
	_crystal_shape.name = "CrystalShape"
	add_child(_crystal_shape)
	_crystal_shape.draw.connect(_draw_crystal)

	# State icon (above crystal)
	_state_icon = Label.new()
	_state_icon.name = "StateIcon"
	_state_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_state_icon.add_theme_font_size_override("font_size", 16)
	_state_icon.position = Vector2(-15, -15)
	_state_icon.size = Vector2(30, 30)
	add_child(_state_icon)

	# Hall name label (below crystal)
	_label = Label.new()
	_label.name = "HallLabel"
	_label.text = hall_name
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.8))
	_label.position = Vector2(-60, CRYSTAL_RADIUS + 8)
	_label.size = Vector2(120, 20)
	add_child(_label)

	# Click area (CollisionShape2D inside Area2D)
	_area = Area2D.new()
	_area.name = "ClickArea"
	_area.input_pickable = true
	add_child(_area)

	var collision = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = CRYSTAL_RADIUS + 8.0
	collision.shape = circle_shape
	_area.add_child(collision)

	_area.input_event.connect(_on_area_input_event)
	_area.mouse_entered.connect(_on_mouse_entered)
	_area.mouse_exited.connect(_on_mouse_exited)

	# Layer badge container (below crystal, above label)
	_badge_container = Node2D.new()
	_badge_container.name = "BadgeContainer"
	_badge_container.position = Vector2(0, CRYSTAL_RADIUS + 2)
	add_child(_badge_container)
	_badge_container.draw.connect(_draw_layer_badges)

	_update_visuals()


func _update_visuals() -> void:
	if _state_icon:
		_state_icon.text = STATE_ICONS.get(state, "")

	if _label:
		_label.text = hall_name
		var alpha := 0.5 if state == VisualState.LOCKED else 0.9
		_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, alpha))
		# Shift label down if badges are present
		if _layer_badges.size() > 0:
			_label.position.y = CRYSTAL_RADIUS + 18

	if _crystal_shape:
		_crystal_shape.queue_redraw()

	_update_badge_visuals()


func _update_badge_visuals() -> void:
	if _badge_container:
		_badge_container.queue_redraw()


func _draw_layer_badges() -> void:
	## Draw small colored circle badges for each layer below the crystal.
	if _layer_badges.is_empty():
		return

	var total := _layer_badges.size()
	var total_width := (total - 1) * BADGE_GAP
	var start_x := -total_width / 2.0

	for i in range(total):
		var badge: Dictionary = _layer_badges[i]
		var layer_num: int = badge.get("layer", 1)
		var badge_state: String = badge.get("state", "locked")
		var color: Color = LAYER_COLORS.get(layer_num, Color.WHITE)
		var x := start_x + i * BADGE_GAP
		var center := Vector2(x, 0)

		# Draw based on state
		match badge_state:
			"locked":
				# Gray dot with padlock feel
				_badge_container.draw_circle(center, BADGE_RADIUS, Color(0.3, 0.3, 0.35, 0.4))
				_badge_container.draw_arc(center, BADGE_RADIUS, 0, TAU, 12, Color(0.4, 0.4, 0.45, 0.3), 1.0)
			"available":
				# Pulsing colored dot
				var pulse_alpha := sin(_pulse_time * 3.0) * 0.2 + 0.7
				var pulse_color := Color(color.r, color.g, color.b, pulse_alpha)
				_badge_container.draw_circle(center, BADGE_RADIUS, pulse_color)
				_badge_container.draw_arc(center, BADGE_RADIUS, 0, TAU, 12, color, 1.5)
			"in_progress":
				# Half-filled colored dot
				_badge_container.draw_circle(center, BADGE_RADIUS, Color(color.r, color.g, color.b, 0.4))
				# Draw a partial fill (left half)
				_badge_container.draw_arc(center, BADGE_RADIUS, PI * 0.5, PI * 1.5, 8, color, 2.0)
			"completed":
				# Solid colored dot with checkmark
				_badge_container.draw_circle(center, BADGE_RADIUS, color)
				# Small inner dot for "completed" effect
				_badge_container.draw_circle(center, BADGE_RADIUS * 0.4, Color(1, 1, 1, 0.6))
			"perfect":
				# Bright colored dot with star effect
				_badge_container.draw_circle(center, BADGE_RADIUS, color)
				_badge_container.draw_circle(center, BADGE_RADIUS * 0.5, Color(1, 1, 1, 0.8))
				_badge_container.draw_arc(center, BADGE_RADIUS * 1.3, 0, TAU, 12, Color(color.r, color.g, color.b, 0.3), 1.0)


func _draw_crystal() -> void:
	var color: Color = STATE_COLORS.get(state, Color.WHITE)
	var glow_color: Color = STATE_GLOW_COLORS.get(state, Color.TRANSPARENT)
	var edge_color: Color = STATE_EDGE_COLORS.get(state, Color.WHITE)

	# Glow circle behind crystal
	if glow_color.a > 0.0:
		var glow_radius := CRYSTAL_RADIUS * 1.8
		if state == VisualState.AVAILABLE:
			var pulse_alpha := sin(_pulse_time * 2.5) * 0.15 + 0.35
			glow_color.a = pulse_alpha
			glow_radius = CRYSTAL_RADIUS * (1.8 + sin(_pulse_time * 2.5) * 0.15)
		_crystal_shape.draw_circle(Vector2.ZERO, glow_radius, glow_color)

	# Crystal polygon (hexagon)
	var points := PackedVector2Array()
	for i in range(CRYSTAL_SIDES):
		var angle := (TAU / CRYSTAL_SIDES) * i - PI / 2.0  # Point up
		points.append(Vector2(cos(angle), sin(angle)) * CRYSTAL_RADIUS)

	# Fill
	_crystal_shape.draw_colored_polygon(points, color)

	# Edge lines
	for i in range(CRYSTAL_SIDES):
		_crystal_shape.draw_line(
			points[i],
			points[(i + 1) % CRYSTAL_SIDES],
			edge_color,
			2.0
		)

	# Inner decorative lines (crystal facets)
	if state != VisualState.LOCKED:
		var inner_color := Color(edge_color.r, edge_color.g, edge_color.b, edge_color.a * 0.3)
		_crystal_shape.draw_line(points[0], points[3], inner_color, 1.0)
		_crystal_shape.draw_line(points[1], points[4], inner_color, 1.0)
		_crystal_shape.draw_line(points[2], points[5], inner_color, 1.0)


## --- Input ---

func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state != VisualState.LOCKED:
			hall_selected.emit(hall_id)


func _on_mouse_entered() -> void:
	_is_hovered = true
	if state != VisualState.LOCKED:
		# Show tooltip
		if _label:
			_label.add_theme_font_size_override("font_size", 14)
			if group_name != "":
				_label.text = "%s\n%s" % [hall_name, group_name]


func _on_mouse_exited() -> void:
	_is_hovered = false
	if _label:
		_label.add_theme_font_size_override("font_size", 12)
		_label.text = hall_name
