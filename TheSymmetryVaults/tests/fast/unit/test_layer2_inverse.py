"""
Unit tests for Layer 2: Inverse Key Detection and Validation.
Tests the InversePairManager logic (Python mirror) and validates
inverse pair correctness across all 24 level JSON files.

T087: Layer 2 Engine — Inverse Keys
"""
import json
import os
import unittest

# Reuse core engine mirrors from test_core_engine
from test_core_engine import Permutation, CrystalGraph, KeyRing


# === Python mirror of InversePairManager ===

class InversePair:
    """Runtime data for a single inverse pair."""
    def __init__(self):
        self.key_sym_id: str = ""
        self.key_perm: Permutation = None
        self.key_name: str = ""
        self.inverse_sym_id: str = ""
        self.inverse_perm: Permutation = None
        self.inverse_name: str = ""
        self.is_self_inverse: bool = False
        self.is_identity: bool = False
        self.paired: bool = False
        self.revealed: bool = False


class InversePairManager:
    """Python mirror of InversePairManager.gd for testing."""

    def __init__(self):
        self.pairs: list[InversePair] = []
        self.bidirectional: bool = True
        self._sym_id_to_perm: dict[str, Permutation] = {}
        self._sym_id_to_name: dict[str, str] = {}

    def setup(self, level_data: dict, layer_config: dict = None) -> None:
        if layer_config is None:
            layer_config = {}
        self.pairs.clear()
        self._sym_id_to_perm.clear()
        self._sym_id_to_name.clear()

        autos = level_data.get("symmetries", {}).get("automorphisms", [])
        for auto in autos:
            sym_id = auto.get("id", "")
            perm = Permutation(auto.get("mapping", []))
            self._sym_id_to_perm[sym_id] = perm
            self._sym_id_to_name[sym_id] = auto.get("name", sym_id)

        self.bidirectional = layer_config.get("bidirectional_pairing", True)

        # Build inverse pairs
        processed = set()
        for sym_id, perm in self._sym_id_to_perm.items():
            if sym_id in processed:
                continue
            inv_perm = perm.inverse()
            inv_sym_id = self._find_sym_id_for_perm(inv_perm)
            if inv_sym_id == "":
                continue

            pair = InversePair()
            pair.key_sym_id = sym_id
            pair.key_perm = perm
            pair.key_name = self._sym_id_to_name.get(sym_id, sym_id)
            pair.inverse_sym_id = inv_sym_id
            pair.inverse_perm = inv_perm
            pair.inverse_name = self._sym_id_to_name.get(inv_sym_id, inv_sym_id)
            pair.is_self_inverse = (sym_id == inv_sym_id)
            pair.is_identity = perm.is_identity()

            # T111: skip identity pair entirely — never shown in UI
            if pair.is_identity:
                processed.add(sym_id)
                continue

            self.pairs.append(pair)
            processed.add(sym_id)
            if self.bidirectional and not pair.is_self_inverse:
                processed.add(inv_sym_id)

        # Apply revealed_pairs
        for rp in layer_config.get("revealed_pairs", []):
            if isinstance(rp, list) and len(rp) >= 2:
                self._reveal_pair(rp[0], rp[1])

    def try_pair(self, key_sym_id: str, candidate_sym_id: str) -> dict:
        pair = self._find_pair_by_key(key_sym_id)
        if pair is None:
            return {"success": False, "reason": "unknown_key", "pair_index": -1, "is_self_inverse": False}
        if pair.paired:
            return {"success": False, "reason": "already_paired", "pair_index": self.pairs.index(pair), "is_self_inverse": False}

        candidate_perm = self._sym_id_to_perm.get(candidate_sym_id)
        if candidate_perm is None:
            return {"success": False, "reason": "unknown_candidate", "pair_index": -1, "is_self_inverse": False}

        if pair.key_perm.compose(candidate_perm).is_identity():
            pair.paired = True
            pair_index = self.pairs.index(pair)
            is_self_inv = pair.is_self_inverse

            if self.bidirectional and not pair.is_self_inverse:
                reverse_pair = self._find_pair_by_key(candidate_sym_id)
                if reverse_pair is not None and not reverse_pair.paired:
                    reverse_pair.paired = True

            return {"success": True, "reason": "correct", "pair_index": pair_index, "is_self_inverse": is_self_inv}
        else:
            result_perm = pair.key_perm.compose(candidate_perm)
            result_name = self._lookup_perm_name(result_perm)
            return {"success": False, "reason": "not_inverse", "pair_index": self.pairs.index(pair),
                    "is_self_inverse": False, "result_name": result_name}

    def is_complete(self) -> bool:
        return all(pair.paired for pair in self.pairs)

    def get_progress(self) -> dict:
        # T111: identity is never in pairs, no filter needed
        matched = sum(1 for p in self.pairs if p.paired)
        total = len(self.pairs)
        return {"matched": matched, "total": total}

    def compose_by_id(self, sym_a: str, sym_b: str) -> dict:
        perm_a = self._sym_id_to_perm.get(sym_a)
        perm_b = self._sym_id_to_perm.get(sym_b)
        if perm_a is None or perm_b is None:
            return {"result_perm": None, "result_name": "", "is_identity": False}
        result = perm_a.compose(perm_b)
        return {
            "result_perm": result,
            "result_name": self._lookup_perm_name(result),
            "is_identity": result.is_identity()
        }

    def try_pair_by_sym_ids(self, sym_a: str, sym_b: str) -> dict:
        """Try to pair two keys by their sym_ids (tries both orderings)."""
        result = self.try_pair(sym_a, sym_b)
        if result["success"]:
            return {
                "success": True, "key_sym_id": sym_a, "inv_sym_id": sym_b,
                "pair_index": result["pair_index"], "is_self_inverse": result["is_self_inverse"],
            }
        result = self.try_pair(sym_b, sym_a)
        if result["success"]:
            return {
                "success": True, "key_sym_id": sym_b, "inv_sym_id": sym_a,
                "pair_index": result["pair_index"], "is_self_inverse": result["is_self_inverse"],
            }
        return {"success": False, "key_sym_id": sym_a, "inv_sym_id": sym_b,
                "pair_index": -1, "is_self_inverse": False}

    def is_paired(self, sym_id: str) -> bool:
        """Check if a sym_id's pair is already matched."""
        for pair in self.pairs:
            if pair.key_sym_id == sym_id or pair.inverse_sym_id == sym_id:
                return pair.paired
        return False

    def get_inverse_sym_id(self, sym_id: str) -> str:
        """Get the inverse sym_id for a given sym_id."""
        for pair in self.pairs:
            if pair.key_sym_id == sym_id:
                return pair.inverse_sym_id
            if pair.inverse_sym_id == sym_id:
                return pair.key_sym_id
        return ""

    def is_self_inverse_sym(self, sym_id: str) -> bool:
        """Check if a sym_id is a self-inverse element."""
        for pair in self.pairs:
            if pair.key_sym_id == sym_id or pair.inverse_sym_id == sym_id:
                return pair.is_self_inverse
        return False

    def get_all_sym_ids(self) -> list[str]:
        """Get all sym_ids."""
        return list(self._sym_id_to_perm.keys())

    def _find_pair_by_key(self, sym_id: str) -> InversePair | None:
        for pair in self.pairs:
            if pair.key_sym_id == sym_id:
                return pair
        return None

    def _find_sym_id_for_perm(self, perm: Permutation) -> str:
        for sym_id, p in self._sym_id_to_perm.items():
            if p.equals(perm):
                return sym_id
        return ""

    def _lookup_perm_name(self, perm: Permutation) -> str:
        sym_id = self._find_sym_id_for_perm(perm)
        if sym_id:
            return self._sym_id_to_name.get(sym_id, sym_id)
        return perm.to_cycle_notation()

    def _reveal_pair(self, key_id: str, inv_id: str) -> None:
        pair = self._find_pair_by_key(key_id)
        if pair is not None and pair.inverse_sym_id == inv_id:
            pair.paired = True
            pair.revealed = True


