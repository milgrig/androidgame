"""
Unit tests for Layer 5: Quotient Group Construction.
Tests the QuotientGroupManager logic (Python mirror) and validates
coset decomposition and quotient table correctness across all 24 level JSON files.

T119: Layer 5 Engine -- Quotient Group Manager
"""
import json
import os
import unittest

# Reuse core engine mirrors from test_core_engine
from test_core_engine import Permutation


# === Helper: is_normal check (reused from layer 4 tests) ===

def is_normal(subgroup_perms: list[Permutation], group_perms: list[Permutation]) -> bool:
    """Check if subgroup H is normal in group G."""
    for g in group_perms:
        g_inv = g.inverse()
        for h in subgroup_perms:
            conjugate = g.compose(h).compose(g_inv)
            if not any(s.equals(conjugate) for s in subgroup_perms):
                return False
    return True


# === Python mirror of QuotientGroupManager ===

class QuotientGroupManager:
    """Python mirror of QuotientGroupManager.gd for testing."""

    def __init__(self):
        self._sym_id_to_perm: dict[str, Permutation] = {}
        self._sym_id_to_name: dict[str, str] = {}
        self._all_sym_ids: list[str] = []

        self._normal_subgroups: list[dict] = []
        self._total_count: int = 0

        self._cosets: dict[int, list[dict]] = {}
        self._quotient_tables: dict[int, dict] = {}

        self._constructed: dict[int, dict] = {}
        self._constructed_count: int = 0

        # Cayley table (fallback for unfaithful perm representations like Q8)
        self._cayley_table: dict[str, dict[str, str]] = {}

        # Signal tracking for tests
        self._signals: list[tuple] = []

    def setup(self, level_data: dict, layer_config: dict = None) -> None:
        if layer_config is None:
            layer_config = {}

        self._sym_id_to_perm.clear()
        self._sym_id_to_name.clear()
        self._all_sym_ids.clear()
        self._normal_subgroups.clear()
        self._cosets.clear()
        self._quotient_tables.clear()
        self._constructed.clear()
        self._constructed_count = 0
        self._cayley_table.clear()
        self._signals.clear()

        # Parse automorphisms
        autos = level_data.get("symmetries", {}).get("automorphisms", [])
        for auto in autos:
            sym_id = auto.get("id", "")
            perm = Permutation(auto.get("mapping", []))
            self._sym_id_to_perm[sym_id] = perm
            self._sym_id_to_name[sym_id] = auto.get("name", sym_id)
            self._all_sym_ids.append(sym_id)

        # Load Cayley table (fallback for unfaithful representations like Q8)
        self._cayley_table = level_data.get("symmetries", {}).get("cayley_table", {})

        # Load quotient group definitions from layer_5
        quotient_groups = layer_config.get("quotient_groups", [])

        for qg in quotient_groups:
            ns_elements = qg.get("normal_subgroup_elements", [])
            if not ns_elements:
                continue
            self._normal_subgroups.append(qg)

        self._total_count = len(self._normal_subgroups)

    # --- Normal Subgroup Access ---

    def get_normal_subgroups(self) -> list[dict]:
        return list(self._normal_subgroups)

    def get_normal_subgroup_count(self) -> int:
        return len(self._normal_subgroups)

    def get_normal_subgroup_elements(self, index: int) -> list[str]:
        if index < 0 or index >= len(self._normal_subgroups):
            return []
        return list(self._normal_subgroups[index].get("normal_subgroup_elements", []))

    # --- Coset Computation ---

    def compute_cosets(self, subgroup_index: int) -> list[dict]:
        if subgroup_index < 0 or subgroup_index >= len(self._normal_subgroups):
            return []

        # If already computed, return cached
        if subgroup_index in self._cosets:
            return [dict(c, elements=list(c["elements"])) for c in self._cosets[subgroup_index]]

        ns_data = self._normal_subgroups[subgroup_index]
        ns_elements = ns_data.get("normal_subgroup_elements", [])

        # Compute left cosets: for each g in G, compute gN using _compose_sym_ids
        cosets = []
        assigned = set()

        for g_sid in self._all_sym_ids:
            if g_sid in assigned:
                continue

            coset_elements = []

            for h_sid in ns_elements:
                product_sid = self._compose_sym_ids(g_sid, h_sid)
                if product_sid != "" and product_sid not in coset_elements:
                    coset_elements.append(product_sid)
                    assigned.add(product_sid)

            cosets.append({
                "representative": g_sid,
                "elements": coset_elements,
            })

        self._cosets[subgroup_index] = cosets
        return [dict(c, elements=list(c["elements"])) for c in cosets]

    # --- Quotient Table ---

    def get_quotient_table(self, subgroup_index: int) -> dict:
        if subgroup_index < 0 or subgroup_index >= len(self._normal_subgroups):
            return {}

        # If already computed, return cached
        if subgroup_index in self._quotient_tables:
            return {k: dict(v) for k, v in self._quotient_tables[subgroup_index].items()}

        # Ensure cosets are computed
        cosets = self.compute_cosets(subgroup_index)
        if not cosets:
            return {}

        # Build representative -> coset-index map
        rep_list = []
        element_to_rep = {}
        for coset in cosets:
            rep = coset["representative"]
            rep_list.append(rep)
            for elem in coset["elements"]:
                element_to_rep[elem] = rep

        # Build multiplication table using _compose_sym_ids
        table = {}
        for rep_a in rep_list:
            table[rep_a] = {}
            for rep_b in rep_list:
                product_sid = self._compose_sym_ids(rep_a, rep_b)
                result_rep = element_to_rep.get(product_sid, "")
                table[rep_a][rep_b] = result_rep

        self._quotient_tables[subgroup_index] = table
        return {k: dict(v) for k, v in table.items()}

    # --- Verification ---

    def verify_quotient(self, subgroup_index: int) -> dict:
        if subgroup_index < 0 or subgroup_index >= len(self._normal_subgroups):
            return {"valid": False, "checks": {}}

        cosets = self.compute_cosets(subgroup_index)
        table = self.get_quotient_table(subgroup_index)
        if not cosets or not table:
            return {"valid": False, "checks": {}}

        rep_list = [c["representative"] for c in cosets]

        # 1. Closure
        closure_ok = True
        for rep_a in rep_list:
            for rep_b in rep_list:
                result = table.get(rep_a, {}).get(rep_b, "")
                if result == "" or result not in rep_list:
                    closure_ok = False

        # 2. Identity
        identity_rep = ""
        for coset in cosets:
            for elem in coset["elements"]:
                p = self._sym_id_to_perm.get(elem)
                if p is not None and p.is_identity():
                    identity_rep = coset["representative"]
                    break
            if identity_rep:
                break

        identity_ok = identity_rep != ""
        if identity_ok:
            for rep in rep_list:
                left = table.get(identity_rep, {}).get(rep, "")
                right = table.get(rep, {}).get(identity_rep, "")
                if left != rep or right != rep:
                    identity_ok = False
                    break

        # 3. Inverses
        inverses_ok = identity_rep != ""
        if inverses_ok:
            for rep in rep_list:
                found_inverse = False
                for candidate in rep_list:
                    product = table.get(rep, {}).get(candidate, "")
                    if product == identity_rep:
                        found_inverse = True
                        break
                if not found_inverse:
                    inverses_ok = False
                    break

        all_valid = closure_ok and identity_ok and inverses_ok
        return {
            "valid": all_valid,
            "checks": {
                "closure": closure_ok,
                "identity": identity_ok,
                "inverses": inverses_ok,
            },
        }

    # --- Construction ---

    def construct_quotient(self, subgroup_index: int) -> dict:
        if subgroup_index < 0 or subgroup_index >= len(self._normal_subgroups):
            return {"error": "invalid_index"}

        if subgroup_index in self._constructed:
            return {"error": "already_constructed"}

        cosets = self.compute_cosets(subgroup_index)
        table = self.get_quotient_table(subgroup_index)
        verification = self.verify_quotient(subgroup_index)

        if not verification.get("valid", False):
            return {"error": "verification_failed"}

        ns_data = self._normal_subgroups[subgroup_index]

        result = {
            "quotient_order": len(cosets),
            "quotient_type": ns_data.get("quotient_type", ""),
            "cosets": cosets,
            "table": table,
            "verified": True,
        }

        self._constructed[subgroup_index] = result
        self._constructed_count += 1
        self._signals.append(("quotient_constructed", subgroup_index))

        if self._constructed_count >= self._total_count:
            self._signals.append(("all_quotients_done",))

        return result

    # --- Progress ---

    def get_progress(self) -> dict:
        return {
            "constructed": self._constructed_count,
            "total": self._total_count,
        }

    def is_complete(self) -> bool:
        return self._constructed_count >= self._total_count and self._total_count >= 0

    def is_constructed(self, index: int) -> bool:
        return index in self._constructed

    def get_construction(self, index: int) -> dict:
        return self._constructed.get(index, {})

    # --- Persistence ---

    def save_state(self) -> dict:
        constructed_data = {}
        for idx, val in self._constructed.items():
            constructed_data[str(idx)] = dict(val)

        return {
            "status": "completed" if self.is_complete() else "in_progress",
            "constructed": constructed_data,
            "constructed_count": self._constructed_count,
            "total_count": self._total_count,
        }

    def restore_from_save(self, save_data: dict) -> None:
        self._constructed.clear()
        constructed_data = save_data.get("constructed", {})
        for idx_str, val in constructed_data.items():
            self._constructed[int(idx_str)] = val

        self._constructed_count = save_data.get("constructed_count", len(self._constructed))

    # --- Query helpers ---

    def get_perm(self, sym_id: str):
        return self._sym_id_to_perm.get(sym_id)

    def get_name(self, sym_id: str) -> str:
        return self._sym_id_to_name.get(sym_id, sym_id)

    def get_all_sym_ids(self) -> list[str]:
        return list(self._all_sym_ids)

    def find_coset_representative(self, subgroup_index: int, element_sym_id: str) -> str:
        cosets = self.compute_cosets(subgroup_index)
        for coset in cosets:
            if element_sym_id in coset["elements"]:
                return coset["representative"]
        return ""

    def _find_sym_id_for_perm(self, perm: Permutation) -> str:
        for sym_id, p in self._sym_id_to_perm.items():
            if p.equals(perm):
                return sym_id
        return ""

    def _compose_sym_ids(self, a_sid: str, b_sid: str) -> str:
        """Compose two elements by sym_id. Uses permutation composition first;
        falls back to Cayley table for groups with unfaithful representations (Q8)."""
        a_perm = self._sym_id_to_perm.get(a_sid)
        b_perm = self._sym_id_to_perm.get(b_sid)
        if a_perm is not None and b_perm is not None:
            product = a_perm.compose(b_perm)
            result = self._find_sym_id_for_perm(product)
            if result != "":
                return result
        # Fallback: Cayley table
        return self._cayley_table.get(a_sid, {}).get(b_sid, "")


