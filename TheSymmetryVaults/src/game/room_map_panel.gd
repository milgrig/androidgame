class_name RoomMapPanel
extends Node2D
## RoomMapPanel — Canvas that draws the room map with BFS layout.
##
## Rooms are drawn as colored squares arranged in concentric layers by BFS
## distance from Home (room 0). Layout uses force-directed relaxation
## to spread nodes evenly. Ported from redesign_map/rooms-keys.html.
##
## Usage:
##   var panel = RoomMapPanel.new()
##   panel.setup(room_state, panel_size)
##   add_child(panel)

# --- Signals ---
signal room_hovered(room_idx: int)   ## -1 when nothing hovered
signal room_clicked(room_idx: int)

# --- Configuration ---

## Size of the drawable area (set via setup or resize)
var panel_size: Vector2 = Vector2(400, 400)

# --- State ---

## Reference to the RoomState data model
var room_state: RoomState = null

## Computed positions for each room (in local coordinates)
var positions: Array = []  # Array[Vector2]

## BFS distances from home (used for layout layers)
var _bfs_dist: Array = []  # Array[int]

## Currently hovered room index (-1 = none)
var _hover_room: int = -1

## Currently highlighted key for preview (-1 = none)
var highlight_key: int = -1

## Whether the Home room (index 0) is visible on the map.
## Set to false at level start; becomes true after the first correct
## permutation (key) is discovered.
var home_visible: bool = false

## Fading transition edges: {from: int, to: int, key: int, color: Color, alpha: float}
var _fading_edges: Array = []

## Layer 3 subgroup highlight: array of room indices (keys from subgroup mapped to rooms).
## When non-empty, these rooms glow gold and all internal transitions are drawn.
var _subgroup_rooms: Array = []  # Array[int] — room indices in the highlighted subgroup
var _subgroup_sym_ids: Array = []  # Array[String] — sym_ids for transition drawing


# --- Public API ---

## Initialize with a RoomState and panel dimensions.
func setup(p_room_state: RoomState, p_panel_size: Vector2 = Vector2(400, 400)) -> void:
	room_state = p_room_state
	panel_size = p_panel_size
	_hover_room = -1
	highlight_key = -1
	_fading_edges.clear()
	compute_layout()


## Recompute layout positions. Call on level load or resize.
func compute_layout() -> void:
	if room_state == null or room_state.group_order == 0:
		positions.clear()
		_bfs_dist.clear()
		queue_redraw()
		return

	var n: int = room_state.group_order
	var cx: float = panel_size.x / 2.0
	var cy: float = panel_size.y / 2.0

	# --- BFS from room 0 using all non-identity keys ---
	_bfs_dist.clear()
	_bfs_dist.resize(n)
	for i in range(n):
		_bfs_dist[i] = 999

	_bfs_dist[0] = 0
	var queue: Array = [0]
	var visited: Dictionary = {0: true}
	var qi: int = 0

	while qi < queue.size():
		var v: int = queue[qi]
		qi += 1
		for k in range(1, n):  # skip key 0 (identity)
			var next: int = room_state.cayley_table[v][k]
			if not visited.has(next):
				visited[next] = true
				_bfs_dist[next] = _bfs_dist[v] + 1
				queue.append(next)

	# --- Group by layer (distance) ---
	var layers: Dictionary = {}  # dist -> Array[int]
	for i in range(n):
		var d: int = _bfs_dist[i]
		if not layers.has(d):
			layers[d] = []
		layers[d].append(i)

	var layer_keys: Array = layers.keys()
	layer_keys.sort()
	var total_layers: int = layer_keys.size()

	# --- Initial placement: concentric arcs ---
	var max_radius: float = minf(panel_size.x, panel_size.y) * 0.38
	positions.clear()
	positions.resize(n)

	for i in range(n):
		var d: int = _bfs_dist[i]
		if d == 0:
			positions[i] = Vector2(cx, cy)
			continue

		var layer: Array = layers[d]
		var idx: int = layer.find(i)
		var count: int = layer.size()
		var r: float = (float(d) / maxf(1.0, float(total_layers - 1))) * max_radius

		var angle: float
		if count == 1:
			angle = -PI / 2.0
		else:
			var angle_span: float = minf(TAU, count * 0.6)
			var start_angle: float = -PI / 2.0 - angle_span / 2.0 + d * 0.4
			angle = start_angle + (float(idx) / float(count - 1)) * angle_span

		positions[i] = Vector2(cx + r * cos(angle), cy + r * sin(angle))

	# --- Force-directed relaxation (200 iterations) ---
	var margin: float = 30.0
	for _iter in range(200):
		var forces: Array = []
		forces.resize(n)
		for i in range(n):
			forces[i] = Vector2.ZERO

		# Repulsion between all pairs
		var repulsion: float = 800.0
		for i in range(n):
			for j in range(i + 1, n):
				var delta: Vector2 = positions[j] - positions[i]
				var dist: float = maxf(1.0, delta.length())
				var f: float = repulsion / (dist * dist)
				var dir: Vector2 = delta / dist
				forces[i] -= dir * f
				forces[j] += dir * f

		# Attraction toward target radius (keep nodes on their layer ring)
		for i in range(n):
			if _bfs_dist[i] > 0:
				var target_r: float = (float(_bfs_dist[i]) / maxf(1.0, float(total_layers - 1))) * max_radius
				var cur_delta: Vector2 = positions[i] - Vector2(cx, cy)
				var cur_r: float = cur_delta.length()
				if cur_r > 0.0:
					var diff: float = cur_r - target_r
					forces[i] -= (cur_delta / cur_r) * diff * 0.1

		# Apply forces (skip home at index 0)
		for i in range(1, n):
			positions[i] += forces[i] * 0.3
			# Clamp within panel bounds
			positions[i].x = clampf(positions[i].x, margin, panel_size.x - margin)
			positions[i].y = clampf(positions[i].y, margin, panel_size.y - margin)

	queue_redraw()


