extends Node
## Unit tests for HallTreeData.
## Run inside Godot (SceneTree) to verify parsing, caches, and validation.
##
## Usage: attach to a Node in a test scene, or run via GUT framework.

var _pass_count: int = 0
var _fail_count: int = 0
var _test_count: int = 0


func _ready() -> void:
	print("=== HallTreeData Tests ===")
	run_all()
	print("=== Results: %d passed, %d failed (of %d) ===" % [_pass_count, _fail_count, _test_count])
	if _fail_count > 0:
		push_error("TESTS FAILED: %d failures" % _fail_count)


func run_all() -> void:
	test_load_from_file()
	test_parse_wings()
	test_parse_edges()
	test_parse_resonances()
	test_hall_to_wing_cache()
	test_hall_edges_cache()
	test_hall_prereqs_cache()
	test_get_wing()
	test_get_wing_halls()
	test_get_hall_edges()
	test_get_hall_prereqs()
	test_get_hall_wing()
	test_get_hall_resonances()
	test_get_ordered_wings()
	test_validate_valid_tree()
	test_validate_missing_hall_in_edge()
	test_validate_cycle_detection()
	test_validate_start_hall_not_in_wing()
	test_parse_empty_data()
	test_get_nonexistent_wing()
	test_get_edges_for_leaf_hall()


# --- Helpers ---

func _assert_true(condition: bool, message: String) -> void:
	_test_count += 1
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("FAIL: %s" % message)
		print("  FAIL: %s" % message)


func _assert_eq(a, b, message: String) -> void:
	_assert_true(a == b, "%s (got %s, expected %s)" % [message, str(a), str(b)])


func _make_test_data() -> Dictionary:
	## Minimal valid hall_tree.json structure for testing
	return {
		"version": 1,
		"wings": [
			{
				"id": "wing_1",
				"name": "The First Vault",
				"subtitle": "Groups",
				"act": 1,
				"order": 1,
				"gate": {
					"type": "threshold",
					"required_halls": 8,
					"total_halls": 12,
					"required_from_wing": null,
					"required_specific": [],
					"message": "Open 8 halls to proceed"
				},
				"halls": [
					"act1_level01", "act1_level02", "act1_level03",
					"act1_level04", "act1_level05", "act1_level06",
					"act1_level07", "act1_level08", "act1_level09",
					"act1_level10", "act1_level11", "act1_level12"
				],
				"start_halls": ["act1_level01"]
			}
		],
		"edges": [
			{"from": "act1_level01", "to": "act1_level02", "type": "path"},
			{"from": "act1_level01", "to": "act1_level03", "type": "path"},
			{"from": "act1_level02", "to": "act1_level04", "type": "path"},
			{"from": "act1_level03", "to": "act1_level06", "type": "path"},
			{"from": "act1_level04", "to": "act1_level05", "type": "path"},
			{"from": "act1_level05", "to": "act1_level09", "type": "path"},
			{"from": "act1_level09", "to": "act1_level11", "type": "path"},
			{"from": "act1_level10", "to": "act1_level11", "type": "path"}
		],
		"resonances": [
			{
				"halls": ["act1_level01", "act1_level11"],
				"type": "subgroup",
				"description": "Z3 is a subgroup of Z6",
				"discovered_when": "both_completed"
			},
			{
				"halls": ["act1_level05", "act1_level12"],
				"type": "isomorphic",
				"description": "Both share D4",
				"discovered_when": "both_completed"
			}
		]
	}


func _make_tree() -> HallTreeData:
	var tree := HallTreeData.new()
	tree.parse(_make_test_data())
	return tree


# --- Tests ---

func test_load_from_file() -> void:
	var tree := HallTreeData.new()
	var ok := tree.load_from_file("res://data/hall_tree.json")
	_assert_true(ok, "load_from_file should succeed for existing hall_tree.json")
	_assert_true(tree.wings.size() > 0, "load_from_file should parse at least one wing")

	# Non-existent file
	var tree2 := HallTreeData.new()
	var ok2 := tree2.load_from_file("res://data/nonexistent.json")
	_assert_true(not ok2, "load_from_file should fail for missing file")


