class_name HallProgressionEngine
extends Node
## Manages hall unlock states and wing progression for the Hall Tree.
##
## Depends on HallTreeData (T030) for the world graph structure
## and GameManager for completed_levels / level_states.
##
## Provides:
## - get_hall_state(hall_id) -> HallState enum
## - is_wing_accessible(wing_id) -> bool
## - get_available_halls() -> Array[String]
## - complete_hall(hall_id) -> void
## - get_wing_progress(wing_id) -> Dictionary
## - get_discovered_resonances() -> Array

# --- Hall state enum (mirrored in HallNodeVisual for display) ---

enum HallState {
	LOCKED,        ## Prerequisites not met — greyed out, no interaction
	AVAILABLE,     ## Prerequisites met, not yet completed — glowing, clickable
	COMPLETED,     ## Completed — golden, clickable (for replay)
	PERFECT        ## Completed with "Seal of Perfection" (no hints used)
}

# --- Signals ---

signal hall_unlocked(hall_id: String)
signal wing_unlocked(wing_id: String)
signal resonance_discovered(resonance: HallTreeData.ResonanceData)

# --- Dependencies ---

## The parsed hall tree data (set externally before use).
var hall_tree: HallTreeData = null

## Reference to completed_levels array.
## If null, falls back to GameManager autoload.
var _completed_levels: Array[String] = []
var _level_states: Dictionary = {}

## When true, use injected _completed_levels / _level_states
## instead of GameManager (for testing).
var _use_injected_state: bool = false


# --- Layer unlock thresholds (configurable) ---
# Each layer N requires a certain number of layer N-1 completions globally.
const LAYER_THRESHOLDS := {
	2: {"required": 8, "from_layer": 1},
	3: {"required": 8, "from_layer": 2},
	4: {"required": 1, "from_layer": 3},
	5: {"required": 1, "from_layer": 4},
}


# ------------------------------------------------------------------
# Dependency injection (for testability)
# ------------------------------------------------------------------

## Inject completion state directly — used by tests that run without
## the GameManager autoload present.
func inject_state(completed: Array[String], states: Dictionary = {}) -> void:
	_completed_levels = completed
	_level_states = states
	_use_injected_state = true


# ------------------------------------------------------------------
# Completion state queries (delegates to GameManager or injected state)
# ------------------------------------------------------------------

func _is_completed(hall_id: String) -> bool:
	if _use_injected_state:
		return hall_id in _completed_levels
	return GameManager.is_level_completed(hall_id)


func _get_level_state(hall_id: String) -> Dictionary:
	if _use_injected_state:
		return _level_states.get(hall_id, {})
	return GameManager.level_states.get(hall_id, {})


func _mark_completed(hall_id: String) -> void:
	if _use_injected_state:
		if hall_id not in _completed_levels:
			_completed_levels.append(hall_id)
	else:
		GameManager.complete_level(hall_id)


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

## Get the display state of a specific hall.
func get_hall_state(hall_id: String) -> HallState:
	if hall_tree == null:
		return HallState.LOCKED

	if _is_completed(hall_id):
		if _has_perfection_seal(hall_id):
			return HallState.PERFECT
		return HallState.COMPLETED

	if _is_hall_available(hall_id):
		return HallState.AVAILABLE

	return HallState.LOCKED


## Check if a wing is accessible (previous wing gate satisfied).
func is_wing_accessible(wing_id: String) -> bool:
	if hall_tree == null:
		return false

	var wing = hall_tree.get_wing(wing_id)
	if wing == null:
		return false

	return _is_wing_accessible_internal(wing)


## Get all currently available (playable) halls — state AVAILABLE or COMPLETED.
func get_available_halls() -> Array[String]:
	var result: Array[String] = []
	if hall_tree == null:
		return result

	for wing in hall_tree.wings:
		for hall_id in wing.halls:
			var state: HallState = get_hall_state(hall_id)
			if state == HallState.AVAILABLE:
				result.append(hall_id)

	return result


## Get progress statistics for a wing.
## Returns: {completed: int, total: int, threshold: int}
func get_wing_progress(wing_id: String) -> Dictionary:
	if hall_tree == null:
		return {"completed": 0, "total": 0, "threshold": 0}

	var wing = hall_tree.get_wing(wing_id)
	if wing == null:
		return {"completed": 0, "total": 0, "threshold": 0}

	var completed: int = _count_completed_in_wing(wing)
	var threshold: int = wing.gate.required_halls if wing.gate else wing.halls.size()

	return {
		"completed": completed,
		"total": wing.halls.size(),
		"threshold": threshold
	}


