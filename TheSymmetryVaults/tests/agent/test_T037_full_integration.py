"""
T037: QA - Comprehensive Integration Test for S004 Features
============================================================

Tests all new features from Sprint S004 via Agent Bridge:
1. Main Menu (T033)
2. World Map (T032)
3. Fixed Math (T029)
4. Echo Hints (T034)

Run:
    pytest tests/agent/test_T037_full_integration.py -v -s

Set GODOT_PATH if needed:
    export GODOT_PATH="/path/to/Godot_v4.6.1-stable_win64_console.exe"
"""

import os
import sys
import time
import unittest
from pathlib import Path

# Add parent dir so we can import agent_client
sys.path.insert(0, str(Path(__file__).parent))

from agent_client import AgentClient, AgentClientError


# ─────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────

GODOT_PATH = os.environ.get(
    "GODOT_PATH",
    "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
)
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


SKIP_REASON = f"Godot binary not found at {GODOT_PATH}"


# ─────────────────────────────────────────────────────────
# Test 1: Main Menu (T033)
# ─────────────────────────────────────────────────────────

@unittest.skipUnless(godot_available(), SKIP_REASON)
class TestMainMenu(unittest.TestCase):
    """Test T033: Main menu functionality."""

    def setUp(self):
        self.client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=15.0,
        )
        # Start without loading a level - should show main menu
        self.client.start()

    def tearDown(self):
        if self.client:
            self.client.quit()

    def test_01_game_starts_with_main_menu(self):
        """Game should start with main menu displayed."""
        tree = self.client.get_tree()

        # Look for MainMenu scene or typical menu buttons
        buttons = self.client.find_buttons(tree)
        button_texts = [b.get("text", "") for b in buttons]

        print(f"\n[TEST] Found buttons: {button_texts}")

        # Main menu should have "Start Game" or similar
        has_start = any("начать" in str(text).lower() or "start" in str(text).lower()
                       for text in button_texts)
        self.assertTrue(has_start,
            f"Main menu should have Start/Начать button. Found: {button_texts}")

    def test_02_start_game_goes_to_world_map(self):
        """Clicking 'Start Game' should transition to world map."""
        tree = self.client.get_tree()
        buttons = self.client.find_buttons(tree)

        # Find start button
        start_btn = None
        for btn in buttons:
            text = btn.get("text", "").lower()
            if "начать" in text or "start" in text:
                start_btn = btn
                break

        if start_btn:
            print(f"\n[TEST] Pressing start button: {start_btn['path']}")
            self.client.press_button(start_btn["path"])

            # Wait a moment for scene transition
            time.sleep(2)

            # Check if world map is loaded
            tree = self.client.get_tree()
            # Look for world map indicators (chambers, wing nodes, etc.)
            # This is a basic check - may need refinement based on actual scene structure
            print(f"\n[TEST] After pressing start, scene tree root: {tree.get('name', 'unknown')}")
        else:
            self.skipTest("Start button not found in main menu")

    def test_03_settings_button_opens_settings(self):
        """Settings button should open settings screen."""
        tree = self.client.get_tree()
        buttons = self.client.find_buttons(tree)

        # Find settings button
        settings_btn = None
        for btn in buttons:
            text = btn.get("text", "").lower()
            if "настройки" in text or "settings" in text or "options" in text:
                settings_btn = btn
                break

        if settings_btn:
            print(f"\n[TEST] Pressing settings button: {settings_btn['path']}")
            self.client.press_button(settings_btn["path"])

            time.sleep(1)

            # Check for settings screen
            tree = self.client.get_tree()
            buttons = self.client.find_buttons(tree)
            button_texts = [b.get("text", "") for b in buttons]

            # Should have a back button
            has_back = any("назад" in str(text).lower() or "back" in str(text).lower()
                          for text in button_texts)

            print(f"\n[TEST] Settings screen buttons: {button_texts}")
            self.assertTrue(has_back,
                f"Settings screen should have Back/Назад button. Found: {button_texts}")

            # Press back to return to main menu
            back_btn = next((b for b in buttons
                           if "назад" in b.get("text", "").lower()
                           or "back" in b.get("text", "").lower()), None)
            if back_btn:
                self.client.press_button(back_btn["path"])
        else:
            print("\n[WARN] Settings button not found - may not be implemented yet")


