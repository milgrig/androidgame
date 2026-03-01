"""
Unit tests for Layer 4: Conjugation Cracking and Normal Subgroup Identification.
Tests the ConjugationCrackingManager logic (Python mirror) and validates
normality detection correctness across all 24 level JSON files.

T105: Layer 4 Engine — Conjugation Cracking Manager and Normality Validation
"""
import json
import os
import unittest

# Reuse core engine mirrors from test_core_engine
from test_core_engine import Permutation


# === Python mirror of SubgroupChecker.is_normal ===

def is_normal(subgroup_perms: list[Permutation], group_perms: list[Permutation]) -> bool:
    """Check if subgroup H is normal in group G.
    H is normal iff for all g in G, h in H: g * h * g^-1 is in H."""
    for g in group_perms:
        g_inv = g.inverse()
        for h in subgroup_perms:
            conjugate = g.compose(h).compose(g_inv)
            if not any(s.equals(conjugate) for s in subgroup_perms):
                return False
    return True


# === Python mirror of ConjugationCrackingManager ===

class ConjugationCrackingManager:
    """Python mirror of ConjugationCrackingManager.gd for testing."""

    def __init__(self):
        self._sym_id_to_perm: dict[str, Permutation] = {}
        self._sym_id_to_name: dict[str, str] = {}
        self._all_sym_ids: list[str] = []

        self._target_subgroups: list[dict] = []
        self._total_count: int = 0

        self._classified: dict[int, dict] = {}
        self._classified_count: int = 0

        self._active_subgroup_index: int = -1
        self._test_history: list[dict] = []

        # Signal tracking for tests
        self._signals: list[tuple] = []

    def setup(self, level_data: dict, layer_config: dict = None) -> None:
        if layer_config is None:
            layer_config = {}

        self._sym_id_to_perm.clear()
        self._sym_id_to_name.clear()
        self._all_sym_ids.clear()
        self._target_subgroups.clear()
        self._classified.clear()
        self._classified_count = 0
        self._active_subgroup_index = -1
        self._test_history.clear()
        self._signals.clear()

        # Parse automorphisms
        autos = level_data.get("symmetries", {}).get("automorphisms", [])
        for auto in autos:
            sym_id = auto.get("id", "")
            perm = Permutation(auto.get("mapping", []))
            self._sym_id_to_perm[sym_id] = perm
            self._sym_id_to_name[sym_id] = auto.get("name", sym_id)
            self._all_sym_ids.append(sym_id)

        # Get subgroups from layer config or fall back to layer_3
        subgroups = layer_config.get("subgroups", [])
        if not subgroups:
            subgroups = level_data.get("layers", {}).get("layer_3", {}).get("subgroups", [])

        # Filter: only non-trivial subgroups
        group_order = len(self._all_sym_ids)
        for sg in subgroups:
            order = sg.get("order", 0)
            is_trivial = sg.get("is_trivial", False)
            if is_trivial or order <= 1 or order >= group_order:
                continue
            self._target_subgroups.append(sg)

        self._total_count = len(self._target_subgroups)

        if "classify_count" in layer_config:
            self._total_count = layer_config["classify_count"]

    # --- Subgroup Selection ---

    def select_subgroup(self, index: int) -> bool:
        if index < 0 or index >= len(self._target_subgroups):
            return False
        if index in self._classified:
            return False
        self._active_subgroup_index = index
        self._test_history.clear()
        return True

    def get_active_subgroup_index(self) -> int:
        return self._active_subgroup_index

    def deselect_subgroup(self) -> None:
        self._active_subgroup_index = -1
        self._test_history.clear()

    # --- Conjugation Testing ---

    def test_conjugation(self, g_sym_id: str, h_sym_id: str) -> dict:
        if self._active_subgroup_index < 0 or self._active_subgroup_index >= len(self._target_subgroups):
            return {"error": "no_active_subgroup"}

        g_perm = self._sym_id_to_perm.get(g_sym_id)
        h_perm = self._sym_id_to_perm.get(h_sym_id)
        if g_perm is None or h_perm is None:
            return {"error": "invalid_sym_id"}

        # T116: validate h is actually in the active subgroup H (defense-in-depth)
        sg_elements = self._target_subgroups[self._active_subgroup_index].get("elements", [])
        if h_sym_id not in sg_elements:
            return {"error": "h_not_in_subgroup"}

        # Compute conjugate: g * h * g^-1
        g_inv = g_perm.inverse()
        conjugate = g_perm.compose(h_perm).compose(g_inv)

        # Find result sym_id
        result_sym_id = self._find_sym_id_for_perm(conjugate)
        result_name = self._sym_id_to_name.get(result_sym_id, "???")

        # Check if conjugate is in H
        sg = self._target_subgroups[self._active_subgroup_index]
        elements = sg.get("elements", [])
        stayed_in = result_sym_id in elements

        # Record test
        test_record = {
            "g": g_sym_id,
            "h": h_sym_id,
            "result": result_sym_id,
            "stayed_in": stayed_in,
        }
        self._test_history.append(test_record)

        is_witness = not stayed_in

        # If conjugate escaped — subgroup is cracked!
        if is_witness and self._active_subgroup_index not in self._classified:
            self._classified[self._active_subgroup_index] = {
                "is_normal": False,
                "witness_g": g_sym_id,
                "witness_h": h_sym_id,
                "witness_result": result_sym_id,
                "tested_pairs": list(self._test_history),
            }
            self._classified_count += 1
            self._signals.append(("subgroup_cracked", self._active_subgroup_index,
                                  g_sym_id, h_sym_id, result_sym_id))

            if self._classified_count >= self._total_count:
                self._signals.append(("all_subgroups_classified",))

        return {
            "result_sym_id": result_sym_id,
            "result_name": result_name,
            "stayed_in": stayed_in,
            "is_witness": is_witness,
        }

    def confirm_normal(self) -> dict:
        if self._active_subgroup_index < 0 or self._active_subgroup_index >= len(self._target_subgroups):
            return {"confirmed": False, "is_actually_normal": False}

        if self._active_subgroup_index in self._classified:
            return {"confirmed": False, "is_actually_normal": False}

        sg = self._target_subgroups[self._active_subgroup_index]
        elements = sg.get("elements", [])

        # Build permutation arrays for verification
        sub_perms = []
        for sid in elements:
            p = self._sym_id_to_perm.get(sid)
            if p is not None:
                sub_perms.append(p)

        group_perms = [self._sym_id_to_perm[sid] for sid in self._all_sym_ids]

        # Verify normality
        is_actually_normal = is_normal(sub_perms, group_perms)

        if is_actually_normal:
            self._classified[self._active_subgroup_index] = {
                "is_normal": True,
                "witness_g": "",
                "witness_h": "",
                "witness_result": "",
                "tested_pairs": list(self._test_history),
            }
            self._classified_count += 1
            self._signals.append(("subgroup_confirmed_normal", self._active_subgroup_index))

            if self._classified_count >= self._total_count:
                self._signals.append(("all_subgroups_classified",))

        return {
            "confirmed": is_actually_normal,
            "is_actually_normal": is_actually_normal,
        }

    def is_subgroup_normal(self, index: int) -> bool:
        if index < 0 or index >= len(self._target_subgroups):
            return False
        return self._target_subgroups[index].get("is_normal", False)

    def find_witness(self, index: int) -> dict:
        if index < 0 or index >= len(self._target_subgroups):
            return {}

        sg = self._target_subgroups[index]
        elements = sg.get("elements", [])

        for g_sid in self._all_sym_ids:
            g_perm = self._sym_id_to_perm[g_sid]
            g_inv = g_perm.inverse()
            for h_sid in elements:
                h_perm = self._sym_id_to_perm.get(h_sid)
                if h_perm is None:
                    continue
                conjugate = g_perm.compose(h_perm).compose(g_inv)
                result_sid = self._find_sym_id_for_perm(conjugate)
                if result_sid not in elements:
                    return {"g": g_sid, "h": h_sid, "result": result_sid}

        return {}

    # --- Progress ---

    def get_progress(self) -> dict:
        normal_count = sum(1 for v in self._classified.values() if v["is_normal"])
        cracked_count = sum(1 for v in self._classified.values() if not v["is_normal"])
        return {
            "classified": self._classified_count,
            "total": self._total_count,
            "normal_count": normal_count,
            "cracked_count": cracked_count,
        }

    def is_complete(self) -> bool:
        return self._classified_count >= self._total_count

    def get_target_subgroups(self) -> list[dict]:
        return list(self._target_subgroups)

    def get_classification(self, index: int) -> dict:
        return self._classified.get(index, {})

    def is_classified(self, index: int) -> bool:
        return index in self._classified

    def get_test_history(self) -> list[dict]:
        return list(self._test_history)

    def get_subgroup_elements(self, index: int) -> list[str]:
        if index < 0 or index >= len(self._target_subgroups):
            return []
        return list(self._target_subgroups[index].get("elements", []))

    def get_subgroup_order(self, index: int) -> int:
        if index < 0 or index >= len(self._target_subgroups):
            return 0
        return self._target_subgroups[index].get("order", 0)

    # --- Persistence ---

    def save_state(self) -> dict:
        classified_data = {str(k): dict(v) for k, v in self._classified.items()}
        return {
            "status": "completed" if self.is_complete() else "in_progress",
            "classified": classified_data,
            "classified_count": self._classified_count,
            "total_count": self._total_count,
            "active_subgroup_index": self._active_subgroup_index,
            "test_history": list(self._test_history),
        }

    def restore_from_save(self, save_data: dict) -> None:
        self._classified = {}
        classified_data = save_data.get("classified", {})
        for idx_str, val in classified_data.items():
            self._classified[int(idx_str)] = val
        self._classified_count = save_data.get("classified_count", len(self._classified))
        self._active_subgroup_index = save_data.get("active_subgroup_index", -1)
        self._test_history = list(save_data.get("test_history", []))

    # --- Internal helpers ---

    def get_name(self, sym_id: str) -> str:
        return self._sym_id_to_name.get(sym_id, sym_id)

    def get_all_sym_ids(self) -> list[str]:
        return list(self._all_sym_ids)

    def _find_sym_id_for_perm(self, perm: Permutation) -> str:
        for sym_id, p in self._sym_id_to_perm.items():
            if p.equals(perm):
                return sym_id
        return ""


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

