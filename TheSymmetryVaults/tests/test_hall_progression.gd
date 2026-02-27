extends Node
## Unit tests for HallProgressionEngine.
## Run inside Godot (SceneTree) to verify progression logic,
## gate types, and state transitions.
##
## Uses inject_state() so tests run without GameManager autoload.

var _pass_count: int = 0
var _fail_count: int = 0
var _test_count: int = 0


func _ready() -> void:
	print("=== HallProgressionEngine Tests ===")
	run_all()
	print("=== Results: %d passed, %d failed (of %d) ===" % [_pass_count, _fail_count, _test_count])
	if _fail_count > 0:
		push_error("TESTS FAILED: %d failures" % _fail_count)


func run_all() -> void:
	# State transitions
	test_initial_state_locked()
	test_start_hall_available()
	test_locked_to_available_to_completed()
	test_completed_with_perfection_seal()
	test_completed_without_perfection_seal()

	# Hall availability
	test_dependent_hall_unlocked_after_prereq_completed()
	test_dependent_hall_locked_without_prereq()
	test_multiple_prereqs_any_one_sufficient()
	test_orphan_hall_available_in_accessible_wing()

	# Wing gates
	test_threshold_gate_met()
	test_threshold_gate_not_met()
	test_threshold_gate_7_of_12()
	test_all_gate_met()
	test_all_gate_not_met()
	test_specific_gate_met()
	test_specific_gate_not_met()
	test_first_wing_always_accessible()

	# get_available_halls
	test_get_available_halls_initial()
	test_get_available_halls_after_completion()

	# Wing progress
	test_get_wing_progress()

	# complete_hall signals
	test_complete_hall_unlocks_neighbors()
	test_complete_hall_unlocks_wing()

	# Resonances
	test_resonance_not_discovered_until_both_completed()
	test_resonance_discovered_after_both_completed()

	# Edge cases
	test_null_hall_tree()
	test_unknown_hall_id()
	test_wing_without_gate()


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


