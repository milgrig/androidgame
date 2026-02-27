"""Critic evaluation script for The Symmetry Vaults."""
import sys
import json
import time
sys.path.insert(0, 'tests/agent')
from agent_client import AgentClient

GODOT_PATH = r'C:\Godot\Godot_v4.6.1-stable_win64_console.exe'
PROJECT_PATH = r'C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults'

def main():
    print("=== CRITIC EVALUATION ===\n")
    client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=20.0)

    try:
        # Start
        client.start()
        time.sleep(2)

        # List levels
        levels = client.list_levels()
        print(f"Available levels: {len(levels)}")
        print(f"Levels: {levels}\n")

        if levels:
            # Load first level
            first_level = levels[0]
            print(f"Loading level: {first_level}")
            client.load_level(first_level)
            time.sleep(2)

            # Get state
            state = client.get_state()
            print("\n=== LEVEL STATE ===")
            print(f"Scene: {state.get('scene_name', 'unknown')}")
            print(f"Level ID: {state.get('level_id', 'none')}")
            print(f"Crystals: {len(state.get('crystals', []))}")
            print(f"Edges: {len(state.get('edges', []))}")

            # Get UI
            buttons = client.find_buttons()
            labels = client.find_labels()

            print("\n=== UI ELEMENTS ===")
            print(f"Buttons: {len(buttons)}")
            for btn in buttons:
                print(f"  - '{btn.get('text', '')}' ({btn.get('name', '')})")

            print(f"\nLabels (first 15):")
            for lbl in labels[:15]:
                text = lbl.get('text', '').strip()
                name = lbl.get('name', '')
                if text and len(text) < 50:
                    print(f"  - '{text}' ({name})")

            # Tree analysis
            tree = client.get_tree()
            print(f"\n=== SCENE TREE ===")
            print(f"Total nodes: {len(tree)}")

            # Node types
            node_types = {}
            for node in tree:
                node_type = node.get('type', 'Unknown')
                node_types[node_type] = node_types.get(node_type, 0) + 1

            print("\nNode types (top 10):")
            for ntype, count in sorted(node_types.items(), key=lambda x: -x[1])[:10]:
                print(f"  {ntype}: {count}")

            # Visual nodes
            crystal_nodes = [n for n in tree if 'Crystal' in n.get('type', '') or 'crystal' in n.get('name', '').lower()]
            print(f"\nCrystal nodes: {len(crystal_nodes)}")

            visual_nodes = [n for n in tree if any(x in n.get('type', '') for x in ['Sprite', 'MeshInstance', 'Polygon', 'ColorRect', 'Panel'])]
            print(f"Visual rendering nodes: {len(visual_nodes)}")

            # Try a swap to test responsiveness
            print("\n=== TESTING INTERACTION ===")
            crystals = state.get('crystals', [])
            if len(crystals) >= 2:
                print(f"Initial arrangement: {[c['id'] for c in crystals]}")
                result = client.swap(0, 1)
                print(f"Swap result: {result.get('status', 'unknown')}")

                new_state = client.get_state()
                new_crystals = new_state.get('crystals', [])
                print(f"After swap: {[c['id'] for c in new_crystals]}")

    finally:
        client.quit()
        print("\n=== DONE ===")

if __name__ == "__main__":
    main()
