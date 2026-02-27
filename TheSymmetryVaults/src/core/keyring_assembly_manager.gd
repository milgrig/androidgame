class_name KeyringAssemblyManager
extends RefCounted
## Manages keyring assembly for Layer 3 — subgroup discovery.
## Analogous to InversePairManager for Layer 2.
##
## The player collects "keyrings" (subsets of group elements) that form
## subgroups. The manager validates each keyring after every add/remove,
## checks for duplicate subgroups, and tracks overall progress.
##
## A valid subgroup must:
##   1. Contain the identity element
##   2. Be closed under composition (∀a,b ∈ H: a∘b ∈ H)
##   3. Be closed under inverses (∀a ∈ H: a⁻¹ ∈ H)
##
## Pedagogical goal: "Some keys naturally group together."


# --- Signals ---

signal subgroup_found(slot_index: int, elements: Array)
signal duplicate_subgroup(slot_index: int)
signal all_subgroups_found()


# --- State ---

var _sym_id_to_perm: Dictionary = {}       ## sym_id -> Permutation
var _sym_id_to_name: Dictionary = {}       ## sym_id -> display name
var _all_sym_ids: Array[String] = []       ## ordered list of all sym_ids

## Target subgroups from level data (each is a Dictionary with "elements", "order", etc.)
var _target_subgroups: Array = []          ## Array[Dictionary]
var _total_count: int = 0                  ## total subgroups to find

## Found subgroups tracking
var _found_signatures: Array[String] = []  ## canonical signatures of found subgroups
var _found_subgroups: Array = []           ## Array[Array[String]] — element lists of found subgroups
var _found_count: int = 0

## Active keyring (the one currently being assembled)
var _active_slot_keys: Array[String] = []  ## sym_ids in the active slot
var _active_slot_index: int = 0            ## which slot is active


# --- Setup ---

## Initialize from level data and layer config.
## level_data: full level JSON dictionary
## layer_config: the "layer_3" section from "layers", or empty dict
func setup(level_data: Dictionary, layer_config: Dictionary = {}) -> void:
	_sym_id_to_perm.clear()
	_sym_id_to_name.clear()
	_all_sym_ids.clear()
	_target_subgroups.clear()
	_found_signatures.clear()
	_found_subgroups.clear()
	_found_count = 0
	_active_slot_keys.clear()
	_active_slot_index = 0

	# Parse automorphisms from level data
	var autos: Array = level_data.get("symmetries", {}).get("automorphisms", [])
	for auto in autos:
		var sym_id: String = auto.get("id", "")
		var perm: Permutation = Permutation.from_array(auto.get("mapping", []))
		_sym_id_to_perm[sym_id] = perm
		_sym_id_to_name[sym_id] = auto.get("name", sym_id)
		_all_sym_ids.append(sym_id)

	# Parse target subgroups from layer config
	_target_subgroups = layer_config.get("subgroups", [])
	_total_count = layer_config.get("subgroup_count", _target_subgroups.size())

	# If no target subgroups provided in layer config, compute them
	if _target_subgroups.is_empty() and not _sym_id_to_perm.is_empty():
		_compute_target_subgroups()


## Compute target subgroups from the group's automorphisms using SubgroupChecker.
func _compute_target_subgroups() -> void:
	var group: Array = []  ## Array[Permutation]
	var id_order: Array[String] = []
	for sym_id in _all_sym_ids:
		group.append(_sym_id_to_perm[sym_id])
		id_order.append(sym_id)

	if group.is_empty():
		return

	var lattice: Dictionary = SubgroupChecker.lattice(group)
	var subgroups_info: Array = lattice.get("subgroups", [])

	_target_subgroups.clear()
	for sub_info in subgroups_info:
		var elements_perms: Array = sub_info.get("elements", [])
		var elem_ids: Array = []
		for p in elements_perms:
			var sid: String = _find_sym_id_for_perm(p)
			if sid != "":
				elem_ids.append(sid)
		elem_ids.sort()

		var is_trivial: bool = (elem_ids.size() == 1) or (elem_ids.size() == group.size())
		var is_normal: bool = SubgroupChecker.is_normal(elements_perms, group)

		_target_subgroups.append({
			"elements": elem_ids,
			"order": elem_ids.size(),
			"is_trivial": is_trivial,
			"is_normal": is_normal,
		})

	_total_count = _target_subgroups.size()