## Build a test data dictionary with 2 wings for thorough testing.
func _make_test_data() -> Dictionary:
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
			},
			{
				"id": "wing_2",
				"name": "The Inner Sanctum",
				"subtitle": "Subgroups",
				"act": 2,
				"order": 2,
				"gate": {
					"type": "threshold",
					"required_halls": 7,
					"total_halls": 12,
					"required_from_wing": "wing_1",
					"required_specific": [],
					"message": "Complete 7 halls in the First Vault"
				},
				"halls": ["act2_level01", "act2_level02"],
				"start_halls": ["act2_level01"]
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
			{"from": "act1_level10", "to": "act1_level11", "type": "path"},
			{"from": "act2_level01", "to": "act2_level02", "type": "path"}
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


func _make_engine(completed: Array[String] = [], states: Dictionary = {}) -> HallProgressionEngine:
	var tree := HallTreeData.new()
	tree.parse(_make_test_data())

	var engine := HallProgressionEngine.new()
	engine.hall_tree = tree
	engine.inject_state(completed, states)
	return engine


## Build engine with custom data (e.g. for specific/all gate tests).
func _make_engine_with_data(data: Dictionary, completed: Array[String] = [], states: Dictionary = {}) -> HallProgressionEngine:
	var tree := HallTreeData.new()
	tree.parse(data)

	var engine := HallProgressionEngine.new()
	engine.hall_tree = tree
	engine.inject_state(completed, states)
	return engine


# ------------------------------------------------------------------
# State transition tests
# ------------------------------------------------------------------

func test_initial_state_locked() -> void:
	var engine := _make_engine()
	# Non-start halls should be LOCKED initially
	var state := engine.get_hall_state("act1_level02")
	_assert_eq(state, HallProgressionEngine.HallState.LOCKED,
		"Non-start hall should be LOCKED initially")


func test_start_hall_available() -> void:
	var engine := _make_engine()
	# Start hall of first wing should be AVAILABLE
	var state := engine.get_hall_state("act1_level01")
	_assert_eq(state, HallProgressionEngine.HallState.AVAILABLE,
		"Start hall of wing_1 should be AVAILABLE")


func test_locked_to_available_to_completed() -> void:
	# Step 1: level02 starts LOCKED
	var engine := _make_engine()
	_assert_eq(engine.get_hall_state("act1_level02"),
		HallProgressionEngine.HallState.LOCKED,
		"level02 should start LOCKED")

	# Step 2: after completing level01, level02 becomes AVAILABLE
	var engine2 := _make_engine(["act1_level01"])
	_assert_eq(engine2.get_hall_state("act1_level02"),
		HallProgressionEngine.HallState.AVAILABLE,
		"level02 should be AVAILABLE after level01 completed")

	# Step 3: after completing level02 itself, it becomes COMPLETED
	var engine3 := _make_engine(["act1_level01", "act1_level02"])
	_assert_eq(engine3.get_hall_state("act1_level02"),
		HallProgressionEngine.HallState.COMPLETED,
		"level02 should be COMPLETED after both level01 and level02 completed")


func test_completed_with_perfection_seal() -> void:
	var states := {"act1_level01": {"hints_used": 0, "time_spent_seconds": 60}}
	var engine := _make_engine(["act1_level01"], states)
	_assert_eq(engine.get_hall_state("act1_level01"),
		HallProgressionEngine.HallState.PERFECT,
		"Completed hall with 0 hints should be PERFECT")


func test_completed_without_perfection_seal() -> void:
	var states := {"act1_level01": {"hints_used": 2, "time_spent_seconds": 120}}
	var engine := _make_engine(["act1_level01"], states)
	_assert_eq(engine.get_hall_state("act1_level01"),
		HallProgressionEngine.HallState.COMPLETED,
		"Completed hall with hints used should be COMPLETED, not PERFECT")


# ------------------------------------------------------------------
# Hall availability tests
# ------------------------------------------------------------------

func test_dependent_hall_unlocked_after_prereq_completed() -> void:
	# level04 depends on level02; complete level01 and level02
	var engine := _make_engine(["act1_level01", "act1_level02"])
	_assert_eq(engine.get_hall_state("act1_level04"),
		HallProgressionEngine.HallState.AVAILABLE,
		"level04 should be AVAILABLE after prereq level02 completed")


func test_dependent_hall_locked_without_prereq() -> void:
	# level04 depends on level02; only complete level01
	var engine := _make_engine(["act1_level01"])
	_assert_eq(engine.get_hall_state("act1_level04"),
		HallProgressionEngine.HallState.LOCKED,
		"level04 should be LOCKED when prereq level02 not completed")


func test_multiple_prereqs_any_one_sufficient() -> void:
	# level11 has prereqs: level09 and level10 (either is sufficient)
	# Complete level01 -> level02 -> level04 -> level05 -> level09
	var completed: Array[String] = [
		"act1_level01", "act1_level02", "act1_level04",
		"act1_level05", "act1_level09"
	]
	var engine := _make_engine(completed)
	_assert_eq(engine.get_hall_state("act1_level11"),
		HallProgressionEngine.HallState.AVAILABLE,
		"level11 should be AVAILABLE when at least one prereq (level09) is completed")


func test_orphan_hall_available_in_accessible_wing() -> void:
	# Halls with no prereqs and not start_halls (orphans) should be available
	# if their wing is accessible. level07, level08, level10 have no incoming edges
	# in test data. Actually level10 has no prereqs in test data.
	# Let's check: in test data, act1_level10 has no incoming edges
	# It's in an accessible wing (wing_1), so it should be AVAILABLE
	var engine := _make_engine()
	# level07 has no incoming edges in test data
	var state_07 := engine.get_hall_state("act1_level07")
	_assert_eq(state_07, HallProgressionEngine.HallState.AVAILABLE,
		"Orphan hall in accessible wing should be AVAILABLE")


# ------------------------------------------------------------------
# Wing gate tests
# ------------------------------------------------------------------

func test_first_wing_always_accessible() -> void:
	var engine := _make_engine()
	_assert_true(engine.is_wing_accessible("wing_1"),
		"First wing (order=1) should always be accessible")


func test_threshold_gate_met() -> void:
	# wing_2 requires 7 completed halls from wing_1
	var completed: Array[String] = [
		"act1_level01", "act1_level02", "act1_level03",
		"act1_level04", "act1_level05", "act1_level06",
		"act1_level07"
	]
	var engine := _make_engine(completed)
	_assert_true(engine.is_wing_accessible("wing_2"),
		"wing_2 should be accessible with 7/7 threshold met")


func test_threshold_gate_not_met() -> void:
	# wing_2 requires 7, only complete 6
	var completed: Array[String] = [
		"act1_level01", "act1_level02", "act1_level03",
		"act1_level04", "act1_level05", "act1_level06"
	]
	var engine := _make_engine(completed)
	_assert_true(not engine.is_wing_accessible("wing_2"),
		"wing_2 should NOT be accessible with only 6/7 threshold")


func test_threshold_gate_7_of_12() -> void:
	# Classic scenario: complete exactly 7 out of 12 halls in wing_1
	var completed: Array[String] = [
		"act1_level01", "act1_level02", "act1_level03",
		"act1_level04", "act1_level05", "act1_level06",
		"act1_level09"
	]
	var engine := _make_engine(completed)
	_assert_true(engine.is_wing_accessible("wing_2"),
		"Threshold gate 7/12: should pass with exactly 7 completed")

	# Now verify the start hall of wing_2 is available
	_assert_eq(engine.get_hall_state("act2_level01"),
		HallProgressionEngine.HallState.AVAILABLE,
		"Start hall of wing_2 should be AVAILABLE after gate opens")


func test_all_gate_met() -> void:
	# Build data with "all" gate on wing_2
	var data := _make_test_data()
	data["wings"][1]["gate"] = {
		"type": "all",
		"required_halls": 0,
		"total_halls": 12,
		"required_from_wing": "wing_1",
		"required_specific": [],
		"message": "Complete all halls in wing_1"
	}
	# Complete all 12 halls
	var completed: Array[String] = []
	for i in range(1, 13):
		completed.append("act1_level%02d" % i)

	var engine := _make_engine_with_data(data, completed)
	_assert_true(engine.is_wing_accessible("wing_2"),
		"ALL gate should pass when all 12 halls completed")


func test_all_gate_not_met() -> void:
	var data := _make_test_data()
	data["wings"][1]["gate"] = {
		"type": "all",
		"required_halls": 0,
		"total_halls": 12,
		"required_from_wing": "wing_1",
		"required_specific": [],
		"message": "Complete all halls in wing_1"
	}
	# Complete 11 out of 12
	var completed: Array[String] = []
	for i in range(1, 12):
		completed.append("act1_level%02d" % i)

	var engine := _make_engine_with_data(data, completed)
	_assert_true(not engine.is_wing_accessible("wing_2"),
		"ALL gate should NOT pass when only 11/12 halls completed")


func test_specific_gate_met() -> void:
	var data := _make_test_data()
	data["wings"][1]["gate"] = {
		"type": "specific",
		"required_halls": 0,
		"total_halls": 0,
		"required_from_wing": "",
		"required_specific": ["act1_level01", "act1_level09", "act1_level11"],
		"message": "Complete the key halls"
	}
	var completed: Array[String] = [
		"act1_level01", "act1_level09", "act1_level11"
	]

	var engine := _make_engine_with_data(data, completed)
	_assert_true(engine.is_wing_accessible("wing_2"),
		"SPECIFIC gate should pass when all required halls completed")


func test_specific_gate_not_met() -> void:
	var data := _make_test_data()
	data["wings"][1]["gate"] = {
		"type": "specific",
		"required_halls": 0,
		"total_halls": 0,
		"required_from_wing": "",
		"required_specific": ["act1_level01", "act1_level09", "act1_level11"],
		"message": "Complete the key halls"
	}
	# Only 2 of 3 required halls completed
	var completed: Array[String] = [
		"act1_level01", "act1_level09"
	]

	var engine := _make_engine_with_data(data, completed)
	_assert_true(not engine.is_wing_accessible("wing_2"),
		"SPECIFIC gate should NOT pass when a required hall is missing")


# ------------------------------------------------------------------
# get_available_halls tests
# ------------------------------------------------------------------

func test_get_available_halls_initial() -> void:
	var engine := _make_engine()
	var available := engine.get_available_halls()
	_assert_true("act1_level01" in available,
		"Start hall should be in available halls initially")
	# No halls from wing_2 should be available (wing locked)
	_assert_true("act2_level01" not in available,
		"Wing 2 start hall should NOT be available initially")


func test_get_available_halls_after_completion() -> void:
	var engine := _make_engine(["act1_level01"])
	var available := engine.get_available_halls()
	_assert_true("act1_level02" in available,
		"level02 should be available after level01 completed")
	_assert_true("act1_level03" in available,
		"level03 should be available after level01 completed")
	# level01 itself is COMPLETED, not AVAILABLE, so not in list
	_assert_true("act1_level01" not in available,
		"Completed hall should not be in get_available_halls()")


# ------------------------------------------------------------------
# get_wing_progress tests
# ------------------------------------------------------------------

func test_get_wing_progress() -> void:
	var completed: Array[String] = ["act1_level01", "act1_level02", "act1_level03"]
	var engine := _make_engine(completed)
	var progress := engine.get_wing_progress("wing_1")
	_assert_eq(progress["completed"], 3, "Wing progress: 3 completed")
	_assert_eq(progress["total"], 12, "Wing progress: 12 total")
	_assert_eq(progress["threshold"], 8, "Wing progress: threshold = 8")


# ------------------------------------------------------------------
# complete_hall signal tests
# ------------------------------------------------------------------

func test_complete_hall_unlocks_neighbors() -> void:
	var engine := _make_engine()
	add_child(engine)  # Needed for signal processing

	var unlocked_halls: Array[String] = []
	engine.hall_unlocked.connect(func(hall_id: String): unlocked_halls.append(hall_id))

	engine.complete_hall("act1_level01")

	_assert_true("act1_level02" in unlocked_halls,
		"complete_hall should emit hall_unlocked for level02")
	_assert_true("act1_level03" in unlocked_halls,
		"complete_hall should emit hall_unlocked for level03")

	remove_child(engine)
	engine.queue_free()


func test_complete_hall_unlocks_wing() -> void:
	# Complete 6 halls, then complete 7th to cross threshold
	var completed: Array[String] = [
		"act1_level01", "act1_level02", "act1_level03",
		"act1_level04", "act1_level05", "act1_level06"
	]
	var engine := _make_engine(completed)
	add_child(engine)

	var unlocked_wings: Array[String] = []
	engine.wing_unlocked.connect(func(wing_id: String): unlocked_wings.append(wing_id))

	engine.complete_hall("act1_level07")

	_assert_true("wing_2" in unlocked_wings,
		"complete_hall should emit wing_unlocked for wing_2 when threshold met")

	remove_child(engine)
	engine.queue_free()


# ------------------------------------------------------------------
# Resonance tests
# ------------------------------------------------------------------

func test_resonance_not_discovered_until_both_completed() -> void:
	# Resonance links level01 and level11
	var engine := _make_engine(["act1_level01"])
	var discovered := engine.get_discovered_resonances()
	var found := false
	for res in discovered:
		if "act1_level01" in res.halls and "act1_level11" in res.halls:
			found = true
	_assert_true(not found,
		"Resonance should NOT be discovered when only one hall completed")


func test_resonance_discovered_after_both_completed() -> void:
	var engine := _make_engine(["act1_level01", "act1_level11"])
	var discovered := engine.get_discovered_resonances()
	var found := false
	for res in discovered:
		if "act1_level01" in res.halls and "act1_level11" in res.halls:
			found = true
	_assert_true(found,
		"Resonance should be discovered when both halls completed")


# ------------------------------------------------------------------
# Edge case tests
# ------------------------------------------------------------------

func test_null_hall_tree() -> void:
	var engine := HallProgressionEngine.new()
	engine.inject_state([])
	# Should not crash, just return safe defaults
	_assert_eq(engine.get_hall_state("anything"),
		HallProgressionEngine.HallState.LOCKED,
		"Null hall_tree should return LOCKED")
	_assert_true(not engine.is_wing_accessible("anything"),
		"Null hall_tree: is_wing_accessible should return false")
	_assert_eq(engine.get_available_halls().size(), 0,
		"Null hall_tree: get_available_halls should return empty")


func test_unknown_hall_id() -> void:
	var engine := _make_engine()
	_assert_eq(engine.get_hall_state("nonexistent_hall"),
		HallProgressionEngine.HallState.LOCKED,
		"Unknown hall ID should return LOCKED")


func test_wing_without_gate() -> void:
	var data := _make_test_data()
	# Remove gate from wing_2
	data["wings"][1]["gate"] = {}
	var engine := _make_engine_with_data(data)
	_assert_true(engine.is_wing_accessible("wing_2"),
		"Wing without gate should be accessible")
