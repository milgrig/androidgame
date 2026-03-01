class_name ConjugationCrackingManager
extends RefCounted
## Manages conjugation cracking for Layer 4 — normal subgroup identification.
## Analogous to KeyringAssemblyManager for Layer 3.
##
## The player selects a subgroup H (found in Layer 3) and tests whether it is
## "normal" by computing conjugations: g·h·g⁻¹ for chosen g ∈ G and h ∈ H.
##
## If every conjugate g·h·g⁻¹ stays inside H for ALL g in G, the subgroup is
## normal (unbreakable). If any conjugate escapes, the subgroup is cracked
## (non-normal) and the player has found a "witness" pair (g, h).
##
## Gameplay flow:
##   1. Player picks a subgroup from the keyring (found in Layer 3)
##   2. Player selects g ∈ G (the "conjugator") and h ∈ H (the "target")
##   3. System computes g·h·g⁻¹ and shows the result
##   4. If g·h·g⁻¹ ∉ H → subgroup is cracked! (non-normal proven)
##   5. If player tests enough conjugations to confirm normality → unbreakable!
##   6. Repeat for all non-trivial subgroups
##
## Pedagogical goal: "Not all subgroups are created equal —
## some are preserved by conjugation."


# --- Signals ---

signal subgroup_cracked(subgroup_index: int, witness_g: String, witness_h: String, result: String)
signal subgroup_confirmed_normal(subgroup_index: int)
signal all_subgroups_classified()


# --- State ---

var _sym_id_to_perm: Dictionary = {}       ## sym_id -> Permutation
var _sym_id_to_name: Dictionary = {}       ## sym_id -> display name
var _all_sym_ids: Array[String] = []       ## ordered list of all sym_ids

## Subgroups to classify (from layer_3 data, excluding trivials)
var _target_subgroups: Array = []          ## Array[Dictionary]
var _total_count: int = 0                  ## total non-trivial subgroups to classify

## Classification results
var _classified: Dictionary = {}           ## subgroup_index -> {is_normal: bool, witness_g: String, witness_h: String, tested_pairs: Array}
var _classified_count: int = 0

## Current subgroup being tested
var _active_subgroup_index: int = -1       ## which subgroup is selected (-1 = none)

## Conjugation test history for active subgroup
var _test_history: Array = []              ## Array[Dictionary] — {g: String, h: String, result: String, stayed_in: bool}


# --- Setup ---

## Initialize from level data and layer config.
## level_data: full level JSON dictionary
## layer_config: the "layer_4" section from "layers", or empty dict
func setup(level_data: Dictionary, layer_config: Dictionary = {}) -> void:
	_sym_id_to_perm.clear()
	_sym_id_to_name.clear()
	_all_sym_ids.clear()
	_target_subgroups.clear()
	_classified.clear()
	_classified_count = 0
	_active_subgroup_index = -1
	_test_history.clear()

	# Parse automorphisms from level data
	var autos: Array = level_data.get("symmetries", {}).get("automorphisms", [])
	for auto in autos:
		var sym_id: String = auto.get("id", "")
		var perm: Permutation = Permutation.from_array(auto.get("mapping", []))
		_sym_id_to_perm[sym_id] = perm
		_sym_id_to_name[sym_id] = auto.get("name", sym_id)
		_all_sym_ids.append(sym_id)

	# Get subgroups from layer config (layer_4 carries its own list)
	# or fall back to layer_3 subgroups
	var subgroups: Array = layer_config.get("subgroups", [])
	if subgroups.is_empty():
		subgroups = level_data.get("layers", {}).get("layer_3", {}).get("subgroups", [])

	# Filter: only non-trivial subgroups need classification
	# Trivial = order 1 (identity only) or order = group_order (whole group)
	# Both are always normal — no cracking needed
	var group_order: int = _all_sym_ids.size()
	for sg in subgroups:
		var order: int = sg.get("order", 0)
		var is_trivial: bool = sg.get("is_trivial", false)
		if is_trivial or order <= 1 or order >= group_order:
			continue
		_target_subgroups.append(sg)

	_total_count = _target_subgroups.size()

	# Override count if explicitly specified
	if layer_config.has("classify_count"):
		_total_count = layer_config.get("classify_count")


# --- Subgroup Selection ---

## Select a subgroup to test by its index in _target_subgroups.
func select_subgroup(index: int) -> bool:
	if index < 0 or index >= _target_subgroups.size():
		return false
	if _classified.has(index):
		return false  # already classified
	_active_subgroup_index = index
	_test_history.clear()
	return true


