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

## Layer 5 coset coloring state
var _coset_coloring: Dictionary = {}   ## room_idx → Color (coset color for each room)
var _coset_groups: Array = []          ## Array[Array[int]] — room indices grouped by coset
var _coset_active: bool = false        ## Whether coset coloring mode is active

## Layer 5 merge animation state
var _merge_active: bool = false        ## Whether a merge animation is running
var _merge_progress: float = 0.0       ## 0.0 → 1.0 animation progress
var _merge_targets: Dictionary = {}    ## room_idx → target_pos (centroid of its coset)
var _merge_original_pos: Array = []    ## Saved original positions before merge

## Layer 5 quotient graph (shown after merge completes)
var _quotient_graph_active: bool = false ## Whether to show the merged quotient graph
var _quotient_nodes: Array = []          ## Array[{pos: Vector2, color: Color, label: String, rooms: Array}]
var _quotient_edges: Array = []          ## Array[{from: int, to: int}] — indices into _quotient_nodes


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
	var margin: float = 40.0
	for _iter in range(200):
		var forces: Array = []
		forces.resize(n)
		for i in range(n):
			forces[i] = Vector2.ZERO

		# Repulsion between all pairs (scaled up for larger node sizes)
		var repulsion: float = 2400.0
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


# --- Layer 5: Coset Coloring API ---

## Set coset coloring: color each room by its coset class.
## cosets: Array[{representative: String, elements: Array[String]}]
## coset_colors: Array[Color] — one per coset (cycled if fewer than cosets)
func set_coset_coloring(cosets: Array, coset_colors: Array = []) -> void:
	_coset_coloring.clear()
	_coset_groups.clear()
	_coset_active = false

	if cosets.is_empty() or room_state == null:
		queue_redraw()
		return

	# Default palette if none provided
	if coset_colors.is_empty():
		coset_colors = _default_coset_colors()

	for ci in range(cosets.size()):
		var coset: Dictionary = cosets[ci]
		var elements: Array = coset.get("elements", [])
		var color: Color = coset_colors[ci % coset_colors.size()]

		var room_indices: Array = []
		for sid in elements:
			var ridx: int = _sym_id_to_room_idx(sid)
			if ridx >= 0:
				_coset_coloring[ridx] = color
				room_indices.append(ridx)

		_coset_groups.append(room_indices)

	_coset_active = true
	queue_redraw()


## Clear coset coloring and any merge/quotient state.
## Restores room positions to pre-merge values if a merge was in progress or completed.
func clear_coset_coloring() -> void:
	# Restore original positions if a merge modified them
	if not _merge_original_pos.is_empty():
		for ridx in range(mini(positions.size(), _merge_original_pos.size())):
			positions[ridx] = _merge_original_pos[ridx]

	_coset_coloring.clear()
	_coset_groups.clear()
	_coset_active = false
	_merge_active = false
	_merge_progress = 0.0
	_merge_targets.clear()
	_merge_original_pos.clear()
	_quotient_graph_active = false
	_quotient_nodes.clear()
	_quotient_edges.clear()
	queue_redraw()