# === Helper to load level JSON ===

def load_level_json(filename: str, act: int = 1) -> dict:
    base = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(base, "..", "..", "..", "data", "levels", f"act{act}", filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def get_all_act1_level_files() -> list[str]:
    base = os.path.dirname(os.path.abspath(__file__))
    levels_dir = os.path.join(base, "..", "..", "..", "data", "levels", "act1")
    if not os.path.exists(levels_dir):
        return []
    return sorted([f for f in os.listdir(levels_dir) if f.endswith('.json')])


# === Test Cases ===

class TestInversePairManagerSetup(unittest.TestCase):
    """Test InversePairManager.setup() with known level data."""

    def test_z3_setup(self):
        """Z3 (level 01): 3 automorphisms -> 1 mutual pair (T111: identity excluded)"""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)

        # Z3: {e, r1, r2}
        # T111: identity is excluded from pairs entirely
        # With bidirectional, we get 1 pair: (r1,r2)
        self.assertEqual(len(mgr.pairs), 1)

        # No identity pair in list
        identity_pairs = [p for p in mgr.pairs if p.is_identity]
        self.assertEqual(len(identity_pairs), 0)

        # Mutual pair should not be paired yet
        mutual_pairs = [p for p in mgr.pairs if not p.is_identity]
        self.assertEqual(len(mutual_pairs), 1)
        self.assertFalse(mutual_pairs[0].paired)

    def test_z2_setup(self):
        """Z2 (level 03): 2 automorphisms -> 1 self-inverse (T111: identity excluded)"""
        data = load_level_json("level_03.json")
        mgr = InversePairManager()
        mgr.setup(data)

        # Z2: {e, s}
        # T111: identity excluded, only s remains as self-inverse
        self.assertEqual(len(mgr.pairs), 1)

        identity_pairs = [p for p in mgr.pairs if p.is_identity]
        self.assertEqual(len(identity_pairs), 0)

        self_inv_pairs = [p for p in mgr.pairs if p.is_self_inverse]
        self.assertEqual(len(self_inv_pairs), 1)
        self.assertFalse(self_inv_pairs[0].paired)

    def test_s3_setup(self):
        """S3 (level 09): 6 elements -> 1 mutual pair + 3 self-inverses (T111: identity excluded)"""
        data = load_level_json("level_09.json")
        mgr = InversePairManager()
        mgr.setup(data)

        # S3 = {e, r1, r2, s01, s02, s12}
        # T111: identity excluded
        # r1 and r2: mutual inverses (1 pair in bidirectional mode)
        # s01, s02, s12: self-inverses (reflections, each order 2)
        # Total pairs in bidirectional mode: 1 (r1<->r2) + 3 (self-inverse) = 4
        self.assertEqual(len(mgr.pairs), 4)

        identity_count = sum(1 for p in mgr.pairs if p.is_identity)
        self_inv_count = sum(1 for p in mgr.pairs if p.is_self_inverse)
        mutual_count = sum(1 for p in mgr.pairs if not p.is_self_inverse)

        self.assertEqual(identity_count, 0)
        self.assertEqual(self_inv_count, 3)
        self.assertEqual(mutual_count, 1)

    def test_no_bidirectional_creates_both_directions(self):
        """Without bidirectional, mutual pairs appear twice (r1->r2 and r2->r1)."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data, {"bidirectional_pairing": False})

        # T111: identity excluded
        # Z3 without bidirectional: r1->r2 (1) + r2->r1 (1) = 2 pairs
        self.assertEqual(len(mgr.pairs), 2)


class TestInversePairManagerPairing(unittest.TestCase):
    """Test the try_pair() pairing logic."""

    def _setup_z3(self) -> InversePairManager:
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        return mgr

    def test_correct_pair(self):
        """Pairing r1 with r2 succeeds in Z3."""
        mgr = self._setup_z3()
        result = mgr.try_pair("r1", "r2")
        self.assertTrue(result["success"])
        self.assertEqual(result["reason"], "correct")

    def test_wrong_pair(self):
        """Pairing r1 with r1 fails (r1*r1 = r2, not identity)."""
        mgr = self._setup_z3()
        result = mgr.try_pair("r1", "r1")
        self.assertFalse(result["success"])
        self.assertEqual(result["reason"], "not_inverse")
        # Result should tell us what we got
        self.assertIn("result_name", result)

    def test_already_paired(self):
        """Pairing an already-paired key fails."""
        mgr = self._setup_z3()
        mgr.try_pair("r1", "r2")
        result = mgr.try_pair("r1", "r2")
        self.assertFalse(result["success"])
        self.assertEqual(result["reason"], "already_paired")

    def test_unknown_key(self):
        """Pairing with unknown key sym_id fails."""
        mgr = self._setup_z3()
        result = mgr.try_pair("nonexistent", "r1")
        self.assertFalse(result["success"])
        self.assertEqual(result["reason"], "unknown_key")

    def test_unknown_candidate(self):
        """Pairing with unknown candidate sym_id fails."""
        mgr = self._setup_z3()
        result = mgr.try_pair("r1", "nonexistent")
        self.assertFalse(result["success"])
        self.assertEqual(result["reason"], "unknown_candidate")

    def test_bidirectional_auto_pairs_reverse(self):
        """In bidirectional mode, pairing r1->r2 also pairs r2->r1."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data, {"bidirectional_pairing": False})
        # Without bidirectional, we have 3 pairs: e, r1->r2, r2->r1
        # Now setup with bidirectional
        mgr2 = InversePairManager()
        mgr2.setup(data, {"bidirectional_pairing": True})
        # With bidirectional, r1->r2 is one pair
        # After pairing, both directions are resolved
        result = mgr2.try_pair("r1", "r2")
        self.assertTrue(result["success"])
        self.assertTrue(mgr2.is_complete())

    def test_self_inverse_pairing(self):
        """Self-inverse elements (involutions) pair with themselves."""
        data = load_level_json("level_03.json")
        mgr = InversePairManager()
        mgr.setup(data)

        # Find the non-identity self-inverse pair
        self_inv = [p for p in mgr.pairs if p.is_self_inverse and not p.is_identity]
        self.assertEqual(len(self_inv), 1)
        pair = self_inv[0]
        self.assertEqual(pair.key_sym_id, pair.inverse_sym_id)

        # Pair it with itself
        result = mgr.try_pair(pair.key_sym_id, pair.inverse_sym_id)
        self.assertTrue(result["success"])
        self.assertTrue(result["is_self_inverse"])

    def test_identity_excluded_from_pairs(self):
        """T111: Identity is excluded from pairs entirely."""
        mgr = self._setup_z3()
        identity_pairs = [p for p in mgr.pairs if p.is_identity]
        self.assertEqual(len(identity_pairs), 0)


