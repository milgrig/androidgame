"""
Tests for the level generator CLI tool (generate_complex_levels.py).
Verifies:
  - Graph construction for all graph types
  - Automorphism computation correctness
  - Cayley table computation
  - Subgroup finding
  - Level JSON schema compliance
  - Generated levels load with existing test infrastructure
"""
import json
import math
import os
import sys
import unittest

# Add project root to path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, PROJECT_ROOT)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from generate_complex_levels import (
    Permutation,
    GraphBuilder,
    AutomorphismFinder,
    GroupGenerator,
    build_graph,
    generate_group,
    compute_cayley_table,
    find_all_subgroups,
    find_generators,
    assign_ids_and_names,
    validate_level,
    generate_level,
    _perm_sign,
)

# Import test infrastructure for integration testing
from test_core_engine import (
    Permutation as CorePermutation,
    CrystalGraph,
    KeyRing,
)
from test_integration import LevelSimulator


# ============================================================================
# Permutation math tests
# ============================================================================

class TestPermutation(unittest.TestCase):
    """Test Permutation class mathematical correctness."""

    def test_identity(self):
        e = Permutation.identity(4)
        self.assertEqual(e.mapping, [0, 1, 2, 3])
        self.assertTrue(e.is_identity())
        self.assertTrue(e.is_valid())

    def test_compose(self):
        """Test composition: (a ∘ b)(i) = b(a(i))."""
        a = Permutation([1, 2, 0])  # (0 1 2)
        b = Permutation([0, 2, 1])  # (1 2)
        ab = a.compose(b)  # Apply a then b
        # a(0)=1, b(1)=2 → ab(0)=2
        # a(1)=2, b(2)=1 → ab(1)=1
        # a(2)=0, b(0)=0 → ab(2)=0
        self.assertEqual(ab.mapping, [2, 1, 0])

    def test_inverse(self):
        p = Permutation([2, 0, 1])
        p_inv = p.inverse()
        # p ∘ p_inv should be identity
        composed = p.compose(p_inv)
        self.assertTrue(composed.is_identity())

    def test_order(self):
        # 3-cycle has order 3
        p = Permutation([1, 2, 0])
        self.assertEqual(p.order(), 3)
        # transposition has order 2
        p2 = Permutation([1, 0, 2])
        self.assertEqual(p2.order(), 2)
        # identity has order 1
        e = Permutation.identity(3)
        self.assertEqual(e.order(), 1)

    def test_cycle_notation(self):
        p = Permutation([1, 2, 0])
        self.assertEqual(p.to_cycle_notation(), "(0 1 2)")
        e = Permutation.identity(3)
        self.assertEqual(e.to_cycle_notation(), "()")

    def test_perm_sign_even(self):
        """3-cycle is even."""
        p = Permutation([1, 2, 0])
        self.assertEqual(_perm_sign(p), 1)

    def test_perm_sign_odd(self):
        """Transposition is odd."""
        p = Permutation([1, 0, 2])
        self.assertEqual(_perm_sign(p), -1)

    def test_perm_sign_identity(self):
        """Identity is even."""
        e = Permutation.identity(4)
        self.assertEqual(_perm_sign(e), 1)


# ============================================================================
# Graph construction tests
# ============================================================================

