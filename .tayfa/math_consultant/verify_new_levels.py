"""
Extended Graph Automorphism Verification Script
Verifies automorphism groups for NEW levels 13-24
Author: math_consultant
Task: T085
"""

import json
import itertools
from pathlib import Path
from typing import List, Dict, Tuple, Set
from collections import defaultdict
import sys


class Graph:
    """Represents a graph with colored nodes and typed edges"""

    def __init__(self, nodes: List[Dict], edges: List[Dict]):
        self.nodes = {n['id']: n for n in nodes}
        self.n = len(nodes)
        self.edges = edges
        self.adj_matrix = self._build_adjacency()

    def _build_adjacency(self) -> Dict[Tuple[int, int], Dict]:
        """Build adjacency structure preserving edge types and directions"""
        adj = {}
        for edge in self.edges:
            from_id = edge['from']
            to_id = edge['to']
            edge_type = edge.get('type', 'standard')
            directed = edge.get('directed', False) or edge_type == 'directed'

            adj[(from_id, to_id)] = {'type': edge_type, 'directed': directed}

            # For undirected edges, add reverse
            if not directed:
                adj[(to_id, from_id)] = {'type': edge_type, 'directed': False}

        return adj

    def is_automorphism(self, perm: List[int]) -> bool:
        """Check if permutation is a graph automorphism"""
        # Check: perm must preserve node colors
        for i in range(self.n):
            if self.nodes[i]['color'] != self.nodes[perm[i]]['color']:
                return False

        # Check: perm must preserve edges (type and direction)
        for (u, v), edge_data in self.adj_matrix.items():
            # After applying permutation: u -> perm[u], v -> perm[v]
            # The edge (perm[u], perm[v]) must exist with same properties
            mapped_edge = self.adj_matrix.get((perm[u], perm[v]))

            if mapped_edge is None:
                return False

            if mapped_edge['type'] != edge_data['type']:
                return False

            if mapped_edge['directed'] != edge_data['directed']:
                return False

        return True

    def find_all_automorphisms(self, max_check=None) -> List[List[int]]:
        """Find ALL automorphisms (with optional limit for large groups)"""
        automorphisms = []

        # For large graphs, we can't check all permutations
        if self.n > 10:
            print(f"   [WARNING] Graph has {self.n} nodes - cannot brute force all {self.factorial(self.n)} permutations")
            return None

        # Try all permutations
        count = 0
        for perm in itertools.permutations(range(self.n)):
            perm_list = list(perm)
            if self.is_automorphism(perm_list):
                automorphisms.append(perm_list)

            count += 1
            if max_check and count >= max_check:
                print(f"   [WARNING] Stopped after checking {count} permutations")
                break

        return automorphisms

    @staticmethod
    def factorial(n):
        """Calculate factorial"""
        if n <= 1:
            return 1
        return n * Graph.factorial(n - 1)


def compose_permutations(p1: List[int], p2: List[int]) -> List[int]:
    """Compose two permutations: (p1 ∘ p2)[i] = p1[p2[i]]"""
    return [p1[p2[i]] for i in range(len(p1))]


def permutation_inverse(perm: List[int]) -> List[int]:
    """Find inverse of a permutation"""
    inverse = [0] * len(perm)
    for i in range(len(perm)):
        inverse[perm[i]] = i
    return inverse


def permutation_to_tuple(perm: List[int]) -> Tuple[int, ...]:
    """Convert permutation to hashable tuple"""
    return tuple(perm)


def verify_group_closure(automorphisms: List[List[int]]) -> Tuple[bool, List[str]]:
    """Verify that automorphisms form a group (closure property)"""
    issues = []
    auto_set = {permutation_to_tuple(a) for a in automorphisms}

    # Check identity
    identity = tuple(range(len(automorphisms[0])))
    if identity not in auto_set:
        issues.append("Identity permutation missing!")

    # Check closure (sample for large groups)
    sample_size = min(len(automorphisms), 20)
    import random
    sample = random.sample(automorphisms, sample_size) if len(automorphisms) > 20 else automorphisms

    for a1 in sample:
        for a2 in sample:
            composition = compose_permutations(a1, a2)
            if permutation_to_tuple(composition) not in auto_set:
                issues.append(f"Closure violated: composition not in group")
                break
        if issues:
            break

    # Check inverses (sample)
    for a in sample:
        inverse = permutation_inverse(a)
        if permutation_to_tuple(inverse) not in auto_set:
            issues.append(f"Inverse missing for element")
            break

    return len(issues) == 0, issues


