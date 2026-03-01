#!/usr/bin/env python3
"""Check Layer 4 logic for all levels - verify is_normal flags match conjugation witnesses"""

import json
import os
import sys

def compose(perm1, perm2):
    """Compose two permutations"""
    return [perm1[perm2[i]] for i in range(len(perm1))]

def check_level_layer4(level_num):
    """Check Layer 4 for a single level"""
    level_path = f"TheSymmetryVaults/data/levels/act1/level_{level_num:02d}.json"

    if not os.path.exists(level_path):
        return None

    with open(level_path, 'r', encoding='utf-8') as f:
        level = json.load(f)

    # Check if Layer 4 exists
    if 'layers' not in level or 'layer_4' not in level['layers']:
        return {'level': level_num, 'has_layer4': False}

    layer4 = level['layers']['layer_4']
    autos = {a['id']: a['mapping'] for a in level['symmetries']['automorphisms']}

    issues = []

    for sg in layer4['subgroups']:
        is_normal = sg['is_normal']
        witness = sg['conjugation_witness']

        # Normal subgroups should have witness=null
        # Non-normal should have a witness
        if is_normal and witness is not None:
            issues.append(f"Order {sg['order']}: is_normal=True but has witness!")

        if not is_normal and witness is None:
            issues.append(f"Order {sg['order']}: is_normal=False but no witness!")

        # If witness exists, verify it mathematically
        if witness is not None:
            g = autos[witness['g']]
            h = autos[witness['h']]
            g_inv = autos[witness['g_inv']]
            expected = autos[witness['result']]

            # Compute g*h*g_inv
            gh = compose(g, h)
            result = compose(gh, g_inv)

            # Check if matches expected
            if result != expected:
                issues.append(f"Order {sg['order']}: witness computation wrong! {result} != {expected}")

            # Check if result is in subgroup
            subgroup_perms = [autos[elem_id] for elem_id in sg['elements']]
            in_subgroup = result in subgroup_perms

            if in_subgroup:
                issues.append(f"Order {sg['order']}: witness result IS in subgroup - should be normal!")

    return {
        'level': level_num,
        'has_layer4': True,
        'subgroup_count': len(layer4['subgroups']),
        'issues': issues
    }

def main():
    print("=== CHECKING LAYER 4 LOGIC FOR ALL LEVELS ===")
    print()

    all_issues = []

    for level_num in range(1, 25):
        result = check_level_layer4(level_num)

        if result is None:
            continue

        if not result['has_layer4']:
            print(f"Level {level_num:2d}: No Layer 4")
            continue

        if result['issues']:
            print(f"Level {level_num:2d}: {result['subgroup_count']} subgroups - {len(result['issues'])} ISSUES!")
            for issue in result['issues']:
                print(f"  - {issue}")
            all_issues.extend([(level_num, issue) for issue in result['issues']])
        else:
            print(f"Level {level_num:2d}: {result['subgroup_count']} subgroups - OK")

    print()
    print("=" * 70)
    if all_issues:
        print(f"TOTAL ISSUES FOUND: {len(all_issues)}")
    else:
        print("ALL LEVELS OK - No issues found!")

if __name__ == "__main__":
    main()
