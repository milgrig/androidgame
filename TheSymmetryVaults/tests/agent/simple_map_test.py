"""Simple test: Does pressing Start load MapScene?"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=20.0)
client.start()

print("1. Waiting for main menu...")
time.sleep(4)

print("2. Finding Start button...")
tree = client.get_tree()
buttons = client.find_buttons(tree)
print(f"   Found {len(buttons)} buttons")

start_btn = next((b for b in buttons if 'Start' in b.get('name', '')), None)

if start_btn:
    print(f"3. Pressing: {start_btn['name']}")
    client.press_button(start_btn['path'])

    print("4. Waiting 5 seconds for transition...")
    time.sleep(5)

    print("5. Checking current scene...")
    tree2 = client.get_tree()

    children = tree2.get('children', [])
    print(f"   Root has {len(children)} children")

    for child in children:
        name = child.get('name', '?')
        script = child.get('script_class', '')
        cls = child.get('class', '?')
        print(f"   - {name}: {script or cls}")

    # Check specifically for MapScene
    map_node = next((c for c in children if 'Map' in c.get('script_class', '')), None)

    if map_node:
        print("\n✓ SUCCESS: MapScene loaded!")
        print(f"   Path: {map_node.get('path', 'unknown')}")
    else:
        print("\n? MapScene not detected")
        print("   Still on MainMenu or something else")
else:
    print("✗ Start button not found")

client.quit()