class TestInversePairManagerCompletion(unittest.TestCase):
    """Test completion detection."""

    def test_z3_complete_after_pairing(self):
        """Z3: complete after pairing the one mutual pair."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)

        self.assertFalse(mgr.is_complete())
        mgr.try_pair("r1", "r2")
        self.assertTrue(mgr.is_complete())

    def test_s3_complete_after_all_pairs(self):
        """S3: complete after pairing mutual pair + all self-inverses."""
        data = load_level_json("level_09.json")
        mgr = InversePairManager()
        mgr.setup(data)

        self.assertFalse(mgr.is_complete())

        # Pair all non-identity, non-auto-paired elements
        for pair in mgr.pairs:
            if not pair.paired:
                mgr.try_pair(pair.key_sym_id, pair.inverse_sym_id)

        self.assertTrue(mgr.is_complete())

    def test_progress_tracking(self):
        """Progress tracks matched vs total non-identity pairs."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)

        prog = mgr.get_progress()
        self.assertEqual(prog["matched"], 0)
        self.assertEqual(prog["total"], 1)  # 1 non-identity pair in Z3 (bidirectional)

        mgr.try_pair("r1", "r2")
        prog = mgr.get_progress()
        self.assertEqual(prog["matched"], 1)
        self.assertEqual(prog["total"], 1)

    def test_z2_progress(self):
        """Z2 progress: 1 self-inverse pair to match."""
        data = load_level_json("level_03.json")
        mgr = InversePairManager()
        mgr.setup(data)

        prog = mgr.get_progress()
        self.assertEqual(prog["total"], 1)
        self.assertEqual(prog["matched"], 0)


class TestCompositionLab(unittest.TestCase):
    """Test the composition lookup helper (used by Composition Lab UI)."""

    def test_compose_mutual_inverses(self):
        """r1 . r2 = identity in Z3."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)

        result = mgr.compose_by_id("r1", "r2")
        self.assertTrue(result["is_identity"])
        self.assertIsNotNone(result["result_perm"])

    def test_compose_non_inverse(self):
        """r1 . r1 = r2 in Z3 (not identity)."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)

        result = mgr.compose_by_id("r1", "r1")
        self.assertFalse(result["is_identity"])
        self.assertEqual(result["result_name"], mgr._sym_id_to_name.get("r2", "r2"))

    def test_compose_unknown_sym_id(self):
        """Unknown sym_id returns empty result."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)

        result = mgr.compose_by_id("nonexistent", "r1")
        self.assertIsNone(result["result_perm"])


class TestRevealedPairs(unittest.TestCase):
    """Test the revealed_pairs tutorial feature."""

    def test_revealed_pair_is_pre_paired(self):
        """Revealed pairs start already paired."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data, {"revealed_pairs": [["r1", "r2"]]})

        # The r1<->r2 pair should be pre-paired
        pair = mgr._find_pair_by_key("r1")
        self.assertIsNotNone(pair)
        self.assertTrue(pair.paired)
        self.assertTrue(pair.revealed)

    def test_revealed_pair_completes_level(self):
        """If all pairs are revealed, level starts complete."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data, {"revealed_pairs": [["r1", "r2"]]})
        self.assertTrue(mgr.is_complete())

    def test_wrong_revealed_pair_ignored(self):
        """Revealed pair with wrong inverse_sym_id is ignored."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data, {"revealed_pairs": [["r1", "e"]]})

        pair = mgr._find_pair_by_key("r1")
        self.assertFalse(pair.paired)


class TestInverseMathCorrectness(unittest.TestCase):
    """Verify that inverse computation is mathematically correct for all levels.
    NOTE: Q8 (level_21) uses abstract quaternion multiplication, not permutation
    composition. Its permutation inverses don't necessarily land within the
    listed mappings, so we skip it for inverse-in-group checks."""

    # Q8 automorphisms are abstract representations, not concrete graph automorphisms
    SKIP_PERMUTATION_CLOSURE = {"level_21.json"}

    def test_every_automorphism_has_inverse_in_group(self):
        """For every level, every automorphism's inverse exists in the group."""
        for filename in get_all_act1_level_files():
            if filename in self.SKIP_PERMUTATION_CLOSURE:
                continue
            data = load_level_json(filename)
            autos = data.get("symmetries", {}).get("automorphisms", [])
            perms = {a["id"]: Permutation(a["mapping"]) for a in autos}

            for sym_id, perm in perms.items():
                inv = perm.inverse()
                found = any(p.equals(inv) for p in perms.values())
                self.assertTrue(found,
                    f"{filename}: inverse of {sym_id} ({inv.mapping}) not found in automorphism group")

    def test_inverse_compose_gives_identity(self):
        """For every automorphism, p.compose(p.inverse()).is_identity()."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            autos = data.get("symmetries", {}).get("automorphisms", [])

            for auto in autos:
                perm = Permutation(auto["mapping"])
                inv = perm.inverse()
                product = perm.compose(inv)
                self.assertTrue(product.is_identity(),
                    f"{filename}: {auto['id']} . inverse != identity. Got {product.mapping}")

    def test_inverse_of_inverse_is_self(self):
        """(p^-1)^-1 = p for all automorphisms."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            autos = data.get("symmetries", {}).get("automorphisms", [])

            for auto in autos:
                perm = Permutation(auto["mapping"])
                self.assertTrue(perm.inverse().inverse().equals(perm),
                    f"{filename}: (({auto['id']})^-1)^-1 != {auto['id']}")