def verify_generators(claimed_autos: Dict[str, List[int]], generators: List[str]) -> Tuple[bool, List[str]]:
    """Verify that generators actually generate the full group"""
    issues = []

    if not generators:
        issues.append("No generators specified")
        return False, issues

    # Build generated subgroup
    generated = set()
    generated.add(tuple(range(len(claimed_autos[generators[0]]))))  # Identity

    queue = []
    for gen_id in generators:
        if gen_id not in claimed_autos:
            issues.append(f"Generator '{gen_id}' not found in automorphisms")
            return False, issues
        queue.append(claimed_autos[gen_id])
        generated.add(permutation_to_tuple(claimed_autos[gen_id]))

    # BFS to generate all elements
    max_iterations = 10000
    iterations = 0
    while queue and iterations < max_iterations:
        current = queue.pop(0)
        iterations += 1

        # Multiply current by all generators
        for gen_id in generators:
            gen = claimed_autos[gen_id]

            # current * gen
            product = compose_permutations(current, gen)
            product_tuple = permutation_to_tuple(product)
            if product_tuple not in generated:
                generated.add(product_tuple)
                queue.append(product)

            # gen * current
            product2 = compose_permutations(gen, current)
            product2_tuple = permutation_to_tuple(product2)
            if product2_tuple not in generated:
                generated.add(product2_tuple)
                queue.append(product2)

    # Compare with full group
    full_group = {permutation_to_tuple(m) for m in claimed_autos.values()}

    if generated != full_group:
        issues.append(
            f"Generators produce {len(generated)} elements, but group has {len(full_group)} elements"
        )
        return False, issues

    return True, []


def analyze_subgroup_structure(claimed_autos: Dict[str, List[int]], group_name: str) -> Dict:
    """Analyze subgroup structure for future layers"""
    n = len(claimed_autos[list(claimed_autos.keys())[0]])
    order = len(claimed_autos)

    analysis = {
        'order': order,
        'divisors': [],
        'potential_subgroups': [],
        'normal_subgroups_check': None
    }

    # Find divisors of group order
    for d in range(1, order + 1):
        if order % d == 0:
            analysis['divisors'].append(d)

    # For known groups, list expected subgroup orders
    if group_name == 'Z7':
        analysis['potential_subgroups'] = [1, 7]  # Prime - only trivial
        analysis['expected_normal'] = [1, 7]
    elif group_name == 'Z8':
        analysis['potential_subgroups'] = [1, 2, 4, 8]
        analysis['expected_normal'] = [1, 2, 4, 8]  # All subgroups normal in abelian
    elif group_name == 'S4':
        analysis['potential_subgroups'] = [1, 2, 3, 4, 6, 8, 12, 24]
        analysis['expected_normal'] = [1, 4, 12, 24]  # {e}, V4, A4, S4
    elif group_name == 'A4':
        analysis['potential_subgroups'] = [1, 2, 3, 4, 6, 12]
        analysis['expected_normal'] = [1, 4, 12]  # {e}, V4, A4
    elif group_name == 'D4':
        analysis['potential_subgroups'] = [1, 2, 4, 8]
        analysis['expected_normal'] = [1, 2, 4, 8]  # Several normal subgroups
    elif group_name in ['D3', 'D5', 'D6']:
        n_sides = int(group_name[1])
        analysis['potential_subgroups'] = analysis['divisors']
        analysis['expected_normal'] = [1, n_sides, 2 * n_sides]  # {e}, Zn, Dn
    elif group_name == 'Q8':
        analysis['potential_subgroups'] = [1, 2, 4, 8]
        analysis['expected_normal'] = [1, 2, 4, 8]  # ALL subgroups normal!
    elif group_name == 'S5':
        analysis['potential_subgroups'] = 'many'
        analysis['expected_normal'] = [1, 60, 120]  # {e}, A5, S5
    elif group_name == 'D4 × Z2':
        analysis['potential_subgroups'] = 'product structure'
        analysis['expected_normal'] = 'multiple from product'

    return analysis