# --- Active Keyring Management ---

## Add a key to the active keyring.
## Returns: {added: bool, reason: String}
func add_key_to_active(sym_id: String) -> Dictionary:
	if not _sym_id_to_perm.has(sym_id):
		return {"added": false, "reason": "unknown_key"}
	if _active_slot_keys.has(sym_id):
		return {"added": false, "reason": "duplicate_key"}

	_active_slot_keys.append(sym_id)
	return {"added": true, "reason": "ok"}


## Remove a key from the active keyring.
## Returns: {removed: bool, reason: String}
func remove_key_from_active(sym_id: String) -> Dictionary:
	var idx: int = _active_slot_keys.find(sym_id)
	if idx < 0:
		return {"removed": false, "reason": "key_not_in_slot"}

	_active_slot_keys.remove_at(idx)
	return {"removed": true, "reason": "ok"}


## Clear the active keyring.
func clear_active() -> void:
	_active_slot_keys.clear()


## Get the current active slot keys.
func get_active_keys() -> Array[String]:
	return _active_slot_keys.duplicate()


# --- Validation ---

## Validate the current active keyring.
## Returns: {is_subgroup: bool, is_duplicate: bool, is_new: bool}
func validate_current() -> Dictionary:
	if _active_slot_keys.is_empty():
		return {"is_subgroup": false, "is_duplicate": false, "is_new": false}

	# Convert sym_ids to Permutations
	var perms: Array = []  ## Array[Permutation]
	for sid in _active_slot_keys:
		var p: Permutation = _sym_id_to_perm.get(sid, null)
		if p == null:
			return {"is_subgroup": false, "is_duplicate": false, "is_new": false}
		perms.append(p)

	# Check 1: Contains identity?
	var has_identity: bool = false
	for p in perms:
		if p.is_identity():
			has_identity = true
			break
	if not has_identity:
		return {"is_subgroup": false, "is_duplicate": false, "is_new": false}

	# Check 2: Closure under composition (∀a,b ∈ H: a∘b ∈ H)
	for a in perms:
		for b in perms:
			var ab: Permutation = a.compose(b)
			var found: bool = false
			for c in perms:
				if c.equals(ab):
					found = true
					break
			if not found:
				return {"is_subgroup": false, "is_duplicate": false, "is_new": false}

	# Check 3: Closure under inverses (∀a ∈ H: a⁻¹ ∈ H)
	for a in perms:
		var a_inv: Permutation = a.inverse()
		var found: bool = false
		for c in perms:
			if c.equals(a_inv):
				found = true
				break
		if not found:
			return {"is_subgroup": false, "is_duplicate": false, "is_new": false}

	# It's a valid subgroup! Check if it's a duplicate.
	var sig: String = _subgroup_signature_from_sym_ids(_active_slot_keys)
	var is_dup: bool = _found_signatures.has(sig)

	return {"is_subgroup": true, "is_duplicate": is_dup, "is_new": not is_dup}


## Auto-validate after key add/remove and emit appropriate signals.
## This is the main entry point called after each keyring modification.
## Returns the validation result.
func auto_validate() -> Dictionary:
	var result: Dictionary = validate_current()

	if result["is_subgroup"]:
		if result["is_new"]:
			# New subgroup found!
			var sig: String = _subgroup_signature_from_sym_ids(_active_slot_keys)
			_found_signatures.append(sig)
			var found_elements: Array[String] = _active_slot_keys.duplicate()
			found_elements.sort()
			_found_subgroups.append(found_elements)
			_found_count += 1

			subgroup_found.emit(_active_slot_index, found_elements)

			# Move to next slot
			_active_slot_keys.clear()
			_active_slot_index += 1

			# Check completion
			if is_complete():
				all_subgroups_found.emit()
		elif result["is_duplicate"]:
			duplicate_subgroup.emit(_active_slot_index)

	return result


