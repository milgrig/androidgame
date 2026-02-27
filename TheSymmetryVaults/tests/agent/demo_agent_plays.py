#!/usr/bin/env python3
"""
Demo: AI Agent plays through Level 1 of The Symmetry Vaults.

This script shows the complete agent workflow:
1. Start Godot in headless mode
2. Explore the "DOM" — see what's on screen
3. Read game state
4. Find all symmetries systematically
5. Verify level completion

Usage:
    python demo_agent_plays.py
    python demo_agent_plays.py --godot-path /path/to/godot
    GODOT_PATH=godot python demo_agent_plays.py

This serves as both documentation and a smoke test.
"""

import argparse
import os
import sys
from pathlib import Path

# Add parent dir for import
sys.path.insert(0, str(Path(__file__).parent))

from agent_client import AgentClient


def main():
    parser = argparse.ArgumentParser(description="AI Agent plays The Symmetry Vaults")
    parser.add_argument("--godot-path", default=os.environ.get("GODOT_PATH", "godot"),
                        help="Path to Godot executable")
    parser.add_argument("--level", default="level_01",
                        help="Level to play (default: level_01)")
    args = parser.parse_args()

    print("=" * 60)
    print("  The Symmetry Vaults — AI Agent Demo")
    print("=" * 60)
    print()

    client = AgentClient(godot_path=args.godot_path)

    try:
        # ── Step 1: Start and handshake ──
        print("[1] Starting Godot in headless agent mode...")
        hello = client.start(level_id=args.level)
        print(f"    Protocol: v{hello['version']}")
        print(f"    Game: {hello['game']}")
        print(f"    Commands available: {len(hello['commands'])}")
        print()

        # ── Step 2: See the DOM ──
        print("[2] Scene tree (like browser DOM):")
        print("-" * 40)
        tree = client.get_tree()
        client.print_tree(tree)
        print()

        # ── Step 3: Read game state ──
        print("[3] Game state:")
        print("-" * 40)
        state = client.get_state()

        print(f"    Level: {state['level']['title']} ({state['level']['id']})")
        print(f"    Group: {state['level'].get('group_name', '?')}")
        print()

        print("    Crystals:")
        for c in state["crystals"]:
            print(f"      [{c['id']}] color={c['color']}, label={c['label']}, "
                  f"draggable={c['draggable']}, pos={c['position']}")

        print()
        print("    Edges:")
        for e in state["edges"]:
            print(f"      {e['from']} --({e['type']})-- {e['to']}")

        print()
        print(f"    Arrangement: {state['arrangement']}")
        print(f"    Keyring: {state['keyring']['found_count']} / {state['keyring']['total']}")
        print()

        # ── Step 4: See what actions are available ──
        print("[4] Available actions:")
        print("-" * 40)
        actions = client.list_actions()
        for a in actions:
            print(f"    {a['action']}: {a['description']}")
        print()

        # ── Step 5: Play! Find all symmetries ──
        print("[5] Playing — finding all symmetries of Z3:")
        print("-" * 40)

        # The Z3 group has 3 elements:
        #   identity: [0, 1, 2]
        #   rotation 120°: [1, 2, 0]
        #   rotation 240°: [2, 0, 1]

        symmetries = [
            ([0, 1, 2], "Identity (e)"),
            ([1, 2, 0], "Rotation 120° (r)"),
            ([2, 0, 1], "Rotation 240° (r²)"),
        ]

        for mapping, name in symmetries:
            print(f"    Submitting {name}: {mapping}")
            resp = client.submit_permutation(mapping)
            events = resp.get("events", [])

            for event in events:
                etype = event["type"]
                if etype == "symmetry_found":
                    print(f"    [OK] Symmetry found! (sym_id: {event['data']['sym_id']})")
                elif etype == "level_completed":
                    print(f"    [***] LEVEL COMPLETED! [***]")
                elif etype == "invalid_attempt":
                    print(f"    [X] Invalid attempt")

        print()

        # ── Step 6: Verify final state ──
        print("[6] Final state:")
        print("-" * 40)
        state = client.get_state()
        print(f"    Keyring: {state['keyring']['found_count']} / {state['keyring']['total']}")
        print(f"    Complete: {state['keyring']['complete']}")
        print(f"    Has identity: {state['keyring']['has_identity']}")
        print(f"    Closed under composition: {state['keyring']['is_closed']}")
        print(f"    Has inverses: {state['keyring']['has_inverses']}")
        print()

        # Check HUD updated
        labels = client.find_labels()
        counter = next((l for l in labels if l["name"] == "CounterLabel"), None)
        if counter:
            print(f"    HUD counter: \"{counter['text']}\"")
        hint = next((l for l in labels if l["name"] == "HintLabel"), None)
        if hint and hint.get("text"):
            print(f"    HUD hint: \"{hint['text']}\"")

        print()
        print("=" * 60)
        print("  Demo complete! Agent successfully played through Level 1.")
        print("=" * 60)

    except Exception as e:
        print(f"\n[ERROR] {type(e).__name__}: {e}")
        sys.exit(1)

    finally:
        print("\nShutting down Godot...")
        client.quit()
        print("Done.")


if __name__ == "__main__":
    main()