## Get the currently active subgroup index.
func get_active_subgroup_index() -> int:
	return _active_subgroup_index


## Deselect the active subgroup.
func deselect_subgroup() -> void:
	_active_subgroup_index = -1
	_test_history.clear()


# --- Conjugation Testing ---

## Perform a conjugation test: compute g·h·g⁻¹.
## g_sym_id: the "conjugator" from G
## h_sym_id: the "target" from the active subgroup H
## Returns: {result_sym_id: String, result_name: String, stayed_in: bool, is_witness: bool}
func test_conjugation(g_sym_id: String, h_sym_id: String) -> Dictionary:
	if _active_subgroup_index < 0 or _active_subgroup_index >= _target_subgroups.size():
		return {"error": "no_active_subgroup"}

	var g_perm: Permutation = _sym_id_to_perm.get(g_sym_id, null)
	var h_perm: Permutation = _sym_id_to_perm.get(h_sym_id, null)
	if g_perm == null or h_perm == null:
		return {"error": "invalid_sym_id"}

	# T116: validate h is actually in the active subgroup H (defense-in-depth)
	var sg_elements: Array = _target_subgroups[_active_subgroup_index].get("elements", [])
	if not sg_elements.has(h_sym_id):
		return {"error": "h_not_in_subgroup"}

	# Compute conjugate: g · h · g⁻¹
	var g_inv: Permutation = g_perm.inverse()
	var conjugate: Permutation = g_perm.compose(h_perm).compose(g_inv)

	# Find which sym_id corresponds to the conjugate
	var result_sym_id: String = _find_sym_id_for_perm(conjugate)
	var result_name: String = _sym_id_to_name.get(result_sym_id, "???")

	# Check if conjugate is in the subgroup H
	var sg: Dictionary = _target_subgroups[_active_subgroup_index]
	var elements: Array = sg.get("elements", [])
	var stayed_in: bool = elements.has(result_sym_id)

	# Record test
	var test_record: Dictionary = {
		"g": g_sym_id,
		"h": h_sym_id,
		"result": result_sym_id,
		"stayed_in": stayed_in,
	}
	_test_history.append(test_record)

	var is_witness: bool = not stayed_in

	# If the conjugate escaped — subgroup is cracked!
	if is_witness and not _classified.has(_active_subgroup_index):
		_classified[_active_subgroup_index] = {
			"is_normal": false,
			"witness_g": g_sym_id,
			"witness_h": h_sym_id,
			"witness_result": result_sym_id,
			"tested_pairs": _test_history.duplicate(),
		}
		_classified_count += 1
		subgroup_cracked.emit(_active_subgroup_index, g_sym_id, h_sym_id, result_sym_id)

		if _classified_count >= _total_count:
			all_subgroups_classified.emit()

	return {
		"result_sym_id": result_sym_id,
		"result_name": result_name,
		"stayed_in": stayed_in,
		"is_witness": is_witness,
	}


## Confirm the active subgroup is normal (player decides it's unbreakable).
## The system verifies this is actually correct using SubgroupChecker.
## Returns: {confirmed: bool, is_actually_normal: bool}
func confirm_normal() -> Dictionary:
	if _active_subgroup_index < 0 or _active_subgroup_index >= _target_subgroups.size():
		return {"confirmed": false, "is_actually_normal": false}

	if _classified.has(_active_subgroup_index):
		return {"confirmed": false, "is_actually_normal": false}  # already classified

	var sg: Dictionary = _target_subgroups[_active_subgroup_index]
	var elements: Array = sg.get("elements", [])

	# Build permutation arrays for verification
	var sub_perms: Array = []
	for sid in elements:
		var p: Permutation = _sym_id_to_perm.get(sid, null)
		if p != null:
			sub_perms.append(p)

	var group_perms: Array = []
	for sid in _all_sym_ids:
		group_perms.append(_sym_id_to_perm[sid])

	# Verify using SubgroupChecker
	var is_actually_normal: bool = SubgroupChecker.is_normal(sub_perms, group_perms)

	# Also check the JSON flag
	var json_normal: bool = sg.get("is_normal", false)

	# Use the computed value (more reliable)
	var correct: bool = is_actually_normal

	if correct:
		_classified[_active_subgroup_index] = {
			"is_normal": true,
			"witness_g": "",
			"witness_h": "",
			"witness_result": "",
			"tested_pairs": _test_history.duplicate(),
		}
		_classified_count += 1
		subgroup_confirmed_normal.emit(_active_subgroup_index)

		if _classified_count >= _total_count:
			all_subgroups_classified.emit()

	return {
		"confirmed": correct,
		"is_actually_normal": is_actually_normal,
	}


