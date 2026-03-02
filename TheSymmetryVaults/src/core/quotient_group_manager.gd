class_name QuotientGroupManager
extends RefCounted
## Manages quotient group construction for Layer 5 — factoring by normal subgroups.
## Analogous to ConjugationCrackingManager for Layer 4.
##
## Two-phase interactive construction:
##   Step 1 (COSETS_BUILDING): Player assigns elements to cosets (drag-and-drop)
##   Step 2 (TYPE_IDENTIFICATION): Player identifies the quotient group type
##
## Construction states per subgroup:
##   PENDING -> COSETS_BUILDING -> COSETS_DONE -> TYPE_IDENTIFIED (= fully done)
##
## The quotient group G/N has order |G|/|N|. Its elements are cosets,
## and the operation is well-defined precisely because N is normal.


# --- Construction State Enum ---

enum ConstructionState {
	PENDING,            ## Not started
	COSETS_BUILDING,    ## Step 1: player is assigning elements to cosets
	COSETS_DONE,        ## Step 1 done, awaiting step 2
	TYPE_IDENTIFIED,    ## Step 2 done — fully constructed
}


# --- Signals ---

signal quotient_constructed(subgroup_index: int)
signal all_quotients_done()
signal coset_assignment_validated(subgroup_index: int, is_correct: bool)
signal quotient_type_guessed(subgroup_index: int, is_correct: bool)


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

## Construction state per subgroup (index -> ConstructionState)
var _construction_states: Dictionary = {}  ## sg_index -> ConstructionState

## Constructed quotient groups (index -> result dict)
var _constructed: Dictionary = {}          ## sg_index -> {quotient_order, quotient_type, cosets, table, verified}
var _constructed_count: int = 0

## Cayley table from level JSON (used as fallback when permutation composition
## produces an unfaithful result, e.g. Q8)
var _cayley_table: Dictionary = {}         ## sym_id_a -> {sym_id_b -> sym_id_result}

## Coset assembly state per subgroup (used during COSETS_BUILDING phase)
## sg_index -> { active_coset_idx: int, coset_slots: Array[Array[String]], completed: bool }
var _assembly_state: Dictionary = {}

## Index of the subgroup currently being assembled (-1 = none)
var _current_assembly_sg: int = -1

## All known quotient types for distractor generation
const ALL_QUOTIENT_TYPES: Array = [
	"Z2", "Z3", "Z4", "Z2xZ2", "Z5", "Z6", "S3",
	"Z4_or_Z2xZ2", "Z6_or_S3", "Z8", "Z4xZ2", "Z2xZ2xZ2",
	"D4", "Q8", "order8",
]


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
	_construction_states.clear()
	_constructed.clear()
	_constructed_count = 0
	_cayley_table.clear()
	_assembly_state.clear()
	_current_assembly_sg = -1

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

	# Initialize all construction states to PENDING
	for i in range(_total_count):
		_construction_states[i] = ConstructionState.PENDING


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


# --- Construction State ---

## Get the current construction state for a subgroup.
func get_construction_state(sg_index: int) -> int:
	return _construction_states.get(sg_index, ConstructionState.PENDING)


## Start coset building (step 1) for a subgroup.
## Transitions PENDING -> COSETS_BUILDING.
## Returns true if transition succeeded.
func begin_coset_building(sg_index: int) -> bool:
	if sg_index < 0 or sg_index >= _normal_subgroups.size():
		return false
	var state: int = _construction_states.get(sg_index, ConstructionState.PENDING)
	if state != ConstructionState.PENDING:
		return false
	_construction_states[sg_index] = ConstructionState.COSETS_BUILDING
	return true


# --- Step 1 API: Coset Assignment Validation ---

## Validate whether an element belongs to the given coset (by index).
## coset_index: 0-based index into the cosets array for this normal subgroup.
## Returns true if element_sym_id is in coset[coset_index].
func validate_element_in_coset(sg_index: int, element_sym_id: String, coset_index: int) -> bool:
	var cosets: Array = compute_cosets(sg_index)
	if coset_index < 0 or coset_index >= cosets.size():
		return false
	var coset: Dictionary = cosets[coset_index]
	return coset["elements"].has(element_sym_id)


