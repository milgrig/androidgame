"""Dump scene tree after waiting for animation."""

import os
import sys
import json
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
client.start()

print("Waiting 4 seconds...")
time.sleep(4)

tree = client.get_tree()

with open("scene_dump_after_wait.json", "w", encoding="utf-8") as f:
    json.dump(tree, f, indent=2, ensure_ascii=False)

print("Saved to scene_dump_after_wait.json")

client.quit()
