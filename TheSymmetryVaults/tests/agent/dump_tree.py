"""Dump scene tree to JSON."""

import os
import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
client.start()

tree = client.get_tree()
buttons = client.find_buttons(tree)
labels = client.find_labels(tree)
actions = client.list_actions()
levels = client.list_levels()

data = {
    "tree": tree,
    "buttons": buttons,
    "labels": labels,
    "actions": actions,
    "levels": levels[:10]
}

with open("scene_dump.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print("Saved to scene_dump.json")

client.quit()
