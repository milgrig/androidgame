"""
Unit tests for RoomState — the room-map data model.
Python mirror of GDScript logic for executable verification.

Verifies:
- Cayley table for Z3 (3 elements) is correct
- Cayley table for D4 (8 elements) matches level_05.json
- apply_key from Home(0) with key k leads to room k
- apply_key(a, b) then apply_key(result, c) = apply_key(a, compose(b,c))
- Color generation produces correct count and gold for room 0
- Room discovery tracking
"""
import json
import os
import unittest
import math


# === Python mirror of Permutation (minimal) ===

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

    @staticmethod
    def create_identity(n: int) -> "Permutation":
        return Permutation(list(range(n)))

    @staticmethod
    def from_array(arr: list) -> "Permutation":
        return Permutation([int(v) for v in arr])

    def __repr__(self):
        return f"Perm({self.mapping})"


# === Python mirror of RoomState (matches room_state.gd logic) ===

class RoomState:
    def __init__(self):
        self.group_order = 0
        self.all_perms = []      # list[Permutation]
        self.perm_names = []     # list[str]
        self.perm_ids = []       # list[str]
        self.cayley_table = []   # list[list[int]]
        self.discovered = []     # list[bool]
        self.current_room = 0
        self.colors = []         # list[tuple(r,g,b)]
        self.transition_history = []

    def setup(self, level_data: dict, rebase_inverse: Permutation = None):
        sym_data = level_data.get("symmetries", {})
        autos = sym_data.get("automorphisms", [])
        if not autos:
            return

        raw_perms = []
        raw_names = []
        raw_ids = []

        for auto in autos:
            mapping = auto.get("mapping", [])
            perm = Permutation.from_array(mapping)
            if rebase_inverse is not None:
                perm = perm.compose(rebase_inverse)
            raw_perms.append(perm)
            raw_names.append(auto.get("name", ""))
            raw_ids.append(auto.get("id", ""))

        # Find identity and move to index 0
        identity_idx = -1
        for i, p in enumerate(raw_perms):
            if p.is_identity():
                identity_idx = i
                break
        if identity_idx == -1:
            identity_idx = 0

        self.all_perms = [raw_perms[identity_idx]]
        self.perm_names = [raw_names[identity_idx]]
        self.perm_ids = [raw_ids[identity_idx]]

        for i in range(len(raw_perms)):
            if i != identity_idx:
                self.all_perms.append(raw_perms[i])
                self.perm_names.append(raw_names[i])
                self.perm_ids.append(raw_ids[i])

        self.group_order = len(self.all_perms)
        self._build_cayley_table()

        self.discovered = [False] * self.group_order
        self.discovered[0] = True
        self.current_room = 0
        self.colors = self.generate_colors(self.group_order)
        self.transition_history = []

    def _build_cayley_table(self):
        # Math convention: cayley[a][b] = a*b where (a*b)(x) = a(b(x))
        # Since Permutation.compose does "self then other",
        # we compute b.compose(a) to get a*b in math convention.
        self.cayley_table = []
        for a in range(self.group_order):
            row = []
            for b in range(self.group_order):
                product = self.all_perms[b].compose(self.all_perms[a])
                idx = self._find_perm_index(product)
                assert idx != -1, f"Cayley table product not found: [{a}][{b}]"
                row.append(idx)
            self.cayley_table.append(row)

    def _find_perm_index(self, perm: Permutation) -> int:
        for i, p in enumerate(self.all_perms):
            if p.equals(perm):
                return i
        return -1

    def discover_room(self, idx: int) -> bool:
        if idx < 0 or idx >= self.group_order:
            return False
        if self.discovered[idx]:
            return False
        self.discovered[idx] = True
        return True

    def apply_key(self, key_idx: int) -> int:
        if key_idx < 0 or key_idx >= self.group_order:
            return self.current_room
        dest = self.cayley_table[self.current_room][key_idx]
        self.transition_history.append({
            "from": self.current_room,
            "to": dest,
            "key": key_idx,
        })
        self.current_room = dest
        return dest

    def get_destination(self, from_room: int, key_idx: int) -> int:
        if from_room < 0 or from_room >= self.group_order:
            return 0
        if key_idx < 0 or key_idx >= self.group_order:
            return from_room
        return self.cayley_table[from_room][key_idx]

    def find_room_for_perm(self, perm: Permutation, rebase_inverse: Permutation = None) -> int:
        check = perm
        if rebase_inverse is not None:
            check = perm.compose(rebase_inverse)
        return self._find_perm_index(check)

    @staticmethod
    def generate_colors(n: int) -> list:
        colors = []
        if n <= 0:
            return colors
        # Room 0: gold
        colors.append((0.788, 0.659, 0.298))
        for i in range(1, n):
            hue = ((i * 360.0 / (n - 1)) + 200.0) % 360.0 / 360.0
            sat = (50.0 + (i % 3) * 10.0) / 100.0
            lit = (45.0 + (i % 2) * 10.0) / 100.0
            r, g, b = RoomState._hsl_to_rgb(hue, sat, lit)
            colors.append((r, g, b))
        return colors

    @staticmethod
    def _hsl_to_rgb(h, s, l):
        a = s * min(l, 1.0 - l)
        def f(n_val):
            k = (n_val + h * 12.0) % 12.0
            return l - a * max(min(min(k - 3.0, 9.0 - k), 1.0), -1.0)
        return (f(0.0), f(8.0), f(4.0))


