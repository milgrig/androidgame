"""Just click Start and see what happens - minimal test."""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

print("Starting game...")
client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=20.0)
client.start()

print("Waiting for UI...")
time.sleep(4)

print("Pressing Start button...")
tree = client.get_tree()
buttons = client.find_buttons(tree)
start = next((b for b in buttons if 'Start' in b.get('name', '')), None)

if start:
    client.press_button(start['path'])
    print("Button pressed!")

    print("Waiting 5 seconds...")
    time.sleep(5)

    print("Checking scene...")
    tree2 = client.get_tree()
    children = [c.get('name') for c in tree2.get('children', [])]
    print(f"Top nodes: {children}")

    if 'MapScene' in str(children) or any('Map' in str(c) for c in children):
        print("\n✓ Map loaded!")
    else:
        print(f"\n? Still on: {children}")

client.quit()
print("\nCheck agent_cmd.jsonl and agent_resp.jsonl for details")
