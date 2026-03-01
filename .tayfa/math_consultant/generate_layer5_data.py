#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate Layer 5 (quotient groups) data for all levels.

For each normal subgroup H from layer_4:
- Compute left cosets gH
- Determine coset representatives
- Calculate quotient order |G/H|
- Identify quotient type (isomorphism class)
"""

import json
import sys
import io
from pathlib import Path
from collections import defaultdict
from typing import List, Dict, Tuple, Set

# UTF-8 output
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


def compose_perms(p1: List[int], p2: List[int]) -> List[int]:
    """Compose two permutations: (p1 ∘ p2)[i] = p1[p2[i]]"""
    return [p1[p2[i]] for i in range(len(p1))]


def inverse_perm(p: List[int]) -> List[int]:
    """Compute inverse permutation"""
    n = len(p)
    inv = [0] * n
    for i in range(n):
        inv[p[i]] = i
    return inv


def perm_equals(p1: List[int], p2: List[int]) -> bool:
    """Check if two permutations are equal"""
    return p1 == p2


def perm_order(p: List[int]) -> int:
    """Compute order of a permutation"""
    n = len(p)
    result = p[:]
    order = 1
    identity = list(range(n))

    while result != identity:
        result = compose_perms(p, result)
        order += 1
        if order > 1000:  # Safety
            break

    return order


def compute_left_coset(g: List[int], subgroup: List[List[int]]) -> List[List[int]]:
    """Compute left coset gH = {g·h | h ∈ H}"""
    coset = []
    for h in subgroup:
        gh = compose_perms(g, h)
        coset.append(gh)
    return coset


def cosets_equal(coset1: List[List[int]], coset2: List[List[int]]) -> bool:
    """Check if two cosets are equal (as sets)"""
    if len(coset1) != len(coset2):
        return False

    for p in coset1:
        found = False
        for q in coset2:
            if perm_equals(p, q):
                found = True
                break
        if not found:
            return False

    return True


def compute_coset_decomposition(group: List[List[int]], subgroup: List[List[int]]) -> List[List[List[int]]]:
    """Compute all left cosets of H in G (like SubgroupChecker.coset_decomposition)"""
    cosets = []
    assigned = []

    for g in group:
        # Check if g already in some coset
        already_assigned = False
        for a in assigned:
            if perm_equals(a, g):
                already_assigned = True
                break

        if already_assigned:
            continue

        # Compute left coset gH
        coset = compute_left_coset(g, subgroup)
        cosets.append(coset)

        # Mark all elements in this coset as assigned
        for element in coset:
            assigned.append(element)

    return cosets


def find_sym_id(perm: List[int], sym_id_to_perm: Dict[str, List[int]]) -> str:
    """Find sym_id for a given permutation"""
    for sid, p in sym_id_to_perm.items():
        if perm_equals(p, perm):
            return sid
    return ""


def identify_quotient_type(quotient_order: int, cosets: List[List[List[int]]],
                          group: List[List[int]], subgroup: List[List[int]]) -> str:
    """
    Identify the isomorphism type of quotient group.

    Common types:
    - Z_n (cyclic)
    - Z_2 × Z_2 (Klein four-group)
    - S_3, D_3, etc.
    """
    n = quotient_order

    if n == 1:
        return "trivial"

    if n == 2:
        return "Z2"

    if n == 3:
        return "Z3"

    if n == 4:
        # Check if cyclic or Klein four-group
        # For now, use heuristic: check element orders in quotient
        # This is simplified - full implementation would check Cayley table
        return "Z4_or_Z2xZ2"  # Placeholder

    if n == 5:
        return "Z5"

    if n == 6:
        return "Z6_or_S3"  # Placeholder

    if n == 8:
        return "order8"  # Could be Z8, Z4xZ2, Z2xZ2xZ2, D4, Q8

    return f"order{n}"


def generate_layer5_for_level(level_data: Dict) -> Dict:
    """Generate layer_5 data for a single level"""

    # Parse automorphisms
    autos = level_data.get("symmetries", {}).get("automorphisms", [])
    sym_id_to_perm = {}
    group_perms = []

    for auto in autos:
        sym_id = auto.get("id", "")
        perm = auto.get("mapping", [])
        sym_id_to_perm[sym_id] = perm
        group_perms.append(perm)

    # Get layer_4 data
    layer4 = level_data.get("layers", {}).get("layer_4", {})
    subgroups = layer4.get("subgroups", [])

    # Filter normal subgroups
    normal_subgroups = [sg for sg in subgroups if sg.get("is_normal", False)]

    if not normal_subgroups:
        # No normal subgroups → no quotient groups
        return {
            "quotient_groups": [],
            "message": "No non-trivial normal subgroups exist"
        }

    quotient_groups = []

    for sg in normal_subgroups:
        sg_elements = sg.get("elements", [])
        sg_order = len(sg_elements)

        # Skip trivial subgroups (order 1 or |G|)
        if sg_order <= 1 or sg_order >= len(group_perms):
            continue

        # Build subgroup as list of permutations
        subgroup_perms = []
        for sid in sg_elements:
            if sid in sym_id_to_perm:
                subgroup_perms.append(sym_id_to_perm[sid])

        # Compute coset decomposition
        cosets = compute_coset_decomposition(group_perms, subgroup_perms)

        # Find coset representatives (first element of each coset)
        coset_data = []
        representatives = []

        for coset in cosets:
            if coset:
                representative_perm = coset[0]
                representative_sid = find_sym_id(representative_perm, sym_id_to_perm)
                representatives.append(representative_sid)

                # Convert coset to sym_ids
                coset_sids = []
                for perm in coset:
                    sid = find_sym_id(perm, sym_id_to_perm)
                    if sid:
                        coset_sids.append(sid)

                coset_data.append({
                    "representative": representative_sid,
                    "elements": coset_sids
                })

        quotient_order = len(cosets)
        quotient_type = identify_quotient_type(quotient_order, cosets, group_perms, subgroup_perms)

        quotient_groups.append({
            "normal_subgroup_elements": sg_elements,
            "cosets": coset_data,
            "coset_representatives": representatives,
            "quotient_order": quotient_order,
            "quotient_type": quotient_type
        })

    return {
        "quotient_groups": quotient_groups
    }


def process_all_levels():
    """Process all 24 levels and add layer_5 data"""
    levels_dir = Path("TheSymmetryVaults/data/levels/act1")

    if not levels_dir.exists():
        print(f"❌ Error: Directory not found: {levels_dir}")
        return

    print("=" * 70)
    print("Layer 5 Data Generation — Quotient Groups")
    print("=" * 70)
    print()

    total_levels = 0
    total_quotients = 0
    modified_files = []

    for level_file in sorted(levels_dir.glob("level_*.json")):
        level_num = int(level_file.stem.split('_')[1])
        total_levels += 1

        # Read level data
        with open(level_file, 'r', encoding='utf-8') as f:
            level_data = json.load(f)

        # Generate layer_5
        layer5_data = generate_layer5_for_level(level_data)

        # Count quotient groups
        num_quotients = len(layer5_data.get("quotient_groups", []))
        total_quotients += num_quotients

        # Add to level data
        if "layers" not in level_data:
            level_data["layers"] = {}

        level_data["layers"]["layer_5"] = layer5_data

        # Write back
        with open(level_file, 'w', encoding='utf-8') as f:
            json.dump(level_data, f, indent=2, ensure_ascii=False)

        modified_files.append(level_file.name)

        # Print status
        if num_quotients > 0:
            print(f"✅ Level {level_num:2d}: {num_quotients} quotient group(s)")
            for qg in layer5_data.get("quotient_groups", []):
                h_order = len(qg["normal_subgroup_elements"])
                q_order = qg["quotient_order"]
                q_type = qg["quotient_type"]
                print(f"    |H|={h_order}, |G/H|={q_order}, type={q_type}")
        else:
            msg = layer5_data.get("message", "No quotient groups")
            print(f"⚪ Level {level_num:2d}: {msg}")

    print()
    print("=" * 70)
    print(f"✅ Processed {total_levels} levels")
    print(f"✅ Generated {total_quotients} quotient groups total")
    print(f"✅ Modified {len(modified_files)} files")
    print("=" * 70)
    print()
    print("Modified files:")
    for fname in modified_files:
        print(f"  - {fname}")


def main():
    print()
    process_all_levels()
    print()
    print("✅ Layer 5 data generation complete!")
    print()


if __name__ == "__main__":
    main()
