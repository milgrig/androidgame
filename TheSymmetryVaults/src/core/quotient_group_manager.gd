class_name QuotientGroupManager
extends RefCounted
## Manages quotient group construction for Layer 5 — factoring by normal subgroups.
## Analogous to ConjugationCrackingManager for Layer 4.
##
## Given a group G and a normal subgroup N (confirmed in Layer 4), the player
## constructs the quotient group G/N by:
##   1. Selecting a normal subgroup N from those found in Layer 4
##   2. Computing cosets gN for each representative g
##   3. Building the quotient multiplication table (gN * g'N = (gg')N)
##   4. Verifying the quotient satisfies group axioms
##
## The quotient group G/N has order |G|/|N|. Its elements are cosets,
## and the operation is well-defined precisely because N is normal.
##
## Pedagogical goal: "Normal subgroups let us build new, simpler groups
## by collapsing equivalent elements."


# --- Signals ---

signal quotient_constructed(subgroup_index: int)
signal all_quotients_done()


# --- State ---

var _sym_id_to_perm: Dictionary = {}       ## sym_id -> Permutation
var _sym_id_to_name: Dictionary = {}       ## sym_id -> display name
var _all_sym_ids: Array[String] = []       ## ordered list of all sym_ids in G

## Normal subgroups eligible for quotient construction (from layer_5 JSON)
var _normal_subgroups: Array = []          ## Array[Dictionary] — each has normal_subgroup_elements, cosets, etc.
var _total_count: int = 0                  ## number of quotient groups to construct

## Cosets computed for each normal subgroup (index -> Array[Dictionary])
var _cosets: Dictionary = {}               ## sg_index -> [{representative: String, elements: [String]}]

## Quotient multiplication tables (index -> Dictionary)
var _quotient_tables: Dictionary = {}      ## sg_index -> {rep_a: {rep_b: rep_result}}

## Constructed quotient groups (index -> result dict)
var _constructed: Dictionary = {}          ## sg_index -> {quotient_order, quotient_type, cosets, table, verified}
var _constructed_count: int = 0

## Cayley table from level JSON (used as fallback when permutation composition
## produces an unfaithful result, e.g. Q8)
var _cayley_table: Dictionary = {}         ## sym_id_a -> {sym_id_b -> sym_id_result}


# --- Setup ---

## Initialize from level data and layer config.
## level_data: full level JSON dictionary
## layer_config: the "layer_5" section from "layers", or empty dict
func setup(level_data: Dictionary, layer_config: Dictionary = {}) -> void:
	_sym_id_to_perm.clear()
	_sym_id_to_name.clear()
	_all_sym_ids.clear()
	_normal_subgroups.clear()
	_cosets.clear()
	_quotient_tables.clear()
	_constructed.clear()
	_constructed_count = 0
	_cayley_table.clear()

	# Parse automorphisms from level data
	var autos: Array = level_data.get("symmetries", {}).get("automorphisms", [])
	for auto in autos:
		var sym_id: String = auto.get("id", "")
		var perm: Permutation = Permutation.from_array(auto.get("mapping", []))
		_sym_id_to_perm[sym_id] = perm
		_sym_id_to_name[sym_id] = auto.get("name", sym_id)
		_all_sym_ids.append(sym_id)

	# Load Cayley table (used as fallback for unfaithful representations like Q8)
	_cayley_table = level_data.get("symmetries", {}).get("cayley_table", {})

	# Load quotient group definitions from layer_5
	var quotient_groups: Array = layer_config.get("quotient_groups", [])

	for qg in quotient_groups:
		var ns_elements: Array = qg.get("normal_subgroup_elements", [])
		if ns_elements.is_empty():
			continue
		_normal_subgroups.append(qg)

	_total_count = _normal_subgroups.size()


# --- Normal Subgroup Access ---

## Get all normal subgroups available for quotient construction.
func get_normal_subgroups() -> Array:
	return _normal_subgroups.duplicate()


## Get the number of normal subgroups.
func get_normal_subgroup_count() -> int:
	return _normal_subgroups.size()


## Get the elements of a normal subgroup by index.
func get_normal_subgroup_elements(index: int) -> Array:
	if index < 0 or index >= _normal_subgroups.size():
		return []
	return _normal_subgroups[index].get("normal_subgroup_elements", []).duplicate()


# --- Coset Computation ---

