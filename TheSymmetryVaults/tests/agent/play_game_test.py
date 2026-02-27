"""
Automated gameplay test - AI plays through the game!
Tests all core features by actually playing.
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

def print_separator(title):
    """Print a nice separator."""
    print(f"\n{'='*60}")
    print(f"  {title}")
    print('='*60)

def test_main_menu(client):
    """Test main menu functionality."""
    print_separator("TEST 1: MAIN MENU")

    print("\n[1.1] Checking scene tree...")
    tree = client.get_tree()

    print("[1.2] Finding buttons...")
    buttons = client.find_buttons(tree)
    print(f"      Found {len(buttons)} buttons")

    for i, btn in enumerate(buttons, 1):
        name = btn.get('name', 'unknown')
        # Skip text display to avoid encoding issues
        print(f"      {i}. {name}")

    if len(buttons) >= 3:
        print("\n✓ PASS: Main menu has all buttons")
        return True
    else:
        print(f"\n✗ FAIL: Expected 3 buttons, found {len(buttons)}")
        return False

def test_level_loading(client):
    """Test loading different levels."""
    print_separator("TEST 2: LEVEL LOADING")

    test_levels = [
        ("level_01", "Z3", 3),
        ("level_03", "Z2", 2),
        ("level_05", "D4", 8),
    ]

    all_passed = True

    for level_id, group, expected_symmetries in test_levels:
        print(f"\n[2.{test_levels.index((level_id, group, expected_symmetries)) + 1}] Loading {level_id} ({group})...")
        try:
            result = client.load_level(level_id)
            state = client.get_state()

            actual_symmetries = state.get('total_symmetries', 0)
            title = state['level'].get('title', 'Unknown')

            print(f"      Title: {title[:40]}")
            print(f"      Group: {state['level'].get('group_name', 'Unknown')}")
            print(f"      Symmetries: {actual_symmetries} (expected {expected_symmetries})")

            if actual_symmetries == expected_symmetries:
                print(f"      ✓ PASS: {level_id}")
            else:
                print(f"      ✗ FAIL: Wrong symmetry count!")
                all_passed = False

        except Exception as e:
            print(f"      ✗ ERROR: {e}")
            all_passed = False

    return all_passed

def test_gameplay_level01(client):
    """Test actually playing through level 1."""
    print_separator("TEST 3: GAMEPLAY - LEVEL 01 (Z3)")

    print("\n[3.1] Loading level_01...")
    client.load_level("level_01")

    print("[3.2] Checking initial state...")
    state = client.get_state()
    print(f"      Crystals: {len(state['crystals'])}")
    print(f"      Total symmetries: {state['total_symmetries']}")
    print(f"      Found: {state['keyring']['found_count']}/{state['keyring']['total']}")

    print("\n[3.3] Submitting identity permutation [0,1,2]...")
    resp1 = client.submit_permutation([0, 1, 2])
    events1 = resp1.get('events', [])
    sym_found_1 = [e for e in events1 if e['type'] == 'symmetry_found']
    print(f"      Events: {len(events1)}")
    print(f"      Symmetries found: {len(sym_found_1)}")

    if len(sym_found_1) == 1:
        print("      ✓ Identity found!")
    else:
        print(f"      ✗ Expected 1 symmetry event, got {len(sym_found_1)}")
        return False

    print("\n[3.4] Submitting rotation [1,2,0]...")
    resp2 = client.submit_permutation([1, 2, 0])
    events2 = resp2.get('events', [])
    sym_found_2 = [e for e in events2 if e['type'] == 'symmetry_found']
    print(f"      Symmetries found: {len(sym_found_2)}")

    if len(sym_found_2) == 1:
        print("      ✓ Rotation 120° found!")
    else:
        print(f"      ✗ Expected 1 symmetry event, got {len(sym_found_2)}")
        return False

    print("\n[3.5] Submitting rotation [2,0,1]...")
    resp3 = client.submit_permutation([2, 0, 1])
    events3 = resp3.get('events', [])
    sym_found_3 = [e for e in events3 if e['type'] == 'symmetry_found']
    completed = [e for e in events3 if e['type'] == 'level_completed']
    print(f"      Symmetries found: {len(sym_found_3)}")
    print(f"      Level completed: {len(completed) > 0}")

    if len(sym_found_3) == 1 and len(completed) == 1:
        print("      ✓ Rotation 240° found!")
        print("      ✓ LEVEL COMPLETED!")
        return True
    else:
        print(f"      ✗ Expected level completion")
        return False

def test_d4_level05(client):
    """Test D4 symmetry group (square with reflections)."""
    print_separator("TEST 4: D4 SYMMETRY - LEVEL 05")

    print("\n[4.1] Loading level_05 (D4 - Mirror Square)...")
    client.load_level("level_05")
    state = client.get_state()

    total_sym = state.get('total_symmetries', 0)
    print(f"      Total symmetries: {total_sym}")

    if total_sym == 8:
        print("      ✓ PASS: D4 has correct 8 symmetries")
        return True
    else:
        print(f"      ✗ FAIL: Expected 8, got {total_sym}")
        return False

def test_s3_level09(client):
    """Test S3 symmetric group."""
    print_separator("TEST 5: S3 SYMMETRY - LEVEL 09")

    print("\n[5.1] Loading level_09 (S3)...")
    try:
        client.load_level("level_09")
        state = client.get_state()

        total_sym = state.get('total_symmetries', 0)
        print(f"      Total symmetries: {total_sym}")

        if total_sym == 6:
            print("      ✓ PASS: S3 has correct 6 symmetries")
            return True
        else:
            print(f"      ✗ FAIL: Expected 6, got {total_sym}")
            return False
    except Exception as e:
        print(f"      ✗ ERROR: {e}")
        return False

def run_full_test_suite():
    """Run all gameplay tests."""
    print_separator("AUTOMATED GAMEPLAY TEST SUITE")
    print("Testing The Symmetry Vaults via Agent Bridge")
    print("This AI will play through the game automatically!")

    client = AgentClient(
        godot_path=GODOT_PATH,
        project_path=PROJECT_PATH,
        timeout=15.0,
    )

    print("\n[INIT] Starting Godot in headless mode...")
    client.start()

    print("[INIT] Waiting for UI initialization...")
    time.sleep(4)  # Wait for main menu animation

    results = {}

    # Run tests
    results['Main Menu'] = test_main_menu(client)
    results['Level Loading'] = test_level_loading(client)
    results['Gameplay Level 01'] = test_gameplay_level01(client)
    results['D4 Math (Level 05)'] = test_d4_level05(client)
    results['S3 Math (Level 09)'] = test_s3_level09(client)

    # Summary
    print_separator("TEST SUMMARY")

    total_tests = len(results)
    passed_tests = sum(1 for v in results.values() if v)

    print(f"\nResults:")
    for test_name, passed in results.items():
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"  {status}: {test_name}")

    print(f"\n{passed_tests}/{total_tests} tests passed ({passed_tests*100//total_tests}%)")

    if passed_tests == total_tests:
        print("\n🎉 ALL TESTS PASSED! Game is working perfectly! 🎉")
    else:
        print(f"\n⚠ {total_tests - passed_tests} test(s) failed")

    client.quit()

    return passed_tests == total_tests

if __name__ == "__main__":
    success = run_full_test_suite()
    exit(0 if success else 1)
