"""
Unit tests for Inner Doors mechanic (Act 2, Levels 13-16).
Python mirrors of GDScript logic for executable verification.

Tests validate:
  - Level JSON files parse correctly and have valid structure
  - Subgroup definitions actually form valid subgroups (identity, closure, inverses)
  - Inner door required_subgroup references exist in subgroups list
  - Cayley table consistency with automorphism definitions
  - InnerDoorPanel matching logic (subset ↔ target subgroup)
"""
import json
import os
import unittest


# === Python mirrors of GDScript classes ===

class Permutation:
    def __init__(self, mapping: list[int]):
        self.mapping = list(mapping)

    def size(self) -> int:
        return len(self.mapping)

    def apply(self, i: int) -> int:
        return self.mapping[i]

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

    def equals(self, other: "Permutation") -> bool:
        return self.mapping == other.mapping

    def order(self) -> int:
        current = self
        identity = Permutation.create_identity(self.size())
        for k in range(1, 1000):
            if current.equals(identity):
                return k
            current = current.compose(self)
        return -1

    @staticmethod
    def create_identity(n: int) -> "Permutation":
        return Permutation(list(range(n)))


# === KeyRing mirror (subset check) ===

class KeyRing:
    def __init__(self):
        self.found: list[Permutation] = []

    def add_key(self, p: Permutation) -> bool:
        if self.contains(p):
            return False
        self.found.append(p)
        return True

    def contains(self, p: Permutation) -> bool:
        return any(k.equals(p) for k in self.found)

    def count(self) -> int:
        return len(self.found)

    def get_key(self, index: int) -> Permutation:
        return self.found[index]

    def check_subgroup(self, key_indices: list[int]) -> dict:
        subset = [self.found[i] for i in key_indices if 0 <= i < len(self.found)]
        result = {"is_subgroup": True, "missing_elements": [], "reasons": []}

        # Check identity
        has_id = any(p.is_identity() for p in subset)
        if not has_id:
            result["is_subgroup"] = False
            result["reasons"].append("missing_identity")

        # Check closure
        for a in subset:
            for b in subset:
                product = a.compose(b)
                if not any(s.equals(product) for s in subset):
                    result["is_subgroup"] = False
                    if not any(m.equals(product) for m in result["missing_elements"]):
                        result["missing_elements"].append(product)
                    if "not_closed_composition" not in result["reasons"]:
                        result["reasons"].append("not_closed_composition")

        # Check inverses
        for a in subset:
            inv = a.inverse()
            if not any(s.equals(inv) for s in subset):
                result["is_subgroup"] = False
                if not any(m.equals(inv) for m in result["missing_elements"]):
                    result["missing_elements"].append(inv)
                if "missing_inverse" not in result["reasons"]:
                    result["reasons"].append("missing_inverse")

        return result


# === Helper functions ===

def _get_level_dir():
    """Locate the data/levels/act2 directory."""
    # Walk up from test file to project root
    test_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.join(test_dir, "..", "..", "..")
    level_dir = os.path.join(project_root, "data", "levels", "act2")
    return os.path.normpath(level_dir)


def _load_level(level_num: int) -> dict:
    """Load a level JSON file by number."""
    level_dir = _get_level_dir()
    path = os.path.join(level_dir, f"level_{level_num}.json")
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _build_perm_map(level_data: dict) -> dict[str, Permutation]:
    """Build sym_id -> Permutation dict from level data."""
    automorphisms = level_data["symmetries"]["automorphisms"]
    return {a["id"]: Permutation(a["mapping"]) for a in automorphisms}


def _get_subgroup_by_name(level_data: dict, name: str) -> dict | None:
    """Find a subgroup definition by name."""
    for sg in level_data.get("subgroups", []):
        if sg["name"] == name:
            return sg
    return None


# =============================================================
# Tests: JSON structure validation
# =============================================================