## Start the merge animation: rooms within each coset slide toward their centroid,
## then the quotient graph is shown.
## cosets: same format as set_coset_coloring
## coset_colors: matching color array
## quotient_table: {rep_a: {rep_b: rep_result}} — for drawing quotient edges
func start_merge_animation(cosets: Array, coset_colors: Array,
		quotient_table: Dictionary) -> void:
	if room_state == null or positions.is_empty() or cosets.is_empty():
		return

	# Ensure coset coloring is active
	if not _coset_active:
		set_coset_coloring(cosets, coset_colors)

	# Save original positions
	_merge_original_pos = positions.duplicate()
	_merge_targets.clear()

	# Compute centroid for each coset and assign targets
	for ci in range(_coset_groups.size()):
		var group: Array = _coset_groups[ci]
		if group.is_empty():
			continue
		var centroid: Vector2 = Vector2.ZERO
		var count: int = 0
		for ridx in group:
			if ridx >= 0 and ridx < positions.size():
				centroid += positions[ridx]
				count += 1
		if count > 0:
			centroid /= float(count)
		for ridx in group:
			_merge_targets[ridx] = centroid

	# Prepare quotient graph nodes (one per coset, at centroid position)
	_quotient_nodes.clear()
	_quotient_edges.clear()

	if coset_colors.is_empty():
		coset_colors = _default_coset_colors()

	var rep_to_qnode: Dictionary = {}  # representative sym_id -> quotient node index
	for ci in range(cosets.size()):
		var coset: Dictionary = cosets[ci]
		var rep: String = coset.get("representative", "")
		var elements: Array = coset.get("elements", [])
		var color: Color = coset_colors[ci % coset_colors.size()]

		# Centroid position
		var centroid: Vector2 = Vector2.ZERO
		var count: int = 0
		for sid in elements:
			var ridx: int = _sym_id_to_room_idx(sid)
			if ridx >= 0 and ridx < positions.size():
				centroid += positions[ridx]
				count += 1
		if count > 0:
			centroid /= float(count)

		var room_indices: Array = []
		for sid in elements:
			var ridx: int = _sym_id_to_room_idx(sid)
			if ridx >= 0:
				room_indices.append(ridx)

		# Label: representative name or coset index
		var label: String = str(ci)
		# Try getting the room index of the representative for display
		var rep_ridx: int = _sym_id_to_room_idx(rep)
		if rep_ridx > 0:
			label = str(rep_ridx)
		elif rep_ridx == 0:
			label = "\u2302"  # ⌂ for home coset

		_quotient_nodes.append({
			"pos": centroid,
			"color": color,
			"label": label,
			"rooms": room_indices,
		})
		rep_to_qnode[rep] = ci

	# Build quotient edges from the multiplication table
	# Edge from coset A to coset B if A * B != A and A * B != identity (to reduce clutter)
	# Actually, draw all non-self non-identity products as edges
	var drawn_qedges: Dictionary = {}
	for rep_a in quotient_table:
		if not rep_to_qnode.has(rep_a):
			continue
		var qi_a: int = rep_to_qnode[rep_a]
		var row: Dictionary = quotient_table[rep_a]
		for rep_b in row:
			if not rep_to_qnode.has(rep_b):
				continue
			var qi_b: int = rep_to_qnode[rep_b]
			var result_rep: String = row[rep_b]
			if not rep_to_qnode.has(result_rep):
				continue
			var qi_result: int = rep_to_qnode[result_rep]
			# Draw edge from qi_b to qi_result (applying coset A maps B→result)
			if qi_b == qi_result:
				continue
			var edge_key: String = "%d_%d" % [mini(qi_b, qi_result), maxi(qi_b, qi_result)]
			if drawn_qedges.has(edge_key):
				continue
			drawn_qedges[edge_key] = true
			_quotient_edges.append({"from": qi_b, "to": qi_result})

	# Start the merge animation
	_merge_active = true
	_merge_progress = 0.0
	_quotient_graph_active = false


## Helper: map sym_id to room index.
func _sym_id_to_room_idx(sym_id: String) -> int:
	if room_state == null:
		return -1
	for i in range(room_state.perm_ids.size()):
		if room_state.perm_ids[i] == sym_id:
			return i
	return -1