## Resize the panel area and recompute layout.
func resize(new_size: Vector2) -> void:
	panel_size = new_size
	compute_layout()


## Add a fading transition edge (called when a key is applied).
## Color is derived from room_state.colors[key_idx].
func add_fading_edge(from_room: int, to_room: int, key_idx: int) -> void:
	var key_color: Color = Color.WHITE
	if room_state != null and key_idx >= 0 and key_idx < room_state.colors.size():
		key_color = room_state.colors[key_idx]
	_fading_edges.append({
		"from": from_room,
		"to": to_room,
		"key": key_idx,
		"color": key_color,
		"alpha": 1.0,
	})


## Legacy alias kept for compatibility.
func add_transition_edge(from_room: int, to_room: int, key_color: Color) -> void:
	_fading_edges.append({
		"from": from_room,
		"to": to_room,
		"key": -1,
		"color": key_color,
		"alpha": 1.0,
	})


## Set which key is highlighted for hover preview (-1 to clear).
func set_hover_key(key_idx: int) -> void:
	highlight_key = key_idx
	queue_redraw()


## Clear hover key preview.
func clear_hover_key() -> void:
	highlight_key = -1
	queue_redraw()


## Legacy alias kept for compatibility.
func set_highlight_key(key_idx: int) -> void:
	set_hover_key(key_idx)


## Highlight a subgroup on the map: show its rooms with gold glow
## and draw all internal transitions (cosets / orbits).
## sym_ids: the sym_ids of the subgroup elements.
## If empty, clears the highlight.
func highlight_subgroup(sym_ids: Array) -> void:
	_subgroup_sym_ids = sym_ids
	_subgroup_rooms.clear()
	if room_state == null or sym_ids.is_empty():
		queue_redraw()
		return
	# Map sym_ids to room indices
	for sid in sym_ids:
		for i in range(room_state.perm_ids.size()):
			if room_state.perm_ids[i] == sid:
				_subgroup_rooms.append(i)
				break
	queue_redraw()


## Clear the subgroup highlight.
func clear_subgroup_highlight() -> void:
	_subgroup_rooms.clear()
	_subgroup_sym_ids.clear()
	queue_redraw()


# --- Drawing ---

func _process(delta: float) -> void:
	# Decay fading edges
	var had_edges: bool = not _fading_edges.is_empty()
	var i: int = _fading_edges.size() - 1
	while i >= 0:
		_fading_edges[i]["alpha"] *= 0.985
		if _fading_edges[i]["alpha"] < 0.03:
			_fading_edges.remove_at(i)
		i -= 1

	if had_edges or not _fading_edges.is_empty():
		queue_redraw()