# --- Auto-check normality ---

## Check if the active subgroup is actually normal (for UI hint purposes).
## Does NOT classify it — just returns the mathematical truth.
func is_subgroup_normal(index: int) -> bool:
	if index < 0 or index >= _target_subgroups.size():
		return false
	var sg: Dictionary = _target_subgroups[index]
	# Use precomputed flag from JSON data
	return sg.get("is_normal", false)


## Get a witness pair (g, h) where g·h·g⁻¹ ∉ H for a non-normal subgroup.
## Returns null if the subgroup is actually normal.
func find_witness(index: int) -> Dictionary:
	if index < 0 or index >= _target_subgroups.size():
		return {}

	var sg: Dictionary = _target_subgroups[index]
	var elements: Array = sg.get("elements", [])

	var group_perms: Array = []
	for sid in _all_sym_ids:
		group_perms.append(_sym_id_to_perm[sid])

	for g_sid in _all_sym_ids:
		var g_perm: Permutation = _sym_id_to_perm[g_sid]
		var g_inv: Permutation = g_perm.inverse()
		for h_sid in elements:
			var h_perm: Permutation = _sym_id_to_perm.get(h_sid, null)
			if h_perm == null:
				continue
			var conjugate: Permutation = g_perm.compose(h_perm).compose(g_inv)
			var result_sid: String = _find_sym_id_for_perm(conjugate)
			if not elements.has(result_sid):
				return {
					"g": g_sid,
					"h": h_sid,
					"result": result_sid,
				}

	return {}  # subgroup is normal — no witness exists


# --- Progress ---

## Get progress: {classified: int, total: int, normal_count: int, cracked_count: int}
func get_progress() -> Dictionary:
	var normal_count: int = 0
	var cracked_count: int = 0
	for idx in _classified:
		if _classified[idx]["is_normal"]:
			normal_count += 1
		else:
			cracked_count += 1
	return {
		"classified": _classified_count,
		"total": _total_count,
		"normal_count": normal_count,
		"cracked_count": cracked_count,
	}


## Check if all subgroups have been classified.
func is_complete() -> bool:
	return _classified_count >= _total_count


## Get all target subgroups (non-trivial ones to classify).
func get_target_subgroups() -> Array:
	return _target_subgroups.duplicate()


## Get classification result for a subgroup index.
## Returns empty Dictionary if not yet classified.
func get_classification(index: int) -> Dictionary:
	return _classified.get(index, {})


## Check if a subgroup index is already classified.
func is_classified(index: int) -> bool:
	return _classified.has(index)


## Get the test history for the current active subgroup.
func get_test_history() -> Array:
	return _test_history.duplicate()


# --- Persistence ---

## Save state to dictionary (for GameManager layer progress).
func save_state() -> Dictionary:
	var classified_data: Dictionary = {}
	for idx in _classified:
		classified_data[str(idx)] = _classified[idx].duplicate()

	return {
		"status": "completed" if is_complete() else "in_progress",
		"classified": classified_data,
		"classified_count": _classified_count,
		"total_count": _total_count,
		"active_subgroup_index": _active_subgroup_index,
		"test_history": _test_history.duplicate(),
	}


## Restore state from saved dictionary.
func restore_from_save(save_data: Dictionary) -> void:
	_classified.clear()
	var classified_data: Dictionary = save_data.get("classified", {})
	for idx_str in classified_data:
		_classified[int(idx_str)] = classified_data[idx_str]

	_classified_count = save_data.get("classified_count", _classified.size())
	_active_subgroup_index = save_data.get("active_subgroup_index", -1)
	_test_history.clear()
	for t in save_data.get("test_history", []):
		_test_history.append(t)


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


## Get the elements of a target subgroup by index.
func get_subgroup_elements(index: int) -> Array:
	if index < 0 or index >= _target_subgroups.size():
		return []
	return _target_subgroups[index].get("elements", []).duplicate()


## Get the order of a target subgroup by index.
func get_subgroup_order(index: int) -> int:
	if index < 0 or index >= _target_subgroups.size():
		return 0
	return _target_subgroups[index].get("order", 0)


# --- Internal helpers ---

## Find the sym_id for a permutation.
func _find_sym_id_for_perm(perm: Permutation) -> String:
	for sym_id in _sym_id_to_perm:
		if _sym_id_to_perm[sym_id].equals(perm):
			return sym_id
	return ""