def verify_level(level_path: Path, run_full_check: bool = True) -> Dict:
    """Verify a single level's mathematical correctness"""
    with open(level_path, 'r', encoding='utf-8') as f:
        level_data = json.load(f)

    meta = level_data['meta']
    graph_data = level_data['graph']
    symmetries = level_data['symmetries']

    result = {
        'level': meta['level'],
        'title': meta['title'],
        'claimed_group': meta['group_name'],
        'claimed_order': meta['group_order'],
        'issues': [],
        'warnings': [],
        'skipped_checks': []
    }

    # Build graph
    graph = Graph(graph_data['nodes'], graph_data['edges'])

    # For large groups (order > 50), skip brute force check
    if meta['group_order'] > 50 and run_full_check:
        result['skipped_checks'].append(f"Brute force automorphism search (group too large: {meta['group_order']})")
        computed_autos = None
        result['computed_order'] = '(not computed - too large)'
    else:
        # Compute ALL automorphisms
        computed_autos = graph.find_all_automorphisms()

        if computed_autos is None:
            result['skipped_checks'].append("Full automorphism computation (graph too large)")
            result['computed_order'] = '(not computed)'
        else:
            result['computed_order'] = len(computed_autos)

            # Check: does count match?
            if len(computed_autos) != meta['group_order']:
                result['issues'].append(
                    f"Group order mismatch: computed {len(computed_autos)}, claimed {meta['group_order']}"
                )

    # Check: are all claimed automorphisms actually automorphisms?
    claimed_autos = {a['id']: a['mapping'] for a in symmetries['automorphisms']}

    for auto_id, mapping in claimed_autos.items():
        if not graph.is_automorphism(mapping):
            result['issues'].append(
                f"Claimed automorphism '{auto_id}' = {mapping} is NOT a valid automorphism!"
            )

    # If we computed all automorphisms, check completeness
    if computed_autos is not None:
        claimed_set = {permutation_to_tuple(m) for m in claimed_autos.values()}
        computed_set = {permutation_to_tuple(m) for m in computed_autos}

        missing = computed_set - claimed_set
        if missing:
            result['warnings'].append(
                f"Found {len(missing)} automorphisms not claimed"
            )

        extra = claimed_set - computed_set
        if extra:
            result['issues'].append(
                f"Claimed {len(extra)} automorphisms that are NOT valid"
            )

    # Check: count matches claimed
    if len(claimed_autos) != meta['group_order']:
        result['issues'].append(
            f"Claimed {len(claimed_autos)} automorphisms, but group_order is {meta['group_order']}"
        )

    # Check group closure (sample for large groups)
    closure_ok, closure_issues = verify_group_closure(list(claimed_autos.values()))
    if not closure_ok:
        result['issues'].extend(closure_issues)

    # Check generators
    if 'generators' in symmetries and symmetries['generators']:
        gen_ok, gen_issues = verify_generators(claimed_autos, symmetries['generators'])
        result['generators_claimed'] = symmetries['generators']
        result['generators_valid'] = gen_ok
        if not gen_ok:
            result['warnings'].extend(gen_issues)
    else:
        result['warnings'].append("No generators specified")

    # Analyze subgroup structure for future layers
    result['subgroup_analysis'] = analyze_subgroup_structure(
        claimed_autos,
        meta['group_name']
    )

    # Check graph structure validity
    graph_issues = []

    # Check: all node IDs are sequential
    node_ids = [n['id'] for n in graph_data['nodes']]
    if node_ids != list(range(len(node_ids))):
        graph_issues.append(f"Node IDs not sequential: {node_ids}")

    # Check: all edges reference valid nodes
    for edge in graph_data['edges']:
        if edge['from'] not in range(len(node_ids)):
            graph_issues.append(f"Edge 'from' {edge['from']} references invalid node")
        if edge['to'] not in range(len(node_ids)):
            graph_issues.append(f"Edge 'to' {edge['to']} references invalid node")

    if graph_issues:
        result['issues'].extend(graph_issues)

    result['status'] = 'PASS' if len(result['issues']) == 0 else 'FAIL'

    return result


