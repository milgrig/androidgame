"""
Agent integration tests — AI agent plays through levels via AgentBridge.

These tests require Godot 4.6+ binary in PATH (or set GODOT_PATH env var).
They launch Godot in headless mode and communicate via the file protocol.

Run:
    pytest tests/agent/test_agent_plays.py -v

Skip if no Godot:
    pytest tests/agent/test_agent_plays.py -v -k "not godot"
"""

import os
import sys
import unittest
from pathlib import Path

# Add parent dir so we can import agent_client
sys.path.insert(0, str(Path(__file__).parent))

from agent_client import AgentClient, AgentClientError


# ─────────────────────────────────────────────────────────
# Skip decorator if Godot is not available
# ─────────────────────────────────────────────────────────

GODOT_PATH = os.environ.get("GODOT_PATH", "godot")
# TheSymmetryVaults root is 2 levels up from tests/agent/
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


# ─────────────────────────────────────────────────────────
# Base test class
# ─────────────────────────────────────────────────────────

@unittest.skipUnless(godot_available(), SKIP_REASON)
class AgentTestBase(unittest.TestCase):
    """Base class for agent tests. Manages Godot lifecycle."""

    client: AgentClient = None
    level_id: str = "level_01"

    @classmethod
    def setUpClass(cls):
        cls.client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=10.0,
        )
        cls.client.start(level_id=cls.level_id)

    @classmethod
    def tearDownClass(cls):
        if cls.client:
            cls.client.quit()


# ─────────────────────────────────────────────────────────
# Test: Agent sees the full scene tree (DOM)
# ─────────────────────────────────────────────────────────

class TestAgentSeesTree(AgentTestBase):
    """The agent can see every node in the scene — like browser DevTools."""

    level_id = "level_01"

    def test_get_tree_returns_root(self):
        tree = self.client.get_tree()
        self.assertIn("name", tree)
        self.assertIn("children", tree)

    def test_tree_contains_level_scene(self):
        tree = self.client.get_tree()
        # Find LevelScene somewhere in the tree
        level_scenes = []
        self._find_by_script(tree, "level_scene", level_scenes)
        self.assertGreaterEqual(len(level_scenes), 1,
            "LevelScene not found in tree")

    def test_tree_contains_crystals(self):
        crystals = self.client.find_crystals()
        self.assertEqual(len(crystals), 3,
            "Level 1 should have 3 crystals")

    def test_crystals_have_properties(self):
        crystals = self.client.find_crystals()
        for crystal in crystals:
            self.assertIn("crystal_id", crystal)
            self.assertIn("color", crystal)
            self.assertIn("label", crystal)
            self.assertIn("draggable", crystal)
            self.assertIn("position", crystal)
            self.assertIn("actions", crystal)

    def test_tree_contains_hud_labels(self):
        labels = self.client.find_labels()
        label_names = [l["name"] for l in labels]
        self.assertIn("TitleLabel", label_names)
        self.assertIn("CounterLabel", label_names)

    def test_title_label_shows_level_name(self):
        labels = self.client.find_labels()
        title = next(l for l in labels if l["name"] == "TitleLabel")
        self.assertEqual(title["text"], "The Triangle Vault")

    def test_counter_label_shows_zero(self):
        labels = self.client.find_labels()
        counter = next(l for l in labels if l["name"] == "CounterLabel")
        self.assertIn("0 / 3", counter["text"])

    def test_new_button_auto_discovered(self):
        """If a button exists in the tree, list_actions shows it."""
        actions = self.client.list_actions()
        # At minimum, swap and submit_permutation should be available
        action_types = [a["action"] for a in actions]
        self.assertIn("swap", action_types)
        self.assertIn("submit_permutation", action_types)

    def _find_by_script(self, node, script_name, result):
        if script_name in node.get("script_class", "").lower():
            result.append(node)
        for child in node.get("children", []):
            self._find_by_script(child, script_name, result)


# ─────────────────────────────────────────────────────────
# Test: Agent reads game state
# ─────────────────────────────────────────────────────────

class TestAgentReadsState(AgentTestBase):
    """Agent can query structured game state."""

    level_id = "level_01"

    def test_state_has_level_info(self):
        state = self.client.get_state()
        self.assertEqual(state["level"]["id"], "level_01")
        self.assertEqual(state["level"]["title"], "The Triangle Vault")

    def test_state_has_crystals(self):
        state = self.client.get_state()
        self.assertEqual(len(state["crystals"]), 3)
        colors = [c["color"] for c in state["crystals"]]
        self.assertTrue(all(c == "red" for c in colors),
            "Level 1: all crystals should be red")

    def test_state_has_edges(self):
        state = self.client.get_state()
        self.assertEqual(len(state["edges"]), 3)
        types = [e["type"] for e in state["edges"]]
        self.assertTrue(all(t == "standard" for t in types),
            "Level 1: all edges should be standard")

    def test_state_has_keyring(self):
        state = self.client.get_state()
        self.assertEqual(state["keyring"]["found_count"], 0)
        self.assertEqual(state["keyring"]["total"], 3)
        self.assertFalse(state["keyring"]["complete"])

    def test_state_arrangement_is_identity(self):
        state = self.client.get_state()
        self.assertEqual(state["arrangement"], [0, 1, 2])

    def test_state_has_total_symmetries(self):
        state = self.client.get_state()
        self.assertEqual(state["total_symmetries"], 3)