class TestGraphBuilder(unittest.TestCase):
    """Test graph construction for all types."""

    def test_cycle_3(self):
        g = GraphBuilder.cycle(3)
        self.assertEqual(len(g["nodes"]), 3)
        self.assertEqual(len(g["edges"]), 3)
        self._check_graph_structure(g)

    def test_cycle_5(self):
        g = GraphBuilder.cycle(5)
        self.assertEqual(len(g["nodes"]), 5)
        self.assertEqual(len(g["edges"]), 5)
        self._check_graph_structure(g)

    def test_path_4(self):
        g = GraphBuilder.path(4)
        self.assertEqual(len(g["nodes"]), 4)
        self.assertEqual(len(g["edges"]), 3)  # n-1 edges
        self._check_graph_structure(g)

    def test_complete_4(self):
        g = GraphBuilder.complete(4)
        self.assertEqual(len(g["nodes"]), 4)
        self.assertEqual(len(g["edges"]), 6)  # C(4,2)
        self._check_graph_structure(g)

    def test_complete_3(self):
        g = GraphBuilder.complete(3)
        self.assertEqual(len(g["nodes"]), 3)
        self.assertEqual(len(g["edges"]), 3)
        self._check_graph_structure(g)

    def test_bipartite_2_3(self):
        g = GraphBuilder.bipartite(2, 3)
        self.assertEqual(len(g["nodes"]), 5)
        self.assertEqual(len(g["edges"]), 6)  # 2*3
        self._check_graph_structure(g)

    def test_bipartite_colors(self):
        """Bipartite graph should have two distinct color groups."""
        g = GraphBuilder.bipartite(2, 3)
        colors = [n["color"] for n in g["nodes"]]
        self.assertEqual(colors[:2], ["cyan", "cyan"])
        self.assertEqual(colors[2:], ["purple", "purple", "purple"])

    def test_prism_4(self):
        g = GraphBuilder.prism(4)
        self.assertEqual(len(g["nodes"]), 8)
        # 4 top + 4 bottom + 4 vertical = 12 edges
        self.assertEqual(len(g["edges"]), 12)
        self._check_graph_structure(g)

    def test_wheel_5(self):
        g = GraphBuilder.wheel(5)
        self.assertEqual(len(g["nodes"]), 6)  # 5 rim + 1 hub
        # 5 rim + 5 spokes = 10 edges
        self.assertEqual(len(g["edges"]), 10)
        self._check_graph_structure(g)

    def test_petersen(self):
        g = GraphBuilder.petersen()
        self.assertEqual(len(g["nodes"]), 10)
        self.assertEqual(len(g["edges"]), 15)
        self._check_graph_structure(g)

    def test_tetrahedron(self):
        g = GraphBuilder.tetrahedron()
        self.assertEqual(len(g["nodes"]), 4)
        self.assertEqual(len(g["edges"]), 6)
        self._check_graph_structure(g)

    def test_cube(self):
        g = GraphBuilder.cube()
        self.assertEqual(len(g["nodes"]), 8)
        self.assertEqual(len(g["edges"]), 12)
        self._check_graph_structure(g)

    def test_octahedron(self):
        g = GraphBuilder.octahedron()
        self.assertEqual(len(g["nodes"]), 6)
        self.assertEqual(len(g["edges"]), 12)
        self._check_graph_structure(g)

    def test_directed_cycle(self):
        g = GraphBuilder.directed_cycle(4)
        self.assertEqual(len(g["nodes"]), 4)
        self.assertEqual(len(g["edges"]), 4)
        for edge in g["edges"]:
            self.assertTrue(edge.get("directed", False))

    def test_star_5(self):
        g = GraphBuilder.star(5)
        self.assertEqual(len(g["nodes"]), 6)  # 1 center + 5 leaves
        self.assertEqual(len(g["edges"]), 5)
        self._check_graph_structure(g)

    def test_cycle_raises_for_n_less_than_3(self):
        with self.assertRaises(ValueError):
            GraphBuilder.cycle(2)

    def test_build_graph_registry(self):
        """All registered graphs should build successfully."""
        from generate_complex_levels import _build_graph_registry
        registry = _build_graph_registry()
        self.assertGreater(len(registry), 20, "Should have many registered graphs")
        # Test a sample from each category
        for name in ["cycle_5", "path_3", "complete_4", "prism_4", "wheel_5",
                      "bipartite_2_3", "petersen", "cube", "octahedron"]:
            graph = build_graph(name)
            self.assertIn("nodes", graph)
            self.assertIn("edges", graph)

    def _check_graph_structure(self, graph: dict):
        """Verify basic graph structure: sequential IDs, valid edges."""
        nodes = graph["nodes"]
        edges = graph["edges"]
        n = len(nodes)
        ids = sorted([node["id"] for node in nodes])
        self.assertEqual(ids, list(range(n)), "Node IDs must be sequential [0..n-1]")
        for edge in edges:
            self.assertGreaterEqual(edge["from"], 0)
            self.assertLess(edge["from"], n)
            self.assertGreaterEqual(edge["to"], 0)
            self.assertLess(edge["to"], n)
            self.assertIn("type", edge)
            self.assertIn("weight", edge)


