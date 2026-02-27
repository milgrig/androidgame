"""Test pressing Start Game button."""

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

# Find and press start button
tree = client.get_tree()
buttons = client.find_buttons(tree)

start_btn = next((b for b in buttons if 'Start' in b.get('name', '')), None)

if start_btn:
    path = start_btn['path']

    # Save result to file instead of printing
    result = client.press_button(path)
    with open("button_press_result.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    time.sleep(2)

    # Check what happened
    tree_after = client.get_tree()

    with open("scene_after_start.json", "w", encoding="utf-8") as f:
        json.dump(tree_after, f, indent=2, ensure_ascii=False)

    # Simple check
    root_name = tree_after.get('name', 'unknown')
    root_script = tree_after.get('script_class', tree_after.get('class', 'unknown'))

    report = {
        "button_pressed": path,
        "scene_after": {
            "root_name": root_name,
            "root_script": root_script,
            "children_count": len(tree_after.get('children', []))
        },
        "success": True
    }

    with open("start_game_report.json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print("DONE - Check start_game_report.json")
else:
    print("Start button not found")

client.quit()
