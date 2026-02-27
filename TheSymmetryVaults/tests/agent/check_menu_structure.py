#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check main menu structure"""

import sys
import json
sys.path.insert(0, '.')
from agent_client import AgentClient

GODOT_PATH = r'C:\Godot\Godot_v4.6.1-stable_win64_console.exe'
PROJECT_PATH = r'C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults'

def print_tree(node, indent=0):
    """Recursively print tree structure"""
    name = node.get('name', 'Unknown')
    node_type = node.get('type', 'Unknown')
    path = node.get('path', '')

    print('  ' * indent + f'- {name} ({node_type})')
    if path:
        print('  ' * indent + f'  path: {path}')

    # Print relevant properties
    if 'text' in node:
        print('  ' * indent + f'  text: "{node["text"]}"')
    if 'visible' in node:
        print('  ' * indent + f'  visible: {node["visible"]}')
    if 'disabled' in node:
        print('  ' * indent + f'  disabled: {node["disabled"]}')

    # Recurse into children
    for child in node.get('children', []):
        print_tree(child, indent + 1)

def main():
    print('=== LAUNCH GAME ===')
    client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
    client.start()

    print('\n=== FULL SCENE TREE (depth=5) ===')
    tree = client._send_command('get_tree', {'root': '/root', 'max_depth': 5})

    if tree.get('ok'):
        root = tree.get('data', {}).get('tree', {})
        print_tree(root)

        # Save full tree to file for inspection
        with open('menu_tree_structure.json', 'w', encoding='utf-8') as f:
            json.dump(tree, f, indent=2, ensure_ascii=False)
        print('\n=== Full tree saved to menu_tree_structure.json ===')
    else:
        print(f'Error: {tree}')

    print('\n=== CHECK BUTTON CONTAINER ===')
    container = client._send_command('get_node', {
        'path': '/root/MainMenu/CenterContainer/VBoxContainer/ButtonContainer'
    })
    print(f'ButtonContainer exists: {container.get("ok")}')
    if container.get('ok'):
        print(f'Children count: {len(container.get("data", {}).get("node", {}).get("children", []))}')
        for child in container.get('data', {}).get('node', {}).get('children', []):
            print(f'  - {child.get("name")} ({child.get("type")})')

    print('\n=== SEARCH FOR BUTTON NODES ===')
    # Try to find buttons by searching the tree
    def find_buttons(node, buttons_list):
        if node.get('type', '').endswith('Button'):
            buttons_list.append({
                'name': node.get('name'),
                'type': node.get('type'),
                'path': node.get('path'),
                'text': node.get('text', '')
            })
        for child in node.get('children', []):
            find_buttons(child, buttons_list)

    buttons = []
    if tree.get('ok'):
        find_buttons(tree.get('data', {}).get('tree', {}), buttons)
        print(f'Found {len(buttons)} button nodes:')
        for btn in buttons:
            print(f'  - {btn["name"]} ({btn["type"]}): {btn["path"]}')
            if btn['text']:
                print(f'    Text: "{btn["text"]}"')

    print('\n=== CLEANUP ===')
    client.quit()
    print('Check complete')

if __name__ == '__main__':
    main()
