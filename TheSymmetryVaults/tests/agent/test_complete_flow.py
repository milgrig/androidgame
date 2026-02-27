"""Complete gameplay flow test - from menu to playing a level."""

import os
import sys
import time
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

def save_json(filename, data):
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=20.0)
client.start()

report = []

# Step 1: Wait for main menu
report.append("=== STEP 1: Main Menu ===")
time.sleep(4)

tree = client.get_tree()
buttons = client.find_buttons(tree)
report.append(f"Buttons found: {len(buttons)}")

# Step 2: Press Start
start_btn = next((b for b in buttons if 'Start' in b.get('name', '')), None)
if start_btn:
    report.append(f"Pressing: {start_btn['path']}")
    result = client.press_button(start_btn['path'])
    report.append("Button pressed!")

    # Step 3: Wait for scene change
    report.append("\n=== STEP 2: Waiting for Scene Transition ===")
    time.sleep(3)

    tree2 = client.get_tree()
    root_name = tree2.get('name', 'unknown')
    report.append(f"Root: {root_name}")

    children = tree2.get('children', [])
    report.append(f"Children: {len(children)}")

    for child in children[:5]:
        name = child.get('name', '?')
        script = child.get('script_class', child.get('class', '?'))
        report.append(f"  - {name} ({script})")

    # Check if MapScene loaded
    map_scene = next((c for c in children if c.get('script_class') == 'MapScene'), None)

    if map_scene:
        report.append("\n✓ SUCCESS: Map scene loaded!")
        report.append(f"Map node: {map_scene.get('path', 'unknown')}")
    else:
        report.append("\n? Map scene not found, trying to load level directly...")

        # Step 4: Try loading level directly
        report.append("\n=== STEP 3: Load Level Directly ===")
        load_result = client.load_level("level_01")
        report.append(f"Level loaded: {load_result.get('loaded', False)}")

        if load_result.get('loaded'):
            state = client.get_state()
            report.append(f"Level ID: {state['level']['id']}")
            report.append(f"Symmetries: {state['total_symmetries']}")

            # Step 5: Play!
            report.append("\n=== STEP 4: Playing Level 01 ===")

            report.append("Submitting [0,1,2]...")
            resp1 = client.submit_permutation([0, 1, 2])
            events1 = resp1.get('events', [])
            sym1 = len([e for e in events1 if e['type'] == 'symmetry_found'])
            report.append(f"  Symmetries found: {sym1}")

            report.append("Submitting [1,2,0]...")
            resp2 = client.submit_permutation([1, 2, 0])
            events2 = resp2.get('events', [])
            sym2 = len([e for e in events2 if e['type'] == 'symmetry_found'])
            report.append(f"  Symmetries found: {sym2}")

            report.append("Submitting [2,0,1]...")
            resp3 = client.submit_permutation([2, 0, 1])
            events3 = resp3.get('events', [])
            sym3 = len([e for e in events3 if e['type'] == 'symmetry_found'])
            completed = len([e for e in events3 if e['type'] == 'level_completed'])
            report.append(f"  Symmetries found: {sym3}")
            report.append(f"  Level completed: {completed > 0}")

            if completed > 0:
                report.append("\n✓✓✓ LEVEL COMPLETED! ✓✓✓")
else:
    report.append("✗ Start button not found!")

# Save report
save_json("complete_flow_report.json", report)

# Print report
for line in report:
    print(line)

client.quit()
