"""
Unit tests for HallProgressionEngine — Python mirror of GDScript logic.
Validates progression engine: hall states, wing gates, unlock logic,
and resonance discovery without requiring the Godot engine.

Mirrors: src/core/hall_progression_engine.gd
Depends on: test_hall_tree_data.py (HallTreeData Python mirror)
"""
import unittest
from enum import IntEnum

# Reuse the Python mirror of HallTreeData from the sibling test module
from test_hall_tree_data import HallTreeData, WingData, GateData, ResonanceData


# === Python mirror of HallProgressionEngine ===

class HallState(IntEnum):
    LOCKED = 0
    AVAILABLE = 1
    COMPLETED = 2
    PERFECT = 3


class HallProgressionEngine:
    """Python mirror of hall_progression_engine.gd for testability."""

    def __init__(self):
        self.hall_tree: HallTreeData | None = None
        self._completed_levels: list[str] = []
        self._level_states: dict[str, dict] = {}

    def inject_state(self, completed: list[str], states: dict | None = None) -> None:
        self._completed_levels = list(completed)
        self._level_states = dict(states) if states else {}

    def _is_completed(self, hall_id: str) -> bool:
        return hall_id in self._completed_levels

    def _get_level_state(self, hall_id: str) -> dict:
        return self._level_states.get(hall_id, {})

    def _mark_completed(self, hall_id: str) -> None:
        if hall_id not in self._completed_levels:
            self._completed_levels.append(hall_id)

    # --- Public API ---

    def get_hall_state(self, hall_id: str) -> HallState:
        if self.hall_tree is None:
            return HallState.LOCKED

        if self._is_completed(hall_id):
            if self._has_perfection_seal(hall_id):
                return HallState.PERFECT
            return HallState.COMPLETED

        if self._is_hall_available(hall_id):
            return HallState.AVAILABLE

        return HallState.LOCKED

    def is_wing_accessible(self, wing_id: str) -> bool:
        if self.hall_tree is None:
            return False
        wing = self.hall_tree.get_wing(wing_id)
        if wing is None:
            return False
        return self._is_wing_accessible_internal(wing)

    def get_available_halls(self) -> list[str]:
        if self.hall_tree is None:
            return []
        result = []
        for wing in self.hall_tree.wings:
            for hall_id in wing.halls:
                state = self.get_hall_state(hall_id)
                if state == HallState.AVAILABLE:
                    result.append(hall_id)
        return result

    def get_wing_progress(self, wing_id: str) -> dict:
        if self.hall_tree is None:
            return {"completed": 0, "total": 0, "threshold": 0}
        wing = self.hall_tree.get_wing(wing_id)
        if wing is None:
            return {"completed": 0, "total": 0, "threshold": 0}
        completed = self._count_completed_in_wing(wing)
        threshold = wing.gate.required_halls if wing.gate else len(wing.halls)
        return {
            "completed": completed,
            "total": len(wing.halls),
            "threshold": threshold,
        }

    def complete_hall(self, hall_id: str) -> tuple[list[str], list[str], list]:
        """Complete a hall and return (unlocked_halls, unlocked_wings, discovered_resonances)."""
        if self.hall_tree is None:
            return ([], [], [])

        self._mark_completed(hall_id)

        unlocked_halls = []
        neighbors = self.hall_tree.get_hall_edges(hall_id)
        for neighbor_id in neighbors:
            if not self._is_completed(neighbor_id):
                if self._is_hall_available(neighbor_id):
                    unlocked_halls.append(neighbor_id)

        unlocked_wings = []
        wing = self.hall_tree.get_hall_wing(hall_id)
        if wing is not None:
            next_wing = self._get_next_wing(wing)
            if next_wing is not None and self._is_wing_accessible_internal(next_wing):
                unlocked_wings.append(next_wing.id)

        discovered = []
        hall_resonances = self.hall_tree.get_hall_resonances(hall_id)
        for resonance in hall_resonances:
            if self._is_resonance_discovered(resonance):
                discovered.append(resonance)

        return (unlocked_halls, unlocked_wings, discovered)

    def get_discovered_resonances(self) -> list:
        if self.hall_tree is None:
            return []
        return [r for r in self.hall_tree.resonances if self._is_resonance_discovered(r)]

    # --- Internal logic ---

    def _is_hall_available(self, hall_id: str) -> bool:
        wing = self.hall_tree.get_hall_wing(hall_id)
        if wing is None:
            return False
        if not self._is_wing_accessible_internal(wing):
            return False
        if hall_id in wing.start_halls:
            return True
        prereqs = self.hall_tree.get_hall_prereqs(hall_id)
        for prereq_id in prereqs:
            if self._is_completed(prereq_id):
                return True
        if not prereqs:
            return True
        return False

    def _is_wing_accessible_internal(self, wing: WingData) -> bool:
        if wing.order == 1:
            return True
        gate = wing.gate
        if gate is None:
            return True

        if gate.type == "threshold":
            source_wing_id = gate.required_from_wing
            if not source_wing_id:
                source_wing_id = self._get_previous_wing_id(wing)
            source_wing = self.hall_tree.get_wing(source_wing_id)
            if source_wing is None:
                return False
            completed_count = self._count_completed_in_wing(source_wing)
            return completed_count >= gate.required_halls

        elif gate.type == "all":
            source_wing_id = gate.required_from_wing
            if not source_wing_id:
                source_wing_id = self._get_previous_wing_id(wing)
            source_wing = self.hall_tree.get_wing(source_wing_id)
            if source_wing is None:
                return False
            return self._count_completed_in_wing(source_wing) >= len(source_wing.halls)

        elif gate.type == "specific":
            for required_id in gate.required_specific:
                if not self._is_completed(required_id):
                    return False
            return True

        return False

    def _count_completed_in_wing(self, wing: WingData) -> int:
        return sum(1 for h in wing.halls if self._is_completed(h))

    def _has_perfection_seal(self, hall_id: str) -> bool:
        state = self._get_level_state(hall_id)
        return state.get("hints_used", 0) == 0 and self._is_completed(hall_id)

    def _is_resonance_discovered(self, resonance) -> bool:
        if resonance.discovered_when == "both_completed":
            return all(self._is_completed(h) for h in resonance.halls)
        elif resonance.discovered_when == "wing_completed":
            for h in resonance.halls:
                wing = self.hall_tree.get_hall_wing(h)
                if wing is None:
                    return False
                if self._count_completed_in_wing(wing) < len(wing.halls):
                    return False
            return True
        return False

    def _get_previous_wing_id(self, wing: WingData) -> str:
        for w in self.hall_tree.wings:
            if w.order == wing.order - 1:
                return w.id
        return ""

    def _get_next_wing(self, wing: WingData) -> WingData | None:
        for w in self.hall_tree.wings:
            if w.order == wing.order + 1:
                return w
        return None


