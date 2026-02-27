#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test all buttons in main menu"""

import sys
import time
sys.path.insert(0, '.')
from agent_client import AgentClient

GODOT_PATH = r'C:\Godot\Godot_v4.6.1-stable_win64_console.exe'
PROJECT_PATH = r'C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults'

def main():
    print('=== LAUNCH GAME ===')
    client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
    client.start()

    print('\n=== CHECK CURRENT SCENE ===')
    tree = client._send_command('get_tree', {'root': '/root', 'max_depth': 2})
    children = tree.get('data', {}).get('tree', {}).get('children', [])
    current = [n['name'] for n in children if n['name'] not in ['GameManager', 'AgentBridge']]
    print(f'Current scene: {current}')

    print('\n=== LIST ALL BUTTONS ===')
    actions = client._send_command('list_actions', {})
    if actions.get('ok'):
        buttons = actions.get('data', {}).get('buttons', [])
        print(f'Found {len(buttons)} buttons:')
        for btn in buttons:
            print(f'  - {btn["name"]}: {btn["path"]}')
            print(f'    Text: "{btn.get("text", "")}"')
            print(f'    Visible: {btn.get("visible", False)}, Enabled: {not btn.get("disabled", True)}')
    else:
        print(f'Error getting buttons: {actions}')

    print('\n=== TEST 1: START BUTTON ===')
    start_result = client._send_command('press_button', {
        'path': '/root/MainMenu/CenterContainer/VBoxContainer/ButtonContainer/StartButton'
    })
    print(f'Press result: {start_result.get("ok")} - {start_result.get("data", start_result.get("error", ""))}')

    time.sleep(1)

    tree2 = client._send_command('get_tree', {'root': '/root', 'max_depth': 2})
    children2 = tree2.get('data', {}).get('tree', {}).get('children', [])
    scene_after = [n['name'] for n in children2 if n['name'] not in ['GameManager', 'AgentBridge']]
    print(f'Scene after press: {scene_after}')

    if 'MapScene' in scene_after:
        print('SUCCESS: Map loaded!')
    else:
        print(f'FAIL: Map not loaded, still on: {scene_after}')

    print('\n=== TEST 2: NAVIGATE BACK TO MENU ===')
    nav_result = client._send_command('navigate', {'to': 'main_menu'})
    print(f'Navigate result: {nav_result.get("ok")}')

    time.sleep(0.5)

    tree3 = client._send_command('get_tree', {'root': '/root', 'max_depth': 2})
    children3 = tree3.get('data', {}).get('tree', {}).get('children', [])
    scene3 = [n['name'] for n in children3 if n['name'] not in ['GameManager', 'AgentBridge']]
    print(f'Scene after back: {scene3}')

    print('\n=== TEST 3: SETTINGS BUTTON ===')
    settings_result = client._send_command('press_button', {
        'path': '/root/MainMenu/CenterContainer/VBoxContainer/ButtonContainer/SettingsButton'
    })
    print(f'Settings press: {settings_result.get("ok")} - {settings_result.get("data", settings_result.get("error", ""))}')

    time.sleep(0.5)

    tree4 = client._send_command('get_tree', {'root': '/root', 'max_depth': 2})
    children4 = tree4.get('data', {}).get('tree', {}).get('children', [])
    scene4 = [n['name'] for n in children4 if n['name'] not in ['GameManager', 'AgentBridge']]
    print(f'Scene after settings: {scene4}')

    print('\n=== CLEANUP ===')
    client.quit()
    print('Test complete')

if __name__ == '__main__':
    main()
