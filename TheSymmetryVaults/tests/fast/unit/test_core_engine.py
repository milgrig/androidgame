"""
Unit tests for core permutation engine.
Python mirror of GDScript logic for executable verification.
Tests validate the mathematical correctness of permutation.gd,
graph_engine.gd, and key_ring.gd using real level data from T003.
"""
import itertools
import unittest


# === Python mirrors of GDScript classes (minimal, for testing) ===

class Permutation:
    def __init__(self, mapping: list[int]):
        self.mapping = list(mapping)

    def size(self) -> int:
        return len(self.mapping)

    def apply(self, i: int) -> int:
        return self.mapping[i]

    def is_valid(self) -> bool:
        n = self.size()
        return n > 0 and sorted(self.mapping) == list(range(n))

    def is_identity(self) -> bool:
        return all(self.mapping[i] == i for i in range(self.size()))

    def compose(self, other: "Permutation") -> "Permutation":
        assert self.size() == other.size()
        return Permutation([other.apply(self.apply(i)) for i in range(self.size())])

    def inverse(self) -> "Permutation":
        inv = [0] * self.size()
        for i, v in enumerate(self.mapping):
            inv[v] = i
        return Permutation(inv)

    def order(self) -> int:
        current = self
        identity = Permutation.create_identity(self.size())
        for k in range(1, 1000):
            if current.equals(identity):
                return k
            current = current.compose(self)
        return -1

    def equals(self, other: "Permutation") -> bool:
        return self.mapping == other.mapping

    def to_cycle_notation(self) -> str:
        visited = set()
        cycles = []
        for i in range(self.size()):
            if i in visited:
                continue
            cycle = []
            j = i
            while j not in visited:
                visited.add(j)
                cycle.append(j)
                j = self.mapping[j]
            if len(cycle) > 1:
                cycles.append("(" + " ".join(str(c) for c in cycle) + ")")
        return "".join(cycles) if cycles else "()"

    @staticmethod
    def create_identity(n: int) -> "Permutation":
        return Permutation(list(range(n)))