# === Test data helpers ===

def _make_test_data() -> dict:
    """Two-wing test data with threshold gate for thorough testing.
    Wing 2 uses act2_level13..16 with nonlinear graph (2 paths)."""
    return {
        "version": 2,
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
                    "required_from_wing": None,
                    "required_specific": [],
                    "message": "Open 8 halls to proceed",
                },
                "halls": [f"act1_level{i:02d}" for i in range(1, 13)],
                "start_halls": ["act1_level01"],
            },
            {
                "id": "wing_2",
                "name": "Inner Locks",
                "subtitle": "Subgroups",
                "act": 2,
                "order": 2,
                "gate": {
                    "type": "threshold",
                    "required_halls": 8,
                    "total_halls": 12,
                    "required_from_wing": "wing_1",
                    "required_specific": [],
                    "message": "Open 8 halls in the First Vault to enter the Inner Locks",
                },
                "halls": ["act2_level13", "act2_level14", "act2_level15", "act2_level16"],
                "start_halls": ["act2_level13"],
            },
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
            # Wing 2 edges (nonlinear: 2 paths from 13 to 16)
            {"from": "act2_level13", "to": "act2_level14", "type": "path"},
            {"from": "act2_level13", "to": "act2_level15", "type": "path"},
            {"from": "act2_level14", "to": "act2_level16", "type": "path"},
            {"from": "act2_level15", "to": "act2_level16", "type": "path"},
        ],
        "resonances": [
            {
                "halls": ["act1_level01", "act1_level11"],
                "type": "subgroup",
                "description": "Z3 is a subgroup of Z6",
                "discovered_when": "both_completed",
            },
            {
                "halls": ["act1_level05", "act1_level12"],
                "type": "isomorphic",
                "description": "Both share D4",
                "discovered_when": "both_completed",
            },
            {
                "halls": ["act1_level09", "act2_level13"],
                "type": "same_group_deeper",
                "description": "S3: the same group, now explored through its subgroups",
                "discovered_when": "both_completed",
            },
            {
                "halls": ["act1_level05", "act2_level14"],
                "type": "same_group_deeper",
                "description": "D4: the same symmetries, now revealing inner structure",
                "discovered_when": "both_completed",
            },
        ],
    }


