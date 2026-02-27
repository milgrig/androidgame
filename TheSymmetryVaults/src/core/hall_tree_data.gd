class_name HallTreeData
extends RefCounted
## Parsed representation of hall_tree.json — the world graph of halls and wings.
##
## Provides:
## - parse(data) — builds typed data structures from raw JSON Dictionary
## - load_from_file(path) — loads and parses hall_tree.json
## - get_wing(wing_id) — returns a wing Dictionary
## - get_hall_edges(hall_id) — outgoing neighbors
## - get_hall_prereqs(hall_id) — incoming neighbors (prerequisites)
## - get_hall_wing(hall_id) — which wing contains this hall
## - get_hall_resonances(hall_id) — resonances involving this hall
## - get_ordered_wings() — all wings sorted by order
## - validate() — structural integrity checks

# --- Inner data classes ---

class WingData:
	var id: String
	var name: String
	var subtitle: String
	var act: int
	var order: int
	var gate: GateData
	var halls: Array[String]
	var start_halls: Array[String]


class GateData:
	var type: String              # "threshold", "all", "specific"
	var required_halls: int       # for "threshold": how many halls needed
	var total_halls: int          # total in the wing (for display "7/10")
	var required_from_wing: String  # which wing's gate this checks ("" = previous)
	var required_specific: Array[String]  # for "specific": exact hall IDs needed
	var message: String


class HallEdge:
	var from_hall: String
	var to_hall: String
	var type: String              # "path", "secret"


class ResonanceData:
	var halls: Array[String]
	var type: String              # "subgroup", "quotient", "isomorphic", "extension", "same_group_deeper"
	var description: String
	var discovered_when: String   # "both_completed", "wing_completed"


# --- Public data ---

var version: int = 0
var wings: Array = []              # Array of WingData
var edges: Array = []              # Array of HallEdge
var resonances: Array = []         # Array of ResonanceData

# --- Lookup caches (built on parse) ---

var _hall_to_wing: Dictionary = {} # hall_id -> WingData
var _hall_edges: Dictionary = {}   # hall_id -> Array[String] (outgoing neighbor IDs)
var _hall_prereqs: Dictionary = {} # hall_id -> Array[String] (incoming neighbor IDs)


# ------------------------------------------------------------------
# Loading
# ------------------------------------------------------------------

