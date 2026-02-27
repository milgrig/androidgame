"""
Play through level 1 - complete gameplay test!
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
print(" PLAYING THE SYMMETRY VAULTS - LEVEL 01")
print("="*70)

client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
client.start()

print("\n[STEP 1] Loading Level 01...")
result = client.load_level("level_01")
print(f"  Loaded: {result.get('loaded', False)}")

print("\n[STEP 2] Getting game state...")
state = client.get_state()
level = state.get('level', {})
print(f"  Level ID: {level.get('id', 'unknown')}")
print(f"  Group: {level.get('group_name', 'unknown')}")
print(f"  Total symmetries: {state.get('total_symmetries', 0)}")
print(f"  Crystals: {len(state.get('crystals', []))}")
print(f"  Keys found: {state['keyring']['found_count']}/{state['keyring']['total']}")

print("\n[STEP 3] Finding symmetry #1 - Identity [0,1,2]...")
resp1 = client.submit_permutation([0, 1, 2])
events1 = resp1.get('events', [])
sym1 = [e for e in events1 if e['type'] == 'symmetry_found']
print(f"  Events received: {len(events1)}")
print(f"  Symmetries found: {len(sym1)}")
if sym1:
    print("  SUCCESS - Identity is a symmetry!")
else:
    print("  FAILED - Identity not recognized")

# Check state after
state = client.get_state()
print(f"  Keys now: {state['keyring']['found_count']}/{state['keyring']['total']}")

print("\n[STEP 4] Finding symmetry #2 - Rotation 120deg [1,2,0]...")
resp2 = client.submit_permutation([1, 2, 0])
events2 = resp2.get('events', [])
sym2 = [e for e in events2 if e['type'] == 'symmetry_found']
print(f"  Events received: {len(events2)}")
print(f"  Symmetries found: {len(sym2)}")
if sym2:
    print("  SUCCESS - 120deg rotation is a symmetry!")
else:
    print("  FAILED - Rotation not recognized")

state = client.get_state()
print(f"  Keys now: {state['keyring']['found_count']}/{state['keyring']['total']}")

print("\n[STEP 5] Finding symmetry #3 - Rotation 240deg [2,0,1]...")
resp3 = client.submit_permutation([2, 0, 1])
events3 = resp3.get('events', [])
sym3 = [e for e in events3 if e['type'] == 'symmetry_found']
completed = [e for e in events3 if e['type'] == 'level_completed']
print(f"  Events received: {len(events3)}")
print(f"  Symmetries found: {len(sym3)}")
print(f"  Level completed: {len(completed) > 0}")

if sym3:
    print("  SUCCESS - 240deg rotation is a symmetry!")
if completed:
    print("  LEVEL COMPLETED!!!")

state = client.get_state()
keyring = state.get('keyring', {})
print(f"  Keys now: {keyring['found_count']}/{keyring['total']}")
print(f"  Keyring complete: {keyring.get('complete', False)}")

print("\n[STEP 6] Testing invalid permutation [1,0,2]...")
resp_invalid = client.submit_permutation([1, 0, 2])
events_invalid = resp_invalid.get('events', [])
invalid = [e for e in events_invalid if e['type'] == 'invalid_attempt']
print(f"  Events received: {len(events_invalid)}")
print(f"  Invalid attempts: {len(invalid)}")
if invalid:
    print("  SUCCESS - Invalid permutation correctly rejected!")

print("\n" + "="*70)
print(" GAMEPLAY TEST COMPLETE")
print("="*70)

# Summary
print("\nRESULTS:")
print(f"  - Found identity: {'YES' if sym1 else 'NO'}")
print(f"  - Found rotation 120: {'YES' if sym2 else 'NO'}")
print(f"  - Found rotation 240: {'YES' if sym3 else 'NO'}")
print(f"  - Level completed: {'YES' if completed else 'NO'}")
print(f"  - Invalid rejected: {'YES' if invalid else 'NO'}")

all_tests_passed = len(sym1) == 1 and len(sym2) == 1 and len(sym3) == 1 and len(completed) == 1 and len(invalid) == 1

if all_tests_passed:
    print("\n  OVERALL: ALL TESTS PASSED!")
else:
    print("\n  OVERALL: Some tests failed")

client.quit()

exit(0 if all_tests_passed else 1)