# ============================================================================
# Automorphism computation tests
# ============================================================================

class TestAutomorphismFinder(unittest.TestCase):
    """Test correctness of automorphism computation.
    Compare with known mathematical results."""

    def test_triangle_has_s3(self):
        """Aut(C_3) = Aut(K_3) = S3 (order 6)."""
        graph = GraphBuilder.cycle(3)
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 6)
        self._verify_group_properties(autos)

    def test_complete_4_has_s4(self):
        """Aut(K_4) = S4 (order 24)."""
        graph = GraphBuilder.complete(4)
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 24)
        self._verify_group_properties(autos)

    def test_cycle_4_has_d4(self):
        """Aut(C_4) = D4 (order 8)."""
        graph = GraphBuilder.cycle(4)
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 8)
        self._verify_group_properties(autos)

    def test_cycle_5_has_d5(self):
        """Aut(C_5) = D5 (order 10)."""
        graph = GraphBuilder.cycle(5)
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 10)
        self._verify_group_properties(autos)

    def test_cycle_6_has_d6(self):
        """Aut(C_6) = D6 (order 12)."""
        graph = GraphBuilder.cycle(6)
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 12)
        self._verify_group_properties(autos)

    def test_directed_cycle_has_zn(self):
        """Aut(directed C_n) = Z_n."""
        for n in [3, 4, 5]:
            graph = GraphBuilder.directed_cycle(n)
            autos = AutomorphismFinder.find_all(graph)
            self.assertEqual(len(autos), n,
                             f"Aut(directed C_{n}) should have order {n}")
            self._verify_group_properties(autos)

    def test_path_3_has_z2(self):
        """Aut(P_3) = Z2 (order 2): flip endpoints."""
        graph = GraphBuilder.path(3)
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 2)
        self._verify_group_properties(autos)

    def test_path_4_has_z2(self):
        """Aut(P_4) = Z2 (order 2): reverse the path."""
        graph = GraphBuilder.path(4)
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 2)
        self._verify_group_properties(autos)

    def test_complete_3_has_s3(self):
        """Aut(K_3) = S3 (order 6)."""
        graph = GraphBuilder.complete(3)
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 6)
        self._verify_group_properties(autos)

    def test_octahedron_has_48(self):
        """Aut(Octahedron) = S4 x Z2 (order 48)."""
        graph = GraphBuilder.octahedron()
        autos = AutomorphismFinder.find_all(graph)
        self.assertEqual(len(autos), 48)
        self._verify_group_properties(autos)

    def test_identity_always_present(self):
        """Every graph should have the identity as an automorphism."""
        for name in ["cycle_3", "cycle_5", "path_3", "complete_4", "petersen", "cube"]:
            graph = build_graph(name)
            autos = AutomorphismFinder.find_all(graph)
            n = len(graph["nodes"])
            has_identity = any(a.is_identity() for a in autos)
            self.assertTrue(has_identity, f"{name}: identity missing")

    def test_automorphisms_are_valid_graph_autos(self):
        """Every found automorphism should be a valid graph automorphism
        (cross-verified with test_core_engine.CrystalGraph.find_all_automorphisms)."""
        for name in ["cycle_3", "cycle_5", "complete_4", "path_3"]:
            graph = build_graph(name)
            our_autos = AutomorphismFinder.find_all(graph)
            cg = CrystalGraph(graph["nodes"], graph["edges"])
            engine_autos = cg.find_all_automorphisms()
            our_set = {tuple(p.mapping) for p in our_autos}
            engine_set = {tuple(p.mapping) for p in engine_autos}
            self.assertEqual(
                our_set, engine_set,
                f"{name}: Our automorphisms differ from CrystalGraph's. "
                f"Ours={len(our_set)}, Engine={len(engine_set)}"
            )

    def _verify_group_properties(self, perms: list[Permutation]):
        """Verify closure, identity, and inverses."""
        perm_set = {tuple(p.mapping) for p in perms}
        # Identity
        n = perms[0].size()
        self.assertIn(tuple(range(n)), perm_set, "Identity missing")
        # Closure
        for a in perms:
            for b in perms:
                prod = tuple(a.compose(b).mapping)
                self.assertIn(prod, perm_set, f"Not closed: {a.mapping} * {b.mapping} = {list(prod)}")
        # Inverses
        for a in perms:
            inv = tuple(a.inverse().mapping)
            self.assertIn(inv, perm_set, f"Missing inverse of {a.mapping}")