class CrystalGraph:
    def __init__(self, nodes: list[dict], edges: list[dict]):
        self.nodes = nodes
        self.edges = edges

    def node_count(self) -> int:
        return len(self.nodes)

    def get_node_color(self, node_id: int) -> str:
        for n in self.nodes:
            if n["id"] == node_id:
                return n.get("color", "")
        return ""

    def get_edge(self, from_id: int, to_id: int) -> dict | None:
        """Return edge dict or None. Directed edges only match exact order."""
        for e in self.edges:
            if e["from"] == from_id and e["to"] == to_id:
                return e
            if not e.get("directed", False):
                if e["from"] == to_id and e["to"] == from_id:
                    return e
        return None

    def get_edge_type(self, from_id: int, to_id: int) -> str:
        e = self.get_edge(from_id, to_id)
        if e is None:
            return ""
        return e.get("type", "")

    def is_automorphism(self, p: Permutation) -> bool:
        if p.size() != self.node_count():
            return False
        for i in range(self.node_count()):
            if self.get_node_color(i) != self.get_node_color(p.apply(i)):
                return False
        for edge in self.edges:
            mapped_from = p.apply(edge["from"])
            mapped_to = p.apply(edge["to"])
            mapped_edge = self.get_edge(mapped_from, mapped_to)
            if mapped_edge is None:
                return False
            if mapped_edge.get("type", "") != edge.get("type", ""):
                return False
            if edge.get("directed", False) != mapped_edge.get("directed", False):
                return False
        return True

    def find_violations(self, p: "Permutation") -> dict:
        """Returns details about WHY a permutation is NOT an automorphism.
        Python mirror of CrystalGraph.find_violations() in graph_engine.gd."""
        result = {
            "is_valid": True,
            "color_violations": [],
            "edge_violations": [],
            "summary": ""
        }
        if p.size() != self.node_count():
            result["is_valid"] = False
            result["summary"] = "Wrong number of nodes"
            return result

        # Check node colors
        for i in range(self.node_count()):
            from_color = self.get_node_color(i)
            to_color = self.get_node_color(p.apply(i))
            if from_color != to_color:
                result["is_valid"] = False
                result["color_violations"].append({
                    "node_id": i,
                    "mapped_id": p.apply(i),
                    "from_color": from_color,
                    "to_color": to_color
                })

        # Check edges
        for edge in self.edges:
            mapped_from = p.apply(edge["from"])
            mapped_to = p.apply(edge["to"])
            mapped_edge = self.get_edge(mapped_from, mapped_to)
            if mapped_edge is None:
                result["is_valid"] = False
                result["edge_violations"].append({
                    "from": edge["from"], "to": edge["to"],
                    "mapped_from": mapped_from, "mapped_to": mapped_to,
                    "reason": "missing_edge"
                })
            elif mapped_edge.get("type", "") != edge.get("type", ""):
                result["is_valid"] = False
                result["edge_violations"].append({
                    "from": edge["from"], "to": edge["to"],
                    "mapped_from": mapped_from, "mapped_to": mapped_to,
                    "reason": "type_mismatch"
                })
            elif edge.get("directed", False) != mapped_edge.get("directed", False):
                result["is_valid"] = False
                result["edge_violations"].append({
                    "from": edge["from"], "to": edge["to"],
                    "mapped_from": mapped_from, "mapped_to": mapped_to,
                    "reason": "direction_mismatch"
                })

        # Build summary
        if result["is_valid"]:
            result["summary"] = ""
        elif result["color_violations"] and result["edge_violations"]:
            result["summary"] = "Colors and edges don't match"
        elif result["color_violations"]:
            result["summary"] = "Crystal colors don't match after swap"
        else:
            reason = result["edge_violations"][0]["reason"]
            if reason == "missing_edge":
                result["summary"] = "An edge connection is broken by this swap"
            elif reason == "type_mismatch":
                result["summary"] = "Edge types don't match after swap"
            elif reason == "direction_mismatch":
                result["summary"] = "Edge direction is reversed by this swap"

        return result

    def find_all_automorphisms(self) -> list[Permutation]:
        n = self.node_count()
        result = []
        for perm in itertools.permutations(range(n)):
            p = Permutation(list(perm))
            if self.is_automorphism(p):
                result.append(p)
        return result


class KeyRing:
    def __init__(self, target_count: int = 0):
        self.found: list[Permutation] = []
        self.target_count = target_count

    def add_key(self, p: Permutation) -> bool:
        if self.contains(p):
            return False
        self.found.append(p)
        return True

    def contains(self, p: Permutation) -> bool:
        return any(k.equals(p) for k in self.found)

    def is_complete(self) -> bool:
        return len(self.found) >= self.target_count > 0

    def count(self) -> int:
        return len(self.found)

    def compose_keys(self, i: int, j: int) -> Permutation:
        return self.found[i].compose(self.found[j])

    def is_closed_under_composition(self) -> bool:
        for a in self.found:
            for b in self.found:
                if not self.contains(a.compose(b)):
                    return False
        return True

    def has_identity(self) -> bool:
        return any(k.is_identity() for k in self.found)

    def has_inverses(self) -> bool:
        return all(self.contains(k.inverse()) for k in self.found)

    def get_key(self, index: int) -> Permutation:
        """Get the key at the given index."""
        return self.found[index]

    def check_subgroup(self, indices: list[int]) -> dict:
        """Check if the selected keys (by index) form a subgroup.
        Returns {"is_subgroup": bool, "reasons": list[str]}."""
        if not indices:
            return {"is_subgroup": False, "reasons": ["empty_selection"]}

        subset = [self.found[i] for i in indices if 0 <= i < len(self.found)]
        if not subset:
            return {"is_subgroup": False, "reasons": ["invalid_indices"]}

        reasons = []

        # Check identity
        has_id = any(p.is_identity() for p in subset)
        if not has_id:
            reasons.append("missing_identity")

        # Check inverses
        for p in subset:
            inv = p.inverse()
            if not any(q.equals(inv) for q in subset):
                reasons.append("missing_inverse")
                break

        # Check closure under composition
        for a in subset:
            for b in subset:
                product = a.compose(b)
                if not any(q.equals(product) for q in subset):
                    reasons.append("not_closed_composition")
                    break
            if "not_closed_composition" in reasons:
                break

        is_subgroup = len(reasons) == 0
        return {"is_subgroup": is_subgroup, "reasons": reasons}

    def build_cayley_table(self) -> list[list[int]]:
        n = len(self.found)
        table = []
        for i in range(n):
            row = []
            for j in range(n):
                product = self.found[i].compose(self.found[j])
                idx = next((k for k, f in enumerate(self.found) if f.equals(product)), -1)
                if idx == -1:
                    return []
                row.append(idx)
            table.append(row)
        return table