class TestConjugationSetup(unittest.TestCase):
    """Test ConjugationCrackingManager.setup() with known level data."""

    def test_z3_setup_no_nontrivial(self):
        """Z3 (level 01): 0 non-trivial subgroups — Layer 4 auto-completes."""
        data = load_level_json("level_01.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_progress()["total"], 0)
        self.assertTrue(mgr.is_complete())  # Auto-complete when nothing to classify

    def test_s3_setup(self):
        """S3 (level 09): 4 non-trivial subgroups to classify."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_progress()["total"], 4)
        self.assertFalse(mgr.is_complete())

    def test_d4_setup(self):
        """D4 (level 05): 8 non-trivial subgroups to classify."""
        data = load_level_json("level_05.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_progress()["total"], 8)

    def test_all_levels_have_layer4_data(self):
        """All 24 levels have layer_4 config in their JSON."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            layer_4 = data.get("layers", {}).get("layer_4", {})
            self.assertIn("classify_count", layer_4,
                f"{filename}: missing layer_4.classify_count")
            self.assertIn("subgroups", layer_4,
                f"{filename}: missing layer_4.subgroups")


class TestSubgroupSelection(unittest.TestCase):
    """Test selecting/deselecting subgroups for testing."""

    def _setup_s3(self) -> ConjugationCrackingManager:
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)
        return mgr

    def test_select_valid_subgroup(self):
        """Selecting a valid subgroup succeeds."""
        mgr = self._setup_s3()
        self.assertTrue(mgr.select_subgroup(0))
        self.assertEqual(mgr.get_active_subgroup_index(), 0)

    def test_select_out_of_range(self):
        """Selecting out-of-range subgroup fails."""
        mgr = self._setup_s3()
        self.assertFalse(mgr.select_subgroup(-1))
        self.assertFalse(mgr.select_subgroup(100))

    def test_deselect_subgroup(self):
        """Deselecting resets active index."""
        mgr = self._setup_s3()
        mgr.select_subgroup(0)
        mgr.deselect_subgroup()
        self.assertEqual(mgr.get_active_subgroup_index(), -1)

    def test_cannot_select_classified_subgroup(self):
        """Cannot re-select an already classified subgroup."""
        mgr = self._setup_s3()
        # Classify subgroup 0 by confirming it normal (if it is)
        # or cracking it
        mgr.select_subgroup(0)
        # Force classify it
        sg = mgr.get_target_subgroups()[0]
        if sg.get("is_normal", False):
            mgr.confirm_normal()
        else:
            witness = mgr.find_witness(0)
            if witness:
                mgr.test_conjugation(witness["g"], witness["h"])

        # Now try to select it again
        self.assertFalse(mgr.select_subgroup(0))