# ─────────────────────────────────────────────────────────
# Test: Agent plays Level 1 (Z3 triangle)
# ─────────────────────────────────────────────────────────

class TestAgentPlaysLevel1(AgentTestBase):
    """Agent finds all symmetries and completes Level 1."""

    level_id = "level_01"

    def test_01_submit_identity(self):
        """Identity [0,1,2] should be a valid symmetry."""
        resp = self.client.submit_permutation([0, 1, 2])
        events = resp.get("events", [])
        sym_events = [e for e in events if e["type"] == "symmetry_found"]
        self.assertEqual(len(sym_events), 1,
            "Identity should be found as a symmetry")

    def test_02_submit_rotation(self):
        """Rotation [1,2,0] should be a valid symmetry."""
        resp = self.client.submit_permutation([1, 2, 0])
        events = resp.get("events", [])
        sym_events = [e for e in events if e["type"] == "symmetry_found"]
        self.assertEqual(len(sym_events), 1,
            "120° rotation should be found")

    def test_03_submit_rotation2_completes_level(self):
        """Rotation [2,0,1] should complete the level."""
        resp = self.client.submit_permutation([2, 0, 1])
        events = resp.get("events", [])

        sym_events = [e for e in events if e["type"] == "symmetry_found"]
        complete_events = [e for e in events if e["type"] == "level_completed"]

        self.assertEqual(len(sym_events), 1,
            "240° rotation should be found")
        self.assertEqual(len(complete_events), 1,
            "Level should be completed after finding all 3 symmetries")

    def test_04_keyring_complete_after_all_symmetries(self):
        """After finding all symmetries, keyring shows complete."""
        state = self.client.get_state()
        self.assertTrue(state["keyring"]["complete"])
        self.assertEqual(state["keyring"]["found_count"], 3)

    def test_05_hud_updates_after_completion(self):
        """HUD should show completion message."""
        labels = self.client.find_labels()
        counter = next(l for l in labels if l["name"] == "CounterLabel")
        self.assertIn("3 / 3", counter["text"])


# ─────────────────────────────────────────────────────────
# Test: Agent uses swap (like a real player)
# ─────────────────────────────────────────────────────────

class TestAgentSwaps(AgentTestBase):
    """Agent swaps crystals like a real player would."""

    level_id = "level_01"

    def test_swap_changes_arrangement(self):
        """Swapping 0↔1 changes the arrangement."""
        state_before = self.client.get_state()
        self.assertEqual(state_before["arrangement"], [0, 1, 2])

        resp = self.client.swap(0, 1)
        self.assertTrue(resp["ok"])

        # The swap creates transposition (0 1), which is NOT in Z3
        # So it should trigger invalid_attempt and reset
        events = resp.get("events", [])
        invalid = [e for e in events if e["type"] == "invalid_attempt"]
        self.assertEqual(len(invalid), 1,
            "Transposition (0 1) is not in Z3, should be invalid")

    def test_swap_invalid_crystal_returns_error(self):
        """Swapping with non-existent crystal ID should error."""
        resp = self.client._send_raw("swap", {"from": 0, "to": 99})
        self.assertFalse(resp["ok"])

    def test_swap_same_crystal_is_noop(self):
        """Swapping crystal with itself should be no-op."""
        resp = self.client._send_raw("swap", {"from": 0, "to": 0})
        # Should succeed but do nothing
        self.assertTrue(resp["ok"])
        self.assertEqual(resp["data"]["result"], "no_op")


# ─────────────────────────────────────────────────────────
# Test: Agent loads different levels
# ─────────────────────────────────────────────────────────

class TestAgentLevels(AgentTestBase):
    """Agent can list and load different levels."""

    level_id = "level_01"

    def test_list_levels(self):
        levels = self.client.list_levels()
        self.assertGreaterEqual(len(levels), 3,
            "Should have at least 3 levels in act1")
        ids = [l["id"] for l in levels]
        self.assertIn("level_01", ids)

    def test_load_level_03(self):
        """Load level 3 (Colors Matter — Z2)."""
        result = self.client.load_level("level_03")
        self.assertTrue(result["loaded"])

        state = self.client.get_state()
        self.assertEqual(state["level"]["title"], "Colors Matter")
        self.assertEqual(state["total_symmetries"], 2)

        # Check crystal colors: 1 red + 2 green
        colors = sorted([c["color"] for c in state["crystals"]])
        self.assertEqual(colors, ["green", "green", "red"])

    def test_load_nonexistent_level_errors(self):
        """Loading a non-existent level should return an error."""
        with self.assertRaises(AgentClientError) as ctx:
            self.client.load_level("nonexistent_level_999")
        self.assertEqual(ctx.exception.code, "NOT_FOUND")


