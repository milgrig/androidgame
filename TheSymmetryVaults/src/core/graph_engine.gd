class_name CrystalGraph
extends RefCounted
## Pure logic: colored graph with typed edges.
## Provides automorphism checking and enumeration.

var nodes: Array[Dictionary]  # [{id, color, position, label}]
var edges: Array[Dictionary]  # [{from, to, type, weight}]

func _init(p_nodes: Array[Dictionary] = [], p_edges: Array[Dictionary] = []) -> void:
	nodes = p_nodes
	edges = p_edges

func node_count() -> int:
	return nodes.size()

func get_node_color(id: int) -> String:
	for node in nodes:
		if node["id"] == id:
			return node.get("color", "")
	return ""

func get_edge(from_id: int, to_id: int) -> Dictionary:
	## Returns edge dict or empty dict.
	## Directed edges only match exact (from, to) order.
	## Undirected edges (default) match either direction.
	for edge in edges:
		if edge["from"] == from_id and edge["to"] == to_id:
			return edge
		if not edge.get("directed", false):
			if edge["from"] == to_id and edge["to"] == from_id:
				return edge
	return {}

func has_edge(from_id: int, to_id: int) -> bool:
	return not get_edge(from_id, to_id).is_empty()

func get_edge_type(from_id: int, to_id: int) -> String:
	var e := get_edge(from_id, to_id)
	if e.is_empty():
		return ""
	return e.get("type", "")

func is_automorphism(p: Permutation) -> bool:
	## Check if permutation p preserves graph structure:
	## 1. Node colors must be preserved: color(i) == color(p(i))
	## 2. Edge structure must be preserved: for each edge (u,v) with type T,
	##    edge (p(u), p(v)) must exist with same type T
	if p.size() != node_count():
		return false

	# Check node colors
	for i in range(node_count()):
		if get_node_color(i) != get_node_color(p.apply(i)):
			return false

	# Check edges: every original edge must map to an edge of the same type
	# For directed edges, direction must also be preserved
	for edge in edges:
		var mapped_from := p.apply(edge["from"])
		var mapped_to := p.apply(edge["to"])
		var mapped_edge := get_edge(mapped_from, mapped_to)
		if mapped_edge.is_empty():
			return false
		if mapped_edge.get("type", "") != edge.get("type", ""):
			return false
		if edge.get("directed", false) != mapped_edge.get("directed", false):
			return false

	return true

func find_violations(p: Permutation) -> Dictionary:
	## Returns details about WHY a permutation is NOT an automorphism.
	## Returns: {
	##   "is_valid": bool,
	##   "color_violations": [{node_id, from_color, to_color}],
	##   "edge_violations": [{from, to, mapped_from, mapped_to, reason}],
	##   "summary": String  # brief human-readable description
	## }
	var result := {
		"is_valid": true,
		"color_violations": [],
		"edge_violations": [],
		"summary": ""
	}

	if p.size() != node_count():
		result["is_valid"] = false
		result["summary"] = "Wrong number of nodes"
		return result

	# Check node colors
	for i in range(node_count()):
		var from_color := get_node_color(i)
		var to_color := get_node_color(p.apply(i))
		if from_color != to_color:
			result["is_valid"] = false
			result["color_violations"].append({
				"node_id": i,
				"mapped_id": p.apply(i),
				"from_color": from_color,
				"to_color": to_color
			})

	# Check edges
	for edge in edges:
		var mapped_from := p.apply(edge["from"])
		var mapped_to := p.apply(edge["to"])
		var mapped_edge := get_edge(mapped_from, mapped_to)
		if mapped_edge.is_empty():
			result["is_valid"] = false
			result["edge_violations"].append({
				"from": edge["from"], "to": edge["to"],
				"mapped_from": mapped_from, "mapped_to": mapped_to,
				"reason": "missing_edge"
			})
		elif mapped_edge.get("type", "") != edge.get("type", ""):
			result["is_valid"] = false
			result["edge_violations"].append({
				"from": edge["from"], "to": edge["to"],
				"mapped_from": mapped_from, "mapped_to": mapped_to,
				"reason": "type_mismatch"
			})
		elif edge.get("directed", false) != mapped_edge.get("directed", false):
			result["is_valid"] = false
			result["edge_violations"].append({
				"from": edge["from"], "to": edge["to"],
				"mapped_from": mapped_from, "mapped_to": mapped_to,
				"reason": "direction_mismatch"
			})

	# Build summary
	if result["is_valid"]:
		result["summary"] = ""
	elif result["color_violations"].size() > 0 and result["edge_violations"].size() > 0:
		result["summary"] = "Colors and edges don't match"
	elif result["color_violations"].size() > 0:
		result["summary"] = "Crystal colors don't match after swap"
	else:
		var reason = result["edge_violations"][0]["reason"]
		if reason == "missing_edge":
			result["summary"] = "An edge connection is broken by this swap"
		elif reason == "type_mismatch":
			result["summary"] = "Edge types don't match after swap"
		elif reason == "direction_mismatch":
			result["summary"] = "Edge direction is reversed by this swap"

	return result


func apply_permutation(p: Permutation) -> CrystalGraph:
	## Returns a new graph with nodes permuted by p.
	## Node at position i gets data from node p^-1(i).
	var inv := p.inverse()
	var new_nodes: Array[Dictionary] = []
	for i in range(node_count()):
		var src := inv.apply(i)
		var new_node: Dictionary = nodes[src].duplicate()
		new_node["id"] = i
		# Keep position of target slot, change color/label
		if nodes[i].has("position"):
			new_node["position"] = nodes[i]["position"]
		new_nodes.append(new_node)

	var new_edges: Array[Dictionary] = []
	for edge in edges:
		var new_edge: Dictionary = edge.duplicate()
		new_edge["from"] = p.apply(edge["from"])
		new_edge["to"] = p.apply(edge["to"])
		new_edges.append(new_edge)

	return CrystalGraph.new(new_nodes, new_edges)

func find_all_automorphisms() -> Array:
	## Brute-force: generate all permutations of n elements, check each.
	## Sufficient for game levels (max n ~ 5-6 for Act 1).
	var n := node_count()
	var result: Array = []  # Array[Permutation]
	var perms := _generate_all_permutations(n)
	for perm_arr in perms:
		var typed: Array[int] = []
		for v in perm_arr:
			typed.append(v)
		var p := Permutation.new(typed)
		if is_automorphism(p):
			result.append(p)
	return result

func _generate_all_permutations(n: int) -> Array:
	## Returns array of arrays, each representing a permutation of [0..n-1]
	if n == 0:
		return [[]]
	if n == 1:
		return [[0]]
	var result: Array = []
	_permute_helper(range(n), 0, n, result)
	return result

func _permute_helper(arr: Array, start: int, n: int, result: Array) -> void:
	if start == n:
		result.append(arr.duplicate())
		return
	for i in range(start, n):
		var temp = arr[start]
		arr[start] = arr[i]
		arr[i] = temp
		_permute_helper(arr, start + 1, n, result)
		arr[i] = arr[start]
		arr[start] = temp

# --- Factory: create graph from level JSON data ---

static func from_dict(data: Dictionary) -> CrystalGraph:
	var node_arr: Array[Dictionary] = []
	for n in data.get("nodes", []):
		node_arr.append(n)
	var edge_arr: Array[Dictionary] = []
	for e in data.get("edges", []):
		edge_arr.append(e)
	return CrystalGraph.new(node_arr, edge_arr)