class TestConjugationMath(unittest.TestCase):
    """Test conjugation computation: g * h * g^-1."""

    def _setup_s3(self) -> ConjugationCrackingManager:
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)
        return mgr

    def test_conjugation_stays_in(self):
        """Conjugation within a normal subgroup stays inside."""
        mgr = self._setup_s3()
        # S3: {e, r1, r2} is normal (rotation subgroup)
        # Find the rotation subgroup index
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if sg.get("is_normal", False) and sg.get("order", 0) == 3:
                mgr.select_subgroup(i)
                # Test: s01 * r1 * s01^-1 — should stay in {e, r1, r2}
                result = mgr.test_conjugation("s01", "r1")
                self.assertFalse(result.get("error"))
                self.assertTrue(result["stayed_in"])
                return
        self.fail("Could not find normal rotation subgroup in S3")

    def test_conjugation_escapes(self):
        """Conjugation of non-normal subgroup can escape."""
        mgr = self._setup_s3()
        # S3: {e, s01} is NOT normal
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if not sg.get("is_normal", False) and sg.get("order", 0) == 2:
                elements = sg.get("elements", [])
                non_identity = [e for e in elements if e != "e"][0]
                mgr.select_subgroup(i)
                # Find a witness
                witness = mgr.find_witness(i)
                if witness:
                    result = mgr.test_conjugation(witness["g"], witness["h"])
                    self.assertFalse(result["stayed_in"])
                    self.assertTrue(result["is_witness"])
                    return
        self.fail("Could not find non-normal subgroup in S3")

    def test_identity_conjugation_always_stays(self):
        """Conjugating with identity: e * h * e^-1 = h always stays in H."""
        mgr = self._setup_s3()
        mgr.select_subgroup(0)
        elements = mgr.get_subgroup_elements(0)
        for h_sid in elements:
            result = mgr.test_conjugation("e", h_sid)
            self.assertTrue(result["stayed_in"],
                f"e * {h_sid} * e^-1 should stay in subgroup")

    def test_no_active_subgroup_error(self):
        """Testing without active subgroup returns error."""
        mgr = self._setup_s3()
        result = mgr.test_conjugation("e", "r1")
        self.assertIn("error", result)

    def test_invalid_sym_id_error(self):
        """Testing with invalid sym_id returns error."""
        mgr = self._setup_s3()
        mgr.select_subgroup(0)
        result = mgr.test_conjugation("nonexistent", "r1")
        self.assertIn("error", result)