func _draw() -> void:
	if room_state == null or positions.is_empty():
		return

	var n: int = room_state.group_order

	# --- Layer 3 subgroup highlight (below everything) ---
	_draw_subgroup_highlight(n)

	# --- Fading transition edges ---
	_draw_fading_edges(n)

	# --- Hover key preview ---
	_draw_key_preview(n)

	# --- Room nodes ---
	_draw_room_nodes(n)


## Draw the subgroup highlight: gold glow on subgroup rooms + internal transitions.
func _draw_subgroup_highlight(n: int) -> void:
	if _subgroup_rooms.is_empty() or room_state == null:
		return

	var gold: Color = Color(0.95, 0.80, 0.20, 1.0)
	var gold_dim: Color = Color(0.95, 0.80, 0.20, 0.3)
	var gold_edge: Color = Color(0.95, 0.80, 0.20, 0.45)

	var subgroup_set: Dictionary = {}  # room_idx -> true for O(1) lookup
	for r in _subgroup_rooms:
		subgroup_set[r] = true

	# Draw internal transitions: for each subgroup room, apply each subgroup key
	# and draw the resulting edge if both endpoints are in the subgroup.
	var drawn_edges: Dictionary = {}  # "from_to" -> true to avoid duplicates
	for from_room in _subgroup_rooms:
		if from_room < 0 or from_room >= n or from_room >= positions.size():
			continue
		for key_room in _subgroup_rooms:
			if key_room < 0 or key_room >= n:
				continue
			var to_room: int = room_state.cayley_table[from_room][key_room]
			if not subgroup_set.has(to_room):
				continue
			if from_room == to_room:
				continue
			# Avoid drawing duplicate edges in both directions
			var edge_key: String = "%d_%d" % [mini(from_room, to_room), maxi(from_room, to_room)]
			if drawn_edges.has(edge_key):
				continue
			drawn_edges[edge_key] = true

			if to_room >= positions.size():
				continue
			var p1: Vector2 = positions[from_room]
			var p2: Vector2 = positions[to_room]
			var delta: Vector2 = p2 - p1
			var length: float = delta.length()
			if length < 1.0:
				continue
			var normal: Vector2 = Vector2(-delta.y, delta.x) / length * 10.0
			var mid: Vector2 = (p1 + p2) / 2.0
			var control: Vector2 = mid + normal

			# Draw curved edge in gold
			var prev: Vector2 = p1
			for s in range(1, 11):
				var t: float = float(s) / 10.0
				var pt: Vector2 = (1.0 - t) * (1.0 - t) * p1 + 2.0 * (1.0 - t) * t * control + t * t * p2
				draw_line(prev, pt, gold_edge, 1.8, true)
				prev = pt

	# Draw gold glow rings around subgroup rooms
	var sz: float = _get_node_size(n)
	var half: float = sz / 2.0
	for room_idx in _subgroup_rooms:
		if room_idx < 0 or room_idx >= n or room_idx >= positions.size():
			continue
		var pos: Vector2 = positions[room_idx]
		# Outer glow (3 rings)
		for g in range(3):
			var grow: float = 4.0 + float(g) * 3.5
			var glow_rect: Rect2 = Rect2(
				pos.x - half - grow, pos.y - half - grow,
				sz + grow * 2, sz + grow * 2
			)
			var ga: Color = gold_dim
			ga.a = 0.25 - float(g) * 0.07
			draw_rect(glow_rect, ga, true)
		# Gold border
		var rect: Rect2 = Rect2(pos.x - half - 1, pos.y - half - 1, sz + 2, sz + 2)
		draw_rect(rect, gold, false, 1.5)


