"""Check if buttons are now created after fix."""

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

import time
print("Waiting 4 seconds for animation...")
time.sleep(4)

tree = client.get_tree()
buttons = client.find_buttons(tree)

print(f"\nBUTTONS FOUND: {len(buttons)}")
for i, btn in enumerate(buttons, 1):
    name = btn.get('name', 'unknown')
    text = btn.get('text', '')
    disabled = btn.get('disabled', False)
    print(f"  {i}. {name}: '{text}' (disabled={disabled})")

if len(buttons) >= 3:
    print("\n✓✓✓ SUCCESS! All buttons are now being created! ✓✓✓")
else:
    print(f"\n✗ FAIL: Expected 3 buttons, found {len(buttons)}")

# Save evidence
with open("buttons_after_fix.json", "w", encoding="utf-8") as f:
    json.dump(buttons, f, indent=2, ensure_ascii=False)

print("\nEvidence saved to: buttons_after_fix.json")

client.quit()