## Compute left cosets of G by the normal subgroup at the given index.
## Returns Array of {representative: String, elements: Array[String]}.
## Cosets are computed from the permutation data (not just read from JSON).
func compute_cosets(subgroup_index: int) -> Array:
	if subgroup_index < 0 or subgroup_index >= _normal_subgroups.size():
		return []

	# If already computed, return cached
	if _cosets.has(subgroup_index):
		return _cosets[subgroup_index].duplicate(true)

	var ns_data: Dictionary = _normal_subgroups[subgroup_index]
	var ns_elements: Array = ns_data.get("normal_subgroup_elements", [])

	# Compute left cosets: for each g in G, compute gN using _compose_sym_ids
	var cosets: Array = []
	var assigned: Array = []  ## sym_ids already placed in a coset

	for g_sid in _all_sym_ids:
		if assigned.has(g_sid):
			continue

		var coset_elements: Array = []

		for h_sid in ns_elements:
			var product_sid: String = _compose_sym_ids(g_sid, h_sid)
			if product_sid != "" and not coset_elements.has(product_sid):
				coset_elements.append(product_sid)
				assigned.append(product_sid)

		cosets.append({
			"representative": g_sid,
			"elements": coset_elements,
		})

	_cosets[subgroup_index] = cosets
	return cosets.duplicate(true)


# --- Quotient Table ---

## Build the quotient group multiplication table for the given normal subgroup.
## Table maps: representative_a -> representative_b -> representative_result
## where gN * g'N = (g*g')N, and result is the representative of that coset.
## Returns: {rep_a: {rep_b: rep_result}}
func get_quotient_table(subgroup_index: int) -> Dictionary:
	if subgroup_index < 0 or subgroup_index >= _normal_subgroups.size():
		return {}

	# If already computed, return cached
	if _quotient_tables.has(subgroup_index):
		return _quotient_tables[subgroup_index].duplicate(true)

	# Ensure cosets are computed
	var cosets: Array = compute_cosets(subgroup_index)
	if cosets.is_empty():
		return {}

	# Build representative -> coset-index map
	var rep_list: Array = []
	var element_to_rep: Dictionary = {}  ## any element -> its coset representative
	for coset in cosets:
		var rep: String = coset["representative"]
		rep_list.append(rep)
		for elem in coset["elements"]:
			element_to_rep[elem] = rep

	# Build multiplication table using _compose_sym_ids
	var table: Dictionary = {}
	for rep_a in rep_list:
		table[rep_a] = {}
		for rep_b in rep_list:
			var product_sid: String = _compose_sym_ids(rep_a, rep_b)
			var result_rep: String = element_to_rep.get(product_sid, "")
			table[rep_a][rep_b] = result_rep

	_quotient_tables[subgroup_index] = table
	return table.duplicate(true)


# --- Verification ---

## Verify that the quotient group G/N satisfies group axioms:
##   1. Closure: every product of cosets is a coset
##   2. Associativity: (aB * bB) * cB = aB * (bB * cB) — automatic for permutations
##   3. Identity: eN acts as identity coset
##   4. Inverses: every coset has an inverse coset
## Returns: {valid: bool, checks: {closure: bool, identity: bool, inverses: bool}}
func verify_quotient(subgroup_index: int) -> Dictionary:
	if subgroup_index < 0 or subgroup_index >= _normal_subgroups.size():
		return {"valid": false, "checks": {}}

	var cosets: Array = compute_cosets(subgroup_index)
	var table: Dictionary = get_quotient_table(subgroup_index)
	if cosets.is_empty() or table.is_empty():
		return {"valid": false, "checks": {}}

	var rep_list: Array = []
	for coset in cosets:
		rep_list.append(coset["representative"])

	# 1. Closure: every product maps to a valid representative
	var closure_ok: bool = true
	for rep_a in rep_list:
		for rep_b in rep_list:
			var result: String = table.get(rep_a, {}).get(rep_b, "")
			if result == "" or not rep_list.has(result):
				closure_ok = false

	# 2. Identity: find the identity coset (contains group identity)
	var identity_rep: String = ""
	for coset in cosets:
		for elem in coset["elements"]:
			var p: Permutation = _sym_id_to_perm.get(elem, null)
			if p != null and p.is_identity():
				identity_rep = coset["representative"]
				break
		if identity_rep != "":
			break

	var identity_ok: bool = identity_rep != ""
	if identity_ok:
		for rep in rep_list:
			# eN * gN = gN and gN * eN = gN
			var left: String = table.get(identity_rep, {}).get(rep, "")
			var right: String = table.get(rep, {}).get(identity_rep, "")
			if left != rep or right != rep:
				identity_ok = false
				break

	# 3. Inverses: for each coset, there exists an inverse coset
	var inverses_ok: bool = identity_rep != ""
	if inverses_ok:
		for rep in rep_list:
			var found_inverse: bool = false
			for candidate in rep_list:
				var product: String = table.get(rep, {}).get(candidate, "")
				if product == identity_rep:
					found_inverse = true
					break
			if not found_inverse:
				inverses_ok = false
				break

	var all_valid: bool = closure_ok and identity_ok and inverses_ok
	return {
		"valid": all_valid,
		"checks": {
			"closure": closure_ok,
			"identity": identity_ok,
			"inverses": inverses_ok,
		},
	}