func test_parse_wings() -> void:
	var tree := _make_tree()
	_assert_eq(tree.wings.size(), 1, "Should have 1 wing")

	var wing = tree.wings[0]
	_assert_eq(wing.id, "wing_1", "Wing ID")
	_assert_eq(wing.name, "The First Vault", "Wing name")
	_assert_eq(wing.subtitle, "Groups", "Wing subtitle")
	_assert_eq(wing.act, 1, "Wing act")
	_assert_eq(wing.order, 1, "Wing order")
	_assert_eq(wing.halls.size(), 12, "Wing should have 12 halls")
	_assert_eq(wing.start_halls.size(), 1, "Wing should have 1 start hall")
	_assert_eq(wing.start_halls[0], "act1_level01", "Start hall ID")


func test_parse_edges() -> void:
	var tree := _make_tree()
	_assert_eq(tree.edges.size(), 8, "Should have 8 edges")

	var first_edge = tree.edges[0]
	_assert_eq(first_edge.from_hall, "act1_level01", "First edge from")
	_assert_eq(first_edge.to_hall, "act1_level02", "First edge to")
	_assert_eq(first_edge.type, "path", "First edge type")


func test_parse_resonances() -> void:
	var tree := _make_tree()
	_assert_eq(tree.resonances.size(), 2, "Should have 2 resonances")

	var r0 = tree.resonances[0]
	_assert_eq(r0.halls.size(), 2, "Resonance should link 2 halls")
	_assert_eq(r0.type, "subgroup", "Resonance type")
	_assert_eq(r0.discovered_when, "both_completed", "Resonance discovery condition")


func test_hall_to_wing_cache() -> void:
	var tree := _make_tree()
	# All 12 halls should map to wing_1
	for i in range(1, 13):
		var hall_id := "act1_level%02d" % i
		var wing = tree._hall_to_wing.get(hall_id)
		_assert_true(wing != null, "Hall '%s' should be in _hall_to_wing" % hall_id)
		if wing:
			_assert_eq(wing.id, "wing_1", "Hall '%s' should belong to wing_1" % hall_id)


func test_hall_edges_cache() -> void:
	var tree := _make_tree()
	# act1_level01 has 2 outgoing edges -> level02 and level03
	var edges_01: Array = tree._hall_edges.get("act1_level01", [])
	_assert_eq(edges_01.size(), 2, "act1_level01 should have 2 outgoing edges")
	_assert_true("act1_level02" in edges_01, "act1_level01 -> act1_level02")
	_assert_true("act1_level03" in edges_01, "act1_level01 -> act1_level03")


func test_hall_prereqs_cache() -> void:
	var tree := _make_tree()
	# act1_level11 has 2 incoming edges: from level09 and level10
	var prereqs_11: Array = tree._hall_prereqs.get("act1_level11", [])
	_assert_eq(prereqs_11.size(), 2, "act1_level11 should have 2 prereqs")
	_assert_true("act1_level09" in prereqs_11, "act1_level11 prereq: act1_level09")
	_assert_true("act1_level10" in prereqs_11, "act1_level11 prereq: act1_level10")

	# act1_level01 is a start hall — no prereqs
	var prereqs_01: Array = tree._hall_prereqs.get("act1_level01", [])
	_assert_eq(prereqs_01.size(), 0, "act1_level01 (start hall) should have 0 prereqs")


func test_get_wing() -> void:
	var tree := _make_tree()
	var wing = tree.get_wing("wing_1")
	_assert_true(wing != null, "get_wing('wing_1') should return a wing")
	if wing:
		_assert_eq(wing.id, "wing_1", "Returned wing ID")

	var none = tree.get_wing("nonexistent")
	_assert_true(none == null, "get_wing('nonexistent') should return null")


func test_get_wing_halls() -> void:
	var tree := _make_tree()
	var halls := tree.get_wing_halls("wing_1")
	_assert_eq(halls.size(), 12, "get_wing_halls should return 12 halls")
	_assert_true("act1_level01" in halls, "Hall list should include act1_level01")

	var empty := tree.get_wing_halls("nonexistent")
	_assert_eq(empty.size(), 0, "get_wing_halls for nonexistent wing returns empty")


func test_get_hall_edges() -> void:
	var tree := _make_tree()
	var edges_01: Array = tree.get_hall_edges("act1_level01")
	_assert_eq(edges_01.size(), 2, "get_hall_edges for act1_level01")

	var edges_none: Array = tree.get_hall_edges("nonexistent")
	_assert_eq(edges_none.size(), 0, "get_hall_edges for nonexistent hall returns empty")