## Get the size of each coset = |N| (all cosets have the same size).
func get_coset_size(sg_index: int) -> int:
	if sg_index < 0 or sg_index >= _normal_subgroups.size():
		return 0
	var ns_elements: Array = _normal_subgroups[sg_index].get("normal_subgroup_elements", [])
	return ns_elements.size()


## Get the number of cosets = |G/N| = |G| / |N|.
func get_num_cosets(sg_index: int) -> int:
	var cosets: Array = compute_cosets(sg_index)
	return cosets.size()


## Check if all elements are correctly assigned to cosets.
## assignments: Dictionary mapping element_sym_id -> coset_index.
## All group elements must be present and correctly placed.
func is_coset_assignment_complete(sg_index: int, assignments: Dictionary) -> bool:
	var cosets: Array = compute_cosets(sg_index)
	if cosets.is_empty():
		return false

	# Every element in the group must be assigned
	if assignments.size() != _all_sym_ids.size():
		return false

	for sym_id in _all_sym_ids:
		if not assignments.has(sym_id):
			return false
		var assigned_coset: int = assignments[sym_id]
		if assigned_coset < 0 or assigned_coset >= cosets.size():
			return false
		if not cosets[assigned_coset]["elements"].has(sym_id):
			return false

	return true


## Complete step 1: validate full coset assignment and transition state.
## assignments: Dictionary mapping element_sym_id -> coset_index.
## Returns true if assignment is correct and state transitions to COSETS_DONE.
func complete_coset_assignment(sg_index: int, assignments: Dictionary) -> bool:
	if sg_index < 0 or sg_index >= _normal_subgroups.size():
		return false

	var state: int = _construction_states.get(sg_index, ConstructionState.PENDING)
	if state != ConstructionState.COSETS_BUILDING:
		return false

	var correct: bool = is_coset_assignment_complete(sg_index, assignments)
	coset_assignment_validated.emit(sg_index, correct)

	if correct:
		_construction_states[sg_index] = ConstructionState.COSETS_DONE
	return correct


# --- Step 2 API: Type Identification ---

## Check if the proposed quotient type matches the correct answer.
func check_quotient_type(sg_index: int, proposed_type: String) -> bool:
	var correct_type: String = get_quotient_type(sg_index)
	if correct_type == "":
		return false
	return proposed_type == correct_type


## Get the correct quotient type for a given normal subgroup (internal use).
func get_quotient_type(sg_index: int) -> String:
	if sg_index < 0 or sg_index >= _normal_subgroups.size():
		return ""
	return _normal_subgroups[sg_index].get("quotient_type", "")


