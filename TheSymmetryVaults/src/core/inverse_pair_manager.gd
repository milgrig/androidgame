class_name InversePairManager
extends RefCounted
## Manages inverse key pairing for Layer 2.
## Given a set of automorphisms from a level, builds inverse pairs
## and validates player choices.
##
## Layer 2 concept: For each automorphism (key), the player must find
## the key that "undoes" it (its group-theoretic inverse).
## Pedagogical goal: "Every action can be undone."

# --- Inner class: InversePair ---

class InversePair:
	extends RefCounted
	var key_sym_id: String       ## e.g. "r1"
	var key_perm: Permutation    ## e.g. [1, 2, 0]
	var key_name: String         ## e.g. "Поворот на 120°"
	var inverse_sym_id: String   ## e.g. "r2"
	var inverse_perm: Permutation ## e.g. [2, 0, 1]
	var inverse_name: String     ## e.g. "Поворот на 240°"
	var is_self_inverse: bool    ## true if key == inverse (involutions)
	var is_identity: bool        ## true for the identity element
	var paired: bool = false     ## player has matched this pair
	var revealed: bool = false   ## pre-revealed by level config


# --- Signals ---

signal pair_matched(pair_index: int, key_sym_id: String, inverse_sym_id: String)
signal all_pairs_matched()


# --- State ---

var pairs: Array = []                     ## Array[InversePair]
var bidirectional: bool = true            ## Pairing A->B auto-pairs B->A
var _sym_id_to_perm: Dictionary = {}      ## sym_id -> Permutation
var _sym_id_to_name: Dictionary = {}      ## sym_id -> display name


# --- Setup ---

## Initialize from level data and optional layer config.
## level_data: full level JSON dictionary
## layer_config: the "layer_2" section from "layers", or empty dict
func setup(level_data: Dictionary, layer_config: Dictionary = {}) -> void:
	pairs.clear()
	_sym_id_to_perm.clear()
	_sym_id_to_name.clear()

	var autos: Array = level_data.get("symmetries", {}).get("automorphisms", [])
	for auto in autos:
		var sym_id: String = auto.get("id", "")
		var perm: Permutation = Permutation.from_array(auto.get("mapping", []))
		_sym_id_to_perm[sym_id] = perm
		_sym_id_to_name[sym_id] = auto.get("name", sym_id)

	# Read bidirectional setting from config (default true)
	bidirectional = layer_config.get("bidirectional_pairing", true)

	# Build inverse pairs
	var processed: Dictionary = {}  # sym_id -> true (to avoid duplicate mutual pairs)
	for sym_id in _sym_id_to_perm:
		if processed.has(sym_id):
			continue
		var perm: Permutation = _sym_id_to_perm[sym_id]
		var inv_perm: Permutation = perm.inverse()

		# Find the sym_id of the inverse
		var inv_sym_id: String = _find_sym_id_for_perm(inv_perm)
		if inv_sym_id == "":
			push_warning("InversePairManager: no inverse found for %s" % sym_id)
			continue

		var pair: InversePair = InversePair.new()
		pair.key_sym_id = sym_id
		pair.key_perm = perm
		pair.key_name = _sym_id_to_name.get(sym_id, sym_id)
		pair.inverse_sym_id = inv_sym_id
		pair.inverse_perm = inv_perm
		pair.inverse_name = _sym_id_to_name.get(inv_sym_id, inv_sym_id)
		pair.is_self_inverse = (sym_id == inv_sym_id)
		pair.is_identity = perm.is_identity()

		# T111: skip identity pair entirely — never shown in UI
		if pair.is_identity:
			processed[sym_id] = true
			continue

		pairs.append(pair)

		# Mark both as processed (for bidirectional mode)
		processed[sym_id] = true
		if bidirectional and not pair.is_self_inverse:
			processed[inv_sym_id] = true

	# Apply revealed_pairs from config
	var revealed_arr: Array = layer_config.get("revealed_pairs", [])
	for rp in revealed_arr:
		if rp is Array and rp.size() >= 2:
			_reveal_pair(rp[0], rp[1])


## Attempt to pair key_sym_id with candidate_sym_id.
## Returns: {success: bool, reason: String, pair_index: int, is_self_inverse: bool}
func try_pair(key_sym_id: String, candidate_sym_id: String) -> Dictionary:
	var pair: InversePair = _find_pair_by_key(key_sym_id)
	if pair == null:
		return {"success": false, "reason": "unknown_key", "pair_index": -1, "is_self_inverse": false}
	if pair.paired:
		return {"success": false, "reason": "already_paired", "pair_index": pairs.find(pair), "is_self_inverse": false}

	var candidate_perm: Permutation = _sym_id_to_perm.get(candidate_sym_id, null)
	if candidate_perm == null:
		return {"success": false, "reason": "unknown_candidate", "pair_index": -1, "is_self_inverse": false}

	# THE CORE CHECK: is candidate the inverse of key?
	if pair.key_perm.compose(candidate_perm).is_identity():
		pair.paired = true
		var pair_index: int = pairs.find(pair)
		var is_self_inv: bool = pair.is_self_inverse

		# Bidirectional: if we paired A->B, also pair B->A
		if bidirectional and not pair.is_self_inverse:
			var reverse_pair = _find_pair_by_key(candidate_sym_id)
			if reverse_pair != null and not reverse_pair.paired:
				reverse_pair.paired = true
				var rev_idx: int = pairs.find(reverse_pair)
				pair_matched.emit(rev_idx, reverse_pair.key_sym_id, reverse_pair.inverse_sym_id)

		pair_matched.emit(pair_index, key_sym_id, candidate_sym_id)

		if is_complete():
			all_pairs_matched.emit()

		return {"success": true, "reason": "correct", "pair_index": pair_index, "is_self_inverse": is_self_inv}
	else:
		# Show what the composition actually is (for feedback)
		var result_perm: Permutation = pair.key_perm.compose(candidate_perm)
		var result_name: String = _lookup_perm_name(result_perm)
		return {
			"success": false,
			"reason": "not_inverse",
			"pair_index": pairs.find(pair),
			"is_self_inverse": false,
			"result_name": result_name
		}


