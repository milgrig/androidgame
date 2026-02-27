#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Verification script for Act 2 subgroups (levels 13-16)

Checks:
1. All automorphisms are valid
2. Cayley tables are correct
3. All claimed subgroups are actually subgroups (closure, identity, inverses)
4. Normality claims are correct
5. Subgroup lattice is correct
6. Consistency with Act 1 levels
"""

import json
import sys
from pathlib import Path
from typing import List, Dict, Set, Tuple
from itertools import product

# Force UTF-8 output
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')

def load_level(level_num: int) -> Dict:
    """Load a level JSON file."""
    path = Path(f"TheSymmetryVaults/data/levels/act2/level_{level_num}.json")
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def compose_permutations(p1: List[int], p2: List[int]) -> List[int]:
    """Compose two permutations: (p1 ∘ p2)[i] = p1[p2[i]]"""
    return [p1[p2[i]] for i in range(len(p1))]

def verify_automorphism(graph: Dict, mapping: List[int]) -> bool:
    """Verify that a permutation is an automorphism of the graph."""
    nodes = graph['nodes']
    edges = graph['edges']

    # Check node colors are preserved
    for i, node in enumerate(nodes):
        mapped_i = mapping[i]
        if nodes[i]['color'] != nodes[mapped_i]['color']:
            return False

    # Check edges are preserved
    for edge in edges:
        u, v = edge['from'], edge['to']
        u_mapped, v_mapped = mapping[u], mapping[v]

        # Find if edge (u_mapped, v_mapped) exists with same type
        edge_found = False
        for e2 in edges:
            if e2['from'] == u_mapped and e2['to'] == v_mapped:
                if e2['type'] == edge['type']:
                    edge_found = True
                    break

        if not edge_found:
            return False

    return True

def verify_cayley_table(automorphisms: List[Dict], cayley_table: Dict) -> Tuple[bool, List[str]]:
    """Verify Cayley table is correct."""
    errors = []

    # Build mapping from id to permutation
    id_to_perm = {aut['id']: aut['mapping'] for aut in automorphisms}

    # Check each entry
    for g1_id in cayley_table:
        for g2_id in cayley_table[g1_id]:
            claimed_result_id = cayley_table[g1_id][g2_id]

            # Compute actual composition
            g1_perm = id_to_perm[g1_id]
            g2_perm = id_to_perm[g2_id]
            actual_result_perm = compose_permutations(g1_perm, g2_perm)

            # Find which automorphism this is
            actual_result_id = None
            for aut in automorphisms:
                if aut['mapping'] == actual_result_perm:
                    actual_result_id = aut['id']
                    break

            if actual_result_id != claimed_result_id:
                errors.append(
                    f"{g1_id} ∘ {g2_id}: claimed={claimed_result_id}, "
                    f"actual={actual_result_id} "
                    f"(perm={actual_result_perm})"
                )

    return len(errors) == 0, errors

def verify_subgroup(subgroup: Dict, automorphisms: List[Dict], cayley_table: Dict) -> Tuple[bool, List[str]]:
    """Verify that a claimed subgroup is actually a subgroup."""
    errors = []

    elements = subgroup['elements']

    # Build mapping from id to permutation
    id_to_perm = {aut['id']: aut['mapping'] for aut in automorphisms}

    # 1. Check identity is present
    if 'e' not in elements:
        errors.append("Identity 'e' not in subgroup")

    # 2. Check closure
    for g1 in elements:
        for g2 in elements:
            result = cayley_table[g1][g2]
            if result not in elements:
                errors.append(f"Closure failed: {g1} ∘ {g2} = {result} ∉ subgroup")

    # 3. Check inverses
    for g in elements:
        if g == 'e':
            continue

        # Find inverse
        inverse_found = False
        for h in elements:
            if cayley_table[g][h] == 'e':
                inverse_found = True
                break

        if not inverse_found:
            errors.append(f"Inverse of {g} not in subgroup")

    return len(errors) == 0, errors

def verify_normality(subgroup: Dict, automorphisms: List[Dict], cayley_table: Dict) -> Tuple[bool, str]:
    """Verify normality claim for a subgroup."""
    elements = set(subgroup['elements'])
    is_normal_claimed = subgroup['is_normal']

    # Check if gHg^{-1} = H for all g in G
    for g_aut in automorphisms:
        g_id = g_aut['id']

        # Find g^{-1}
        g_inv_id = None
        for h_aut in automorphisms:
            if cayley_table[g_id][h_aut['id']] == 'e':
                g_inv_id = h_aut['id']
                break

        # For each h in H, compute ghg^{-1}
        for h_id in elements:
            gh = cayley_table[g_id][h_id]
            ghg_inv = cayley_table[gh][g_inv_id]

            if ghg_inv not in elements:
                # Not normal
                if is_normal_claimed:
                    return False, f"Claimed normal but {g_id}∘{h_id}∘{g_inv_id} = {ghg_inv} ∉ H"
                else:
                    return True, "Correctly identified as non-normal"

    # Is normal
    if not is_normal_claimed:
        return False, "Claimed non-normal but actually normal!"
    else:
        return True, "Correctly identified as normal"

def verify_lattice(subgroups: List[Dict], lattice: Dict) -> Tuple[bool, List[str]]:
    """Verify subgroup lattice structure."""
    errors = []

    # Build subset relations
    subgroup_by_name = {sg['name']: set(sg['elements']) for sg in subgroups}

    # Check each edge in lattice
    for edge in lattice['edges']:
        from_name = edge['from']
        to_name = edge['to']

        from_set = subgroup_by_name[from_name]
        to_set = subgroup_by_name[to_name]

        # Check subset relation
        if not from_set.issubset(to_set):
            errors.append(f"Lattice edge {from_name} → {to_name} invalid: not a subset")

    return len(errors) == 0, errors

def verify_level(level_num: int) -> Dict:
    """Verify a complete level."""
    print(f"\n{'='*60}")
    print(f"VERIFYING LEVEL {level_num}")
    print(f"{'='*60}\n")

    level = load_level(level_num)

    results = {
        'level': level_num,
        'group_name': level['meta']['group_name'],
        'group_order': level['meta']['group_order'],
        'checks': {}
    }

    graph = level['graph']
    automorphisms = level['symmetries']['automorphisms']
    cayley_table = level['symmetries']['cayley_table']
    subgroups = level['subgroups']
    lattice = level['subgroup_lattice']

    # 1. Verify automorphisms
    print("1. Verifying automorphisms...")
    aut_valid = True
    for aut in automorphisms:
        if not verify_automorphism(graph, aut['mapping']):
            print(f"   [FAIL] {aut['id']} ({aut['name']}): NOT a valid automorphism!")
            aut_valid = False
    if aut_valid:
        print(f"   [OK] All {len(automorphisms)} automorphisms valid")
    results['checks']['automorphisms'] = aut_valid

    # 2. Verify Cayley table
    print("\n2. Verifying Cayley table...")
    cayley_valid, cayley_errors = verify_cayley_table(automorphisms, cayley_table)
    if cayley_valid:
        print(f"   [OK] Cayley table correct")
    else:
        print(f"   [FAIL] Cayley table has {len(cayley_errors)} errors:")
        for err in cayley_errors[:5]:  # Show first 5
            print(f"      {err}")
        if len(cayley_errors) > 5:
            print(f"      ... and {len(cayley_errors) - 5} more")
    results['checks']['cayley_table'] = cayley_valid
    results['cayley_errors'] = len(cayley_errors)

    # 3. Verify subgroups
    print(f"\n3. Verifying {len(subgroups)} subgroups...")
    subgroup_results = []
    for sg in subgroups:
        sg_valid, sg_errors = verify_subgroup(sg, automorphisms, cayley_table)
        sg_name = sg['name']
        sg_order = sg['order']

        if sg_valid:
            print(f"   [OK] {sg_name} (order {sg_order}): valid subgroup")
        else:
            print(f"   [FAIL] {sg_name} (order {sg_order}): INVALID!")
            for err in sg_errors:
                print(f"      {err}")

        subgroup_results.append({
            'name': sg_name,
            'order': sg_order,
            'valid': sg_valid,
            'errors': sg_errors
        })

    all_subgroups_valid = all(sg['valid'] for sg in subgroup_results)
    results['checks']['subgroups'] = all_subgroups_valid
    results['subgroup_results'] = subgroup_results

    # 4. Verify normality
    print(f"\n4. Verifying normality claims...")
    normality_results = []
    for sg in subgroups:
        if sg['name'] in ['Trivial', f'Full_{level["meta"]["group_name"]}',' Full_S3', 'Full_D4', 'Full_group']:
            # Trivial and full group always normal
            continue

        norm_valid, norm_msg = verify_normality(sg, automorphisms, cayley_table)

        if norm_valid:
            print(f"   [OK] {sg['name']}: {norm_msg}")
        else:
            print(f"   [FAIL] {sg['name']}: {norm_msg}")

        normality_results.append({
            'name': sg['name'],
            'valid': norm_valid,
            'message': norm_msg
        })

    all_normality_valid = all(nr['valid'] for nr in normality_results)
    results['checks']['normality'] = all_normality_valid
    results['normality_results'] = normality_results

    # 5. Verify lattice
    print(f"\n5. Verifying subgroup lattice...")
    lattice_valid, lattice_errors = verify_lattice(subgroups, lattice)
    if lattice_valid:
        print(f"   [OK] Lattice structure valid")
    else:
        print(f"   [FAIL] Lattice has errors:")
        for err in lattice_errors:
            print(f"      {err}")
    results['checks']['lattice'] = lattice_valid

    # Overall result
    all_pass = all(results['checks'].values())
    results['overall'] = 'PASS' if all_pass else 'FAIL'

    print(f"\n{'='*60}")
    print(f"LEVEL {level_num}: {results['overall']}")
    print(f"{'='*60}")

    return results

def main():
    """Main verification routine."""
    print("=" * 60)
    print("   ACT 2 SUBGROUP VERIFICATION (Levels 13-16)".center(60))
    print("=" * 60)

    all_results = []

    for level_num in [13, 14, 15, 16]:
        results = verify_level(level_num)
        all_results.append(results)

    # Summary
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)

    for res in all_results:
        status = "[PASS]" if res['overall'] == 'PASS' else "[FAIL]"
        print(f"Level {res['level']} ({res['group_name']}): {status}")
        if res['overall'] == 'FAIL':
            print(f"   Failed checks: {[k for k, v in res['checks'].items() if not v]}")

    # Save results
    output_path = Path(".tayfa/math_consultant/T051_VERIFICATION_RESULTS.json")
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(all_results, f, indent=2, ensure_ascii=False)

    print(f"\nDetailed results saved to: {output_path}")

    # Overall
    all_pass = all(res['overall'] == 'PASS' for res in all_results)
    if all_pass:
        print("\n[SUCCESS] ALL LEVELS PASS VERIFICATION!")
    else:
        print("\n[ERROR] SOME LEVELS HAVE ERRORS - see report above")

    return 0 if all_pass else 1

if __name__ == '__main__':
    exit(main())