# === Test Helpers ===

LEVELS_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "data", "levels", "act1")


def load_level_json(filename: str) -> dict:
    path = os.path.join(LEVELS_DIR, filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# Levels with no quotient groups (empty quotient_groups array)
# These are prime-order or Z2 groups with no non-trivial normal subgroups
NO_QUOTIENT_LEVELS = {
    "level_01.json", "level_02.json", "level_03.json",
    "level_07.json", "level_08.json", "level_10.json",
    "level_13.json", "level_16.json",
}


def _setup_mgr(filename: str) -> QuotientGroupManager:
    """Load a level and set up QuotientGroupManager."""
    data = load_level_json(filename)
    layer_config = data.get("layers", {}).get("layer_5", {})
    mgr = QuotientGroupManager()
    mgr.setup(data, layer_config)
    return mgr


# =============================================================================
# Test Classes
# =============================================================================


class TestQuotientSetup(unittest.TestCase):
    """Test QuotientGroupManager.setup() across different group types."""

    def test_s3_setup_one_quotient(self):
        """S3 (level_09): has 1 normal subgroup -> 1 quotient group."""
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.get_normal_subgroup_count(), 1)
        self.assertEqual(mgr.get_progress()["total"], 1)

    def test_z4_setup_one_quotient(self):
        """Z4 (level_04): has 1 normal subgroup of order 2."""
        mgr = _setup_mgr("level_04.json")
        self.assertEqual(mgr.get_normal_subgroup_count(), 1)

    def test_v4_setup_three_quotients(self):
        """V4 (level_06): has 3 normal subgroups -> 3 quotient groups."""
        mgr = _setup_mgr("level_06.json")
        self.assertEqual(mgr.get_normal_subgroup_count(), 3)

    def test_z3_setup_no_quotients(self):
        """Z3 (level_01): no non-trivial normal subgroups -> 0 quotient groups."""
        mgr = _setup_mgr("level_01.json")
        self.assertEqual(mgr.get_normal_subgroup_count(), 0)
        self.assertTrue(mgr.is_complete(), "No quotient groups -> auto-complete")

    def test_all_levels_have_layer5(self):
        """Every level JSON should have a layer_5 section."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            data = load_level_json(filename)
            layer_5 = data.get("layers", {}).get("layer_5", None)
            self.assertIsNotNone(layer_5, f"{filename}: missing layer_5 section")

    def test_no_quotient_levels_have_empty_list(self):
        """Levels with no non-trivial normal subgroups have empty quotient_groups."""
        for filename in NO_QUOTIENT_LEVELS:
            mgr = _setup_mgr(filename)
            self.assertEqual(mgr.get_normal_subgroup_count(), 0,
                f"{filename}: should have no quotient groups")
            self.assertTrue(mgr.is_complete(),
                f"{filename}: should auto-complete with 0 quotient groups")

    def test_automorphisms_loaded(self):
        """All automorphisms from level data should be loaded."""
        mgr = _setup_mgr("level_09.json")
        all_ids = mgr.get_all_sym_ids()
        self.assertEqual(len(all_ids), 6, "S3 has 6 elements")
        self.assertIn("e", all_ids)
        self.assertIn("r1", all_ids)


class TestNormalSubgroupAccess(unittest.TestCase):
    """Test accessing normal subgroup data."""

    def test_get_normal_subgroup_elements_s3(self):
        """S3: normal subgroup is {e, r1, r2} (the rotation subgroup)."""
        mgr = _setup_mgr("level_09.json")
        elements = mgr.get_normal_subgroup_elements(0)
        self.assertEqual(sorted(elements), ["e", "r1", "r2"])

    def test_get_normal_subgroup_elements_out_of_range(self):
        """Out-of-range index returns empty list."""
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.get_normal_subgroup_elements(99), [])
        self.assertEqual(mgr.get_normal_subgroup_elements(-1), [])

    def test_get_normal_subgroups_returns_copies(self):
        """get_normal_subgroups returns a copy, not the internal list."""
        mgr = _setup_mgr("level_09.json")
        subs1 = mgr.get_normal_subgroups()
        subs2 = mgr.get_normal_subgroups()
        self.assertEqual(len(subs1), len(subs2))
        self.assertIsNot(subs1, subs2)


class TestCosetComputation(unittest.TestCase):
    """Test coset decomposition."""

    def test_s3_cosets_by_rotation_subgroup(self):
        """S3 / {e,r1,r2}: 2 cosets of size 3."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        self.assertEqual(len(cosets), 2)
        for coset in cosets:
            self.assertEqual(len(coset["elements"]), 3)

    def test_s3_cosets_partition_group(self):
        """Cosets must partition the group: every element in exactly one coset."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        all_elements = []
        for coset in cosets:
            all_elements.extend(coset["elements"])
        self.assertEqual(sorted(all_elements), sorted(mgr.get_all_sym_ids()))

    def test_z4_cosets(self):
        """Z4 / {e,r2}: 2 cosets of size 2."""
        mgr = _setup_mgr("level_04.json")
        cosets = mgr.compute_cosets(0)
        self.assertEqual(len(cosets), 2)
        for coset in cosets:
            self.assertEqual(len(coset["elements"]), 2)

    def test_v4_three_coset_decompositions(self):
        """V4 has 3 normal subgroups, each giving 2 cosets of size 2."""
        mgr = _setup_mgr("level_06.json")
        for i in range(3):
            cosets = mgr.compute_cosets(i)
            self.assertEqual(len(cosets), 2,
                f"V4 quotient {i}: should have 2 cosets")
            for coset in cosets:
                self.assertEqual(len(coset["elements"]), 2)

    def test_coset_has_representative(self):
        """Each coset's representative should be in its own elements."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        for coset in cosets:
            self.assertIn(coset["representative"], coset["elements"],
                f"Representative {coset['representative']} should be in its own coset")

    def test_identity_coset_contains_normal_subgroup(self):
        """The identity coset should contain all elements of the normal subgroup."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        ns_elements = set(mgr.get_normal_subgroup_elements(0))

        # Find the coset containing the identity
        identity_coset = None
        for coset in cosets:
            for elem in coset["elements"]:
                p = mgr.get_perm(elem)
                if p is not None and p.is_identity():
                    identity_coset = coset
                    break
            if identity_coset:
                break

        self.assertIsNotNone(identity_coset)
        self.assertEqual(set(identity_coset["elements"]), ns_elements)

    def test_coset_sizes_divide_group_order(self):
        """All cosets must have the same size, equal to |N|."""
        mgr = _setup_mgr("level_09.json")
        ns_size = len(mgr.get_normal_subgroup_elements(0))
        cosets = mgr.compute_cosets(0)
        for coset in cosets:
            self.assertEqual(len(coset["elements"]), ns_size)

    def test_cosets_are_cached(self):
        """Calling compute_cosets twice returns same structure (cached)."""
        mgr = _setup_mgr("level_09.json")
        cosets1 = mgr.compute_cosets(0)
        cosets2 = mgr.compute_cosets(0)
        self.assertEqual(len(cosets1), len(cosets2))
        for i in range(len(cosets1)):
            self.assertEqual(cosets1[i]["representative"], cosets2[i]["representative"])
            self.assertEqual(sorted(cosets1[i]["elements"]), sorted(cosets2[i]["elements"]))

    def test_out_of_range_returns_empty(self):
        """Out-of-range index returns empty list."""
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.compute_cosets(99), [])
        self.assertEqual(mgr.compute_cosets(-1), [])


class TestQuotientTable(unittest.TestCase):
    """Test quotient group multiplication table."""

    def test_s3_quotient_table_z2(self):
        """S3 / {e,r1,r2} is isomorphic to Z2: table should be 2x2."""
        mgr = _setup_mgr("level_09.json")
        table = mgr.get_quotient_table(0)
        self.assertEqual(len(table), 2, "Z2 quotient table should have 2 rows")
        for rep_a, row in table.items():
            self.assertEqual(len(row), 2, "Each row should have 2 entries")

    def test_z4_quotient_table(self):
        """Z4 / {e,r2} is Z2: table should be 2x2."""
        mgr = _setup_mgr("level_04.json")
        table = mgr.get_quotient_table(0)
        self.assertEqual(len(table), 2)

    def test_table_closure(self):
        """Every product in the table should be a valid representative."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        table = mgr.get_quotient_table(0)
        reps = {c["representative"] for c in cosets}
        for rep_a, row in table.items():
            self.assertIn(rep_a, reps)
            for rep_b, result in row.items():
                self.assertIn(rep_b, reps)
                self.assertIn(result, reps,
                    f"{rep_a} * {rep_b} = {result} not in representatives")

    def test_identity_coset_is_identity(self):
        """The coset containing the identity should act as identity in the table."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        table = mgr.get_quotient_table(0)

        # Find identity representative
        identity_rep = None
        for coset in cosets:
            for elem in coset["elements"]:
                p = mgr.get_perm(elem)
                if p is not None and p.is_identity():
                    identity_rep = coset["representative"]
                    break
            if identity_rep:
                break

        self.assertIsNotNone(identity_rep)

        # eN * gN = gN for all g
        reps = [c["representative"] for c in cosets]
        for rep in reps:
            self.assertEqual(table[identity_rep][rep], rep)
            self.assertEqual(table[rep][identity_rep], rep)

    def test_every_element_has_inverse(self):
        """Every coset representative should have an inverse in the table."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        table = mgr.get_quotient_table(0)

        # Find identity representative
        identity_rep = None
        for coset in cosets:
            for elem in coset["elements"]:
                p = mgr.get_perm(elem)
                if p is not None and p.is_identity():
                    identity_rep = coset["representative"]
                    break
            if identity_rep:
                break

        reps = [c["representative"] for c in cosets]
        for rep in reps:
            found = any(table[rep][candidate] == identity_rep for candidate in reps)
            self.assertTrue(found, f"Representative {rep} has no inverse")

    def test_out_of_range_returns_empty(self):
        """Out-of-range index returns empty dict."""
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.get_quotient_table(99), {})

    def test_quotient_table_well_defined(self):
        """Quotient operation must be well-defined: same coset product
        regardless of which representative we pick."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        table = mgr.get_quotient_table(0)

        # Build element -> representative map
        elem_to_rep = {}
        for coset in cosets:
            rep = coset["representative"]
            for elem in coset["elements"]:
                elem_to_rep[elem] = rep

        # For every pair of elements, check:
        #   rep(a*b) = table[rep(a)][rep(b)]
        all_ids = mgr.get_all_sym_ids()
        for a_sid in all_ids:
            for b_sid in all_ids:
                product_sid = mgr._compose_sym_ids(a_sid, b_sid)
                self.assertIn(product_sid, elem_to_rep,
                    f"Product {a_sid}*{b_sid}={product_sid} not in any coset")
                rep_of_product = elem_to_rep[product_sid]
                table_result = table[elem_to_rep[a_sid]][elem_to_rep[b_sid]]
                self.assertEqual(rep_of_product, table_result,
                    f"Well-definedness failed: {a_sid}*{b_sid}={product_sid}, "
                    f"rep={rep_of_product} but table gives {table_result}")


class TestVerification(unittest.TestCase):
    """Test quotient group axiom verification."""

    def test_s3_quotient_valid(self):
        """S3 / {e,r1,r2} should pass all axiom checks."""
        mgr = _setup_mgr("level_09.json")
        result = mgr.verify_quotient(0)
        self.assertTrue(result["valid"])
        self.assertTrue(result["checks"]["closure"])
        self.assertTrue(result["checks"]["identity"])
        self.assertTrue(result["checks"]["inverses"])

    def test_z4_quotient_valid(self):
        """Z4 / {e,r2} should pass all axiom checks."""
        mgr = _setup_mgr("level_04.json")
        result = mgr.verify_quotient(0)
        self.assertTrue(result["valid"])

    def test_v4_all_quotients_valid(self):
        """All 3 quotients of V4 should pass verification."""
        mgr = _setup_mgr("level_06.json")
        for i in range(3):
            result = mgr.verify_quotient(i)
            self.assertTrue(result["valid"], f"V4 quotient {i} failed verification")

    def test_out_of_range_returns_invalid(self):
        """Out-of-range index returns invalid."""
        mgr = _setup_mgr("level_09.json")
        result = mgr.verify_quotient(99)
        self.assertFalse(result["valid"])

    def test_all_levels_with_quotients_verify(self):
        """Every level with quotient_groups should pass verification."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            for j in range(mgr.get_normal_subgroup_count()):
                result = mgr.verify_quotient(j)
                self.assertTrue(result["valid"],
                    f"{filename} quotient {j}: verification failed "
                    f"(closure={result['checks'].get('closure')}, "
                    f"identity={result['checks'].get('identity')}, "
                    f"inverses={result['checks'].get('inverses')})")