## Default coset color palette (matches QuotientPanel.COSET_COLORS).
func _default_coset_colors() -> Array:
	return [
		Color(0.85, 0.45, 0.95, 0.9),
		Color(0.40, 0.75, 1.00, 0.9),
		Color(0.95, 0.65, 0.25, 0.9),
		Color(0.40, 0.95, 0.55, 0.9),
		Color(0.95, 0.45, 0.55, 0.9),
		Color(0.70, 0.85, 0.30, 0.9),
		Color(0.50, 0.55, 1.00, 0.9),
		Color(0.95, 0.80, 0.30, 0.9),
		Color(0.35, 0.85, 0.85, 0.9),
		Color(0.90, 0.55, 0.70, 0.9),
		Color(0.60, 0.95, 0.80, 0.9),
		Color(0.80, 0.60, 0.40, 0.9),
	]


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

	# Layer 5: Merge animation tick
	if _merge_active:
		_merge_progress += delta * 0.7  # ~1.4 seconds total
		if _merge_progress >= 1.0:
			_merge_progress = 1.0
			_merge_active = false
			_quotient_graph_active = true

		# Interpolate room positions toward coset centroids
		for ridx in _merge_targets:
			if ridx >= 0 and ridx < positions.size() and ridx < _merge_original_pos.size():
				var orig: Vector2 = _merge_original_pos[ridx]
				var target: Vector2 = _merge_targets[ridx]
				# Ease-in-out curve
				var t: float = _merge_progress
				var eased: float = t * t * (3.0 - 2.0 * t)  # smoothstep
				positions[ridx] = orig.lerp(target, eased)

		queue_redraw()


func _draw() -> void:
	if room_state == null or positions.is_empty():
		return

	var n: int = room_state.group_order

	# --- Layer 5 quotient graph (after merge completes) ---
	if _quotient_graph_active:
		_draw_quotient_graph()
		return  # Only show the quotient graph, not the original map

	# --- Layer 5 coset coloring (edges between cosets) ---
	if _coset_active:
		_draw_coset_edges(n)

	# --- Layer 3 subgroup highlight (below everything) ---
	if not _coset_active:
		_draw_subgroup_highlight(n)

	# --- Fading transition edges ---
	_draw_fading_edges(n)

	# --- Hover key preview ---
	_draw_key_preview(n)

	# --- Room nodes (with coset coloring if active) ---
	_draw_room_nodes(n)


## Layer 5: Draw coset-aware edges.
## Intra-coset edges: dashed, dim. Inter-coset edges: solid, bright.
func _draw_coset_edges(n: int) -> void:
	if not _coset_active or room_state == null:
		return

	# Build room_idx → coset_index map for O(1) lookup
	var room_to_coset: Dictionary = {}
	for ci in range(_coset_groups.size()):
		for ridx in _coset_groups[ci]:
			room_to_coset[ridx] = ci

	# Draw edges for all key-transitions between discovered rooms
	var drawn: Dictionary = {}  # edge_key -> true
	for from_room in range(n):
		if from_room >= positions.size():
			continue
		if not room_state.is_discovered(from_room):
			continue
		for key_room in range(1, n):  # skip identity
			var to_room: int = room_state.cayley_table[from_room][key_room]
			if from_room == to_room:
				continue
			if to_room >= positions.size() or not room_state.is_discovered(to_room):
				continue
			var edge_key: String = "%d_%d" % [mini(from_room, to_room), maxi(from_room, to_room)]
			if drawn.has(edge_key):
				continue
			drawn[edge_key] = true

			var p1: Vector2 = positions[from_room]
			var p2: Vector2 = positions[to_room]
			var delta: Vector2 = p2 - p1
			var length: float = delta.length()
			if length < 1.0:
				continue

			var same_coset: bool = (room_to_coset.get(from_room, -1) == room_to_coset.get(to_room, -2))

			if same_coset:
				# Intra-coset: dashed, dim, thin
				var coset_color: Color = _coset_coloring.get(from_room, Color.WHITE)
				coset_color.a = 0.15
				_draw_dashed_line(p1, p2, coset_color, 1.0, 4.0, 3.0)
			else:
				# Inter-coset: solid, bright, thicker
				var color_a: Color = _coset_coloring.get(from_room, Color.WHITE)
				var color_b: Color = _coset_coloring.get(to_room, Color.WHITE)
				# Blend colors
				var edge_color: Color = Color(
					(color_a.r + color_b.r) * 0.5,
					(color_a.g + color_b.g) * 0.5,
					(color_a.b + color_b.b) * 0.5,
					0.5
				)
				# Curved line
				var normal: Vector2 = Vector2(-delta.y, delta.x) / length * 8.0
				var mid: Vector2 = (p1 + p2) / 2.0
				var control: Vector2 = mid + normal
				var prev: Vector2 = p1
				for s in range(1, 9):
					var t: float = float(s) / 8.0
					var pt: Vector2 = (1.0 - t) * (1.0 - t) * p1 + 2.0 * (1.0 - t) * t * control + t * t * p2
					draw_line(prev, pt, edge_color, 1.8, true)
					prev = pt