# ============================================================================
# Group generator tests
# ============================================================================

class TestGroupGenerator(unittest.TestCase):
    """Test abstract group generation."""

    def test_cyclic_z3(self):
        perms = GroupGenerator.cyclic(3)
        self.assertEqual(len(perms), 3)
        self._verify_group(perms)

    def test_cyclic_z5(self):
        perms = GroupGenerator.cyclic(5)
        self.assertEqual(len(perms), 5)
        self._verify_group(perms)

    def test_dihedral_d3(self):
        perms = GroupGenerator.dihedral(3)
        self.assertEqual(len(perms), 6)
        self._verify_group(perms)

    def test_dihedral_d4(self):
        perms = GroupGenerator.dihedral(4)
        self.assertEqual(len(perms), 8)
        self._verify_group(perms)

    def test_symmetric_s3(self):
        perms = GroupGenerator.symmetric(3)
        self.assertEqual(len(perms), 6)
        self._verify_group(perms)

    def test_symmetric_s4(self):
        perms = GroupGenerator.symmetric(4)
        self.assertEqual(len(perms), 24)
        self._verify_group(perms)

    def test_alternating_a3(self):
        perms = GroupGenerator.alternating(3)
        self.assertEqual(len(perms), 3)
        self._verify_group(perms)
        # All should be even
        for p in perms:
            self.assertEqual(_perm_sign(p), 1)

    def test_alternating_a4(self):
        perms = GroupGenerator.alternating(4)
        self.assertEqual(len(perms), 12)
        self._verify_group(perms)

    def test_klein_four(self):
        perms = GroupGenerator.klein_four()
        self.assertEqual(len(perms), 4)
        self._verify_group(perms)
        # Every non-identity element has order 2
        for p in perms:
            if not p.is_identity():
                self.assertEqual(p.order(), 2)

    def test_d3_equals_s3(self):
        """D3 and S3 should be isomorphic (same set of permutations on 3 elements)."""
        d3 = set(tuple(p.mapping) for p in GroupGenerator.dihedral(3))
        s3 = set(tuple(p.mapping) for p in GroupGenerator.symmetric(3))
        self.assertEqual(d3, s3)

    def _verify_group(self, perms: list[Permutation]):
        perm_set = {tuple(p.mapping) for p in perms}
        n = perms[0].size()
        self.assertIn(tuple(range(n)), perm_set, "Missing identity")
        for a in perms:
            for b in perms:
                prod = tuple(a.compose(b).mapping)
                self.assertIn(prod, perm_set, "Not closed")
        for a in perms:
            inv = tuple(a.inverse().mapping)
            self.assertIn(inv, perm_set, "Missing inverse")


# ============================================================================
# Cayley table tests
# ============================================================================