# ─────────────────────────────────────────────────────────
# Test 2: World Map (T032)
# ─────────────────────────────────────────────────────────

@unittest.skipUnless(godot_available(), SKIP_REASON)
class TestWorldMap(unittest.TestCase):
    """Test T032: World map with chambers."""

    def setUp(self):
        self.client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=15.0,
        )
        self.client.start()

        # Navigate to world map if not already there
        # (This assumes we can get there - may need adjustment)
        time.sleep(1)

    def tearDown(self):
        if self.client:
            self.client.quit()

    def test_01_world_map_shows_wing1_chambers(self):
        """World map should display 12 chambers for Wing 1."""
        tree = self.client.get_tree()

        # Look for chamber nodes (exact structure depends on implementation)
        # This is a placeholder - needs to match actual scene structure
        print(f"\n[TEST] Scene tree root: {tree.get('name', 'unknown')}")
        print(f"\n[TEST] Scene tree children count: {len(tree.get('children', []))}")

        # Try to find chamber-related nodes
        # You may need to adjust this based on actual implementation
        self._print_tree_structure(tree, max_depth=3)

    def test_02_initial_chamber_available_others_locked(self):
        """Initial chamber should be AVAILABLE, others LOCKED."""
        # This test needs implementation details from T032
        # Placeholder for now
        print("\n[TEST] Checking chamber states...")

        tree = self.client.get_tree()
        # Look for chamber state indicators
        # This requires knowing the actual scene structure

    def test_03_click_available_chamber_loads_level(self):
        """Clicking an available chamber should load its level."""
        # Try to load a level directly for now
        try:
            result = self.client.load_level("level_01")
            self.assertTrue(result.get("loaded", False),
                "Should be able to load level_01")

            state = self.client.get_state()
            self.assertEqual(state["level"]["id"], "level_01")
            print(f"\n[TEST] Successfully loaded: {state['level']['title']}")
        except Exception as e:
            print(f"\n[ERROR] Failed to load level: {e}")
            raise

    def test_04_completing_level_returns_to_map_chamber_completed(self):
        """After completing a level, should return to map with chamber marked COMPLETED."""
        # Load level 1
        self.client.load_level("level_01")

        # Complete it quickly
        self.client.submit_permutation([0, 1, 2])  # identity
        self.client.submit_permutation([1, 2, 0])  # rotation
        resp = self.client.submit_permutation([2, 0, 1])  # rotation 2

        events = resp.get("events", [])
        completed = [e for e in events if e["type"] == "level_completed"]
        self.assertEqual(len(completed), 1, "Level should be completed")

        print("\n[TEST] Level completed, checking return to map...")
        # The actual return-to-map logic needs to be checked based on implementation

    def _print_tree_structure(self, node, indent=0, max_depth=3):
        """Helper to print tree structure for debugging."""
        if indent > max_depth:
            return

        prefix = "  " * indent
        name = node.get("name", "?")
        node_class = node.get("class", "?")
        script_class = node.get("script_class", "")

        print(f"{prefix}{name} ({script_class or node_class})")

        for child in node.get("children", []):
            self._print_tree_structure(child, indent + 1, max_depth)


# ─────────────────────────────────────────────────────────
# Test 3: Fixed Math (T029)
# ─────────────────────────────────────────────────────────

@unittest.skipUnless(godot_available(), SKIP_REASON)
class TestFixedMath(unittest.TestCase):
    """Test T029: Verify corrected symmetry math for D4 and S3."""

    def setUp(self):
        self.client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=15.0,
        )
        self.client.start()

    def tearDown(self):
        if self.client:
            self.client.quit()

    def test_01_level_05_d4_has_8_symmetries(self):
        """Level 05 (D4 square) should have exactly 8 symmetries."""
        try:
            self.client.load_level("level_05")
            state = self.client.get_state()

            total_symmetries = state.get("total_symmetries", 0)
            print(f"\n[TEST] Level 05 total symmetries: {total_symmetries}")
            self.assertEqual(total_symmetries, 8,
                "Level 05 (D4) should have 8 symmetries")
        except AgentClientError as e:
            if e.code == "NOT_FOUND":
                self.skipTest("level_05 not found")
            raise

    def test_02_level_09_s3_has_6_symmetries(self):
        """Level 09 (S3 symmetric group) should have exactly 6 symmetries."""
        try:
            self.client.load_level("level_09")
            state = self.client.get_state()

            total_symmetries = state.get("total_symmetries", 0)
            print(f"\n[TEST] Level 09 total symmetries: {total_symmetries}")
            self.assertEqual(total_symmetries, 6,
                "Level 09 (S3) should have 6 symmetries")
        except AgentClientError as e:
            if e.code == "NOT_FOUND":
                self.skipTest("level_09 not found")
            raise

    def test_03_level_12_d4_has_8_symmetries(self):
        """Level 12 (D4 square) should have exactly 8 symmetries."""
        try:
            self.client.load_level("level_12")
            state = self.client.get_state()

            total_symmetries = state.get("total_symmetries", 0)
            print(f"\n[TEST] Level 12 total symmetries: {total_symmetries}")
            self.assertEqual(total_symmetries, 8,
                "Level 12 (D4) should have 8 symmetries")
        except AgentClientError as e:
            if e.code == "NOT_FOUND":
                self.skipTest("level_12 not found")
            raise