## Layer 5: Draw the quotient graph (after merge animation completes).
## Shows coset nodes at centroid positions with colored squares and
## edges between distinct cosets from the quotient multiplication table.
func _draw_quotient_graph() -> void:
	if _quotient_nodes.is_empty():
		return

	var count: int = _quotient_nodes.size()
	var node_sz: float = 32.0 if count <= 6 else (24.0 if count <= 12 else 18.0)
	var half: float = node_sz / 2.0

	# --- Draw quotient edges first (below nodes) ---
	for edge in _quotient_edges:
		var fi: int = edge["from"]
		var ti: int = edge["to"]
		if fi < 0 or fi >= count or ti < 0 or ti >= count:
			continue
		var p1: Vector2 = _quotient_nodes[fi]["pos"]
		var p2: Vector2 = _quotient_nodes[ti]["pos"]
		var delta: Vector2 = p2 - p1
		var length: float = delta.length()
		if length < 1.0:
			continue

		var color_a: Color = _quotient_nodes[fi]["color"]
		var color_b: Color = _quotient_nodes[ti]["color"]
		var edge_color: Color = Color(
			(color_a.r + color_b.r) * 0.5,
			(color_a.g + color_b.g) * 0.5,
			(color_a.b + color_b.b) * 0.5,
			0.6
		)

		# Curved line
		var normal: Vector2 = Vector2(-delta.y, delta.x) / length * 12.0
		var mid: Vector2 = (p1 + p2) / 2.0
		var control: Vector2 = mid + normal
		var prev: Vector2 = p1
		for s in range(1, 11):
			var t: float = float(s) / 10.0
			var pt: Vector2 = (1.0 - t) * (1.0 - t) * p1 + 2.0 * (1.0 - t) * t * control + t * t * p2
			draw_line(prev, pt, edge_color, 2.5, true)
			prev = pt

	# --- Draw quotient nodes ---
	for qi in range(count):
		var qnode: Dictionary = _quotient_nodes[qi]
		var pos: Vector2 = qnode["pos"]
		var color: Color = qnode["color"]
		var label: String = qnode["label"]

		# Glow rings
		var glow_col: Color = color
		for g in range(3):
			var grow: float = 5.0 + float(g) * 4.0
			var glow_rect: Rect2 = Rect2(
				pos.x - half - grow, pos.y - half - grow,
				node_sz + grow * 2, node_sz + grow * 2
			)
			glow_col.a = 0.25 - float(g) * 0.07
			draw_rect(glow_rect, glow_col, true)

		# Filled square
		var rect: Rect2 = Rect2(pos.x - half, pos.y - half, node_sz, node_sz)
		draw_rect(rect, color, true)

		# Bright border
		var border_col: Color = Color(color.r, color.g, color.b, 1.0)
		draw_rect(rect, border_col, false, 2.0)

		# Label
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 13 if node_sz >= 28.0 else (11 if node_sz >= 20.0 else 9)
		var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos: Vector2 = Vector2(pos.x - text_size.x / 2.0, pos.y + text_size.y / 3.0)
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# --- Title label ---
	var title_font: Font = ThemeDB.fallback_font
	var title_text: String = "G/N  (%d элементов)" % count
	var title_size: Vector2 = title_font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
	var title_pos: Vector2 = Vector2((panel_size.x - title_size.x) / 2.0, 18)
	draw_string(title_font, title_pos, title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(0.65, 0.35, 0.90, 0.8))


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
			draw_line(prev, pt, edge_color, 3.0 * alpha, true)
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
				var sz: float = 7.0 * alpha
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

		# Previously traversed edges are brighter (0.45 vs 0.25)
		var edge_key: String = "%d_%d" % [from_room, to_room]
		var key_color: Color = base_color
		key_color.a = 0.45 if traversed.has(edge_key) else 0.25
		var line_w: float = 2.0 if traversed.has(edge_key) else 1.5

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
	var show_labels_always: bool = n <= 24

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

		# Use coset color if active, otherwise original room color
		var col: Color
		if _coset_active and _coset_coloring.has(i):
			col = _coset_coloring[i]
		else:
			col = room_state.colors[i] if i < room_state.colors.size() else Color.WHITE
		var rect: Rect2 = Rect2(pos.x - half, pos.y - half, sz, sz)

		# During merge animation: fade individual rooms as they converge
		var merge_alpha: float = 1.0
		if _merge_active:
			# After 60% progress, start fading out individual rooms
			merge_alpha = clampf(1.0 - (_merge_progress - 0.6) / 0.4, 0.0, 1.0)

		# Glow for current room (or coset glow)
		if is_current and not _coset_active:
			var glow_col: Color = col
			glow_col.a = 0.3 * merge_alpha
			for g in range(4):
				var grow: float = 4.0 + float(g) * 4.0
				var glow_rect: Rect2 = Rect2(rect.position - Vector2(grow, grow), rect.size + Vector2(grow * 2, grow * 2))
				var ga: Color = glow_col
				ga.a = (0.3 - float(g) * 0.065) * merge_alpha
				draw_rect(glow_rect, ga, true)
		elif _coset_active and not _merge_active:
			# Coset glow: subtle ring in coset color
			var glow_col: Color = col
			glow_col.a = 0.15
			var glow_rect: Rect2 = Rect2(
				pos.x - half - 3, pos.y - half - 3,
				sz + 6, sz + 6)
			draw_rect(glow_rect, glow_col, true)

		# Fill
		var fill_col: Color = col
		if is_current and not _coset_active:
			fill_col.a = 1.0 * merge_alpha
		elif is_hover:
			fill_col.a = 0.85 * merge_alpha
		elif _coset_active:
			fill_col.a = 0.80 * merge_alpha
		else:
			fill_col.a = 0.50 * merge_alpha

		draw_rect(rect, fill_col, true)

		# Outline
		var outline_col: Color = col
		if _coset_active:
			outline_col.a = 0.9 * merge_alpha
		else:
			outline_col.a = (1.0 if is_current else 0.35) * merge_alpha
		var outline_width: float = 2.0 if (is_current or _coset_active) else 1.0
		draw_rect(rect, outline_col, false, outline_width)

		# Label (number or home symbol)
		if show_labels_always or is_current or is_hover:
			var font: Font = ThemeDB.fallback_font
			var font_size: int = 12 if sz >= 20.0 else (10 if sz >= 14.0 else 8)
			var label_text: String = "\u2302" if i == 0 else str(i)  # ⌂ for home
			var label_col: Color = Color.WHITE if is_current else (Color(0.85, 0.85, 0.85, 0.9) if is_hover else Color(0.55, 0.55, 0.6, 0.85))
			var text_size: Vector2 = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			# Draw label INSIDE the room square (centered)
			var text_pos: Vector2 = Vector2(pos.x - text_size.x / 2.0, pos.y + text_size.y / 3.0)
			draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_col)


## Get the node square size based on total room count.
## Sizes scaled up significantly for readability (especially on mobile).
func _get_node_size(n: int) -> float:
	if n > 24:
		return 16.0
	elif n > 16:
		return 20.0
	elif n > 12:
		return 24.0
	elif n > 6:
		return 28.0
	else:
		return 32.0


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
	var hit_margin: float = 6.0  # extra pixels for easier clicking

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
