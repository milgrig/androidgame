"""
Full flow smoke test: Menu -> Map -> Level -> play -> verify.
This test proves the game ACTUALLY LAUNCHES and is navigable.
"""
import sys, os, time, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
os.environ["PYTHONIOENCODING"] = "utf-8"
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

PASS = 0
FAIL = 0

def check(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  PASS: {name}")
    else:
        FAIL += 1
        print(f"  FAIL: {name}" + (f" ({detail})" if detail else ""))

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=20.0)

try:
    # ============================
    print("=" * 60)
    print("STEP 1: Game starts -> MainMenu")
    print("=" * 60)
    client.start()
    time.sleep(3)

    # Check we're on MainMenu
    tree = client._send_command("get_tree", {"root": "/root/MainMenu", "max_depth": 3})
    menu_tree = tree.get("data", {}).get("tree", {})
    check("MainMenu scene loaded", menu_tree.get("name") == "MainMenu")

    # Check buttons exist
    actions = client._send_command("list_actions", {})
    action_list = actions.get("data", {}).get("actions", [])
    button_texts = [a.get("button_text", "") for a in action_list if a.get("action") == "press_button"]
    check("Start button visible", any("игру" in t or "Продолжить" in t for t in button_texts), str(button_texts))
    check("Settings button visible", any("Настройки" in t for t in button_texts))
    check("Exit button visible", any("Выход" in t for t in button_texts))

    # ============================
    print("\n" + "=" * 60)
    print("STEP 2: Press Start -> MapScene")
    print("=" * 60)
    client._send_command("press_button", {"path": "/root/MainMenu/ButtonContainer/StartButton"})
    time.sleep(3)

    # Check we're on MapScene
    map_state = client._send_command("get_map_state", {})
    map_data = map_state.get("data", {})
    check("Navigated to MapScene", map_data.get("current_scene") == "MapScene",
          f"scene={map_data.get('current_scene')}")

    # Check hall data
    halls = map_data.get("halls", [])
    check("12 halls visible on map", len(halls) == 12, f"got {len(halls)}")

    available = [h for h in halls if h.get("state") == "available"]
    check("At least 1 hall available", len(available) >= 1, f"available: {len(available)}")

    # ============================
    print("\n" + "=" * 60)
    print("STEP 3: Load level_01 from MapScene")
    print("=" * 60)
    result = client._send_command("load_level", {"level_id": "level_01"})
    check("load_level accepted", result.get("ok") == True, str(result.get("error", "")))
    time.sleep(3)  # Wait for scene transition

    # Now get state
    try:
        state = client.get_state()
        check("Level loaded", state.get("level", {}).get("id", "") != "", f"id={state.get('level', {}).get('id', '?')}")
        check("Crystals present", len(state.get("crystals", [])) >= 3, f"count={len(state.get('crystals', []))}")
        check("Keyring initialized", state.get("keyring", {}).get("total", 0) > 0)
        check("Is shuffled", state.get("is_shuffled") == True)
    except Exception as e:
        check("get_state works", False, str(e))

    # ============================
    print("\n" + "=" * 60)
    print("STEP 4: Play — submit identity permutation")
    print("=" * 60)
    try:
        state = client.get_state()
        n = len(state.get("crystals", []))
        identity = list(range(n))
        result = client._send_command("submit_permutation", {"mapping": identity})
        check("submit_permutation works", result.get("ok") == True)
        events = result.get("events", [])
        event_types = [e.get("type") for e in events]
        check("symmetry_found event", "symmetry_found" in event_types, str(event_types))
    except Exception as e:
        check("gameplay works", False, str(e))

    # ============================
    print("\n" + "=" * 60)
    print("STEP 5: Check buttons in level")
    print("=" * 60)
    actions = client._send_command("list_actions", {})
    action_list = actions.get("data", {}).get("actions", [])
    button_actions = [a for a in action_list if a.get("action") == "press_button"]
    check("Level has buttons", len(button_actions) >= 1, f"count={len(button_actions)}")
    for ba in button_actions:
        text = ba.get("button_text", "?")
        try:
            print(f"    Button: '{text}'")
        except UnicodeEncodeError:
            print(f"    Button: [unicode]")

    # ============================
    print("\n" + "=" * 60)
    print("STEP 6: Navigate back to map")
    print("=" * 60)
    result = client._send_command("navigate", {"to": "map"})
    check("Navigate to map", result.get("ok") == True)
    time.sleep(2)

    map_state = client._send_command("get_map_state", {})
    check("Back on MapScene", map_state.get("data", {}).get("current_scene") == "MapScene")

    # ============================
    print("\n" + "=" * 60)
    print("STEP 7: Navigate to MainMenu")
    print("=" * 60)
    result = client._send_command("navigate", {"to": "main_menu"})
    check("Navigate to menu", result.get("ok") == True)
    time.sleep(2)

    tree = client._send_command("get_tree", {"root": "/root/MainMenu", "max_depth": 1})
    check("Back on MainMenu", tree.get("ok") == True)

    # ============================
    print("\n" + "=" * 60)
    print(f"RESULTS: {PASS} PASS, {FAIL} FAIL")
    print("=" * 60)

    if FAIL > 0:
        print("\n*** SOME TESTS FAILED ***")
        sys.exit(1)
    else:
        print("\n*** ALL TESTS PASSED — GAME IS NAVIGABLE ***")

finally:
    client.quit()
