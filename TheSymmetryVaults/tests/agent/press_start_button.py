"""Press the Start Game button and see what happens."""

import os
import sys
import time
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

print("Starting game...")
client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
client.start()

print("Waiting for UI...")
time.sleep(4)

print("\nFinding Start button...")
tree = client.get_tree()
buttons = client.find_buttons(tree)

start_button = None
for btn in buttons:
    name = btn.get('name', '')
    if 'Start' in name or 'start' in name.lower():
        start_button = btn
        print(f"Found: {btn['path']}")
        break

if start_button:
    print(f"\nPressing button: {start_button['path']}")
    result = client.press_button(start_button['path'])
    print(f"Result: {result}")

    print("\nWaiting for transition...")
    time.sleep(2)

    print("\nChecking new scene...")
    tree_after = client.get_tree()

    # Save to file
    with open("scene_after_start.json", "w", encoding="utf-8") as f:
        json.dump(tree_after, f, indent=2, ensure_ascii=False)

    print(f"Scene root: {tree_after.get('name', 'unknown')}")
    print(f"Scene class: {tree_after.get('class', 'unknown')}")
    print(f"Script class: {tree_after.get('script_class', 'none')}")

    # Check for world map or level scene
    children = tree_after.get('children', [])
    print(f"\nTop-level nodes ({len(children)}):")
    for child in children[:10]:
        print(f"  - {child.get('name', '?')} ({child.get('script_class', child.get('class', '?'))})")

    print("\nScene saved to: scene_after_start.json")
else:
    print("Start button not found!")

client.quit()