class TestCayleyTable(unittest.TestCase):
    """Test Cayley table computation."""

    def test_z3_cayley(self):
        perms = GroupGenerator.cyclic(3)
        ids = ["e", "r1", "r2"]
        table = compute_cayley_table(perms, ids)
        # e * anything = that thing (in our convention)
        self.assertEqual(table["e"]["e"], "e")
        self.assertEqual(table["e"]["r1"], "r1")
        self.assertEqual(table["e"]["r2"], "r2")
        # r1 * r1 should give r2
        self.assertEqual(table["r1"]["r1"], "r2")
        # r1 * r2 should give e
        self.assertEqual(table["r1"]["r2"], "e")

    def test_z3_cayley_matches_existing_level(self):
        """Verify our Cayley table matches the one in level_01.json."""
        perms = GroupGenerator.cyclic(3)
        ids = ["e", "r1", "r2"]
        computed = compute_cayley_table(perms, ids)

        expected = {
            "e":  {"e": "e",  "r1": "r1", "r2": "r2"},
            "r1": {"e": "r1", "r1": "r2", "r2": "e"},
            "r2": {"e": "r2", "r1": "e",  "r2": "r1"}
        }
        self.assertEqual(computed, expected)

    def test_cayley_table_size(self):
        """Cayley table should be n x n."""
        perms = GroupGenerator.dihedral(4)
        ids = [f"g{i}" for i in range(8)]
        table = compute_cayley_table(perms, ids)
        self.assertEqual(len(table), 8)
        for row_id, row in table.items():
            self.assertEqual(len(row), 8)

    def test_cayley_identity_row(self):
        """Identity row should map each element to itself."""
        perms = GroupGenerator.cyclic(5)
        ids = ["e", "r1", "r2", "r3", "r4"]
        table = compute_cayley_table(perms, ids)
        for col_id in ids:
            self.assertEqual(table["e"][col_id], col_id)

    def test_cayley_identity_column(self):
        """Identity column should map each element to itself."""
        perms = GroupGenerator.cyclic(5)
        ids = ["e", "r1", "r2", "r3", "r4"]
        table = compute_cayley_table(perms, ids)
        for row_id in ids:
            self.assertEqual(table[row_id]["e"], row_id)


# ============================================================================
# Subgroup tests
# ============================================================================