# === Test Cases ===

class TestPermutation(unittest.TestCase):
    def test_identity(self):
        e = Permutation.create_identity(3)
        self.assertEqual(e.mapping, [0, 1, 2])
        self.assertTrue(e.is_identity())
        self.assertTrue(e.is_valid())

    def test_not_identity(self):
        r = Permutation([1, 2, 0])
        self.assertFalse(r.is_identity())
        self.assertTrue(r.is_valid())

    def test_invalid_permutation(self):
        self.assertFalse(Permutation([0, 0, 1]).is_valid())
        self.assertFalse(Permutation([0, 1, 3]).is_valid())
        self.assertFalse(Permutation([]).is_valid())

    def test_apply(self):
        r = Permutation([1, 2, 0])
        self.assertEqual(r.apply(0), 1)
        self.assertEqual(r.apply(1), 2)
        self.assertEqual(r.apply(2), 0)

    def test_compose_z3_rotations(self):
        """r . r = r^2 in Z3"""
        r = Permutation([1, 2, 0])
        r2 = r.compose(r)
        self.assertEqual(r2.mapping, [2, 0, 1])

    def test_compose_gives_identity(self):
        """r . r^2 = e in Z3"""
        r = Permutation([1, 2, 0])
        r2 = Permutation([2, 0, 1])
        e = r.compose(r2)
        self.assertTrue(e.is_identity())

    def test_inverse_z3(self):
        r = Permutation([1, 2, 0])
        r_inv = r.inverse()
        self.assertEqual(r_inv.mapping, [2, 0, 1])  # r^-1 = r^2
        product = r.compose(r_inv)
        self.assertTrue(product.is_identity())

    def test_inverse_identity(self):
        e = Permutation.create_identity(3)
        self.assertTrue(e.inverse().is_identity())

    def test_order_identity(self):
        e = Permutation.create_identity(3)
        self.assertEqual(e.order(), 1)

    def test_order_z3_rotation(self):
        r = Permutation([1, 2, 0])
        self.assertEqual(r.order(), 3)

    def test_order_z2_swap(self):
        s = Permutation([0, 2, 1])
        self.assertEqual(s.order(), 2)

    def test_equals(self):
        a = Permutation([1, 2, 0])
        b = Permutation([1, 2, 0])
        c = Permutation([2, 0, 1])
        self.assertTrue(a.equals(b))
        self.assertFalse(a.equals(c))

    def test_cycle_notation(self):
        self.assertEqual(Permutation([0, 1, 2]).to_cycle_notation(), "()")
        self.assertEqual(Permutation([1, 2, 0]).to_cycle_notation(), "(0 1 2)")
        self.assertEqual(Permutation([0, 2, 1]).to_cycle_notation(), "(1 2)")


