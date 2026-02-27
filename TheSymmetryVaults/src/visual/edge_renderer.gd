## EdgeRenderer — Visual edge connecting two crystal nodes
##
## Renders edges between crystals with different visual styles:
## - standard: thin, subtle connection line
## - thick: bold, prominent connection (used in Level 2 for marked edges)
## - glowing: pulsing, bright connection
## - dashed: intermittent line pattern
##
## Automatically follows connected crystal node positions.

class_name EdgeRenderer
extends Node2D

# --- Edge Type Configuration ---
## Visual parameters for each edge type
const EDGE_STYLES := {
	"standard": {
		"width": 2.5,
		"color": Color(0.5, 0.6, 0.8, 0.5),
		"glow_color": Color(0.5, 0.6, 0.8, 0.15),
		"glow_width": 8.0,
		"pulse": false,
		"dashed": false,
	},
	"thick": {
		"width": 5.0,
		"color": Color(0.8, 0.75, 0.6, 0.7),
		"glow_color": Color(0.9, 0.85, 0.5, 0.25),
		"glow_width": 14.0,
		"pulse": false,
		"dashed": false,
	},
	"glowing": {
		"width": 3.0,
		"color": Color(0.6, 0.85, 1.0, 0.8),
		"glow_color": Color(0.5, 0.8, 1.0, 0.35),
		"glow_width": 18.0,
		"pulse": true,
		"dashed": false,
	},
	"dashed": {
		"width": 2.0,
		"color": Color(0.6, 0.6, 0.7, 0.4),
		"glow_color": Color(0.5, 0.5, 0.7, 0.1),
		"glow_width": 6.0,
		"pulse": false,
		"dashed": true,
	},
}

# --- Properties ---
@export var edge_type: String = "standard"
@export var from_node_id: int = -1
@export var to_node_id: int = -1
@export var weight: int = 1
@export var directed: bool = false

# --- Internal State ---
var _from_crystal: CrystalNode = null
var _to_crystal: CrystalNode = null
var _from_pos: Vector2 = Vector2.ZERO
var _to_pos: Vector2 = Vector2.ZERO
var _pulse_time: float = 0.0

# Feedback
var _flash_intensity: float = 0.0
var _dim_amount: float = 0.0
var _violation_intensity: float = 0.0  # Red highlight for violation feedback


func _ready() -> void:
	# Edges draw below crystals
	z_index = 5
	_pulse_time = randf() * TAU


func _process(delta: float) -> void:
	# Follow crystal positions
	if _from_crystal != null:
		_from_pos = _from_crystal.position
	if _to_crystal != null:
		_to_pos = _to_crystal.position

	# Pulse animation for glowing type
	_pulse_time += delta * 2.0

	# Flash decay
	if _flash_intensity > 0.0:
		_flash_intensity = max(0.0, _flash_intensity - delta * 2.0)

	# Dim decay
	if _dim_amount > 0.0:
		_dim_amount = max(0.0, _dim_amount - delta * 1.5)

	# Violation decay (slower than flash so player can see it)
	if _violation_intensity > 0.0:
		_violation_intensity = max(0.0, _violation_intensity - delta * 1.0)

	queue_redraw()


func _draw() -> void:
	if _from_pos == _to_pos:
		return

	var style = EDGE_STYLES.get(edge_type, EDGE_STYLES["standard"])
	var base_color: Color = style["color"]
	var glow_color: Color = style["glow_color"]
	var line_width: float = style["width"]
	var glow_width: float = style["glow_width"]
	var is_pulse: bool = style["pulse"]
	var is_dashed: bool = style["dashed"]

	# Apply pulse effect
	var pulse_factor = 1.0
	if is_pulse:
		pulse_factor = 0.7 + 0.3 * sin(_pulse_time)

	# Apply dim effect
	if _dim_amount > 0.0:
		var gray = base_color.r * 0.299 + base_color.g * 0.587 + base_color.b * 0.114
		base_color = base_color.lerp(Color(gray, gray, gray, base_color.a), _dim_amount)
		base_color.a *= (1.0 - _dim_amount * 0.5)
		glow_color.a *= (1.0 - _dim_amount * 0.7)

	# Apply flash effect
	if _flash_intensity > 0.0:
		var flash_add = Color(1.0, 0.95, 0.6, 0.0) * _flash_intensity * 0.3
		base_color = Color(
			min(base_color.r + flash_add.r, 1.5),
			min(base_color.g + flash_add.g, 1.5),
			min(base_color.b + flash_add.b, 1.5),
			base_color.a
		)

	# Apply violation highlight (red pulse for broken edges)
	if _violation_intensity > 0.0:
		var violation_color = Color(1.0, 0.15, 0.1, 1.0)
		base_color = base_color.lerp(violation_color, _violation_intensity * 0.85)
		base_color.a = max(base_color.a, 0.9 * _violation_intensity)
		glow_color = glow_color.lerp(Color(1.0, 0.2, 0.1, 0.5), _violation_intensity * 0.7)
		line_width = max(line_width, 4.0 * _violation_intensity)
		glow_width = max(glow_width, 16.0 * _violation_intensity)

	# Convert positions to local space
	var from_local = to_local(_from_pos + get_parent().global_position if get_parent() else _from_pos)
	var to_local_pos = to_local(_to_pos + get_parent().global_position if get_parent() else _to_pos)
	# Since edge is child of same parent as crystals, use positions directly
	from_local = _from_pos
	to_local_pos = _to_pos

	if is_dashed:
		_draw_dashed_line(from_local, to_local_pos, base_color, glow_color, line_width, glow_width, pulse_factor)
	else:
		_draw_solid_line(from_local, to_local_pos, base_color, glow_color, line_width, glow_width, pulse_factor)


