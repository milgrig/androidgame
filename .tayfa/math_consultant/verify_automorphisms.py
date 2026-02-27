"""
Graph Automorphism Verification Script
Mathematically verifies automorphism groups for levels 4-12
Author: math_consultant
"""

import json
import itertools
from pathlib import Path
from typing import List, Dict, Tuple, Set
from collections import defaultdict


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
            directed = edge.get('directed', False)

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

    def find_all_automorphisms(self) -> List[List[int]]:
        """Brute force: find ALL automorphisms"""
        automorphisms = []

        # Try all permutations
        for perm in itertools.permutations(range(self.n)):
            perm_list = list(perm)
            if self.is_automorphism(perm_list):
                automorphisms.append(perm_list)

        return automorphisms


def compose_permutations(p1: List[int], p2: List[int]) -> List[int]:
    """Compose two permutations: (p1 ∘ p2)[i] = p1[p2[i]]"""
    return [p1[p2[i]] for i in range(len(p1))]


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

    # Check closure
    for a1 in automorphisms:
        for a2 in automorphisms:
            composition = compose_permutations(a1, a2)
            if permutation_to_tuple(composition) not in auto_set:
                issues.append(f"Closure violated: {a1} ∘ {a2} = {composition} not in group")

    # Check inverses
    for a in automorphisms:
        # Find inverse: a^-1 such that a ∘ a^-1 = identity
        inverse = [0] * len(a)
        for i in range(len(a)):
            inverse[a[i]] = i

        if permutation_to_tuple(inverse) not in auto_set:
            issues.append(f"Inverse missing for {a}: inverse = {inverse}")

    return len(issues) == 0, issues


def build_cayley_table(automorphisms: Dict[str, List[int]]) -> Dict[str, Dict[str, str]]:
    """Build Cayley table from automorphisms"""
    table = {}

    for id1, perm1 in automorphisms.items():
        table[id1] = {}
        for id2, perm2 in automorphisms.items():
            composition = compose_permutations(perm1, perm2)

            # Find which automorphism this composition is
            result_id = None
            for id_check, perm_check in automorphisms.items():
                if perm_check == composition:
                    result_id = id_check
                    break

            table[id1][id2] = result_id if result_id else "ERROR"

    return table


def verify_cayley_table(computed: Dict, claimed: Dict) -> Tuple[bool, List[str]]:
    """Compare computed Cayley table with claimed one"""
    issues = []

    for g1 in computed:
        if g1 not in claimed:
            issues.append(f"Element {g1} in computed table but not in claimed")
            continue

        for g2 in computed[g1]:
            if g2 not in claimed[g1]:
                issues.append(f"Element {g2} missing from claimed table row {g1}")
                continue

            if computed[g1][g2] != claimed[g1][g2]:
                issues.append(
                    f"Cayley table mismatch: {g1} * {g2} = "
                    f"{computed[g1][g2]} (computed) vs {claimed[g1][g2]} (claimed)"
                )

    return len(issues) == 0, issues


def verify_level(level_path: Path) -> Dict:
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
        'warnings': []
    }

    # Build graph
    graph = Graph(graph_data['nodes'], graph_data['edges'])

    # Compute ALL automorphisms
    computed_autos = graph.find_all_automorphisms()
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

    # Check: are there automorphisms we computed that are not claimed?
    claimed_set = {permutation_to_tuple(m) for m in claimed_autos.values()}
    computed_set = {permutation_to_tuple(m) for m in computed_autos}

    missing = computed_set - claimed_set
    if missing:
        result['warnings'].append(
            f"Found {len(missing)} automorphisms not claimed: {list(missing)[:3]}..."
        )

    extra = claimed_set - computed_set
    if extra:
        result['issues'].append(
            f"Claimed {len(extra)} automorphisms that are NOT valid: {list(extra)}"
        )

    # Check group closure
    closure_ok, closure_issues = verify_group_closure(list(claimed_autos.values()))
    if not closure_ok:
        result['issues'].extend(closure_issues)

    # Check Cayley table if provided
    if 'cayley_table' in symmetries and symmetries['cayley_table']:
        computed_table = build_cayley_table(claimed_autos)
        claimed_table = symmetries['cayley_table']

        table_ok, table_issues = verify_cayley_table(computed_table, claimed_table)
        if not table_ok:
            result['issues'].extend(table_issues)

    # Check generators
    if 'generators' in symmetries:
        # TODO: verify generators actually generate the group
        result['generators_claimed'] = symmetries['generators']

    result['status'] = 'PASS' if len(result['issues']) == 0 else 'FAIL'

    return result


def main():
    """Run verification on levels 4-12"""
    levels_dir = Path(__file__).parent.parent.parent / 'TheSymmetryVaults' / 'data' / 'levels' / 'act1'

    results = []

    for level_num in range(1, 13):
        level_file = levels_dir / f'level_{level_num:02d}.json'

        if not level_file.exists():
            print(f"⚠️  Level {level_num} file not found: {level_file}")
            continue

        print(f"\n{'='*60}")
        print(f"Verifying Level {level_num}...")
        print(f"{'='*60}")

        result = verify_level(level_file)
        results.append(result)

        # Print result
        status_icon = "[PASS]" if result['status'] == 'PASS' else "[FAIL]"
        print(f"{status_icon} Level {result['level']}")
        print(f"   Group: {result['claimed_group']} (order {result['claimed_order']})")
        print(f"   Computed order: {result['computed_order']}")

        if result['issues']:
            print(f"   [!] ISSUES COUNT: {len(result['issues'])}")

        if result['warnings']:
            print(f"   [WARNING] COUNT: {len(result['warnings'])}")

        if result['status'] == 'PASS':
            print(f"   [OK] All checks passed!")

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")

    passed = sum(1 for r in results if r['status'] == 'PASS')
    failed = sum(1 for r in results if r['status'] == 'FAIL')

    print(f"Total levels: {len(results)}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")

    if failed > 0:
        print(f"\n[!] FAILED LEVELS:")
        for r in results:
            if r['status'] == 'FAIL':
                print(f"   - Level {r['level']}: {r['title']}")

    # Save results to JSON
    output_file = Path(__file__).parent / 'verification_results.json'
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"\n[SAVED] Detailed results saved to: {output_file}")

    return results


if __name__ == '__main__':
    main()