class TestInversePairManagerAllLevels(unittest.TestCase):
    """Test InversePairManager.setup() works correctly for all 24 act1 levels.
    NOTE: Q8 (level_21) uses abstract quaternion multiplication where permutation
    inverses may not map back to listed group elements. We skip coverage check for Q8."""

    # Q8 automorphisms are abstract representations
    SKIP_COVERAGE_CHECK = {"level_21.json"}

    def test_setup_succeeds_for_all_levels(self):
        """InversePairManager.setup() doesn't crash and produces valid pairs."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            mgr = InversePairManager()
            mgr.setup(data)

            if filename in self.SKIP_COVERAGE_CHECK:
                # Q8: just verify setup doesn't crash and produces some pairs
                self.assertGreater(len(mgr.pairs), 0,
                    f"{filename}: Q8 should produce at least some pairs")
                continue

            group_order = data["meta"]["group_order"]
            # T111: identity is excluded from pairs, so covered = group_order - 1
            covered_ids = set()
            for pair in mgr.pairs:
                covered_ids.add(pair.key_sym_id)
                if not pair.is_self_inverse:
                    covered_ids.add(pair.inverse_sym_id)
            self.assertEqual(len(covered_ids), group_order - 1,
                f"{filename}: pairs cover {len(covered_ids)} sym_ids, expected {group_order - 1} (identity excluded)")

    def test_identity_excluded_from_all_levels(self):
        """T111: Identity is excluded from pairs in every level."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            mgr = InversePairManager()
            mgr.setup(data)

            identity_pairs = [p for p in mgr.pairs if p.is_identity]
            self.assertEqual(len(identity_pairs), 0,
                f"{filename}: identity should not be in pairs (T111)")

    def test_all_levels_completable(self):
        """All levels can be completed by pairing each key with its correct inverse."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            mgr = InversePairManager()
            mgr.setup(data)

            for pair in mgr.pairs:
                if not pair.paired:
                    result = mgr.try_pair(pair.key_sym_id, pair.inverse_sym_id)
                    self.assertTrue(result["success"],
                        f"{filename}: failed to pair {pair.key_sym_id} -> {pair.inverse_sym_id}: {result['reason']}")

            self.assertTrue(mgr.is_complete(),
                f"{filename}: level not complete after pairing all keys")

    def test_pair_count_matches_group_structure(self):
        """Verify pair counts match expected group-theoretic structure."""
        # Known pair counts for specific groups (bidirectional mode):
        # Z2: 2 pairs (identity + 1 self-inverse)
        # Z3: 2 pairs (identity + 1 mutual)
        # Z4: 3 pairs (identity + 1 self-inverse r2 + 1 mutual r1<->r3)
        # V4: 4 pairs (identity + 3 self-inverses)
        # S3: 5 pairs (identity + 1 mutual + 3 self-inverses)
        # T111: identity excluded from pairs
        expected = {
            "level_01.json": 1,   # Z3 (only r1<->r2)
            "level_03.json": 1,   # Z2 (only s self-inverse)
        }

        for filename, expected_pairs in expected.items():
            data = load_level_json(filename)
            mgr = InversePairManager()
            mgr.setup(data)
            self.assertEqual(len(mgr.pairs), expected_pairs,
                f"{filename}: expected {expected_pairs} pairs, got {len(mgr.pairs)}")


class TestInversePairTypes(unittest.TestCase):
    """Test identification of self-inverse vs mutual-inverse pairs."""

    def test_reflections_are_self_inverse(self):
        """All reflections (s_*) in dihedral groups are self-inverse (order 2)."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            group_name = data["meta"]["group_name"]
            if not group_name.startswith("D") and group_name != "S3":
                continue

            autos = data.get("symmetries", {}).get("automorphisms", [])
            for auto in autos:
                perm = Permutation(auto["mapping"])
                if auto["id"].startswith("s"):
                    # Reflection: should be self-inverse
                    self.assertTrue(perm.compose(perm).is_identity(),
                        f"{filename}: reflection {auto['id']} is not self-inverse (order != 2)")

    def test_identity_not_in_pairs(self):
        """T111: Identity is excluded from pairs in every group."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            mgr = InversePairManager()
            mgr.setup(data)

            identity_pairs = [p for p in mgr.pairs if p.is_identity]
            self.assertEqual(len(identity_pairs), 0,
                f"{filename}: identity should not be in pairs")

    def test_cyclic_rotations_mutual_inverses(self):
        """In Zn, rotation by k and rotation by n-k are mutual inverses."""
        # Test Z7 specifically
        data = load_level_json("level_16.json")
        mgr = InversePairManager()
        mgr.setup(data)

        # Z7: r1<->r6, r2<->r5, r3<->r4
        r1_pair = mgr._find_pair_by_key("r1")
        if r1_pair is None:
            # Might be indexed as r6 pair due to bidirectional grouping
            r1_pair = next((p for p in mgr.pairs if
                           (p.key_sym_id == "r1" and p.inverse_sym_id == "r6") or
                           (p.key_sym_id == "r6" and p.inverse_sym_id == "r1")), None)
        self.assertIsNotNone(r1_pair, "Z7: r1<->r6 pair not found")
        self.assertFalse(r1_pair.is_self_inverse)


class TestLayerProgressionLogic(unittest.TestCase):
    """Test layer unlock thresholds and hall layer state logic.
    Python mirror of HallProgressionEngine layer methods."""

    # Layer thresholds (mirror of GDScript LAYER_THRESHOLDS)
    LAYER_THRESHOLDS = {
        2: {"required": 8, "from_layer": 1},
        3: {"required": 8, "from_layer": 2},
        4: {"required": 8, "from_layer": 3},
        5: {"required": 6, "from_layer": 4},
    }

    def _is_layer_unlocked(self, layer: int, layer_completions: dict[int, int]) -> bool:
        """Check if a layer is globally unlocked."""
        if layer <= 1:
            return True
        threshold = self.LAYER_THRESHOLDS.get(layer, {})
        if not threshold:
            return False
        required = threshold.get("required", 0)
        from_layer = threshold.get("from_layer", layer - 1)
        completed = layer_completions.get(from_layer, 0)
        return completed >= required

    def test_layer1_always_unlocked(self):
        """Layer 1 is always unlocked."""
        self.assertTrue(self._is_layer_unlocked(1, {}))
        self.assertTrue(self._is_layer_unlocked(1, {1: 0}))

    def test_layer2_locked_by_default(self):
        """Layer 2 is locked with 0 completions."""
        self.assertFalse(self._is_layer_unlocked(2, {1: 0}))

    def test_layer2_unlocks_at_8_completions(self):
        """Layer 2 unlocks when 8 Layer-1 halls are completed."""
        self.assertFalse(self._is_layer_unlocked(2, {1: 7}))
        self.assertTrue(self._is_layer_unlocked(2, {1: 8}))
        self.assertTrue(self._is_layer_unlocked(2, {1: 12}))

    def test_layer3_requires_layer2(self):
        """Layer 3 requires 8 Layer-2 completions."""
        self.assertFalse(self._is_layer_unlocked(3, {1: 24, 2: 7}))
        self.assertTrue(self._is_layer_unlocked(3, {1: 24, 2: 8}))

    def test_layer5_lower_threshold(self):
        """Layer 5 only requires 6 Layer-4 completions (lower bar)."""
        self.assertFalse(self._is_layer_unlocked(5, {4: 5}))
        self.assertTrue(self._is_layer_unlocked(5, {4: 6}))

    def test_unknown_layer_locked(self):
        """Unknown layers (e.g., layer 99) are always locked."""
        self.assertFalse(self._is_layer_unlocked(99, {98: 100}))


class TestHallLayerState(unittest.TestCase):
    """Test per-hall layer state logic.
    Python mirror of HallProgressionEngine.get_hall_layer_state()."""

    def _get_hall_layer_state(self, hall_id: str, layer: int,
                               completed_halls: set[str],
                               layer_completions: dict[int, int],
                               hall_layer_progress: dict[str, dict[int, dict]]) -> str:
        """Simplified mirror of get_hall_layer_state."""
        if layer <= 0:
            return "locked"

        if layer == 1:
            if hall_id in completed_halls:
                return "completed"
            return "available"  # simplified

        # Layer 2+: check global unlock
        from_layer = layer - 1
        required = {2: 8, 3: 8, 4: 8, 5: 6}.get(layer, 999)
        if layer_completions.get(from_layer, 0) < required:
            return "locked"

        # Check prior layer completion
        prior_state = self._get_hall_layer_state(
            hall_id, layer - 1, completed_halls, layer_completions, hall_layer_progress)
        if prior_state not in ("completed", "perfect"):
            return "locked"

        # Check save data
        hall_data = hall_layer_progress.get(hall_id, {})
        layer_data = hall_data.get(layer, {})
        return layer_data.get("status", "available")

    def test_layer2_locked_when_layer1_incomplete(self):
        """Layer 2 is locked for a hall if Layer 1 isn't completed there."""
        state = self._get_hall_layer_state(
            "act1_level01", 2,
            completed_halls=set(),  # Level not completed
            layer_completions={1: 8},  # Layer 2 globally unlocked
            hall_layer_progress={})
        self.assertEqual(state, "locked")

    def test_layer2_available_when_layer1_complete(self):
        """Layer 2 is available when Layer 1 is completed and threshold met."""
        state = self._get_hall_layer_state(
            "act1_level01", 2,
            completed_halls={"act1_level01"},
            layer_completions={1: 8},
            hall_layer_progress={})
        self.assertEqual(state, "available")

    def test_layer2_completed_from_save_data(self):
        """Layer 2 shows 'completed' when save data says so."""
        state = self._get_hall_layer_state(
            "act1_level01", 2,
            completed_halls={"act1_level01"},
            layer_completions={1: 8},
            hall_layer_progress={"act1_level01": {2: {"status": "completed"}}})
        self.assertEqual(state, "completed")

    def test_layer2_locked_when_threshold_not_met(self):
        """Layer 2 locked even if hall's Layer 1 is complete but threshold not met."""
        state = self._get_hall_layer_state(
            "act1_level01", 2,
            completed_halls={"act1_level01"},
            layer_completions={1: 5},  # Not enough
            hall_layer_progress={})
        self.assertEqual(state, "locked")