func _draw_solid_line(from: Vector2, to: Vector2, color: Color, glow_col: Color,
		width: float, glow_w: float, pulse: float) -> void:
	# Glow layers (wider, transparent lines underneath)
	var num_glow_layers = 3
	for i in range(num_glow_layers):
		var layer_width = glow_w * (1.0 - float(i) * 0.25) * pulse
		var layer_alpha = glow_col.a * (1.0 - float(i) * 0.3) * pulse
		var layer_col = glow_col
		layer_col.a = layer_alpha
		draw_line(from, to, layer_col, layer_width, true)

	# Core line
	var core_col = color
	core_col.a *= pulse
	draw_line(from, to, core_col, width * pulse, true)

	# Inner bright line (highlight)
	var highlight = color.lightened(0.3)
	highlight.a = 0.3 * pulse
	draw_line(from, to, highlight, max(1.0, width * 0.4) * pulse, true)

	# Arrowhead for directed edges
	if directed:
		_draw_arrowhead(from, to, core_col, width * 2.5 * pulse)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, glow_col: Color,
		width: float, glow_w: float, pulse: float) -> void:
	var direction = (to - from)
	var length = direction.length()
	if length < 1.0:
		return
	direction = direction.normalized()

	var dash_length = 12.0
	var gap_length = 8.0
	var segment_length = dash_length + gap_length
	var current = 0.0

	while current < length:
		var dash_end = min(current + dash_length, length)
		var p1 = from + direction * current
		var p2 = from + direction * dash_end

		# Glow for each dash segment
		var glow = glow_col
		glow.a *= pulse
		draw_line(p1, p2, glow, glow_w * pulse, true)

		# Core dash
		var core = color
		core.a *= pulse
		draw_line(p1, p2, core, width * pulse, true)

		current += segment_length


func _draw_arrowhead(from: Vector2, to: Vector2, color: Color, size: float) -> void:
	## Draw a triangular arrowhead at the midpoint of the edge, pointing from→to.
	var direction = (to - from).normalized()
	var midpoint = (from + to) / 2.0
	var perp = Vector2(-direction.y, direction.x)
	var arrow_tip = midpoint + direction * size
	var arrow_left = midpoint - direction * size * 0.5 + perp * size * 0.6
	var arrow_right = midpoint - direction * size * 0.5 - perp * size * 0.6
	var points = PackedVector2Array([arrow_tip, arrow_left, arrow_right])
	var colors = PackedColorArray([color, color, color])
	draw_polygon(points, colors)


# --- Public API ---

## Bind this edge to two crystal nodes (it will follow their positions)
func bind_crystals(from_crystal: CrystalNode, to_crystal: CrystalNode) -> void:
	_from_crystal = from_crystal
	_to_crystal = to_crystal
	_from_pos = from_crystal.position
	_to_pos = to_crystal.position
	queue_redraw()


## Set edge endpoints directly (for when crystals aren't available)
func set_endpoints(from_pos: Vector2, to_pos: Vector2) -> void:
	_from_pos = from_pos
	_to_pos = to_pos
	queue_redraw()


## Set the visual edge type
func set_edge_type(type_name: String) -> void:
	if type_name.to_lower() in EDGE_STYLES:
		edge_type = type_name.to_lower()
	else:
		push_warning("EdgeRenderer: Unknown edge type '%s', using standard" % type_name)
		edge_type = "standard"
	queue_redraw()


## Play flash effect (valid symmetry)
func play_flash() -> void:
	_flash_intensity = 1.5


## Play dim effect (invalid attempt)
func play_dim() -> void:
	_dim_amount = 1.0


## Play violation highlight (red pulse showing broken structure)
func play_violation() -> void:
	_violation_intensity = 1.0


## Update endpoints when crystals swap
func update_binding(from_crystal: CrystalNode, to_crystal: CrystalNode) -> void:
	_from_crystal = from_crystal
	_to_crystal = to_crystal
