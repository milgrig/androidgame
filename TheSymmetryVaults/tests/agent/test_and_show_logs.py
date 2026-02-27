"""Test and capture Godot logs to see what's happening."""

import os
import sys
import time
import subprocess
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

print("Starting Godot and capturing logs...")
print("="*60)

# Start Godot with console output visible
cmd = [
    GODOT_PATH,
    "--path", PROJECT_PATH,
    "--",
    "--agent-mode",
]

# Run with output capture
process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding='utf-8',
    errors='replace'
)

# Give it time to start
time.sleep(3)

# Now use agent client
from agent_client import AgentClient

client = AgentClient(
    godot_path=GODOT_PATH,
    project_path=PROJECT_PATH,
    timeout=20.0,
)

# We already started manually, so connect to existing instance
print("\n[1] Waiting for main menu...")
time.sleep(2)

print("[2] Finding Start button...")
try:
    tree = client.get_tree()
    buttons = client.find_buttons(tree)
    print(f"    Found {len(buttons)} buttons")

    if buttons:
        start_btn = next((b for b in buttons if 'Start' in b.get('name', '')), None)
        if start_btn:
            print(f"\n[3] Pressing Start button...")
            client.press_button(start_btn['path'])

            print("[4] Waiting for scene change...")
            time.sleep(3)

            print("\n[5] Checking scene...")
            tree2 = client.get_tree()
            children = tree2.get('children', [])
            print(f"    Scene nodes: {[c.get('name') for c in children]}")
except Exception as e:
    print(f"Error: {e}")

print("\n[6] Reading Godot logs...")
print("="*60)

# Kill process and get output
process.terminate()
stdout, stderr = process.communicate(timeout=5)

print("STDERR (errors and debug):")
print(stderr[-2000:] if len(stderr) > 2000 else stderr)  # Last 2000 chars

print("\nDone!")