## Check if all pairs are matched (Layer 2 complete for this level).
func is_complete() -> bool:
	for pair in pairs:
		if not pair.paired:
			return false
	return true


## Get progress: {matched: int, total: int}
## T111: identity is never in pairs, so no filter needed.
func get_progress() -> Dictionary:
	var matched: int = 0
	var total: int = pairs.size()
	for pair in pairs:
		if pair.paired:
			matched += 1
	return {"matched": matched, "total": total}


## Get all pairs (for display).
func get_pairs() -> Array:
	return pairs


## Get the permutation for a sym_id.
func get_perm(sym_id: String) -> Permutation:
	return _sym_id_to_perm.get(sym_id, null)


## Get the display name for a sym_id.
func get_name(sym_id: String) -> String:
	return _sym_id_to_name.get(sym_id, sym_id)


## Get the composition of two permutations by sym_id.
## Returns: {result_perm: Permutation, result_name: String, is_identity: bool}
func compose_by_id(sym_a: String, sym_b: String) -> Dictionary:
	var perm_a: Permutation = _sym_id_to_perm.get(sym_a, null)
	var perm_b: Permutation = _sym_id_to_perm.get(sym_b, null)
	if perm_a == null or perm_b == null:
		return {"result_perm": null, "result_name": "", "is_identity": false}
	var result: Permutation = perm_a.compose(perm_b)
	return {
		"result_perm": result,
		"result_name": _lookup_perm_name(result),
		"is_identity": result.is_identity()
	}


## Get all sym_ids (for candidate pool display).
func get_all_sym_ids() -> Array:
	return _sym_id_to_perm.keys()


## Try to pair two keys by their sym_ids.
## Called when the player presses key A then key B and returns to Home.
## Returns: {success: bool, key_sym_id: String, inv_sym_id: String,
##           pair_index: int, is_self_inverse: bool}
func try_pair_by_sym_ids(sym_a: String, sym_b: String) -> Dictionary:
	# Try both orderings: maybe pair has sym_a as key, or sym_b as key
	var result: Dictionary = try_pair(sym_a, sym_b)
	if result["success"]:
		return {
			"success": true,
			"key_sym_id": sym_a,
			"inv_sym_id": sym_b,
			"pair_index": result["pair_index"],
			"is_self_inverse": result["is_self_inverse"],
		}
	# Try reverse: sym_b as key, sym_a as candidate
	result = try_pair(sym_b, sym_a)
	if result["success"]:
		return {
			"success": true,
			"key_sym_id": sym_b,
			"inv_sym_id": sym_a,
			"pair_index": result["pair_index"],
			"is_self_inverse": result["is_self_inverse"],
		}
	return {"success": false, "key_sym_id": sym_a, "inv_sym_id": sym_b,
			"pair_index": -1, "is_self_inverse": false}


## Check if a sym_id's pair is already matched.
func is_paired(sym_id: String) -> bool:
	for pair in pairs:
		if pair.key_sym_id == sym_id or pair.inverse_sym_id == sym_id:
			return pair.paired
	return false


## Get the inverse sym_id for a given sym_id (regardless of pairing state).
func get_inverse_sym_id(sym_id: String) -> String:
	for pair in pairs:
		if pair.key_sym_id == sym_id:
			return pair.inverse_sym_id
		if pair.inverse_sym_id == sym_id:
			return pair.key_sym_id
	return ""


## Check if a sym_id is a self-inverse element.
func is_self_inverse_sym(sym_id: String) -> bool:
	for pair in pairs:
		if pair.key_sym_id == sym_id or pair.inverse_sym_id == sym_id:
			return pair.is_self_inverse
	return false


# --- Internal helpers ---

## Find a pair by its key sym_id.
func _find_pair_by_key(sym_id: String) -> InversePair:
	for pair in pairs:
		if pair.key_sym_id == sym_id:
			return pair
	return null


## Find the sym_id whose permutation equals the given one.
func _find_sym_id_for_perm(perm: Permutation) -> String:
	for sym_id in _sym_id_to_perm:
		if _sym_id_to_perm[sym_id].equals(perm):
			return sym_id
	return ""


## Look up the display name for a given permutation.
func _lookup_perm_name(perm: Permutation) -> String:
	var sym_id: String = _find_sym_id_for_perm(perm)
	if sym_id != "":
		return _sym_id_to_name.get(sym_id, sym_id)
	return perm.to_cycle_notation()


## Pre-reveal a pair (for tutorial levels).
func _reveal_pair(key_id: String, inv_id: String) -> void:
	var pair: InversePair = _find_pair_by_key(key_id)
	if pair != null and pair.inverse_sym_id == inv_id:
		pair.paired = true
		pair.revealed = true