## Complete a hall — updates state, checks for new unlocks, emits signals.
## This is the main entry point after a player finishes a level.
func complete_hall(hall_id: String) -> void:
	if hall_tree == null:
		return

	# Mark the hall as completed
	_mark_completed(hall_id)

	# Check if any new halls were unlocked (neighbors)
	var neighbors: Array = hall_tree.get_hall_edges(hall_id)
	for neighbor_id in neighbors:
		if not _is_completed(neighbor_id):
			if _is_hall_available(neighbor_id):
				hall_unlocked.emit(neighbor_id)

	# Check if any wing was newly unlocked
	var wing = hall_tree.get_hall_wing(hall_id)
	if wing != null:
		var next_wing = _get_next_wing(wing)
		if next_wing != null and _is_wing_accessible_internal(next_wing):
			wing_unlocked.emit(next_wing.id)

	# Check for new resonances
	var hall_resonances: Array = hall_tree.get_hall_resonances(hall_id)
	for resonance in hall_resonances:
		if _is_resonance_discovered(resonance):
			resonance_discovered.emit(resonance)


## Get all discovered resonances (both halls completed).
func get_discovered_resonances() -> Array:
	var result: Array = []
	if hall_tree == null:
		return result

	for resonance in hall_tree.resonances:
		if _is_resonance_discovered(resonance):
			result.append(resonance)

	return result


# ------------------------------------------------------------------
# Internal logic
# ------------------------------------------------------------------

## Check if a hall is available (wing accessible + at least one prereq completed).
func _is_hall_available(hall_id: String) -> bool:
	var wing = hall_tree.get_hall_wing(hall_id)
	if wing == null:
		return false

	if not _is_wing_accessible_internal(wing):
		return false

	# Start halls are always available if wing is accessible
	if hall_id in wing.start_halls:
		return true

	# At least one predecessor must be completed
	var prereqs: Array = hall_tree.get_hall_prereqs(hall_id)
	for prereq_id in prereqs:
		if _is_completed(prereq_id):
			return true

	# If hall has no prereqs and is not a start hall, it's an orphan
	# within an accessible wing — make it available
	if prereqs.is_empty():
		return true

	return false


## Check if a wing is accessible (gate condition of previous wing met).
func _is_wing_accessible_internal(wing: HallTreeData.WingData) -> bool:
	if wing.order == 1:
		return true  # First wing always accessible

	var gate = wing.gate
	if gate == null:
		return true  # No gate = always accessible

	match gate.type:
		"threshold":
			var source_wing_id: String = gate.required_from_wing
			if source_wing_id == "":
				# Default: check previous wing
				source_wing_id = _get_previous_wing_id(wing)
			var source_wing = hall_tree.get_wing(source_wing_id)
			if source_wing == null:
				return false
			var completed_count: int = _count_completed_in_wing(source_wing)
			return completed_count >= gate.required_halls

		"all":
			var source_wing_id: String = gate.required_from_wing
			if source_wing_id == "":
				source_wing_id = _get_previous_wing_id(wing)
			var source_wing = hall_tree.get_wing(source_wing_id)
			if source_wing == null:
				return false
			return _count_completed_in_wing(source_wing) >= source_wing.halls.size()

		"specific":
			var required: Array[String] = gate.required_specific
			for required_id in required:
				if not _is_completed(required_id):
					return false
			return true

	return false


## Count completed halls in a wing.
func _count_completed_in_wing(wing: HallTreeData.WingData) -> int:
	var count: int = 0
	for hall_id in wing.halls:
		if _is_completed(hall_id):
			count += 1
	return count


## Check if the player has a perfection seal for a hall (no hints used).
func _has_perfection_seal(hall_id: String) -> bool:
	var state: Dictionary = _get_level_state(hall_id)
	return state.get("hints_used", 0) == 0 and _is_completed(hall_id)


## Check if a resonance should be revealed.
func _is_resonance_discovered(resonance: HallTreeData.ResonanceData) -> bool:
	match resonance.discovered_when:
		"both_completed":
			for h_id in resonance.halls:
				if not _is_completed(h_id):
					return false
			return true
		"wing_completed":
			for h_id in resonance.halls:
				var wing = hall_tree.get_hall_wing(h_id)
				if wing == null:
					return false
				if _count_completed_in_wing(wing) < wing.halls.size():
					return false
			return true
	return false