class TestConstruction(unittest.TestCase):
    """Test quotient construction and signal emission."""

    def test_construct_quotient_s3(self):
        """Constructing the S3 quotient should succeed and emit signal."""
        mgr = _setup_mgr("level_09.json")
        result = mgr.construct_quotient(0)
        self.assertNotIn("error", result)
        self.assertEqual(result["quotient_order"], 2)
        self.assertEqual(result["quotient_type"], "Z2")
        self.assertTrue(result["verified"])
        self.assertIn(("quotient_constructed", 0), mgr._signals)

    def test_construct_duplicate_fails(self):
        """Cannot construct same quotient twice."""
        mgr = _setup_mgr("level_09.json")
        mgr.construct_quotient(0)
        result = mgr.construct_quotient(0)
        self.assertEqual(result["error"], "already_constructed")

    def test_construct_invalid_index(self):
        """Invalid index returns error."""
        mgr = _setup_mgr("level_09.json")
        result = mgr.construct_quotient(99)
        self.assertEqual(result["error"], "invalid_index")

    def test_all_quotients_done_signal(self):
        """Constructing all quotients emits all_quotients_done."""
        mgr = _setup_mgr("level_06.json")  # V4: 3 quotients
        for i in range(3):
            mgr.construct_quotient(i)

        self.assertIn(("all_quotients_done",), mgr._signals)
        self.assertTrue(mgr.is_complete())

    def test_is_constructed(self):
        """is_constructed returns correct state."""
        mgr = _setup_mgr("level_09.json")
        self.assertFalse(mgr.is_constructed(0))
        mgr.construct_quotient(0)
        self.assertTrue(mgr.is_constructed(0))

    def test_get_construction(self):
        """get_construction returns the stored result."""
        mgr = _setup_mgr("level_09.json")
        mgr.construct_quotient(0)
        result = mgr.get_construction(0)
        self.assertEqual(result["quotient_order"], 2)
        self.assertTrue(result["verified"])

    def test_get_construction_empty_if_not_built(self):
        """get_construction returns empty dict if not built."""
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.get_construction(0), {})