func _draw_fading_edges(n: int) -> void:
	for edge in _fading_edges:
		var from_idx: int = edge["from"]
		var to_idx: int = edge["to"]
		if from_idx < 0 or from_idx >= n or to_idx < 0 or to_idx >= n:
			continue
		if from_idx == to_idx:
			continue
		# Hide edges involving Home when home is not visible
		if not home_visible and (from_idx == 0 or to_idx == 0):
			continue
		var p1: Vector2 = positions[from_idx]
		var p2: Vector2 = positions[to_idx]
		var edge_color: Color = edge["color"]
		var alpha: float = edge["alpha"]
		edge_color.a = alpha

		# Curved line (quadratic bezier approximation via 3 points)
		var mid: Vector2 = (p1 + p2) / 2.0
		var delta: Vector2 = p2 - p1
		var length: float = delta.length()
		if length < 1.0:
			continue
		var normal: Vector2 = Vector2(-delta.y, delta.x) / length * 15.0
		var control: Vector2 = mid + normal

		# Draw bezier as line segments
		var prev: Vector2 = p1
		var segments: int = 12
		for s in range(1, segments + 1):
			var t: float = float(s) / float(segments)
			var pt: Vector2 = (1.0 - t) * (1.0 - t) * p1 + 2.0 * (1.0 - t) * t * control + t * t * p2
			draw_line(prev, pt, edge_color, 2.5 * alpha, true)
			prev = pt

		# Arrow at t=0.78 — skip when too faint to avoid degenerate polygon
		if alpha >= 0.05:
			var at: float = 0.78
			var arrow_pos: Vector2 = (1.0 - at) * (1.0 - at) * p1 + 2.0 * (1.0 - at) * at * control + at * at * p2
			var tangent: Vector2 = 2.0 * (1.0 - at) * (control - p1) + 2.0 * at * (p2 - control)
			var tlen: float = tangent.length()
			if tlen > 0.0:
				var tdir: Vector2 = tangent / tlen
				var tnorm: Vector2 = Vector2(-tdir.y, tdir.x)
				var sz: float = 5.0 * alpha
				var pts: PackedVector2Array = PackedVector2Array([
					arrow_pos + tdir * sz,
					arrow_pos - tnorm * sz * 0.6,
					arrow_pos + tnorm * sz * 0.6,
				])
				draw_colored_polygon(pts, edge_color)


func _draw_key_preview(n: int) -> void:
	if highlight_key < 0 or highlight_key >= n or room_state == null:
		return

	var base_color: Color = room_state.colors[highlight_key] if highlight_key < room_state.colors.size() else Color.WHITE

	# Build set of previously traversed (from, to) pairs for this key
	var traversed: Dictionary = {}  # "from_to" -> true
	for entry in room_state.transition_history:
		if entry.get("key", -1) == highlight_key:
			var edge_key: String = "%d_%d" % [entry.get("from", -1), entry.get("to", -1)]
			traversed[edge_key] = true

	for from_room in range(n):
		if not room_state.is_discovered(from_room):
			continue
		# Hide edges involving Home when home is not visible
		if not home_visible and from_room == 0:
			continue
		var to_room: int = room_state.get_destination(from_room, highlight_key)
		if not room_state.is_discovered(to_room):
			continue
		if not home_visible and to_room == 0:
			continue
		if from_room == to_room:
			continue
		if from_room >= positions.size() or to_room >= positions.size():
			continue

		# Previously traversed edges are brighter (0.35 vs 0.2)
		var edge_key: String = "%d_%d" % [from_room, to_room]
		var key_color: Color = base_color
		key_color.a = 0.35 if traversed.has(edge_key) else 0.2
		var line_w: float = 1.5 if traversed.has(edge_key) else 1.0

		var p1: Vector2 = positions[from_room]
		var p2: Vector2 = positions[to_room]
		var delta: Vector2 = p2 - p1
		var length: float = delta.length()
		if length < 1.0:
			continue
		var normal: Vector2 = Vector2(-delta.y, delta.x) / length * 12.0
		var mid: Vector2 = (p1 + p2) / 2.0
		var control: Vector2 = mid + normal

		var prev: Vector2 = p1
		for s in range(1, 9):
			var t: float = float(s) / 8.0
			var pt: Vector2 = (1.0 - t) * (1.0 - t) * p1 + 2.0 * (1.0 - t) * t * control + t * t * p2
			draw_line(prev, pt, key_color, line_w, true)
			prev = pt


