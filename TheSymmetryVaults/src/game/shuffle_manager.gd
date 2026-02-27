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
	var n := current_arrangement.size()
	if n == 0:
		return
	var new_arrangement: Array[int] = []
	new_arrangement.resize(n)
	for i in range(n):
		new_arrangement[i] = current_arrangement[auto_perm.apply(i)]
	current_arrangement = new_arrangement


## Build a positions map from node data and viewport.
## Returns Dictionary: node_id (int) -> Vector2 world position.
static func build_positions_map(nodes_data: Array, viewport_size: Vector2) -> Dictionary:
	var center_offset = viewport_size / 2.0
	var positions_map: Dictionary = {}
	for node_data in nodes_data:
		var node_id: int = int(node_data.get("id", 0))
		var pos_arr = node_data.get("position", [0, 0])
		var pos: Vector2
		if pos_arr is Array and pos_arr.size() >= 2:
			pos = Vector2(pos_arr[0], pos_arr[1])
		else:
			pos = Vector2.ZERO
		# Scale positions: if they're normalized (-1 to 1 range), scale up
		if abs(pos.x) <= 2.0 and abs(pos.y) <= 2.0:
			pos = pos * 200.0 + center_offset
		positions_map[node_id] = pos
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

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var perm: Array[int] = []
	for i in range(size):
		perm.append(i)

	# Fisher-Yates shuffle
	for i in range(size - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := perm[i]
		perm[i] = perm[j]
		perm[j] = tmp

	# Guarantee not identity: if shuffle == identity, swap first two elements
	var is_identity := true
	for i in range(size):
		if perm[i] != i:
			is_identity = false
			break
	if is_identity:
		var tmp := perm[0]
		perm[0] = perm[1]
		perm[1] = tmp

	return perm