class TestProgress(unittest.TestCase):
    """Test progress tracking."""

    def test_progress_starts_at_zero(self):
        """Initial progress should be 0/total."""
        mgr = _setup_mgr("level_06.json")
        p = mgr.get_progress()
        self.assertEqual(p["constructed"], 0)
        self.assertEqual(p["total"], 3)

    def test_progress_increments(self):
        """Progress increments with each construction."""
        mgr = _setup_mgr("level_06.json")
        mgr.construct_quotient(0)
        p = mgr.get_progress()
        self.assertEqual(p["constructed"], 1)
        self.assertEqual(p["total"], 3)

    def test_complete_after_all_constructed(self):
        """is_complete after constructing all quotients."""
        mgr = _setup_mgr("level_09.json")
        self.assertFalse(mgr.is_complete())
        mgr.construct_quotient(0)
        self.assertTrue(mgr.is_complete())

    def test_no_quotient_levels_auto_complete(self):
        """Levels with 0 quotient groups are auto-complete."""
        for filename in NO_QUOTIENT_LEVELS:
            mgr = _setup_mgr(filename)
            self.assertTrue(mgr.is_complete(),
                f"{filename}: 0 quotients should auto-complete")


class TestPersistence(unittest.TestCase):
    """Test save/restore state."""

    def test_save_state(self):
        """save_state returns valid dictionary."""
        mgr = _setup_mgr("level_09.json")
        mgr.construct_quotient(0)
        state = mgr.save_state()
        self.assertEqual(state["status"], "completed")
        self.assertEqual(state["constructed_count"], 1)
        self.assertIn("0", state["constructed"])

    def test_save_in_progress(self):
        """save_state shows in_progress when not all constructed."""
        mgr = _setup_mgr("level_06.json")
        mgr.construct_quotient(0)
        state = mgr.save_state()
        self.assertEqual(state["status"], "in_progress")

    def test_restore_from_save(self):
        """Restoring from save prevents re-construction."""
        mgr = _setup_mgr("level_09.json")
        mgr.construct_quotient(0)
        state = mgr.save_state()

        # Create new manager and restore
        mgr2 = _setup_mgr("level_09.json")
        mgr2.restore_from_save(state)
        self.assertEqual(mgr2._constructed_count, 1)
        self.assertTrue(mgr2.is_constructed(0))

        # Cannot re-construct
        result = mgr2.construct_quotient(0)
        self.assertEqual(result["error"], "already_constructed")


