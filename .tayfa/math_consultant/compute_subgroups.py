#!/usr/bin/env python3
"""
Compute all subgroups for all 24 levels of The Symmetry Vaults.
For each level, identifies:
- All subgroups (including trivial)
- Generators for each subgroup
- Whether each subgroup is normal
- Order of each subgroup
"""

import json
import os
from typing import List, Dict, Set, Tuple
from itertools import combinations
from collections import deque

def compose_permutations(perm1: List[int], perm2: List[int]) -> List[int]:
    """Compose two permutations: (perm1 ∘ perm2)[i] = perm1[perm2[i]]"""
    return [perm1[perm2[i]] for i in range(len(perm1))]

def inverse_permutation(perm: List[int]) -> List[int]:
    """Compute inverse of a permutation"""
    inv = [0] * len(perm)
    for i, p in enumerate(perm):
        inv[p] = i
    return inv

def permutation_order(perm: List[int]) -> int:
    """Compute the order of a permutation (smallest n such that perm^n = identity)"""
    n = len(perm)
    identity = list(range(n))
    current = perm[:]
    order = 1
    while current != identity:
        current = compose_permutations(perm, current)
        order += 1
        if order > 1000:  # Safety check
            return -1
    return order

def generate_subgroup_from_generators(generators: List[List[int]], n: int) -> Set[Tuple[int, ...]]:
    """Generate all elements of subgroup from generators using BFS"""
    identity = tuple(range(n))
    elements = {identity}
    queue = deque([identity])

    for gen in generators:
        gen_tuple = tuple(gen)
        if gen_tuple not in elements:
            elements.add(gen_tuple)
            queue.append(gen_tuple)

    while queue:
        current = queue.popleft()
        current_list = list(current)

        # Multiply by each generator
        for gen in generators:
            # current * gen
            new_perm = tuple(compose_permutations(current_list, gen))
            if new_perm not in elements:
                elements.add(new_perm)
                queue.append(new_perm)

            # gen * current
            new_perm = tuple(compose_permutations(gen, current_list))
            if new_perm not in elements:
                elements.add(new_perm)
                queue.append(new_perm)

        # Also compute inverses
        inv = tuple(inverse_permutation(current_list))
        if inv not in elements:
            elements.add(inv)
            queue.append(inv)

    return elements

def find_all_subgroups(group_elements: List[List[int]]) -> List[Dict]:
    """Find all subgroups of a given group using brute force enumeration"""
    n = len(group_elements[0])
    identity = list(range(n))

    # Convert to tuples for hashing
    group_set = {tuple(perm) for perm in group_elements}

    subgroups = []

    # Trivial subgroup {e}
    subgroups.append({
        'elements': [identity],
        'order': 1,
        'is_trivial': True
    })

    # Full group
    if len(group_elements) > 1:
        subgroups.append({
            'elements': group_elements,
            'order': len(group_elements),
            'is_trivial': True  # Full group is also considered trivial
        })

    # Try all possible non-empty subsets as potential generators
    # We'll check subsets of size 1, 2, 3, ... up to a reasonable limit
    checked_subgroups = set()
    checked_subgroups.add(frozenset([tuple(identity)]))
    checked_subgroups.add(frozenset(group_set))

    # First, try all single elements (cyclic subgroups)
    for elem in group_elements:
        if elem == identity:
            continue

        generated = generate_subgroup_from_generators([elem], n)
        generated_frozen = frozenset(generated)

        if generated_frozen not in checked_subgroups:
            checked_subgroups.add(generated_frozen)
            if generated_frozen != frozenset([tuple(identity)]) and generated_frozen != frozenset(group_set):
                subgroups.append({
                    'elements': [list(p) for p in sorted(generated)],
                    'order': len(generated),
                    'is_trivial': False
                })

    # Try pairs of elements
    if len(group_elements) <= 24:  # Only for small groups to avoid combinatorial explosion
        for elem1, elem2 in combinations(group_elements, 2):
            if elem1 == identity or elem2 == identity:
                continue

            generated = generate_subgroup_from_generators([elem1, elem2], n)
            generated_frozen = frozenset(generated)

            if generated_frozen not in checked_subgroups:
                checked_subgroups.add(generated_frozen)
                if generated_frozen != frozenset([tuple(identity)]) and generated_frozen != frozenset(group_set):
                    subgroups.append({
                        'elements': [list(p) for p in sorted(generated)],
                        'order': len(generated),
                        'is_trivial': False
                    })

    # Try triples for small groups
    if len(group_elements) <= 12:
        for elem1, elem2, elem3 in combinations(group_elements, 3):
            if elem1 == identity or elem2 == identity or elem3 == identity:
                continue

            generated = generate_subgroup_from_generators([elem1, elem2, elem3], n)
            generated_frozen = frozenset(generated)

            if generated_frozen not in checked_subgroups:
                checked_subgroups.add(generated_frozen)
                if generated_frozen != frozenset([tuple(identity)]) and generated_frozen != frozenset(group_set):
                    subgroups.append({
                        'elements': [list(p) for p in sorted(generated)],
                        'order': len(generated),
                        'is_trivial': False
                    })

    return subgroups