class TestCrackingDetection(unittest.TestCase):
    """Test that cracking non-normal subgroups works correctly."""

    def _setup_s3(self) -> ConjugationCrackingManager:
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)
        return mgr

    def test_crack_non_normal(self):
        """Cracking a non-normal subgroup classifies it."""
        mgr = self._setup_s3()
        # Find first non-normal subgroup
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if not sg.get("is_normal", False):
                mgr.select_subgroup(i)
                witness = mgr.find_witness(i)
                self.assertNotEqual(witness, {},
                    f"Should find witness for non-normal subgroup {i}")
                result = mgr.test_conjugation(witness["g"], witness["h"])
                self.assertTrue(result["is_witness"])
                self.assertTrue(mgr.is_classified(i))
                classification = mgr.get_classification(i)
                self.assertFalse(classification["is_normal"])
                return
        self.fail("No non-normal subgroup found in S3")

    def test_crack_emits_signal(self):
        """Cracking emits 'subgroup_cracked' signal."""
        mgr = self._setup_s3()
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if not sg.get("is_normal", False):
                mgr.select_subgroup(i)
                witness = mgr.find_witness(i)
                mgr.test_conjugation(witness["g"], witness["h"])
                cracked_signals = [s for s in mgr._signals if s[0] == "subgroup_cracked"]
                self.assertEqual(len(cracked_signals), 1)
                self.assertEqual(cracked_signals[0][1], i)
                return

    def test_double_crack_no_double_count(self):
        """Cracking same subgroup twice doesn't double count."""
        mgr = self._setup_s3()
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if not sg.get("is_normal", False):
                mgr.select_subgroup(i)
                witness = mgr.find_witness(i)
                mgr.test_conjugation(witness["g"], witness["h"])
                count_before = mgr.get_progress()["classified"]
                # Try another witness
                mgr.test_conjugation(witness["g"], witness["h"])
                count_after = mgr.get_progress()["classified"]
                self.assertEqual(count_before, count_after)
                return


