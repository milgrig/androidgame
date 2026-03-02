"""
Unit tests for Layer 5: Quotient Group Construction.
Tests the QuotientGroupManager logic (Python mirror) and validates
coset decomposition, quotient table correctness, two-phase interactive
construction, and type identification across all 24 level JSON files.

T119: Layer 5 Engine -- Quotient Group Manager
T128: Interactive validation API (two-phase construction)
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


# === Construction State Enum (mirrors GDScript enum) ===

class ConstructionState:
    PENDING = 0
    COSETS_BUILDING = 1
    COSETS_DONE = 2
    TYPE_IDENTIFIED = 3


# === All known quotient types for distractor generation ===

ALL_QUOTIENT_TYPES = [
    "Z2", "Z3", "Z4", "Z2xZ2", "Z5", "Z6", "S3",
    "Z4_or_Z2xZ2", "Z6_or_S3", "Z8", "Z4xZ2", "Z2xZ2xZ2",
    "D4", "Q8", "order8",
]


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

        self._construction_states: dict[int, int] = {}
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
        self._construction_states.clear()
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

        # Initialize all construction states to PENDING
        for i in range(self._total_count):
            self._construction_states[i] = ConstructionState.PENDING

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

    # --- Construction State ---

    def get_construction_state(self, sg_index: int) -> int:
        return self._construction_states.get(sg_index, ConstructionState.PENDING)

    def begin_coset_building(self, sg_index: int) -> bool:
        if sg_index < 0 or sg_index >= len(self._normal_subgroups):
            return False
        state = self._construction_states.get(sg_index, ConstructionState.PENDING)
        if state != ConstructionState.PENDING:
            return False
        self._construction_states[sg_index] = ConstructionState.COSETS_BUILDING
        return True

    # --- Step 1 API: Coset Assignment Validation ---

    def validate_element_in_coset(self, sg_index: int, element_sym_id: str, coset_index: int) -> bool:
        cosets = self.compute_cosets(sg_index)
        if coset_index < 0 or coset_index >= len(cosets):
            return False
        return element_sym_id in cosets[coset_index]["elements"]

    def get_coset_size(self, sg_index: int) -> int:
        if sg_index < 0 or sg_index >= len(self._normal_subgroups):
            return 0
        ns_elements = self._normal_subgroups[sg_index].get("normal_subgroup_elements", [])
        return len(ns_elements)

    def get_num_cosets(self, sg_index: int) -> int:
        cosets = self.compute_cosets(sg_index)
        return len(cosets)

    def is_coset_assignment_complete(self, sg_index: int, assignments: dict) -> bool:
        cosets = self.compute_cosets(sg_index)
        if not cosets:
            return False

        if len(assignments) != len(self._all_sym_ids):
            return False

        for sym_id in self._all_sym_ids:
            if sym_id not in assignments:
                return False
            assigned_coset = assignments[sym_id]
            if assigned_coset < 0 or assigned_coset >= len(cosets):
                return False
            if sym_id not in cosets[assigned_coset]["elements"]:
                return False

        return True

    def complete_coset_assignment(self, sg_index: int, assignments: dict) -> bool:
        if sg_index < 0 or sg_index >= len(self._normal_subgroups):
            return False

        state = self._construction_states.get(sg_index, ConstructionState.PENDING)
        if state != ConstructionState.COSETS_BUILDING:
            return False

        correct = self.is_coset_assignment_complete(sg_index, assignments)
        self._signals.append(("coset_assignment_validated", sg_index, correct))

        if correct:
            self._construction_states[sg_index] = ConstructionState.COSETS_DONE
        return correct

    # --- Step 2 API: Type Identification ---

    def check_quotient_type(self, sg_index: int, proposed_type: str) -> bool:
        correct_type = self.get_quotient_type(sg_index)
        if correct_type == "":
            return False
        return proposed_type == correct_type

    def get_quotient_type(self, sg_index: int) -> str:
        if sg_index < 0 or sg_index >= len(self._normal_subgroups):
            return ""
        return self._normal_subgroups[sg_index].get("quotient_type", "")

    def generate_type_options(self, sg_index: int) -> list[str]:
        correct = self.get_quotient_type(sg_index)
        if correct == "":
            return []

        quotient_order = self._normal_subgroups[sg_index].get("quotient_order", 0)

        distractors_by_order = {
            2: ["Z2", "Z3", "Z4"],
            3: ["Z3", "Z2", "S3"],
            4: ["Z4", "Z2xZ2", "Z4_or_Z2xZ2", "Z2", "D4"],
            6: ["Z6", "S3", "Z6_or_S3", "Z3", "D3"],
            8: ["Z8", "Z4xZ2", "Z2xZ2xZ2", "D4", "Q8", "order8"],
        }

        candidates = list(distractors_by_order.get(quotient_order, []))

        # Add some wrong-order distractors for variety
        for t in ALL_QUOTIENT_TYPES:
            if t != correct and t not in candidates:
                candidates.append(t)

        # Pick 2-3 distractors (not equal to correct)
        target_count = 3 if len(candidates) >= 3 else len(candidates)
        distractors = []
        for c in candidates:
            if c != correct and len(distractors) < target_count:
                distractors.append(c)

        # Build options: correct + distractors (no shuffle in test mirror for determinism)
        options = [correct] + distractors
        return options

    def complete_type_identification(self, sg_index: int, proposed_type: str) -> dict:
        if sg_index < 0 or sg_index >= len(self._normal_subgroups):
            return {"error": "invalid_index"}

        state = self._construction_states.get(sg_index, ConstructionState.PENDING)
        if state != ConstructionState.COSETS_DONE:
            return {"error": "wrong_state"}

        correct = self.check_quotient_type(sg_index, proposed_type)
        self._signals.append(("quotient_type_guessed", sg_index, correct))

        if not correct:
            return {"error": "wrong_type"}

        # Finalize
        self._construction_states[sg_index] = ConstructionState.TYPE_IDENTIFIED

        cosets = self.compute_cosets(sg_index)
        table = self.get_quotient_table(sg_index)
        ns_data = self._normal_subgroups[sg_index]

        result = {
            "quotient_order": len(cosets),
            "quotient_type": ns_data.get("quotient_type", ""),
            "cosets": cosets,
            "table": table,
            "verified": True,
        }

        self._constructed[sg_index] = result
        self._constructed_count += 1
        self._signals.append(("quotient_constructed", sg_index))

        if self._constructed_count >= self._total_count:
            self._signals.append(("all_quotients_done",))

        return result

    # --- Legacy one-shot construction ---

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
        self._construction_states[subgroup_index] = ConstructionState.TYPE_IDENTIFIED
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

        states_data = {}
        for idx, val in self._construction_states.items():
            states_data[str(idx)] = val

        return {
            "status": "completed" if self.is_complete() else "in_progress",
            "constructed": constructed_data,
            "constructed_count": self._constructed_count,
            "total_count": self._total_count,
            "construction_states": states_data,
        }

    def restore_from_save(self, save_data: dict) -> None:
        self._constructed.clear()
        constructed_data = save_data.get("constructed", {})
        for idx_str, val in constructed_data.items():
            self._constructed[int(idx_str)] = val

        self._constructed_count = save_data.get("constructed_count", len(self._constructed))

        # Restore construction states
        self._construction_states.clear()
        states_data = save_data.get("construction_states", {})
        for idx_str, val in states_data.items():
            self._construction_states[int(idx_str)] = val

        # Ensure all subgroups have a state entry
        for i in range(self._total_count):
            if i not in self._construction_states:
                if i in self._constructed:
                    self._construction_states[i] = ConstructionState.TYPE_IDENTIFIED
                else:
                    self._construction_states[i] = ConstructionState.PENDING

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


def _build_correct_assignments(mgr: QuotientGroupManager, sg_index: int) -> dict:
    """Build a correct element->coset_index assignment dict."""
    cosets = mgr.compute_cosets(sg_index)
    assignments = {}
    for ci, coset in enumerate(cosets):
        for elem in coset["elements"]:
            assignments[elem] = ci
    return assignments


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

    def test_construction_states_initialized(self):
        """All subgroups should start in PENDING state."""
        mgr = _setup_mgr("level_06.json")
        for i in range(3):
            self.assertEqual(mgr.get_construction_state(i), ConstructionState.PENDING)


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

    def test_construct_sets_state_to_type_identified(self):
        """One-shot construct_quotient should set state to TYPE_IDENTIFIED."""
        mgr = _setup_mgr("level_09.json")
        mgr.construct_quotient(0)
        self.assertEqual(mgr.get_construction_state(0), ConstructionState.TYPE_IDENTIFIED)


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

    def test_save_restore_construction_states(self):
        """Construction states survive save/restore cycle."""
        mgr = _setup_mgr("level_06.json")  # V4: 3 quotients
        mgr.begin_coset_building(0)
        assignments = _build_correct_assignments(mgr, 0)
        mgr.complete_coset_assignment(0, assignments)
        # sg 0 is COSETS_DONE, sg 1 is PENDING, sg 2 is PENDING

        state = mgr.save_state()

        mgr2 = _setup_mgr("level_06.json")
        mgr2.restore_from_save(state)
        self.assertEqual(mgr2.get_construction_state(0), ConstructionState.COSETS_DONE)
        self.assertEqual(mgr2.get_construction_state(1), ConstructionState.PENDING)

    def test_restore_without_states_infers_from_constructed(self):
        """Old save format without construction_states still works."""
        mgr = _setup_mgr("level_09.json")
        mgr.construct_quotient(0)
        state = mgr.save_state()

        # Remove construction_states from saved data (simulate old format)
        del state["construction_states"]

        mgr2 = _setup_mgr("level_09.json")
        mgr2.restore_from_save(state)
        self.assertEqual(mgr2.get_construction_state(0), ConstructionState.TYPE_IDENTIFIED)


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


# =============================================================================
# T128: Two-Phase Construction Tests
# =============================================================================


class TestConstructionStateTransitions(unittest.TestCase):
    """Test the state machine: PENDING -> COSETS_BUILDING -> COSETS_DONE -> TYPE_IDENTIFIED."""

    def test_initial_state_is_pending(self):
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.get_construction_state(0), ConstructionState.PENDING)

    def test_begin_coset_building(self):
        mgr = _setup_mgr("level_09.json")
        self.assertTrue(mgr.begin_coset_building(0))
        self.assertEqual(mgr.get_construction_state(0), ConstructionState.COSETS_BUILDING)

    def test_begin_coset_building_only_from_pending(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        # Cannot begin again from COSETS_BUILDING
        self.assertFalse(mgr.begin_coset_building(0))

    def test_begin_coset_building_invalid_index(self):
        mgr = _setup_mgr("level_09.json")
        self.assertFalse(mgr.begin_coset_building(99))
        self.assertFalse(mgr.begin_coset_building(-1))

    def test_complete_coset_assignment_transitions_to_cosets_done(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        assignments = _build_correct_assignments(mgr, 0)
        self.assertTrue(mgr.complete_coset_assignment(0, assignments))
        self.assertEqual(mgr.get_construction_state(0), ConstructionState.COSETS_DONE)

    def test_complete_coset_assignment_wrong_stays_in_building(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        # All elements assigned to coset 0 — wrong
        bad_assignments = {sid: 0 for sid in mgr.get_all_sym_ids()}
        self.assertFalse(mgr.complete_coset_assignment(0, bad_assignments))
        self.assertEqual(mgr.get_construction_state(0), ConstructionState.COSETS_BUILDING)

    def test_complete_coset_assignment_requires_building_state(self):
        mgr = _setup_mgr("level_09.json")
        # Still PENDING — should fail
        assignments = _build_correct_assignments(mgr, 0)
        self.assertFalse(mgr.complete_coset_assignment(0, assignments))

    def test_complete_type_identification_transitions_to_type_identified(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        assignments = _build_correct_assignments(mgr, 0)
        mgr.complete_coset_assignment(0, assignments)

        correct_type = mgr.get_quotient_type(0)
        result = mgr.complete_type_identification(0, correct_type)
        self.assertNotIn("error", result)
        self.assertEqual(mgr.get_construction_state(0), ConstructionState.TYPE_IDENTIFIED)
        self.assertTrue(mgr.is_constructed(0))

    def test_complete_type_wrong_stays_in_cosets_done(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        assignments = _build_correct_assignments(mgr, 0)
        mgr.complete_coset_assignment(0, assignments)

        result = mgr.complete_type_identification(0, "WRONG_TYPE")
        self.assertEqual(result["error"], "wrong_type")
        self.assertEqual(mgr.get_construction_state(0), ConstructionState.COSETS_DONE)
        self.assertFalse(mgr.is_constructed(0))

    def test_complete_type_requires_cosets_done_state(self):
        mgr = _setup_mgr("level_09.json")
        # Still PENDING
        result = mgr.complete_type_identification(0, "Z2")
        self.assertEqual(result["error"], "wrong_state")

    def test_full_two_phase_flow(self):
        """Full happy path: begin -> assign cosets -> identify type -> done."""
        mgr = _setup_mgr("level_06.json")  # V4: 3 quotients

        for i in range(3):
            self.assertTrue(mgr.begin_coset_building(i))
            assignments = _build_correct_assignments(mgr, i)
            self.assertTrue(mgr.complete_coset_assignment(i, assignments))
            correct_type = mgr.get_quotient_type(i)
            result = mgr.complete_type_identification(i, correct_type)
            self.assertNotIn("error", result)

        self.assertTrue(mgr.is_complete())
        self.assertIn(("all_quotients_done",), mgr._signals)

    def test_full_two_phase_all_levels(self):
        """Two-phase construction works for every level with quotient groups."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            for j in range(mgr.get_normal_subgroup_count()):
                self.assertTrue(mgr.begin_coset_building(j),
                    f"{filename} sg {j}: begin_coset_building failed")
                assignments = _build_correct_assignments(mgr, j)
                self.assertTrue(mgr.complete_coset_assignment(j, assignments),
                    f"{filename} sg {j}: complete_coset_assignment failed")
                correct_type = mgr.get_quotient_type(j)
                result = mgr.complete_type_identification(j, correct_type)
                self.assertNotIn("error", result,
                    f"{filename} sg {j}: complete_type_identification failed: {result}")
            self.assertTrue(mgr.is_complete(),
                f"{filename}: not complete after two-phase construction")


