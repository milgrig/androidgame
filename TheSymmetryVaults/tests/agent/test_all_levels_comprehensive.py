"""
Comprehensive runtime test for all 12 levels of Act 1 through Agent Bridge.

This test validates:
1. All level metadata (crystals, edges, group)
2. All automorphisms can be found
3. Invalid permutations are rejected
4. Level completion works correctly
5. Keyring updates properly
6. HUD labels update correctly
7. Buttons (RESET, TEST PATTERN) work
8. Swap operations work correctly
9. Edge cases (duplicate submissions, invalid swaps, etc.)

Task: T021 - Full runtime QA of all 12 Act 1 levels

Usage:
    pytest tests/agent/test_all_levels_comprehensive.py -v -s
    pytest tests/agent/test_all_levels_comprehensive.py::TestLevel01 -v -s
"""

import os
import sys
import unittest
from pathlib import Path
from typing import Dict, List, Tuple

# Add parent dir for agent_client
sys.path.insert(0, str(Path(__file__).parent))

from agent_client import AgentClient, AgentClientError


# ═══════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════

GODOT_PATH = os.environ.get("GODOT_PATH", "godot")
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

def godot_available() -> bool:
    """Check if Godot binary is accessible."""
    import subprocess
    try:
        result = subprocess.run(
            [GODOT_PATH, "--version"],
            capture_output=True, timeout=10
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False

SKIP_REASON = "Godot binary not found (set GODOT_PATH env var)"


# ═══════════════════════════════════════════════════════════
# Level Definitions
# ═══════════════════════════════════════════════════════════

LEVEL_SPECS = {
    "level_01": {
        "id": "act1_level01",
        "title": "Треугольный зал",
        "group": "Z3",
        "group_order": 3,
        "num_crystals": 3,
        "num_edges": 3,
        "automorphisms": [
            [0, 1, 2],  # identity
            [1, 2, 0],  # rotation 120°
            [2, 0, 1],  # rotation 240°
        ],
        "invalid_perms": [
            [1, 0, 2],  # transposition - not in Z3
            [0, 2, 1],  # another transposition
        ],
        "crystal_colors": ["red", "red", "red"],
    },
    "level_02": {
        "id": "act1_level02",
        "title": "Направленный поток",
        "group": "Z3",
        "group_order": 3,
        "num_crystals": 3,
        "num_edges": 3,
        "automorphisms": [
            [0, 1, 2],  # identity
            [1, 2, 0],  # rotation 120°
            [2, 0, 1],  # rotation 240°
        ],
        "invalid_perms": [
            [1, 0, 2],  # breaks directed edges
        ],
        "crystal_colors": ["blue", "blue", "blue"],
    },
    "level_03": {
        "id": "act1_level03",
        "title": "Цвет имеет значение",
        "group": "Z2",
        "group_order": 2,
        "num_crystals": 3,
        "num_edges": 3,
        "automorphisms": [
            [0, 1, 2],  # identity
            [0, 2, 1],  # swap green crystals
        ],
        "invalid_perms": [
            [1, 0, 2],  # red crystal moves - breaks color constraint
            [1, 2, 0],  # rotation - breaks colors
        ],
        "crystal_colors": ["red", "green", "green"],
    },
    "level_04": {
        "id": "act1_level04",
        "title": "Квадратная комната",
        "group": "D4",
        "group_order": 8,
        "num_crystals": 4,
        "num_edges": 4,
        "automorphisms": [
            [0, 1, 2, 3],  # identity
            [1, 2, 3, 0],  # rotation 90°
            [2, 3, 0, 1],  # rotation 180°
            [3, 0, 1, 2],  # rotation 270°
            [0, 3, 2, 1],  # reflection vertical
            [2, 1, 0, 3],  # reflection horizontal
            [1, 0, 3, 2],  # reflection diagonal
            [3, 2, 1, 0],  # reflection diagonal
        ],
        "invalid_perms": [
            [1, 0, 2, 3],  # only swaps two - not a valid symmetry
        ],
        "crystal_colors": ["red", "red", "red", "red"],
    },
    "level_05": {
        "id": "act1_level05",
        "title": "Пентагональный узор",
        "group": "D5",
        "group_order": 10,
        "num_crystals": 5,
        "num_edges": 5,
        "automorphisms": [
            [0, 1, 2, 3, 4],  # identity
            [1, 2, 3, 4, 0],  # rotation 72°
            [2, 3, 4, 0, 1],  # rotation 144°
            [3, 4, 0, 1, 2],  # rotation 216°
            [4, 0, 1, 2, 3],  # rotation 288°
            [0, 4, 3, 2, 1],  # reflection
            [1, 0, 4, 3, 2],  # reflection
            [2, 1, 0, 4, 3],  # reflection
            [3, 2, 1, 0, 4],  # reflection
            [4, 3, 2, 1, 0],  # reflection
        ],
        "invalid_perms": [
            [1, 0, 2, 3, 4],  # breaks pentagon structure
        ],
        "crystal_colors": ["red", "red", "red", "red", "red"],
    },
    "level_06": {
        "id": "act1_level06",
        "title": "Звездные врата",
        "group": "D6",
        "group_order": 12,
        "num_crystals": 6,
        "num_edges": 6,
        "automorphisms": [
            [0, 1, 2, 3, 4, 5],  # identity
            [1, 2, 3, 4, 5, 0],  # rotation 60°
            [2, 3, 4, 5, 0, 1],  # rotation 120°
            [3, 4, 5, 0, 1, 2],  # rotation 180°
            [4, 5, 0, 1, 2, 3],  # rotation 240°
            [5, 0, 1, 2, 3, 4],  # rotation 300°
            [0, 5, 4, 3, 2, 1],  # reflections...
            [1, 0, 5, 4, 3, 2],
            [2, 1, 0, 5, 4, 3],
            [3, 2, 1, 0, 5, 4],
            [4, 3, 2, 1, 0, 5],
            [5, 4, 3, 2, 1, 0],
        ],
        "invalid_perms": [
            [1, 0, 2, 3, 4, 5],  # breaks structure
        ],
        "crystal_colors": ["red", "red", "red", "red", "red", "red"],
    },
    "level_07": {
        "id": "act1_level07",
        "title": "Двойная ось",
        "group": "V4",
        "group_order": 4,
        "num_crystals": 4,
        "num_edges": 4,
        "automorphisms": [
            [0, 1, 2, 3],  # identity
            [1, 0, 3, 2],  # swap pairs
            [2, 3, 0, 1],  # swap pairs
            [3, 2, 1, 0],  # swap pairs
        ],
        "invalid_perms": [
            [1, 2, 3, 0],  # cyclic - not in Klein-4
        ],
        "crystal_colors": ["red", "red", "blue", "blue"],
    },
    "level_08": {
        "id": "act1_level08",
        "title": "Центральная звезда",
        "group": "S4",
        "group_order": 24,
        "num_crystals": 4,
        "num_edges": 6,  # complete graph K4
        # S4 has 24 automorphisms - testing a subset
        "automorphisms": [
            [0, 1, 2, 3],  # identity
            [0, 1, 3, 2],  # (2 3)
            [0, 2, 1, 3],  # (1 2)
            [0, 2, 3, 1],  # (1 2 3)
            [0, 3, 1, 2],  # (1 3 2)
            [0, 3, 2, 1],  # (1 3)
            [1, 0, 2, 3],  # (0 1)
            [1, 0, 3, 2],  # (0 1)(2 3)
            # ... many more, but testing subset for feasibility
        ],
        "invalid_perms": [],  # Any permutation is valid in S4
        "crystal_colors": ["red", "red", "red", "red"],
    },
    "level_09": {
        "id": "act1_level09",
        "title": "Триплет",
        "group": "S3",
        "group_order": 6,
        "num_crystals": 3,
        "num_edges": 3,
        "automorphisms": [
            [0, 1, 2],  # identity
            [0, 2, 1],  # (1 2)
            [1, 0, 2],  # (0 1)
            [1, 2, 0],  # (0 1 2)
            [2, 0, 1],  # (0 2 1)
            [2, 1, 0],  # (0 2)
        ],
        "invalid_perms": [],  # All permutations valid in S3
        "crystal_colors": ["red", "blue", "green"],
    },
    "level_10": {
        "id": "act1_level10",
        "title": "Биекция",
        "group": "S2",
        "group_order": 2,
        "num_crystals": 2,
        "num_edges": 1,
        "automorphisms": [
            [0, 1],  # identity
            [1, 0],  # swap
        ],
        "invalid_perms": [],  # Only 2 permutations exist
        "crystal_colors": ["red", "blue"],
    },
    "level_11": {
        "id": "act1_level11",
        "title": "Единица",
        "group": "trivial",
        "group_order": 1,
        "num_crystals": 1,
        "num_edges": 0,
        "automorphisms": [
            [0],  # only identity
        ],
        "invalid_perms": [],  # Only one permutation exists
        "crystal_colors": ["red"],
    },
    "level_12": {
        "id": "act1_level12",
        "title": "Хаос",
        "group": "S5",
        "group_order": 120,
        "num_crystals": 5,
        "num_edges": 10,  # complete graph K5
        # S5 has 120 automorphisms - testing subset only
        "automorphisms": [
            [0, 1, 2, 3, 4],  # identity
            [0, 1, 2, 4, 3],  # (3 4)
            [0, 1, 3, 2, 4],  # (2 3)
            [1, 0, 2, 3, 4],  # (0 1)
            # Testing subset - finding all 120 would be impractical
        ],
        "invalid_perms": [],  # All permutations valid in S5
        "crystal_colors": ["red", "red", "red", "red", "red"],
    },
}


# ═══════════════════════════════════════════════════════════
# Base Test Class
# ═══════════════════════════════════════════════════════════

@unittest.skipUnless(godot_available(), SKIP_REASON)
class LevelTestBase(unittest.TestCase):
    """Base class for comprehensive level testing."""

    client: AgentClient = None
    level_id: str = None
    spec: Dict = None

    @classmethod
    def setUpClass(cls):
        """Start Godot client and load the level."""
        cls.spec = LEVEL_SPECS.get(cls.level_id)
        if not cls.spec:
            raise ValueError(f"No spec found for {cls.level_id}")

        cls.client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=15.0,
        )
        print(f"\n{'═' * 60}")
        print(f"Testing {cls.level_id}: {cls.spec['title']}")
        print(f"Group: {cls.spec['group']} (order {cls.spec['group_order']})")
        print(f"{'═' * 60}")
        cls.client.start(level_id=cls.level_id)

    @classmethod
    def tearDownClass(cls):
        """Clean up Godot client."""
        if cls.client:
            cls.client.quit()

    def setUp(self):
        """Reset level before each test."""
        self.client.load_level(self.level_id)

    # ───────────────────────────────────────────────────────
    # 1. LEVEL METADATA VALIDATION
    # ───────────────────────────────────────────────────────

    def test_01_level_metadata(self):
        """Verify level ID, title, and group information."""
        state = self.client.get_state()
        level = state["level"]

        self.assertEqual(level["id"], self.spec["id"],
                        f"Level ID mismatch")
        self.assertEqual(level["title"], self.spec["title"],
                        f"Level title mismatch")
        self.assertEqual(level.get("group_name", level.get("group")), self.spec["group"],
                        f"Group name mismatch")

    def test_02_crystal_count(self):
        """Verify correct number of crystals."""
        state = self.client.get_state()
        self.assertEqual(len(state["crystals"]), self.spec["num_crystals"],
                        f"Expected {self.spec['num_crystals']} crystals")

    def test_03_edge_count(self):
        """Verify correct number of edges."""
        state = self.client.get_state()
        self.assertEqual(len(state["edges"]), self.spec["num_edges"],
                        f"Expected {self.spec['num_edges']} edges")

    def test_04_crystal_colors(self):
        """Verify crystal colors match specification."""
        state = self.client.get_state()
        actual_colors = sorted([c["color"] for c in state["crystals"]])
        expected_colors = sorted(self.spec["crystal_colors"])
        self.assertEqual(actual_colors, expected_colors,
                        f"Crystal colors mismatch")

    def test_05_initial_arrangement(self):
        """Verify arrangement starts at identity."""
        state = self.client.get_state()
        n = self.spec["num_crystals"]
        expected = list(range(n))
        self.assertEqual(state["arrangement"], expected,
                        f"Initial arrangement should be identity")

    def test_06_total_symmetries(self):
        """Verify total symmetry count matches group order."""
        state = self.client.get_state()
        self.assertEqual(state["total_symmetries"], self.spec["group_order"],
                        f"Total symmetries should equal group order")

    # ───────────────────────────────────────────────────────
    # 2. AUTOMORPHISM VALIDATION
    # ───────────────────────────────────────────────────────

    def test_10_find_all_automorphisms(self):
        """Submit all valid automorphisms - each should be accepted."""
        found_count = 0
        for perm in self.spec["automorphisms"]:
            resp = self.client.submit_permutation(perm)
            events = resp.get("events", [])
            sym_events = [e for e in events if e["type"] == "symmetry_found"]

            if len(sym_events) == 0:
                # Check if already found
                state = self.client.get_state()
                keyring = state["keyring"]
                if perm == list(range(len(perm))):
                    # Identity should always be first
                    pass
                else:
                    self.fail(f"Valid automorphism {perm} not recognized as symmetry")
            else:
                self.assertEqual(len(sym_events), 1,
                                f"Expected exactly 1 symmetry_found for {perm}, got {len(sym_events)}")
                found_count += 1

        # Verify all symmetries were found
        state = self.client.get_state()
        self.assertEqual(state["keyring"]["found_count"], self.spec["group_order"],
                        f"Should have found all {self.spec['group_order']} symmetries")

    # ───────────────────────────────────────────────────────
    # 3. INVALID PERMUTATIONS
    # ───────────────────────────────────────────────────────

    def test_20_invalid_permutations_rejected(self):
        """Submit invalid permutations - should trigger invalid_attempt."""
        if not self.spec["invalid_perms"]:
            self.skipTest("No invalid permutations defined for this level")

        for perm in self.spec["invalid_perms"]:
            resp = self.client.submit_permutation(perm)
            events = resp.get("events", [])
            invalid_events = [e for e in events if e["type"] == "invalid_attempt"]
            self.assertGreaterEqual(len(invalid_events), 1,
                                   f"Invalid permutation {perm} should trigger invalid_attempt")

    # ───────────────────────────────────────────────────────
    # 4. LEVEL COMPLETION
    # ───────────────────────────────────────────────────────

    def test_30_level_completion(self):
        """Find all symmetries and verify level_completed event."""
        completed = False
        for perm in self.spec["automorphisms"]:
            resp = self.client.submit_permutation(perm)
            events = resp.get("events", [])
            complete_events = [e for e in events if e["type"] == "level_completed"]
            if complete_events:
                completed = True
                break

        self.assertTrue(completed, "level_completed event should fire after finding all symmetries")

    # ───────────────────────────────────────────────────────
    # 5. KEYRING VALIDATION
    # ───────────────────────────────────────────────────────

    def test_40_keyring_updates(self):
        """Verify keyring updates correctly as symmetries are found."""
        state = self.client.get_state()
        initial_found = state["keyring"]["found_count"]

        # Submit one valid automorphism (not identity)
        if len(self.spec["automorphisms"]) > 1:
            perm = self.spec["automorphisms"][1]
            self.client.submit_permutation(perm)

            state = self.client.get_state()
            new_found = state["keyring"]["found_count"]
            self.assertGreater(new_found, initial_found,
                             "Keyring found_count should increase")

    def test_41_keyring_completion(self):
        """Verify keyring shows complete=true after finding all symmetries."""
        # Find all symmetries
        for perm in self.spec["automorphisms"]:
            self.client.submit_permutation(perm)

        state = self.client.get_state()
        keyring = state["keyring"]
        self.assertTrue(keyring["complete"], "Keyring should be marked complete")
        self.assertEqual(keyring["found_count"], keyring["total"],
                        "Found count should equal total")

    # ───────────────────────────────────────────────────────
    # 6. HUD LABEL VALIDATION
    # ───────────────────────────────────────────────────────

    def test_50_hud_labels_exist(self):
        """Verify HUD labels are present in scene tree."""
        labels = self.client.find_labels()
        label_names = [l["name"] for l in labels]

        self.assertIn("TitleLabel", label_names, "TitleLabel should exist")
        self.assertIn("CounterLabel", label_names, "CounterLabel should exist")
        # StatusLabel may or may not exist depending on level

    def test_51_title_label_correct(self):
        """Verify TitleLabel shows correct level title."""
        labels = self.client.find_labels()
        title_label = next((l for l in labels if l["name"] == "TitleLabel"), None)
        if title_label:
            self.assertEqual(title_label["text"], self.spec["title"],
                           "TitleLabel should show level title")

    def test_52_counter_label_updates(self):
        """Verify CounterLabel updates as symmetries are found."""
        labels = self.client.find_labels()
        counter = next((l for l in labels if l["name"] == "CounterLabel"), None)
        if not counter:
            self.skipTest("CounterLabel not found")

        # Should start at 0
        self.assertIn("0", counter["text"], "Counter should start at 0")

        # Submit one symmetry
        if len(self.spec["automorphisms"]) > 1:
            self.client.submit_permutation(self.spec["automorphisms"][1])

            labels = self.client.find_labels()
            counter = next((l for l in labels if l["name"] == "CounterLabel"), None)
            # Counter should have increased
            self.assertNotIn("0 / ", counter["text"], "Counter should have updated")

    # ───────────────────────────────────────────────────────
    # 7. BUTTON FUNCTIONALITY
    # ───────────────────────────────────────────────────────

    def test_60_reset_button_exists(self):
        """Verify RESET button exists and is accessible."""
        buttons = self.client.find_buttons()
        reset_buttons = [b for b in buttons if "reset" in b.get("name", "").lower()]
        self.assertGreater(len(reset_buttons), 0, "RESET button should exist")

    def test_61_reset_button_works(self):
        """Verify RESET button resets arrangement to identity."""
        # Submit a permutation
        if len(self.spec["automorphisms"]) > 1:
            perm = self.spec["automorphisms"][1]
            self.client.submit_permutation(perm)

            # Press reset
            try:
                self.client.reset()
            except Exception as e:
                self.fail(f"Reset failed: {e}")

            # Verify arrangement is identity
            state = self.client.get_state()
            expected = list(range(self.spec["num_crystals"]))
            self.assertEqual(state["arrangement"], expected,
                           "Reset should restore identity arrangement")

    # ───────────────────────────────────────────────────────
    # 8. SWAP FUNCTIONALITY
    # ───────────────────────────────────────────────────────

    def test_70_swap_valid_crystals(self):
        """Verify swap() works between valid crystal IDs."""
        n = self.spec["num_crystals"]
        if n < 2:
            self.skipTest("Level has < 2 crystals, cannot test swap")

        resp = self.client.swap(0, 1)
        self.assertTrue(resp.get("ok", False), "Swap should succeed")

    def test_71_swap_same_crystal_noop(self):
        """Verify swapping crystal with itself is no-op."""
        resp = self.client._send_raw("swap", {"from": 0, "to": 0})
        self.assertTrue(resp.get("ok", False), "Swap same crystal should succeed")
        self.assertEqual(resp.get("data", {}).get("result"), "no_op",
                        "Swapping same crystal should be no_op")

    def test_72_swap_invalid_crystal_errors(self):
        """Verify swapping non-existent crystal returns error."""
        n = self.spec["num_crystals"]
        resp = self.client._send_raw("swap", {"from": 0, "to": n + 10})
        self.assertFalse(resp.get("ok", False),
                        "Swap with invalid crystal ID should fail")

    # ───────────────────────────────────────────────────────
    # 9. EDGE CASES
    # ───────────────────────────────────────────────────────

    def test_80_duplicate_submission(self):
        """Verify submitting same automorphism twice doesn't duplicate."""
        if len(self.spec["automorphisms"]) < 1:
            self.skipTest("No automorphisms to test")

        perm = self.spec["automorphisms"][0]

        # Submit first time
        resp1 = self.client.submit_permutation(perm)
        state1 = self.client.get_state()
        count1 = state1["keyring"]["found_count"]

        # Submit again
        resp2 = self.client.submit_permutation(perm)
        state2 = self.client.get_state()
        count2 = state2["keyring"]["found_count"]

        # Count should not increase
        self.assertEqual(count1, count2,
                        "Duplicate submission should not increase count")

    def test_81_load_nonexistent_level_errors(self):
        """Verify loading non-existent level returns error."""
        with self.assertRaises(AgentClientError) as ctx:
            self.client.load_level("nonexistent_level_999")
        self.assertEqual(ctx.exception.code, "NOT_FOUND",
                        "Loading non-existent level should return NOT_FOUND")


# ═══════════════════════════════════════════════════════════
# Individual Test Classes for Each Level
# ═══════════════════════════════════════════════════════════

class TestLevel01(LevelTestBase):
    level_id = "level_01"

class TestLevel02(LevelTestBase):
    level_id = "level_02"

class TestLevel03(LevelTestBase):
    level_id = "level_03"

class TestLevel04(LevelTestBase):
    level_id = "level_04"

class TestLevel05(LevelTestBase):
    level_id = "level_05"

class TestLevel06(LevelTestBase):
    level_id = "level_06"

class TestLevel07(LevelTestBase):
    level_id = "level_07"

class TestLevel08(LevelTestBase):
    level_id = "level_08"

class TestLevel09(LevelTestBase):
    level_id = "level_09"

class TestLevel10(LevelTestBase):
    level_id = "level_10"

class TestLevel11(LevelTestBase):
    level_id = "level_11"

class TestLevel12(LevelTestBase):
    level_id = "level_12"


# ═══════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════

if __name__ == "__main__":
    unittest.main(verbosity=2)