class TestNormalConfirmation(unittest.TestCase):
    """Test confirming normal subgroups."""

    def _setup_d4(self) -> ConjugationCrackingManager:
        data = load_level_json("level_05.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)
        return mgr

    def test_confirm_normal_correct(self):
        """Confirming a truly normal subgroup succeeds."""
        mgr = self._setup_d4()
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if sg.get("is_normal", False):
                mgr.select_subgroup(i)
                result = mgr.confirm_normal()
                self.assertTrue(result["confirmed"])
                self.assertTrue(result["is_actually_normal"])
                self.assertTrue(mgr.is_classified(i))
                classification = mgr.get_classification(i)
                self.assertTrue(classification["is_normal"])
                return
        self.fail("No normal subgroup found in D4")

    def test_confirm_non_normal_fails(self):
        """Confirming a non-normal subgroup fails."""
        mgr = self._setup_d4()
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if not sg.get("is_normal", False):
                mgr.select_subgroup(i)
                result = mgr.confirm_normal()
                self.assertFalse(result["confirmed"])
                self.assertFalse(result["is_actually_normal"])
                self.assertFalse(mgr.is_classified(i))  # Not classified on wrong answer
                return

    def test_confirm_emits_signal(self):
        """Confirming normal emits 'subgroup_confirmed_normal' signal."""
        mgr = self._setup_d4()
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if sg.get("is_normal", False):
                mgr.select_subgroup(i)
                mgr.confirm_normal()
                normal_signals = [s for s in mgr._signals if s[0] == "subgroup_confirmed_normal"]
                self.assertEqual(len(normal_signals), 1)
                self.assertEqual(normal_signals[0][1], i)
                return

    def test_cannot_confirm_already_classified(self):
        """Cannot confirm an already classified subgroup."""
        mgr = self._setup_d4()
        for i, sg in enumerate(mgr.get_target_subgroups()):
            if sg.get("is_normal", False):
                mgr.select_subgroup(i)
                mgr.confirm_normal()  # First time
                mgr._active_subgroup_index = i  # Re-select manually
                result = mgr.confirm_normal()  # Second time
                self.assertFalse(result["confirmed"])
                return


class TestWitnessSearch(unittest.TestCase):
    """Test finding witnesses (g, h) for non-normal subgroups."""

    def test_witness_exists_for_non_normal(self):
        """Every non-normal subgroup has a witness."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        for i, sg in enumerate(mgr.get_target_subgroups()):
            if not sg.get("is_normal", False):
                witness = mgr.find_witness(i)
                self.assertNotEqual(witness, {},
                    f"S3 subgroup {i} is non-normal but no witness found")

    def test_no_witness_for_normal(self):
        """Normal subgroups have no witness."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        for i, sg in enumerate(mgr.get_target_subgroups()):
            if sg.get("is_normal", False):
                witness = mgr.find_witness(i)
                self.assertEqual(witness, {},
                    f"S3 subgroup {i} is normal but witness found: {witness}")


class TestCompletionDetection(unittest.TestCase):
    """Test completion detection when all subgroups are classified."""

    def test_s3_complete_after_all_classified(self):
        """S3: complete after classifying all 4 non-trivial subgroups."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        self.assertFalse(mgr.is_complete())

        for i, sg in enumerate(mgr.get_target_subgroups()):
            mgr.select_subgroup(i)
            if sg.get("is_normal", False):
                mgr.confirm_normal()
            else:
                witness = mgr.find_witness(i)
                mgr.test_conjugation(witness["g"], witness["h"])

        self.assertTrue(mgr.is_complete())
        prog = mgr.get_progress()
        self.assertEqual(prog["classified"], 4)
        self.assertEqual(prog["total"], 4)
        self.assertEqual(prog["normal_count"], 1)
        self.assertEqual(prog["cracked_count"], 3)

    def test_completion_signal_emitted(self):
        """Completion signal is emitted when all subgroups classified."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        for i, sg in enumerate(mgr.get_target_subgroups()):
            mgr.select_subgroup(i)
            if sg.get("is_normal", False):
                mgr.confirm_normal()
            else:
                witness = mgr.find_witness(i)
                mgr.test_conjugation(witness["g"], witness["h"])

        completion_signals = [s for s in mgr._signals if s[0] == "all_subgroups_classified"]
        self.assertEqual(len(completion_signals), 1)

    def test_z2_auto_complete(self):
        """Z2 (level 03): 0 non-trivial subgroups = auto-complete."""
        data = load_level_json("level_03.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        self.assertTrue(mgr.is_complete())

    def test_z4_one_subgroup(self):
        """Z4 (level 04): 1 non-trivial subgroup ({e, r2}) — normal."""
        data = load_level_json("level_04.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        self.assertEqual(mgr.get_progress()["total"], 1)
        mgr.select_subgroup(0)
        result = mgr.confirm_normal()
        self.assertTrue(result["confirmed"])
        self.assertTrue(mgr.is_complete())


class TestPersistence(unittest.TestCase):
    """Test save/restore state."""

    def test_save_and_restore(self):
        """Save state can be restored correctly."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr1 = ConjugationCrackingManager()
        mgr1.setup(data, layer_config)

        # Classify first subgroup
        mgr1.select_subgroup(0)
        sg = mgr1.get_target_subgroups()[0]
        if sg.get("is_normal", False):
            mgr1.confirm_normal()
        else:
            witness = mgr1.find_witness(0)
            mgr1.test_conjugation(witness["g"], witness["h"])

        # Save
        save_data = mgr1.save_state()
        self.assertEqual(save_data["classified_count"], 1)

        # Restore into new manager
        mgr2 = ConjugationCrackingManager()
        mgr2.setup(data, layer_config)
        mgr2.restore_from_save(save_data)

        self.assertEqual(mgr2.get_progress()["classified"], 1)
        self.assertTrue(mgr2.is_classified(0))

    def test_restore_prevents_re_classification(self):
        """After restoring, classified subgroups cannot be selected."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr1 = ConjugationCrackingManager()
        mgr1.setup(data, layer_config)

        mgr1.select_subgroup(0)
        sg = mgr1.get_target_subgroups()[0]
        if sg.get("is_normal", False):
            mgr1.confirm_normal()
        else:
            witness = mgr1.find_witness(0)
            mgr1.test_conjugation(witness["g"], witness["h"])

        save_data = mgr1.save_state()
        mgr2 = ConjugationCrackingManager()
        mgr2.setup(data, layer_config)
        mgr2.restore_from_save(save_data)

        self.assertFalse(mgr2.select_subgroup(0))  # Already classified


class TestNormalityAcrossAllGroupTypes(unittest.TestCase):
    """Verify normality detection works for all group types."""

    def test_all_levels_normality_consistent(self):
        """For each level, the is_normal flag in JSON matches computed normality."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            layer_config = data.get("layers", {}).get("layer_4", {})
            layer_4_subgroups = layer_config.get("subgroups", [])

            autos = data.get("symmetries", {}).get("automorphisms", [])
            sym_id_to_perm = {}
            all_perms = []
            for auto in autos:
                perm = Permutation(auto.get("mapping", []))
                sym_id_to_perm[auto["id"]] = perm
                all_perms.append(perm)

            for sg in layer_4_subgroups:
                elements = sg.get("elements", [])
                json_normal = sg.get("is_normal", False)

                sub_perms = []
                for sid in elements:
                    p = sym_id_to_perm.get(sid)
                    if p is not None:
                        sub_perms.append(p)

                if len(sub_perms) == 0:
                    continue

                computed_normal = is_normal(sub_perms, all_perms)
                self.assertEqual(json_normal, computed_normal,
                    f"{filename}: subgroup {elements} — JSON says is_normal={json_normal}, "
                    f"computed={computed_normal}")

    def test_all_non_normal_have_witnesses(self):
        """Every non-normal subgroup across all levels has a crackable witness."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            layer_config = data.get("layers", {}).get("layer_4", {})
            mgr = ConjugationCrackingManager()
            mgr.setup(data, layer_config)

            for i, sg in enumerate(mgr.get_target_subgroups()):
                if not sg.get("is_normal", False):
                    witness = mgr.find_witness(i)
                    self.assertNotEqual(witness, {},
                        f"{filename}: non-normal subgroup {i} ({sg['elements']}) "
                        f"has no witness")

    def test_all_levels_completable(self):
        """Every level can be completed by classifying all non-trivial subgroups."""
        for filename in get_all_act1_level_files():
            data = load_level_json(filename)
            layer_config = data.get("layers", {}).get("layer_4", {})
            mgr = ConjugationCrackingManager()
            mgr.setup(data, layer_config)

            for i, sg in enumerate(mgr.get_target_subgroups()):
                mgr.select_subgroup(i)
                if sg.get("is_normal", False):
                    result = mgr.confirm_normal()
                    self.assertTrue(result["confirmed"],
                        f"{filename}: subgroup {i} ({sg['elements']}) is_normal=True "
                        f"but confirm_normal failed")
                else:
                    witness = mgr.find_witness(i)
                    self.assertNotEqual(witness, {},
                        f"{filename}: no witness for non-normal subgroup {i}")
                    result = mgr.test_conjugation(witness["g"], witness["h"])
                    self.assertTrue(result["is_witness"],
                        f"{filename}: witness for subgroup {i} didn't crack it")

            self.assertTrue(mgr.is_complete(),
                f"{filename}: level not complete after classifying all subgroups "
                f"({mgr.get_progress()})")


class TestProgressTracking(unittest.TestCase):
    """Test progress tracking."""

    def test_progress_starts_at_zero(self):
        """Progress starts at 0/N."""
        data = load_level_json("level_05.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        prog = mgr.get_progress()
        self.assertEqual(prog["classified"], 0)
        self.assertEqual(prog["normal_count"], 0)
        self.assertEqual(prog["cracked_count"], 0)

    def test_progress_increments_on_crack(self):
        """Progress increments when a subgroup is cracked."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        for i, sg in enumerate(mgr.get_target_subgroups()):
            if not sg.get("is_normal", False):
                mgr.select_subgroup(i)
                witness = mgr.find_witness(i)
                mgr.test_conjugation(witness["g"], witness["h"])
                prog = mgr.get_progress()
                self.assertEqual(prog["classified"], 1)
                self.assertEqual(prog["cracked_count"], 1)
                return

    def test_progress_increments_on_confirm(self):
        """Progress increments when a subgroup is confirmed normal."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        for i, sg in enumerate(mgr.get_target_subgroups()):
            if sg.get("is_normal", False):
                mgr.select_subgroup(i)
                mgr.confirm_normal()
                prog = mgr.get_progress()
                self.assertEqual(prog["classified"], 1)
                self.assertEqual(prog["normal_count"], 1)
                return


class TestTestHistory(unittest.TestCase):
    """Test that conjugation test history is tracked."""

    def test_history_recorded(self):
        """Test history is recorded after each conjugation test."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        mgr.select_subgroup(0)
        elements = mgr.get_subgroup_elements(0)
        h_sid = elements[0] if elements else "e"

        mgr.test_conjugation("e", h_sid)
        history = mgr.get_test_history()
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["g"], "e")
        self.assertEqual(history[0]["h"], h_sid)
        self.assertIn("stayed_in", history[0])

    def test_history_clears_on_subgroup_change(self):
        """Test history clears when selecting a different subgroup."""
        data = load_level_json("level_05.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        mgr.select_subgroup(0)
        elements = mgr.get_subgroup_elements(0)
        h_sid = elements[0] if elements else "e"
        mgr.test_conjugation("e", h_sid)
        self.assertEqual(len(mgr.get_test_history()), 1)

        mgr.select_subgroup(1)
        self.assertEqual(len(mgr.get_test_history()), 0)


class TestLayerProgressionForLayer4(unittest.TestCase):
    """Test layer progression logic for Layer 4."""

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

    def test_layer4_locked_by_default(self):
        """Layer 4 is locked with 0 Layer-3 completions."""
        self.assertFalse(self._is_layer_unlocked(4, {3: 0}))

    def test_layer4_unlocks_at_8_layer3_completions(self):
        """Layer 4 unlocks when 8 Layer-3 halls are completed."""
        self.assertFalse(self._is_layer_unlocked(4, {3: 7}))
        self.assertTrue(self._is_layer_unlocked(4, {3: 8}))
        self.assertTrue(self._is_layer_unlocked(4, {3: 12}))

    def test_layer4_requires_layer3_not_layer2(self):
        """Layer 4 requires Layer 3 completions, not Layer 2."""
        self.assertFalse(self._is_layer_unlocked(4, {2: 24, 3: 7}))
        self.assertTrue(self._is_layer_unlocked(4, {2: 24, 3: 8}))


class TestEdgeCases(unittest.TestCase):
    """Test edge cases and boundary conditions."""

    def test_abelian_group_all_normal(self):
        """In abelian groups (Z, V4), ALL subgroups are normal."""
        # V4 (level 06): 3 non-trivial subgroups, all normal
        data = load_level_json("level_06.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        for i, sg in enumerate(mgr.get_target_subgroups()):
            self.assertTrue(sg.get("is_normal", False),
                f"V4 subgroup {i} should be normal (abelian group)")

        # Complete by confirming all
        for i in range(len(mgr.get_target_subgroups())):
            mgr.select_subgroup(i)
            result = mgr.confirm_normal()
            self.assertTrue(result["confirmed"])

        self.assertTrue(mgr.is_complete())
        prog = mgr.get_progress()
        self.assertEqual(prog["cracked_count"], 0)

    def test_q8_subgroups(self):
        """Q8 (level 21): has both normal and non-normal subgroups."""
        data = load_level_json("level_21.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        total = mgr.get_progress()["total"]
        self.assertGreater(total, 0, "Q8 should have non-trivial subgroups")

        # Complete the level
        for i, sg in enumerate(mgr.get_target_subgroups()):
            mgr.select_subgroup(i)
            if sg.get("is_normal", False):
                mgr.confirm_normal()
            else:
                witness = mgr.find_witness(i)
                if witness:
                    mgr.test_conjugation(witness["g"], witness["h"])

        self.assertTrue(mgr.is_complete())

    def test_conjugation_with_self(self):
        """Conjugating h ∈ H with itself: h * h * h^-1 = h, always stays in H."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        mgr.select_subgroup(0)
        elements = mgr.get_subgroup_elements(0)
        for h_sid in elements:
            result = mgr.test_conjugation(h_sid, h_sid)
            self.assertTrue(result["stayed_in"],
                f"{h_sid} * {h_sid} * {h_sid}^-1 should be {h_sid}")
            # Verify result is h itself
            self.assertEqual(result["result_sym_id"], h_sid)


class TestHInSubgroupValidation(unittest.TestCase):
    """T116: test_conjugation() rejects h not in active subgroup H."""

    def test_h_not_in_subgroup_returns_error(self):
        """Using h outside the active subgroup H returns error."""
        data = load_level_json("level_09.json")  # S3 — has non-trivial subgroups
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        mgr.select_subgroup(0)
        sg_elements = mgr.get_subgroup_elements(0)
        all_ids = mgr.get_all_sym_ids()

        # Find a sym_id that is NOT in the active subgroup
        outside_h = None
        for sid in all_ids:
            if sid not in sg_elements:
                outside_h = sid
                break
        self.assertIsNotNone(outside_h,
            "S3 subgroups should not contain all group elements")

        # Use a valid g (any element) with invalid h (outside subgroup)
        g_sid = all_ids[0]
        result = mgr.test_conjugation(g_sid, outside_h)
        self.assertIn("error", result)
        self.assertEqual(result["error"], "h_not_in_subgroup")

    def test_h_in_subgroup_succeeds(self):
        """Using h inside the active subgroup H works normally."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        mgr.select_subgroup(0)
        sg_elements = mgr.get_subgroup_elements(0)
        all_ids = mgr.get_all_sym_ids()

        g_sid = all_ids[0]
        h_sid = sg_elements[0]  # h IS in the subgroup
        result = mgr.test_conjugation(g_sid, h_sid)
        self.assertNotIn("error", result)
        self.assertIn("result_sym_id", result)
        self.assertIn("stayed_in", result)

    def test_h_not_in_subgroup_no_side_effects(self):
        """Rejected h should not record a test or change state."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        mgr.select_subgroup(0)
        sg_elements = mgr.get_subgroup_elements(0)
        all_ids = mgr.get_all_sym_ids()

        outside_h = None
        for sid in all_ids:
            if sid not in sg_elements:
                outside_h = sid
                break

        history_before = list(mgr._test_history)
        signals_before = list(mgr._signals)
        classified_before = dict(mgr._classified)

        result = mgr.test_conjugation(all_ids[0], outside_h)
        self.assertEqual(result["error"], "h_not_in_subgroup")

        # No side effects
        self.assertEqual(mgr._test_history, history_before)
        self.assertEqual(mgr._signals, signals_before)
        self.assertEqual(mgr._classified, classified_before)

    def test_h_validation_across_multiple_subgroups(self):
        """h-in-subgroup check applies to whichever subgroup is active."""
        data = load_level_json("level_09.json")  # S3 — multiple subgroups
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        targets = mgr.get_target_subgroups()
        if len(targets) < 2:
            self.skipTest("Need at least 2 subgroups for this test")

        all_ids = mgr.get_all_sym_ids()

        # For each subgroup, find an element NOT in it and verify rejection
        for i in range(min(len(targets), 3)):
            mgr.select_subgroup(i)
            sg_elements = mgr.get_subgroup_elements(i)
            outside_h = None
            for sid in all_ids:
                if sid not in sg_elements:
                    outside_h = sid
                    break
            if outside_h is None:
                continue  # subgroup is the whole group (shouldn't happen after T114)

            result = mgr.test_conjugation(all_ids[0], outside_h)
            self.assertEqual(result["error"], "h_not_in_subgroup",
                f"Subgroup {i}: h outside H should be rejected")

    def test_identity_in_subgroup_accepted(self):
        """The identity element is always in every subgroup, should be accepted as h."""
        data = load_level_json("level_09.json")
        layer_config = data.get("layers", {}).get("layer_4", {})
        mgr = ConjugationCrackingManager()
        mgr.setup(data, layer_config)

        mgr.select_subgroup(0)
        sg_elements = mgr.get_subgroup_elements(0)

        # Find the identity element (should be in every subgroup)
        identity_sid = None
        for sid in mgr.get_all_sym_ids():
            p = mgr._sym_id_to_perm.get(sid)
            if p is not None and p.is_identity():
                identity_sid = sid
                break

        if identity_sid is None:
            self.skipTest("No identity found")

        self.assertIn(identity_sid, sg_elements,
            "Identity should be in every subgroup")

        result = mgr.test_conjugation(identity_sid, identity_sid)
        self.assertNotIn("error", result)
        self.assertTrue(result["stayed_in"])


if __name__ == "__main__":
    unittest.main()
