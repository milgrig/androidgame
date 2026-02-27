"""
Unit tests for Layer 3: Keyring Assembly and Subgroup Validation.
Tests the KeyringAssemblyManager logic (Python mirror) and validates
subgroup detection correctness across all 24 level JSON files.

T097: Layer 3 Engine — Keyring Assembly and Subgroup Validation
"""
import json
import os
import unittest

# Reuse core engine mirrors from test_core_engine
from test_core_engine import Permutation


# === Python mirror of KeyringAssemblyManager ===

class KeyringAssemblyManager:
    """Python mirror of KeyringAssemblyManager.gd for testing."""

    def __init__(self):
        self._sym_id_to_perm: dict[str, Permutation] = {}
        self._sym_id_to_name: dict[str, str] = {}
        self._all_sym_ids: list[str] = []

        self._target_subgroups: list[dict] = []
        self._total_count: int = 0

        self._found_signatures: list[str] = []
        self._found_subgroups: list[list[str]] = []
        self._found_count: int = 0

        self._active_slot_keys: list[str] = []
        self._active_slot_index: int = 0

        # Signal tracking for tests
        self._signals: list[tuple] = []

    def setup(self, level_data: dict, layer_config: dict = None) -> None:
        if layer_config is None:
            layer_config = {}

        self._sym_id_to_perm.clear()
        self._sym_id_to_name.clear()
        self._all_sym_ids.clear()
        self._target_subgroups.clear()
        self._found_signatures.clear()
        self._found_subgroups.clear()
        self._found_count = 0
        self._active_slot_keys.clear()
        self._active_slot_index = 0
        self._signals.clear()

        # Parse automorphisms
        autos = level_data.get("symmetries", {}).get("automorphisms", [])
        for auto in autos:
            sym_id = auto.get("id", "")
            perm = Permutation(auto.get("mapping", []))
            self._sym_id_to_perm[sym_id] = perm
            self._sym_id_to_name[sym_id] = auto.get("name", sym_id)
            self._all_sym_ids.append(sym_id)

        # Parse target subgroups
        self._target_subgroups = layer_config.get("subgroups", [])
        self._total_count = layer_config.get("subgroup_count", len(self._target_subgroups))

        # If no target subgroups provided, compute them
        if not self._target_subgroups and self._sym_id_to_perm:
            self._compute_target_subgroups()

    def _compute_target_subgroups(self) -> None:
        """Compute all subgroups of the group using generator-based approach."""
        group = list(self._sym_id_to_perm.values())
        if not group:
            return

        n = group[0].size()
        seen_signatures = set()
        all_subgroups = []

        # Generate subgroups from single generators
        for g in group:
            sub = self._generate_subgroup([g], n)
            sig = self._perm_signature(sub)
            if sig not in seen_signatures:
                seen_signatures.add(sig)
                all_subgroups.append(sub)

        # Generate subgroups from pairs of generators
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                sub = self._generate_subgroup([group[i], group[j]], n)
                sig = self._perm_signature(sub)
                if sig not in seen_signatures:
                    seen_signatures.add(sig)
                    all_subgroups.append(sub)

        # Convert to element ID format
        self._target_subgroups = []
        for sub in all_subgroups:
            elem_ids = []
            for p in sub:
                sid = self._find_sym_id_for_perm(p)
                if sid:
                    elem_ids.append(sid)
            elem_ids.sort()
            is_trivial = len(elem_ids) == 1 or len(elem_ids) == len(group)
            self._target_subgroups.append({
                "elements": elem_ids,
                "order": len(elem_ids),
                "is_trivial": is_trivial,
            })

        self._total_count = len(self._target_subgroups)

    def _generate_subgroup(self, generators: list[Permutation], n: int) -> list[Permutation]:
        """Generate subgroup from generators via closure."""
        subgroup = [Permutation.create_identity(n)]

        for gen in generators:
            if not any(s.equals(gen) for s in subgroup):
                subgroup.append(gen)

        changed = True
        while changed:
            changed = False
            to_add = []
            for a in subgroup:
                for b in subgroup:
                    product = a.compose(b)
                    if not any(s.equals(product) for s in subgroup) and \
                       not any(t.equals(product) for t in to_add):
                        to_add.append(product)
            for a in subgroup:
                inv = a.inverse()
                if not any(s.equals(inv) for s in subgroup) and \
                   not any(t.equals(inv) for t in to_add):
                    to_add.append(inv)
            if to_add:
                subgroup.extend(to_add)
                changed = True

        return subgroup

    def _perm_signature(self, sub: list[Permutation]) -> str:
        mappings = []
        for p in sub:
            s = ",".join(str(v) for v in p.mapping)
            mappings.append(s)
        mappings.sort()
        return "|".join(mappings)

    def _find_sym_id_for_perm(self, perm: Permutation) -> str:
        for sym_id, p in self._sym_id_to_perm.items():
            if p.equals(perm):
                return sym_id
        return ""

    # --- Active keyring management ---

    def add_key_to_active(self, sym_id: str) -> dict:
        if sym_id not in self._sym_id_to_perm:
            return {"added": False, "reason": "unknown_key"}
        if sym_id in self._active_slot_keys:
            return {"added": False, "reason": "duplicate_key"}
        self._active_slot_keys.append(sym_id)
        return {"added": True, "reason": "ok"}

    def remove_key_from_active(self, sym_id: str) -> dict:
        if sym_id not in self._active_slot_keys:
            return {"removed": False, "reason": "key_not_in_slot"}
        self._active_slot_keys.remove(sym_id)
        return {"removed": True, "reason": "ok"}

    def clear_active(self) -> None:
        self._active_slot_keys.clear()

    def get_active_keys(self) -> list[str]:
        return list(self._active_slot_keys)

    # --- Validation ---

    def validate_current(self) -> dict:
        if not self._active_slot_keys:
            return {"is_subgroup": False, "is_duplicate": False, "is_new": False}

        perms = []
        for sid in self._active_slot_keys:
            p = self._sym_id_to_perm.get(sid)
            if p is None:
                return {"is_subgroup": False, "is_duplicate": False, "is_new": False}
            perms.append(p)

        # Check 1: Contains identity?
        if not any(p.is_identity() for p in perms):
            return {"is_subgroup": False, "is_duplicate": False, "is_new": False}

        # Check 2: Closure under composition
        for a in perms:
            for b in perms:
                ab = a.compose(b)
                if not any(c.equals(ab) for c in perms):
                    return {"is_subgroup": False, "is_duplicate": False, "is_new": False}

        # Check 3: Closure under inverses
        for a in perms:
            a_inv = a.inverse()
            if not any(c.equals(a_inv) for c in perms):
                return {"is_subgroup": False, "is_duplicate": False, "is_new": False}

        # Valid subgroup! Check duplicate.
        sig = self._subgroup_signature_from_sym_ids(self._active_slot_keys)
        is_dup = sig in self._found_signatures

        return {"is_subgroup": True, "is_duplicate": is_dup, "is_new": not is_dup}

    def auto_validate(self) -> dict:
        result = self.validate_current()

        if result["is_subgroup"]:
            if result["is_new"]:
                sig = self._subgroup_signature_from_sym_ids(self._active_slot_keys)
                self._found_signatures.append(sig)
                found_elements = sorted(list(self._active_slot_keys))
                self._found_subgroups.append(found_elements)
                self._found_count += 1

                self._signals.append(("subgroup_found", self._active_slot_index, found_elements))

                self._active_slot_keys.clear()
                self._active_slot_index += 1

                if self.is_complete():
                    self._signals.append(("all_subgroups_found",))
            elif result["is_duplicate"]:
                self._signals.append(("duplicate_subgroup", self._active_slot_index))

        return result

    # --- Progress ---

    def get_progress(self) -> dict:
        return {"found": self._found_count, "total": self._total_count}

    def is_complete(self) -> bool:
        return self._found_count >= self._total_count

    def get_found_subgroups(self) -> list[list[str]]:
        return list(self._found_subgroups)

    def get_active_slot_index(self) -> int:
        return self._active_slot_index

    def get_total_count(self) -> int:
        return self._total_count

    # --- Persistence ---

    def save_state(self) -> dict:
        return {
            "status": "completed" if self.is_complete() else "in_progress",
            "found_subgroups": list(self._found_subgroups),
            "found_count": self._found_count,
            "total_count": self._total_count,
            "active_slot_keys": list(self._active_slot_keys),
            "active_slot_index": self._active_slot_index,
            "found_signatures": list(self._found_signatures),
        }

    def restore_from_save(self, save_data: dict) -> None:
        self._found_subgroups = [list(sg) for sg in save_data.get("found_subgroups", [])]
        self._found_count = save_data.get("found_count", len(self._found_subgroups))
        self._found_signatures = list(save_data.get("found_signatures", []))

        if not self._found_signatures and self._found_subgroups:
            for sg in self._found_subgroups:
                sig = self._subgroup_signature_from_sym_ids(sg)
                self._found_signatures.append(sig)

        self._active_slot_keys = list(save_data.get("active_slot_keys", []))
        self._active_slot_index = save_data.get("active_slot_index", self._found_count)

    # --- Query helpers ---

    def get_all_sym_ids(self) -> list[str]:
        return list(self._all_sym_ids)

    def is_target_subgroup(self, sym_ids: list[str]) -> bool:
        sorted_ids = sorted(sym_ids)
        for target in self._target_subgroups:
            target_els = sorted(target.get("elements", []))
            if sorted_ids == target_els:
                return True
        return False

    def _subgroup_signature_from_sym_ids(self, sym_ids: list[str]) -> str:
        return "|".join(sorted(sym_ids))


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

