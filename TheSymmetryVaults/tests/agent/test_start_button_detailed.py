#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Detailed test of Start button with console log capture"""

import sys
import time
import subprocess
import os
sys.path.insert(0, '.')
from agent_client import AgentClient

GODOT_PATH = r'C:\Godot\Godot_v4.6.1-stable_win64_console.exe'
PROJECT_PATH = r'C:\Cursor\TayfaProject\AndroidGame\TheSymmetryVaults'

def main():
    print('=== CRITICAL TEST: START BUTTON + MAP LOADING ===\n')

    # Check console log file first
    console_log = os.path.join(PROJECT_PATH, 'game_console.log')
    if os.path.exists(console_log):
        os.remove(console_log)
        print('Cleared old console log')

    client = AgentClient(godot_path=GODOT_PATH, project_path=PROJECT_PATH, timeout=15.0)

    print('Launching game...')
    client.start()
    print('Game launched\n')

    time.sleep(1)

    print('--- PRESSING START BUTTON ---')
    result = client._send_command('press_button', {
        'path': '/root/MainMenu/ButtonContainer/StartButton'
    })

    print(f'Press result: {result.get("ok")}')
    if not result.get('ok'):
        print(f'ERROR: {result.get("error")}')

    print('Waiting 2 seconds for scene transition...')
    time.sleep(2)

    print('\n--- CHECKING CURRENT SCENE ---')
    tree = client._send_command('get_tree', {'root': '/root', 'max_depth': 2})
    children = tree.get('data', {}).get('tree', {}).get('children', [])
    current = [n['name'] for n in children if n['name'] not in ['GameManager', 'AgentBridge']]

    print(f'Current scene: {current}')

    if 'MapScene' in current:
        print('\n✅ SUCCESS: MapScene loaded!')

        # Try to get map state
        print('\n--- CHECKING MAP STATE ---')
        map_state = client._send_command('get_map_state', {})
        if map_state.get('ok'):
            print('✅ Map state accessible')
            halls = map_state.get('data', {}).get('halls', [])
            print(f'   Halls available: {len(halls)}')
        else:
            print(f'❌ Map state error: {map_state.get("error")}')
    else:
        print(f'\n❌ FAIL: Expected MapScene, got {current}')

    print('\n--- CHECKING GODOT PROCESS OUTPUT ---')
    # The Godot process stderr/stdout should be captured by AgentClient
    # Let's check if we can get any error logs

    client.quit()

    # Now check console log if it exists
    print('\n--- CONSOLE LOG CHECK ---')
    if os.path.exists(console_log):
        with open(console_log, 'r', encoding='utf-8', errors='ignore') as f:
            log_content = f.read()

        if 'ERROR:' in log_content or 'SCRIPT ERROR' in log_content:
            print('❌ ERRORS FOUND IN LOG:')
            print('---')
            for line in log_content.split('\n'):
                if 'ERROR' in line or 'SCRIPT ERROR' in line:
                    print(line)
            print('---')
        else:
            print('✅ No errors in console log')
    else:
        print('⚠️  No console log file found')

    print('\n=== TEST COMPLETE ===')

if __name__ == '__main__':
    main()
