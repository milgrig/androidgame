#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Проверка Layer 4: всегда ли witness.h принадлежит подгруппе?

Если в JSON есть witness, где h ∉ H — это ошибка в данных!
"""

import json
from pathlib import Path


def check_layer4_h_validation():
    """
    Проверяет, всегда ли witness.h принадлежит подгруппе.
    """
    levels_dir = Path("TheSymmetryVaults/data/levels/act1")
    issues = []
    checked_count = 0

    for level_file in sorted(levels_dir.glob("level_*.json")):
        with open(level_file, 'r', encoding='utf-8') as f:
            data = json.load(f)

        level_num = int(level_file.stem.split('_')[1])
        layer4 = data.get("layers", {}).get("layer_4", {})
        subgroups = layer4.get("subgroups", [])

        for i, sg in enumerate(subgroups):
            elements = sg.get("elements", [])
            witness = sg.get("conjugation_witness")

            if witness is None:
                continue  # Нормальная подгруппа, witness не нужен

            checked_count += 1
            h = witness.get("h")

            if h not in elements:
                issues.append({
                    "level": level_num,
                    "subgroup_idx": i,
                    "order": len(elements),
                    "elements": elements,
                    "witness_h": h,
                    "error": "h NOT in subgroup!"
                })

    print(f"Checked {checked_count} witnesses across all levels.\n")

    if issues:
        print(f"❌ Found {len(issues)} issues where h ∉ H:\n")
        for issue in issues:
            print(f"  Level {issue['level']}, subgroup #{issue['subgroup_idx']} "
                  f"(order {issue['order']}):")
            print(f"    h = '{issue['witness_h']}'")
            print(f"    H = {issue['elements']}")
            print(f"    ⚠ ERROR: h is NOT in H!\n")
    else:
        print("✅ All witnesses have h ∈ H")
        print("   Data is mathematically correct!")

    return issues


def main():
    import sys
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

    print("=" * 60)
    print("Layer 4 Witness Validation: h ∈ H?")
    print("=" * 60)
    print()

    issues = check_layer4_h_validation()

    print()
    print("=" * 60)
    if issues:
        print("RESULT: ❌ DATA ERRORS FOUND")
        print(f"Action: Fix {len(issues)} witness(es) in JSON files")
    else:
        print("RESULT: ✅ ALL DATA VALID")
    print("=" * 60)


if __name__ == "__main__":
    main()