# === Helper: load level JSON ===

def load_level(filename: str) -> dict:
    base = os.path.dirname(os.path.abspath(__file__))
    level_path = os.path.join(base, "..", "..", "..", "data", "levels", filename)
    level_path = os.path.normpath(level_path)
    with open(level_path, "r", encoding="utf-8") as f:
        return json.load(f)


# === Tests ===

class TestRoomStateCayleyZ3(unittest.TestCase):
    """Verify Cayley table for Z3 (level 13, 3 rotations as subgroup)."""

    def setUp(self):
        # Manually construct Z3 = {e, r1, r2} with cycle (0,1,2)
        self.level_data = {
            "symmetries": {
                "automorphisms": [
                    {"id": "e",  "mapping": [0, 1, 2], "name": "Identity"},
                    {"id": "r1", "mapping": [1, 2, 0], "name": "Rotation 120"},
                    {"id": "r2", "mapping": [2, 0, 1], "name": "Rotation 240"},
                ]
            }
        }
        self.rs = RoomState()
        self.rs.setup(self.level_data)

    def test_group_order(self):
        self.assertEqual(self.rs.group_order, 3)

    def test_identity_at_zero(self):
        self.assertTrue(self.rs.all_perms[0].is_identity())
        self.assertEqual(self.rs.perm_ids[0], "e")

    def test_cayley_table_size(self):
        self.assertEqual(len(self.rs.cayley_table), 3)
        for row in self.rs.cayley_table:
            self.assertEqual(len(row), 3)

    def test_cayley_identity_row(self):
        """e * x = x for all x."""
        for j in range(3):
            self.assertEqual(self.rs.cayley_table[0][j], j)

    def test_cayley_identity_column(self):
        """x * e = x for all x."""
        for i in range(3):
            self.assertEqual(self.rs.cayley_table[i][0], i)

    def test_cayley_r1_r1_eq_r2(self):
        """r1 * r1 = r2."""
        # r1 is at index 1, r2 at index 2
        r1_idx = self.rs._find_perm_index(Permutation([1, 2, 0]))
        r2_idx = self.rs._find_perm_index(Permutation([2, 0, 1]))
        self.assertEqual(self.rs.cayley_table[r1_idx][r1_idx], r2_idx)

    def test_cayley_r1_r2_eq_e(self):
        """r1 * r2 = e."""
        r1_idx = self.rs._find_perm_index(Permutation([1, 2, 0]))
        r2_idx = self.rs._find_perm_index(Permutation([2, 0, 1]))
        self.assertEqual(self.rs.cayley_table[r1_idx][r2_idx], 0)

    def test_cayley_r2_r2_eq_r1(self):
        """r2 * r2 = r1."""
        r1_idx = self.rs._find_perm_index(Permutation([1, 2, 0]))
        r2_idx = self.rs._find_perm_index(Permutation([2, 0, 1]))
        self.assertEqual(self.rs.cayley_table[r2_idx][r2_idx], r1_idx)

    def test_cayley_associativity(self):
        """(a * b) * c = a * (b * c) for all a, b, c."""
        n = self.rs.group_order
        for a in range(n):
            for b in range(n):
                for c in range(n):
                    ab = self.rs.cayley_table[a][b]
                    ab_c = self.rs.cayley_table[ab][c]
                    bc = self.rs.cayley_table[b][c]
                    a_bc = self.rs.cayley_table[a][bc]
                    self.assertEqual(ab_c, a_bc,
                        f"Associativity failed: ({a}*{b})*{c} = {ab_c} != {a}*({b}*{c}) = {a_bc}")


