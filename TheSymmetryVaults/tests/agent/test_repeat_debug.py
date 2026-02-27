#!/usr/bin/env python3
"""Debug test for REPEAT on level_01 (Z3, 3 crystals)."""
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
    print(msg)

def main():
    client = AgentClient(godot_path=GODOT, project_path=PROJECT, timeout=15.0)
    try:
        log("Starting Godot...")
        client.start()

        # Level_01 loads automatically (Z3, rotations [1,2,0], [2,0,1], [0,1,2])
        log("--- Loading level_01 ---")
        client.load_level("level_01")
        time.sleep(1.0)
        st = client.get_state()
        log(f"  level: {st.get('level',{}).get('id','?')}")
        log(f"  arrangement: {st.get('arrangement')}")
        log(f"  crystals: {len(st.get('arrangement',[]))}")
        log(f"  found: {st.get('keyring',{}).get('found_count',0)}")

        # Submit r1=[1,2,0] (rotation 120)
        log("\n--- Submit [1,2,0] ---")
        client.submit_permutation([1, 2, 0])
        st1 = client.get_state()
        log(f"  arr={st1.get('arrangement')} found={st1.get('keyring',{}).get('found_count',0)}")

        # Submit [2,0,1] (rotation 240)
        log("--- Submit [2,0,1] ---")
        client.submit_permutation([2, 0, 1])
        st2 = client.get_state()
        log(f"  arr={st2.get('arrangement')} found={st2.get('keyring',{}).get('found_count',0)}")

        # Submit identity [0,1,2]
        log("--- Submit [0,1,2] (identity) ---")
        client.submit_permutation([0, 1, 2])
        st3 = client.get_state()
        log(f"  arr={st3.get('arrangement')} found={st3.get('keyring',{}).get('found_count',0)}")

        # Find all repeat buttons
        log("\n--- Buttons ---")
        buttons = client.find_buttons()
        repeat_btns = []
        for btn in buttons:
            name = btn.get("name", "")
            text = btn.get("text", "")
            path = btn.get("path", "")
            if "Repeat" in name:
                repeat_btns.append({"name": name, "text": text, "path": path})
                log(f"  REPEAT: {name} text='{text}'")

        # Test REPEAT on each key
        for rbtn in repeat_btns:
            log(f"\n=== REPEAT: {rbtn['name']} ({rbtn['text']}) ===")
            arr_before = client.get_state().get('arrangement')
            log(f"  before: {arr_before}")

            try:
                client.press_button(rbtn['path'])
                time.sleep(0.3)
            except Exception as e:
                log(f"  error: {e}")
                continue

            arr_after = client.get_state().get('arrangement')
            found = client.get_state().get('keyring',{}).get('found_count',0)
            log(f"  after:  {arr_after} found={found}")
            log(f"  >>> {'MOVED' if arr_before != arr_after else 'NO CHANGE'}")

    except Exception as e:
        log(f"\n!!! ERROR: {e}")
        import traceback
        log(traceback.format_exc())
    finally:
        log("\nShutting down...")
        client.quit()
        log("Done.")

if __name__ == "__main__":
    main()