func test_get_hall_prereqs() -> void:
	var tree := _make_tree()
	var prereqs: Array = tree.get_hall_prereqs("act1_level04")
	_assert_eq(prereqs.size(), 1, "act1_level04 should have 1 prereq")
	_assert_true("act1_level02" in prereqs, "act1_level04 prereq: act1_level02")

	var prereqs_start: Array = tree.get_hall_prereqs("act1_level01")
	_assert_eq(prereqs_start.size(), 0, "Start hall should have 0 prereqs")


func test_get_hall_wing() -> void:
	var tree := _make_tree()
	var wing = tree.get_hall_wing("act1_level05")
	_assert_true(wing != null, "get_hall_wing for act1_level05 should return a wing")
	if wing:
		_assert_eq(wing.id, "wing_1", "act1_level05 belongs to wing_1")

	var none = tree.get_hall_wing("nonexistent")
	_assert_true(none == null, "get_hall_wing for nonexistent returns null")


func test_get_hall_resonances() -> void:
	var tree := _make_tree()
	var res_01: Array = tree.get_hall_resonances("act1_level01")
	_assert_eq(res_01.size(), 1, "act1_level01 has 1 resonance")
	_assert_eq(res_01[0].type, "subgroup", "Resonance type for act1_level01")

	var res_05: Array = tree.get_hall_resonances("act1_level05")
	_assert_eq(res_05.size(), 1, "act1_level05 has 1 resonance")

	var res_none: Array = tree.get_hall_resonances("act1_level07")
	_assert_eq(res_none.size(), 0, "act1_level07 has no resonances")


func test_get_ordered_wings() -> void:
	var tree := _make_tree()
	var ordered: Array = tree.get_ordered_wings()
	_assert_eq(ordered.size(), 1, "Should have 1 wing")
	_assert_eq(ordered[0].id, "wing_1", "First ordered wing is wing_1")


func test_validate_valid_tree() -> void:
	var tree := _make_tree()
	var errors := tree.validate()
	_assert_eq(errors.size(), 0, "Valid tree should have 0 validation errors, got: %s" % str(errors))


func test_validate_missing_hall_in_edge() -> void:
	var data := _make_test_data()
	data["edges"].append({"from": "act1_level01", "to": "nonexistent_hall", "type": "path"})
	var tree := HallTreeData.new()
	tree.parse(data)
	var errors := tree.validate()
	_assert_true(errors.size() > 0, "Should detect edge to unknown hall")
	var found_error := false
	for e in errors:
		if "nonexistent_hall" in e:
			found_error = true
	_assert_true(found_error, "Error message should mention 'nonexistent_hall'")


func test_validate_cycle_detection() -> void:
	var data := _make_test_data()
	# Create a cycle: level04 -> level02 (level02 -> level04 already exists)
	data["edges"].append({"from": "act1_level04", "to": "act1_level02", "type": "path"})
	var tree := HallTreeData.new()
	tree.parse(data)
	var errors := tree.validate()
	var has_cycle_error := false
	for e in errors:
		if "Cycle" in e or "cycle" in e:
			has_cycle_error = true
	_assert_true(has_cycle_error, "Should detect cycle in graph")


func test_validate_start_hall_not_in_wing() -> void:
	var data := _make_test_data()
	data["wings"][0]["start_halls"] = ["nonexistent_start"]
	var tree := HallTreeData.new()
	tree.parse(data)
	var errors := tree.validate()
	var found := false
	for e in errors:
		if "nonexistent_start" in e:
			found = true
	_assert_true(found, "Should detect start hall not in wing's halls list")


func test_parse_empty_data() -> void:
	var tree := HallTreeData.new()
	tree.parse({})
	_assert_eq(tree.wings.size(), 0, "Empty data: no wings")
	_assert_eq(tree.edges.size(), 0, "Empty data: no edges")
	_assert_eq(tree.resonances.size(), 0, "Empty data: no resonances")
	var errors := tree.validate()
	_assert_true(errors.size() > 0, "Empty tree should have validation errors")


func test_get_nonexistent_wing() -> void:
	var tree := _make_tree()
	var wing = tree.get_wing("wing_99")
	_assert_true(wing == null, "Nonexistent wing returns null")


func test_get_edges_for_leaf_hall() -> void:
	var tree := _make_tree()
	# act1_level11 has incoming but might not have outgoing in test data
	var edges_11: Array = tree.get_hall_edges("act1_level11")
	_assert_eq(edges_11.size(), 0, "Leaf hall should have 0 outgoing edges")
