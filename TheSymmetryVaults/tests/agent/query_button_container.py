"""Query ButtonContainer specifically."""

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

# Query ButtonContainer node specifically
try:
    btn_container = client.get_node("/root/MainMenu/ButtonContainer")
    print("ButtonContainer node:")
    print(json.dumps(btn_container, indent=2, ensure_ascii=False))
except Exception as e:
    print(f"Error querying ButtonContainer: {e}")

# Get detailed tree of MainMenu only
try:
    tree = client.get_tree(root="/root/MainMenu", max_depth=5)
    with open("mainmenu_tree.json", "w", encoding="utf-8") as f:
        json.dump(tree, f, indent=2, ensure_ascii=False)
    print("\nSaved MainMenu tree to mainmenu_tree.json")
except Exception as e:
    print(f"Error getting tree: {e}")

client.quit()