def _make_engine(
    completed: list[str] | None = None,
    states: dict | None = None,
    data: dict | None = None,
) -> HallProgressionEngine:
    tree = HallTreeData()
    tree.parse(data if data is not None else _make_test_data())
    engine = HallProgressionEngine()
    engine.hall_tree = tree
    engine.inject_state(completed or [], states)
    return engine


# === Test Cases ===


class TestHallStateTransitions(unittest.TestCase):
    """Tests for LOCKED -> AVAILABLE -> COMPLETED -> PERFECT transitions."""

    def test_initial_nonstart_hall_locked(self):
        engine = _make_engine()
        self.assertEqual(engine.get_hall_state("act1_level02"), HallState.LOCKED)

    def test_start_hall_available(self):
        engine = _make_engine()
        self.assertEqual(engine.get_hall_state("act1_level01"), HallState.AVAILABLE)

    def test_locked_to_available(self):
        engine = _make_engine(completed=["act1_level01"])
        self.assertEqual(engine.get_hall_state("act1_level02"), HallState.AVAILABLE)

    def test_available_to_completed(self):
        # Provide hints_used > 0 so it's COMPLETED, not PERFECT
        states = {"act1_level02": {"hints_used": 1}}
        engine = _make_engine(completed=["act1_level01", "act1_level02"], states=states)
        self.assertEqual(engine.get_hall_state("act1_level02"), HallState.COMPLETED)

    def test_completed_with_perfection_seal(self):
        states = {"act1_level01": {"hints_used": 0, "time_spent_seconds": 60}}
        engine = _make_engine(completed=["act1_level01"], states=states)
        self.assertEqual(engine.get_hall_state("act1_level01"), HallState.PERFECT)

    def test_completed_without_perfection_seal(self):
        states = {"act1_level01": {"hints_used": 2, "time_spent_seconds": 120}}
        engine = _make_engine(completed=["act1_level01"], states=states)
        self.assertEqual(engine.get_hall_state("act1_level01"), HallState.COMPLETED)

    def test_full_state_chain(self):
        """Test the full LOCKED -> AVAILABLE -> COMPLETED chain for level02."""
        # Step 1: LOCKED
        e1 = _make_engine()
        self.assertEqual(e1.get_hall_state("act1_level02"), HallState.LOCKED)

        # Step 2: AVAILABLE (prereq level01 completed)
        e2 = _make_engine(completed=["act1_level01"])
        self.assertEqual(e2.get_hall_state("act1_level02"), HallState.AVAILABLE)

        # Step 3: COMPLETED (with hints_used > 0 to distinguish from PERFECT)
        states = {"act1_level02": {"hints_used": 1}}
        e3 = _make_engine(completed=["act1_level01", "act1_level02"], states=states)
        self.assertEqual(e3.get_hall_state("act1_level02"), HallState.COMPLETED)


class TestHallAvailability(unittest.TestCase):
    """Tests for hall unlock logic based on prerequisites."""

    def test_dependent_hall_unlocked_after_prereq(self):
        engine = _make_engine(completed=["act1_level01", "act1_level02"])
        self.assertEqual(engine.get_hall_state("act1_level04"), HallState.AVAILABLE)

    def test_dependent_hall_locked_without_prereq(self):
        engine = _make_engine(completed=["act1_level01"])
        self.assertEqual(engine.get_hall_state("act1_level04"), HallState.LOCKED)

    def test_multiple_prereqs_any_sufficient(self):
        """level11 has prereqs level09 and level10 — either one is enough."""
        completed = [
            "act1_level01", "act1_level02", "act1_level04",
            "act1_level05", "act1_level09",
        ]
        engine = _make_engine(completed=completed)
        self.assertEqual(engine.get_hall_state("act1_level11"), HallState.AVAILABLE)

    def test_multiple_prereqs_other_path(self):
        """level11 via level10 instead of level09."""
        completed = ["act1_level10"]
        engine = _make_engine(completed=completed)
        self.assertEqual(engine.get_hall_state("act1_level11"), HallState.AVAILABLE)

    def test_orphan_hall_available_in_accessible_wing(self):
        """Hall with no prereqs (not start) in accessible wing should be AVAILABLE."""
        engine = _make_engine()
        # level07 has no incoming edges in test data (no prereq)
        state = engine.get_hall_state("act1_level07")
        self.assertEqual(state, HallState.AVAILABLE)

    def test_hall_in_locked_wing_not_available(self):
        """Even start halls in a locked wing should be LOCKED."""
        engine = _make_engine()
        self.assertEqual(engine.get_hall_state("act2_level13"), HallState.LOCKED)


