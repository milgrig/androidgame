## TargetPreviewDraw — draws a miniature graph showing the goal arrangement.
##
## Uses Control._draw() for reliable rendering inside CanvasLayer/HUD.
## Previous child-node approach (Line2D, Polygon2D) failed to render
## when the Control was parented inside a CanvasLayer hierarchy.

class_name TargetPreviewDraw
extends Control

# Data set by LevelScene._build_level()
var graph_nodes: Array = []   # [{id, color, position}]
var graph_edges: Array = []   # [{from, to, directed}]
var identity_found: bool = false

# Color map matching crystal_node.gd
const COLOR_MAP := {
	"red":    Color(0.95, 0.25, 0.2),
	"blue":   Color(0.2, 0.45, 0.95),
	"green":  Color(0.2, 0.85, 0.35),
	"yellow": Color(0.95, 0.85, 0.15),
	"purple": Color(0.7, 0.25, 0.9),
	"orange": Color(0.95, 0.55, 0.1),
	"cyan":   Color(0.1, 0.85, 0.85),
	"white":  Color(0.9, 0.9, 0.95),
	"pink":   Color(0.95, 0.45, 0.65),
	"gold":   Color(1.0, 0.85, 0.2),
}

## Explicit draw size (used for scaling calculations)
var _draw_size := Vector2(140, 127)

# Pre-computed draw data (built in setup, rendered in _draw)
var _edge_segments: Array = []   # [{from: Vector2, to: Vector2}]
var _node_circles: Array = []    # [{pos: Vector2, color: Color, label: String}]
var _node_radius: float = 8.0
var _has_data: bool = false


func setup(nodes: Array, edges: Array, draw_size: Vector2 = Vector2.ZERO) -> void:
	graph_nodes = nodes
	graph_edges = edges
	if draw_size != Vector2.ZERO:
		_draw_size = draw_size
	_compute_draw_data()
	queue_redraw()


func set_identity_found(found: bool) -> void:
	identity_found = found


func _compute_draw_data() -> void:
	_edge_segments.clear()
	_node_circles.clear()
	_has_data = false

	if graph_nodes.is_empty():
		return

	# Compute bounding box from node positions
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var positions_by_id: Dictionary = {}

	for node_data in graph_nodes:
		var pos_arr = node_data.get("position", [0, 0])
		var npos := Vector2(float(pos_arr[0]), float(pos_arr[1]))
		var nid: int = int(node_data.get("id", 0))
		positions_by_id[nid] = npos
		min_pos.x = min(min_pos.x, npos.x)
		min_pos.y = min(min_pos.y, npos.y)
		max_pos.x = max(max_pos.x, npos.x)
		max_pos.y = max(max_pos.y, npos.y)

	# Scale to fit within our drawing area with padding
	var draw_area := _draw_size
	var padding := 12.0
	var usable := draw_area - Vector2(padding * 2, padding * 2) - Vector2(_node_radius * 2, _node_radius * 2)

	var range_x := max_pos.x - min_pos.x
	var range_y := max_pos.y - min_pos.y
	if range_x < 1.0:
		range_x = 1.0
	if range_y < 1.0:
		range_y = 1.0

	var scale_factor: float = min(usable.x / range_x, usable.y / range_y)

	# Center offset
	var scaled_range := Vector2(range_x * scale_factor, range_y * scale_factor)
	var offset := (draw_area - scaled_range) / 2.0

	# Map positions into draw space
	var mapped_positions: Dictionary = {}
	for node_data in graph_nodes:
		var node_id: int = int(node_data.get("id", 0))
		var raw_pos: Vector2 = positions_by_id[node_id]
		var mapped := Vector2(
			(raw_pos.x - min_pos.x) * scale_factor + offset.x,
			(raw_pos.y - min_pos.y) * scale_factor + offset.y
		)
		mapped_positions[node_id] = mapped

	# --- Pre-compute edge segments ---
	for edge_data in graph_edges:
		var from_id: int = int(edge_data.get("from", 0))
		var to_id: int = int(edge_data.get("to", 0))
		if from_id in mapped_positions and to_id in mapped_positions:
			_edge_segments.append({
				"from": mapped_positions[from_id],
				"to": mapped_positions[to_id],
			})

	# --- Pre-compute node circles ---
	for node_data in graph_nodes:
		var node_id: int = int(node_data.get("id", 0))
		if node_id not in mapped_positions:
			continue
		var pos: Vector2 = mapped_positions[node_id]
		var color_name: String = node_data.get("color", "white")
		var col: Color = COLOR_MAP.get(color_name, Color(0.9, 0.9, 0.95))
		var label_str: String = node_data.get("label", "")
		_node_circles.append({
			"pos": pos,
			"color": col,
			"label": label_str,
		})

	_has_data = true


func _draw() -> void:
	if not _has_data:
		return

	var edge_color := Color(0.5, 0.55, 0.7, 0.6)

	# Draw edges
	for seg in _edge_segments:
		draw_line(seg["from"], seg["to"], edge_color, 1.5, true)

	# Draw node circles
	for nc in _node_circles:
		var pos: Vector2 = nc["pos"]
		var col: Color = nc["color"]
		var label_str: String = nc["label"]

		# Outer glow
		draw_circle(pos, _node_radius + 1.5, Color(col.r, col.g, col.b, 0.3))

		# Solid circle
		draw_circle(pos, _node_radius, col)

		# Inner highlight
		draw_circle(pos + Vector2(-2, -2), _node_radius * 0.35, Color(1, 1, 1, 0.35))

		# Label
		if label_str != "":
			var font := ThemeDB.fallback_font
			var font_size := 9
			if font:
				var text_size := font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
				var text_pos := pos - text_size / 2.0 + Vector2(0, text_size.y * 0.35)
				draw_string(font, text_pos, label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.95))
