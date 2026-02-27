class_name MapLayoutEngine
extends RefCounted
## BFS-based tree layout engine for the Hall Tree map.
##
## Computes positions for hall nodes using a layer-based layout:
## - Start halls at the top of each wing's zone
## - BFS from start halls assigns layers
## - Each BFS layer = one horizontal row; nodes evenly spaced
## - Wings are stacked vertically with gaps between them
##
## Usage:
##   var positions = MapLayoutEngine.compute_layout(hall_tree)
##   # positions is Dictionary: hall_id -> Vector2

const WING_VERTICAL_GAP := 200.0        ## Space between wings
const LAYER_HEIGHT := 140.0              ## Vertical distance between layers
const NODE_HORIZONTAL_SPACING := 160.0   ## Min horizontal gap between nodes
const WING_HEADER_HEIGHT := 100.0        ## Space for wing title + progress bar


## Returns Dictionary: hall_id -> Vector2 (position in world coordinates).
## Also returns wing_headers: wing_id -> {position: Vector2, name, subtitle, progress_y}
## Full result: {positions: Dict, wing_headers: Dict, total_height: float}
static func compute_layout(tree: HallTreeData) -> Dictionary:
	var positions: Dictionary = {}
	var wing_headers: Dictionary = {}
	var current_y := 0.0

	for wing in tree.get_ordered_wings():
		# Store wing header position
		wing_headers[wing.id] = {
			"position": Vector2(0.0, current_y),
			"name": wing.name,
			"subtitle": wing.subtitle,
		}

		current_y += WING_HEADER_HEIGHT

		# BFS layer assignment within this wing
		var layers: Array = _bfs_layers(
			wing.start_halls,
			wing.halls,
			tree
		)

		# Position nodes in each layer
		for layer_idx in range(layers.size()):
			var layer: Array = layers[layer_idx]
			var layer_width: float = layer.size() * NODE_HORIZONTAL_SPACING
			var start_x: float = -layer_width / 2.0 + NODE_HORIZONTAL_SPACING / 2.0

			for i in range(layer.size()):
				var hall_id: String = layer[i]
				positions[hall_id] = Vector2(
					start_x + i * NODE_HORIZONTAL_SPACING,
					current_y + layer_idx * LAYER_HEIGHT
				)

		var num_layers := layers.size() if not layers.is_empty() else 1
		current_y += num_layers * LAYER_HEIGHT + WING_VERTICAL_GAP

	return {
		"positions": positions,
		"wing_headers": wing_headers,
		"total_height": current_y,
	}


## BFS from start_halls, grouping nodes by BFS depth.
## Only includes halls that belong to hall_set (i.e., within the wing).
## Unreachable halls are appended to the last layer.
static func _bfs_layers(starts: Array, hall_set: Array, tree: HallTreeData) -> Array:
	var visited: Dictionary = {}
	var layers: Array = []

	# Seed the BFS with start halls
	var current_layer: Array = []
	for start in starts:
		if start in hall_set:
			current_layer.append(start)
			visited[start] = true

	while not current_layer.is_empty():
		layers.append(current_layer)
		var next_layer: Array = []
		for hall_id in current_layer:
			var neighbors: Array = tree.get_hall_edges(hall_id)
			for neighbor in neighbors:
				if neighbor in hall_set and not (neighbor in visited):
					next_layer.append(neighbor)
					visited[neighbor] = true
		current_layer = next_layer

	# Append any orphan halls (not reachable from starts) to the last layer
	var orphans: Array = []
	for hall_id in hall_set:
		if not (hall_id in visited):
			orphans.append(hall_id)

	if not orphans.is_empty():
		if layers.is_empty():
			layers.append(orphans)
		else:
			layers.append(orphans)

	return layers