class TestSubgroupFinding(unittest.TestCase):
    """Test subgroup discovery."""

    def test_z3_subgroups(self):
        """Z3 (prime order) has only trivial and full subgroups."""
        perms = GroupGenerator.cyclic(3)
        ids = ["e", "r1", "r2"]
        subgroups = find_all_subgroups(perms, ids)
        orders = sorted([sg["order"] for sg in subgroups])
        self.assertEqual(orders, [1, 3])

    def test_z4_subgroups(self):
        """Z4 has subgroups of order 1, 2, 4."""
        perms = GroupGenerator.cyclic(4)
        ids = ["e", "r1", "r2", "r3"]
        subgroups = find_all_subgroups(perms, ids)
        orders = sorted([sg["order"] for sg in subgroups])
        self.assertEqual(orders, [1, 2, 4])

    def test_s3_subgroups(self):
        """S3 has subgroups of order 1, 2, 2, 2, 3, 6."""
        perms = GroupGenerator.symmetric(3)
        ids = [f"g{i}" for i in range(6)]
        subgroups = find_all_subgroups(perms, ids)
        orders = sorted([sg["order"] for sg in subgroups])
        self.assertEqual(orders, [1, 2, 2, 2, 3, 6])

    def test_d4_subgroups(self):
        """D4 has 10 subgroups (1+3+1+3+1+1)."""
        perms = GroupGenerator.dihedral(4)
        ids = [f"g{i}" for i in range(8)]
        subgroups = find_all_subgroups(perms, ids)
        self.assertEqual(len(subgroups), 10)

    def test_trivial_subgroup_always_present(self):
        """Every group has a trivial subgroup."""
        for name, gen_fn in [("Z5", lambda: GroupGenerator.cyclic(5)),
                              ("S3", lambda: GroupGenerator.symmetric(3))]:
            perms = gen_fn()
            ids = [f"g{i}" for i in range(len(perms))]
            subgroups = find_all_subgroups(perms, ids)
            orders = [sg["order"] for sg in subgroups]
            self.assertIn(1, orders, f"{name}: missing trivial subgroup")

    def test_full_group_always_present(self):
        """The full group is always a subgroup."""
        perms = GroupGenerator.dihedral(3)
        ids = [f"g{i}" for i in range(6)]
        subgroups = find_all_subgroups(perms, ids)
        orders = [sg["order"] for sg in subgroups]
        self.assertIn(6, orders)

    def test_normal_subgroups_of_s3(self):
        """S3 has 2 normal subgroups: trivial {e} and Z3 = {e, r1, r2}."""
        perms = GroupGenerator.symmetric(3)
        ids = [f"g{i}" for i in range(6)]
        subgroups = find_all_subgroups(perms, ids)
        normal_orders = sorted([sg["order"] for sg in subgroups if sg["is_normal"]])
        # Trivial, Z3 (normal), S3 (full group = trivially normal)
        self.assertIn(1, normal_orders)
        self.assertIn(3, normal_orders)
        self.assertIn(6, normal_orders)

    def test_lagrange_theorem(self):
        """All subgroup orders must divide the group order (Lagrange's theorem)."""
        for gen_fn, expected_order in [
            (lambda: GroupGenerator.cyclic(6), 6),
            (lambda: GroupGenerator.dihedral(4), 8),
            (lambda: GroupGenerator.symmetric(3), 6),
        ]:
            perms = gen_fn()
            ids = [f"g{i}" for i in range(len(perms))]
            subgroups = find_all_subgroups(perms, ids)
            for sg in subgroups:
                self.assertEqual(
                    expected_order % sg["order"], 0,
                    f"Subgroup order {sg['order']} doesn't divide "
                    f"group order {expected_order}"
                )


# ============================================================================
# Generator finding tests
# ============================================================================

class TestGeneratorFinding(unittest.TestCase):
    """Test minimal generator set discovery."""

    def test_z5_single_generator(self):
        """Z5 is cyclic — needs only 1 generator."""
        perms = GroupGenerator.cyclic(5)
        ids = ["e", "r1", "r2", "r3", "r4"]
        generators = find_generators(perms, ids)
        self.assertEqual(len(generators), 1)
        self.assertNotIn("e", generators)

    def test_d4_two_generators(self):
        """D4 needs exactly 2 generators (rotation + reflection)."""
        perms = GroupGenerator.dihedral(4)
        ids = [f"g{i}" for i in range(8)]
        generators = find_generators(perms, ids)
        self.assertLessEqual(len(generators), 2)

    def test_s3_two_generators(self):
        """S3 needs at most 2 generators."""
        perms = GroupGenerator.symmetric(3)
        ids = [f"g{i}" for i in range(6)]
        generators = find_generators(perms, ids)
        self.assertLessEqual(len(generators), 2)

    def test_generators_dont_include_identity(self):
        """Identity should never be in the generator set."""
        for gen_fn in [
            lambda: GroupGenerator.cyclic(5),
            lambda: GroupGenerator.dihedral(3),
            lambda: GroupGenerator.symmetric(3),
        ]:
            perms = gen_fn()
            ids = [f"g{i}" for i in range(len(perms))]
            generators = find_generators(perms, ids)
            # Find identity id
            for p, pid in zip(perms, ids):
                if p.is_identity():
                    self.assertNotIn(pid, generators)


# ============================================================================
# Level validation tests
# ============================================================================