func _draw_room_nodes(n: int) -> void:
	var sz: float = _get_node_size(n)
	var half: float = sz / 2.0
	var show_labels_always: bool = n <= 16

	for i in range(n):
		if i >= positions.size():
			continue

		# Hide Home (room 0) until home_visible is set to true
		if i == 0 and not home_visible:
			continue

		var pos: Vector2 = positions[i]
		var is_discovered: bool = room_state.is_discovered(i)
		var is_current: bool = i == room_state.current_room
		var is_hover: bool = i == _hover_room

		if not is_discovered:
			# Undiscovered: dashed outline, very faint
			var rect: Rect2 = Rect2(pos.x - half, pos.y - half, sz, sz)
			_draw_dashed_rect(rect, Color(0.2, 0.2, 0.2, 0.12), 0.5)
			continue

		var col: Color = room_state.colors[i] if i < room_state.colors.size() else Color.WHITE
		var rect: Rect2 = Rect2(pos.x - half, pos.y - half, sz, sz)

		# Glow for current room
		if is_current:
			var glow_col: Color = col
			glow_col.a = 0.25
			for g in range(3):
				var grow: float = 3.0 + float(g) * 3.0
				var glow_rect: Rect2 = Rect2(rect.position - Vector2(grow, grow), rect.size + Vector2(grow * 2, grow * 2))
				var ga: Color = glow_col
				ga.a = 0.25 - float(g) * 0.07
				draw_rect(glow_rect, ga, true)

		# Fill
		var fill_col: Color = col
		if is_current:
			fill_col.a = 1.0
		elif is_hover:
			fill_col.a = 0.67
		else:
			fill_col.a = 0.33

		draw_rect(rect, fill_col, true)

		# Outline
		var outline_col: Color = col
		outline_col.a = 1.0 if is_current else 0.27
		var outline_width: float = 1.5 if is_current else 0.5
		draw_rect(rect, outline_col, false, outline_width)

		# Label (number or home symbol)
		if show_labels_always or is_current or is_hover:
			var font: Font = ThemeDB.fallback_font
			var font_size: int = 8 if sz > 9.0 else 6
			var label_text: String = "\u2302" if i == 0 else str(i)  # ⌂ for home
			var label_col: Color = Color.WHITE if is_current else (Color(0.8, 0.8, 0.8, 0.9) if is_hover else Color(0.47, 0.47, 0.47, 0.8))
			var text_size: Vector2 = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos: Vector2 = Vector2(pos.x - text_size.x / 2.0, pos.y + half + 3.0 + font_size * 0.8)
			draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_col)


## Get the node square size based on total room count.
func _get_node_size(n: int) -> float:
	if n > 16:
		return 7.0
	elif n > 12:
		return 9.0
	else:
		return 11.0


## Draw a dashed rectangle outline.
func _draw_dashed_rect(rect: Rect2, color: Color, width: float) -> void:
	var corners: Array = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for ci in range(4):
		var a: Vector2 = corners[ci]
		var b: Vector2 = corners[(ci + 1) % 4]
		_draw_dashed_line(a, b, color, width, 3.0, 3.0)


## Draw a dashed line.
func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash_len: float, gap_len: float) -> void:
	var delta: Vector2 = to - from
	var total_len: float = delta.length()
	if total_len < 0.5:
		return
	var dir: Vector2 = delta / total_len
	var pos: float = 0.0
	while pos < total_len:
		var seg_end: float = minf(pos + dash_len, total_len)
		draw_line(from + dir * pos, from + dir * seg_end, color, width, true)
		pos = seg_end + gap_len


# --- Input ---

func _input(event: InputEvent) -> void:
	if room_state == null or positions.is_empty():
		return

	if event is InputEventMouseMotion:
		var local_pos: Vector2 = _get_local_mouse(event)
		var prev_hover: int = _hover_room
		_hover_room = _hit_test(local_pos)
		if _hover_room != prev_hover:
			room_hovered.emit(_hover_room)
			queue_redraw()

	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var local_pos: Vector2 = _get_local_mouse(event)
			var hit: int = _hit_test(local_pos)
			if hit >= 0 and room_state.is_discovered(hit):
				room_clicked.emit(hit)


## Convert a mouse event position to local coordinates.
func _get_local_mouse(_event: InputEvent) -> Vector2:
	return get_local_mouse_position()


## Hit-test: find which room square contains the point. Returns -1 if none.
func _hit_test(local_pos: Vector2) -> int:
	if room_state == null:
		return -1
	var n: int = room_state.group_order
	var sz: float = _get_node_size(n)
	var half: float = sz / 2.0
	var hit_margin: float = 4.0  # extra pixels for easier clicking

	for i in range(n):
		if i >= positions.size():
			continue
		# Skip Home when hidden
		if i == 0 and not home_visible:
			continue
		var pos: Vector2 = positions[i]
		if absf(local_pos.x - pos.x) <= half + hit_margin and absf(local_pos.y - pos.y) <= half + hit_margin:
			return i
	return -1