# ─────────────────────────────────────────────────────────
# Test: Protocol self-description
# ─────────────────────────────────────────────────────────

class TestProtocolSelfDescription(AgentTestBase):
    """The protocol is fully self-describing — agent can discover everything."""

    level_id = "level_01"

    def test_hello_returns_commands(self):
        """hello lists all available commands."""
        hello = self.client.hello()
        self.assertIn("commands", hello)
        cmd_names = [c["cmd"] for c in hello["commands"]]
        self.assertIn("get_tree", cmd_names)
        self.assertIn("get_state", cmd_names)
        self.assertIn("swap", cmd_names)
        self.assertIn("press_button", cmd_names)

    def test_list_actions_includes_swap(self):
        """list_actions shows swap with available crystal IDs."""
        actions = self.client.list_actions()
        swap_action = next(a for a in actions if a["action"] == "swap")
        self.assertIn("available_ids", swap_action)
        self.assertEqual(sorted(swap_action["available_ids"]), [0, 1, 2])

    def test_unknown_command_returns_error(self):
        """Unknown commands get a clear error message."""
        resp = self.client._send_raw("nonexistent_command")
        self.assertFalse(resp["ok"])
        self.assertEqual(resp["code"], "UNKNOWN_COMMAND")


# ─────────────────────────────────────────────────────────
# Test: No duplicate events (T026 regression test)
# ─────────────────────────────────────────────────────────

class TestNoDuplicateEvents(AgentTestBase):
    """Verify that Agent Bridge does not send duplicate events.

    Regression test for T026: each event (symmetry_found, level_completed)
    must appear exactly once per command that triggers it.
    """

    level_id = "level_01"

    def test_identity_produces_exactly_one_symmetry_found(self):
        """submit_permutation for identity [0,1,2] must yield exactly 1 symmetry_found event."""
        resp = self.client.submit_permutation([0, 1, 2])
        events = resp.get("events", [])
        sym_events = [e for e in events if e["type"] == "symmetry_found"]
        self.assertEqual(len(sym_events), 1,
            f"Expected exactly 1 symmetry_found event, got {len(sym_events)}: {events}")

    def test_rotation_produces_exactly_one_symmetry_found(self):
        """submit_permutation for rotation [1,2,0] must yield exactly 1 symmetry_found event."""
        resp = self.client.submit_permutation([1, 2, 0])
        events = resp.get("events", [])
        sym_events = [e for e in events if e["type"] == "symmetry_found"]
        self.assertEqual(len(sym_events), 1,
            f"Expected exactly 1 symmetry_found event, got {len(sym_events)}: {events}")

    def test_final_symmetry_produces_one_found_and_one_completed(self):
        """Last symmetry [2,0,1] must produce exactly 1 symmetry_found + 1 level_completed."""
        resp = self.client.submit_permutation([2, 0, 1])
        events = resp.get("events", [])
        sym_events = [e for e in events if e["type"] == "symmetry_found"]
        complete_events = [e for e in events if e["type"] == "level_completed"]
        self.assertEqual(len(sym_events), 1,
            f"Expected exactly 1 symmetry_found event, got {len(sym_events)}: {events}")
        self.assertEqual(len(complete_events), 1,
            f"Expected exactly 1 level_completed event, got {len(complete_events)}: {events}")

    def test_no_stale_events_between_commands(self):
        """Reload level and verify no leftover events leak into the next command."""
        # Reload level to reset state
        self.client.load_level("level_01")

        # Submit identity — should get exactly 1 symmetry_found, no stale events
        resp = self.client.submit_permutation([0, 1, 2])
        events = resp.get("events", [])
        sym_events = [e for e in events if e["type"] == "symmetry_found"]
        self.assertEqual(len(sym_events), 1,
            f"After reload, expected exactly 1 symmetry_found, got {len(sym_events)}: {events}")

        # Submit rotation — should get exactly 1 symmetry_found, not 2
        resp2 = self.client.submit_permutation([1, 2, 0])
        events2 = resp2.get("events", [])
        sym_events2 = [e for e in events2 if e["type"] == "symmetry_found"]
        self.assertEqual(len(sym_events2), 1,
            f"Second submit should have exactly 1 symmetry_found, got {len(sym_events2)}: {events2}")


if __name__ == "__main__":
    unittest.main()
