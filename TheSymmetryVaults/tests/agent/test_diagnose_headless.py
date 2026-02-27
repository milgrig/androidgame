"""
Diagnostic test: does MainMenu create buttons in headless mode?
"""
import sys, os, time, json
sys.path.insert(0, os.path.dirname(__file__))
os.environ["PYTHONIOENCODING"] = "utf-8"
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = os.path.join(os.path.dirname(__file__), "..", "..")

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)

try:
    print("=== Starting Godot headless ===")
    hello = client.start()

    # Wait for everything to settle
    time.sleep(4)

    # 1. Raw get_node for ButtonContainer
    print("\n=== RAW get_node ButtonContainer ===")
    try:
        raw = client._send_command("get_node", {"path": "/root/MainMenu/ButtonContainer"})
        print(json.dumps(raw, indent=2, ensure_ascii=False, default=str))
    except Exception as e:
        print(f"  ERROR: {e}")

    # 2. Raw get_node for StartButton
    print("\n=== RAW get_node StartButton ===")
    try:
        raw = client._send_command("get_node", {"path": "/root/MainMenu/ButtonContainer/StartButton"})
        print(json.dumps(raw, indent=2, ensure_ascii=False, default=str))
    except Exception as e:
        print(f"  ERROR: {e}")

    # 3. Raw get_tree max_depth=5 for MainMenu subtree
    print("\n=== RAW get_tree /root/MainMenu depth=5 ===")
    try:
        raw = client._send_command("get_tree", {"root": "/root/MainMenu", "max_depth": 5})
        print(json.dumps(raw, indent=2, ensure_ascii=False, default=str))
    except Exception as e:
        print(f"  ERROR: {e}")

    # 4. list_actions raw
    print("\n=== RAW list_actions ===")
    try:
        raw = client._send_command("list_actions", {})
        print(json.dumps(raw, indent=2, ensure_ascii=False, default=str))
    except Exception as e:
        print(f"  ERROR: {e}")

    # 5. Try press_button directly
    print("\n=== press_button /root/MainMenu/ButtonContainer/StartButton ===")
    try:
        raw = client._send_command("press_button", {"path": "/root/MainMenu/ButtonContainer/StartButton"})
        print(json.dumps(raw, indent=2, ensure_ascii=False, default=str))
    except Exception as e:
        print(f"  ERROR: {e}")

    time.sleep(2)

    # 6. After pressing — where are we?
    print("\n=== After button press: get_tree root depth=2 ===")
    try:
        raw = client._send_command("get_tree", {"max_depth": 2})
        children = raw.get("tree", raw.get("data", {})).get("children", [])
        if not children:
            children = raw.get("children", [])
        for c in children:
            name = c.get("name", "?")
            cls = c.get("script_class", c.get("class", "?"))
            print(f"  {name} ({cls})")
    except Exception as e:
        print(f"  ERROR: {e}")

    # 7. Try load_level directly
    print("\n=== load_level level_01 ===")
    try:
        raw = client._send_command("load_level", {"level_id": "level_01"})
        print(f"  ok: {raw.get('ok')}")
        print(f"  keys: {list(raw.get('data', {}).keys()) if raw.get('data') else 'no data'}")
    except Exception as e:
        print(f"  ERROR: {e}")

    time.sleep(1)

    # 8. get_state
    print("\n=== get_state ===")
    try:
        state = client.get_state()
        print(f"  level_id: {state.get('level_id', '?')}")
        print(f"  crystals: {len(state.get('crystals', []))}")
        print(f"  total_symmetries: {state.get('total_symmetries', '?')}")
        print(f"  is_shuffled: {state.get('is_shuffled', '?')}")
    except Exception as e:
        print(f"  ERROR: {e}")

    # 9. list_actions in level
    print("\n=== list_actions in level ===")
    try:
        raw = client._send_command("list_actions", {})
        for a in raw.get("data", {}).get("actions", raw.get("actions", [])):
            if a.get("action") == "press_button":
                path = a.get("path", "?")
                label = a.get("label", "?")
                print(f"  BUTTON: {path} -> {label}")
    except Exception as e:
        print(f"  ERROR: {e}")

finally:
    client.quit()
    print("\n=== Done ===")