def find_minimal_generators(subgroup_elements: List[List[int]], n: int) -> List[List[int]]:
    """Find a minimal generating set for a subgroup"""
    if len(subgroup_elements) <= 1:
        return []

    identity = list(range(n))
    non_identity = [elem for elem in subgroup_elements if elem != identity]

    if len(non_identity) == 0:
        return []

    # Try to find smallest generating set
    # Start with single elements
    for elem in non_identity:
        generated = generate_subgroup_from_generators([elem], n)
        if len(generated) == len(subgroup_elements):
            # Check if same elements
            if frozenset(tuple(e) for e in subgroup_elements) == generated:
                return [elem]

    # Try pairs
    for elem1, elem2 in combinations(non_identity, 2):
        generated = generate_subgroup_from_generators([elem1, elem2], n)
        if len(generated) == len(subgroup_elements):
            if frozenset(tuple(e) for e in subgroup_elements) == generated:
                return [elem1, elem2]

    # Try triples (for small groups)
    if len(subgroup_elements) <= 20:
        for elem1, elem2, elem3 in combinations(non_identity, 3):
            generated = generate_subgroup_from_generators([elem1, elem2, elem3], n)
            if len(generated) == len(subgroup_elements):
                if frozenset(tuple(e) for e in subgroup_elements) == generated:
                    return [elem1, elem2, elem3]

    # Fallback: return all non-identity elements (not minimal, but works)
    return non_identity[:3] if len(non_identity) > 3 else non_identity

def is_normal_subgroup(subgroup_elements: List[List[int]], group_elements: List[List[int]]) -> bool:
    """Check if H is a normal subgroup of G: for all g in G, h in H: ghg^-1 in H"""
    subgroup_set = {tuple(h) for h in subgroup_elements}

    for g in group_elements:
        g_inv = inverse_permutation(g)
        for h in subgroup_elements:
            # Compute ghg^-1
            conjugate = compose_permutations(compose_permutations(g, h), g_inv)
            if tuple(conjugate) not in subgroup_set:
                return False

    return True

def map_to_sym_ids(elements: List[List[int]], automorphisms: List[Dict]) -> List[str]:
    """Map permutation elements back to their sym_id names from the level JSON"""
    result = []
    for elem in elements:
        for auto in automorphisms:
            if auto['mapping'] == elem:
                result.append(auto['id'])
                break
    return result

def process_level(level_num: int) -> Dict:
    """Process a single level and compute all subgroups"""
    level_path = f"TheSymmetryVaults/data/levels/act1/level_{level_num:02d}.json"

    if not os.path.exists(level_path):
        return None

    with open(level_path, 'r', encoding='utf-8') as f:
        level_data = json.load(f)

    meta = level_data['meta']
    automorphisms = level_data['symmetries']['automorphisms']

    # Extract all permutations
    group_elements = [auto['mapping'] for auto in automorphisms]
    n = len(group_elements[0])

    print(f"Level {level_num}: {meta['title']} ({meta['group_name']}, order {meta['group_order']})")

    # Find all subgroups
    subgroups = find_all_subgroups(group_elements)

    # Process each subgroup
    subgroup_data = []
    for sg in subgroups:
        # Find generators
        generators = find_minimal_generators(sg['elements'], n)

        # Check if normal
        is_normal = is_normal_subgroup(sg['elements'], group_elements)

        # Map to sym_ids
        sym_ids = map_to_sym_ids(sg['elements'], automorphisms)
        generator_ids = map_to_sym_ids(generators, automorphisms)

        subgroup_data.append({
            'order': sg['order'],
            'elements': sym_ids,
            'generators': generator_ids,
            'is_trivial': sg['is_trivial'],
            'is_normal': is_normal
        })

    # Sort by order
    subgroup_data.sort(key=lambda x: x['order'])

    print(f"  Found {len(subgroup_data)} subgroups")

    return {
        'level': level_num,
        'title': meta['title'],
        'group_name': meta['group_name'],
        'group_order': meta['group_order'],
        'subgroup_count': len(subgroup_data),
        'subgroups': subgroup_data
    }

def main():
    """Process all 24 levels"""
    import sys
    import io

    # Set UTF-8 encoding for stdout
    if sys.stdout.encoding != 'utf-8':
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

    results = []

    for level_num in range(1, 25):
        result = process_level(level_num)
        if result:
            results.append(result)

    # Save to JSON
    output_path = ".tayfa/math_consultant/T095_subgroups_data.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"\n[INFO] Saved results to {output_path}")

    # Print summary
    print("\n=== SUMMARY ===")
    print(f"{'Level':<8} {'Group':<10} {'Order':<8} {'Subgroups':<12} {'Too many?'}")
    print("-" * 60)
    for result in results:
        too_many = "[!!!]" if result['subgroup_count'] > 10 else ""
        print(f"{result['level']:<8} {result['group_name']:<10} {result['group_order']:<8} {result['subgroup_count']:<12} {too_many}")

if __name__ == "__main__":
    main()