# --- Construction (gameplay) ---

## Mark a quotient group as constructed by the player.
## Stores the full result and emits signal.
func construct_quotient(subgroup_index: int) -> Dictionary:
	if subgroup_index < 0 or subgroup_index >= _normal_subgroups.size():
		return {"error": "invalid_index"}

	if _constructed.has(subgroup_index):
		return {"error": "already_constructed"}

	var cosets: Array = compute_cosets(subgroup_index)
	var table: Dictionary = get_quotient_table(subgroup_index)
	var verification: Dictionary = verify_quotient(subgroup_index)

	if not verification.get("valid", false):
		return {"error": "verification_failed"}

	var ns_data: Dictionary = _normal_subgroups[subgroup_index]

	var result: Dictionary = {
		"quotient_order": cosets.size(),
		"quotient_type": ns_data.get("quotient_type", ""),
		"cosets": cosets,
		"table": table,
		"verified": true,
	}

	_constructed[subgroup_index] = result
	_constructed_count += 1
	quotient_constructed.emit(subgroup_index)

	if _constructed_count >= _total_count:
		all_quotients_done.emit()

	return result


# --- Progress ---

## Get progress: {constructed: int, total: int}
func get_progress() -> Dictionary:
	return {
		"constructed": _constructed_count,
		"total": _total_count,
	}


## Check if all quotient groups have been constructed.
func is_complete() -> bool:
	return _constructed_count >= _total_count and _total_count >= 0


## Check if a particular quotient has been constructed.
func is_constructed(index: int) -> bool:
	return _constructed.has(index)


## Get the construction result for a given index.
func get_construction(index: int) -> Dictionary:
	return _constructed.get(index, {})


# --- Persistence ---

## Save state to dictionary (for GameManager layer progress).
func save_state() -> Dictionary:
	var constructed_data: Dictionary = {}
	for idx in _constructed:
		constructed_data[str(idx)] = _constructed[idx].duplicate(true)

	return {
		"status": "completed" if is_complete() else "in_progress",
		"constructed": constructed_data,
		"constructed_count": _constructed_count,
		"total_count": _total_count,
	}


## Restore state from saved dictionary.
func restore_from_save(save_data: Dictionary) -> void:
	_constructed.clear()
	var constructed_data: Dictionary = save_data.get("constructed", {})
	for idx_str in constructed_data:
		_constructed[int(idx_str)] = constructed_data[idx_str]

	_constructed_count = save_data.get("constructed_count", _constructed.size())


# --- Query helpers ---

## Get the permutation for a sym_id.
func get_perm(sym_id: String) -> Permutation:
	return _sym_id_to_perm.get(sym_id, null)


## Get the display name for a sym_id.
func get_name(sym_id: String) -> String:
	return _sym_id_to_name.get(sym_id, sym_id)


## Get all sym_ids in the group.
func get_all_sym_ids() -> Array[String]:
	return _all_sym_ids.duplicate()


## Look up which coset a given element belongs to (for a given normal subgroup).
## Returns the representative sym_id, or "" if not found.
func find_coset_representative(subgroup_index: int, element_sym_id: String) -> String:
	var cosets: Array = compute_cosets(subgroup_index)
	for coset in cosets:
		if coset["elements"].has(element_sym_id):
			return coset["representative"]
	return ""


# --- Internal helpers ---

## Find the sym_id for a permutation.
func _find_sym_id_for_perm(perm: Permutation) -> String:
	for sym_id in _sym_id_to_perm:
		if _sym_id_to_perm[sym_id].equals(perm):
			return sym_id
	return ""


## Compose two elements by sym_id, returning the result sym_id.
## Uses permutation composition first; falls back to Cayley table
## for groups with unfaithful permutation representations (e.g. Q8).
func _compose_sym_ids(a_sid: String, b_sid: String) -> String:
	var a_perm: Permutation = _sym_id_to_perm.get(a_sid, null)
	var b_perm: Permutation = _sym_id_to_perm.get(b_sid, null)
	if a_perm != null and b_perm != null:
		var product: Permutation = a_perm.compose(b_perm)
		var result: String = _find_sym_id_for_perm(product)
		if result != "":
			return result
	# Fallback: Cayley table
	return _cayley_table.get(a_sid, {}).get(b_sid, "")
