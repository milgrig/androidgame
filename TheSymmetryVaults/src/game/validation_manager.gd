## ValidationManager — Handles permutation validation, target matching,
## first-key rebasing, and symmetry discovery logic.
##
## Responsibilities:
## - Parse target automorphisms from level JSON
## - Validate permutations against targets
## - First-key-is-identity rebasing
## - Key display name resolution
## - Combine mode key composition

class_name ValidationManager
extends RefCounted


# --- Target symmetries (from level JSON) ---
var target_perms: Dictionary = {}               # sym_id -> Permutation
var target_perm_names: Dictionary = {}           # sym_id -> display name
var target_perm_descriptions: Dictionary = {}    # sym_id -> description text
var total_symmetries: int = 0

# --- Core engine ---
var key_ring: KeyRing = null
var crystal_graph: CrystalGraph = null

# --- First-key-is-identity rebasing ---
var first_key_relabeled: bool = false
var rebase_inverse: Permutation = null

# --- Identity tracking ---
var identity_found: bool = false


## Initialize from level data.
func setup(level_data: Dictionary) -> void:
	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var edges_data = graph_data.get("edges", [])

	# Create CrystalGraph for engine-based automorphism validation
	var gd_nodes: Array[Dictionary] = []
	for n in nodes_data:
		gd_nodes.append(n)
	var gd_edges: Array[Dictionary] = []
	for e in edges_data:
		gd_edges.append(e)
	crystal_graph = CrystalGraph.new(gd_nodes, gd_edges)

	# Parse target symmetries from JSON
	var symmetries_data = level_data.get("symmetries", {})
	var automorphisms = symmetries_data.get("automorphisms", [])
	total_symmetries = automorphisms.size()
	target_perms.clear()
	target_perm_names.clear()
	target_perm_descriptions.clear()
	for auto in automorphisms:
		var sym_id: String = auto.get("id", "")
		var perm := Permutation.from_array(auto.get("mapping", []))
		target_perms[sym_id] = perm
		target_perm_names[sym_id] = auto.get("name", sym_id)
		target_perm_descriptions[sym_id] = auto.get("description", "")

	# Initialize KeyRing
	key_ring = KeyRing.new(total_symmetries)

	# Reset rebase state
	first_key_relabeled = false
	rebase_inverse = null
	identity_found = false


## Clear all validation state.
func clear() -> void:
	if key_ring:
		key_ring.clear()
	target_perms.clear()
	target_perm_names.clear()
	target_perm_descriptions.clear()
	first_key_relabeled = false
	rebase_inverse = null
	identity_found = false


## Validate a permutation against target automorphisms.
## Returns a Dictionary with the result:
##   {"match": true, "sym_id": "r1", "is_new": true, "perm": Permutation}
##   {"match": true, "sym_id": "r1", "is_new": false}  (already found)
##   {"match": false}
func validate_permutation(perm: Permutation) -> Dictionary:
	# Rebase the permutation relative to the first found key
	var check_perm := perm
	if rebase_inverse != null:
		check_perm = perm.compose(rebase_inverse)

	# Check against each target automorphism
	for sym_id in target_perms:
		var target_perm: Permutation = target_perms[sym_id]
		if check_perm.equals(target_perm):
			# Match found — try adding to KeyRing (stores ORIGINAL perm)
			if key_ring.add_key(perm):
				# New symmetry discovered!

				# First found key becomes "Тождество" — set up rebasing
				if not first_key_relabeled:
					first_key_relabeled = true
					_relabel_first_key_as_identity(sym_id)

				# Track identity found
				if check_perm.is_identity():
					identity_found = true

				return {
					"match": true,
					"is_new": true,
					"sym_id": sym_id,
					"perm": perm,
					"check_perm": check_perm
				}
			else:
				# Already found
				return {
					"match": true,
					"is_new": false,
					"sym_id": sym_id
				}

	# No match
	return {"match": false, "perm": perm}


## Check if level is complete (all keys found).
## Does NOT check inner doors — that's LevelScene's job.
func is_keys_complete() -> bool:
	return key_ring != null and key_ring.is_complete()


## Compose two keys from the KeyRing and validate the result.
## Returns the same format as validate_permutation.
func compose_and_validate(index_a: int, index_b: int) -> Dictionary:
	if key_ring == null:
		return {"match": false}
	var result_perm: Permutation = key_ring.compose_keys(index_a, index_b)
	return validate_permutation(result_perm)


## Get display name for a key by index.
func get_key_display_name(index: int) -> String:
	if key_ring == null or index < 0 or index >= key_ring.count():
		return "?"
	var perm: Permutation = key_ring.get_key(index)
	# Rebase for display
	var display_perm := perm
	if rebase_inverse != null:
		display_perm = perm.compose(rebase_inverse)
	for sym_id in target_perms:
		if target_perms[sym_id].equals(display_perm):
			return target_perm_names.get(sym_id, display_perm.to_cycle_notation())
	return display_perm.to_cycle_notation()


## Rebase the group around the first found key.
func _relabel_first_key_as_identity(first_sym_id: String) -> void:
	var first_perm: Permutation = target_perms.get(first_sym_id)
	if first_perm == null:
		return

	# If first found IS already identity, no rebase needed
	if first_perm.is_identity():
		rebase_inverse = null
		return

	# Store inverse for rebasing all future checks
	rebase_inverse = first_perm.inverse()


## Build summary text listing all discovered keys with names and descriptions.
func build_summary_keys_text() -> String:
	if key_ring == null:
		return ""
	var text := ""
	for i in range(key_ring.count()):
		var perm: Permutation = key_ring.get_key(i)
		var display_name := perm.to_cycle_notation()
		var description := ""
		for sym_id in target_perms:
			if target_perms[sym_id].equals(perm):
				display_name = target_perm_names.get(sym_id, display_name)
				description = target_perm_descriptions.get(sym_id, "")
				break
		if description != "":
			text += "  %s  —  %s\n" % [display_name, description]
		else:
			text += "  %s\n" % display_name
	return text
