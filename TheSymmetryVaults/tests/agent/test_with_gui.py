"""
Test with GUI window open - you can see what's happening!
This launches Godot with a visible window AND Agent Bridge.
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

# Use regular Godot (with window), not console version
GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

print("="*60)
print("LAUNCHING GAME WITH VISIBLE WINDOW")
print("You can watch what happens!")
print("="*60)

client = AgentClient(
    godot_path=GODOT_PATH,
    project_path=PROJECT_PATH,
    timeout=20.0,
)

print("\n[1] Starting Godot with GUI window...")
# Start - this will open a visible window
client.start()

print("[2] Waiting 5 seconds for you to see the main menu...")
print("    (Look for the Godot window!)")
time.sleep(5)

print("\n[3] Checking what's on screen...")
tree = client.get_tree()
buttons = client.find_buttons(tree)
print(f"    Buttons visible: {len(buttons)}")
for btn in buttons:
    print(f"      - {btn.get('name', '?')}")

if buttons:
    start_btn = next((b for b in buttons if 'Start' in b.get('name', '')), None)

    if start_btn:
        print(f"\n[4] Clicking '{start_btn['name']}' button...")
        print("    WATCH THE WINDOW - button should be clicked!")

        client.press_button(start_btn['path'])

        print("\n[5] Waiting 3 seconds to see what happens...")
        time.sleep(3)

        print("\n[6] Checking new scene...")
        tree2 = client.get_tree()
        children = tree2.get('children', [])

        print(f"    Current scene has {len(children)} top-level nodes:")
        for child in children[:10]:
            name = child.get('name', '?')
            script = child.get('script_class', child.get('class', '?'))
            print(f"      - {name} ({script})")

        # Check for MapScene
        map_node = next((c for c in children if 'Map' in c.get('script_class', '')), None)

        if map_node:
            print("\n✓✓✓ SUCCESS! MapScene loaded!")
            print(f"    You should see the world map in the window!")
        else:
            print("\n? Still on MainMenu or different scene")
            print("  Check the Godot window to see what happened")
    else:
        print("\n✗ Start button not found")
else:
    print("\n✗ No buttons found!")

print("\n[7] Leaving window open for 10 seconds so you can see...")
print("    Press Ctrl+C to close early")
time.sleep(10)

print("\n[8] Closing game...")
client.quit()

print("\nDone! Did you see the window? Did the button click work?")
