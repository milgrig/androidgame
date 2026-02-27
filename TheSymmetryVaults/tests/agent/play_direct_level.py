"""
Play level 1 by starting directly with it loaded.
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from agent_client import AgentClient

GODOT_PATH = "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

print("="*70)
print(" PLAYING THE SYMMETRY VAULTS - DIRECT LEVEL LOAD")
print("="*70)

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)

print("\n[INIT] Starting game with level_01 pre-loaded...")
# Start with level_id parameter - this loads the level immediately
client.start(level_id="level_01")

print("\n[STEP 1] Checking game state...")
state = client.get_state()
level = state.get('level', {})
print(f"  Level ID: {level.get('id', 'unknown')}")
print(f"  Group: {level.get('group_name', 'unknown')}")
print(f"  Total symmetries: {state.get('total_symmetries', 0)}")
print(f"  Crystals: {len(state.get('crystals', []))}")
print(f"  Keys found: {state['keyring']['found_count']}/{state['keyring']['total']}")

print("\n[STEP 2] Finding symmetry #1 - Identity [0,1,2]...")
resp1 = client.submit_permutation([0, 1, 2])
events1 = resp1.get('events', [])
sym1 = [e for e in events1 if e['type'] == 'symmetry_found']
print(f"  Symmetries found: {len(sym1)}")
if sym1:
    print("  ✓ Identity recognized!")

state = client.get_state()
print(f"  Keys: {state['keyring']['found_count']}/{state['keyring']['total']}")

print("\n[STEP 3] Finding symmetry #2 - Rotation [1,2,0]...")
resp2 = client.submit_permutation([1, 2, 0])
events2 = resp2.get('events', [])
sym2 = [e for e in events2 if e['type'] == 'symmetry_found']
print(f"  Symmetries found: {len(sym2)}")
if sym2:
    print("  ✓ Rotation 120deg recognized!")

state = client.get_state()
print(f"  Keys: {state['keyring']['found_count']}/{state['keyring']['total']}")

print("\n[STEP 4] Finding symmetry #3 - Rotation [2,0,1]...")
resp3 = client.submit_permutation([2, 0, 1])
events3 = resp3.get('events', [])
sym3 = [e for e in events3 if e['type'] == 'symmetry_found']
completed = [e for e in events3 if e['type'] == 'level_completed']
print(f"  Symmetries found: {len(sym3)}")
print(f"  Level completed events: {len(completed)}")

if sym3:
    print("  ✓ Rotation 240deg recognized!")
if completed:
    print("  ✓✓✓ LEVEL COMPLETED! ✓✓✓")

state = client.get_state()
print(f"  Keys: {state['keyring']['found_count']}/{state['keyring']['total']}")
print(f"  Complete: {state['keyring'].get('complete', False)}")

print("\n[STEP 5] Testing invalid permutation [1,0,2]...")
resp_inv = client.submit_permutation([1, 0, 2])
events_inv = resp_inv.get('events', [])
invalid = [e for e in events_inv if e['type'] == 'invalid_attempt']
print(f"  Invalid events: {len(invalid)}")
if invalid:
    print("  ✓ Invalid correctly rejected!")

print("\n" + "="*70)
print(" TEST SUMMARY")
print("="*70)

passed = []
failed = []

if len(sym1) == 1:
    passed.append("Identity found")
else:
    failed.append("Identity NOT found")

if len(sym2) == 1:
    passed.append("Rotation 120 found")
else:
    failed.append("Rotation 120 NOT found")

if len(sym3) == 1:
    passed.append("Rotation 240 found")
else:
    failed.append("Rotation 240 NOT found")

if len(completed) == 1:
    passed.append("Level completed")
else:
    failed.append("Level NOT completed")

if len(invalid) == 1:
    passed.append("Invalid rejected")
else:
    failed.append("Invalid NOT rejected")

print(f"\nPASSED ({len(passed)}):")
for p in passed:
    print(f"  ✓ {p}")

if failed:
    print(f"\nFAILED ({len(failed)}):")
    for f in failed:
        print(f"  ✗ {f}")

success = len(failed) == 0
print(f"\nOVERALL: {'ALL TESTS PASSED!' if success else 'Some tests failed'}")

client.quit()
exit(0 if success else 1)