class TestStep1CosetValidation(unittest.TestCase):
    """Test Step 1 API: validate_element_in_coset, get_coset_size, etc."""

    def test_validate_element_correct_coset(self):
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        for ci, coset in enumerate(cosets):
            for elem in coset["elements"]:
                self.assertTrue(mgr.validate_element_in_coset(0, elem, ci),
                    f"{elem} should be in coset {ci}")

    def test_validate_element_wrong_coset(self):
        mgr = _setup_mgr("level_09.json")
        cosets = mgr.compute_cosets(0)
        # Take element from coset 0, validate against coset 1
        if len(cosets) >= 2:
            elem = cosets[0]["elements"][0]
            self.assertFalse(mgr.validate_element_in_coset(0, elem, 1))

    def test_validate_element_invalid_coset_index(self):
        mgr = _setup_mgr("level_09.json")
        self.assertFalse(mgr.validate_element_in_coset(0, "e", 99))
        self.assertFalse(mgr.validate_element_in_coset(0, "e", -1))

    def test_validate_element_nonexistent_element(self):
        mgr = _setup_mgr("level_09.json")
        self.assertFalse(mgr.validate_element_in_coset(0, "nonexistent", 0))

    def test_get_coset_size(self):
        mgr = _setup_mgr("level_09.json")
        # S3 / {e,r1,r2}: |N| = 3
        self.assertEqual(mgr.get_coset_size(0), 3)

    def test_get_coset_size_z4(self):
        mgr = _setup_mgr("level_04.json")
        # Z4 / {e,r2}: |N| = 2
        self.assertEqual(mgr.get_coset_size(0), 2)

    def test_get_coset_size_invalid_index(self):
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.get_coset_size(99), 0)

    def test_get_num_cosets(self):
        mgr = _setup_mgr("level_09.json")
        # S3 / {e,r1,r2}: |G/N| = 2
        self.assertEqual(mgr.get_num_cosets(0), 2)

    def test_get_num_cosets_v4(self):
        mgr = _setup_mgr("level_06.json")
        for i in range(3):
            self.assertEqual(mgr.get_num_cosets(i), 2)

    def test_coset_assignment_complete_correct(self):
        mgr = _setup_mgr("level_09.json")
        assignments = _build_correct_assignments(mgr, 0)
        self.assertTrue(mgr.is_coset_assignment_complete(0, assignments))

    def test_coset_assignment_complete_wrong(self):
        mgr = _setup_mgr("level_09.json")
        # Swap one element to wrong coset
        assignments = _build_correct_assignments(mgr, 0)
        cosets = mgr.compute_cosets(0)
        if len(cosets) >= 2:
            # Move first element of coset 0 to coset 1
            elem = cosets[0]["elements"][0]
            assignments[elem] = 1
            self.assertFalse(mgr.is_coset_assignment_complete(0, assignments))

    def test_coset_assignment_incomplete_missing_elements(self):
        mgr = _setup_mgr("level_09.json")
        # Only assign some elements
        assignments = {"e": 0}
        self.assertFalse(mgr.is_coset_assignment_complete(0, assignments))

    def test_coset_assignment_invalid_coset_index(self):
        mgr = _setup_mgr("level_09.json")
        assignments = _build_correct_assignments(mgr, 0)
        # Set one element to invalid coset index
        first_key = list(assignments.keys())[0]
        assignments[first_key] = 99
        self.assertFalse(mgr.is_coset_assignment_complete(0, assignments))

    def test_validate_element_all_levels(self):
        """validate_element_in_coset works for all levels."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            for j in range(mgr.get_normal_subgroup_count()):
                cosets = mgr.compute_cosets(j)
                for ci, coset in enumerate(cosets):
                    for elem in coset["elements"]:
                        self.assertTrue(mgr.validate_element_in_coset(j, elem, ci),
                            f"{filename} sg {j}: {elem} should be in coset {ci}")


class TestStep2TypeIdentification(unittest.TestCase):
    """Test Step 2 API: type checking and distractor generation."""

    def test_check_quotient_type_correct(self):
        mgr = _setup_mgr("level_09.json")
        self.assertTrue(mgr.check_quotient_type(0, "Z2"))

    def test_check_quotient_type_wrong(self):
        mgr = _setup_mgr("level_09.json")
        self.assertFalse(mgr.check_quotient_type(0, "Z3"))

    def test_check_quotient_type_invalid_index(self):
        mgr = _setup_mgr("level_09.json")
        self.assertFalse(mgr.check_quotient_type(99, "Z2"))

    def test_get_quotient_type(self):
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.get_quotient_type(0), "Z2")

    def test_get_quotient_type_z3(self):
        mgr = _setup_mgr("level_11.json")
        # Z6 has quotient Z3 (first one)
        self.assertEqual(mgr.get_quotient_type(0), "Z3")

    def test_get_quotient_type_invalid_index(self):
        mgr = _setup_mgr("level_09.json")
        self.assertEqual(mgr.get_quotient_type(99), "")

    def test_generate_type_options_contains_correct(self):
        mgr = _setup_mgr("level_09.json")
        options = mgr.generate_type_options(0)
        self.assertIn("Z2", options)

    def test_generate_type_options_has_distractors(self):
        mgr = _setup_mgr("level_09.json")
        options = mgr.generate_type_options(0)
        self.assertGreaterEqual(len(options), 3, "Should have correct + 2+ distractors")

    def test_generate_type_options_no_duplicates(self):
        mgr = _setup_mgr("level_09.json")
        options = mgr.generate_type_options(0)
        self.assertEqual(len(options), len(set(options)), "No duplicate options")

    def test_generate_type_options_invalid_index(self):
        mgr = _setup_mgr("level_09.json")
        options = mgr.generate_type_options(99)
        self.assertEqual(options, [])

    def test_generate_type_options_all_levels(self):
        """All levels with quotients generate valid type options."""
        for i in range(1, 25):
            filename = f"level_{i:02d}.json"
            if filename in NO_QUOTIENT_LEVELS:
                continue
            mgr = _setup_mgr(filename)
            for j in range(mgr.get_normal_subgroup_count()):
                options = mgr.generate_type_options(j)
                correct = mgr.get_quotient_type(j)
                self.assertIn(correct, options,
                    f"{filename} sg {j}: correct type {correct} not in options {options}")
                self.assertGreaterEqual(len(options), 3,
                    f"{filename} sg {j}: too few options: {options}")

    def test_distractors_are_plausible_same_order(self):
        """At least some distractors should be for the same quotient order."""
        mgr = _setup_mgr("level_05.json")  # D4: has Z4_or_Z2xZ2 quotient
        # Find the Z4_or_Z2xZ2 quotient
        for j in range(mgr.get_normal_subgroup_count()):
            if mgr.get_quotient_type(j) == "Z4_or_Z2xZ2":
                options = mgr.generate_type_options(j)
                # Order 4 distractors like Z4, Z2xZ2 should be present
                order4_types = {"Z4", "Z2xZ2", "Z4_or_Z2xZ2"}
                order4_in_options = [o for o in options if o in order4_types]
                self.assertGreaterEqual(len(order4_in_options), 2,
                    f"Should have multiple order-4 distractors in {options}")
                break


class TestTwoPhaseSignals(unittest.TestCase):
    """Test signal emission during two-phase construction."""

    def test_coset_assignment_validated_signal_correct(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        assignments = _build_correct_assignments(mgr, 0)
        mgr.complete_coset_assignment(0, assignments)
        self.assertIn(("coset_assignment_validated", 0, True), mgr._signals)

    def test_coset_assignment_validated_signal_incorrect(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        bad = {sid: 0 for sid in mgr.get_all_sym_ids()}
        mgr.complete_coset_assignment(0, bad)
        self.assertIn(("coset_assignment_validated", 0, False), mgr._signals)

    def test_quotient_type_guessed_signal_correct(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        assignments = _build_correct_assignments(mgr, 0)
        mgr.complete_coset_assignment(0, assignments)
        mgr.complete_type_identification(0, "Z2")
        self.assertIn(("quotient_type_guessed", 0, True), mgr._signals)

    def test_quotient_type_guessed_signal_incorrect(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        assignments = _build_correct_assignments(mgr, 0)
        mgr.complete_coset_assignment(0, assignments)
        mgr.complete_type_identification(0, "WRONG")
        self.assertIn(("quotient_type_guessed", 0, False), mgr._signals)

    def test_quotient_constructed_signal_after_type_identification(self):
        mgr = _setup_mgr("level_09.json")
        mgr.begin_coset_building(0)
        assignments = _build_correct_assignments(mgr, 0)
        mgr.complete_coset_assignment(0, assignments)
        mgr.complete_type_identification(0, "Z2")
        self.assertIn(("quotient_constructed", 0), mgr._signals)

    def test_all_quotients_done_after_all_two_phase(self):
        mgr = _setup_mgr("level_06.json")  # V4: 3 quotients
        for i in range(3):
            mgr.begin_coset_building(i)
            assignments = _build_correct_assignments(mgr, i)
            mgr.complete_coset_assignment(i, assignments)
            correct_type = mgr.get_quotient_type(i)
            mgr.complete_type_identification(i, correct_type)
        self.assertIn(("all_quotients_done",), mgr._signals)


if __name__ == "__main__":
    unittest.main()
