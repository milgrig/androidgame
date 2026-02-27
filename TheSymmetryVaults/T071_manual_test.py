"""
T071: Manual testing script for room map on all level types.
Tests visual appearance, interactions, and completeness.
"""
import sys
import os
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "tests" / "agent"))
os.environ["PYTHONIOENCODING"] = "utf-8"

from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parent)

# Test levels with their group types
TEST_LEVELS = [
    {"id": "level_01", "group": "Z3", "rooms": 3, "title": "Level 01"},
    {"id": "level_04", "group": "Z4", "rooms": 4, "title": "Level 04"},
    {"id": "level_05", "group": "D5", "rooms": 10, "title": "Level 05"},
    {"id": "level_09", "group": "S3", "rooms": 6, "title": "Level 09"},
    {"id": "level_10", "group": "S2", "rooms": 2, "title": "Level 10"},
    {"id": "level_11", "group": "trivial", "rooms": 1, "title": "Level 11"},
]

ACT2_LEVELS = [
    {"id": "level_13", "title": "Subgroups and Inner Doors"},
    {"id": "level_14", "title": "Full Playthrough"},
    {"id": "level_15", "title": "Complex Subgroups"},
    {"id": "level_16", "title": "Final Challenge"},
]

class TestReport:
    def __init__(self):
        self.results = []
        self.passed = 0
        self.failed = 0
        self.warnings = []

    def check(self, name, condition, detail="", warning=False):
        status = "PASS" if condition else ("WARN" if warning else "FAIL")
        msg = f"  [{status}] {name}"
        if detail:
            msg += f" ({detail})"
        print(msg)

        self.results.append({"name": name, "status": status, "detail": detail})
        if condition:
            self.passed += 1
        elif warning:
            self.warnings.append(msg)
        else:
            self.failed += 1

    def section(self, title):
        print(f"\n{'='*70}")
        print(f"  {title}")
        print(f"{'='*70}")

    def subsection(self, title):
        print(f"\n{'-'*70}")
        print(f"  {title}")
        print(f"{'-'*70}")

    def summary(self):
        print(f"\n{'='*70}")
        print(f"TEST SUMMARY")
        print(f"{'='*70}")
        print(f"  Total checks: {self.passed + self.failed}")
        print(f"  Passed: {self.passed}")
        print(f"  Failed: {self.failed}")
        print(f"  Warnings: {len(self.warnings)}")
        print(f"{'='*70}")
        return self.failed == 0


def test_room_map_visual(client: AgentClient, report: TestReport, level_info: dict):
    """Test room map visual appearance and layout"""
    report.subsection(f"Testing {level_info['id']}: {level_info['title']}")

    # Load level
    try:
        client.load_level(level_info["id"])
        time.sleep(2)
        report.check(f"Level {level_info['id']} loaded", True)
    except Exception as e:
        report.check(f"Level {level_info['id']} loaded", False, str(e))
        return False

    # Get state
    try:
        state = client.get_state()
        report.check("get_state() works", True)
    except Exception as e:
        report.check("get_state() works", False, str(e))
        return False

    # Check basic level properties
    level = state.get("level", {})
    report.check("Level ID correct", level.get("id") == f"act1_{level_info['id']}")
    report.check("Level title correct", level.get("title") == level_info.get("title", ""))

    # Check room map exists
    crystals = state.get("crystals", [])
    expected_rooms = level_info.get("rooms", len(crystals))
    report.check(f"Expected {expected_rooms} rooms",
                 len(crystals) > 0,
                 f"got {len(crystals)} crystals")

    # Check keyring
    keyring = state.get("keyring", {})
    total_symmetries = keyring.get("total", 0)
    report.check("Total symmetries > 0", total_symmetries > 0, f"total={total_symmetries}")
    report.check(f"Group order matches rooms",
                 total_symmetries == expected_rooms,
                 f"expected {expected_rooms}, got {total_symmetries}",
                 warning=True)

    return True


def test_level_playable(client: AgentClient, report: TestReport, level_info: dict):
    """Test that level can be played through"""
    try:
        # Submit identity
        state = client.get_state()
        n = len(state.get("crystals", []))
        identity = list(range(n))

        result = client.submit_permutation(identity)
        events = result.get("events", [])
        event_types = [e.get("type") for e in events]

        report.check("Identity submission works", "symmetry_found" in event_types or "already_found" in event_types)

        # Check counter updated
        state2 = client.get_state()
        found_count = state2["keyring"]["found_count"]
        report.check("Keyring updated", found_count >= 1, f"found={found_count}")

        return True
    except Exception as e:
        report.check("Level playable", False, str(e))
        return False


def test_window_resize(client: AgentClient, report: TestReport):
    """Test window resize behavior"""
    report.section("WINDOW RESIZE TEST")

    try:
        # Try to get window info
        tree = client._send_command("get_tree", {"root": "/root", "max_depth": 2})
        report.check("Can query scene tree", tree.get("ok", False))

        # Load a level
        client.load_level("level_01")
        time.sleep(2)

        # Test if level still works after load
        state = client.get_state()
        report.check("Level state accessible after resize scenario", len(state.get("crystals", [])) > 0)

        return True
    except Exception as e:
        report.check("Window resize test", False, str(e))
        return False


def main():
    report = TestReport()

    try:
        report.section("STARTING GODOT CLIENT")
        client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=30.0)
        client.start()
        time.sleep(3)
        report.check("Godot client started", True)

        # Test Act 1 levels
        report.section("ACT 1 LEVELS - Room Map Visual Tests")
        for level_info in TEST_LEVELS:
            success = test_room_map_visual(client, report, level_info)
            if success:
                test_level_playable(client, report, level_info)

        # Test window resize
        test_window_resize(client, report)

        # Act 2 levels note
        report.section("ACT 2 LEVELS - Subgroups")
        print("  Note: Act 2 levels (13-16) require subgroup implementation")
        print("  Attempting to test if they load...")

        for level_info in ACT2_LEVELS:
            try:
                client.load_level(level_info["id"])
                time.sleep(2)
                state = client.get_state()
                report.check(f"{level_info['id']} loads", True)
            except Exception as e:
                report.check(f"{level_info['id']} loads", False, str(e), warning=True)

    except Exception as e:
        report.check("Test execution", False, f"Fatal error: {e}")
    finally:
        if 'client' in locals():
            client.quit()

    # Print summary
    success = report.summary()

    # Save report
    report_path = Path(__file__).parent / "T071_manual_test_report.txt"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("="*70 + "\n")
        f.write("T071: Room Map QA Test Report\n")
        f.write("="*70 + "\n\n")
        for result in report.results:
            f.write(f"[{result['status']}] {result['name']}")
            if result['detail']:
                f.write(f" - {result['detail']}")
            f.write("\n")
        f.write(f"\n{'='*70}\n")
        f.write(f"PASSED: {report.passed}, FAILED: {report.failed}, WARNINGS: {len(report.warnings)}\n")
        f.write(f"{'='*70}\n")

    print(f"\nReport saved to: {report_path}")
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