class TestLevelJsonStructure(unittest.TestCase):
    """Validate that each Act 2 level JSON has required fields."""

    LEVELS = [13, 14, 15, 16]

    def _load(self, num):
        return _load_level(num)

    def test_all_levels_exist_and_parse(self):
        for lvl in self.LEVELS:
            data = self._load(lvl)
            self.assertIn("meta", data, f"Level {lvl} missing 'meta'")
            self.assertIn("graph", data, f"Level {lvl} missing 'graph'")
            self.assertIn("symmetries", data, f"Level {lvl} missing 'symmetries'")
            self.assertIn("subgroups", data, f"Level {lvl} missing 'subgroups'")
            self.assertIn("mechanics", data, f"Level {lvl} missing 'mechanics'")

    def test_meta_fields(self):
        for lvl in self.LEVELS:
            data = self._load(lvl)
            meta = data["meta"]
            self.assertIn("id", meta)
            self.assertEqual(meta["act"], 2, f"Level {lvl} should be act 2")
            self.assertIn("group_name", meta)
            self.assertIn("group_order", meta)
            self.assertGreater(meta["group_order"], 0)

    def test_inner_doors_defined(self):
        for lvl in self.LEVELS:
            data = self._load(lvl)
            mechanics = data.get("mechanics", {})
            inner_doors = mechanics.get("inner_doors", [])
            self.assertGreater(len(inner_doors), 0,
                               f"Level {lvl} should have inner_doors")
            for door in inner_doors:
                self.assertIn("id", door, f"Door in level {lvl} missing 'id'")
                self.assertIn("required_subgroup", door,
                              f"Door {door.get('id', '?')} missing 'required_subgroup'")

    def test_inner_door_references_valid_subgroup(self):
        """Each door's required_subgroup must exist in subgroups list."""
        for lvl in self.LEVELS:
            data = self._load(lvl)
            mechanics = data.get("mechanics", {})
            inner_doors = mechanics.get("inner_doors", [])
            subgroup_names = [sg["name"] for sg in data.get("subgroups", [])]
            for door in inner_doors:
                req_sg = door["required_subgroup"]
                self.assertIn(req_sg, subgroup_names,
                              f"Level {lvl}, door '{door['id']}': required_subgroup "
                              f"'{req_sg}' not found in subgroups list {subgroup_names}")

    def test_automorphisms_count_matches_group_order(self):
        for lvl in self.LEVELS:
            data = self._load(lvl)
            group_order = data["meta"]["group_order"]
            auts = data["symmetries"]["automorphisms"]
            self.assertEqual(len(auts), group_order,
                             f"Level {lvl}: {len(auts)} automorphisms but group_order={group_order}")


# =============================================================
# Tests: Automorphism mathematical validity
# =============================================================

class TestAutomorphismValidity(unittest.TestCase):
    """Validate that all automorphisms are valid permutations and form a group."""

    LEVELS = [13, 14, 15, 16]

    def test_all_valid_permutations(self):
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            n = len(data["graph"]["nodes"])
            for sym_id, perm in perm_map.items():
                self.assertEqual(perm.size(), n,
                                 f"Level {lvl}, {sym_id}: wrong size {perm.size()} vs {n}")
                self.assertEqual(sorted(perm.mapping), list(range(n)),
                                 f"Level {lvl}, {sym_id}: invalid permutation {perm.mapping}")

    def test_identity_exists(self):
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            has_identity = any(p.is_identity() for p in perm_map.values())
            self.assertTrue(has_identity, f"Level {lvl}: no identity permutation")

    def test_closure_under_composition(self):
        """All pairwise compositions should produce elements within the group."""
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            perms = list(perm_map.values())
            for a in perms:
                for b in perms:
                    product = a.compose(b)
                    found = any(p.equals(product) for p in perms)
                    self.assertTrue(found,
                                    f"Level {lvl}: composition not closed: "
                                    f"{a.mapping} ∘ {b.mapping} = {product.mapping} not in group")

    def test_inverses_exist(self):
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            perms = list(perm_map.values())
            for p in perms:
                inv = p.inverse()
                found = any(q.equals(inv) for q in perms)
                self.assertTrue(found,
                                f"Level {lvl}: inverse of {p.mapping} = {inv.mapping} not in group")


# =============================================================
# Tests: Subgroup validity
# =============================================================

