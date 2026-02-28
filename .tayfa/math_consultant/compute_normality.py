#!/usr/bin/env python3
"""
Compute normality catalog for Layer 4 gameplay.
Finds conjugation witnesses for non-normal subgroups.
"""

import json
import os
from pathlib import Path
from typing import List, Dict, Tuple, Set, Optional
from itertools import product

# Permutation composition helper
def compose_perm(perm1: List[int], perm2: List[int]) -> List[int]:
    """Compose two permutations: (perm1 ∘ perm2)[i] = perm1[perm2[i]]"""
    return [perm1[perm2[i]] for i in range(len(perm1))]

def inverse_perm(perm: List[int]) -> List[int]:
    """Compute inverse of a permutation"""
    n = len(perm)
    inv = [0] * n
    for i in range(n):
        inv[perm[i]] = i
    return inv

def conjugate(g: List[int], h: List[int]) -> List[int]:
    """
    Compute conjugation: ghg^{-1}
    In group theory: g * h * g^{-1}
    """
    g_inv = inverse_perm(g)
    # First apply g^{-1}, then h, then g
    return compose_perm(g, compose_perm(h, g_inv))

def perm_to_str(perm: List[int]) -> str:
    """Convert permutation to cycle notation string"""
    n = len(perm)
    visited = [False] * n
    cycles = []

    for i in range(n):
        if visited[i] or perm[i] == i:
            continue

        cycle = []
        j = i
        while not visited[j]:
            visited[j] = True
            cycle.append(j)
            j = perm[j]

        if len(cycle) > 1:
            cycles.append(f"({' '.join(map(str, cycle))})")

    return ''.join(cycles) if cycles else 'e'

def find_conjugation_witness(
    subgroup_perms: List[List[int]],
    all_group_perms: List[List[int]]
) -> Optional[Tuple[List[int], List[int], List[int]]]:
    """
    Find a witness (g, h) where h ∈ H but ghg^{-1} ∉ H.
    Returns (g, h, ghg^{-1}) or None if subgroup is normal.
    """
    # Try different g from the group (not in subgroup preferably)
    candidates_g = [g for g in all_group_perms if g not in subgroup_perms]
    if not candidates_g:
        candidates_g = all_group_perms

    # Try each element h in the subgroup
    for g in candidates_g[:10]:  # Limit search to avoid timeout
        for h in subgroup_perms[1:]:  # Skip identity
            conjugated = conjugate(g, h)
            if conjugated not in subgroup_perms:
                return (g, h, conjugated)

    return None

def load_subgroups_data():
    """Load T095 subgroups data"""
    json_path = Path(__file__).parent / "T095_subgroups_data.json"
    with open(json_path, 'r', encoding='utf-8') as f:
        return json.load(f)

def load_level_automorphisms(level_num: int) -> Dict:
    """Load automorphisms from level JSON"""
    level_path = Path(__file__).parent.parent.parent / "TheSymmetryVaults" / "data" / "levels" / "act1" / f"level_{level_num:02d}.json"
    with open(level_path, 'r', encoding='utf-8') as f:
        level_data = json.load(f)
    return level_data.get("automorphisms", [])

