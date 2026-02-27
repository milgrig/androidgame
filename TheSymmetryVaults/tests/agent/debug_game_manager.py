"""Debug GameManager state."""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
client.start()
time.sleep(2)

# Get GameManager node
try:
    gm = client.get_node("/root/GameManager")
    print("GameManager node info:")
    print(f"  Name: {gm.get('name', 'N/A')}")
    print(f"  Class: {gm.get('class', 'N/A')}")
    print(f"  Script: {gm.get('script_class', 'N/A')}")

    # Check properties
    if 'properties' in gm:
        print("\n  Properties:")
        for key, val in gm.get('properties', {}).items():
            if key in ['hall_tree', 'progression', 'level_registry']:
                print(f"    {key}: {val}")

    # Check children
    children = gm.get('children', [])
    print(f"\n  Children: {len(children)}")
    for child in children:
        print(f"    - {child.get('name', '?')} ({child.get('class', '?')})")

except Exception as e:
    print(f"Error getting GameManager: {e}")

client.quit()