class TestSubgroupValidity(unittest.TestCase):
    """Validate that each subgroup definition is a genuine subgroup."""

    LEVELS = [13, 14, 15, 16]

    def test_subgroup_elements_exist_in_group(self):
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            for sg in data.get("subgroups", []):
                for elem_id in sg["elements"]:
                    self.assertIn(elem_id, perm_map,
                                  f"Level {lvl}, subgroup '{sg['name']}': "
                                  f"element '{elem_id}' not in automorphisms")

    def test_subgroup_has_identity(self):
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            for sg in data.get("subgroups", []):
                elements = [perm_map[e] for e in sg["elements"]]
                has_id = any(p.is_identity() for p in elements)
                self.assertTrue(has_id,
                                f"Level {lvl}, subgroup '{sg['name']}': no identity element")

    def test_subgroup_closed_under_composition(self):
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            for sg in data.get("subgroups", []):
                elements = [perm_map[e] for e in sg["elements"]]
                for a in elements:
                    for b in elements:
                        product = a.compose(b)
                        found = any(e.equals(product) for e in elements)
                        self.assertTrue(found,
                                        f"Level {lvl}, subgroup '{sg['name']}': "
                                        f"not closed: {a.mapping}∘{b.mapping}={product.mapping}")

    def test_subgroup_closed_under_inverse(self):
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            for sg in data.get("subgroups", []):
                elements = [perm_map[e] for e in sg["elements"]]
                for a in elements:
                    inv = a.inverse()
                    found = any(e.equals(inv) for e in elements)
                    self.assertTrue(found,
                                    f"Level {lvl}, subgroup '{sg['name']}': "
                                    f"missing inverse of {a.mapping}")

    def test_subgroup_order_matches_elements(self):
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            for sg in data.get("subgroups", []):
                self.assertEqual(sg["order"], len(sg["elements"]),
                                 f"Level {lvl}, subgroup '{sg['name']}': "
                                 f"order {sg['order']} != len(elements) {len(sg['elements'])}")

    def test_subgroup_order_divides_group_order(self):
        """Lagrange's theorem: |H| divides |G|."""
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            group_order = data["meta"]["group_order"]
            for sg in data.get("subgroups", []):
                self.assertEqual(group_order % sg["order"], 0,
                                 f"Level {lvl}, subgroup '{sg['name']}': "
                                 f"order {sg['order']} does not divide group order {group_order}")


# =============================================================
# Tests: Inner door subgroup matching logic
# =============================================================