class TestCosetRepresentativeLookup(unittest.TestCase):
    """Test find_coset_representative helper."""

    def test_find_rep_for_element(self):
        """Every group element should map to a valid coset representative."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        reps = {c["representative"] for c in cosets}

        for sid in mgr.get_all_sym_ids():
            rep = mgr.find_coset_representative(0, sid)
            self.assertIn(rep, reps, f"{sid} should map to a valid representative")

    def test_find_rep_for_representative(self):
        """A representative should map to itself."""
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        for coset in cosets:
            rep = mgr.find_coset_representative(0, coset["representative"])
            self.assertEqual(rep, coset["representative"])

    def test_find_rep_unknown_element(self):
        """Unknown element returns empty string."""
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.find_coset_representative(0, "nonexistent"), "")


class TestMathematicalCorrectnessAllLevels(unittest.TestCase):
    """Verify mathematical correctness of quotient groups across all levels."""

    def test_quotient_order_equals_index(self):
        """Quotient order should equal |G|/|N| (Lagrange's theorem)."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            group_order = len(mgr.get_all_sym_ids())
            for j in range(mgr.get_normal_subgroup_count()):
                ns_order = len(mgr.get_normal_subgroup_elements(j))
                cosets = mgr.compute_cosets(j)
                expected_quotient_order = group_order // ns_order
                self.assertEqual(len(cosets), expected_quotient_order,
                    f"{filename} quotient {j}: |G/N| should be {expected_quotient_order}, "
                    f"got {len(cosets)}")

    def test_normal_subgroups_are_actually_normal(self):
        """Verify that the listed normal subgroups are indeed normal."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            group_perms = [mgr.get_perm(sid) for sid in mgr.get_all_sym_ids()]
            for j in range(mgr.get_normal_subgroup_count()):
                ns_elements = mgr.get_normal_subgroup_elements(j)
                ns_perms = [mgr.get_perm(sid) for sid in ns_elements]
                self.assertTrue(is_normal(ns_perms, group_perms),
                    f"{filename} quotient {j}: normal subgroup is not actually normal")

    def test_cosets_have_equal_size(self):
        """All cosets of a normal subgroup should have the same size."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            for j in range(mgr.get_normal_subgroup_count()):
                cosets = mgr.compute_cosets(j)
                if not cosets:
                    continue
                expected_size = len(cosets[0]["elements"])
                for k, coset in enumerate(cosets):
                    self.assertEqual(len(coset["elements"]), expected_size,
                        f"{filename} quotient {j}: coset {k} has {len(coset['elements'])} "
                        f"elements, expected {expected_size}")

    def test_cosets_partition_group(self):
        """Cosets should partition G: each element in exactly one coset."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            for j in range(mgr.get_normal_subgroup_count()):
                cosets = mgr.compute_cosets(j)
                all_elements = []
                for coset in cosets:
                    all_elements.extend(coset["elements"])
                self.assertEqual(sorted(all_elements), sorted(mgr.get_all_sym_ids()),
                    f"{filename} quotient {j}: cosets don't partition the group")

    def test_all_levels_completable(self):
        """Every level with quotient groups can be fully completed."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            mgr = _setup_mgr(filename)
            if filename in NO_QUOTIENT_LEVELS:
                self.assertTrue(mgr.is_complete())
                continue
            for j in range(mgr.get_normal_subgroup_count()):
                result = mgr.construct_quotient(j)
                self.assertNotIn("error", result,
                    f"{filename} quotient {j}: construction failed with {result}")
            self.assertTrue(mgr.is_complete(),
                f"{filename}: not complete after constructing all quotients")

    def test_quotient_table_matches_json_data(self):
        """Computed quotient order should match the JSON quotient_order field."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            for j in range(mgr.get_normal_subgroup_count()):
                ns_data = mgr.get_normal_subgroups()[j]
                expected_order = ns_data.get("quotient_order", 0)
                cosets = mgr.compute_cosets(j)
                self.assertEqual(len(cosets), expected_order,
                    f"{filename} quotient {j}: computed {len(cosets)} cosets "
                    f"but JSON says quotient_order={expected_order}")


class TestEdgeCases(unittest.TestCase):
    """Test edge cases and boundary conditions."""

    def test_q8_quotient(self):
        """Q8 (level_21): quotient by center {id, neg} gives order-4 group."""
        mgr = _setup_mgr("level_21.json")
        self.assertGreater(mgr.get_normal_subgroup_count(), 0)
        cosets = mgr.compute_cosets(0)
        self.assertEqual(len(cosets), 4, "Q8/{id,neg} has order 4")
        verification = mgr.verify_quotient(0)
        self.assertTrue(verification["valid"])

    def test_a4_quotient(self):
        """A4 (level_15): quotient by Klein V4 gives Z3."""
        mgr = _setup_mgr("level_15.json")
        self.assertEqual(mgr.get_normal_subgroup_count(), 1)
        cosets = mgr.compute_cosets(0)
        self.assertEqual(len(cosets), 3, "A4/V4 has order 3")
        verification = mgr.verify_quotient(0)
        self.assertTrue(verification["valid"])

    def test_s4_quotient(self):
        """S4 (level_23) or (level_24): should have quotient groups."""
        mgr = _setup_mgr("level_23.json")
        self.assertGreater(mgr.get_normal_subgroup_count(), 0)
        for j in range(mgr.get_normal_subgroup_count()):
            verification = mgr.verify_quotient(j)
            self.assertTrue(verification["valid"],
                f"S4 quotient {j} verification failed")

    def test_abelian_group_all_quotients_valid(self):
        """In abelian groups (Z6), all quotients should verify."""
        mgr = _setup_mgr("level_11.json")  # Z6
        for j in range(mgr.get_normal_subgroup_count()):
            verification = mgr.verify_quotient(j)
            self.assertTrue(verification["valid"],
                f"Z6 quotient {j} verification failed")

    def test_dihedral_group_quotients(self):
        """D4 levels (level_05 or level_12): should have multiple quotient groups."""
        mgr = _setup_mgr("level_05.json")
        self.assertGreater(mgr.get_normal_subgroup_count(), 0)
        for j in range(mgr.get_normal_subgroup_count()):
            result = mgr.construct_quotient(j)
            self.assertNotIn("error", result,
                f"D4 quotient {j} construction failed")


if __name__ == "__main__":
    unittest.main()