class TestRoomStateCayleyD4(unittest.TestCase):
    """Verify Cayley table for D4 (8 elements) matches level_05.json."""

    def setUp(self):
        self.level_data = load_level("act1/level_05.json")
        self.rs = RoomState()
        self.rs.setup(self.level_data)

    def test_group_order(self):
        self.assertEqual(self.rs.group_order, 8)

    def test_identity_at_zero(self):
        self.assertTrue(self.rs.all_perms[0].is_identity())

    def test_cayley_table_size(self):
        self.assertEqual(len(self.rs.cayley_table), 8)
        for row in self.rs.cayley_table:
            self.assertEqual(len(row), 8)

    def test_cayley_matches_json(self):
        """Cayley table computed by RoomState matches the one in level JSON."""
        json_cayley = self.level_data["symmetries"]["cayley_table"]

        # Build sym_id -> room_index mapping
        id_to_room = {}
        for i, sid in enumerate(self.rs.perm_ids):
            id_to_room[sid] = i

        for a_id, row in json_cayley.items():
            a_idx = id_to_room[a_id]
            for b_id, result_id in row.items():
                b_idx = id_to_room[b_id]
                result_idx = id_to_room[result_id]
                computed = self.rs.cayley_table[a_idx][b_idx]
                self.assertEqual(computed, result_idx,
                    f"Cayley mismatch: {a_id}*{b_id} = {result_id} (room {result_idx}) "
                    f"but computed room {computed} ({self.rs.perm_ids[computed]})")

    def test_cayley_associativity(self):
        """(a * b) * c = a * (b * c) for all a, b, c."""
        n = self.rs.group_order
        for a in range(n):
            for b in range(n):
                for c in range(n):
                    ab = self.rs.cayley_table[a][b]
                    ab_c = self.rs.cayley_table[ab][c]
                    bc = self.rs.cayley_table[b][c]
                    a_bc = self.rs.cayley_table[a][bc]
                    self.assertEqual(ab_c, a_bc,
                        f"Associativity failed: ({a}*{b})*{c} = {ab_c} != {a}*({b}*{c}) = {a_bc}")

    def test_inverses_exist(self):
        """Every element has an inverse in the group."""
        n = self.rs.group_order
        for a in range(n):
            found_inverse = False
            for b in range(n):
                if self.rs.cayley_table[a][b] == 0:  # a * b = e
                    # Also check b * a = e
                    self.assertEqual(self.rs.cayley_table[b][a], 0,
                        f"Element {a} has right-inverse {b} but it's not left-inverse")
                    found_inverse = True
                    break
            self.assertTrue(found_inverse, f"Element {a} has no inverse")


