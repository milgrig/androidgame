#!/usr/bin/env python3
"""Test REPEAT composition on act1_level04 (Z4, 4 crystals, directed square).
Verifies that applying r3 (270) repeatedly gives correct cycle:
  identity -> r3 -> r2 -> r1 -> identity
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

def log(msg):
    print(msg, flush=True)

def find_repeat_btn(client, key_index=None):
    """Find a repeat button, optionally for a specific key index."""
    buttons = client.find_buttons()
    repeat_btns = [b for b in buttons if "Repeat" in b.get("name", "")]
    if key_index is not None:
        # Look for RepeatBtn_{key_index}
        target_name = "RepeatBtn_%d" % key_index
        for btn in repeat_btns:
            if btn.get("name", "") == target_name:
                return btn
    # Fallback: return first visible repeat button
    for btn in repeat_btns:
        if btn.get("visible", True):
            return btn
    return repeat_btns[0] if repeat_btns else None

def main():
    client = AgentClient(godot_path=GODOT, project_path=PROJECT, timeout=15.0)
    passed = 0
    failed = 0

    try:
        log("Starting Godot...")
        client.start()
        time.sleep(1.0)

        log("Loading act1_level04...")
        client.load_level("act1_level04")
        time.sleep(3.0)

        for _ in range(10):
            try:
                st = client.get_state()
                if len(st.get('arrangement', [])) == 4:
                    break
                time.sleep(1.0)
            except:
                time.sleep(1.0)

        # Find identity and r3
        log("\n--- Submit identity [0,1,2,3] (first key) ---")
        client.submit_permutation([0, 1, 2, 3])
        time.sleep(0.3)

        log("--- Submit r3 [3,0,1,2] (second key) ---")
        client.submit_permutation([3, 0, 1, 2])
        time.sleep(0.3)

        # Reset to identity
        log("--- Reset to identity ---")
        client.submit_permutation([0, 1, 2, 3])
        time.sleep(0.3)

        st = client.get_state()
        log("State: arr=%s found=%d" % (st.get('arrangement'), st.get('keyring', {}).get('found_count', 0)))

        # Expected cycle when repeatedly applying r3:
        # e -> r3 -> r2 -> r1 -> e
        expected = [
            ([3, 0, 1, 2], "r3 (270)"),
            ([2, 3, 0, 1], "r2 (180)"),
            ([1, 2, 3, 0], "r1 (90)"),
            ([0, 1, 2, 3], "e (identity)"),
        ]

        for i, (exp_arr, label) in enumerate(expected):
            test_name = "REPEAT #%d -> %s" % (i + 1, label)
            arr_before = client.get_state().get('arrangement')
            log("\n=== %s ===" % test_name)
            log("  before: %s" % arr_before)

            # Re-find repeat button (UI may rebuild after key discovery)
            rbtn = find_repeat_btn(client, key_index=1)
            if not rbtn:
                # Try any repeat button
                rbtn = find_repeat_btn(client)
            if not rbtn:
                log("  SKIP: no repeat button found (UI may have changed)")
                continue

            try:
                client.press_button(rbtn['path'])
            except Exception as e:
                log("  Button press error: %s" % e)
                # Try refreshing button list
                time.sleep(0.5)
                rbtn = find_repeat_btn(client)
                if rbtn:
                    client.press_button(rbtn['path'])
                else:
                    log("  FAIL: cannot find any repeat button")
                    failed += 1
                    continue

            time.sleep(0.5)
            arr_after = client.get_state().get('arrangement')
            log("  after:  %s" % arr_after)
            log("  expect: %s" % exp_arr)

            if arr_after == exp_arr:
                log("  PASS")
                passed += 1
            elif arr_before != arr_after:
                log("  PARTIAL: moved but to wrong position")
                failed += 1
            else:
                log("  FAIL: no change")
                failed += 1

        log("\n" + "=" * 40)
        log("RESULTS: %d passed, %d failed" % (passed, failed))
        if failed == 0 and passed > 0:
            log("ALL TESTS PASSED!")
        elif failed > 0:
            log("SOME TESTS FAILED!")

    except Exception as e:
        log("\n!!! ERROR: %s" % e)
        import traceback
        log(traceback.format_exc())
    finally:
        log("\nShutting down...")
        client.quit()
        log("Done.")

if __name__ == "__main__":
    main()