class TestCrystalGraph(unittest.TestCase):
    def _make_level1_graph(self):
        """Level 1: uniform triangle, all RED, all STANDARD edges -> Z3"""
        nodes = [
            {"id": 0, "color": "RED"}, {"id": 1, "color": "RED"}, {"id": 2, "color": "RED"}
        ]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD"},
            {"from": 1, "to": 2, "type": "STANDARD"},
            {"from": 2, "to": 0, "type": "STANDARD"},
        ]
        return CrystalGraph(nodes, edges)

    def _make_level2_graph(self):
        """Level 2: triangle with directed edges (cycle 0→1→2→0) -> Z3 (rotations only)
        Directed cycle breaks reflections but preserves rotational symmetry."""
        nodes = [
            {"id": 0, "color": "BLUE"}, {"id": 1, "color": "BLUE"}, {"id": 2, "color": "BLUE"}
        ]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD", "directed": True},
            {"from": 1, "to": 2, "type": "STANDARD", "directed": True},
            {"from": 2, "to": 0, "type": "STANDARD", "directed": True},
        ]
        return CrystalGraph(nodes, edges)

    def _make_level3_graph(self):
        """Level 3: triangle with colored nodes (1 RED, 2 GREEN) -> Z2"""
        nodes = [
            {"id": 0, "color": "RED"}, {"id": 1, "color": "GREEN"}, {"id": 2, "color": "GREEN"}
        ]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD"},
            {"from": 1, "to": 2, "type": "STANDARD"},
            {"from": 2, "to": 0, "type": "STANDARD"},
        ]
        return CrystalGraph(nodes, edges)

    # --- Level 1 tests ---
    def test_level1_identity_is_automorphism(self):
        g = self._make_level1_graph()
        e = Permutation.create_identity(3)
        self.assertTrue(g.is_automorphism(e))

    def test_level1_rotation_is_automorphism(self):
        g = self._make_level1_graph()
        r = Permutation([1, 2, 0])
        self.assertTrue(g.is_automorphism(r))

    def test_level1_all_permutations_are_automorphisms(self):
        """Uniform triangle: all 6 permutations of S3 are automorphisms"""
        g = self._make_level1_graph()
        autos = g.find_all_automorphisms()
        self.assertEqual(len(autos), 6)  # Full S3

    # --- Level 2 tests ---
    # Level 2 uses directed edges forming a cycle (0→1→2→0).
    # Rotations preserve direction, reflections reverse it → Z3.
    def test_level2_rotation_is_automorphism(self):
        """Rotation (0→1→2→0) preserves directed cycle"""
        g = self._make_level2_graph()
        r = Permutation([1, 2, 0])
        self.assertTrue(g.is_automorphism(r))

    def test_level2_swap_not_automorphism(self):
        """Swap(1,2) reverses edge direction in directed cycle"""
        g = self._make_level2_graph()
        s = Permutation([0, 2, 1])
        self.assertFalse(g.is_automorphism(s))

    def test_level2_has_exactly_3_automorphisms(self):
        """Directed cycle on 3 nodes → Z3: {e, r, r²}"""
        g = self._make_level2_graph()
        autos = g.find_all_automorphisms()
        self.assertEqual(len(autos), 3)  # Z3: {e, r, r²}
        # Verify the specific mappings
        mappings = sorted([a.mapping for a in autos])
        self.assertEqual(mappings, [[0, 1, 2], [1, 2, 0], [2, 0, 1]])

    # --- Level 3 tests ---
    def test_level3_identity_is_automorphism(self):
        g = self._make_level3_graph()
        e = Permutation.create_identity(3)
        self.assertTrue(g.is_automorphism(e))

    def test_level3_swap_green_is_automorphism(self):
        g = self._make_level3_graph()
        s = Permutation([0, 2, 1])  # swap GREEN nodes
        self.assertTrue(g.is_automorphism(s))

    def test_level3_rotation_not_automorphism(self):
        """Rotation moves RED to GREEN position"""
        g = self._make_level3_graph()
        r = Permutation([1, 2, 0])
        self.assertFalse(g.is_automorphism(r))

    def test_level3_has_exactly_2_automorphisms(self):
        g = self._make_level3_graph()
        autos = g.find_all_automorphisms()
        self.assertEqual(len(autos), 2)  # Z2

    def test_wrong_size_permutation(self):
        g = self._make_level1_graph()
        p = Permutation([0, 1])
        self.assertFalse(g.is_automorphism(p))


