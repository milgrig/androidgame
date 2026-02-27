#!/usr/bin/env python3
"""
Analyze edge types in all levels to determine if they are mathematically necessary
or just decorative.

For edge types to be necessary, they must:
1. Be preserved by automorphisms (only edges of same type can map to each other)
2. Actually constrain the automorphism group (removing edge types would increase group size)
"""

import json
import os
from typing import List, Dict, Set, Tuple
from collections import defaultdict

def analyze_level_edges(level_num: int) -> Dict:
    """Analyze edge types for a single level"""
    level_path = f"TheSymmetryVaults/data/levels/act1/level_{level_num:02d}.json"

    if not os.path.exists(level_path):
        return None

    with open(level_path, 'r', encoding='utf-8') as f:
        level_data = json.load(f)

    meta = level_data['meta']
    graph = level_data['graph']
    automorphisms = level_data['symmetries']['automorphisms']

    # Count edge types
    edge_types = {}
    for edge in graph['edges']:
        edge_type = edge.get('type', 'standard')
        if edge_type not in edge_types:
            edge_types[edge_type] = []
        edge_types[edge_type].append((edge['from'], edge['to']))

    # Check if all edges are the same type
    all_same = len(edge_types) == 1

    # Check if automorphisms preserve edge types
    # (This would indicate edge types are mathematically meaningful)
    edge_types_preserved = True

    if not all_same:
        # For each automorphism, check if it maps edges of type T to edges of type T
        for auto in automorphisms:
            mapping = auto['mapping']
            for edge_type, edges in edge_types.items():
                for from_node, to_node in edges:
                    # After applying automorphism, where do these nodes go?
                    new_from = mapping[from_node]
                    new_to = mapping[to_node]

                    # Check if there's an edge from new_from to new_to
                    # and if it has the same type
                    found_edge = False
                    for edge in graph['edges']:
                        if ((edge['from'] == new_from and edge['to'] == new_to) or
                            (edge['from'] == new_to and edge['to'] == new_from)):
                            if edge.get('type', 'standard') != edge_type:
                                edge_types_preserved = False
                            found_edge = True
                            break

    # Count node colors
    node_colors = {}
    for node in graph['nodes']:
        color = node.get('color', 'default')
        if color not in node_colors:
            node_colors[color] = []
        node_colors[color].append(node['id'])

    all_same_color = len(node_colors) == 1

    return {
        'level': level_num,
        'title': meta['title'],
        'group_name': meta['group_name'],
        'group_order': meta['group_order'],
        'edge_types': list(edge_types.keys()),
        'edge_type_counts': {k: len(v) for k, v in edge_types.items()},
        'all_edges_same_type': all_same,
        'edge_types_preserved': edge_types_preserved,
        'node_colors': list(node_colors.keys()),
        'all_nodes_same_color': all_same_color,
        'recommendation': 'KEEP_VARIED' if (not all_same and edge_types_preserved) else
                         ('SIMPLIFY_TO_STANDARD' if not all_same else 'OK_STANDARD')
    }

def main():
    """Analyze all 24 levels"""
    import sys
    import io

    # Set UTF-8 encoding for stdout
    if sys.stdout.encoding != 'utf-8':
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

    results = []

    print("=" * 80)
    print("EDGE TYPE ANALYSIS FOR ALL LEVELS")
    print("=" * 80)
    print()

    for level_num in range(1, 25):
        result = analyze_level_edges(level_num)
        if result:
            results.append(result)

    # Print summary
    print(f"{'Level':<6} {'Group':<8} {'Edge Types':<30} {'Recommendation'}")
    print("-" * 80)

    needs_simplification = []

    for r in results:
        edge_type_str = ", ".join([f"{t}({c})" for t, c in r['edge_type_counts'].items()])

        if r['recommendation'] == 'SIMPLIFY_TO_STANDARD':
            needs_simplification.append(r)
            print(f"{r['level']:<6} {r['group_name']:<8} {edge_type_str:<30} ⚠️  SIMPLIFY")
        elif r['recommendation'] == 'OK_STANDARD':
            print(f"{r['level']:<6} {r['group_name']:<8} {edge_type_str:<30} ✓  OK")
        else:
            print(f"{r['level']:<6} {r['group_name']:<8} {edge_type_str:<30} ✓  KEEP (needed)")

    print()
    print("=" * 80)
    print(f"SUMMARY: {len(needs_simplification)} levels need edge type simplification")
    print("=" * 80)
    print()

    if needs_simplification:
        print("LEVELS TO SIMPLIFY (change all edges to 'standard'):")
        print()
        for r in needs_simplification:
            print(f"Level {r['level']:2d}: {r['title']}")
            print(f"  Current edge types: {', '.join([f'{t}({c})' for t, c in r['edge_type_counts'].items()])}")
            print(f"  Group: {r['group_name']} (order {r['group_order']})")
            print()

    # Save results
    output_path = ".tayfa/math_consultant/edge_type_analysis.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"[INFO] Detailed results saved to {output_path}")

if __name__ == "__main__":
    main()