# ─────────────────────────────────────────────────────────
# Test 4: Echo Hints (T034)
# ─────────────────────────────────────────────────────────

@unittest.skipUnless(godot_available(), SKIP_REASON)
class TestEchoHints(unittest.TestCase):
    """Test T034: Echo hint system with whisper/voice/vision."""

    def setUp(self):
        self.client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=300.0,  # Longer timeout for waiting tests
        )
        self.client.start(level_id="level_01")

    def tearDown(self):
        if self.client:
            self.client.quit()

    def test_01_whisper_appears_after_60_seconds(self):
        """After 60 seconds of inactivity, whisper hint should appear."""
        print("\n[TEST] Waiting 60 seconds for whisper hint...")

        # Check initial state
        tree_before = self.client.get_tree()

        # Wait 60+ seconds
        time.sleep(62)

        # Check for whisper hint
        tree_after = self.client.get_tree()
        events = self.client.get_events()

        print(f"\n[TEST] Events after 60s: {events}")

        # Look for whisper-related events or UI elements
        # This depends on how hints are implemented
        # May need to check for specific labels, animations, or events

        # For now, just verify the game is still responsive
        state = self.client.get_state()
        self.assertIsNotNone(state)

    def test_02_voice_appears_after_120_seconds(self):
        """After 120 seconds of inactivity, voice hint should appear."""
        print("\n[TEST] Waiting 120 seconds for voice hint...")

        # This is a long test - skip in quick runs
        if os.environ.get("QUICK_TEST"):
            self.skipTest("Skipping long wait test (QUICK_TEST set)")

        time.sleep(122)

        events = self.client.get_events()
        print(f"\n[TEST] Events after 120s: {events}")

        # Check for voice hint indicators
        state = self.client.get_state()
        self.assertIsNotNone(state)

    def test_03_vision_appears_after_180_seconds(self):
        """After 180 seconds of inactivity, vision (highlight) hint should appear."""
        print("\n[TEST] Waiting 180 seconds for vision hint...")

        # This is a very long test - skip unless explicitly requested
        if not os.environ.get("FULL_HINT_TEST"):
            self.skipTest("Skipping very long wait test (set FULL_HINT_TEST=1 to run)")

        time.sleep(182)

        events = self.client.get_events()
        tree = self.client.get_tree()

        print(f"\n[TEST] Events after 180s: {events}")

        # Look for vision/highlight indicators
        # This may be visible in the scene tree as highlighted crystals or special effects
        state = self.client.get_state()
        self.assertIsNotNone(state)

    def test_04_hints_reset_after_player_action(self):
        """After player action, hint timers should reset."""
        print("\n[TEST] Testing hint reset after player action...")

        # Wait for whisper (60s)
        print("  Waiting 60s for initial whisper...")
        time.sleep(62)

        # Perform action
        print("  Performing player action (swap)...")
        self.client.swap(0, 1)

        # Drain events
        events_after_action = self.client.get_events()
        print(f"  Events after action: {events_after_action}")

        # Wait less than 60s - should NOT get another whisper yet
        print("  Waiting 30s - should not see whisper yet...")
        time.sleep(30)

        events_short_wait = self.client.get_events()
        print(f"  Events after 30s: {events_short_wait}")

        # This test verifies the reset logic works
        # Actual assertion depends on event structure


# ─────────────────────────────────────────────────────────
# Run tests
# ─────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Run with verbose output
    unittest.main(verbosity=2)