class TestRoomStateApplyKey(unittest.TestCase):
    """Verify apply_key navigation properties."""

    def setUp(self):
        # Use Z3 for simplicity
        self.level_data = {
            "symmetries": {
                "automorphisms": [
                    {"id": "e",  "mapping": [0, 1, 2], "name": "Identity"},
                    {"id": "r1", "mapping": [1, 2, 0], "name": "Rotation 120"},
                    {"id": "r2", "mapping": [2, 0, 1], "name": "Rotation 240"},
                ]
            }
        }
        self.rs = RoomState()
        self.rs.setup(self.level_data)

    def test_apply_from_home_leads_to_key_room(self):
        """apply_key from Home(0) with key k leads to room k."""
        for k in range(self.rs.group_order):
            rs = RoomState()
            rs.setup(self.level_data)
            dest = rs.apply_key(k)
            self.assertEqual(dest, k,
                f"apply_key(0, {k}) should go to room {k}, got {dest}")

    def test_apply_key_sequential_associativity(self):
        """apply_key(a, b) then apply_key(result, c) = apply_key(a, compose(b,c)).

        In Cayley table terms: table[table[a][b]][c] = table[a][table[b][c]]
        This is associativity, which we check exhaustively.
        """
        n = self.rs.group_order
        for a in range(n):
            for b in range(n):
                for c in range(n):
                    # Sequential: a -> apply b -> apply c
                    step1 = self.rs.get_destination(a, b)
                    step2 = self.rs.get_destination(step1, c)
                    # Composed: compose(b, c) then apply from a
                    bc = self.rs.cayley_table[b][c]
                    direct = self.rs.get_destination(a, bc)
                    self.assertEqual(step2, direct,
                        f"Sequential ({a}->key{b}->key{c})={step2} != "
                        f"composed ({a}->key[{b}*{c}={bc}])={direct}")

    def test_apply_key_updates_current_room(self):
        """apply_key updates current_room correctly."""
        self.assertEqual(self.rs.current_room, 0)
        r1_idx = self.rs._find_perm_index(Permutation([1, 2, 0]))
        dest = self.rs.apply_key(r1_idx)
        self.assertEqual(self.rs.current_room, dest)
        self.assertEqual(dest, r1_idx)

    def test_apply_key_records_history(self):
        """apply_key records transition in history."""
        self.assertEqual(len(self.rs.transition_history), 0)
        self.rs.apply_key(1)
        self.assertEqual(len(self.rs.transition_history), 1)
        self.assertEqual(self.rs.transition_history[0]["from"], 0)
        self.assertEqual(self.rs.transition_history[0]["to"], 1)
        self.assertEqual(self.rs.transition_history[0]["key"], 1)


class TestRoomStateDiscovery(unittest.TestCase):
    """Verify room discovery tracking."""

    def setUp(self):
        self.level_data = {
            "symmetries": {
                "automorphisms": [
                    {"id": "e",  "mapping": [0, 1, 2], "name": "Identity"},
                    {"id": "r1", "mapping": [1, 2, 0], "name": "Rotation 120"},
                    {"id": "r2", "mapping": [2, 0, 1], "name": "Rotation 240"},
                ]
            }
        }
        self.rs = RoomState()
        self.rs.setup(self.level_data)

    def test_home_discovered_by_default(self):
        self.assertTrue(self.rs.discovered[0])

    def test_other_rooms_not_discovered(self):
        for i in range(1, self.rs.group_order):
            self.assertFalse(self.rs.discovered[i])

    def test_discover_new_room(self):
        result = self.rs.discover_room(1)
        self.assertTrue(result)
        self.assertTrue(self.rs.discovered[1])

    def test_discover_already_discovered(self):
        self.rs.discover_room(1)
        result = self.rs.discover_room(1)
        self.assertFalse(result)  # Already discovered

    def test_discover_home_returns_false(self):
        result = self.rs.discover_room(0)
        self.assertFalse(result)  # Already discovered

    def test_discover_invalid_index(self):
        result = self.rs.discover_room(-1)
        self.assertFalse(result)
        result = self.rs.discover_room(999)
        self.assertFalse(result)