## Load and parse hall_tree.json from the given path.
## Returns true on success, false on any error.
func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("HallTreeData: file not found: %s" % path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("HallTreeData: cannot open file: %s" % path)
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("HallTreeData: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return false

	if not (json.data is Dictionary):
		push_error("HallTreeData: root must be a Dictionary")
		return false

	parse(json.data)
	return true


# ------------------------------------------------------------------
# Parsing
# ------------------------------------------------------------------

## Parse a raw Dictionary (already-decoded JSON) into typed structures.
func parse(data: Dictionary) -> void:
	version = int(data.get("version", 0))
	wings.clear()
	edges.clear()
	resonances.clear()
	_hall_to_wing.clear()
	_hall_edges.clear()
	_hall_prereqs.clear()

	# --- Wings ---
	for w in data.get("wings", []):
		var wing := WingData.new()
		wing.id = str(w.get("id", ""))
		wing.name = str(w.get("name", ""))
		wing.subtitle = str(w.get("subtitle", ""))
		wing.act = int(w.get("act", 0))
		wing.order = int(w.get("order", 0))

		# Gate
		var g = w.get("gate", {})
		if g is Dictionary and not g.is_empty():
			var gate := GateData.new()
			gate.type = str(g.get("type", "threshold"))
			gate.required_halls = int(g.get("required_halls", 0))
			gate.total_halls = int(g.get("total_halls", 0))
			var rfw = g.get("required_from_wing", null)
			gate.required_from_wing = str(rfw) if rfw != null else ""
			var rs = g.get("required_specific", [])
			gate.required_specific = []
			for s in rs:
				gate.required_specific.append(str(s))
			gate.message = str(g.get("message", ""))
			wing.gate = gate
		else:
			wing.gate = null

		# Hall list
		wing.halls = []
		for h in w.get("halls", []):
			wing.halls.append(str(h))

		# Start halls
		wing.start_halls = []
		for sh in w.get("start_halls", []):
			wing.start_halls.append(str(sh))

		wings.append(wing)

		# Build hall -> wing cache
		for hall_id in wing.halls:
			_hall_to_wing[hall_id] = wing

	# --- Edges ---
	for e in data.get("edges", []):
		var edge := HallEdge.new()
		edge.from_hall = str(e.get("from", ""))
		edge.to_hall = str(e.get("to", ""))
		edge.type = str(e.get("type", "path"))
		edges.append(edge)

	# Build edge caches
	_build_edge_caches()

	# --- Resonances ---
	for r in data.get("resonances", []):
		var res := ResonanceData.new()
		res.halls = []
		for h in r.get("halls", []):
			res.halls.append(str(h))
		res.type = str(r.get("type", ""))
		res.description = str(r.get("description", ""))
		res.discovered_when = str(r.get("discovered_when", "both_completed"))
		resonances.append(res)


func _build_edge_caches() -> void:
	_hall_edges.clear()
	_hall_prereqs.clear()
	for edge in edges:
		# Outgoing: from -> to
		if not _hall_edges.has(edge.from_hall):
			_hall_edges[edge.from_hall] = []
		_hall_edges[edge.from_hall].append(edge.to_hall)
		# Incoming: to <- from
		if not _hall_prereqs.has(edge.to_hall):
			_hall_prereqs[edge.to_hall] = []
		_hall_prereqs[edge.to_hall].append(edge.from_hall)


# ------------------------------------------------------------------
# Query API
# ------------------------------------------------------------------

## Get a wing by ID. Returns null if not found.
func get_wing(wing_id: String) -> WingData:
	for wing in wings:
		if wing.id == wing_id:
			return wing
	return null


## Get all hall IDs in a wing. Returns empty array if wing not found.
func get_wing_halls(wing_id: String) -> Array[String]:
	var wing := get_wing(wing_id)
	if wing == null:
		return []
	return wing.halls


## Get outgoing edges from a hall (neighbor hall IDs).
func get_hall_edges(hall_id: String) -> Array:
	return _hall_edges.get(hall_id, [])


## Get incoming edges to a hall (prerequisite hall IDs).
func get_hall_prereqs(hall_id: String) -> Array:
	return _hall_prereqs.get(hall_id, [])


## Get the wing containing a specific hall. Returns null if not found.
func get_hall_wing(hall_id: String) -> WingData:
	return _hall_to_wing.get(hall_id, null)


## Get all resonances involving a specific hall.
func get_hall_resonances(hall_id: String) -> Array:
	var result: Array = []
	for res in resonances:
		if hall_id in res.halls:
			result.append(res)
	return result


## Get all wings, ordered by their 'order' field.
func get_ordered_wings() -> Array:
	var sorted_wings: Array = wings.duplicate()
	sorted_wings.sort_custom(func(a, b): return a.order < b.order)
	return sorted_wings


# ------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------

## Validate the tree structure. Returns list of errors; empty = valid.
func validate() -> Array[String]:
	var errors: Array[String] = []

	if wings.is_empty():
		errors.append("No wings defined")

	# Collect all known hall IDs across all wings
	var all_halls: Dictionary = {}
	for wing in wings:
		if wing.id == "":
			errors.append("Wing with empty id")
		if wing.halls.is_empty():
			errors.append("Wing '%s' has no halls" % wing.id)
		for hall_id in wing.halls:
			if hall_id in all_halls:
				errors.append("Hall '%s' appears in multiple wings" % hall_id)
			all_halls[hall_id] = true

		# Validate start_halls are within the wing
		for sh in wing.start_halls:
			if sh not in wing.halls:
				errors.append("Start hall '%s' not in wing '%s' halls list" % [sh, wing.id])

		# Validate gate
		if wing.gate != null:
			if wing.gate.type not in ["threshold", "all", "specific"]:
				errors.append("Wing '%s' has unknown gate type '%s'" % [wing.id, wing.gate.type])
			if wing.gate.type == "threshold" and wing.gate.required_halls <= 0:
				errors.append("Wing '%s' threshold gate requires required_halls > 0" % wing.id)

	# Validate edges reference known halls
	for edge in edges:
		if edge.from_hall not in all_halls:
			errors.append("Edge from unknown hall '%s'" % edge.from_hall)
		if edge.to_hall not in all_halls:
			errors.append("Edge to unknown hall '%s'" % edge.to_hall)
		if edge.from_hall == edge.to_hall:
			errors.append("Self-loop edge on hall '%s'" % edge.from_hall)

	# Validate resonances reference known halls
	for res in resonances:
		if res.halls.size() < 2:
			errors.append("Resonance must link at least 2 halls")
		for h in res.halls:
			if h not in all_halls:
				errors.append("Resonance references unknown hall '%s'" % h)

	# Check for cycles (DAG property)
	var cycle_errors := _check_for_cycles(all_halls)
	errors.append_array(cycle_errors)

	return errors


## Detect cycles using DFS-based topological sort.
func _check_for_cycles(all_halls: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	# States: 0 = unvisited, 1 = visiting (in current path), 2 = finished
	var state: Dictionary = {}
	for hall_id in all_halls:
		state[hall_id] = 0

	for hall_id in all_halls:
		if state[hall_id] == 0:
			if _dfs_has_cycle(hall_id, state):
				errors.append("Cycle detected involving hall '%s'" % hall_id)
				break  # One cycle error is enough

	return errors


func _dfs_has_cycle(hall_id: String, state: Dictionary) -> bool:
	state[hall_id] = 1  # visiting
	var neighbors: Array = _hall_edges.get(hall_id, [])
	for neighbor_id in neighbors:
		if not state.has(neighbor_id):
			continue
		if state[neighbor_id] == 1:
			return true  # back-edge = cycle
		if state[neighbor_id] == 0:
			if _dfs_has_cycle(neighbor_id, state):
				return true
	state[hall_id] = 2  # finished
	return false
