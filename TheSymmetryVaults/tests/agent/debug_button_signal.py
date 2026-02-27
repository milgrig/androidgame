"""Debug: Is the button signal connected?"""

import os
import sys
import time
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
client.start()

time.sleep(4)

# Get detailed node info for StartButton
try:
    btn_info = client.get_node("/root/MainMenu/ButtonContainer/StartButton")

    with open("button_debug.json", "w", encoding="utf-8") as f:
        json.dump(btn_info, f, indent=2, ensure_ascii=False)

    print("Button info:")
    print(f"  Name: {btn_info.get('name', '?')}")
    print(f"  Class: {btn_info.get('class', '?')}")
    print(f"  Disabled: {btn_info.get('disabled', '?')}")
    print(f"  Visible: {btn_info.get('visible', '?')}")

    signals = btn_info.get('signals', [])
    print(f"\n  Signals ({len(signals)}):")
    for sig in signals:
        name = sig.get('name', '?')
        connections = sig.get('connections', 0)
        print(f"    - {name}: {connections} connections")

    pressed_signal = next((s for s in signals if s['name'] == 'pressed'), None)
    if pressed_signal:
        if pressed_signal['connections'] > 0:
            print("\n✓ 'pressed' signal IS connected!")
        else:
            print("\n✗ 'pressed' signal has NO connections!")
    else:
        print("\n? 'pressed' signal not found")

except Exception as e:
    print(f"Error: {e}")

client.quit()
