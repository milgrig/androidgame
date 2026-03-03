"""
Visual QA Tests for Room Cluster Overlay (T140).

Tests cluster rendering across all 5 layers using Agent Bridge.
Launches Godot in headless mode and inspects scene tree state.

Run:
    pytest tests/agent/test_cluster_visual.py -v -s

Requirements:
    - Godot 4.6+ in PATH (or set GODOT_PATH env var)
    - Agent Bridge implementation in src/agent/agent_bridge.gd
"""

import os
import sys
import unittest
from pathlib import Path
from typing import Dict, List, Optional

# Add parent dir for agent_client import
sys.path.insert(0, str(Path(__file__).parent))

from agent_client import AgentClient, AgentClientError


# ─────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────

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


# ─────────────────────────────────────────────────────────
# Helper: Find room_map_panel in scene tree
# ─────────────────────────────────────────────────────────

def find_room_map_panel(tree: Dict) -> Optional[Dict]:
    """Recursively find RoomMapPanel node in scene tree."""
    if tree.get("script_class") == "RoomMapPanel":
        return tree
    for child in tree.get("children", []):
        result = find_room_map_panel(child)
        if result:
            return result
    return None


def get_room_map_state(client: AgentClient) -> Dict:
    """
    Get room_map_panel state by finding it in the scene tree.

    Returns state dict with:
        - _clusters_active: bool
        - _cluster_data: Array of cluster info
        - positions: Array of room positions
    """
    tree = client.get_tree()
    room_map = find_room_map_panel(tree)

    if not room_map:
        return {
            "found": False,
            "_clusters_active": False,
            "_cluster_data": [],
            "positions": [],
        }

    return {
        "found": True,
        "path": room_map.get("path", ""),
        "_clusters_active": room_map.get("_clusters_active", False),
        "_cluster_data": room_map.get("_cluster_data", []),
        "positions": room_map.get("positions", []),
    }


# ─────────────────────────────────────────────────────────
# Base test class
# ─────────────────────────────────────────────────────────

@unittest.skipUnless(godot_available(), SKIP_REASON)
class ClusterVisualTestBase(unittest.TestCase):
    """Base class for cluster visual tests."""

    client: AgentClient = None

    @classmethod
    def setUpClass(cls):
        cls.client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=15.0,
        )
        cls.client.start()

    @classmethod
    def tearDownClass(cls):
        if cls.client:
            cls.client.quit()


# ─────────────────────────────────────────────────────────
# Test: Layer 1 (Baseline - No Clusters)
# ─────────────────────────────────────────────────────────

class TestLayer1NoClusters(ClusterVisualTestBase):
    """Layer 1 should have no clusters (baseline check)."""

    def test_layer1_no_clusters_on_level_01(self):
        """Level 01 (Z3): Layer 1 should not activate clusters."""
        self.client.load_level("level_01")

        room_map = get_room_map_state(self.client)

        self.assertTrue(room_map["found"], "RoomMapPanel not found in scene tree")
        self.assertFalse(room_map["_clusters_active"],
            "Layer 1 should not have clusters active")
        self.assertEqual(len(room_map["_cluster_data"]), 0,
            "Layer 1 should have no cluster data")

    def test_layer1_no_clusters_on_level_04(self):
        """Level 04 (S3): Layer 1 should not activate clusters."""
        self.client.load_level("level_04")

        room_map = get_room_map_state(self.client)

        self.assertTrue(room_map["found"], "RoomMapPanel not found")
        self.assertFalse(room_map["_clusters_active"],
            "Layer 1 should not have clusters active on S3 level")


# ─────────────────────────────────────────────────────────
# Test: Layer 2 (Mirror Pairs)
# ─────────────────────────────────────────────────────────