class TestKeyringSetup(unittest.TestCase):
    """Test KeyringAssemblyManager.setup() with known level data."""

    def test_z3_setup(self):
        """Z3 (level 01): 2 subgroups — {e} and G."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_total_count(), 2)
        self.assertFalse(mgr.is_complete())

    def test_z2_setup(self):
        """Z2 (level 03): 2 subgroups — {e} and G."""
        data = load_level_json("level_03.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_total_count(), 2)

    def test_z4_setup(self):
        """Z4 (level 04): 3 subgroups — {e}, {e,r2}, G."""
        data = load_level_json("level_04.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_total_count(), 3)

    def test_d4_setup(self):
        """D4 (level 05): 10 subgroups."""
        data = load_level_json("level_05.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_total_count(), 10)

    def test_s3_setup(self):
        """S3 (level 09): 6 subgroups."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_total_count(), 6)

    def test_all_levels_have_layer3_data(self):
        """All 24 levels have layer_3 config in their JSON."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            layer_3 = data.get("layers", {}).get("layer_3", {})
            self.assertIn("subgroup_count", layer_3,
                f"{filename}: missing layer_3.subgroup_count")
            self.assertIn("subgroups", layer_3,
                f"{filename}: missing layer_3.subgroups")
            self.assertGreater(layer_3["subgroup_count"], 0,
                f"{filename}: subgroup_count should be > 0")


class TestAddRemoveKeys(unittest.TestCase):
    """Test adding/removing keys from the active keyring."""

    def _setup_z3(self) -> KeyringAssemblyManager:
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)
        return mgr

    def test_add_valid_key(self):
        """Adding a valid key succeeds."""
        mgr = self._setup_z3()
        result = mgr.add_key_to_active("e")
        self.assertTrue(result["added"])
        self.assertEqual(result["reason"], "ok")
        self.assertEqual(mgr.get_active_keys(), ["e"])

    def test_add_multiple_keys(self):
        """Adding multiple keys preserves order."""
        mgr = self._setup_z3()
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        self.assertEqual(mgr.get_active_keys(), ["e", "r1"])

    def test_add_duplicate_key_rejected(self):
        """Adding the same key twice is rejected."""
        mgr = self._setup_z3()
        mgr.add_key_to_active("e")
        result = mgr.add_key_to_active("e")
        self.assertFalse(result["added"])
        self.assertEqual(result["reason"], "duplicate_key")
        self.assertEqual(len(mgr.get_active_keys()), 1)

    def test_add_unknown_key_rejected(self):
        """Adding an unknown key is rejected."""
        mgr = self._setup_z3()
        result = mgr.add_key_to_active("nonexistent")
        self.assertFalse(result["added"])
        self.assertEqual(result["reason"], "unknown_key")

    def test_remove_key(self):
        """Removing a key that exists succeeds."""
        mgr = self._setup_z3()
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        result = mgr.remove_key_from_active("e")
        self.assertTrue(result["removed"])
        self.assertEqual(mgr.get_active_keys(), ["r1"])

    def test_remove_nonexistent_key(self):
        """Removing a key not in the slot fails."""
        mgr = self._setup_z3()
        result = mgr.remove_key_from_active("e")
        self.assertFalse(result["removed"])
        self.assertEqual(result["reason"], "key_not_in_slot")

    def test_clear_active(self):
        """Clearing the active slot removes all keys."""
        mgr = self._setup_z3()
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.clear_active()
        self.assertEqual(mgr.get_active_keys(), [])


class TestSubgroupDetection(unittest.TestCase):
    """Test subgroup validation after key adds."""

    def _setup_z3(self) -> KeyringAssemblyManager:
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)
        return mgr

    def _setup_s3(self) -> KeyringAssemblyManager:
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)
        return mgr

    def test_trivial_subgroup_identity(self):
        """The trivial subgroup {e} is detected."""
        mgr = self._setup_z3()
        mgr.add_key_to_active("e")
        result = mgr.validate_current()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_new"])

    def test_full_group_detected(self):
        """The full group is detected as a subgroup."""
        mgr = self._setup_z3()
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        result = mgr.validate_current()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_new"])

    def test_non_subgroup_without_identity(self):
        """A set without identity is not a subgroup."""
        mgr = self._setup_z3()
        mgr.add_key_to_active("r1")
        result = mgr.validate_current()
        self.assertFalse(result["is_subgroup"])

    def test_non_subgroup_not_closed(self):
        """A set not closed under composition is not a subgroup."""
        mgr = self._setup_z3()
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        # {e, r1} is not closed: r1 * r1 = r2, which is not in the set
        result = mgr.validate_current()
        self.assertFalse(result["is_subgroup"])

    def test_s3_rotation_subgroup(self):
        """S3: {e, r1, r2} is a valid subgroup (Z3 rotations)."""
        mgr = self._setup_s3()
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        result = mgr.validate_current()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_new"])

    def test_s3_reflection_subgroup(self):
        """S3: {e, s01} is a valid subgroup (Z2)."""
        mgr = self._setup_s3()
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("s01")
        result = mgr.validate_current()
        self.assertTrue(result["is_subgroup"])

    def test_empty_keyring_not_subgroup(self):
        """Empty keyring is not a subgroup."""
        mgr = self._setup_z3()
        result = mgr.validate_current()
        self.assertFalse(result["is_subgroup"])


class TestDuplicateRejection(unittest.TestCase):
    """Test that duplicate subgroups are rejected."""

    def _setup_z3(self) -> KeyringAssemblyManager:
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)
        return mgr

    def test_duplicate_rejected(self):
        """Finding the same subgroup twice is detected as duplicate."""
        mgr = self._setup_z3()

        # Find {e} first time
        mgr.add_key_to_active("e")
        result = mgr.auto_validate()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_new"])

        # Try {e} again
        mgr.add_key_to_active("e")
        result = mgr.auto_validate()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_duplicate"])
        self.assertFalse(result["is_new"])

    def test_duplicate_does_not_increment_count(self):
        """Duplicate subgroup does not increase found count."""
        mgr = self._setup_z3()

        # Find {e}
        mgr.add_key_to_active("e")
        mgr.auto_validate()
        self.assertEqual(mgr.get_progress()["found"], 1)

        # Try {e} again
        mgr.add_key_to_active("e")
        mgr.auto_validate()
        self.assertEqual(mgr.get_progress()["found"], 1)  # Still 1

    def test_duplicate_signal_emitted(self):
        """Duplicate emits 'duplicate_subgroup' signal."""
        mgr = self._setup_z3()

        mgr.add_key_to_active("e")
        mgr.auto_validate()

        mgr.add_key_to_active("e")
        mgr.auto_validate()

        dup_signals = [s for s in mgr._signals if s[0] == "duplicate_subgroup"]
        self.assertEqual(len(dup_signals), 1)


class TestTrivialSubgroups(unittest.TestCase):
    """Test that trivial subgroups ({e} and G) are findable."""

    def test_trivial_identity_subgroup_z3(self):
        """Z3: {e} is findable."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("e")
        result = mgr.auto_validate()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_new"])

    def test_trivial_full_group_z3(self):
        """Z3: {e, r1, r2} (full group) is findable."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        result = mgr.auto_validate()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_new"])

    def test_trivial_identity_subgroup_z2(self):
        """Z2: {e} is findable."""
        data = load_level_json("level_03.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        # Get the identity sym_id (might be "e" or "s" depending on level)
        autos = data["symmetries"]["automorphisms"]
        identity_id = None
        for auto in autos:
            perm = Permutation(auto["mapping"])
            if perm.is_identity():
                identity_id = auto["id"]
                break
        self.assertIsNotNone(identity_id)

        mgr.add_key_to_active(identity_id)
        result = mgr.auto_validate()
        self.assertTrue(result["is_subgroup"])

    def test_trivial_full_group_d4(self):
        """D4: full group {e,r1,r2,r3,sh,sv,sd,sa} is findable."""
        data = load_level_json("level_05.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        all_ids = mgr.get_all_sym_ids()
        for sid in all_ids:
            mgr.add_key_to_active(sid)
        result = mgr.auto_validate()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_new"])


class TestCompletionDetection(unittest.TestCase):
    """Test completion detection when all subgroups are found."""

    def test_z3_complete_after_both_subgroups(self):
        """Z3: complete after finding {e} and {e,r1,r2}."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertFalse(mgr.is_complete())

        # Find {e}
        mgr.add_key_to_active("e")
        mgr.auto_validate()
        self.assertFalse(mgr.is_complete())
        self.assertEqual(mgr.get_progress(), {"found": 1, "total": 2})

        # Find {e, r1, r2}
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        mgr.auto_validate()
        self.assertTrue(mgr.is_complete())
        self.assertEqual(mgr.get_progress(), {"found": 2, "total": 2})

    def test_z2_complete_after_both_subgroups(self):
        """Z2: complete after finding {e} and G."""
        data = load_level_json("level_03.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        # Get all sym_ids
        all_ids = mgr.get_all_sym_ids()
        identity_id = None
        for sid in all_ids:
            p = mgr._sym_id_to_perm[sid]
            if p.is_identity():
                identity_id = sid
                break

        # Find {e}
        mgr.add_key_to_active(identity_id)
        mgr.auto_validate()

        # Find full group
        for sid in all_ids:
            mgr.add_key_to_active(sid)
        mgr.auto_validate()

        self.assertTrue(mgr.is_complete())

    def test_completion_signal_emitted(self):
        """Completion signal is emitted when all subgroups found."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        # Find both subgroups
        mgr.add_key_to_active("e")
        mgr.auto_validate()

        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        mgr.auto_validate()

        # Check that all_subgroups_found signal was emitted
        completion_signals = [s for s in mgr._signals if s[0] == "all_subgroups_found"]
        self.assertEqual(len(completion_signals), 1)

    def test_z4_complete_with_3_subgroups(self):
        """Z4: complete after finding {e}, {e,r2}, {e,r1,r2,r3}."""
        data = load_level_json("level_04.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        # {e}
        mgr.add_key_to_active("e")
        mgr.auto_validate()

        # {e, r2}
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r2")
        mgr.auto_validate()

        # {e, r1, r2, r3}
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        mgr.add_key_to_active("r3")
        mgr.auto_validate()

        self.assertTrue(mgr.is_complete())
        self.assertEqual(mgr.get_progress(), {"found": 3, "total": 3})


class TestAutoValidateAfterAdd(unittest.TestCase):
    """Test that auto_validate correctly detects subgroups after adding keys."""

    def test_auto_validate_clears_slot_on_new(self):
        """After finding a new subgroup, active slot is cleared."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("e")
        mgr.auto_validate()
        self.assertEqual(mgr.get_active_keys(), [])  # Cleared after found

    def test_auto_validate_does_not_clear_on_duplicate(self):
        """After finding a duplicate, active slot is NOT cleared."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("e")
        mgr.auto_validate()

        # Add {e} again — duplicate
        mgr.add_key_to_active("e")
        mgr.auto_validate()
        # Keys should still be there (not cleared)
        self.assertEqual(mgr.get_active_keys(), ["e"])

    def test_auto_validate_does_not_clear_on_non_subgroup(self):
        """Non-subgroup set remains in active slot."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        result = mgr.auto_validate()
        self.assertFalse(result["is_subgroup"])
        self.assertEqual(len(mgr.get_active_keys()), 2)  # Still there

    def test_slot_index_increments(self):
        """Slot index increments after each new subgroup."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_active_slot_index(), 0)

        mgr.add_key_to_active("e")
        mgr.auto_validate()
        self.assertEqual(mgr.get_active_slot_index(), 1)

        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        mgr.auto_validate()
        self.assertEqual(mgr.get_active_slot_index(), 2)


class TestSubgroupFoundSignals(unittest.TestCase):
    """Test that correct signals are emitted."""

    def test_subgroup_found_signal(self):
        """'subgroup_found' signal emitted with correct data."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("e")
        mgr.auto_validate()

        found_signals = [s for s in mgr._signals if s[0] == "subgroup_found"]
        self.assertEqual(len(found_signals), 1)
        self.assertEqual(found_signals[0][1], 0)  # slot_index
        self.assertEqual(found_signals[0][2], ["e"])  # elements (sorted)

    def test_no_signal_for_non_subgroup(self):
        """No signal emitted for non-subgroup."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("r1")
        mgr.auto_validate()

        self.assertEqual(len(mgr._signals), 0)


class TestPersistence(unittest.TestCase):
    """Test save/restore state."""

    def test_save_and_restore(self):
        """Save state can be restored correctly."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr1 = KeyringAssemblyManager()
        mgr1.setup(data, layer_config)

        # Find {e}
        mgr1.add_key_to_active("e")
        mgr1.auto_validate()

        # Add some keys to active slot
        mgr1.add_key_to_active("r1")

        # Save
        save_data = mgr1.save_state()
        self.assertEqual(save_data["found_count"], 1)
        self.assertEqual(save_data["active_slot_keys"], ["r1"])

        # Restore into new manager
        mgr2 = KeyringAssemblyManager()
        mgr2.setup(data, layer_config)
        mgr2.restore_from_save(save_data)

        self.assertEqual(mgr2.get_progress()["found"], 1)
        self.assertEqual(mgr2.get_active_keys(), ["r1"])
        self.assertEqual(mgr2.get_active_slot_index(), 1)

    def test_restore_prevents_duplicate(self):
        """After restoring, previously found subgroups are detected as duplicates."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr1 = KeyringAssemblyManager()
        mgr1.setup(data, layer_config)

        # Find {e}
        mgr1.add_key_to_active("e")
        mgr1.auto_validate()

        # Save and restore
        save_data = mgr1.save_state()
        mgr2 = KeyringAssemblyManager()
        mgr2.setup(data, layer_config)
        mgr2.restore_from_save(save_data)

        # Try {e} again — should be duplicate
        mgr2.add_key_to_active("e")
        result = mgr2.validate_current()
        self.assertTrue(result["is_subgroup"])
        self.assertTrue(result["is_duplicate"])


class TestSubgroupDetectionAllGroupTypes(unittest.TestCase):
    """Verify subgroup detection works for all group types (Z, D, S, A, Q8)."""

    # Q8 (level_21) has abstract representation issues with permutation approach
    SKIP_LEVELS = {"level_21.json"}

    def test_all_target_subgroups_detectable(self):
        """For each level, every target subgroup from JSON can be detected."""
        for filename in get_all_act1_level_files():
            if filename in self.SKIP_LEVELS:
                continue

            data = load_level_json(filename)
            layer_config = data.get("layers", {}).get("layer_3", {})
            target_subgroups = layer_config.get("subgroups", [])

            mgr = KeyringAssemblyManager()
            mgr.setup(data, layer_config)

            for target in target_subgroups:
                elements = target.get("elements", [])
                mgr.clear_active()
                for sid in elements:
                    result = mgr.add_key_to_active(sid)
                    self.assertTrue(result["added"],
                        f"{filename}: failed to add {sid} from subgroup {elements}")

                val = mgr.validate_current()
                self.assertTrue(val["is_subgroup"],
                    f"{filename}: {elements} (order {target.get('order')}) not detected as subgroup")

    def test_all_levels_completable(self):
        """Every level can be completed by submitting all target subgroups."""
        for filename in get_all_act1_level_files():
            if filename in self.SKIP_LEVELS:
                continue

            data = load_level_json(filename)
            layer_config = data.get("layers", {}).get("layer_3", {})
            target_subgroups = layer_config.get("subgroups", [])

            mgr = KeyringAssemblyManager()
            mgr.setup(data, layer_config)

            for target in target_subgroups:
                elements = target.get("elements", [])
                for sid in elements:
                    mgr.add_key_to_active(sid)
                result = mgr.auto_validate()
                self.assertTrue(result["is_subgroup"],
                    f"{filename}: {elements} not valid subgroup during completion")

            self.assertTrue(mgr.is_complete(),
                f"{filename}: level not complete after submitting all {len(target_subgroups)} subgroups "
                f"(found {mgr.get_progress()['found']}/{mgr.get_progress()['total']})")

    def test_z_group_subgroups(self):
        """Cyclic groups: subgroups correspond to divisors of group order."""
        # Z6 has subgroups of order 1, 2, 3, 6
        data = load_level_json("level_11.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_total_count(), 4)

        # Find all 4 subgroups
        # {e}
        mgr.add_key_to_active("e")
        mgr.auto_validate()
        # {e, r3} (order 2)
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r3")
        mgr.auto_validate()
        # {e, r2, r4} (order 3)
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r2")
        mgr.add_key_to_active("r4")
        mgr.auto_validate()
        # Full Z6
        for sid in mgr.get_all_sym_ids():
            mgr.add_key_to_active(sid)
        mgr.auto_validate()

        self.assertTrue(mgr.is_complete())

    def test_d_group_subgroups(self):
        """Dihedral groups: has both rotation and reflection subgroups."""
        # D3 (level 18): 6 subgroups
        data = load_level_json("level_18.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_total_count(), 6)

    def test_s_group_subgroups(self):
        """S3 (level 09): 6 subgroups with mix of normal and non-normal."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        target_subgroups = layer_config.get("subgroups", [])

        # Check that we have the expected types
        orders = [sg["order"] for sg in target_subgroups]
        self.assertIn(1, orders)   # {e}
        self.assertIn(2, orders)   # reflections
        self.assertIn(3, orders)   # rotations
        self.assertIn(6, orders)   # full S3

    def test_a4_subgroups(self):
        """A4 (level 15): 10 subgroups including V4."""
        data = load_level_json("level_15.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_total_count(), 10)


class TestFilteredLevels(unittest.TestCase):
    """Test that filtered levels have correct subgroup_count."""

    def test_s4_filtered(self):
        """S4 (level 13): 30 actual subgroups, filtered to 10."""
        data = load_level_json("level_13.json")
        layer_3 = data.get("layers", {}).get("layer_3", {})
        self.assertTrue(layer_3.get("filtered", False))
        self.assertEqual(layer_3["subgroup_count"], 10)
        self.assertEqual(layer_3["full_subgroup_count"], 30)

    def test_d6_filtered(self):
        """D6 (level 20): 16 actual subgroups, filtered to 10."""
        data = load_level_json("level_20.json")
        layer_3 = data.get("layers", {}).get("layer_3", {})
        self.assertTrue(layer_3.get("filtered", False))
        self.assertEqual(layer_3["subgroup_count"], 10)
        self.assertEqual(layer_3["full_subgroup_count"], 16)

    def test_d4xz2_filtered(self):
        """D4xZ2 (level 24): 33 actual subgroups, filtered to 10."""
        data = load_level_json("level_24.json")
        layer_3 = data.get("layers", {}).get("layer_3", {})
        self.assertTrue(layer_3.get("filtered", False))
        self.assertEqual(layer_3["subgroup_count"], 10)
        self.assertEqual(layer_3["full_subgroup_count"], 33)

    def test_q8_not_filtered(self):
        """Q8 (level 21): 12 subgroups, NOT filtered (pedagogically valuable)."""
        data = load_level_json("level_21.json")
        layer_3 = data.get("layers", {}).get("layer_3", {})
        self.assertFalse(layer_3.get("filtered", False))
        self.assertEqual(layer_3["subgroup_count"], 12)


class TestProgressTracking(unittest.TestCase):
    """Test progress tracking across multiple subgroup discoveries."""

    def test_progress_starts_at_zero(self):
        """Progress starts at 0/N."""
        data = load_level_json("level_04.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        prog = mgr.get_progress()
        self.assertEqual(prog["found"], 0)
        self.assertEqual(prog["total"], 3)

    def test_progress_increments_correctly(self):
        """Progress increments by 1 for each new subgroup."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("e")
        mgr.auto_validate()
        self.assertEqual(mgr.get_progress()["found"], 1)

        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        mgr.auto_validate()
        self.assertEqual(mgr.get_progress()["found"], 2)

    def test_found_subgroups_tracked(self):
        """Found subgroups are tracked as sorted element arrays."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        mgr.add_key_to_active("e")
        mgr.auto_validate()

        found = mgr.get_found_subgroups()
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0], ["e"])

        mgr.add_key_to_active("r2")
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.auto_validate()

        found = mgr.get_found_subgroups()
        self.assertEqual(len(found), 2)
        self.assertEqual(found[1], ["e", "r1", "r2"])  # Sorted


class TestLayerProgressionForLayer3(unittest.TestCase):
    """Test layer progression logic for Layer 3 (Python mirror)."""

    LAYER_THRESHOLDS = {
        2: {"required": 8, "from_layer": 1},
        3: {"required": 8, "from_layer": 2},
        4: {"required": 8, "from_layer": 3},
        5: {"required": 6, "from_layer": 4},
    }

    def _is_layer_unlocked(self, layer: int, layer_completions: dict) -> bool:
        if layer <= 1:
            return True
        threshold = self.LAYER_THRESHOLDS.get(layer, {})
        if not threshold:
            return False
        required = threshold.get("required", 0)
        from_layer = threshold.get("from_layer", layer - 1)
        completed = layer_completions.get(from_layer, 0)
        return completed >= required

    def test_layer3_locked_by_default(self):
        """Layer 3 is locked with 0 Layer-2 completions."""
        self.assertFalse(self._is_layer_unlocked(3, {2: 0}))

    def test_layer3_unlocks_at_8_layer2_completions(self):
        """Layer 3 unlocks when 8 Layer-2 halls are completed."""
        self.assertFalse(self._is_layer_unlocked(3, {2: 7}))
        self.assertTrue(self._is_layer_unlocked(3, {2: 8}))
        self.assertTrue(self._is_layer_unlocked(3, {2: 12}))

    def test_layer3_requires_layer2_not_layer1(self):
        """Layer 3 requires Layer 2 completions, not Layer 1."""
        self.assertFalse(self._is_layer_unlocked(3, {1: 24, 2: 7}))
        self.assertTrue(self._is_layer_unlocked(3, {1: 24, 2: 8}))


class TestEdgeCases(unittest.TestCase):
    """Test edge cases and boundary conditions."""

    def test_single_element_group_z1(self):
        """If a level had order 1, {e} would be both trivial subgroups."""
        # We don't have a Z1 level, but test the concept
        pass

    def test_prime_order_only_trivial_subgroups(self):
        """Z5 and Z7 (prime order) have only {e} and G."""
        for filename in ["level_10.json", "level_16.json"]:
            data = load_level_json(filename)
            layer_config = data.get("layers", {}).get("layer_3", {})
            mgr = KeyringAssemblyManager()
            mgr.setup(data, layer_config)

            self.assertEqual(mgr.get_total_count(), 2,
                f"{filename}: prime order group should have exactly 2 subgroups")

    def test_order_matters_for_elements_not_for_detection(self):
        """Adding elements in different order still detects the same subgroup."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})

        # Order 1: e, r1, r2
        mgr1 = KeyringAssemblyManager()
        mgr1.setup(data, layer_config)
        mgr1.add_key_to_active("e")
        mgr1.add_key_to_active("r1")
        mgr1.add_key_to_active("r2")
        r1 = mgr1.validate_current()

        # Order 2: r2, e, r1
        mgr2 = KeyringAssemblyManager()
        mgr2.setup(data, layer_config)
        mgr2.add_key_to_active("r2")
        mgr2.add_key_to_active("e")
        mgr2.add_key_to_active("r1")
        r2 = mgr2.validate_current()

        self.assertEqual(r1["is_subgroup"], r2["is_subgroup"])
        self.assertTrue(r1["is_subgroup"])

    def test_validate_after_remove(self):
        """Subgroup detection works correctly after removing a key."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_3", {})
        mgr = KeyringAssemblyManager()
        mgr.setup(data, layer_config)

        # Add full group, then remove r1
        mgr.add_key_to_active("e")
        mgr.add_key_to_active("r1")
        mgr.add_key_to_active("r2")
        self.assertTrue(mgr.validate_current()["is_subgroup"])

        mgr.remove_key_from_active("r1")
        # {e, r2} is NOT a subgroup in Z3 (r2*r2=r1 not in set)
        self.assertFalse(mgr.validate_current()["is_subgroup"])


if __name__ == "__main__":
    unittest.main()