def main():
    """Run verification on NEW levels 13-24"""
    # Set UTF-8 encoding for console
    import sys
    if sys.platform == 'win32':
        import codecs
        sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')
        sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'strict')

    levels_dir = Path(__file__).parent.parent.parent / 'TheSymmetryVaults' / 'data' / 'levels' / 'act1'

    print("="*80)
    print("MATHEMATICAL VERIFICATION: NEW LEVELS 13-24")
    print("Task: T085")
    print("="*80)

    results = []

    for level_num in range(13, 25):
        level_file = levels_dir / f'level_{level_num:02d}.json'

        if not level_file.exists():
            print(f"\n⚠️  Level {level_num} file not found: {level_file}")
            continue

        print(f"\n{'='*80}")
        print(f"Verifying Level {level_num}...")
        print(f"{'='*80}")

        # For very large groups (S5), skip full automorphism check
        run_full = level_num != 23  # Level 23 is S5 with 120 elements

        result = verify_level(level_file, run_full_check=run_full)
        results.append(result)

        # Print result
        status_icon = "[PASS]" if result['status'] == 'PASS' else "[FAIL]"
        print(f"\n{status_icon} Level {result['level']}: {result['title']}")
        print(f"   Group: {result['claimed_group']} (order {result['claimed_order']})")
        print(f"   Computed order: {result['computed_order']}")

        if result.get('generators_claimed'):
            gen_status = "[OK]" if result.get('generators_valid') else "[FAIL]"
            print(f"   Generators {gen_status}: {result['generators_claimed']}")

        if result['issues']:
            print(f"   [!] ISSUES: {len(result['issues'])}")
            for issue in result['issues'][:3]:  # Show first 3
                print(f"      - {issue}")

        if result['warnings']:
            print(f"   [WARN] WARNINGS: {len(result['warnings'])}")
            for warning in result['warnings'][:2]:  # Show first 2
                print(f"      - {warning}")

        if result['skipped_checks']:
            print(f"   [SKIP] SKIPPED: {', '.join(result['skipped_checks'])}")

        # Subgroup analysis
        if 'subgroup_analysis' in result:
            analysis = result['subgroup_analysis']
            print(f"   [INFO] Subgroup Analysis:")
            print(f"      Order: {analysis['order']}")
            print(f"      Divisors: {analysis['divisors']}")
            if 'expected_normal' in analysis:
                print(f"      Expected normal subgroup orders: {analysis['expected_normal']}")

        if result['status'] == 'PASS':
            print(f"   [OK] All checks passed!")

    # Summary
    print(f"\n{'='*80}")
    print("SUMMARY")
    print(f"{'='*80}")

    passed = sum(1 for r in results if r['status'] == 'PASS')
    failed = sum(1 for r in results if r['status'] == 'FAIL')

    print(f"Total levels verified: {len(results)}")
    print(f"[PASS] Passed: {passed}")
    print(f"[FAIL] Failed: {failed}")

    if failed > 0:
        print(f"\n[FAIL] FAILED LEVELS:")
        for r in results:
            if r['status'] == 'FAIL':
                print(f"   - Level {r['level']}: {r['title']}")
                print(f"     Issues: {len(r['issues'])}")

    # Save results to JSON
    output_file = Path(__file__).parent / 'T085_verification_results.json'
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"\n[SAVED] Detailed results saved to: {output_file}")

    return results


if __name__ == '__main__':
    main()