class TestThresholdGate(unittest.TestCase):
    """Tests for threshold gate type (N of M halls)."""

    def test_threshold_met(self):
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]  # 8 halls
        engine = _make_engine(completed=completed)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_threshold_not_met(self):
        completed = [f"act1_level{i:02d}" for i in range(1, 8)]  # 7 halls
        engine = _make_engine(completed=completed)
        self.assertFalse(engine.is_wing_accessible("wing_2"))

    def test_threshold_exact_boundary(self):
        """Exactly at threshold = 8."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]
        engine = _make_engine(completed=completed)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_threshold_8_of_12(self):
        """Classic scenario: complete non-sequential 8 out of 12."""
        completed = [
            "act1_level01", "act1_level03", "act1_level05",
            "act1_level07", "act1_level09", "act1_level10",
            "act1_level11", "act1_level12",
        ]
        engine = _make_engine(completed=completed)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_threshold_above(self):
        """More than threshold should also pass."""
        completed = [f"act1_level{i:02d}" for i in range(1, 11)]  # 10 halls
        engine = _make_engine(completed=completed)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_start_hall_available_after_gate_opens(self):
        """When threshold is met, start hall of next wing becomes AVAILABLE."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]  # 8 halls
        engine = _make_engine(completed=completed)
        self.assertEqual(engine.get_hall_state("act2_level13"), HallState.AVAILABLE)


class TestAllGate(unittest.TestCase):
    """Tests for 'all' gate type (100% required)."""

    def _make_all_gate_data(self) -> dict:
        data = _make_test_data()
        data["wings"][1]["gate"] = {
            "type": "all",
            "required_halls": 0,
            "total_halls": 12,
            "required_from_wing": "wing_1",
            "required_specific": [],
            "message": "Complete all halls in wing_1",
        }
        return data

    def test_all_gate_met(self):
        data = self._make_all_gate_data()
        completed = [f"act1_level{i:02d}" for i in range(1, 13)]
        engine = _make_engine(completed=completed, data=data)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_all_gate_not_met_one_missing(self):
        data = self._make_all_gate_data()
        completed = [f"act1_level{i:02d}" for i in range(1, 12)]  # 11/12
        engine = _make_engine(completed=completed, data=data)
        self.assertFalse(engine.is_wing_accessible("wing_2"))

    def test_all_gate_empty(self):
        data = self._make_all_gate_data()
        engine = _make_engine(data=data)
        self.assertFalse(engine.is_wing_accessible("wing_2"))


class TestSpecificGate(unittest.TestCase):
    """Tests for 'specific' gate type (named halls required)."""

    def _make_specific_gate_data(self) -> dict:
        data = _make_test_data()
        data["wings"][1]["gate"] = {
            "type": "specific",
            "required_halls": 0,
            "total_halls": 0,
            "required_from_wing": "",
            "required_specific": ["act1_level01", "act1_level09", "act1_level11"],
            "message": "Complete the key halls",
        }
        return data

    def test_specific_gate_met(self):
        data = self._make_specific_gate_data()
        completed = ["act1_level01", "act1_level09", "act1_level11"]
        engine = _make_engine(completed=completed, data=data)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_specific_gate_not_met(self):
        data = self._make_specific_gate_data()
        completed = ["act1_level01", "act1_level09"]  # missing level11
        engine = _make_engine(completed=completed, data=data)
        self.assertFalse(engine.is_wing_accessible("wing_2"))

    def test_specific_gate_with_extra_halls(self):
        """Having more halls completed than required should still pass."""
        data = self._make_specific_gate_data()
        completed = [f"act1_level{i:02d}" for i in range(1, 13)]
        engine = _make_engine(completed=completed, data=data)
        self.assertTrue(engine.is_wing_accessible("wing_2"))


class TestWingAccessibility(unittest.TestCase):
    """Tests for wing accessibility."""

    def test_first_wing_always_accessible(self):
        engine = _make_engine()
        self.assertTrue(engine.is_wing_accessible("wing_1"))

    def test_second_wing_locked_initially(self):
        engine = _make_engine()
        self.assertFalse(engine.is_wing_accessible("wing_2"))

    def test_unknown_wing(self):
        engine = _make_engine()
        self.assertFalse(engine.is_wing_accessible("nonexistent"))

    def test_wing_without_gate_accessible(self):
        data = _make_test_data()
        data["wings"][1]["gate"] = {}
        engine = _make_engine(data=data)
        self.assertTrue(engine.is_wing_accessible("wing_2"))


