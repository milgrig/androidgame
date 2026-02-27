"""
Quick exploration script to see what's actually in the game.
"""

import os
import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from agent_client import AgentClient

GODOT_PATH = os.environ.get(
    "GODOT_PATH",
    "C:/Users/Xaser/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.1-stable_win64_console.exe"
)
PROJECT_PATH = str(Path(__file__).resolve().parents[2])

def safe_print(text):
    """Print with UTF-8 encoding to avoid Windows console issues."""
    try:
        print(text)
    except UnicodeEncodeError:
        print(text.encode('utf-8', errors='replace').decode('utf-8', errors='replace'))

def print_node(node, indent=0, max_depth=5):
    """Print node info safely."""
    if indent > max_depth:
        return

    prefix = "  " * indent
    name = node.get("name", "?")
    node_class = node.get("class", "?")
    script_class = node.get("script_class", "")

    # Build info
    info_parts = []
    if "text" in node:
        text = node["text"]
        if text:
            info_parts.append(f'text="{text}"')
    if "disabled" in node:
        info_parts.append(f"disabled={node['disabled']}")
    if "visible" in node and not node["visible"]:
        info_parts.append("HIDDEN")

    info_str = f" [{', '.join(info_parts)}]" if info_parts else ""
    line = f"{prefix}{name} ({script_class or node_class}){info_str}"

    safe_print(line)

    for child in node.get("children", []):
        print_node(child, indent + 1, max_depth)

def explore_initial_state():
    """Explore what the game looks like on initial start."""
    client = AgentClient(
        godot_path=GODOT_PATH,
        project_path=PROJECT_PATH,
        timeout=15.0,
    )

    safe_print("Starting Godot...")
    client.start()

    safe_print("\n=== SCENE TREE ===")
    tree = client.get_tree()
    print_node(tree, max_depth=6)

    safe_print("\n=== BUTTONS ===")
    buttons = client.find_buttons(tree)
    for btn in buttons:
        text = btn.get('text', '')
        path = btn['path']
        disabled = btn.get('disabled', False)
        safe_print(f"  {path}: '{text}' (disabled={disabled})")

    safe_print("\n=== LABELS ===")
    labels = client.find_labels(tree)
    for lbl in labels:
        text = lbl.get('text', '')
        path = lbl['path']
        safe_print(f"  {path}: '{text}'")

    safe_print("\n=== AVAILABLE ACTIONS ===")
    actions = client.list_actions()
    for action in actions:
        safe_print(f"  {action['action']}: {action.get('description', 'no description')}")

    safe_print("\n=== GAME STATE ===")
    try:
        state = client.get_state()
        safe_print(f"State keys: {list(state.keys())}")
    except Exception as e:
        safe_print(f"Could not get state: {e}")

    safe_print("\n=== AVAILABLE LEVELS ===")
    levels = client.list_levels()
    safe_print(f"Total levels: {len(levels)}")
    for lvl in levels[:5]:  # Show first 5
        safe_print(f"  {lvl['id']}: {lvl.get('title', 'no title')}")

    client.quit()

if __name__ == "__main__":
    explore_initial_state()
