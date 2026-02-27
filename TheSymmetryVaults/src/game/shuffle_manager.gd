## ShuffleManager — Handles level shuffling, initial positions, and seed generation.
##
## Responsibilities:
## - Generate deterministic shuffle seeds from level_id
## - Fisher-Yates shuffle (guaranteed != identity)
## - Track identity, initial (shuffled), and current arrangements
## - Build position maps from level node data

class_name ShuffleManager
extends RefCounted


# --- Arrangements ---
var identity_arrangement: Array[int] = []   # [0, 1, ..., n-1] — the GOAL
var initial_arrangement: Array[int] = []    # Shuffled starting arrangement (for RESET)
var current_arrangement: Array[int] = []    # Current state

# --- Shuffle state ---
var shuffle_seed: int = 0


## Initialize arrangements for a level.
## Builds identity from nodes, generates shuffle, sets initial + current.
func setup(level_id: String, nodes_data: Array) -> void:
	# Build identity arrangement: [0, 1, 2, ..., n-1]
	identity_arrangement.clear()
	for node_data in nodes_data:
		identity_arrangement.append(node_data.get("id", 0))

	# Generate shuffled start arrangement (Fisher-Yates, guaranteed != identity)
	var n_nodes: int = identity_arrangement.size()
	shuffle_seed = _generate_shuffle_seed(level_id)
	var shuffle_perm: Array[int] = generate_shuffle(n_nodes, shuffle_seed)

	# Apply shuffle: current_arrangement[i] = identity[shuffle[i]]
	initial_arrangement.clear()
	current_arrangement.clear()
	for i in range(n_nodes):
		initial_arrangement.append(identity_arrangement[shuffle_perm[i]])
		current_arrangement.append(identity_arrangement[shuffle_perm[i]])


## Clear all arrangement state.
func clear() -> void:
	identity_arrangement.clear()
	initial_arrangement.clear()
	current_arrangement.clear()
	shuffle_seed = 0


## Reset current arrangement to the shuffled start (for RESET button).
func reset_to_initial() -> void:
	current_arrangement = initial_arrangement.duplicate()


## Swap two elements in current_arrangement by their values (crystal IDs).
func swap_in_arrangement(id_a: int, id_b: int) -> void:
	var idx_a = current_arrangement.find(id_a)
	var idx_b = current_arrangement.find(id_b)
	if idx_a >= 0 and idx_b >= 0:
		var temp = current_arrangement[idx_a]
		current_arrangement[idx_a] = current_arrangement[idx_b]
		current_arrangement[idx_b] = temp


## Set current arrangement directly (used by submit_permutation).
func set_arrangement(mapping: Array) -> void:
	current_arrangement = Array(mapping, TYPE_INT, "", null)


## Apply an automorphism permutation to current arrangement (left composition).
## new[i] = current[P[i]]
func apply_permutation(auto_perm: Permutation) -> void:
	var n: int = current_arrangement.size()
	if n == 0:
		return
	var new_arrangement: Array[int] = []
	new_arrangement.resize(n)
	for i in range(n):
		new_arrangement[i] = current_arrangement[auto_perm.apply(i)]
	current_arrangement = new_arrangement


## Build a positions map from node data, fitting into the target area.
## Returns Dictionary: node_id (int) -> Vector2 world position.
## [param target_size] is the area where crystals should be placed
## (e.g. crystal_rect.size for split-screen layout).
static func build_positions_map(nodes_data: Array, target_size: Vector2) -> Dictionary:
	if nodes_data.is_empty():
		return {}

	# 1. Parse raw positions from JSON
	var raw_positions: Dictionary = {}  # node_id -> Vector2
	var min_pos: Vector2 = Vector2(INF, INF)
	var max_pos: Vector2 = Vector2(-INF, -INF)
	for node_data in nodes_data:
		var node_id: int = int(node_data.get("id", 0))
		var pos_arr = node_data.get("position", [0, 0])
		var pos: Vector2
		if pos_arr is Array and pos_arr.size() >= 2:
			pos = Vector2(pos_arr[0], pos_arr[1])
		else:
			pos = Vector2.ZERO
		raw_positions[node_id] = pos
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.y = max(max_pos.y, pos.y)

	# 2. Compute scale to fit into target_size with padding
	var padding: float = 60.0  # margin inside the crystal zone
	var usable: Vector2 = target_size - Vector2(padding * 2, padding * 2)
	if usable.x < 10.0: usable.x = 10.0
	if usable.y < 10.0: usable.y = 10.0

	var range_x: float = max_pos.x - min_pos.x
	var range_y: float = max_pos.y - min_pos.y
	if range_x < 1.0: range_x = 1.0
	if range_y < 1.0: range_y = 1.0

	var scale_factor: float = min(usable.x / range_x, usable.y / range_y)

	# 3. Center offset: place the scaled graph centered within target_size
	var scaled_range: Vector2 = Vector2(range_x * scale_factor, range_y * scale_factor)
	var offset: Vector2 = (target_size - scaled_range) / 2.0

	# 4. Map all positions
	var positions_map: Dictionary = {}
	for node_id in raw_positions:
		var raw: Vector2 = raw_positions[node_id]
		var mapped: Vector2 = Vector2(
			(raw.x - min_pos.x) * scale_factor + offset.x,
			(raw.y - min_pos.y) * scale_factor + offset.y
		)
		positions_map[node_id] = mapped

	return positions_map


## Generate a deterministic seed for the level shuffle.
## Uses level_id hash so the same level always gets the same shuffle.
static func _generate_shuffle_seed(level_id: String) -> int:
	return level_id.hash()


## Generate a Fisher-Yates shuffle permutation that is NOT identity.
## Returns an array where result[i] = which position to take from.
static func generate_shuffle(size: int, seed_val: int) -> Array[int]:
	if size <= 1:
		return [0]

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val

	var perm: Array[int] = []
	for i in range(size):
		perm.append(i)

	# Fisher-Yates shuffle
	for i in range(size - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = perm[i]
		perm[i] = perm[j]
		perm[j] = tmp

	# Guarantee not identity: if shuffle == identity, swap first two elements
	var is_identity: bool = true
	for i in range(size):
		if perm[i] != i:
			is_identity = false
			break
	if is_identity:
		var tmp: int = perm[0]
		perm[0] = perm[1]
		perm[1] = tmp

	return perm
