"""Quick test to verify UI appears after animation."""

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

print("Waiting 4 seconds for UI animation to complete...")
time.sleep(4)

tree = client.get_tree()
buttons = client.find_buttons(tree)

print(f"\nFound {len(buttons)} buttons:")
for btn in buttons:
    print(f"  - {btn['name']}: '{btn.get('text', '')}' (path: {btn['path']})")

if len(buttons) >= 3:
    print("\n✓ SUCCESS: All buttons appeared after animation")
else:
    print(f"\n✗ FAIL: Expected 3 buttons, found {len(buttons)}")

client.quit()
