#!/usr/bin/env python3
"""T057 reproduction: Simulates the exact pattern from T052 QA that triggers
'No level loaded' after ~12 loads.

Mimics run_T052_qa.py flow:
1. Start Godot (no level_id => starts at MainMenu)
2. Load 12 levels sequentially, call get_tree() + get_state() each time
3. Then try loading more levels with submit_permutation
"""
import sys, os, time
from pathlib import Path

os.environ["PYTHONIOENCODING"] = "utf-8"
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'replace')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'replace')

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient, AgentClientError

GODOT = "C:/Godot/Godot_v4.6.1-stable_win64_console.exe"
PROJECT = str(Path(__file__).resolve().parents[2])

LEVELS = ["level_%02d" % i for i in range(1, 13)]

def log(msg):
    print(msg, flush=True)

def find_node_in_tree(tree, name):
    if tree.get("name") == name:
        return tree
    for child in tree.get("children", []):
        result = find_node_in_tree(child, name)
        if result:
            return result
    return None

def main():
    client = AgentClient(godot_path=GODOT, project_path=PROJECT, timeout=15.0)

    try:
        log("Starting Godot (no level_id => MainMenu)...")
        client.start()  # No level_id - same as run_T052_qa.py
        time.sleep(1.0)

        # Phase 1: Load 12 levels with get_tree (like T043 TargetPreview test)
        log("\n=== PHASE 1: 12 levels with get_tree (T043 pattern) ===")
        for i, level_id in enumerate(LEVELS):
            try:
                result = client.load_level(level_id)
                loaded = result.get("loaded")
                if loaded == "pending":
                    time.sleep(2.0)
                else:
                    time.sleep(0.2)

                # Call get_tree (heavy operation) - same as T043 test
                tree = client.get_tree()
                tp = find_node_in_tree(tree, "TargetPreview")

                state = client.get_state()
                arr = state.get("arrangement", [])
                log("  #%02d %s: loaded=%s crystals=%d TP=%s" % (
                    i+1, level_id, loaded, len(arr), "yes" if tp else "NO"))
            except Exception as e:
                log("  #%02d %s: ERROR: %s" % (i+1, level_id, e))

        # Phase 2: Load more levels with submit_permutation (like T044 test)
        log("\n=== PHASE 2: Additional loads with submit (T044 pattern) ===")
        test_cases = [
            ("level_01", [1, 2, 0]),
            ("level_05", [1, 2, 3, 4, 0]),
            ("level_11", [1, 2, 3, 4, 5, 0]),
        ]

        for level_id, perm in test_cases:
            try:
                log("  Loading %s..." % level_id)
                result = client.load_level(level_id)
                loaded = result.get("loaded")
                if loaded == "pending":
                    time.sleep(2.0)
                else:
                    time.sleep(0.2)

                log("    load result: loaded=%s" % loaded)

                # submit_permutation
                resp = client.submit_permutation(perm)
                log("    submit OK")

                state = client.get_state()
                found = state.get("keyring", {}).get("found_count", 0)
                log("    state OK: found=%d arr=%s" % (found, state.get("arrangement")))

            except AgentClientError as e:
                log("    AGENT ERROR: %s (code=%s)" % (e, e.code))
            except Exception as e:
                log("    ERROR: %s" % e)

        # Phase 3: Rapid loads (regression)
        log("\n=== PHASE 3: 12 more rapid loads (regression pattern) ===")
        for i, level_id in enumerate(LEVELS):
            try:
                result = client.load_level(level_id)
                loaded = result.get("loaded")
                if loaded == "pending":
                    time.sleep(2.0)
                else:
                    time.sleep(0.1)
                state = client.get_state()
                arr = state.get("arrangement", [])
                log("  #%02d %s: crystals=%d" % (i+1, level_id, len(arr)))
            except Exception as e:
                log("  #%02d %s: ERROR: %s" % (i+1, level_id, e))

        # Phase 4: Level completion test
        log("\n=== PHASE 4: Level completion ===")
        try:
            client.load_level("level_01")
            time.sleep(0.2)
            for perm in [[0,1,2], [1,2,0], [2,0,1]]:
                client.submit_permutation(perm)
            state = client.get_state()
            found = state["keyring"]["found_count"]
            total = state["keyring"]["total"]
            log("  level_01 completion: %d/%d" % (found, total))
        except Exception as e:
            log("  level_01 completion ERROR: %s" % e)

        log("\n=== ALL PHASES COMPLETE ===")

    except Exception as e:
        log("\nFATAL: %s" % e)
        import traceback
        log(traceback.format_exc())
    finally:
        log("\nShutting down...")
        client.quit()
        log("Done.")

if __name__ == "__main__":
    main()