## Generate answer options: the correct type + 2-3 plausible distractors.
## Returns an Array of Strings, shuffled so the correct answer is not always first.
func generate_type_options(sg_index: int) -> Array:
	var correct: String = get_quotient_type(sg_index)
	if correct == "":
		return []

	var quotient_order: int = _normal_subgroups[sg_index].get("quotient_order", 0)

	# Collect plausible distractors based on the quotient order
	var distractors: Array = []
	var distractors_by_order: Dictionary = {
		2: ["Z2", "Z3", "Z4"],
		3: ["Z3", "Z2", "S3"],
		4: ["Z4", "Z2xZ2", "Z4_or_Z2xZ2", "Z2", "D4"],
		6: ["Z6", "S3", "Z6_or_S3", "Z3", "D3"],
		8: ["Z8", "Z4xZ2", "Z2xZ2xZ2", "D4", "Q8", "order8"],
	}

	var candidates: Array = distractors_by_order.get(quotient_order, [])

	# Add some wrong-order distractors for variety
	for t in ALL_QUOTIENT_TYPES:
		if t != correct and not candidates.has(t):
			candidates.append(t)

	# Pick 2-3 distractors (not equal to correct)
	var target_count: int = 3 if candidates.size() >= 3 else candidates.size()
	for c in candidates:
		if c != correct and distractors.size() < target_count:
			distractors.append(c)

	# Build options: correct + distractors
	var options: Array = [correct]
	options.append_array(distractors)

	# Shuffle using a simple Fisher-Yates
	for i in range(options.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var tmp: String = options[i]
		options[i] = options[j]
		options[j] = tmp

	return options


## Complete step 2: check the proposed type and finalize construction.
## Returns the full construction result dict (or error).
func complete_type_identification(sg_index: int, proposed_type: String) -> Dictionary:
	if sg_index < 0 or sg_index >= _normal_subgroups.size():
		return {"error": "invalid_index"}

	var state: int = _construction_states.get(sg_index, ConstructionState.PENDING)
	if state != ConstructionState.COSETS_DONE:
		return {"error": "wrong_state"}

	var correct: bool = check_quotient_type(sg_index, proposed_type)
	quotient_type_guessed.emit(sg_index, correct)

	if not correct:
		return {"error": "wrong_type"}

	# Finalize: build the full construction result
	_construction_states[sg_index] = ConstructionState.TYPE_IDENTIFIED

	var cosets: Array = compute_cosets(sg_index)
	var table: Dictionary = get_quotient_table(sg_index)
	var ns_data: Dictionary = _normal_subgroups[sg_index]

	var result: Dictionary = {
		"quotient_order": cosets.size(),
		"quotient_type": ns_data.get("quotient_type", ""),
		"cosets": cosets,
		"table": table,
		"verified": true,
	}

	_constructed[sg_index] = result
	_constructed_count += 1
	quotient_constructed.emit(sg_index)

	if _constructed_count >= _total_count:
		all_quotients_done.emit()

	return result


# --- Assembly API (interactive coset building) ---

## Start coset assembly for a given normal subgroup.
## Pre-fills the first coset slot with eN = N (the subgroup itself).
## Returns: { num_cosets: int, coset_size: int, prefilled_elements: Array[String] }
## or { error: String } on failure.
func begin_assembly(sg_idx: int) -> Dictionary:
	if sg_idx < 0 or sg_idx >= _normal_subgroups.size():
		return {"error": "invalid_index"}

	# Allow re-entering assembly if already in building state for this subgroup
	var state: int = _construction_states.get(sg_idx, ConstructionState.PENDING)
	if state == ConstructionState.PENDING:
		begin_coset_building(sg_idx)
	elif state != ConstructionState.COSETS_BUILDING:
		return {"error": "wrong_state"}

	_current_assembly_sg = sg_idx

	var cosets: Array = compute_cosets(sg_idx)
	var coset_size: int = get_coset_size(sg_idx)
	var num_cosets: int = cosets.size()

	# Initialize assembly state with empty slots
	var slots: Array = []
	for i in range(num_cosets):
		slots.append([])  # Each slot is Array[String]

	# Pre-fill slot 0 with eN = the normal subgroup elements
	var ns_elements: Array = get_normal_subgroup_elements(sg_idx)
	slots[0] = ns_elements.duplicate()

	_assembly_state[sg_idx] = {
		"active_coset_idx": 1 if num_cosets > 1 else 0,
		"coset_slots": slots,
		"completed": num_cosets <= 1,
	}

	return {
		"num_cosets": num_cosets,
		"coset_size": coset_size,
		"prefilled_elements": ns_elements.duplicate(),
	}


## Try to add an element to the active coset slot during assembly.
## Returns: { accepted: bool, reason: String, slot_idx: int, slot_full: bool, all_done: bool }
func try_add_to_assembly(sg_idx: int, sym_id: String) -> Dictionary:
	var fail := {"accepted": false, "slot_idx": -1, "slot_full": false, "all_done": false}
	if not _assembly_state.has(sg_idx):
		fail["reason"] = "no_assembly_active"
		return fail

	var astate: Dictionary = _assembly_state[sg_idx]
	var active_idx: int = astate["active_coset_idx"]
	var slots: Array = astate["coset_slots"]

	if active_idx >= slots.size():
		fail["reason"] = "all_slots_filled"
		fail["all_done"] = true
		return fail

	# Check duplicate (already in any slot)
	if is_element_already_assigned(sg_idx, sym_id):
		fail["reason"] = "already_assigned"
		fail["slot_idx"] = active_idx
		return fail

	var active_slot: Array = slots[active_idx]
	var coset_size: int = get_coset_size(sg_idx)

	# Validate coset membership
	if active_slot.is_empty():
		# First element in slot -- always accepted (becomes representative)
		active_slot.append(sym_id)
	else:
		# Subsequent elements -- must be in same coset as the first element
		var representative: String = active_slot[0]
		var rep_coset: String = find_coset_representative(sg_idx, representative)
		var cand_coset: String = find_coset_representative(sg_idx, sym_id)
		if rep_coset == "" or cand_coset == "" or rep_coset != cand_coset:
			fail["reason"] = "wrong_coset"
			fail["slot_idx"] = active_idx
			return fail
		active_slot.append(sym_id)

	# Check if slot is full
	var slot_full: bool = active_slot.size() >= coset_size
	if slot_full:
		astate["active_coset_idx"] = active_idx + 1

	# Check if all cosets are done
	var all_done: bool = astate["active_coset_idx"] >= slots.size()
	if all_done:
		astate["completed"] = true

	return {
		"accepted": true,
		"reason": "ok",
		"slot_idx": active_idx,
		"slot_full": slot_full,
		"all_done": all_done,
	}


## Check if an element is already placed in any coset slot during assembly.
func is_element_already_assigned(sg_idx: int, sym_id: String) -> bool:
	if not _assembly_state.has(sg_idx):
		return false
	var astate: Dictionary = _assembly_state[sg_idx]
	for slot in astate["coset_slots"]:
		if slot.has(sym_id):
			return true
	return false


## Get the current assembly state for a subgroup.
func get_assembly_state(sg_idx: int) -> Dictionary:
	if not _assembly_state.has(sg_idx):
		return {}
	return _assembly_state[sg_idx].duplicate(true)


## Get the active coset slot index for the current assembly.
func get_active_coset_slot() -> int:
	if _current_assembly_sg < 0 or not _assembly_state.has(_current_assembly_sg):
		return -1
	return _assembly_state[_current_assembly_sg].get("active_coset_idx", -1)


## Get the current assembly subgroup index.
func get_current_assembly_sg() -> int:
	return _current_assembly_sg


## Finalize the assembly and build assignments dict for complete_coset_assignment.
func finalize_assembly(sg_idx: int) -> bool:
	if not _assembly_state.has(sg_idx):
		return false
	var astate: Dictionary = _assembly_state[sg_idx]
	if not astate.get("completed", false):
		return false

	var slots: Array = astate["coset_slots"]
	var assignments: Dictionary = {}
	for ci in range(slots.size()):
		for sid in slots[ci]:
			assignments[sid] = ci

	var result: bool = complete_coset_assignment(sg_idx, assignments)
	if result:
		_current_assembly_sg = -1
	return result


# --- Legacy one-shot construction (kept for auto-complete / testing) ---

## One-shot construction: bypasses two-phase flow.
## Used for auto-complete (levels with 0 quotient groups) and backward compat.
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
	_construction_states[subgroup_index] = ConstructionState.TYPE_IDENTIFIED
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


## Check if a particular quotient has been constructed (fully done).
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

	var states_data: Dictionary = {}
	for idx in _construction_states:
		states_data[str(idx)] = _construction_states[idx]

	# Serialize assembly state (coset slots per subgroup)
	var assembly_data: Dictionary = {}
	for sg_idx in _assembly_state:
		assembly_data[str(sg_idx)] = _assembly_state[sg_idx].duplicate(true)

	return {
		"status": "completed" if is_complete() else "in_progress",
		"constructed": constructed_data,
		"constructed_count": _constructed_count,
		"total_count": _total_count,
		"construction_states": states_data,
		"assembly_state": assembly_data,
		"current_assembly_sg": _current_assembly_sg,
	}


## Restore state from saved dictionary.
func restore_from_save(save_data: Dictionary) -> void:
	_constructed.clear()
	var constructed_data: Dictionary = save_data.get("constructed", {})
	for idx_str in constructed_data:
		_constructed[int(idx_str)] = constructed_data[idx_str]

	_constructed_count = save_data.get("constructed_count", _constructed.size())

	# Restore construction states
	_construction_states.clear()
	var states_data: Dictionary = save_data.get("construction_states", {})
	for idx_str in states_data:
		_construction_states[int(idx_str)] = states_data[idx_str]

	# Ensure all subgroups have a state entry
	for i in range(_total_count):
		if not _construction_states.has(i):
			if _constructed.has(i):
				_construction_states[i] = ConstructionState.TYPE_IDENTIFIED
			else:
				_construction_states[i] = ConstructionState.PENDING

	# Restore assembly state
	_assembly_state.clear()
	var assembly_data: Dictionary = save_data.get("assembly_state", {})
	for idx_str in assembly_data:
		_assembly_state[int(idx_str)] = assembly_data[idx_str]
	_current_assembly_sg = save_data.get("current_assembly_sg", -1)


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