class TestInnerDoorMatching(unittest.TestCase):
    """Test the matching logic: does a set of selected keys match the target subgroup?"""

    def _matches_target_subgroup(self, key_ring: KeyRing, selected_indices: list[int],
                                 target_sg: dict, perm_map: dict,
                                 rebase_inverse: Permutation | None) -> bool:
        """Python mirror of InnerDoorPanel._matches_target_subgroup()."""
        target_element_ids = target_sg["elements"]
        if len(selected_indices) != len(target_element_ids):
            return False

        # Build rebased selected permutations
        selected_rebased = []
        for idx in selected_indices:
            if 0 <= idx < key_ring.count():
                perm = key_ring.get_key(idx)
                rebased = perm
                if rebase_inverse is not None:
                    rebased = perm.compose(rebase_inverse)
                selected_rebased.append(rebased)

        # Check each target element matches a selected one
        for elem_id in target_element_ids:
            target_p = perm_map.get(elem_id)
            if target_p is None:
                return False
            if not any(sel_p.equals(target_p) for sel_p in selected_rebased):
                return False
        return True

    def test_level13_rotation_door(self):
        """Level 13: selecting e, r1, r2 should match Z3_rotations door."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)

        # Simulate finding all 6 keys (no rebase for simplicity, identity found first)
        kr = KeyRing()
        order = ["e", "r1", "r2", "s01", "s02", "s12"]
        for sym_id in order:
            kr.add_key(perm_map[sym_id])

        target_sg = _get_subgroup_by_name(data, "Z3_rotations")
        self.assertIsNotNone(target_sg)

        # Select indices 0, 1, 2 (e, r1, r2) — no rebase needed (identity is first)
        matched = self._matches_target_subgroup(kr, [0, 1, 2], target_sg, perm_map, None)
        self.assertTrue(matched, "Z3_rotations should match [e, r1, r2]")

    def test_level13_wrong_subset(self):
        """Level 13: selecting e, r1, s01 should NOT match Z3_rotations door."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)

        kr = KeyRing()
        order = ["e", "r1", "r2", "s01", "s02", "s12"]
        for sym_id in order:
            kr.add_key(perm_map[sym_id])

        target_sg = _get_subgroup_by_name(data, "Z3_rotations")
        # Select indices 0, 1, 3 (e, r1, s01) — wrong subset
        matched = self._matches_target_subgroup(kr, [0, 1, 3], target_sg, perm_map, None)
        self.assertFalse(matched, "[e, r1, s01] should not match Z3_rotations")

    def test_level13_subset_is_subgroup(self):
        """Check that {e, r1, r2} is a valid subgroup using KeyRing.check_subgroup()."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)

        kr = KeyRing()
        for sym_id in ["e", "r1", "r2", "s01", "s02", "s12"]:
            kr.add_key(perm_map[sym_id])

        result = kr.check_subgroup([0, 1, 2])  # e, r1, r2
        self.assertTrue(result["is_subgroup"], "Z3_rotations should be a subgroup")

    def test_level13_non_subgroup_detected(self):
        """Check that {e, r1, s01} is NOT a subgroup."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)

        kr = KeyRing()
        for sym_id in ["e", "r1", "r2", "s01", "s02", "s12"]:
            kr.add_key(perm_map[sym_id])

        result = kr.check_subgroup([0, 1, 3])  # e, r1, s01
        self.assertFalse(result["is_subgroup"])

    def test_level13_with_rebase(self):
        """Level 13: if first found key is r1 (not identity), rebase should work."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)

        # Simulate player finding r1 first, then others
        kr = KeyRing()
        discovery_order = ["r1", "e", "r2", "s01", "s02", "s12"]
        for sym_id in discovery_order:
            kr.add_key(perm_map[sym_id])

        # First key is r1, so rebase_inverse = r1.inverse() = r2
        rebase_inverse = perm_map["r1"].inverse()
        self.assertTrue(rebase_inverse.equals(perm_map["r2"]))

        target_sg = _get_subgroup_by_name(data, "Z3_rotations")
        # Select keys at indices 0,1,2 → r1, e, r2 — the same rotation set
        matched = self._matches_target_subgroup(kr, [0, 1, 2], target_sg, perm_map, rebase_inverse)
        self.assertTrue(matched, "With rebase, [r1, e, r2] should match Z3_rotations")


class TestLevel14InnerDoors(unittest.TestCase):
    """Level 14: D4 with 3 inner doors (Z2_180, Z4_rotations, V4_klein)."""

    def test_level14_has_3_doors(self):
        data = _load_level(14)
        inner_doors = data["mechanics"]["inner_doors"]
        self.assertEqual(len(inner_doors), 3, "Level 14 should have 3 inner doors")

    def test_level14_all_door_subgroups_valid(self):
        """All 7 door subgroups should be genuine subgroups."""
        data = _load_level(14)
        perm_map = _build_perm_map(data)
        inner_doors = data["mechanics"]["inner_doors"]

        for door in inner_doors:
            sg = _get_subgroup_by_name(data, door["required_subgroup"])
            self.assertIsNotNone(sg, f"Door '{door['id']}' references unknown subgroup")
            elements = [perm_map[e] for e in sg["elements"]]

            # Check identity
            self.assertTrue(any(p.is_identity() for p in elements),
                            f"Door '{door['id']}' subgroup '{sg['name']}' missing identity")

            # Check closure
            for a in elements:
                for b in elements:
                    product = a.compose(b)
                    self.assertTrue(any(e.equals(product) for e in elements),
                                    f"Door '{door['id']}' subgroup not closed")

            # Check inverses
            for a in elements:
                inv = a.inverse()
                self.assertTrue(any(e.equals(inv) for e in elements),
                                f"Door '{door['id']}' subgroup missing inverse")


class TestLevel15InnerDoors(unittest.TestCase):
    """Level 15: Z2×Z3 with 2 inner doors."""

    def test_level15_has_2_doors(self):
        data = _load_level(15)
        inner_doors = data["mechanics"]["inner_doors"]
        self.assertEqual(len(inner_doors), 2, "Level 15 should have 2 inner doors")

    def test_level15_z3_subgroup_valid(self):
        data = _load_level(15)
        perm_map = _build_perm_map(data)
        sg = _get_subgroup_by_name(data, "Z3_rotations")
        self.assertIsNotNone(sg)
        self.assertEqual(sg["order"], 3)
        elements = [perm_map[e] for e in sg["elements"]]

        # Full subgroup check
        self.assertTrue(any(p.is_identity() for p in elements))
        for a in elements:
            for b in elements:
                product = a.compose(b)
                self.assertTrue(any(e.equals(product) for e in elements))
        for a in elements:
            inv = a.inverse()
            self.assertTrue(any(e.equals(inv) for e in elements))

    def test_level15_z2_subgroup_valid(self):
        data = _load_level(15)
        perm_map = _build_perm_map(data)
        sg = _get_subgroup_by_name(data, "Z2_swap")
        self.assertIsNotNone(sg)
        self.assertEqual(sg["order"], 2)
        elements = [perm_map[e] for e in sg["elements"]]

        # Full subgroup check
        self.assertTrue(any(p.is_identity() for p in elements))
        for a in elements:
            for b in elements:
                product = a.compose(b)
                self.assertTrue(any(e.equals(product) for e in elements))


class TestLevel16InnerDoors(unittest.TestCase):
    """Level 16: D4 variant with 3 inner doors."""

    def test_level16_has_3_doors(self):
        data = _load_level(16)
        inner_doors = data["mechanics"]["inner_doors"]
        self.assertEqual(len(inner_doors), 3, "Level 16 should have 3 inner doors")

    def test_level16_all_door_subgroups_valid(self):
        data = _load_level(16)
        perm_map = _build_perm_map(data)
        inner_doors = data["mechanics"]["inner_doors"]

        for door in inner_doors:
            sg = _get_subgroup_by_name(data, door["required_subgroup"])
            self.assertIsNotNone(sg, f"Door '{door['id']}' references unknown subgroup")
            elements = [perm_map[e] for e in sg["elements"]]

            # Check identity
            self.assertTrue(any(p.is_identity() for p in elements),
                            f"Door '{door['id']}' subgroup missing identity")

            # Check closure
            for a in elements:
                for b in elements:
                    product = a.compose(b)
                    self.assertTrue(any(e.equals(product) for e in elements),
                                    f"Door '{door['id']}' subgroup not closed under composition")

            # Check inverses
            for a in elements:
                inv = a.inverse()
                self.assertTrue(any(e.equals(inv) for e in elements),
                                f"Door '{door['id']}' subgroup missing inverse")


# =============================================================
# Tests: Cayley table consistency
# =============================================================

class TestCayleyTableConsistency(unittest.TestCase):
    """Verify Cayley tables match composition of automorphisms."""

    LEVELS = [13, 14, 15, 16]

    def test_cayley_table_references_valid_elements(self):
        """Verify all Cayley table entries reference valid automorphism IDs."""
        for lvl in self.LEVELS:
            data = _load_level(lvl)
            perm_map = _build_perm_map(data)
            cayley = data["symmetries"].get("cayley_table", {})
            if not cayley:
                continue
            valid_ids = set(perm_map.keys())
            for row_id, row in cayley.items():
                self.assertIn(row_id, valid_ids,
                              f"Level {lvl}: Cayley row '{row_id}' not a valid element")
                for col_id, result_id in row.items():
                    self.assertIn(col_id, valid_ids,
                                  f"Level {lvl}: Cayley col '{col_id}' not a valid element")
                    self.assertIn(result_id, valid_ids,
                                  f"Level {lvl}: Cayley result '{result_id}' not a valid element")

    def test_cayley_table_level13_correct(self):
        """Verify level 13 Cayley table entries match computed composition.
        Level 13 (S3) Cayley table uses math convention: table[a][b] = a∘b
        where (a∘b)(x) = a(b(x)) → b.compose(a) in our code."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)
        cayley = data["symmetries"].get("cayley_table", {})
        self.assertTrue(len(cayley) > 0)
        errors = []
        for row_id, row in cayley.items():
            for col_id, result_id in row.items():
                a = perm_map[row_id]
                b = perm_map[col_id]
                expected = perm_map[result_id]
                # Math convention: table[a][b] = a*b = b.compose(a)
                actual = b.compose(a)
                if not actual.equals(expected):
                    errors.append(f"Cayley[{row_id}][{col_id}]={result_id}: "
                                  f"expected {expected.mapping}, got {actual.mapping}")
        self.assertEqual(len(errors), 0, "Level 13 Cayley errors:\n" + "\n".join(errors))