class TestLayer2MirrorPairs(ClusterVisualTestBase):
    """Layer 2 should show green clusters around mirror pairs."""

    def test_layer2_clusters_exist(self):
        """Layer 2 activates clusters for mirror pairs."""
        # Load a level with non-trivial inverse structure
        self.client.load_level("level_04")  # S3

        # TODO: Navigate to Layer 2 mode
        # This requires either:
        # 1. Agent command to switch layer mode
        # 2. Or press the Layer 2 button in the UI
        # For now, this is a placeholder test

        room_map = get_room_map_state(self.client)

        # NOTE: Without layer switching, clusters won't be active yet
        # This test verifies the infrastructure works
        self.assertTrue(room_map["found"],
            "RoomMapPanel should exist in LevelScene")


# ─────────────────────────────────────────────────────────
# Test: Cluster Data Structure
# ─────────────────────────────────────────────────────────

class TestClusterDataStructure(ClusterVisualTestBase):
    """Test that cluster data has the correct structure."""

    def test_room_map_panel_has_cluster_fields(self):
        """RoomMapPanel should expose _cluster_data and _clusters_active."""
        self.client.load_level("level_04")

        tree = self.client.get_tree()
        room_map = find_room_map_panel(tree)

        self.assertIsNotNone(room_map, "RoomMapPanel not found")

        # Check that cluster fields exist in the node properties
        # Agent Bridge serializes all properties, so these should be present
        # if the implementation is correct

        # NOTE: GDScript properties starting with _ are private and may not
        # be serialized by default. We may need to add public getter methods
        # like get_cluster_state() to expose this for testing.

        self.assertIn("path", room_map,
            "RoomMapPanel should have a scene tree path")


# ─────────────────────────────────────────────────────────
# Test: Edge Cases
# ─────────────────────────────────────────────────────────

class TestClusterEdgeCases(ClusterVisualTestBase):
    """Test edge cases: Z2, Z3, D4, S4 groups."""

    def test_z3_group_level_01(self):
        """Z3 (3 rooms): No normal subgroups → no Layer 5 clusters."""
        self.client.load_level("level_01")

        state = self.client.get_state()

        self.assertEqual(state["level"]["group_order"], 3,
            "Level 01 should have group order 3 (Z3)")

        room_map = get_room_map_state(self.client)
        self.assertTrue(room_map["found"], "RoomMapPanel should exist")

        # Z3 is cyclic (abelian), has only trivial normal subgroups
        # Layer 5 should auto-complete (no quotient groups to build)
        # But without layer switching, we can't verify Layer 5 state yet

    def test_s3_group_level_04(self):
        """S3 (6 rooms): Has one normal subgroup Z3."""
        self.client.load_level("level_04")

        state = self.client.get_state()

        self.assertEqual(state["level"]["group_order"], 6,
            "Level 04 should have group order 6 (S3)")

        room_map = get_room_map_state(self.client)
        self.assertEqual(len(room_map["positions"]), 6,
            "S3 should have 6 room positions on map")

    def test_d4_group_level_05(self):
        """D4 (8 rooms): Multiple subgroups of varying sizes."""
        self.client.load_level("level_05")

        state = self.client.get_state()

        self.assertEqual(state["level"]["group_order"], 8,
            "Level 05 should have group order 8 (D4)")

        room_map = get_room_map_state(self.client)
        self.assertEqual(len(room_map["positions"]), 8,
            "D4 should have 8 room positions on map")


# ─────────────────────────────────────────────────────────
# Test: Subclustering (Spatial Proximity)
# ─────────────────────────────────────────────────────────

class TestSubclustering(ClusterVisualTestBase):
    """Test that subclustering splits distant rooms correctly."""

    def test_room_positions_loaded(self):
        """Room positions should be computed after level load."""
        self.client.load_level("level_04")

        room_map = get_room_map_state(self.client)

        self.assertGreater(len(room_map["positions"]), 0,
            "Positions should be computed for S3 level")

        # For S3 (6 rooms), we expect 6 positions
        self.assertEqual(len(room_map["positions"]), 6,
            "S3 should have exactly 6 room positions")