class TestGetAvailableHalls(unittest.TestCase):
    """Tests for get_available_halls()."""

    def test_initial_only_start_and_orphans(self):
        engine = _make_engine()
        available = engine.get_available_halls()
        self.assertIn("act1_level01", available)
        # wing_2 halls should not be available
        self.assertNotIn("act2_level13", available)

    def test_after_first_completion(self):
        engine = _make_engine(completed=["act1_level01"])
        available = engine.get_available_halls()
        self.assertIn("act1_level02", available)
        self.assertIn("act1_level03", available)
        # Completed halls are not in AVAILABLE list
        self.assertNotIn("act1_level01", available)

    def test_deep_chain(self):
        """Halls deep in the DAG become available as chain completes."""
        completed = ["act1_level01", "act1_level02", "act1_level04"]
        engine = _make_engine(completed=completed)
        available = engine.get_available_halls()
        self.assertIn("act1_level05", available)


class TestGetWingProgress(unittest.TestCase):
    """Tests for get_wing_progress()."""

    def test_empty_progress(self):
        engine = _make_engine()
        progress = engine.get_wing_progress("wing_1")
        self.assertEqual(progress["completed"], 0)
        self.assertEqual(progress["total"], 12)
        self.assertEqual(progress["threshold"], 8)

    def test_partial_progress(self):
        completed = ["act1_level01", "act1_level02", "act1_level03"]
        engine = _make_engine(completed=completed)
        progress = engine.get_wing_progress("wing_1")
        self.assertEqual(progress["completed"], 3)
        self.assertEqual(progress["total"], 12)

    def test_unknown_wing_progress(self):
        engine = _make_engine()
        progress = engine.get_wing_progress("nonexistent")
        self.assertEqual(progress["completed"], 0)
        self.assertEqual(progress["total"], 0)


class TestCompleteHall(unittest.TestCase):
    """Tests for complete_hall() — signals and state updates."""

    def test_complete_unlocks_neighbors(self):
        engine = _make_engine()
        unlocked_halls, _, _ = engine.complete_hall("act1_level01")
        self.assertIn("act1_level02", unlocked_halls)
        self.assertIn("act1_level03", unlocked_halls)

    def test_complete_unlocks_wing(self):
        completed = [f"act1_level{i:02d}" for i in range(1, 8)]  # 7 halls
        engine = _make_engine(completed=completed)
        _, unlocked_wings, _ = engine.complete_hall("act1_level08")  # 8th hall
        self.assertIn("wing_2", unlocked_wings)

    def test_complete_does_not_unlock_wing_prematurely(self):
        completed = [f"act1_level{i:02d}" for i in range(1, 7)]  # 6 halls
        engine = _make_engine(completed=completed)
        _, unlocked_wings, _ = engine.complete_hall("act1_level07")  # 7th hall, threshold is 8
        self.assertNotIn("wing_2", unlocked_wings)

    def test_complete_marks_hall_completed(self):
        # Without level_states, a completed hall defaults to PERFECT (0 hints)
        engine = _make_engine()
        engine.complete_hall("act1_level01")
        self.assertEqual(engine.get_hall_state("act1_level01"), HallState.PERFECT)

    def test_complete_marks_hall_completed_with_hints(self):
        states = {"act1_level01": {"hints_used": 3}}
        engine = _make_engine(states=states)
        engine.complete_hall("act1_level01")
        self.assertEqual(engine.get_hall_state("act1_level01"), HallState.COMPLETED)

    def test_complete_discovers_resonance(self):
        completed = ["act1_level01"]
        engine = _make_engine(completed=completed)
        _, _, resonances = engine.complete_hall("act1_level11")
        found = any(
            "act1_level01" in r.halls and "act1_level11" in r.halls
            for r in resonances
        )
        self.assertTrue(found, "Should discover resonance linking level01 and level11")


class TestResonances(unittest.TestCase):
    """Tests for resonance discovery."""

    def test_not_discovered_single_hall(self):
        engine = _make_engine(completed=["act1_level01"])
        discovered = engine.get_discovered_resonances()
        self.assertEqual(len([r for r in discovered
                              if "act1_level01" in r.halls and "act1_level11" in r.halls]), 0)

    def test_discovered_both_completed(self):
        engine = _make_engine(completed=["act1_level01", "act1_level11"])
        discovered = engine.get_discovered_resonances()
        found = any("act1_level01" in r.halls and "act1_level11" in r.halls
                     for r in discovered)
        self.assertTrue(found)

    def test_multiple_resonances(self):
        completed = [
            "act1_level01", "act1_level11",  # resonance 1
            "act1_level05", "act1_level12",  # resonance 2
        ]
        engine = _make_engine(completed=completed)
        discovered = engine.get_discovered_resonances()
        self.assertEqual(len(discovered), 2)

    def test_no_resonances_nothing_completed(self):
        engine = _make_engine()
        discovered = engine.get_discovered_resonances()
        self.assertEqual(len(discovered), 0)