# =============================================================
# Tests: InnerDoorPanel state machine
# =============================================================

class TestInnerDoorPanelState(unittest.TestCase):
    """Test InnerDoorPanel state tracking (Python mirror)."""

    def test_initial_state_all_locked(self):
        """All doors start locked."""
        data = _load_level(13)
        doors = data["mechanics"]["inner_doors"]
        door_states = {d["id"]: "locked" for d in doors}
        self.assertEqual(door_states["rotation_door"], "locked")

    def test_door_opens_on_correct_subgroup(self):
        """Simulate: select correct subgroup → door opens."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)
        doors = data["mechanics"]["inner_doors"]
        door_states = {d["id"]: "locked" for d in doors}

        # Simulate finding all keys
        kr = KeyRing()
        for sym_id in ["e", "r1", "r2", "s01", "s02", "s12"]:
            kr.add_key(perm_map[sym_id])

        # Select e, r1, r2 (indices 0,1,2) and check subgroup
        result = kr.check_subgroup([0, 1, 2])
        self.assertTrue(result["is_subgroup"])

        # Simulate door opening
        door_states["rotation_door"] = "opened"
        self.assertEqual(door_states["rotation_door"], "opened")

    def test_all_doors_opened_check(self):
        data = _load_level(13)
        doors = data["mechanics"]["inner_doors"]
        door_states = {d["id"]: "opened" for d in doors}
        all_opened = all(s == "opened" for s in door_states.values())
        self.assertTrue(all_opened)

    def test_partial_doors_not_complete(self):
        """Level 14 with 7 doors: opening some is not complete."""
        data = _load_level(14)
        doors = data["mechanics"]["inner_doors"]
        door_states = {d["id"]: "locked" for d in doors}
        # Open only first door
        first_id = doors[0]["id"]
        door_states[first_id] = "opened"
        all_opened = all(s == "opened" for s in door_states.values())
        self.assertFalse(all_opened)


# =============================================================
# Tests: Level completion with inner doors
# =============================================================

class TestLevelCompletion(unittest.TestCase):
    """Test that level completion requires both all keys + all doors."""

    def _is_level_complete(self, key_ring: KeyRing, target_count: int,
                           door_states: dict | None) -> bool:
        """Python mirror of LevelScene._is_level_complete()."""
        if key_ring.count() < target_count:
            return False
        if door_states is not None:
            return all(s == "opened" for s in door_states.values())
        return True

    def test_keys_only_not_complete_with_doors(self):
        """All keys found but doors not opened → not complete."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)
        kr = KeyRing()
        for sym_id in ["e", "r1", "r2", "s01", "s02", "s12"]:
            kr.add_key(perm_map[sym_id])

        door_states = {"rotation_door": "locked"}
        self.assertFalse(self._is_level_complete(kr, 6, door_states))

    def test_keys_and_doors_complete(self):
        """All keys found + all doors opened → complete."""
        data = _load_level(13)
        perm_map = _build_perm_map(data)
        kr = KeyRing()
        for sym_id in ["e", "r1", "r2", "s01", "s02", "s12"]:
            kr.add_key(perm_map[sym_id])

        door_states = {"rotation_door": "opened"}
        self.assertTrue(self._is_level_complete(kr, 6, door_states))

    def test_act1_no_doors_complete_with_keys_only(self):
        """Act 1 (no inner doors): all keys found → complete."""
        kr = KeyRing()
        kr.add_key(Permutation.create_identity(3))
        kr.add_key(Permutation([1, 0, 2]))
        self.assertTrue(self._is_level_complete(kr, 2, None))

    def test_doors_opened_but_keys_missing(self):
        """Doors opened but not all keys → not complete."""
        kr = KeyRing()
        kr.add_key(Permutation.create_identity(3))  # Only 1 key
        door_states = {"rotation_door": "opened"}
        self.assertFalse(self._is_level_complete(kr, 6, door_states))


if __name__ == "__main__":
    unittest.main()