def analyze_level_normality(level_data: Dict) -> Dict:
    """
    Analyze normality for a single level.
    Returns analysis with conjugation witnesses.
    """
    level_num = level_data["level"]
    # Skip printing for encoding issues

    # Load automorphisms from level file
    autos = load_level_automorphisms(level_num)

    # Build mapping from sym_id to permutation
    sym_id_to_perm = {}
    for auto in autos:
        sym_id = auto["sym_id"]
        perm = auto["permutation"]
        sym_id_to_perm[sym_id] = perm

    # Get all group elements as permutations
    all_perms = list(sym_id_to_perm.values())

    result = {
        "level": level_num,
        "title": level_data["title"],
        "group_name": level_data["group_name"],
        "group_order": level_data["group_order"],
        "subgroups": []
    }

    # Analyze each subgroup
    for idx, subgroup in enumerate(level_data["subgroups"]):
        order = subgroup["order"]
        is_normal = subgroup["is_normal"]
        is_trivial = subgroup["is_trivial"]

        # Skip printing to avoid encoding issues

        # Get subgroup elements as permutations
        subgroup_sym_ids = subgroup["elements"]
        subgroup_perms = [sym_id_to_perm.get(sid, None) for sid in subgroup_sym_ids]

        # Filter out None values (in case of missing data)
        subgroup_perms = [p for p in subgroup_perms if p is not None]

        subgroup_analysis = {
            "index": idx + 1,
            "order": order,
            "is_trivial": is_trivial,
            "is_normal": is_normal,
            "elements": subgroup_sym_ids,
            "generators": subgroup.get("generators", [])
        }

        # For non-normal subgroups, find conjugation witness
        if not is_normal and not is_trivial:
            witness = find_conjugation_witness(subgroup_perms, all_perms)
            if witness:
                g, h, ghg_inv = witness

                # Find sym_ids for witness elements
                g_sym_id = None
                h_sym_id = None
                ghg_inv_sym_id = None

                for sid, perm in sym_id_to_perm.items():
                    if perm == g:
                        g_sym_id = sid
                    if perm == h:
                        h_sym_id = sid
                    if perm == ghg_inv:
                        ghg_inv_sym_id = sid

                subgroup_analysis["conjugation_witness"] = {
                    "g": g_sym_id,
                    "h": h_sym_id,
                    "ghg_inv": ghg_inv_sym_id,
                    "explanation": f"{g_sym_id} * {h_sym_id} * {g_sym_id}^{{-1}} = {ghg_inv_sym_id} (not in subgroup)"
                }
                pass  # Found witness
            else:
                # Should not happen if is_normal=False
                subgroup_analysis["conjugation_witness"] = None
        else:
            subgroup_analysis["conjugation_witness"] = None

        result["subgroups"].append(subgroup_analysis)

    return result

def classify_difficulty(level_analysis: Dict) -> str:
    """
    Classify level difficulty for Layer 4:
    - TRIVIAL: prime order groups (all subgroups trivially normal)
    - EASY: abelian groups (all subgroups normal)
    - MEDIUM: clear normal/non-normal split
    - HARD: large groups with many subgroups
    - SPECIAL: Q8 (all subgroups normal despite non-abelian)
    """
    group_name = level_analysis["group_name"]
    group_order = level_analysis["group_order"]
    subgroups = level_analysis["subgroups"]

    # Count normal vs non-normal
    total = len(subgroups)
    normal_count = sum(1 for s in subgroups if s["is_normal"])
    non_normal_count = total - normal_count

    # Prime order groups
    if group_order in [2, 3, 5, 7, 11, 13]:
        return "TRIVIAL"

    # Special case: Q8
    if group_name == "Q8":
        return "SPECIAL"

    # All abelian groups
    if group_name.startswith("Z") or group_name == "V4":
        return "EASY"

    # Large groups
    if group_order >= 16 or total >= 15:
        return "HARD"

    # Medium difficulty
    return "MEDIUM"

def main():
    """Main analysis"""
    # Load subgroups data
    subgroups_data = load_subgroups_data()

    # Analyze each level
    all_results = []
    difficulty_groups = {
        "TRIVIAL": [],
        "EASY": [],
        "MEDIUM": [],
        "HARD": [],
        "SPECIAL": []
    }

    for level_data in subgroups_data:
        result = analyze_level_normality(level_data)
        difficulty = classify_difficulty(result)
        result["layer4_difficulty"] = difficulty
        difficulty_groups[difficulty].append(result["level"])
        all_results.append(result)

    # Save results
    output_path = Path(__file__).parent / "T103_normality_data.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(all_results, f, ensure_ascii=False, indent=2)

    # Save summary
    summary = {
        "total_levels": len(all_results),
        "difficulty_distribution": {k: len(v) for k, v in difficulty_groups.items()},
        "difficulty_groups": difficulty_groups
    }
    summary_path = Path(__file__).parent / "T103_normality_summary.json"
    with open(summary_path, 'w', encoding='utf-8') as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