class TestEdgeCases(unittest.TestCase):
    """Edge cases and error handling."""

    def test_null_hall_tree_state(self):
        engine = HallProgressionEngine()
        engine.inject_state([])
        self.assertEqual(engine.get_hall_state("anything"), HallState.LOCKED)

    def test_null_hall_tree_wing_accessible(self):
        engine = HallProgressionEngine()
        engine.inject_state([])
        self.assertFalse(engine.is_wing_accessible("anything"))

    def test_null_hall_tree_available_halls(self):
        engine = HallProgressionEngine()
        engine.inject_state([])
        self.assertEqual(engine.get_available_halls(), [])

    def test_null_hall_tree_complete_hall(self):
        engine = HallProgressionEngine()
        engine.inject_state([])
        # Should not crash
        result = engine.complete_hall("anything")
        self.assertEqual(result, ([], [], []))

    def test_unknown_hall_id(self):
        engine = _make_engine()
        self.assertEqual(engine.get_hall_state("nonexistent"), HallState.LOCKED)

    def test_wing_without_gate_is_accessible(self):
        data = _make_test_data()
        data["wings"][1]["gate"] = {}
        engine = _make_engine(data=data)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_idempotent_complete(self):
        """Completing the same hall twice should not cause issues."""
        states = {"act1_level01": {"hints_used": 1}}
        engine = _make_engine(states=states)
        engine.complete_hall("act1_level01")
        engine.complete_hall("act1_level01")
        self.assertEqual(engine.get_hall_state("act1_level01"), HallState.COMPLETED)
        # Should not have duplicates
        count = engine._completed_levels.count("act1_level01")
        self.assertEqual(count, 1)


class TestThreeWingProgression(unittest.TestCase):
    """Tests with 3 wings to verify chained gate logic."""

    def _make_three_wing_data(self) -> dict:
        return {
            "version": 1,
            "wings": [
                {
                    "id": "wing_1",
                    "name": "First",
                    "subtitle": "",
                    "act": 1,
                    "order": 1,
                    "gate": None,
                    "halls": ["h1", "h2", "h3"],
                    "start_halls": ["h1"],
                },
                {
                    "id": "wing_2",
                    "name": "Second",
                    "subtitle": "",
                    "act": 2,
                    "order": 2,
                    "gate": {
                        "type": "threshold",
                        "required_halls": 2,
                        "total_halls": 3,
                        "required_from_wing": "wing_1",
                        "required_specific": [],
                        "message": "Need 2",
                    },
                    "halls": ["h4", "h5"],
                    "start_halls": ["h4"],
                },
                {
                    "id": "wing_3",
                    "name": "Third",
                    "subtitle": "",
                    "act": 3,
                    "order": 3,
                    "gate": {
                        "type": "all",
                        "required_halls": 0,
                        "total_halls": 2,
                        "required_from_wing": "wing_2",
                        "required_specific": [],
                        "message": "Complete all",
                    },
                    "halls": ["h6"],
                    "start_halls": ["h6"],
                },
            ],
            "edges": [
                {"from": "h1", "to": "h2", "type": "path"},
                {"from": "h2", "to": "h3", "type": "path"},
                {"from": "h4", "to": "h5", "type": "path"},
            ],
            "resonances": [],
        }

    def test_wing3_locked_when_wing2_incomplete(self):
        data = self._make_three_wing_data()
        completed = ["h1", "h2", "h4"]  # wing_2 threshold met, but wing_2 not all done
        engine = _make_engine(completed=completed, data=data)
        self.assertTrue(engine.is_wing_accessible("wing_2"))
        self.assertFalse(engine.is_wing_accessible("wing_3"))

    def test_wing3_unlocked_when_wing2_all_complete(self):
        data = self._make_three_wing_data()
        completed = ["h1", "h2", "h4", "h5"]
        engine = _make_engine(completed=completed, data=data)
        self.assertTrue(engine.is_wing_accessible("wing_3"))

    def test_chained_hall_availability(self):
        """h6 (wing_3 start) only available when wing_3 gate satisfied."""
        data = self._make_three_wing_data()
        # Wing 2 not fully complete
        engine1 = _make_engine(completed=["h1", "h2", "h4"], data=data)
        self.assertEqual(engine1.get_hall_state("h6"), HallState.LOCKED)

        # Wing 2 fully complete
        engine2 = _make_engine(completed=["h1", "h2", "h4", "h5"], data=data)
        self.assertEqual(engine2.get_hall_state("h6"), HallState.AVAILABLE)


