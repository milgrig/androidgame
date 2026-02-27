#!/usr/bin/env python3
"""T057 verification: Load 20+ levels sequentially through AgentBridge.

Tests multiple scenarios:
1. Fast sequential loads (no delay between loads)
2. Loads with scene transitions (navigate away, then load)
3. Mixed: some via load_level, some via navigate
"""
import sys, os, time
from pathlib import Path

os.environ["PYTHONIOENCODING"] = "utf-8"
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'replace')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'replace')

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT = "C:/Godot/Godot_v4.6.1-stable_win64_console.exe"
PROJECT = str(Path(__file__).resolve().parents[2])

LEVELS = ["level_%02d" % i for i in range(1, 13)]

def log(msg):
    print(msg, flush=True)

def run_test_fast_loads(client, num=25):
    """Test 1: Fast sequential loads with no extra delay."""
    log("\n=== TEST 1: %d fast sequential loads ===" % num)
    passed = 0
    failed = 0
    errors = []

    for i in range(num):
        level_id = LEVELS[i % len(LEVELS)]
        label = "#%02d '%s'" % (i + 1, level_id)
        try:
            result = client.load_level(level_id)
            if result.get("loaded") == "pending":
                time.sleep(1.5)
            state = client.get_state()
            arr = state.get("arrangement", [])
            if len(arr) > 0:
                passed += 1
            else:
                log("  %s -> FAIL: empty arrangement" % label)
                failed += 1
                errors.append(label)
        except Exception as e:
            log("  %s -> ERROR: %s" % (label, e))
            failed += 1
            errors.append("%s: %s" % (label, e))

    log("  Result: %d/%d passed" % (passed, num))
    return passed, failed, errors

def run_test_scene_transitions(client, num=10):
    """Test 2: Navigate to main_menu, then load level (tests pending path)."""
    log("\n=== TEST 2: %d loads via scene transitions ===" % num)
    passed = 0
    failed = 0
    errors = []

    for i in range(num):
        level_id = LEVELS[i % len(LEVELS)]
        label = "#%02d '%s' (via main_menu)" % (i + 1, level_id)
        try:
            # Navigate to main menu first (drops _level_scene)
            client._send_command("navigate", {"to": "main_menu"})
            time.sleep(1.0)

            # Now load level (should go through change_scene_to_file path)
            result = client.load_level(level_id)
            loaded = result.get("loaded")

            if loaded == "pending":
                # Wait for scene transition
                time.sleep(2.0)

            # Verify state
            state = client.get_state()
            arr = state.get("arrangement", [])
            if len(arr) > 0:
                passed += 1
            else:
                log("  %s -> FAIL: empty arrangement" % label)
                failed += 1
                errors.append(label)
        except Exception as e:
            log("  %s -> ERROR: %s" % (label, e))
            failed += 1
            errors.append("%s: %s" % (label, e))

    log("  Result: %d/%d passed" % (passed, num))
    return passed, failed, errors

def run_test_rapid_fire(client, num=30):
    """Test 3: Ultra-fast loads with minimal delay."""
    log("\n=== TEST 3: %d rapid-fire loads (no delay) ===" % num)
    passed = 0
    failed = 0
    errors = []

    for i in range(num):
        level_id = LEVELS[i % len(LEVELS)]
        label = "#%02d '%s'" % (i + 1, level_id)
        try:
            result = client.load_level(level_id)
            if result.get("loaded") == "pending":
                time.sleep(1.5)
            # Minimal delay
            time.sleep(0.05)
            state = client.get_state()
            arr = state.get("arrangement", [])
            if len(arr) > 0:
                passed += 1
            else:
                log("  %s -> FAIL: empty arrangement" % label)
                failed += 1
                errors.append(label)
        except Exception as e:
            log("  %s -> ERROR: %s" % (label, e))
            failed += 1
            errors.append("%s: %s" % (label, e))

    log("  Result: %d/%d passed" % (passed, num))
    return passed, failed, errors

def main():
    client = AgentClient(godot_path=GODOT, project_path=PROJECT, timeout=15.0)
    total_passed = 0
    total_failed = 0
    all_errors = []

    try:
        log("Starting Godot in agent mode...")
        client.start()
        time.sleep(1.0)

        # Test 1: Fast sequential
        p, f, e = run_test_fast_loads(client, 25)
        total_passed += p; total_failed += f; all_errors += e

        # Test 2: Scene transitions
        p, f, e = run_test_scene_transitions(client, 10)
        total_passed += p; total_failed += f; all_errors += e

        # Test 3: Rapid fire
        p, f, e = run_test_rapid_fire(client, 30)
        total_passed += p; total_failed += f; all_errors += e

        total = total_passed + total_failed
        log("\n" + "=" * 50)
        log("TOTAL: %d passed, %d failed out of %d" % (total_passed, total_failed, total))
        if all_errors:
            log("\nAll errors:")
            for err in all_errors:
                log("  - %s" % err)
        if total_failed == 0:
            log("\nALL TESTS PASSED!")
        else:
            log("\n%d TESTS FAILED!" % total_failed)

    except Exception as e:
        log("\n!!! FATAL: %s" % e)
        import traceback
        log(traceback.format_exc())
    finally:
        log("\nShutting down...")
        client.quit()
        log("Done.")

if __name__ == "__main__":
    main()