class TestKeyRing(unittest.TestCase):
    def test_add_key(self):
        kr = KeyRing(3)
        e = Permutation.create_identity(3)
        self.assertTrue(kr.add_key(e))
        self.assertEqual(kr.count(), 1)

    def test_reject_duplicate(self):
        kr = KeyRing(3)
        e = Permutation.create_identity(3)
        kr.add_key(e)
        self.assertFalse(kr.add_key(Permutation([0, 1, 2])))
        self.assertEqual(kr.count(), 1)

    def test_is_complete(self):
        kr = KeyRing(3)
        kr.add_key(Permutation([0, 1, 2]))
        kr.add_key(Permutation([1, 2, 0]))
        self.assertFalse(kr.is_complete())
        kr.add_key(Permutation([2, 0, 1]))
        self.assertTrue(kr.is_complete())

    def test_contains(self):
        kr = KeyRing(3)
        r = Permutation([1, 2, 0])
        kr.add_key(r)
        self.assertTrue(kr.contains(Permutation([1, 2, 0])))
        self.assertFalse(kr.contains(Permutation([2, 0, 1])))

    def test_compose_keys(self):
        kr = KeyRing(3)
        kr.add_key(Permutation([1, 2, 0]))  # r
        kr.add_key(Permutation([1, 2, 0]))  # duplicate rejected
        kr.add_key(Permutation([2, 0, 1]))  # r^2
        result = kr.compose_keys(0, 0)  # r . r = r^2
        self.assertEqual(result.mapping, [2, 0, 1])

    def test_z3_closure(self):
        """Complete Z3 group is closed under composition"""
        kr = KeyRing(3)
        kr.add_key(Permutation([0, 1, 2]))  # e
        kr.add_key(Permutation([1, 2, 0]))  # r
        kr.add_key(Permutation([2, 0, 1]))  # r^2
        self.assertTrue(kr.is_closed_under_composition())
        self.assertTrue(kr.has_identity())
        self.assertTrue(kr.has_inverses())

    def test_incomplete_not_closed(self):
        kr = KeyRing(3)
        kr.add_key(Permutation([0, 1, 2]))  # e
        kr.add_key(Permutation([1, 2, 0]))  # r
        # Missing r^2, so r.r = r^2 not in set
        self.assertFalse(kr.is_closed_under_composition())

    def test_cayley_table_z3(self):
        kr = KeyRing(3)
        kr.add_key(Permutation([0, 1, 2]))  # e  (index 0)
        kr.add_key(Permutation([1, 2, 0]))  # r  (index 1)
        kr.add_key(Permutation([2, 0, 1]))  # r2 (index 2)
        table = kr.build_cayley_table()
        self.assertEqual(len(table), 3)
        # e.e=e, e.r=r, e.r2=r2
        self.assertEqual(table[0], [0, 1, 2])
        # r.e=r, r.r=r2, r.r2=e
        self.assertEqual(table[1], [1, 2, 0])
        # r2.e=r2, r2.r=e, r2.r2=r
        self.assertEqual(table[2], [2, 0, 1])

    def test_cayley_table_z2(self):
        kr = KeyRing(2)
        kr.add_key(Permutation([0, 1, 2]))  # e  (index 0)
        kr.add_key(Permutation([0, 2, 1]))  # s  (index 1)
        table = kr.build_cayley_table()
        self.assertEqual(table[0], [0, 1])  # e.e=e, e.s=s
        self.assertEqual(table[1], [1, 0])  # s.e=s, s.s=e

    def test_empty_keyring_not_complete(self):
        kr = KeyRing(3)
        self.assertFalse(kr.is_complete())
        self.assertEqual(kr.count(), 0)