# --- Progress ---

## Get progress: {found: int, total: int}
func get_progress() -> Dictionary:
	return {"found": _found_count, "total": _total_count}


## Check if all subgroups have been found.
func is_complete() -> bool:
	return _found_count >= _total_count


## Get all found subgroups (as arrays of sym_ids).
func get_found_subgroups() -> Array:
	return _found_subgroups.duplicate()


## Get the active slot index.
func get_active_slot_index() -> int:
	return _active_slot_index


## Get the total subgroup count.
func get_total_count() -> int:
	return _total_count


# --- Persistence ---

## Save state to dictionary (for GameManager layer progress).
func save_state() -> Dictionary:
	return {
		"status": "completed" if is_complete() else "in_progress",
		"found_subgroups": _found_subgroups.duplicate(),
		"found_count": _found_count,
		"total_count": _total_count,
		"active_slot_keys": _active_slot_keys.duplicate(),
		"active_slot_index": _active_slot_index,
		"found_signatures": _found_signatures.duplicate(),
	}


## Restore state from saved dictionary.
func restore_from_save(save_data: Dictionary) -> void:
	_found_subgroups = []
	for sg in save_data.get("found_subgroups", []):
		var arr: Array[String] = []
		for s in sg:
			arr.append(str(s))
		_found_subgroups.append(arr)

	_found_count = save_data.get("found_count", _found_subgroups.size())

	_found_signatures.clear()
	for sig in save_data.get("found_signatures", []):
		_found_signatures.append(str(sig))

	# If signatures weren't saved, rebuild them from found_subgroups
	if _found_signatures.is_empty() and not _found_subgroups.is_empty():
		for sg in _found_subgroups:
			var sig: String = _subgroup_signature_from_sym_ids(sg)
			_found_signatures.append(sig)

	_active_slot_keys.clear()
	for k in save_data.get("active_slot_keys", []):
		_active_slot_keys.append(str(k))

	_active_slot_index = save_data.get("active_slot_index", _found_count)


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


## Check if a set of sym_ids forms a known target subgroup.
func is_target_subgroup(sym_ids: Array) -> bool:
	var sorted_ids: Array = sym_ids.duplicate()
	sorted_ids.sort()
	for target in _target_subgroups:
		var target_els: Array = target.get("elements", []).duplicate()
		target_els.sort()
		if sorted_ids == target_els:
			return true
	return false


## Get the target subgroup data for a set of sym_ids (or null).
func get_target_subgroup_info(sym_ids: Array) -> Dictionary:
	var sorted_ids: Array = sym_ids.duplicate()
	sorted_ids.sort()
	for target in _target_subgroups:
		var target_els: Array = target.get("elements", []).duplicate()
		target_els.sort()
		if sorted_ids == target_els:
			return target
	return {}


# --- Internal helpers ---

## Create a canonical signature for deduplication from sym_ids.
## Sorts the sym_ids and joins them.
func _subgroup_signature_from_sym_ids(sym_ids: Array) -> String:
	var sorted_ids: Array = sym_ids.duplicate()
	sorted_ids.sort()
	return "|".join(sorted_ids)


## Create a canonical signature from Permutation objects (compatible with SubgroupChecker).
static func _subgroup_signature_from_perms(perms: Array) -> String:
	var mappings: Array = []
	for p in perms:
		var s: String = ""
		for v in p.mapping:
			s += str(v) + ","
		mappings.append(s)
	mappings.sort()
	return "|".join(mappings)


## Find the sym_id for a permutation.
func _find_sym_id_for_perm(perm: Permutation) -> String:
	for sym_id in _sym_id_to_perm:
		if _sym_id_to_perm[sym_id].equals(perm):
			return sym_id
	return ""