class TestLevelValidation(unittest.TestCase):
    """Test level JSON validation."""

    def test_valid_level_passes(self):
        """A properly generated level should pass validation."""
        level = generate_level(
            group_name="Z3",
            graph_name="cycle_3",
            level_id=99,
        )
        warnings = validate_level(level)
        errors = [w for w in warnings if w.startswith("ERROR")]
        self.assertEqual(len(errors), 0, f"Errors found: {errors}")

    def test_validate_existing_levels(self):
        """All existing act1 levels should pass validation."""
        levels_dir = os.path.join(PROJECT_ROOT, "data", "levels", "act1")
        if not os.path.isdir(levels_dir):
            self.skipTest("Levels directory not found")
        for filename in sorted(os.listdir(levels_dir)):
            if not filename.endswith(".json"):
                continue
            filepath = os.path.join(levels_dir, filename)
            with open(filepath, "r", encoding="utf-8") as f:
                data = json.load(f)
            warnings = validate_level(data)
            errors = [w for w in warnings if w.startswith("ERROR")]
            self.assertEqual(
                len(errors), 0,
                f"{filename} has validation errors: {errors}"
            )

    def test_missing_meta_detected(self):
        """Validation should catch missing meta fields."""
        level = {
            "meta": {"id": "test"},  # Missing required fields
            "graph": {"nodes": [], "edges": []},
            "symmetries": {"automorphisms": [], "generators": [], "cayley_table": {}},
            "mechanics": {"allowed_actions": ["swap"]},
            "visuals": {},
            "hints": [],
            "echo_hints": []
        }
        warnings = validate_level(level)
        error_strs = " ".join(warnings)
        self.assertIn("ERROR", error_strs)


# ============================================================================
# Integration tests: generated levels work with game infrastructure
# ============================================================================

class TestGeneratedLevelsIntegration(unittest.TestCase):
    """Test that generated levels work with the existing game test infrastructure."""

    def test_z3_cycle3_loads_in_simulator(self):
        """Z3 on cycle_3 should load and work in LevelSimulator."""
        level = generate_level("Z3", "cycle_3", 99)
        sim = LevelSimulator(level)
        self.assertEqual(sim.crystal_graph.node_count(), 3)
        self.assertEqual(len(sim.target_perms), 3)

    def test_s3_complete3_loads_in_simulator(self):
        """S3 on complete_3 should load and work in LevelSimulator."""
        level = generate_level("S3", "complete_3", 99)
        sim = LevelSimulator(level)
        self.assertEqual(sim.crystal_graph.node_count(), 3)
        self.assertEqual(len(sim.target_perms), 6)

    def test_d4_cycle4_loads_in_simulator(self):
        """D4 on cycle_4 should load and work."""
        level = generate_level("D4", "cycle_4", 99)
        sim = LevelSimulator(level)
        self.assertEqual(sim.crystal_graph.node_count(), 4)
        self.assertEqual(len(sim.target_perms), 8)

    def test_z5_cycle5_completable(self):
        """Z5 level should be completable via direct validation."""
        level = generate_level("Z5", "cycle_5", 99)
        sim = LevelSimulator(level)
        for perm in sim.target_perms.values():
            sim._validate_permutation(perm)
        self.assertTrue(sim.key_ring.is_complete())

    def test_s3_completable(self):
        """S3 level should be completable via direct validation."""
        level = generate_level("S3", "complete_3", 99)
        sim = LevelSimulator(level)
        for perm in sim.target_perms.values():
            sim._validate_permutation(perm)
        self.assertTrue(sim.key_ring.is_complete())

    def test_d5_cycle5_completable(self):
        """D5 level should be completable."""
        level = generate_level("D5", "cycle_5", 99)
        sim = LevelSimulator(level)
        for perm in sim.target_perms.values():
            sim._validate_permutation(perm)
        self.assertTrue(sim.key_ring.is_complete())

    def test_identity_discoverable(self):
        """Setting arrangement to identity should discover it."""
        level = generate_level("Z5", "cycle_5", 99)
        sim = LevelSimulator(level)
        n = sim.crystal_graph.node_count()
        sim.current_arrangement = list(range(n))
        result = sim.check_current()
        self.assertIn(result, ("new_symmetry", "level_complete"))

    def test_auto_petersen_loads(self):
        """Auto-computed Petersen level should load in simulator."""
        level = generate_level(
            group_name="auto",
            graph_name="petersen",
            level_id=99,
            auto_group=True,
        )
        sim = LevelSimulator(level)
        self.assertEqual(sim.crystal_graph.node_count(), 10)
        self.assertGreater(len(sim.target_perms), 0)

    def test_auto_petersen_completable(self):
        """Auto-computed Petersen level should be completable."""
        level = generate_level(
            group_name="auto",
            graph_name="petersen",
            level_id=99,
            auto_group=True,
        )
        sim = LevelSimulator(level)
        for perm in sim.target_perms.values():
            sim._validate_permutation(perm)
        self.assertTrue(sim.key_ring.is_complete())

    def test_generated_level_has_required_schema(self):
        """Generated levels must have all required top-level keys."""
        level = generate_level("Z3", "cycle_3", 99)
        required = {"meta", "graph", "symmetries", "mechanics", "visuals", "hints", "echo_hints"}
        self.assertEqual(required - set(level.keys()), set())

    def test_generated_automorphisms_form_group(self):
        """Generated automorphisms should form a group (closed, identity, inverses)."""
        for group_name, graph_name in [
            ("Z3", "cycle_3"),
            ("Z5", "cycle_5"),
            ("D4", "cycle_4"),
            ("S3", "complete_3"),
            ("D5", "cycle_5"),
        ]:
            level = generate_level(group_name, graph_name, 99)
            kr = KeyRing(0)
            for auto in level["symmetries"]["automorphisms"]:
                kr.add_key(CorePermutation(auto["mapping"]))
            self.assertTrue(kr.has_identity(), f"{group_name}: missing identity")
            self.assertTrue(kr.is_closed_under_composition(),
                            f"{group_name}: not closed")
            self.assertTrue(kr.has_inverses(), f"{group_name}: missing inverses")