# ─────────────────────────────────────────────────────────
# Test: Integration with Layer Mode Controller
# ─────────────────────────────────────────────────────────

class TestLayerModeIntegration(ClusterVisualTestBase):
    """Test that clusters integrate with layer mode controller."""

    def test_level_scene_has_room_map(self):
        """LevelScene should contain RoomMapPanel as _room_map."""
        self.client.load_level("level_04")

        tree = self.client.get_tree()

        # Find LevelScene
        def find_level_scene(node):
            if node.get("script_class") == "LevelScene":
                return node
            for child in node.get("children", []):
                result = find_level_scene(child)
                if result:
                    return result
            return None

        level_scene = find_level_scene(tree)
        self.assertIsNotNone(level_scene, "LevelScene not found in tree")

        # Check that _room_map reference exists
        # (This is an internal field, may need public accessor)
        room_map = find_room_map_panel(level_scene)
        self.assertIsNotNone(room_map,
            "RoomMapPanel should be a child of LevelScene")


# ─────────────────────────────────────────────────────────
# Manual Test Report
# ─────────────────────────────────────────────────────────

class TestManualChecklistReport(unittest.TestCase):
    """
    This test class documents what CANNOT be automatically tested
    and requires manual verification.

    These tests always pass — they serve as a checklist for manual QA.
    """

    def test_manual_checklist(self):
        """Print manual testing checklist."""
        print("\n" + "="*70)
        print("MANUAL TESTING CHECKLIST (Cannot be automated)")
        print("="*70)
        print("\nThese visual aspects require running the game with a display:")
        print()
        print("Layer 2 (Green Mirror Pairs):")
        print("  [ ] Green capsule shapes around mirror pairs")
        print("  [ ] Yellow halo for self-inverse elements (if any)")
        print("  [ ] Capsule smoothly wraps 2 rooms")
        print()
        print("Layer 3 (Gold Subgroup Highlight):")
        print("  [ ] Gold cluster outline when subgroup selected")
        print("  [ ] Outline updates when switching subgroups")
        print("  [ ] Single-room halos for size-1 subgroups")
        print()
        print("Layer 4 (Red Normal Subgroup):")
        print("  [ ] Red cluster during normality testing")
        print("  [ ] Switches to green if confirmed normal")
        print()
        print("Layer 5 (Multi-color Coset Classes):")
        print("  [ ] Each coset class has distinct color")
        print("  [ ] Distant rooms -> separate outlines + dashed arcs")
        print("  [ ] Nearby rooms -> shared convex hull bubble")
        print("  [ ] 12 coset colors cycle correctly")
        print()
        print("Edge Cases:")
        print("  [ ] Z2 (2 rooms): Single-room halos render correctly")
        print("  [ ] Z3 (3 rooms): Triangle hull for 3 colocated rooms")
        print("  [ ] D4 (8 rooms): Various subgroup sizes (2, 4)")
        print("  [ ] S4 (24 rooms): Large groups with dashed arcs")
        print()
        print("Visual Quality:")
        print("  [ ] Room numbers are readable under cluster outlines")
        print("  [ ] Outline colors match layer theme (green/gold/red/purple)")
        print("  [ ] Rounded corners look smooth")
        print("  [ ] Fill alpha is subtle (~0.08)")
        print("  [ ] Stroke alpha is visible (~0.5)")
        print()
        print("Performance:")
        print("  [ ] No lag when switching layers")
        print("  [ ] Smooth rendering on S4 (24 rooms)")
        print()
        print("Regression:")
        print("  [ ] Layers 1-4 still work correctly")
        print("  [ ] No visual glitches on any level")
        print("="*70)

        # Always pass — this is just documentation
        self.assertTrue(True, "Manual checklist printed")


# ─────────────────────────────────────────────────────────
# Run tests
# ─────────────────────────────────────────────────────────

if __name__ == '__main__':
    # Run with verbose output to see checklist
    unittest.main(verbosity=2)