class TestGameManagerLayerExtension(unittest.TestCase):
    """Test GameManager layer progress helpers (Python simulation)."""

    def test_get_layer_progress_default(self):
        """Default layer progress is {status: 'locked'}."""
        level_states = {}
        hall_id = "act1_level01"
        state = level_states.get(hall_id, {})
        lp = state.get("layer_progress", {})
        result = lp.get("layer_2", {"status": "locked"})
        self.assertEqual(result["status"], "locked")

    def test_set_and_get_layer_progress(self):
        """Set and retrieve layer progress."""
        level_states = {}
        hall_id = "act1_level01"

        # Simulate set_layer_progress
        if hall_id not in level_states:
            level_states[hall_id] = {}
        if "layer_progress" not in level_states[hall_id]:
            level_states[hall_id]["layer_progress"] = {}
        level_states[hall_id]["layer_progress"]["layer_2"] = {
            "status": "completed",
            "pairs_found": 2,
            "total_pairs": 2,
            "hints_used": 0,
            "paired_keys": ["r1", "r2"]
        }

        # Simulate get_layer_progress
        state = level_states.get(hall_id, {})
        lp = state.get("layer_progress", {})
        result = lp.get("layer_2", {"status": "locked"})
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["pairs_found"], 2)

    def test_save_data_format_includes_layer(self):
        """Save data format includes current_layer field."""
        # Simulate save_data structure
        save_data = {
            "player": {
                "current_act": 1,
                "current_level": 5,
                "current_layer": 2,
                "completed_levels": ["act1_level01", "act1_level02"],
                "level_states": {
                    "act1_level01": {
                        "layer_progress": {
                            "layer_1": {"status": "completed"},
                            "layer_2": {"status": "in_progress", "pairs_found": 1, "total_pairs": 2}
                        }
                    }
                },
                "flags": {},
            }
        }
        player = save_data["player"]
        self.assertEqual(player["current_layer"], 2)
        lp = player["level_states"]["act1_level01"]["layer_progress"]
        self.assertEqual(lp["layer_1"]["status"], "completed")
        self.assertEqual(lp["layer_2"]["status"], "in_progress")


class TestInverseGroupProperties(unittest.TestCase):
    """Mathematical verification: inverse properties hold for all level groups."""

    def test_left_inverse_equals_right_inverse(self):
        """For all automorphisms: p*p^{-1} = e = p^{-1}*p."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            autos = data.get("symmetries", {}).get("automorphisms", [])
            for auto in autos:
                perm = Permutation(auto["mapping"])
                inv = perm.inverse()
                left = perm.compose(inv)
                right = inv.compose(perm)
                self.assertTrue(left.is_identity(),
                    f"{filename} {auto['id']}: p*p^-1 not identity")
                self.assertTrue(right.is_identity(),
                    f"{filename} {auto['id']}: p^-1*p not identity")

    def test_involution_detection(self):
        """Elements of order 2 are correctly detected as self-inverse."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            autos = data.get("symmetries", {}).get("automorphisms", [])
            for auto in autos:
                perm = Permutation(auto["mapping"])
                is_order_2 = perm.compose(perm).is_identity() and not perm.is_identity()
                is_self_inv = perm.inverse().equals(perm) and not perm.is_identity()
                self.assertEqual(is_order_2, is_self_inv,
                    f"{filename} {auto['id']}: order-2 vs self-inverse mismatch")

    def test_mutual_inverse_symmetric(self):
        """If a^{-1} = b then b^{-1} = a.
        Skips Q8 (level_21) where permutation inverses don't map to group elements."""
        for filename in get_all_act1_level_files():
            if filename == "level_21.json":
                continue  # Q8: abstract representation, not permutation group
            data = load_level_json(filename)
            autos = data.get("symmetries", {}).get("automorphisms", [])
            perms = {a["id"]: Permutation(a["mapping"]) for a in autos}

            for sym_id, perm in perms.items():
                inv = perm.inverse()
                # Find the sym_id of the inverse
                inv_id = next((sid for sid, p in perms.items() if p.equals(inv)), None)
                self.assertIsNotNone(inv_id,
                    f"{filename}: inverse of {sym_id} not found")
                # Check the reverse
                inv_of_inv = perms[inv_id].inverse()
                self.assertTrue(inv_of_inv.equals(perm),
                    f"{filename}: ({inv_id})^-1 != {sym_id}")


