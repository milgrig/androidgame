#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Verify Layer 5 (quotient groups) data for all levels.

Checks:
1. Cosets partition the group (disjoint union)
2. Each coset has size |H|
3. Number of cosets = |G|/|H|
4. Coset representatives are valid
"""

import json
import sys
import io
from pathlib import Path
from typing import List, Dict

# UTF-8 output
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


def verify_coset_decomposition(group_size: int, subgroup_size: int, cosets: List[Dict]) -> List[str]:
    """Verify that cosets form a valid partition of the group"""
    issues = []

    # Check 1: Number of cosets should be |G|/|H|
    expected_num_cosets = group_size // subgroup_size
    actual_num_cosets = len(cosets)

    if actual_num_cosets != expected_num_cosets:
        issues.append(f"Expected {expected_num_cosets} cosets, got {actual_num_cosets}")

    # Check 2: Each coset should have size |H|
    for i, coset in enumerate(cosets):
        coset_elements = coset.get("elements", [])
        if len(coset_elements) != subgroup_size:
            issues.append(f"Coset {i} has size {len(coset_elements)}, expected {subgroup_size}")

    # Check 3: Cosets should partition the group (no overlaps, cover everything)
    all_elements = []
    for coset in cosets:
        all_elements.extend(coset.get("elements", []))

    # Check for duplicates
    if len(all_elements) != len(set(all_elements)):
        duplicates = [x for x in all_elements if all_elements.count(x) > 1]
        issues.append(f"Cosets have overlapping elements: {set(duplicates)}")

    # Check total size
    if len(all_elements) != group_size:
        issues.append(f"Cosets cover {len(all_elements)} elements, expected {group_size}")

    # Check 4: Representative should be in its coset
    for i, coset in enumerate(cosets):
        rep = coset.get("representative", "")
        elements = coset.get("elements", [])
        if rep not in elements:
            issues.append(f"Coset {i} representative '{rep}' not in its elements")

    return issues


def verify_level(level_num: int, level_data: Dict) -> List[str]:
    """Verify layer_5 data for a single level"""
    issues = []

    # Get group size
    autos = level_data.get("symmetries", {}).get("automorphisms", [])
    group_size = len(autos)

    # Get layer_5 data
    layer5 = level_data.get("layers", {}).get("layer_5", {})

    if not layer5:
        issues.append("layer_5 data missing")
        return issues

    quotient_groups = layer5.get("quotient_groups", [])

    for qg_idx, qg in enumerate(quotient_groups):
        subgroup_elements = qg.get("normal_subgroup_elements", [])
        subgroup_size = len(subgroup_elements)
        cosets = qg.get("cosets", [])
        quotient_order = qg.get("quotient_order", 0)

        # Verify quotient order
        expected_order = group_size // subgroup_size
        if quotient_order != expected_order:
            issues.append(f"QG{qg_idx}: quotient_order={quotient_order}, expected {expected_order}")

        # Verify coset decomposition
        coset_issues = verify_coset_decomposition(group_size, subgroup_size, cosets)
        for issue in coset_issues:
            issues.append(f"QG{qg_idx}: {issue}")

        # Verify coset representatives list
        representatives = qg.get("coset_representatives", [])
        if len(representatives) != len(cosets):
            issues.append(f"QG{qg_idx}: {len(representatives)} representatives, {len(cosets)} cosets")

        # Check representatives match coset data
        for i, coset in enumerate(cosets):
            rep_in_coset = coset.get("representative", "")
            if i < len(representatives) and representatives[i] != rep_in_coset:
                issues.append(f"QG{qg_idx}: representative mismatch at index {i}")

    return issues


def verify_all_levels():
    """Verify layer_5 data for all 24 levels"""
    levels_dir = Path("TheSymmetryVaults/data/levels/act1")

    print("=" * 70)
    print("Layer 5 Data Verification — Quotient Groups")
    print("=" * 70)
    print()

    total_levels = 0
    total_quotients = 0
    total_issues = 0

    for level_file in sorted(levels_dir.glob("level_*.json")):
        level_num = int(level_file.stem.split('_')[1])
        total_levels += 1

        # Read level data
        with open(level_file, 'r', encoding='utf-8') as f:
            level_data = json.load(f)

        # Verify
        issues = verify_level(level_num, level_data)

        # Count quotient groups
        layer5 = level_data.get("layers", {}).get("layer_5", {})
        num_quotients = len(layer5.get("quotient_groups", []))
        total_quotients += num_quotients

        if issues:
            total_issues += len(issues)
            print(f"❌ Level {level_num:2d}: {len(issues)} issue(s)")
            for issue in issues:
                print(f"    {issue}")
        else:
            if num_quotients > 0:
                print(f"✅ Level {level_num:2d}: {num_quotients} quotient group(s) verified")
            else:
                print(f"⚪ Level {level_num:2d}: No quotient groups (OK)")

    print()
    print("=" * 70)
    print(f"Verified {total_levels} levels, {total_quotients} quotient groups total")
    if total_issues == 0:
        print("✅ ALL CHECKS PASSED — Data is mathematically correct!")
    else:
        print(f"❌ Found {total_issues} issue(s) — needs fixing")
    print("=" * 70)


def main():
    print()
    verify_all_levels()
    print()


if __name__ == "__main__":
    main()
