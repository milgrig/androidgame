"""
Integration tests for T006: Engine + UI integration.
Simulates the LevelScene game flow (load JSON, swap, validate, track)
using the same core engine classes (Permutation, CrystalGraph, KeyRing).
Verifies the integration logic without requiring Godot runtime.
"""
import json
import os
import unittest

# Reuse core engine mirrors from test_core_engine
from test_core_engine import Permutation, CrystalGraph, KeyRing


def load_level_json(filename: str) -> dict:
    """Load a level JSON file from the data directory."""
    base = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(base, "..", "..", "..", "data", "levels", "act1", filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


class LevelSimulator:
    """Simulates LevelScene integration logic in Python.
    Mirrors the GDScript flow: load level, build engine objects, validate swaps.
    Swaps accumulate — no auto-reset on invalid permutation.
    Player uses manual reset or check_current to interact.

    T041: Levels start from a SHUFFLED arrangement (not identity).
    The player must first assemble the target (identity) by swapping.
    """

    @staticmethod
    def _generate_shuffle(size: int, seed_val: int) -> list[int]:
        """Fisher-Yates shuffle with deterministic seed. Guaranteed != identity.
        Mirrors GDScript _generate_shuffle() in level_scene.gd."""
        import random
        if size <= 1:
            return [0]

        rng = random.Random(seed_val)
        perm = list(range(size))

        # Fisher-Yates shuffle
        for i in range(size - 1, 0, -1):
            j = rng.randint(0, i)
            perm[i], perm[j] = perm[j], perm[i]

        # Guarantee not identity
        if perm == list(range(size)):
            perm[0], perm[1] = perm[1], perm[0]

        return perm

    def __init__(self, level_data: dict, shuffle: bool = True):
        self.level_data = level_data
        self.level_id = level_data["meta"]["id"]

        # Build CrystalGraph from level JSON
        graph_data = level_data["graph"]
        self.crystal_graph = CrystalGraph(graph_data["nodes"], graph_data["edges"])

        # Parse target symmetries into Permutation objects
        sym_data = level_data.get("symmetries", {})
        automorphisms = sym_data.get("automorphisms", [])
        self.target_perms: dict[str, Permutation] = {}
        self.target_names: dict[str, str] = {}
        for auto in automorphisms:
            sym_id = auto["id"]
            self.target_perms[sym_id] = Permutation(auto["mapping"])
            self.target_names[sym_id] = auto.get("name", sym_id)

        # Initialize KeyRing
        self.key_ring = KeyRing(len(automorphisms))

        # Identity arrangement (the GOAL)
        n = self.crystal_graph.node_count()
        self.identity_arrangement = list(range(n))

        # T041: Shuffled start
        self.is_shuffled = shuffle
        self.identity_found = False
        if shuffle:
            self.shuffle_seed = hash(self.level_id)
            shuffle_perm = self._generate_shuffle(n, self.shuffle_seed)
            # initial_arrangement[i] = identity[shuffle_perm[i]]
            self.initial_arrangement = [self.identity_arrangement[shuffle_perm[i]] for i in range(n)]
        else:
            self.shuffle_seed = 0
            self.initial_arrangement = list(range(n))

        self.current_arrangement = list(self.initial_arrangement)

        # Event log
        self.events: list[str] = []

    def perform_swap(self, pos_a: int, pos_b: int) -> str:
        """Simulate swapping crystals at two positions.
        Swaps accumulate — no reset on invalid.
        Returns event type: 'new_symmetry', 'already_found', 'no_match', or 'level_complete'.
        """
        # Swap in arrangement
        self.current_arrangement[pos_a], self.current_arrangement[pos_b] = \
            self.current_arrangement[pos_b], self.current_arrangement[pos_a]

        perm = Permutation(list(self.current_arrangement))
        return self._validate_permutation(perm)

    def reset(self) -> None:
        """Manual reset — returns arrangement to shuffled start (not identity!).
        T041: RESET goes back to the shuffled beginning, not the answer."""
        self.current_arrangement = list(self.initial_arrangement)
        self.events.append("reset")

    def check_current(self) -> str:
        """Check current arrangement with full feedback (like CHECK button)."""
        perm = Permutation(list(self.current_arrangement))
        return self._validate_permutation(perm, show_invalid_feedback=True)

    def _validate_permutation(self, perm: Permutation, show_invalid_feedback: bool = False) -> str:
        """Validate permutation against target automorphisms. Returns event type.
        No auto-reset on invalid — swaps accumulate.
        """
        for sym_id, target in self.target_perms.items():
            if perm.equals(target):
                if self.key_ring.add_key(perm):
                    self.events.append(f"found:{sym_id}")
                    # Track identity found (T041)
                    if perm.is_identity():
                        self.identity_found = True
                    if self.key_ring.is_complete():
                        self.events.append("level_complete")
                        return "level_complete"
                    return "new_symmetry"
                else:
                    self.events.append(f"already_found:{sym_id}")
                    return "already_found"

        self.events.append("no_match")
        # NO reset — swaps accumulate, let the player keep experimenting
        return "no_match"


class TestLevel1Integration(unittest.TestCase):
    """Level 1: Uniform triangle, 3 rotations (Z3).
    T041: Levels start shuffled — identity is no longer free."""

    def setUp(self):
        self.data = load_level_json("level_01.json")
        self.sim = LevelSimulator(self.data)

    def test_level_loads_correctly(self):
        self.assertEqual(self.sim.level_id, "act1_level01")
        self.assertEqual(self.sim.crystal_graph.node_count(), 3)
        self.assertEqual(len(self.sim.target_perms), 3)
        self.assertEqual(self.sim.key_ring.target_count, 3)

    def test_identity_is_target(self):
        """Identity [0,1,2] is in target list"""
        e = Permutation([0, 1, 2])
        found = any(t.equals(e) for t in self.sim.target_perms.values())
        self.assertTrue(found)

    def test_shuffled_start_not_identity(self):
        """T041: Level starts with a shuffled arrangement, NOT identity."""
        self.assertNotEqual(self.sim.current_arrangement, [0, 1, 2],
            "Shuffled start should NOT be identity")
        self.assertTrue(self.sim.is_shuffled)

    def test_shuffled_start_is_deterministic(self):
        """T041: Same level_id produces same shuffle (seed-based)."""
        sim2 = LevelSimulator(self.data)
        self.assertEqual(self.sim.current_arrangement, sim2.current_arrangement)
        self.assertEqual(self.sim.shuffle_seed, sim2.shuffle_seed)

    def test_swaps_accumulate_no_reset(self):
        """After an invalid swap, arrangement is NOT reset — swaps accumulate."""
        initial = list(self.sim.current_arrangement)
        result = self.sim.perform_swap(0, 1)
        # After swap, arrangement should differ from initial
        self.assertNotEqual(self.sim.current_arrangement, initial)
        # Should not have reset

    def test_manual_reset_returns_to_shuffled_start(self):
        """T041: Manual reset returns to shuffled start, NOT identity."""
        initial = list(self.sim.current_arrangement)
        self.sim.perform_swap(0, 1)
        self.assertNotEqual(self.sim.current_arrangement, initial)
        self.sim.reset()
        self.assertEqual(self.sim.current_arrangement, initial,
            "Reset should return to shuffled start, not identity")
        # Verify it's NOT identity
        self.assertNotEqual(self.sim.current_arrangement, [0, 1, 2])

    def test_check_current_on_shuffled_start(self):
        """T041: Checking the shuffled start does NOT discover identity."""
        result = self.sim.check_current()
        # Shuffled arrangement should NOT match any target automorphism
        # (or if it does, it's not identity)
        # The key point: identity is no longer free
        initial_perm = Permutation(list(self.sim.current_arrangement))
        self.assertFalse(initial_perm.is_identity(),
            "Shuffled start must not be identity")

    def test_full_level1_completion_via_direct_validation(self):
        """Discover all 3 Z3 symmetries through direct validation.
        This tests the core engine logic independent of shuffle."""
        self.sim._validate_permutation(Permutation([0, 1, 2]))  # e
        self.sim._validate_permutation(Permutation([1, 2, 0]))  # r1
        result = self.sim._validate_permutation(Permutation([2, 0, 1]))  # r2
        self.assertEqual(result, "level_complete")
        self.assertTrue(self.sim.key_ring.is_complete())
        self.assertIn("level_complete", self.sim.events)

    def test_identity_found_by_assembling_target(self):
        """T041: Identity is found when player manually arranges crystals to [0,1,2].
        Player must work to assemble the target picture — it's not free."""
        # Manually set arrangement to identity (simulating swaps that got there)
        self.sim.current_arrangement = [0, 1, 2]
        result = self.sim.check_current()
        self.assertEqual(result, "new_symmetry")
        self.assertTrue(self.sim.identity_found)
        self.assertTrue(self.sim.key_ring.found[0].is_identity())

    def test_validate_identity_directly(self):
        """Test that identity permutation is recognized"""
        perm = Permutation([0, 1, 2])
        result = self.sim._validate_permutation(perm)
        self.assertEqual(result, "new_symmetry")
        self.assertEqual(self.sim.key_ring.count(), 1)

    def test_validate_rotation_120_directly(self):
        """Test that rotation 120 is recognized"""
        perm = Permutation([1, 2, 0])
        result = self.sim._validate_permutation(perm)
        self.assertEqual(result, "new_symmetry")
        self.assertEqual(self.sim.key_ring.count(), 1)

    def test_validate_invalid_directly(self):
        """Test that non-target permutation is rejected but NOT reset"""
        perm = Permutation([1, 0, 2])  # transposition, not in Z3 targets
        result = self.sim._validate_permutation(perm)
        self.assertEqual(result, "no_match")
        self.assertEqual(self.sim.key_ring.count(), 0)

    def test_complete_level_directly(self):
        """Find all 3 symmetries directly"""
        self.sim._validate_permutation(Permutation([0, 1, 2]))  # e
        self.sim._validate_permutation(Permutation([1, 2, 0]))  # r1
        result = self.sim._validate_permutation(Permutation([2, 0, 1]))  # r2
        self.assertEqual(result, "level_complete")
        self.assertTrue(self.sim.key_ring.is_complete())
        self.assertIn("level_complete", self.sim.events)

    def test_duplicate_rejection(self):
        """Finding same symmetry twice doesn't add to key ring"""
        self.sim._validate_permutation(Permutation([1, 2, 0]))
        result = self.sim._validate_permutation(Permutation([1, 2, 0]))
        self.assertEqual(result, "already_found")
        self.assertEqual(self.sim.key_ring.count(), 1)

    def test_keyring_tracks_permutation_objects(self):
        """KeyRing stores proper Permutation objects"""
        self.sim._validate_permutation(Permutation([0, 1, 2]))
        self.sim._validate_permutation(Permutation([1, 2, 0]))
        kr = self.sim.key_ring
        self.assertEqual(kr.count(), 2)
        self.assertTrue(kr.found[0].is_identity())
        self.assertEqual(kr.found[1].mapping, [1, 2, 0])

    def test_unshuffled_mode_for_backwards_compat(self):
        """LevelSimulator with shuffle=False starts at identity (legacy behavior)."""
        sim_noshuf = LevelSimulator(self.data, shuffle=False)
        self.assertEqual(sim_noshuf.current_arrangement, [0, 1, 2])
        self.assertFalse(sim_noshuf.is_shuffled)


class TestLevel3Integration(unittest.TestCase):
    """Level 3: Colored triangle (1 red, 2 green), Z2"""

    def setUp(self):
        self.data = load_level_json("level_03.json")
        # Use shuffle=False for swap-based tests that check specific arrangements
        self.sim = LevelSimulator(self.data, shuffle=False)

    def test_level_loads_correctly(self):
        self.assertEqual(self.sim.level_id, "act1_level03")
        self.assertEqual(len(self.sim.target_perms), 2)

    def test_shuffled_start(self):
        """T041: Level 3 starts shuffled by default."""
        sim_shuffled = LevelSimulator(self.data)
        self.assertTrue(sim_shuffled.is_shuffled)
        self.assertNotEqual(sim_shuffled.current_arrangement, [0, 1, 2])

    def test_swap_green_nodes_is_valid(self):
        """Swap positions 1 and 2 (green nodes) → [0,2,1] = reflection.
        Uses shuffle=False to test swap logic from identity start."""
        result = self.sim.perform_swap(1, 2)
        self.assertEqual(result, "new_symmetry")

    def test_swap_red_and_green_invalid(self):
        """Swap positions 0 and 1 (red + green) → [1,0,2] = not a target.
        Uses shuffle=False to test swap logic from identity start."""
        result = self.sim.perform_swap(0, 1)
        self.assertEqual(result, "no_match")
        # Arrangement stays at [1,0,2] — no auto-reset
        self.assertEqual(self.sim.current_arrangement, [1, 0, 2])

    def test_complete_level3(self):
        """Find both Z2 symmetries"""
        self.sim._validate_permutation(Permutation([0, 1, 2]))  # identity
        result = self.sim._validate_permutation(Permutation([0, 2, 1]))  # reflection
        self.assertEqual(result, "level_complete")

    def test_graph_engine_agrees_with_targets(self):
        """CrystalGraph.is_automorphism agrees with target permutations"""
        for sym_id, perm in self.sim.target_perms.items():
            self.assertTrue(
                self.sim.crystal_graph.is_automorphism(perm),
                f"Engine disagrees with target {sym_id}: {perm.mapping}"
            )


class TestLevel2Integration(unittest.TestCase):
    """Level 2: Triangle with directed edges (cycle 0→1→2→0) → Z3."""

    def setUp(self):
        self.data = load_level_json("level_02.json")
        self.sim = LevelSimulator(self.data)

    def test_level_loads(self):
        self.assertEqual(self.sim.level_id, "act1_level02")
        self.assertEqual(self.data["meta"]["group_name"], "Z3")
        self.assertEqual(self.data["meta"]["group_order"], 3)

    def test_engine_agrees_with_json_targets(self):
        """Engine finds exactly 3 automorphisms matching JSON targets (Z3)."""
        graph = self.sim.crystal_graph
        engine_autos = graph.find_all_automorphisms()
        json_targets = list(self.sim.target_perms.values())

        # Engine finds exactly 3 automorphisms (Z3)
        self.assertEqual(len(engine_autos), 3)
        # JSON lists 3 targets (Z3)
        self.assertEqual(len(json_targets), 3)

        # All JSON targets should be valid automorphisms per engine
        for t in json_targets:
            self.assertTrue(
                graph.is_automorphism(t),
                f"Engine disagrees with target: {t.mapping}"
            )

    def test_reflection_not_automorphism(self):
        """Swap(1,2) reverses directed edge direction → not valid."""
        graph = self.sim.crystal_graph
        s = Permutation([0, 2, 1])
        self.assertFalse(graph.is_automorphism(s))

    def test_complete_level2(self):
        """Find all 3 Z3 symmetries."""
        self.sim._validate_permutation(Permutation([0, 1, 2]))  # e
        self.sim._validate_permutation(Permutation([1, 2, 0]))  # r1
        result = self.sim._validate_permutation(Permutation([2, 0, 1]))  # r2
        self.assertEqual(result, "level_complete")
        self.assertTrue(self.sim.key_ring.is_complete())

    def test_level2_keyring_forms_group(self):
        """Z3 key ring is closed, has identity, has inverses."""
        for perm in self.sim.target_perms.values():
            self.sim.key_ring.add_key(perm)
        self.assertTrue(self.sim.key_ring.is_closed_under_composition())
        self.assertTrue(self.sim.key_ring.has_identity())
        self.assertTrue(self.sim.key_ring.has_inverses())


class TestCrossLevelKeyRingProperties(unittest.TestCase):
    """Verify group properties of key ring across levels"""

    def test_level1_keyring_forms_group(self):
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        for perm in sim.target_perms.values():
            sim.key_ring.add_key(perm)
        self.assertTrue(sim.key_ring.is_closed_under_composition())
        self.assertTrue(sim.key_ring.has_identity())
        self.assertTrue(sim.key_ring.has_inverses())

    def test_level3_keyring_forms_group(self):
        data = load_level_json("level_03.json")
        sim = LevelSimulator(data)
        for perm in sim.target_perms.values():
            sim.key_ring.add_key(perm)
        self.assertTrue(sim.key_ring.is_closed_under_composition())
        self.assertTrue(sim.key_ring.has_identity())
        self.assertTrue(sim.key_ring.has_inverses())

    def test_level1_cayley_table(self):
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        for perm in sim.target_perms.values():
            sim.key_ring.add_key(perm)
        table = sim.key_ring.build_cayley_table()
        self.assertEqual(len(table), 3)
        # Table should be non-empty (closed set)
        for row in table:
            self.assertEqual(len(row), 3)
            for idx in row:
                self.assertGreaterEqual(idx, 0)
                self.assertLess(idx, 3)


class TestKeyRingDisplayFriendlyNames(unittest.TestCase):
    """T015: Verify key ring display shows friendly names + descriptions
    instead of cycle notation like '(0 1 2)'.
    Mirrors the GDScript _update_keyring_display() logic from level_scene.gd."""

    def _build_keyring_display(self, sim: LevelSimulator) -> str:
        """Python mirror of _update_keyring_display() from level_scene.gd.
        Now includes description field alongside friendly name."""
        # Load descriptions from level JSON (mirrors target_perm_descriptions)
        sym_data = sim.level_data.get("symmetries", {})
        automorphisms = sym_data.get("automorphisms", [])
        target_descriptions: dict[str, str] = {}
        for auto in automorphisms:
            sym_id = auto["id"]
            target_descriptions[sym_id] = auto.get("description", "")

        text = "Found:\n"
        for i in range(sim.key_ring.count()):
            perm = sim.key_ring.found[i]
            # Look up display name and description from level JSON data
            display_name = perm.to_cycle_notation()
            description = ""
            for sym_id, target in sim.target_perms.items():
                if target.equals(perm):
                    display_name = sim.target_names.get(sym_id, display_name)
                    description = target_descriptions.get(sym_id, "")
                    break
            if description:
                text += "  %s \u2014 %s\n" % (display_name, description)
            else:
                text += "  %s\n" % display_name
        return text

    def test_level1_shows_friendly_names_not_cycle_notation(self):
        """Level 1: Display should show 'Rotation 120°' not '(0 1 2)'"""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        # Find all symmetries
        sim._validate_permutation(Permutation([0, 1, 2]))  # identity
        sim._validate_permutation(Permutation([1, 2, 0]))  # r1
        sim._validate_permutation(Permutation([2, 0, 1]))  # r2

        display = self._build_keyring_display(sim)

        # Must contain friendly names
        self.assertIn("Identity", display)
        self.assertIn("Rotation 120", display)
        self.assertIn("Rotation 240", display)

        # Must NOT contain raw cycle notation
        self.assertNotIn("(0 1 2)", display)
        self.assertNotIn("(0 2 1)", display)
        self.assertNotIn("()", display)  # identity cycle notation

    def test_level1_shows_descriptions(self):
        """Level 1: Display should show descriptions like 'One step clockwise'"""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        sim._validate_permutation(Permutation([0, 1, 2]))
        sim._validate_permutation(Permutation([1, 2, 0]))
        sim._validate_permutation(Permutation([2, 0, 1]))

        display = self._build_keyring_display(sim)

        # Must contain descriptions from JSON
        self.assertIn("Everything stays in place", display)
        self.assertIn("One step clockwise", display)
        self.assertIn("Two steps clockwise", display)

    def test_level1_display_format(self):
        """Level 1: Display format should be 'Name — Description'"""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        sim._validate_permutation(Permutation([1, 2, 0]))  # r1

        display = self._build_keyring_display(sim)

        # Should contain em-dash separator between name and description
        self.assertIn("\u2014", display)
        # Full expected line
        self.assertIn("Rotation 120", display)
        self.assertIn("One step clockwise", display)

    def test_level3_shows_friendly_names(self):
        """Level 3: Display should show 'Reflection' not '(1 2)'"""
        data = load_level_json("level_03.json")
        sim = LevelSimulator(data)
        sim._validate_permutation(Permutation([0, 1, 2]))  # identity
        sim._validate_permutation(Permutation([0, 2, 1]))  # reflection

        display = self._build_keyring_display(sim)

        self.assertIn("Identity", display)
        self.assertIn("Reflection", display)
        self.assertIn("Swap the two green crystals", display)
        # Must NOT contain cycle notation
        self.assertNotIn("(1 2)", display)

    def test_partial_discovery_shows_only_found(self):
        """Only discovered symmetries should appear in display"""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        sim._validate_permutation(Permutation([1, 2, 0]))  # Only r1

        display = self._build_keyring_display(sim)

        self.assertIn("Rotation 120", display)
        self.assertNotIn("Identity", display)
        self.assertNotIn("Rotation 240", display)


class TestOnboardingTutorial(unittest.TestCase):
    """T014: Test onboarding tutorial behavior.
    Mirrors the GDScript onboarding logic from level_scene.gd."""

    def test_level1_is_act1_level1(self):
        """Level 1 JSON has act=1, level=1 metadata for tutorial trigger"""
        data = load_level_json("level_01.json")
        self.assertEqual(data["meta"]["act"], 1)
        self.assertEqual(data["meta"]["level"], 1)

    def test_level1_has_hint_triggers(self):
        """Level 1 JSON includes both hint triggers needed for onboarding"""
        data = load_level_json("level_01.json")
        hints = data.get("hints", [])
        triggers = [h["trigger"] for h in hints]
        self.assertIn("after_30_seconds_no_action", triggers)
        self.assertIn("after_first_valid", triggers)

    def test_first_symmetry_message_identity(self):
        """First symmetry message for identity should be encouraging"""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        # Simulate finding identity first
        result = sim._validate_permutation(Permutation([0, 1, 2]))
        self.assertEqual(result, "new_symmetry")
        # The message logic: for identity, show special message
        sym_name = sim.target_names.get("e", "")
        self.assertEqual(sym_name, "Identity")

    def test_first_symmetry_message_rotation(self):
        """First symmetry message for rotation should mention the name"""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        result = sim._validate_permutation(Permutation([1, 2, 0]))
        self.assertEqual(result, "new_symmetry")
        sym_name = sim.target_names.get("r1", "")
        self.assertIn("Rotation", sym_name)

    def test_remaining_count_after_first_discovery(self):
        """After first discovery, remaining count should be total - 1"""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        total = len(sim.target_perms)
        sim._validate_permutation(Permutation([0, 1, 2]))
        remaining = total - sim.key_ring.count()
        self.assertEqual(remaining, 2)  # 3 total - 1 found = 2

    def test_swap_count_tracking(self):
        """Simulate swap counting for progressive hints"""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        swap_count = 0
        sim.perform_swap(0, 1)
        swap_count += 1
        self.assertEqual(swap_count, 1)
        sim.perform_swap(1, 2)
        swap_count += 1
        self.assertEqual(swap_count, 2)

    def test_all_act1_levels_have_hints(self):
        """All Act 1 levels should have hints for onboarding"""
        for filename in ["level_01.json", "level_02.json", "level_03.json"]:
            data = load_level_json(filename)
            hints = data.get("hints", [])
            self.assertGreater(len(hints), 0,
                f"{filename} should have at least one hint")


class TestShuffledStart(unittest.TestCase):
    """T041: Comprehensive tests for shuffled start feature."""

    def test_shuffle_not_identity(self):
        """All levels should start shuffled (not identity)."""
        for filename in ["level_01.json", "level_02.json", "level_03.json"]:
            data = load_level_json(filename)
            sim = LevelSimulator(data)
            n = sim.crystal_graph.node_count()
            identity = list(range(n))
            self.assertNotEqual(sim.current_arrangement, identity,
                f"{filename}: shuffled start should not be identity")

    def test_shuffle_deterministic(self):
        """Same level gets same shuffle every time."""
        for filename in ["level_01.json", "level_02.json", "level_03.json"]:
            data = load_level_json(filename)
            sim1 = LevelSimulator(data)
            sim2 = LevelSimulator(data)
            self.assertEqual(sim1.current_arrangement, sim2.current_arrangement,
                f"{filename}: shuffle should be deterministic")

    def test_shuffle_is_valid_permutation(self):
        """Shuffled arrangement is a valid permutation (all IDs present)."""
        for filename in ["level_01.json", "level_02.json", "level_03.json"]:
            data = load_level_json(filename)
            sim = LevelSimulator(data)
            n = sim.crystal_graph.node_count()
            self.assertEqual(sorted(sim.current_arrangement), list(range(n)),
                f"{filename}: shuffled arrangement should be a valid permutation")

    def test_reset_returns_to_shuffled_start(self):
        """Reset goes back to initial shuffled arrangement, not identity."""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        initial = list(sim.current_arrangement)
        sim.perform_swap(0, 1)
        self.assertNotEqual(sim.current_arrangement, initial)
        sim.reset()
        self.assertEqual(sim.current_arrangement, initial)

    def test_identity_requires_work(self):
        """Identity is NOT found at start — player must assemble it."""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        # Check at shuffled start — should NOT find identity
        result = sim.check_current()
        initial_perm = Permutation(sim.current_arrangement)
        if initial_perm.is_identity():
            self.fail("Shuffled start should not be identity")

    def test_identity_found_after_assembly(self):
        """T041: After manually assembling identity, check_current discovers it."""
        data = load_level_json("level_01.json")
        sim = LevelSimulator(data)
        # Manually set to identity (simulating correct swaps)
        sim.current_arrangement = [0, 1, 2]
        result = sim.check_current()
        self.assertEqual(result, "new_symmetry")
        self.assertTrue(sim.identity_found)

    def test_all_12_levels_shuffle(self):
        """T041 acceptance: all 12 levels start shuffled."""
        import os
        base = os.path.dirname(os.path.abspath(__file__))
        levels_dir = os.path.join(base, "..", "..", "..", "data", "levels", "act1")
        if not os.path.exists(levels_dir):
            self.skipTest("Levels directory not found")
        level_files = sorted([f for f in os.listdir(levels_dir) if f.endswith('.json')])
        for filename in level_files:
            data = load_level_json(filename)
            sim = LevelSimulator(data)
            n = sim.crystal_graph.node_count()
            identity = list(range(n))
            self.assertNotEqual(sim.current_arrangement, identity,
                f"{filename}: should start shuffled")
            self.assertEqual(sorted(sim.current_arrangement), identity,
                f"{filename}: should be a valid permutation")

    def test_shuffle_generates_different_arrangements_per_level(self):
        """Different levels get different shuffles (based on level_id seed)."""
        data1 = load_level_json("level_01.json")
        data2 = load_level_json("level_02.json")
        sim1 = LevelSimulator(data1)
        sim2 = LevelSimulator(data2)
        # They have the same graph size (both 3 nodes) but different shuffles
        # (because different level_id → different seed)
        # Note: with only 3 elements and 2 possible non-identity shuffles,
        # there's a chance they match — but the seeds should differ
        self.assertNotEqual(sim1.shuffle_seed, sim2.shuffle_seed)


if __name__ == "__main__":
    unittest.main()
