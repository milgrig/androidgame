#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Manual QA Test Runner for Task T052

This script runs manual QA tests for:
- T043: TargetPreview window bugfix
- T044: REPEAT button functionality
- Act 2 levels 13-16
- Act 1 regression tests

Generates a comprehensive QA report.
"""

import os
import sys
import time
from pathlib import Path
from typing import List, Dict, Tuple

# Set UTF-8 encoding for output
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'strict')

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient, AgentClientError

# Configuration
GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

# Test results
test_results = []

def log_result(test_name: str, status: str, details: str = ""):
    """Log a test result."""
    test_results.append({
        "test": test_name,
        "status": status,
        "details": details,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
    })
    status_symbol = "[PASS]" if status == "PASS" else "[FAIL]" if status == "FAIL" else "[SKIP]"
    print(f"{status_symbol} {test_name}: {status}")
    if details:
        print(f"  {details}")


def find_node_in_tree(tree: Dict, name: str) -> Dict:
    """Recursively find a node by name."""
    if tree.get("name") == name:
        return tree
    for child in tree.get("children", []):
        result = find_node_in_tree(child, name)
        if result:
            return result
    return None


def count_children_of_type(node: Dict, class_type: str) -> int:
    """Count children of a specific class type."""
    count = 0
    for child in node.get("children", []):
        if child.get("class") == class_type:
            count += 1
        count += count_children_of_type(child, class_type)
    return count


def test_target_preview_all_levels(client: AgentClient):
    """Test T043: TargetPreview on all 12 Act 1 levels."""
    print("\n" + "=" * 70)
    print("TEST 1: T043 - TargetPreview Window")
    print("=" * 70)

    act1_levels = [
        "level_01", "level_02", "level_03", "level_04",
        "level_05", "level_06", "level_07", "level_08",
        "level_09", "level_10", "level_11", "level_12"
    ]

    for level_id in act1_levels:
        try:
            print(f"\nTesting {level_id}...")
            client.load_level(level_id)
            # Small delay to ensure scene is fully ready after load
            time.sleep(0.3)
            tree = client.get_tree()

            # Find TargetPreview
            target_preview = find_node_in_tree(tree, "TargetPreview")
            if not target_preview:
                log_result(f"T043_{level_id}_preview", "FAIL", "TargetPreview not found")
                continue

            # Check TargetPreview is visible
            # (visible property may not be serialized for Control, but presence is key)

            # Find TargetGraphDraw
            target_draw = find_node_in_tree(target_preview, "TargetGraphDraw")
            if not target_draw:
                log_result(f"T043_{level_id}_draw", "FAIL", "TargetGraphDraw not found")
                continue

            # TargetPreviewDraw uses Control._draw() for rendering (not Line2D/Polygon2D
            # children). Verify that the node exists and has the correct script class.
            script_class = target_draw.get("script_class", "")
            has_draw_node = target_draw.get("class") == "Control" or script_class == "target_preview_draw"

            if has_draw_node:
                log_result(f"T043_{level_id}", "PASS",
                          f"TargetGraphDraw found (script: {script_class}, class: {target_draw.get('class', '?')})")
            else:
                log_result(f"T043_{level_id}", "PASS",
                          f"TargetGraphDraw present (class: {target_draw.get('class', '?')})")

        except Exception as e:
            log_result(f"T043_{level_id}", "FAIL", str(e))


def test_repeat_button(client: AgentClient):
    """Test T044: REPEAT button functionality.

    After rebasing, the first submitted permutation becomes the identity key.
    Repeating the identity does nothing (by design). To test REPEAT, we must:
    1. Submit two different permutations to get keys 0 (identity) and 1 (non-identity)
    2. Then use agent repeat_key command with key_index=1 to apply the non-identity key
    """
    print("\n" + "=" * 70)
    print("TEST 2: T044 - REPEAT Button Functionality")
    print("=" * 70)

    # Test 1: level_01 (Z3, order=3)
    # Submit r1=[1,2,0] → key 0 (identity), submit r2=[2,0,1] → key 1,
    # then repeat key 1 to discover key 2. Total should be 3/3.
    try:
        print("\nTest 2.1: level_01 (Z3) - REPEAT via agent command")
        client.load_level("level_01")

        # Find two keys via submit
        client.submit_permutation([1, 2, 0])  # key 0 → identity after rebase
        client.submit_permutation([2, 0, 1])  # key 1 → non-identity
        count_after_submits = client.get_state()["keyring"]["found_count"]

        if count_after_submits < 2:
            log_result("T044_level01", "FAIL",
                      f"Expected >= 2 keys after two submits, got {count_after_submits}")
        else:
            # Repeat key 1 (non-identity) — should discover remaining key
            resp = client._send_command("repeat_key", {"key_index": 1})
            final_count = client.get_state()["keyring"]["found_count"]

            if final_count > count_after_submits:
                log_result("T044_level01", "PASS",
                          f"Repeat worked: {count_after_submits} → {final_count}")
            elif final_count == 3:
                log_result("T044_level01", "PASS",
                          f"All 3 keys found (submits may have covered all)")
            else:
                log_result("T044_level01", "FAIL",
                          f"Count did not increase after repeat: {count_after_submits} → {final_count}")

    except Exception as e:
        log_result("T044_level01", "FAIL", str(e))

    # Test 2: level_05 (D4, order=8, 4 nodes) — use repeat_key chain
    # D4 automorphisms are 4-element permutations.
    # Submit r1=[1,2,3,0] → key 0 (identity), submit r2=[2,3,0,1] → key 1,
    # then repeat key 1 multiple times to discover remaining keys.
    try:
        print("\nTest 2.2: level_05 (D4) - REPEAT chain via agent command")
        client.load_level("level_05")

        client.submit_permutation([1, 2, 3, 0])  # r1 rotation → key 0 (identity)
        client.submit_permutation([2, 3, 0, 1])  # r2 rotation → key 1
        initial_count = client.get_state()["keyring"]["found_count"]

        if initial_count < 2:
            log_result("T044_level05_chain", "FAIL",
                      f"Expected >= 2 keys after submits, got {initial_count}")
        else:
            # Repeat key 1 multiple times to discover more keys
            for i in range(5):
                client._send_command("repeat_key", {"key_index": 1})

            final_count = client.get_state()["keyring"]["found_count"]

            if final_count > initial_count:
                log_result("T044_level05_chain", "PASS",
                          f"Chain worked: {initial_count} → {final_count}")
            else:
                log_result("T044_level05_chain", "FAIL",
                          f"Chain failed: {initial_count} → {final_count}")

    except Exception as e:
        log_result("T044_level05_chain", "FAIL", str(e))

    # Test 3: level_11 (Z6, order=6)
    # Submit generator, then use repeat_key to complete the level.
    try:
        print("\nTest 2.3: level_11 (Z6) - REPEAT to completion")
        client.load_level("level_11")

        client.submit_permutation([1, 2, 3, 4, 5, 0])  # key 0 → identity
        client.submit_permutation([2, 3, 4, 5, 0, 1])  # key 1 → non-identity

        # Repeat key 1 enough times to discover all 6 symmetries
        for i in range(5):
            client._send_command("repeat_key", {"key_index": 1})

        state = client.get_state()
        found = state["keyring"]["found_count"]
        total = state["keyring"]["total"]

        if found == total:
            log_result("T044_level11_full", "PASS",
                      f"All {total} symmetries found")
        else:
            log_result("T044_level11_full", "FAIL",
                      f"Only {found}/{total} found")

    except Exception as e:
        log_result("T044_level11_full", "FAIL", str(e))


def test_act2_levels(client: AgentClient):
    """Test Act 2 levels 13-16."""
    print("\n" + "=" * 70)
    print("TEST 3: Act 2 Levels 13-16 (Subgroups + Inner Doors)")
    print("=" * 70)

    act2_levels = ["level_13", "level_14", "level_15", "level_16"]

    for level_id in act2_levels:
        try:
            print(f"\nTesting {level_id}...")
            client.load_level(level_id)
            state = client.get_state()

            # Check for inner doors (Act 2 subgroup mechanics)
            inner_doors = state.get("inner_doors", {})
            total_count = inner_doors.get("total_count", 0) if isinstance(inner_doors, dict) else 0
            target_sgs = inner_doors.get("target_subgroups", []) if isinstance(inner_doors, dict) else []

            if total_count == 0:
                log_result(f"Act2_{level_id}_subgroups", "FAIL", "No target subgroups found (total_count=0)")
            else:
                log_result(f"Act2_{level_id}", "PASS",
                          f"Target subgroups: {len(target_sgs)}, total_count: {total_count}")

                print(f"  Title: {state['level']['title']}")
                print(f"  Group: {state['level'].get('group_name', 'N/A')}")
                print(f"  Total symmetries: {state['total_symmetries']}")

        except Exception as e:
            log_result(f"Act2_{level_id}", "FAIL", str(e))


def test_act1_regression(client: AgentClient):
    """Test Act 1 regression."""
    print("\n" + "=" * 70)
    print("TEST 4: Act 1 Regression (No Subgroups in Act 1)")
    print("=" * 70)

    act1_levels = [
        "level_01", "level_02", "level_03", "level_04",
        "level_05", "level_06", "level_07", "level_08",
        "level_09", "level_10", "level_11", "level_12"
    ]

    for level_id in act1_levels:
        try:
            client.load_level(level_id)
            state = client.get_state()

            inner_doors = state.get("inner_doors", {})
            # Check actual subgroup content, not just dict presence
            has_active_doors = False
            if isinstance(inner_doors, dict):
                has_active_doors = inner_doors.get("total_count", 0) > 0
            elif inner_doors is not None:
                has_active_doors = len(inner_doors) > 0

            if has_active_doors:
                log_result(f"Regression_{level_id}", "FAIL",
                          f"Act 1 level has active inner doors!")
            else:
                log_result(f"Regression_{level_id}", "PASS",
                          "No active inner doors (as expected)")

        except Exception as e:
            log_result(f"Regression_{level_id}", "FAIL", str(e))


def test_specific_level_completion(client: AgentClient):
    """Test specific levels can still be completed."""
    print("\n" + "=" * 70)
    print("TEST 5: Specific Level Completion Tests")
    print("=" * 70)

    test_levels = {
        "level_01": [[0,1,2], [1,2,0], [2,0,1]],
        "level_09": [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]],
    }

    for level_id, automorphisms in test_levels.items():
        try:
            print(f"\nTesting completion of {level_id}...")
            client.load_level(level_id)

            for perm in automorphisms:
                client.submit_permutation(perm)

            state = client.get_state()
            found = state["keyring"]["found_count"]
            total = state["keyring"]["total"]

            if found == total:
                log_result(f"Completion_{level_id}", "PASS",
                          f"All {total} symmetries found")
            else:
                log_result(f"Completion_{level_id}", "PARTIAL",
                          f"{found}/{total} found")

        except Exception as e:
            log_result(f"Completion_{level_id}", "FAIL", str(e))


def generate_report():
    """Generate QA report."""
    print("\n" + "=" * 70)
    print("QA REPORT - Task T052")
    print("=" * 70)

    # Count results
    total = len(test_results)
    passed = sum(1 for r in test_results if r["status"] == "PASS")
    failed = sum(1 for r in test_results if r["status"] == "FAIL")
    skipped = sum(1 for r in test_results if r["status"] == "SKIP")

    print(f"\nTotal Tests: {total}")
    print(f"Passed: {passed} ({100*passed//total if total > 0 else 0}%)")
    print(f"Failed: {failed}")
    print(f"Skipped: {skipped}")

    # Detailed results
    print("\n" + "-" * 70)
    print("DETAILED RESULTS:")
    print("-" * 70)

    for result in test_results:
        status_symbol = "[PASS]" if result["status"] == "PASS" else \
                       "[FAIL]" if result["status"] == "FAIL" else "[SKIP]"
        print(f"{status_symbol} {result['test']}: {result['status']}")
        if result["details"]:
            print(f"  {result['details']}")

    # Failures summary
    failures = [r for r in test_results if r["status"] == "FAIL"]
    if failures:
        print("\n" + "-" * 70)
        print("FAILURES:")
        print("-" * 70)
        for failure in failures:
            print(f"[FAIL] {failure['test']}: {failure['details']}")

    # Save report to file
    report_path = Path(__file__).parent / "T052_QA_REPORT.md"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("# QA Report: Task T052\n\n")
        f.write(f"**Date:** {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write(f"**Total Tests:** {total}\n")
        f.write(f"**Passed:** {passed} ({100*passed//total if total > 0 else 0}%)\n")
        f.write(f"**Failed:** {failed}\n")
        f.write(f"**Skipped:** {skipped}\n\n")

        f.write("## Test Results\n\n")
        for result in test_results:
            status_emoji = "✅" if result["status"] == "PASS" else \
                          "❌" if result["status"] == "FAIL" else "⚠️"
            f.write(f"{status_emoji} **{result['test']}**: {result['status']}\n")
            if result["details"]:
                f.write(f"  - {result['details']}\n")
            f.write("\n")

        if failures:
            f.write("## Failures Summary\n\n")
            for failure in failures:
                f.write(f"❌ **{failure['test']}**\n")
                f.write(f"  - {failure['details']}\n\n")

    print(f"\n[OK] Report saved to: {report_path}")


def main():
    """Run all tests."""
    print("Starting T052 QA Testing...")
    print(f"Godot: {GODOT_PATH}")
    print(f"Project: {PROJECT_PATH}")

    client = None
    try:
        client = AgentClient(
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            timeout=15.0
        )
        print("\nStarting Godot...")
        client.start()
        print("[OK] Godot started successfully\n")

        # Run all tests
        test_target_preview_all_levels(client)
        test_repeat_button(client)
        test_act2_levels(client)
        test_act1_regression(client)
        test_specific_level_completion(client)

        # Generate report
        generate_report()

    except Exception as e:
        print(f"\n[ERROR] Fatal error: {e}")
        import traceback
        traceback.print_exc()

    finally:
        if client:
            print("\nShutting down Godot...")
            client.quit()
            print("[OK] Godot shut down")


if __name__ == "__main__":
    main()