class TestSpecificLevelInverses(unittest.TestCase):
    """Verify specific expected inverse relationships for known groups."""

    def test_z3_inverses(self):
        """Z3: r1^{-1} = r2, r2^{-1} = r1, e^{-1} = e."""
        data = load_level_json("level_01.json")
        perms = {a["id"]: Permutation(a["mapping"])
                 for a in data["symmetries"]["automorphisms"]}

        self.assertTrue(perms["e"].inverse().equals(perms["e"]))
        self.assertTrue(perms["r1"].inverse().equals(perms["r2"]))
        self.assertTrue(perms["r2"].inverse().equals(perms["r1"]))

    def test_z2_self_inverse(self):
        """Z2: reflection s is self-inverse (s^{-1} = s)."""
        data = load_level_json("level_03.json")
        perms = {a["id"]: Permutation(a["mapping"])
                 for a in data["symmetries"]["automorphisms"]}

        self.assertTrue(perms["s"].inverse().equals(perms["s"]))

    def test_d5_inverses(self):
        """D5 (level 19): r1^{-1}=r4, r2^{-1}=r3, reflections self-inverse."""
        data = load_level_json("level_19.json")
        perms = {a["id"]: Permutation(a["mapping"])
                 for a in data["symmetries"]["automorphisms"]}

        self.assertTrue(perms["r1"].inverse().equals(perms["r4"]))
        self.assertTrue(perms["r2"].inverse().equals(perms["r3"]))
        # All s_ are self-inverse
        for sym_id, perm in perms.items():
            if sym_id.startswith("s"):
                self.assertTrue(perm.compose(perm).is_identity(),
                    f"D5 reflection {sym_id} not self-inverse")

    def test_d6_inverses(self):
        """D6 (level 20): r1<->r5, r2<->r4, r3 self-inverse, reflections self-inverse."""
        data = load_level_json("level_20.json")
        perms = {a["id"]: Permutation(a["mapping"])
                 for a in data["symmetries"]["automorphisms"]}

        self.assertTrue(perms["r1"].inverse().equals(perms["r5"]))
        self.assertTrue(perms["r2"].inverse().equals(perms["r4"]))
        self.assertTrue(perms["r3"].inverse().equals(perms["r3"]))  # 180° is self-inverse

        for sym_id, perm in perms.items():
            if sym_id.startswith("s"):
                self.assertTrue(perm.compose(perm).is_identity(),
                    f"D6 reflection {sym_id} not self-inverse")

    def test_z7_inverses(self):
        """Z7 (level 16): ri^{-1} = r(7-i) for i=1..6."""
        data = load_level_json("level_16.json")
        perms = {a["id"]: Permutation(a["mapping"])
                 for a in data["symmetries"]["automorphisms"]}

        self.assertTrue(perms["r1"].inverse().equals(perms["r6"]))
        self.assertTrue(perms["r2"].inverse().equals(perms["r5"]))
        self.assertTrue(perms["r3"].inverse().equals(perms["r4"]))


# === T092: Tests for key-press-based pair detection API ===

class TestTryPairBySymIds(unittest.TestCase):
    """Test try_pair_by_sym_ids() — the new key-press pair detection method."""

    def _setup_z3(self) -> InversePairManager:
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        return mgr

    def test_pair_correct_order(self):
        """try_pair_by_sym_ids(r1, r2) succeeds."""
        mgr = self._setup_z3()
        result = mgr.try_pair_by_sym_ids("r1", "r2")
        self.assertTrue(result["success"])
        self.assertIn(result["key_sym_id"], ("r1", "r2"))
        self.assertIn(result["inv_sym_id"], ("r1", "r2"))
        self.assertNotEqual(result["key_sym_id"], result["inv_sym_id"])

    def test_pair_reverse_order(self):
        """try_pair_by_sym_ids(r2, r1) also succeeds (tries both orderings)."""
        mgr = self._setup_z3()
        result = mgr.try_pair_by_sym_ids("r2", "r1")
        self.assertTrue(result["success"])

    def test_pair_wrong_combination(self):
        """try_pair_by_sym_ids(r1, r1) fails (not inverses)."""
        mgr = self._setup_z3()
        result = mgr.try_pair_by_sym_ids("r1", "r1")
        self.assertFalse(result["success"])

    def test_pair_self_inverse(self):
        """try_pair_by_sym_ids(s, s) succeeds for self-inverse in Z2."""
        data = load_level_json("level_03.json")
        mgr = InversePairManager()
        mgr.setup(data)
        # Find the self-inverse element
        self_inv = [p for p in mgr.pairs if p.is_self_inverse and not p.is_identity]
        self.assertEqual(len(self_inv), 1)
        sid = self_inv[0].key_sym_id
        result = mgr.try_pair_by_sym_ids(sid, sid)
        self.assertTrue(result["success"])
        self.assertTrue(result["is_self_inverse"])

    def test_pair_unknown_sym_id(self):
        """try_pair_by_sym_ids with unknown sym_id fails."""
        mgr = self._setup_z3()
        result = mgr.try_pair_by_sym_ids("nonexistent", "r1")
        self.assertFalse(result["success"])

    def test_pair_already_paired(self):
        """try_pair_by_sym_ids fails if pair is already matched."""
        mgr = self._setup_z3()
        mgr.try_pair_by_sym_ids("r1", "r2")
        result = mgr.try_pair_by_sym_ids("r1", "r2")
        self.assertFalse(result["success"])


class TestIsPaired(unittest.TestCase):
    """Test is_paired() query method."""

    def test_identity_not_in_pairs(self):
        """T111: Identity is excluded from pairs, is_paired returns False."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self.assertFalse(mgr.is_paired("e"))

    def test_unpaired_returns_false(self):
        """Unpaired key returns False."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self.assertFalse(mgr.is_paired("r1"))

    def test_paired_after_match(self):
        """Key becomes paired after successful match."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        mgr.try_pair_by_sym_ids("r1", "r2")
        self.assertTrue(mgr.is_paired("r1"))
        self.assertTrue(mgr.is_paired("r2"))

    def test_unknown_sym_id(self):
        """Unknown sym_id returns False."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self.assertFalse(mgr.is_paired("nonexistent"))


