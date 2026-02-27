#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test all buttons in main menu - FIXED PATHS"""

import sys
import time
sys.path.insert(0, '.')
from agent_client import AgentClient

GODOT_PATH = r'C:\Godot\Godot_v4.6.1-stable_win64_console.exe'
PROJECT_PATH = r'C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults'

def get_current_scene(client):
    """Get current scene name"""
    tree = client._send_command('get_tree', {'root': '/root', 'max_depth': 2})
    children = tree.get('data', {}).get('tree', {}).get('children', [])
    scenes = [n['name'] for n in children if n['name'] not in ['GameManager', 'AgentBridge']]
    return scenes[0] if scenes else 'Unknown'

def main():
    print('=== BUTTON TEST REPORT ===\n')

    client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)
    client.start()

    print('Game launched successfully')
    current = get_current_scene(client)
    print(f'Initial scene: {current}\n')

    # Button paths from structure
    buttons = [
        {
            'name': 'Start Button',
            'path': '/root/MainMenu/ButtonContainer/StartButton',
            'text': 'Start Game',
            'expected': 'MapScene'
        },
        {
            'name': 'Settings Button',
            'path': '/root/MainMenu/ButtonContainer/SettingsButton',
            'text': 'Settings',
            'expected': 'SettingsMenu (not implemented)'
        },
        {
            'name': 'Exit Button',
            'path': '/root/MainMenu/ButtonContainer/ExitButton',
            'text': 'Exit',
            'expected': 'Game quit (not testable in headless)'
        }
    ]

    results = []

    # TEST 1: START BUTTON
    print('--- TEST 1: START BUTTON ---')
    try:
        result = client._send_command('press_button', {
            'path': buttons[0]['path']
        })

        if result.get('ok'):
            print('  Press command: SUCCESS')
            time.sleep(1)

            scene_after = get_current_scene(client)
            print(f'  Scene after: {scene_after}')

            if scene_after == 'MapScene':
                print('  Result: WORKS - Map loaded!')
                results.append(('Start Button', 'WORKS', 'Transitions to MapScene'))
            else:
                print(f'  Result: PARTIAL - Scene is {scene_after}, not MapScene')
                results.append(('Start Button', 'PARTIAL', f'Scene: {scene_after}'))
        else:
            error = result.get('error', 'Unknown error')
            print(f'  Press command: FAILED - {error}')
            results.append(('Start Button', 'BROKEN', error))
    except Exception as e:
        print(f'  Exception: {e}')
        results.append(('Start Button', 'ERROR', str(e)))

    print()

    # Navigate back to menu for next tests
    print('Navigating back to MainMenu...')
    nav = client._send_command('navigate', {'to': 'main_menu'})
    if nav.get('ok'):
        time.sleep(0.5)
        current = get_current_scene(client)
        print(f'Back on: {current}\n')
    else:
        print('Navigation failed, may affect next tests\n')

    # TEST 2: SETTINGS BUTTON
    print('--- TEST 2: SETTINGS BUTTON ---')
    try:
        result = client._send_command('press_button', {
            'path': buttons[1]['path']
        })

        if result.get('ok'):
            print('  Press command: SUCCESS')
            time.sleep(0.5)

            scene_after = get_current_scene(client)
            print(f'  Scene after: {scene_after}')

            if scene_after != 'MainMenu':
                print(f'  Result: WORKS - Changed to {scene_after}')
                results.append(('Settings Button', 'WORKS', f'Opens {scene_after}'))
            else:
                print('  Result: NOT IMPLEMENTED - No scene change')
                results.append(('Settings Button', 'NOT IMPLEMENTED', 'No action defined'))
        else:
            error = result.get('error', 'Unknown error')
            print(f'  Press command: FAILED - {error}')
            results.append(('Settings Button', 'BROKEN', error))
    except Exception as e:
        print(f'  Exception: {e}')
        results.append(('Settings Button', 'ERROR', str(e)))

    print()

    # TEST 3: EXIT BUTTON
    print('--- TEST 3: EXIT BUTTON ---')
    print('  Note: Exit button quits the game, not testable in automated mode')
    print('  Status: SKIPPED (requires manual test)')
    results.append(('Exit Button', 'SKIPPED', 'Quits game - not testable'))

    print()

    # SUMMARY
    print('=== TEST SUMMARY ===\n')
    print('Button Test Results:')
    for btn, status, detail in results:
        print(f'  {btn}: {status}')
        print(f'    {detail}')

    print()

    # Final verdict
    working = sum(1 for _, s, _ in results if s == 'WORKS')
    total = len(results)

    print(f'Working: {working}/{total} buttons')

    if working >= 1:
        print('Status: PASS (at least Start button works)')
    else:
        print('Status: FAIL (no buttons working)')

    client.quit()
    print('\nTest complete')

if __name__ == '__main__':
    main()
