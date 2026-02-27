"""
Tests for T049: Inner Door UI — visual door, subgroup selector, progress display.

Verifies:
1. InnerDoorVisual state management and animations
2. SubgroupSelector key selection and subgroup validation
3. Counter label shows "Ключи: X/Y | Двери: Z/W" for Act 2
4. "Момент понимания" triggers only on first door ever opened
5. InnerDoorPanel integration with SubgroupSelector
6. Door visual placement (centroid of crystal positions)
7. All Act 2 levels (13-16) have inner_doors defined
"""
import json
import os
import unittest

from test_core_engine import Permutation, CrystalGraph, KeyRing


def load_level_json(filename: str, act: int = 1) -> dict:
    """Load a level JSON file from the data directory."""
    base = os.path.dirname(os.path.abspath(__file__))
    act_dir = "act%d" % act
    path = os.path.join(base, "..", "..", "..", "data", "levels", act_dir, filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# ---- Simulated UI components (Python mirrors) ----

class InnerDoorVisualSim:
    """Python mirror of InnerDoorVisual.gd."""
    LOCKED = "locked"
    UNLOCKED = "unlocked"

    def __init__(self, door_id: str, visual_hint: str, required_order: int, position: tuple):
        self.door_id = door_id
        self.visual_hint = visual_hint
        self.required_order = required_order
        self.position = position
        self.state = self.LOCKED
        self.animation_log: list[str] = []

    def play_unlock_animation(self):
        self.state = self.UNLOCKED
        self.animation_log.append("unlock")

    def play_failure_animation(self):
        self.animation_log.append("failure")


class SubgroupSelectorSim:
    """Python mirror of SubgroupSelector.gd + InnerDoorPanel logic."""

    def __init__(self, doors_data: list, subgroups_data: list, key_ring: KeyRing,
                 target_perms: dict):
        self.doors_data = list(doors_data)
        self.subgroups_data = list(subgroups_data)
        self.key_ring = key_ring
        self.target_perms = target_perms
        self.door_states = {d["id"]: "locked" for d in doors_data}
        self.selected_indices: list[int] = []
        self.events: list[str] = []

    def select_keys(self, indices: list[int]):
        self.selected_indices = list(indices)

    def check_subgroup(self) -> dict:
        """Check if selected keys form a subgroup."""
        return self.key_ring.check_subgroup(self.selected_indices)

    def try_open_door(self) -> dict:
        """Try to open a locked door with selected keys."""
        result = self.check_subgroup()
        if not result["is_subgroup"]:
            self.events.append("door_failed")
            return {"opened": False, "reason": result.get("reasons", [])}

        # Check which door matches
        for door in self.doors_data:
            did = door["id"]
            if self.door_states[did] != "locked":
                continue
            req_sg = door.get("required_subgroup", "")
            if self._matches_subgroup(req_sg):
                self.door_states[did] = "opened"
                self.events.append(f"door_opened:{did}")
                return {"opened": True, "door_id": did}

        self.events.append("subgroup_valid_no_door")
        return {"opened": False, "reason": ["valid_but_no_match"]}

    def _matches_subgroup(self, sg_name: str) -> bool:
        """Check if selected keys match the target subgroup elements."""
        target_sg = None
        for sg in self.subgroups_data:
            if sg["name"] == sg_name:
                target_sg = sg
                break
        if target_sg is None:
            return False

        target_elements = target_sg.get("elements", [])
        if len(self.selected_indices) != len(target_elements):
            return False

        # Get selected permutations
        selected_perms = []
        for idx in self.selected_indices:
            if idx < self.key_ring.count():
                selected_perms.append(self.key_ring.get_key(idx))

        # Check each target element is in selected
        for elem_id in target_elements:
            target_p = self.target_perms.get(elem_id)
            if target_p is None:
                return False
            if not any(sp.equals(target_p) for sp in selected_perms):
                return False
        return True

    def is_all_doors_opened(self) -> bool:
        return all(v == "opened" for v in self.door_states.values())

    def get_opened_count(self) -> int:
        return sum(1 for v in self.door_states.values() if v == "opened")

    def get_total_count(self) -> int:
        return len(self.door_states)


class CounterLabelSim:
    """Simulates the enhanced counter label: Ключи + Двери."""

    @staticmethod
    def format(keys_found: int, keys_total: int, door_panel=None) -> str:
        text = "Ключи: %d / %d" % (keys_found, keys_total)
        if door_panel is not None:
            opened = door_panel.get_opened_count()
            total = door_panel.get_total_count()
            text += " | Двери: %d / %d" % (opened, total)
        return text


class MomentOfUnderstandingSim:
    """Simulates the 'Момент понимания' — first inner door celebration."""

    def __init__(self):
        self.first_door_ever_opened = False
        self.moment_played = False

    def on_door_opened(self, door_id: str):
        if not self.first_door_ever_opened:
            self.first_door_ever_opened = True
            self.moment_played = True
            return True  # "Момент понимания" played
        return False


# ---- Tests ----

class TestInnerDoorVisual(unittest.TestCase):
    """T049: InnerDoorVisual state management."""

    def test_initial_state_is_locked(self):
        dv = InnerDoorVisualSim("door1", "Test door", 3, (500, 400))
        self.assertEqual(dv.state, InnerDoorVisualSim.LOCKED)

    def test_unlock_changes_state(self):
        dv = InnerDoorVisualSim("door1", "Test door", 3, (500, 400))
        dv.play_unlock_animation()
        self.assertEqual(dv.state, InnerDoorVisualSim.UNLOCKED)
        self.assertIn("unlock", dv.animation_log)

    def test_failure_keeps_locked(self):
        dv = InnerDoorVisualSim("door1", "Test door", 3, (500, 400))
        dv.play_failure_animation()
        self.assertEqual(dv.state, InnerDoorVisualSim.LOCKED)
        self.assertIn("failure", dv.animation_log)

    def test_position_stored(self):
        dv = InnerDoorVisualSim("door1", "Hint text", 2, (420, 300))
        self.assertEqual(dv.position, (420, 300))
        self.assertEqual(dv.visual_hint, "Hint text")
        self.assertEqual(dv.required_order, 2)


class TestDoorVisualPlacement(unittest.TestCase):
    """T049: Door visual placement at centroid of crystal positions."""

    def test_centroid_calculation_level13(self):
        """Level 13 has 3 nodes at [420,280], [640,200], [560,440].
        Centroid = (540, 306.67)."""
        data = load_level_json("level_13.json", act=2)
        nodes = data["graph"]["nodes"]
        cx = sum(n["position"][0] for n in nodes) / len(nodes)
        cy = sum(n["position"][1] for n in nodes) / len(nodes)
        self.assertAlmostEqual(cx, 540.0, places=0)
        self.assertAlmostEqual(cy, 306.67, places=0)

    def test_all_act2_levels_have_positions(self):
        """All Act 2 levels must have graph nodes with positions."""
        for i in range(13, 17):
            filename = "level_%02d.json" % i
            try:
                data = load_level_json(filename, act=2)
            except FileNotFoundError:
                continue
            nodes = data.get("graph", {}).get("nodes", [])
            self.assertGreater(len(nodes), 0, f"{filename}: no nodes")
            for n in nodes:
                self.assertIn("position", n, f"{filename}: node missing position")


class TestSubgroupSelectorLogic(unittest.TestCase):
    """T049: SubgroupSelector validates subgroups and opens doors."""

    def setUp(self):
        """Load level 13 (S3) and discover all 6 keys."""
        self.data = load_level_json("level_13.json", act=2)
        sym_data = self.data["symmetries"]
        automorphisms = sym_data["automorphisms"]
        self.target_perms = {}
        for auto in automorphisms:
            self.target_perms[auto["id"]] = Permutation(auto["mapping"])

        self.key_ring = KeyRing(len(automorphisms))
        # Discover all keys in order: e, r1, r2, s01, s02, s12
        for auto in automorphisms:
            self.key_ring.add_key(Permutation(auto["mapping"]))

        self.selector = SubgroupSelectorSim(
            self.data["mechanics"]["inner_doors"],
            self.data["subgroups"],
            self.key_ring,
            self.target_perms,
        )

    def test_initial_state(self):
        self.assertEqual(self.selector.get_total_count(), 1)
        self.assertEqual(self.selector.get_opened_count(), 0)
        self.assertFalse(self.selector.is_all_doors_opened())

    def test_valid_subgroup_z3_rotations(self):
        """Selecting e, r1, r2 (indices 0,1,2) should be a valid subgroup."""
        self.selector.select_keys([0, 1, 2])
        result = self.selector.check_subgroup()
        self.assertTrue(result["is_subgroup"],
                        f"Z3 rotations should be a subgroup, got: {result}")

    def test_invalid_subgroup(self):
        """Selecting just r1, s01 should NOT be a subgroup."""
        self.selector.select_keys([1, 3])
        result = self.selector.check_subgroup()
        self.assertFalse(result["is_subgroup"])

    def test_open_door_with_correct_subgroup(self):
        """Opening the rotation_door with Z3 = {e, r1, r2}."""
        self.selector.select_keys([0, 1, 2])
        result = self.selector.try_open_door()
        self.assertTrue(result["opened"])
        self.assertEqual(result["door_id"], "rotation_door")
        self.assertTrue(self.selector.is_all_doors_opened())

    def test_open_door_with_wrong_subgroup(self):
        """Valid subgroup but wrong size won't open the door."""
        # {e} is a subgroup but not the right one (order 1 vs 3)
        self.selector.select_keys([0])
        result = self.selector.try_open_door()
        # check_subgroup for {e} alone: it IS a subgroup (trivial)
        # but doesn't match Z3_rotations (needs 3 elements)
        if result.get("opened"):
            self.fail("Should not open door with wrong subgroup")

    def test_open_door_with_non_subgroup_fails(self):
        """Non-subgroup selection should fail."""
        self.selector.select_keys([1, 3])  # r1, s01 — not a subgroup
        result = self.selector.try_open_door()
        self.assertFalse(result["opened"])
        self.assertIn("door_failed", self.selector.events)

    def test_door_cannot_be_opened_twice(self):
        """Once opened, same door can't be opened again."""
        self.selector.select_keys([0, 1, 2])
        r1 = self.selector.try_open_door()
        self.assertTrue(r1["opened"])

        # Try again
        self.selector.select_keys([0, 1, 2])
        r2 = self.selector.try_open_door()
        self.assertFalse(r2["opened"])


class TestCounterLabel(unittest.TestCase):
    """T049: Counter label shows keys AND doors progress."""

    def test_keys_only_act1(self):
        """Act 1 levels show only keys."""
        text = CounterLabelSim.format(3, 6, door_panel=None)
        self.assertEqual(text, "Ключи: 3 / 6")
        self.assertNotIn("Двери", text)

    def test_keys_and_doors_act2(self):
        """Act 2 levels show keys + doors."""
        data = load_level_json("level_13.json", act=2)
        key_ring = KeyRing(6)
        target_perms = {}
        for auto in data["symmetries"]["automorphisms"]:
            target_perms[auto["id"]] = Permutation(auto["mapping"])

        panel = SubgroupSelectorSim(
            data["mechanics"]["inner_doors"],
            data["subgroups"],
            key_ring,
            target_perms,
        )
        text = CounterLabelSim.format(2, 6, door_panel=panel)
        self.assertEqual(text, "Ключи: 2 / 6 | Двери: 0 / 1")

    def test_counter_after_door_opened(self):
        """Counter updates after door is opened."""
        data = load_level_json("level_13.json", act=2)
        target_perms = {}
        key_ring = KeyRing(6)
        for auto in data["symmetries"]["automorphisms"]:
            p = Permutation(auto["mapping"])
            target_perms[auto["id"]] = p
            key_ring.add_key(p)

        panel = SubgroupSelectorSim(
            data["mechanics"]["inner_doors"],
            data["subgroups"],
            key_ring,
            target_perms,
        )
        panel.select_keys([0, 1, 2])
        panel.try_open_door()

        text = CounterLabelSim.format(6, 6, door_panel=panel)
        self.assertEqual(text, "Ключи: 6 / 6 | Двери: 1 / 1")


class TestMomentOfUnderstanding(unittest.TestCase):
    """T049: 'Момент понимания' animation — only on first door ever."""

    def test_first_door_triggers_moment(self):
        moment = MomentOfUnderstandingSim()
        triggered = moment.on_door_opened("door1")
        self.assertTrue(triggered)
        self.assertTrue(moment.moment_played)

    def test_second_door_does_not_trigger(self):
        moment = MomentOfUnderstandingSim()
        moment.on_door_opened("door1")
        triggered = moment.on_door_opened("door2")
        self.assertFalse(triggered)

    def test_same_door_same_level_no_retrigger(self):
        moment = MomentOfUnderstandingSim()
        moment.on_door_opened("door1")
        triggered = moment.on_door_opened("door1")
        self.assertFalse(triggered)

    def test_flag_persists(self):
        """Flag should stay set after being triggered."""
        moment = MomentOfUnderstandingSim()
        self.assertFalse(moment.first_door_ever_opened)
        moment.on_door_opened("door1")
        self.assertTrue(moment.first_door_ever_opened)
        self.assertTrue(moment.moment_played)


class TestAct2LevelsHaveInnerDoors(unittest.TestCase):
    """T049: All Act 2 levels must define inner_doors in mechanics."""

    def test_all_act2_levels_have_inner_doors(self):
        """Levels 13-16 should have inner_doors."""
        for i in range(13, 17):
            filename = "level_%02d.json" % i
            try:
                data = load_level_json(filename, act=2)
            except FileNotFoundError:
                self.skipTest(f"{filename} not found")
                continue
            mechanics = data.get("mechanics", {})
            inner_doors = mechanics.get("inner_doors", [])
            self.assertGreater(len(inner_doors), 0,
                               f"{filename}: no inner_doors defined")

    def test_all_act2_levels_have_subgroups(self):
        """Levels 13-16 should have subgroups defined."""
        for i in range(13, 17):
            filename = "level_%02d.json" % i
            try:
                data = load_level_json(filename, act=2)
            except FileNotFoundError:
                continue
            subgroups = data.get("subgroups", [])
            self.assertGreater(len(subgroups), 0,
                               f"{filename}: no subgroups defined")
            # At least one subgroup should be an inner door
            door_sgs = [sg for sg in subgroups if sg.get("is_inner_door", False)]
            self.assertGreater(len(door_sgs), 0,
                               f"{filename}: no subgroup marked as inner_door")

    def test_inner_doors_reference_valid_subgroups(self):
        """Each inner door's required_subgroup must exist in subgroups."""
        for i in range(13, 17):
            filename = "level_%02d.json" % i
            try:
                data = load_level_json(filename, act=2)
            except FileNotFoundError:
                continue
            mechanics = data.get("mechanics", {})
            inner_doors = mechanics.get("inner_doors", [])
            subgroups = data.get("subgroups", [])
            sg_names = {sg["name"] for sg in subgroups}

            for door in inner_doors:
                req = door.get("required_subgroup", "")
                self.assertIn(req, sg_names,
                              f"{filename}: door '{door['id']}' references "
                              f"unknown subgroup '{req}'")


class TestAct1NoInnerDoors(unittest.TestCase):
    """T049: Act 1 levels should NOT have inner_doors (backward compatibility)."""

    def test_act1_no_inner_doors(self):
        """Levels 1-12 should not have inner_doors."""
        for i in range(1, 13):
            filename = "level_%02d.json" % i
            try:
                data = load_level_json(filename, act=1)
            except FileNotFoundError:
                continue
            mechanics = data.get("mechanics", {})
            inner_doors = mechanics.get("inner_doors", [])
            self.assertEqual(len(inner_doors), 0,
                             f"{filename}: Act 1 should not have inner_doors")


class TestDoorVisualAnimationSequence(unittest.TestCase):
    """T049: Door visual animation sequence (unlock/failure)."""

    def test_unlock_then_failure_on_other_door(self):
        """Multiple doors: unlock one, fail on another."""
        d1 = InnerDoorVisualSim("door_a", "Door A", 2, (100, 200))
        d2 = InnerDoorVisualSim("door_b", "Door B", 3, (300, 400))

        d1.play_unlock_animation()
        d2.play_failure_animation()

        self.assertEqual(d1.state, InnerDoorVisualSim.UNLOCKED)
        self.assertEqual(d2.state, InnerDoorVisualSim.LOCKED)
        self.assertEqual(d1.animation_log, ["unlock"])
        self.assertEqual(d2.animation_log, ["failure"])

    def test_multiple_failures_log(self):
        """Multiple failure attempts are all logged."""
        dv = InnerDoorVisualSim("door1", "Test", 3, (0, 0))
        dv.play_failure_animation()
        dv.play_failure_animation()
        dv.play_failure_animation()
        self.assertEqual(len(dv.animation_log), 3)
        self.assertTrue(all(a == "failure" for a in dv.animation_log))


class TestFullAct2Flow(unittest.TestCase):
    """T049: Full Act 2 flow: discover keys, select subgroup, open door."""

    def test_level13_full_flow(self):
        """Level 13: discover all 6 S3 keys, open Z3 rotation door."""
        data = load_level_json("level_13.json", act=2)
        automorphisms = data["symmetries"]["automorphisms"]
        target_perms = {}
        key_ring = KeyRing(len(automorphisms))

        # Discover all keys
        for auto in automorphisms:
            p = Permutation(auto["mapping"])
            target_perms[auto["id"]] = p
            key_ring.add_key(p)

        self.assertTrue(key_ring.is_complete())

        # Create selector
        selector = SubgroupSelectorSim(
            data["mechanics"]["inner_doors"],
            data["subgroups"],
            key_ring,
            target_perms,
        )

        # Counter should show keys + doors
        counter = CounterLabelSim.format(6, 6, selector)
        self.assertIn("Двери: 0 / 1", counter)

        # Select Z3 = {e, r1, r2} (indices 0, 1, 2)
        selector.select_keys([0, 1, 2])

        # Validate subgroup
        check = selector.check_subgroup()
        self.assertTrue(check["is_subgroup"])

        # Open door
        result = selector.try_open_door()
        self.assertTrue(result["opened"])
        self.assertEqual(result["door_id"], "rotation_door")

        # Level complete: all keys found + all doors opened
        self.assertTrue(key_ring.is_complete())
        self.assertTrue(selector.is_all_doors_opened())

        # Counter updated
        counter_after = CounterLabelSim.format(6, 6, selector)
        self.assertIn("Двери: 1 / 1", counter_after)

        # Moment of understanding
        moment = MomentOfUnderstandingSim()
        triggered = moment.on_door_opened("rotation_door")
        self.assertTrue(triggered)


if __name__ == "__main__":
    unittest.main()