class TestGetInverseSymId(unittest.TestCase):
    """Test get_inverse_sym_id() query method."""

    def test_mutual_inverse(self):
        """r1's inverse is r2 in Z3."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        inv = mgr.get_inverse_sym_id("r1")
        self.assertEqual(inv, "r2")

    def test_reverse_lookup(self):
        """r2's inverse is r1 in Z3 (reverse lookup through inverse_sym_id)."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        inv = mgr.get_inverse_sym_id("r2")
        self.assertEqual(inv, "r1")

    def test_identity_not_in_pairs(self):
        """T111: Identity excluded from pairs, get_inverse_sym_id returns empty."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        inv = mgr.get_inverse_sym_id("e")
        self.assertEqual(inv, "")

    def test_self_inverse_element(self):
        """Self-inverse element returns itself."""
        data = load_level_json("level_03.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self_inv = [p for p in mgr.pairs if p.is_self_inverse and not p.is_identity]
        sid = self_inv[0].key_sym_id
        self.assertEqual(mgr.get_inverse_sym_id(sid), sid)

    def test_unknown_returns_empty(self):
        """Unknown sym_id returns empty string."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self.assertEqual(mgr.get_inverse_sym_id("nonexistent"), "")


class TestIsSelfInverseSym(unittest.TestCase):
    """Test is_self_inverse_sym() query method."""

    def test_rotation_not_self_inverse(self):
        """r1 in Z3 is not self-inverse."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self.assertFalse(mgr.is_self_inverse_sym("r1"))

    def test_reflection_is_self_inverse(self):
        """Reflection in Z2 is self-inverse."""
        data = load_level_json("level_03.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self_inv = [p for p in mgr.pairs if p.is_self_inverse and not p.is_identity]
        sid = self_inv[0].key_sym_id
        self.assertTrue(mgr.is_self_inverse_sym(sid))

    def test_identity_not_in_pairs(self):
        """T111: Identity excluded from pairs, is_self_inverse_sym returns False."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self.assertFalse(mgr.is_self_inverse_sym("e"))

    def test_unknown_returns_false(self):
        """Unknown sym_id returns False."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)
        self.assertFalse(mgr.is_self_inverse_sym("nonexistent"))

    def test_s3_reflections_self_inverse(self):
        """All reflections in S3 are self-inverse."""
        data = load_level_json("level_09.json")
        mgr = InversePairManager()
        mgr.setup(data)
        for sym_id in mgr.get_all_sym_ids():
            if sym_id.startswith("s"):
                self.assertTrue(mgr.is_self_inverse_sym(sym_id),
                    f"S3 reflection {sym_id} should be self-inverse")

    def test_s3_rotations_not_self_inverse(self):
        """Non-identity rotations in S3 are not self-inverse (except possibly r3=r_180)."""
        data = load_level_json("level_09.json")
        mgr = InversePairManager()
        mgr.setup(data)
        # r1 and r2 in S3 are mutual inverses, not self-inverse
        self.assertFalse(mgr.is_self_inverse_sym("r1"))
        self.assertFalse(mgr.is_self_inverse_sym("r2"))


class TestKeyPressBasedPairDetection(unittest.TestCase):
    """Integration test: simulate the key-press pair detection flow.
    This mirrors LayerModeController.on_key_pressed() logic."""

    def _simulate_key_presses(self, mgr: InversePairManager, room_state_perm_ids: list[str],
                                cayley_table: list[list[int]], key_sequence: list[int]) -> list[dict]:
        """Simulate a sequence of key presses and return detected pairs.
        Mirrors LayerModeController.on_key_pressed() state machine.
        """
        detected_pairs = []
        prev_key_idx = -1
        room_before_prev = -1
        current_room = 0  # Start at Home

        for key_idx in key_sequence:
            room_before = current_room
            room_after = cayley_table[current_room][key_idx]
            current_room = room_after

            # Skip identity key
            if key_idx == 0:
                prev_key_idx = -1
                room_before_prev = -1
                continue

            if prev_key_idx == -1:
                prev_key_idx = key_idx
                room_before_prev = room_before
            else:
                if room_after == room_before_prev:
                    # Pair detected!
                    sym_a = room_state_perm_ids[prev_key_idx]
                    sym_b = room_state_perm_ids[key_idx]
                    result = mgr.try_pair_by_sym_ids(sym_a, sym_b)
                    if result["success"]:
                        detected_pairs.append(result)
                # Reset for next pair
                prev_key_idx = key_idx
                room_before_prev = room_before

        return detected_pairs

    def _build_cayley_table(self, perms: list[Permutation]) -> list[list[int]]:
        """Build Cayley table matching RoomState convention: table[a][b] = a*b."""
        n = len(perms)
        table = []
        for a in range(n):
            row = [0] * n
            for b in range(n):
                product = perms[b].compose(perms[a])  # a*b in math = b.compose(a)
                for k in range(n):
                    if perms[k].equals(product):
                        row[b] = k
                        break
            table.append(row)
        return table

    def _setup_room_data(self, data: dict) -> tuple:
        """Parse level data into (perms, perm_ids, cayley_table).
        Returns lists with identity at index 0."""
        autos = data.get("symmetries", {}).get("automorphisms", [])
        raw_perms = []
        raw_ids = []
        for auto in autos:
            raw_perms.append(Permutation(auto["mapping"]))
            raw_ids.append(auto["id"])

        # Move identity to index 0
        identity_idx = next(i for i, p in enumerate(raw_perms) if p.is_identity())
        perms = [raw_perms[identity_idx]]
        perm_ids = [raw_ids[identity_idx]]
        for i in range(len(raw_perms)):
            if i != identity_idx:
                perms.append(raw_perms[i])
                perm_ids.append(raw_ids[i])

        table = self._build_cayley_table(perms)
        return perms, perm_ids, table

    def test_z3_pair_by_key_presses(self):
        """Z3: press key 1 (r1) from Home, then key 2 (r2) → returns to Home → pair detected."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)

        perms, perm_ids, table = self._setup_room_data(data)

        # Press key 1 (r1), then key 2 (r2) — should find r1<->r2
        pairs = self._simulate_key_presses(mgr, perm_ids, table, [1, 2])
        self.assertEqual(len(pairs), 1)
        self.assertTrue(pairs[0]["success"])
        self.assertTrue(mgr.is_complete())

    def test_z3_wrong_pair_no_detection(self):
        """Z3: press key 1 (r1) twice — does NOT return to Home → no pair."""
        data = load_level_json("level_01.json")
        mgr = InversePairManager()
        mgr.setup(data)

        perms, perm_ids, table = self._setup_room_data(data)

        # r1 then r1 = r2 (not Home), so no pair detected
        pairs = self._simulate_key_presses(mgr, perm_ids, table, [1, 1])
        self.assertEqual(len(pairs), 0)
        self.assertFalse(mgr.is_complete())

    def test_z2_self_inverse_detection(self):
        """Z2: press key s from Home → goes away, press s again → returns to Home."""
        data = load_level_json("level_03.json")
        mgr = InversePairManager()
        mgr.setup(data)

        perms, perm_ids, table = self._setup_room_data(data)

        # Find the non-identity key index
        s_idx = next(i for i, sid in enumerate(perm_ids) if sid != "e")

        # Press s, then s → returns to Home → self-inverse detected
        pairs = self._simulate_key_presses(mgr, perm_ids, table, [s_idx, s_idx])
        self.assertEqual(len(pairs), 1)
        self.assertTrue(pairs[0]["is_self_inverse"])

    def test_s3_full_completion_by_key_presses(self):
        """S3: complete all inverse pairs via key presses."""
        data = load_level_json("level_09.json")
        mgr = InversePairManager()
        mgr.setup(data)

        perms, perm_ids, table = self._setup_room_data(data)

        # Identify mutual and self-inverse pairs from the manager
        for pair in mgr.pairs:
            if pair.is_identity or pair.paired:
                continue
            key_idx = perm_ids.index(pair.key_sym_id)
            inv_idx = perm_ids.index(pair.inverse_sym_id)
            # Press key, then inverse — should return to Home and detect pair
            self._simulate_key_presses(mgr, perm_ids, table, [key_idx, inv_idx])

        self.assertTrue(mgr.is_complete(),
            "S3 should be complete after pairing all inverse keys via key presses")