# ============================================================================
# Auto-computation integration tests
# ============================================================================

class TestAutoComputation(unittest.TestCase):
    """Test --auto mode: compute Aut(G) from graph."""

    def test_auto_cycle_5_equals_d5(self):
        """Aut(C_5) should equal D5 as a set of permutations."""
        level_auto = generate_level("auto", "cycle_5", 99, auto_group=True)
        level_d5 = generate_level("D5", "cycle_5", 99)
        auto_mappings = set(
            tuple(a["mapping"]) for a in level_auto["symmetries"]["automorphisms"]
        )
        d5_mappings = set(
            tuple(a["mapping"]) for a in level_d5["symmetries"]["automorphisms"]
        )
        self.assertEqual(auto_mappings, d5_mappings)

    def test_auto_cycle_3_equals_d3_equals_s3(self):
        """Aut(C_3) = D3 = S3."""
        level_auto = generate_level("auto", "cycle_3", 99, auto_group=True)
        auto_mappings = set(
            tuple(a["mapping"]) for a in level_auto["symmetries"]["automorphisms"]
        )
        self.assertEqual(len(auto_mappings), 6)

    def test_auto_directed_cycle_4_equals_z4(self):
        """Aut(directed C_4) = Z4."""
        level_auto = generate_level("auto", "directed_cycle_4", 99, auto_group=True)
        level_z4 = generate_level("Z4", "directed_cycle_4", 99)
        auto_mappings = set(
            tuple(a["mapping"]) for a in level_auto["symmetries"]["automorphisms"]
        )
        z4_mappings = set(
            tuple(a["mapping"]) for a in level_z4["symmetries"]["automorphisms"]
        )
        self.assertEqual(auto_mappings, z4_mappings)

    def test_auto_complete_3_is_s3(self):
        """Aut(K_3) = S3 (order 6)."""
        level = generate_level("auto", "complete_3", 99, auto_group=True)
        self.assertEqual(level["meta"]["group_order"], 6)


if __name__ == "__main__":
    unittest.main()