class TestRoomStateColors(unittest.TestCase):
    """Verify color generation."""

    def test_colors_count(self):
        colors = RoomState.generate_colors(6)
        self.assertEqual(len(colors), 6)

    def test_room_0_is_gold(self):
        colors = RoomState.generate_colors(6)
        r, g, b = colors[0]
        self.assertAlmostEqual(r, 0.788, places=2)
        self.assertAlmostEqual(g, 0.659, places=2)
        self.assertAlmostEqual(b, 0.298, places=2)

    def test_colors_unique(self):
        """All colors should be distinct."""
        colors = RoomState.generate_colors(8)
        for i in range(len(colors)):
            for j in range(i + 1, len(colors)):
                self.assertNotEqual(colors[i], colors[j],
                    f"Colors {i} and {j} are identical: {colors[i]}")

    def test_colors_in_valid_range(self):
        """All color components should be in [0, 1]."""
        colors = RoomState.generate_colors(24)
        for i, (r, g, b) in enumerate(colors):
            self.assertGreaterEqual(r, 0.0, f"Color {i} red < 0: {r}")
            self.assertLessEqual(r, 1.0, f"Color {i} red > 1: {r}")
            self.assertGreaterEqual(g, 0.0, f"Color {i} green < 0: {g}")
            self.assertLessEqual(g, 1.0, f"Color {i} green > 1: {g}")
            self.assertGreaterEqual(b, 0.0, f"Color {i} blue < 0: {b}")
            self.assertLessEqual(b, 1.0, f"Color {i} blue > 1: {b}")

    def test_single_room(self):
        """Edge case: only 1 room."""
        colors = RoomState.generate_colors(1)
        self.assertEqual(len(colors), 1)
        self.assertAlmostEqual(colors[0][0], 0.788, places=2)

    def test_empty(self):
        colors = RoomState.generate_colors(0)
        self.assertEqual(len(colors), 0)


class TestRoomStateFindRoom(unittest.TestCase):
    """Verify find_room_for_perm."""

    def setUp(self):
        self.level_data = {
            "symmetries": {
                "automorphisms": [
                    {"id": "e",  "mapping": [0, 1, 2], "name": "Identity"},
                    {"id": "r1", "mapping": [1, 2, 0], "name": "Rotation 120"},
                    {"id": "r2", "mapping": [2, 0, 1], "name": "Rotation 240"},
                ]
            }
        }
        self.rs = RoomState()
        self.rs.setup(self.level_data)

    def test_find_identity(self):
        perm = Permutation([0, 1, 2])
        self.assertEqual(self.rs.find_room_for_perm(perm), 0)

    def test_find_r1(self):
        perm = Permutation([1, 2, 0])
        idx = self.rs.find_room_for_perm(perm)
        self.assertGreater(idx, 0)
        self.assertTrue(self.rs.all_perms[idx].equals(perm))

    def test_find_nonexistent(self):
        perm = Permutation([1, 0, 2])  # Transposition, not in Z3 rotations
        self.assertEqual(self.rs.find_room_for_perm(perm), -1)

    def test_find_with_rebase(self):
        """find_room_for_perm with rebase_inverse should compose before lookup."""
        r1 = Permutation([1, 2, 0])
        r1_inv = r1.inverse()  # = r2 = [2, 0, 1]
        # If player's first key was r1, then rebase_inverse = r1^-1 = r2
        # A perm p in player's frame should match after p.compose(r2)
        # Identity in rebased frame = r1 in original frame
        # So find_room_for_perm(r1, r1_inv) should find identity (room 0)
        idx = self.rs.find_room_for_perm(r1, r1_inv)
        # r1.compose(r2) = [0,1,2] = identity
        self.assertEqual(idx, 0)