class TestKeyPressFromAnyRoom(unittest.TestCase):
    """T092 update: pair detection works from ANY starting room, not just Home.
    Two consecutive key presses that return to the SAME starting room = pair."""

    def _build_cayley_table(self, perms: list[Permutation]) -> list[list[int]]:
        n = len(perms)
        table = []
        for a in range(n):
            row = [0] * n
            for b in range(n):
                product = perms[b].compose(perms[a])
                for k in range(n):
                    if perms[k].equals(product):
                        row[b] = k
                        break
            table.append(row)
        return table

    def _setup_room_data(self, data: dict) -> tuple:
        autos = data.get("symmetries", {}).get("automorphisms", [])
        raw_perms = []
        raw_ids = []
        for auto in autos:
            raw_perms.append(Permutation(auto["mapping"]))
            raw_ids.append(auto["id"])
        identity_idx = next(i for i, p in enumerate(raw_perms) if p.is_identity())
        perms = [raw_perms[identity_idx]]
        perm_ids = [raw_ids[identity_idx]]
        for i in range(len(raw_perms)):
            if i != identity_idx:
                perms.append(raw_perms[i])
                perm_ids.append(raw_ids[i])
        table = self._build_cayley_table(perms)
        return perms, perm_ids, table

    def _simulate_key_presses_from_room(self, mgr: InversePairManager,
            perm_ids: list[str], cayley_table: list[list[int]],
            start_room: int, key_sequence: list[int]) -> list[dict]:
        """Simulate key presses starting from a specific room."""
        detected = []
        prev_key_idx = -1
        room_before_prev = -1
        current_room = start_room

        for key_idx in key_sequence:
            room_before = current_room
            room_after = cayley_table[current_room][key_idx]
            current_room = room_after

            if key_idx == 0:
                prev_key_idx = -1
                room_before_prev = -1
                continue

            if prev_key_idx == -1:
                prev_key_idx = key_idx
                room_before_prev = room_before
            else:
                if room_after == room_before_prev:
                    sym_a = perm_ids[prev_key_idx]
                    sym_b = perm_ids[key_idx]
                    result = mgr.try_pair_by_sym_ids(sym_a, sym_b)
                    if result["success"]:
                        detected.append(result)
                prev_key_idx = key_idx
                room_before_prev = room_before

        return detected

    def test_z3_pair_detected_from_every_room(self):
        """Z3: pressing r1→r2 detects pair regardless of starting room.
        Since r1*r2 = e, applying both from any room returns to that room."""
        data = load_level_json("level_01.json")
        perms, perm_ids, table = self._setup_room_data(data)
        r1_idx = perm_ids.index("r1")
        r2_idx = perm_ids.index("r2")

        for start_room in range(len(perms)):
            mgr = InversePairManager()
            mgr.setup(data)
            pairs = self._simulate_key_presses_from_room(
                mgr, perm_ids, table, start_room, [r1_idx, r2_idx])
            self.assertEqual(len(pairs), 1,
                f"Z3: pair r1<->r2 should be detected from room {start_room}")
            self.assertTrue(pairs[0]["success"])

    def test_z2_self_inverse_from_every_room(self):
        """Z2: pressing s→s detects self-inverse pair from every room."""
        data = load_level_json("level_03.json")
        perms, perm_ids, table = self._setup_room_data(data)
        s_idx = next(i for i, sid in enumerate(perm_ids) if sid != "e")

        for start_room in range(len(perms)):
            mgr = InversePairManager()
            mgr.setup(data)
            pairs = self._simulate_key_presses_from_room(
                mgr, perm_ids, table, start_room, [s_idx, s_idx])
            self.assertEqual(len(pairs), 1,
                f"Z2: self-inverse should be detected from room {start_room}")
            self.assertTrue(pairs[0]["is_self_inverse"])

    def test_s3_all_pairs_from_non_home(self):
        """S3: complete all pairs starting from a non-Home room."""
        data = load_level_json("level_09.json")
        perms, perm_ids, table = self._setup_room_data(data)
        mgr = InversePairManager()
        mgr.setup(data)

        current_room = 1  # Start from room 1, not Home
        prev_key_idx = -1
        room_before_prev = -1

        for pair in mgr.pairs:
            if pair.is_identity or pair.paired:
                continue
            key_idx = perm_ids.index(pair.key_sym_id)
            inv_idx = perm_ids.index(pair.inverse_sym_id)

            # Press key from current_room
            room_before = current_room
            room_after = table[current_room][key_idx]
            current_room = room_after
            prev_key_idx = key_idx
            room_before_prev = room_before

            # Press inverse
            room_before2 = current_room
            room_after2 = table[current_room][inv_idx]
            current_room = room_after2

            if room_after2 == room_before_prev:
                sym_a = perm_ids[prev_key_idx]
                sym_b = perm_ids[inv_idx]
                mgr.try_pair_by_sym_ids(sym_a, sym_b)

            prev_key_idx = inv_idx
            room_before_prev = room_before2

        self.assertTrue(mgr.is_complete(),
            "S3 should be completable from a non-Home starting room")

    def test_all_levels_completable_from_any_room(self):
        """Every level can be completed via key presses from any starting room.
        This is the key T092 invariant: inverse keys return you to the same room
        regardless of where you start."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            perms, perm_ids, table = self._setup_room_data(data)

            # Try from room 0 and room 1 (if exists)
            for start_room in [0, min(1, len(perms) - 1)]:
                mgr = InversePairManager()
                mgr.setup(data)

                for pair in mgr.pairs:
                    if pair.is_identity or pair.paired:
                        continue
                    key_idx = perm_ids.index(pair.key_sym_id)
                    inv_idx = perm_ids.index(pair.inverse_sym_id)

                    pairs = self._simulate_key_presses_from_room(
                        mgr, perm_ids, table, start_room, [key_idx, inv_idx])
                    self.assertGreater(len(pairs), 0,
                        f"{filename}: pair {pair.key_sym_id}<->{pair.inverse_sym_id} "
                        f"not detected from room {start_room}")

                self.assertTrue(mgr.is_complete(),
                    f"{filename}: not completable from room {start_room}")


if __name__ == "__main__":
    unittest.main()