## Get the ID of the wing with order = wing.order - 1.
func _get_previous_wing_id(wing: HallTreeData.WingData) -> String:
	for w in hall_tree.wings:
		if w.order == wing.order - 1:
			return w.id
	return ""


## Get the next wing (order + 1).
func _get_next_wing(wing: HallTreeData.WingData) -> HallTreeData.WingData:
	for w in hall_tree.wings:
		if w.order == wing.order + 1:
			return w
	return null


# ------------------------------------------------------------------
# Layer progression (Layer 2+)
# ------------------------------------------------------------------

## Check if a layer is globally unlocked (enough prior-layer halls completed).
## Layer 1 is always unlocked. Layer 2 requires 8 Layer-1-completed halls, etc.
func is_layer_unlocked(layer: int) -> bool:
	if layer <= 1:
		return true
	var threshold: Dictionary = LAYER_THRESHOLDS.get(layer, {})
	if threshold.is_empty():
		return false
	var required: int = threshold.get("required", 0)
	var from_layer: int = threshold.get("from_layer", layer - 1)
	var completed: int = count_layer_completed_globally(from_layer)
	return completed >= required


## Get the layer completion status for a specific hall.
## Returns: "locked", "available", "in_progress", "completed", or "perfect"
func get_hall_layer_state(hall_id: String, layer: int) -> String:
	if layer <= 0:
		return "locked"

	if layer == 1:
		# Map HallState enum to string
		var state: HallState = get_hall_state(hall_id)
		match state:
			HallState.LOCKED: return "locked"
			HallState.AVAILABLE: return "available"
			HallState.COMPLETED: return "completed"
			HallState.PERFECT: return "perfect"
		return "locked"

	# Layer 2+: check global unlock + prior layer completion
	if not is_layer_unlocked(layer):
		return "locked"

	var prior_state: String = get_hall_layer_state(hall_id, layer - 1)
	if prior_state != "completed" and prior_state != "perfect":
		return "locked"

	# Check save data for this layer's progress
	var layer_data: Dictionary = _get_layer_progress(hall_id, layer)
	return layer_data.get("status", "available")


## Count how many halls have completed a given layer (globally, across all wings).
func count_layer_completed_globally(layer: int) -> int:
	if hall_tree == null:
		return 0
	var count: int = 0
	for wing in hall_tree.wings:
		count += count_layer_completed(wing.id, layer)
	return count


## Count how many halls have completed a given layer within a specific wing.
func count_layer_completed(wing_id: String, layer: int) -> int:
	if hall_tree == null:
		return 0
	var wing = hall_tree.get_wing(wing_id)
	if wing == null:
		return 0
	var count: int = 0
	for hall_id in wing.halls:
		if layer == 1:
			if _is_completed(hall_id):
				count += 1
		else:
			var lp: Dictionary = _get_layer_progress(hall_id, layer)
			var status: String = lp.get("status", "")
			if status == "completed" or status == "perfect":
				count += 1
	return count


## Record layer completion for a hall.
## progress should contain at minimum: {status: "completed", ...}
func set_layer_progress(hall_id: String, layer: int, progress: Dictionary) -> void:
	if _use_injected_state:
		if not _level_states.has(hall_id):
			_level_states[hall_id] = {}
		if not _level_states[hall_id].has("layer_progress"):
			_level_states[hall_id]["layer_progress"] = {}
		_level_states[hall_id]["layer_progress"]["layer_%d" % layer] = progress
	else:
		if not GameManager.level_states.has(hall_id):
			GameManager.level_states[hall_id] = {}
		if not GameManager.level_states[hall_id].has("layer_progress"):
			GameManager.level_states[hall_id]["layer_progress"] = {}
		GameManager.level_states[hall_id]["layer_progress"]["layer_%d" % layer] = progress
		GameManager.save_game()


## Get the layer progress dictionary for a specific hall and layer.
## Returns: {status: "locked"/"available"/"in_progress"/"completed"/"perfect", ...}
func _get_layer_progress(hall_id: String, layer: int) -> Dictionary:
	var state: Dictionary = _get_level_state(hall_id)
	var lp: Dictionary = state.get("layer_progress", {})
	return lp.get("layer_%d" % layer, {})