class TestIntegration(unittest.TestCase):
    """End-to-end: build graph, find automorphisms, fill key ring, verify group"""

    def test_level1_full_workflow(self):
        """Level 1: uniform triangle -> discover all S3 symmetries"""
        nodes = [{"id": i, "color": "RED"} for i in range(3)]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD"},
            {"from": 1, "to": 2, "type": "STANDARD"},
            {"from": 2, "to": 0, "type": "STANDARD"},
        ]
        graph = CrystalGraph(nodes, edges)
        autos = graph.find_all_automorphisms()
        kr = KeyRing(len(autos))
        for a in autos:
            kr.add_key(a)
        self.assertTrue(kr.is_complete())
        self.assertTrue(kr.is_closed_under_composition())
        self.assertTrue(kr.has_identity())
        self.assertTrue(kr.has_inverses())
        self.assertEqual(kr.count(), 6)

    def test_level3_full_workflow(self):
        """Level 3: colored triangle -> discover Z2"""
        nodes = [
            {"id": 0, "color": "RED"}, {"id": 1, "color": "GREEN"}, {"id": 2, "color": "GREEN"}
        ]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD"},
            {"from": 1, "to": 2, "type": "STANDARD"},
            {"from": 2, "to": 0, "type": "STANDARD"},
        ]
        graph = CrystalGraph(nodes, edges)
        autos = graph.find_all_automorphisms()
        kr = KeyRing(len(autos))
        for a in autos:
            kr.add_key(a)
        self.assertTrue(kr.is_complete())
        self.assertTrue(kr.is_closed_under_composition())
        self.assertEqual(kr.count(), 2)
        # Verify the automorphisms are identity and swap(1,2)
        mappings = sorted([a.mapping for a in autos])
        self.assertEqual(mappings, [[0, 1, 2], [0, 2, 1]])

    def test_square_d4_group(self):
        """Square with uniform edges and colors -> D4 (8 symmetries)"""
        nodes = [{"id": i, "color": "BLUE"} for i in range(4)]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD"},
            {"from": 1, "to": 2, "type": "STANDARD"},
            {"from": 2, "to": 3, "type": "STANDARD"},
            {"from": 3, "to": 0, "type": "STANDARD"},
        ]
        graph = CrystalGraph(nodes, edges)
        autos = graph.find_all_automorphisms()
        kr = KeyRing(len(autos))
        for a in autos:
            kr.add_key(a)
        self.assertEqual(kr.count(), 8)  # D4
        self.assertTrue(kr.is_closed_under_composition())
        self.assertTrue(kr.has_identity())
        self.assertTrue(kr.has_inverses())


