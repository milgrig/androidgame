class_name KeyRing
extends RefCounted
## Tracks discovered symmetries (permutations) for a level.
## "Key ring" = collection of valid automorphisms found by the player.

var found: Array  # Array[Permutation]
var target_count: int  # Total automorphisms in this level's group

func _init(p_target_count: int = 0) -> void:
	found = []
	target_count = p_target_count

func add_key(p: Permutation) -> bool:
	## Adds permutation to key ring. Returns false if already present.
	if contains(p):
		return false
	found.append(p)
	return true

func contains(p: Permutation) -> bool:
	for key in found:
		if key.equals(p):
			return true
	return false

func is_complete() -> bool:
	return found.size() >= target_count and target_count > 0

func count() -> int:
	return found.size()

func get_key(index: int) -> Permutation:
	return found[index]

func compose_keys(i: int, j: int) -> Permutation:
	## Compose found[i] then found[j], returning the result.
	## Used for the "combine two keys" button in the game.
	return found[i].compose(found[j])

func is_closed_under_composition() -> bool:
	## Checks if the found set forms a group (closed under composition).
	for a in found:
		for b in found:
			var c: Permutation = a.compose(b)
			if not contains(c):
				return false
	return true

func has_identity() -> bool:
	for key in found:
		if key.is_identity():
			return true
	return false

func has_inverses() -> bool:
	## Check that every element in found has its inverse also in found.
	for key in found:
		var inv: Permutation = key.inverse()
		if not contains(inv):
			return false
	return true

func build_cayley_table() -> Array:
	## Returns 2D array: result[i][j] = index of found[i].compose(found[j])
	## Returns empty array if set is not closed.
	var n: int = found.size()
	var table: Array = []
	for i in range(n):
		var row: Array = []
		for j in range(n):
			var product: Permutation = found[i].compose(found[j])
			var idx: int = _index_of(product)
			if idx == -1:
				return []  # Not closed
			row.append(idx)
		table.append(row)
	return table

func _index_of(p: Permutation) -> int:
	for i in range(found.size()):
		if found[i].equals(p):
			return i
	return -1

func clear() -> void:
	found.clear()


## Check whether the subset of keys at the given indices forms a subgroup.
## Returns: {is_subgroup: bool, missing_elements: Array[Permutation], reasons: Array[String]}
func check_subgroup(key_indices: Array) -> Dictionary:
	var subset: Array = []  # Array[Permutation]
	for idx in key_indices:
		if idx >= 0 and idx < found.size():
			subset.append(found[idx])

	var result: Dictionary = {
		"is_subgroup": true,
		"missing_elements": [],
		"reasons": []
	}

	# Check: contains identity?
	var has_id: bool = false
	for p in subset:
		if p.is_identity():
			has_id = true
			break
	if not has_id:
		result["is_subgroup"] = false
		result["reasons"].append("missing_identity")

	# Check: closed under composition?
	for a in subset:
		for b in subset:
			var product: Permutation = a.compose(b)
			var found_in_subset: bool = false
			for s in subset:
				if s.equals(product):
					found_in_subset = true
					break
			if not found_in_subset:
				result["is_subgroup"] = false
				var already_missing: bool = false
				for m in result["missing_elements"]:
					if m.equals(product):
						already_missing = true
						break
				if not already_missing:
					result["missing_elements"].append(product)
				if not result["reasons"].has("not_closed_composition"):
					result["reasons"].append("not_closed_composition")

	# Check: closed under inverse?
	for a in subset:
		var inv: Permutation = a.inverse()
		var found_in_subset: bool = false
		for s in subset:
			if s.equals(inv):
				found_in_subset = true
				break
		if not found_in_subset:
			result["is_subgroup"] = false
			var already_missing: bool = false
			for m in result["missing_elements"]:
				if m.equals(inv):
					already_missing = true
					break
			if not already_missing:
				result["missing_elements"].append(inv)
			if not result["reasons"].has("missing_inverse"):
				result["reasons"].append("missing_inverse")

	return result


## Generate the closure of the subset of keys at the given indices.
## Returns indices into found[] of all elements in the closed subgroup.
## If a needed element is not in found[], it won't be included (only existing keys).
func get_subgroup_closure(key_indices: Array) -> Array:
	# Gather the subset permutations
	var generators: Array = []  # Array[Permutation]
	for idx in key_indices:
		if idx >= 0 and idx < found.size():
			generators.append(found[idx])

	if generators.is_empty():
		return []

	var n: int = generators[0].size()
	var closed: Array = Permutation.generate_subgroup_from(generators, n)

	# Map back to indices in found[]
	var result_indices: Array = []  # Array[int]
	for c in closed:
		var idx: int = _index_of(c)
		if idx != -1 and not result_indices.has(idx):
			result_indices.append(idx)

	result_indices.sort()
	return result_indices


## Find all subgroups among the found keys.
## For small groups (≤24 elements), does full subset enumeration.
## Returns: [{indices: Array[int], order: int, elements: Array[Permutation]}]
func find_all_subgroups() -> Array:
	var n: int = found.size()
	if n == 0:
		return []

	# Full subset enumeration for small groups
	var subgroups: Array = []  # Array[Dictionary]
	var total_subsets: int = 1 << n  # 2^n

	for mask in range(1, total_subsets):  # skip empty set
		var subset: Array = []  # Array[Permutation]
		var indices: Array = []  # Array[int]
		for bit in range(n):
			if mask & (1 << bit):
				subset.append(found[bit])
				indices.append(bit)

		# Check if this subset forms a subgroup
		if _is_subset_subgroup(subset):
			subgroups.append({
				"indices": indices,
				"order": subset.size(),
				"elements": subset
			})

	return subgroups


## Check if a given array of permutations forms a subgroup (has identity, closed, inverses).
func _is_subset_subgroup(subset: Array) -> bool:
	# Must contain identity
	var has_id: bool = false
	for p in subset:
		if p.is_identity():
			has_id = true
			break
	if not has_id:
		return false

	# Must be closed under composition
	for a in subset:
		for b in subset:
			var product: Permutation = a.compose(b)
			var found_product: bool = false
			for s in subset:
				if s.equals(product):
					found_product = true
					break
			if not found_product:
				return false

	# Must be closed under inverse
	for a in subset:
		var inv: Permutation = a.inverse()
		var found_inv: bool = false
		for s in subset:
			if s.equals(inv):
				found_inv = true
				break
		if not found_inv:
			return false

	return true