class TestWing2Progression(unittest.TestCase):
    """Tests for Wing 2 (Act 2) progression with halls 13-16."""

    def test_wing2_start_locked_initially(self):
        """act2_level13 should be LOCKED until wing_1 threshold is met."""
        engine = _make_engine()
        self.assertEqual(engine.get_hall_state("act2_level13"), HallState.LOCKED)

    def test_wing2_start_available_after_threshold(self):
        """act2_level13 becomes AVAILABLE when 8 wing_1 halls completed."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]  # 8 halls
        engine = _make_engine(completed=completed)
        self.assertEqual(engine.get_hall_state("act2_level13"), HallState.AVAILABLE)

    def test_wing2_nonstart_halls_locked_before_threshold(self):
        """All wing_2 halls are LOCKED when wing_1 threshold not met."""
        engine = _make_engine()
        for h in ["act2_level13", "act2_level14", "act2_level15", "act2_level16"]:
            self.assertEqual(engine.get_hall_state(h), HallState.LOCKED,
                             f"{h} should be LOCKED")

    def test_wing2_nonstart_halls_locked_even_after_gate(self):
        """Non-start halls in wing_2 remain LOCKED until prereqs met."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]  # gate open
        engine = _make_engine(completed=completed)
        # act2_level14 requires act2_level13 completion
        self.assertEqual(engine.get_hall_state("act2_level14"), HallState.LOCKED)
        self.assertEqual(engine.get_hall_state("act2_level15"), HallState.LOCKED)
        self.assertEqual(engine.get_hall_state("act2_level16"), HallState.LOCKED)

    def test_wing2_path_a(self):
        """Path A: 13 -> 14 -> 16."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]  # gate open
        completed.append("act2_level13")
        engine = _make_engine(completed=completed)
        self.assertEqual(engine.get_hall_state("act2_level14"), HallState.AVAILABLE)
        self.assertEqual(engine.get_hall_state("act2_level15"), HallState.AVAILABLE)
        self.assertEqual(engine.get_hall_state("act2_level16"), HallState.LOCKED)

    def test_wing2_path_b(self):
        """Path B: 13 -> 15 -> 16."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]
        completed.extend(["act2_level13", "act2_level15"])
        engine = _make_engine(completed=completed)
        self.assertEqual(engine.get_hall_state("act2_level16"), HallState.AVAILABLE)

    def test_wing2_convergent_paths(self):
        """Both paths converge: completing 14 alone is enough for 16."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]
        completed.extend(["act2_level13", "act2_level14"])
        engine = _make_engine(completed=completed)
        self.assertEqual(engine.get_hall_state("act2_level16"), HallState.AVAILABLE)

    def test_wing2_progress(self):
        """get_wing_progress for wing_2."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]
        completed.extend(["act2_level13", "act2_level14"])
        engine = _make_engine(completed=completed)
        progress = engine.get_wing_progress("wing_2")
        self.assertEqual(progress["completed"], 2)
        self.assertEqual(progress["total"], 4)

    def test_wing2_complete_all_halls(self):
        """All wing_2 halls can be completed."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]
        completed.extend(["act2_level13", "act2_level14", "act2_level15", "act2_level16"])
        engine = _make_engine(completed=completed)
        for h in ["act2_level13", "act2_level14", "act2_level15", "act2_level16"]:
            state = engine.get_hall_state(h)
            self.assertIn(state, [HallState.COMPLETED, HallState.PERFECT],
                          f"{h} should be COMPLETED or PERFECT")


class TestWing2Gate(unittest.TestCase):
    """Dedicated tests for the Wing 2 threshold gate."""

    def test_gate_requires_8_halls(self):
        """Wing 2 gate requires exactly 8 halls from wing_1."""
        # 7 halls: not enough
        completed_7 = [f"act1_level{i:02d}" for i in range(1, 8)]
        engine7 = _make_engine(completed=completed_7)
        self.assertFalse(engine7.is_wing_accessible("wing_2"),
                         "7 halls should NOT open wing_2 (threshold=8)")

        # 8 halls: exactly enough
        completed_8 = [f"act1_level{i:02d}" for i in range(1, 9)]
        engine8 = _make_engine(completed=completed_8)
        self.assertTrue(engine8.is_wing_accessible("wing_2"),
                        "8 halls should open wing_2 (threshold=8)")

    def test_gate_non_sequential_8(self):
        """Non-sequential 8 halls from wing_1 still opens gate."""
        completed = [
            "act1_level01", "act1_level02", "act1_level05",
            "act1_level06", "act1_level08", "act1_level09",
            "act1_level11", "act1_level12",
        ]
        engine = _make_engine(completed=completed)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_gate_all_12_opens(self):
        """All 12 wing_1 halls completed obviously opens gate."""
        completed = [f"act1_level{i:02d}" for i in range(1, 13)]
        engine = _make_engine(completed=completed)
        self.assertTrue(engine.is_wing_accessible("wing_2"))

    def test_gate_zero_halls_locked(self):
        """Zero completed halls: wing_2 locked."""
        engine = _make_engine()
        self.assertFalse(engine.is_wing_accessible("wing_2"))

    def test_gate_source_is_wing_1(self):
        """Gate checks wing_1, not wing_2 halls for threshold."""
        # Complete act2 halls (shouldn't count for wing_1 threshold)
        completed = ["act2_level13", "act2_level14", "act2_level15", "act2_level16"]
        engine = _make_engine(completed=completed)
        self.assertFalse(engine.is_wing_accessible("wing_2"),
                         "Completing wing_2 halls should not satisfy wing_1 threshold")

    def test_complete_8th_hall_triggers_wing_unlock(self):
        """Completing the 8th hall should signal wing_2 unlock."""
        completed = [f"act1_level{i:02d}" for i in range(1, 8)]  # 7 halls
        engine = _make_engine(completed=completed)
        _, unlocked_wings, _ = engine.complete_hall("act1_level08")
        self.assertIn("wing_2", unlocked_wings)

    def test_complete_7th_hall_no_wing_unlock(self):
        """Completing the 7th hall should NOT unlock wing_2."""
        completed = [f"act1_level{i:02d}" for i in range(1, 7)]  # 6 halls
        engine = _make_engine(completed=completed)
        _, unlocked_wings, _ = engine.complete_hall("act1_level07")
        self.assertNotIn("wing_2", unlocked_wings)


class TestCrossWingResonances(unittest.TestCase):
    """Tests for same_group_deeper resonances between Wing 1 and Wing 2."""

    def test_cross_wing_resonance_not_discovered_single(self):
        """Cross-wing resonance not discovered when only one hall is done."""
        completed = ["act1_level09"]
        engine = _make_engine(completed=completed)
        discovered = engine.get_discovered_resonances()
        sgd = [r for r in discovered if r.type == "same_group_deeper"]
        self.assertEqual(len(sgd), 0)

    def test_cross_wing_resonance_discovered_both(self):
        """Cross-wing resonance discovered when both halls completed."""
        completed = [f"act1_level{i:02d}" for i in range(1, 10)]  # gate open + level09
        completed.extend(["act2_level13"])  # act1_level09 + act2_level13
        engine = _make_engine(completed=completed)
        discovered = engine.get_discovered_resonances()
        sgd = [r for r in discovered if r.type == "same_group_deeper"]
        s3_found = any(
            "act1_level09" in r.halls and "act2_level13" in r.halls
            for r in sgd
        )
        self.assertTrue(s3_found, "S3 cross-wing resonance should be discovered")

    def test_cross_wing_resonance_d4(self):
        """D4 cross-wing resonance: act1_level05 <-> act2_level14."""
        completed = [f"act1_level{i:02d}" for i in range(1, 9)]
        completed.extend(["act2_level13", "act2_level14"])
        engine = _make_engine(completed=completed)
        discovered = engine.get_discovered_resonances()
        d4_found = any(
            r.type == "same_group_deeper"
            and "act1_level05" in r.halls
            and "act2_level14" in r.halls
            for r in discovered
        )
        self.assertTrue(d4_found, "D4 cross-wing resonance should be discovered")

    def test_complete_hall_emits_cross_wing_resonance(self):
        """Completing act2_level13 should emit the S3 resonance."""
        completed = [f"act1_level{i:02d}" for i in range(1, 10)]  # includes 09
        engine = _make_engine(completed=completed)
        _, _, resonances = engine.complete_hall("act2_level13")
        sgd = [r for r in resonances if r.type == "same_group_deeper"]
        self.assertTrue(len(sgd) > 0, "Should discover cross-wing resonance on completion")


if __name__ == "__main__":
    unittest.main()