class TestFindViolations(unittest.TestCase):
    """T016: Test find_violations() returns detailed info about WHY
    a permutation is not an automorphism."""

    def _make_colored_triangle(self):
        """Level 3 style: 1 RED, 2 GREEN nodes, undirected edges"""
        nodes = [
            {"id": 0, "color": "RED"},
            {"id": 1, "color": "GREEN"},
            {"id": 2, "color": "GREEN"}
        ]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD"},
            {"from": 1, "to": 2, "type": "STANDARD"},
            {"from": 2, "to": 0, "type": "STANDARD"},
        ]
        return CrystalGraph(nodes, edges)

    def _make_directed_triangle(self):
        """Level 2 style: uniform color, directed cycle 0->1->2->0"""
        nodes = [
            {"id": 0, "color": "BLUE"},
            {"id": 1, "color": "BLUE"},
            {"id": 2, "color": "BLUE"}
        ]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD", "directed": True},
            {"from": 1, "to": 2, "type": "STANDARD", "directed": True},
            {"from": 2, "to": 0, "type": "STANDARD", "directed": True},
        ]
        return CrystalGraph(nodes, edges)

    def test_valid_automorphism_no_violations(self):
        """Identity on colored triangle should have no violations"""
        g = self._make_colored_triangle()
        result = g.find_violations(Permutation([0, 1, 2]))
        self.assertTrue(result["is_valid"])
        self.assertEqual(len(result["color_violations"]), 0)
        self.assertEqual(len(result["edge_violations"]), 0)
        self.assertEqual(result["summary"], "")

    def test_valid_reflection_no_violations(self):
        """Swap(1,2) on colored triangle is valid (Z2 reflection)"""
        g = self._make_colored_triangle()
        result = g.find_violations(Permutation([0, 2, 1]))
        self.assertTrue(result["is_valid"])
        self.assertEqual(len(result["color_violations"]), 0)
        self.assertEqual(len(result["edge_violations"]), 0)

    def test_color_violation_detected(self):
        """Swap(0,1) on colored triangle: RED<->GREEN color mismatch"""
        g = self._make_colored_triangle()
        # [1,0,2] swaps node 0 (RED) with node 1 (GREEN)
        result = g.find_violations(Permutation([1, 0, 2]))
        self.assertFalse(result["is_valid"])
        self.assertGreater(len(result["color_violations"]), 0)
        # Should mention colors
        self.assertIn("color", result["summary"].lower())

    def test_color_violation_identifies_nodes(self):
        """Color violation should identify which nodes have mismatched colors"""
        g = self._make_colored_triangle()
        result = g.find_violations(Permutation([1, 0, 2]))
        cv = result["color_violations"]
        # Node 0 maps to 1: RED -> GREEN
        node_ids = [v["node_id"] for v in cv]
        self.assertIn(0, node_ids)

    def test_direction_violation_on_reflection(self):
        """Swap(1,2) on directed triangle: reverses edge direction"""
        g = self._make_directed_triangle()
        # [0,2,1] — swaps 1 and 2, which reverses the cycle direction
        result = g.find_violations(Permutation([0, 2, 1]))
        self.assertFalse(result["is_valid"])
        # Should have edge violations (direction reversal)
        self.assertGreater(len(result["edge_violations"]), 0)

    def test_rotation_valid_on_directed(self):
        """Rotation [1,2,0] on directed triangle is valid"""
        g = self._make_directed_triangle()
        result = g.find_violations(Permutation([1, 2, 0]))
        self.assertTrue(result["is_valid"])
        self.assertEqual(len(result["edge_violations"]), 0)

    def test_summary_message_not_empty_for_invalid(self):
        """Invalid permutation should have a non-empty summary"""
        g = self._make_colored_triangle()
        result = g.find_violations(Permutation([1, 0, 2]))
        self.assertFalse(result["is_valid"])
        self.assertTrue(len(result["summary"]) > 0)

    def test_consistent_with_is_automorphism(self):
        """find_violations.is_valid should match is_automorphism for all perms"""
        g = self._make_colored_triangle()
        for perm in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
            p = Permutation(perm)
            self.assertEqual(
                g.find_violations(p)["is_valid"],
                g.is_automorphism(p),
                f"Mismatch for perm {perm}"
            )

    def test_mixed_edge_types(self):
        """Graph with mixed edge types: type mismatch should be detected"""
        nodes = [
            {"id": 0, "color": "RED"}, {"id": 1, "color": "RED"},
            {"id": 2, "color": "RED"}, {"id": 3, "color": "RED"}
        ]
        edges = [
            {"from": 0, "to": 1, "type": "STANDARD"},
            {"from": 1, "to": 2, "type": "THICK"},   # Different type
            {"from": 2, "to": 3, "type": "STANDARD"},
            {"from": 3, "to": 0, "type": "THICK"},
        ]
        g = CrystalGraph(nodes, edges)
        # Rotation by 1: [1,2,3,0] — this swaps edge types around
        result = g.find_violations(Permutation([1, 2, 3, 0]))
        self.assertFalse(result["is_valid"])
        self.assertGreater(len(result["edge_violations"]), 0)
        # At least one should be type_mismatch
        reasons = [ev["reason"] for ev in result["edge_violations"]]
        self.assertIn("type_mismatch", reasons)


if __name__ == "__main__":
    unittest.main()