class TestRoomStateWithRebase(unittest.TestCase):
    """Test setup with rebase_inverse parameter."""

    def setUp(self):
        self.level_data = {
            "symmetries": {
                "automorphisms": [
                    {"id": "e",  "mapping": [0, 1, 2], "name": "Identity"},
                    {"id": "r1", "mapping": [1, 2, 0], "name": "Rotation 120"},
                    {"id": "r2", "mapping": [2, 0, 1], "name": "Rotation 240"},
                ]
            }
        }

    def test_rebase_identity(self):
        """Rebase with identity should not change anything."""
        rs = RoomState()
        rs.setup(self.level_data, Permutation([0, 1, 2]))
        self.assertEqual(rs.group_order, 3)
        self.assertTrue(rs.all_perms[0].is_identity())

    def test_rebase_by_r1(self):
        """Rebase by r1^-1: each perm p becomes p.compose(r1^-1).
        The identity in the original becomes r1.compose(r1^-1) = e, still identity.
        r1 becomes r1.compose(r1^-1) = e.
        Actually: rebase_inverse = r1^-1 = r2 = [2,0,1]
        p.compose(rebase_inverse) means: for each i, result[i] = rebase_inverse.apply(p.apply(i))

        e.compose(r2) = r2 (NOT identity)
        r1.compose(r2) = identity
        r2.compose(r2) = r1

        So after rebase by r1^-1, the elements are {r2, e, r1} and identity (e)
        moves to index 0.
        """
        r1 = Permutation([1, 2, 0])
        r1_inv = r1.inverse()
        rs = RoomState()
        rs.setup(self.level_data, r1_inv)

        self.assertEqual(rs.group_order, 3)
        self.assertTrue(rs.all_perms[0].is_identity())
        # Cayley table should still be valid
        for a in range(3):
            for b in range(3):
                for c in range(3):
                    ab = rs.cayley_table[a][b]
                    ab_c = rs.cayley_table[ab][c]
                    bc = rs.cayley_table[b][c]
                    a_bc = rs.cayley_table[a][bc]
                    self.assertEqual(ab_c, a_bc)


class TestRoomStateS3Full(unittest.TestCase):
    """Test with full S3 from level_13.json."""

    def setUp(self):
        self.level_data = load_level("act2/level_13.json")
        self.rs = RoomState()
        self.rs.setup(self.level_data)

    def test_group_order(self):
        self.assertEqual(self.rs.group_order, 6)

    def test_identity_at_zero(self):
        self.assertTrue(self.rs.all_perms[0].is_identity())

    def test_cayley_matches_json(self):
        """Cayley table matches JSON."""
        json_cayley = self.level_data["symmetries"]["cayley_table"]
        id_to_room = {sid: i for i, sid in enumerate(self.rs.perm_ids)}

        for a_id, row in json_cayley.items():
            a_idx = id_to_room[a_id]
            for b_id, result_id in row.items():
                b_idx = id_to_room[b_id]
                result_idx = id_to_room[result_id]
                computed = self.rs.cayley_table[a_idx][b_idx]
                self.assertEqual(computed, result_idx,
                    f"Cayley: {a_id}*{b_id}={result_id}(room {result_idx}) "
                    f"but got room {computed}({self.rs.perm_ids[computed]})")

    def test_associativity(self):
        n = self.rs.group_order
        for a in range(n):
            for b in range(n):
                for c in range(n):
                    ab_c = self.rs.cayley_table[self.rs.cayley_table[a][b]][c]
                    a_bc = self.rs.cayley_table[a][self.rs.cayley_table[b][c]]
                    self.assertEqual(ab_c, a_bc)


if __name__ == "__main__":
    unittest.main()
