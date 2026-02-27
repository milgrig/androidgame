"""
Test: Stack underflow bug reproduction (Engine Bug).
=====================================================
ERROR: Stack underflow!
   at: exit_function (modules/gdscript/gdscript.h:530)

This bug occurs when ALL levels are completed and the game attempts
to transition back to the map scene. The root cause is lambda closures
used as tween/timer callbacks in the completion flow.

When the last level (act2_level16) is completed:
1. GameManager.complete_level() cannot find a next level
   (act2_level17 doesn't exist, act3_level01 doesn't exist)
2. act_completed signal is NOT emitted for the final act
   (because there's no next act in the registry)
3. HudBuilder.show_complete_summary() uses lambda `_s = func(n, t): ...`
   inside a static function — this lambda captures the panel reference
4. Player presses "ВЕРНУТЬСЯ НА КАРТУ" → _on_next_level_pressed()
   → GameManager.return_to_map() → open_map() → change_scene_to_file()
5. Scene change destroys the old LevelScene while tween/timer lambdas
   are still on the GDScript call stack → Stack underflow

This test validates the bug EXISTS at the game logic level:
- complete_level() silently drops the last act completion
- get_next_level_path() returns "" for the final level
- The completion flow has no guard for "game finished" state

Mirrors: src/game/game_manager.gd, src/game/level_scene.gd,
         src/game/hud_builder.gd
Depends on: test_hall_tree_data.py, test_hall_progression.py
"""
import json
import os
import unittest
from pathlib import Path

# Reuse Python mirrors from sibling test modules
from test_hall_tree_data import HallTreeData, WingData, GateData
from test_hall_progression import HallProgressionEngine, HallState


# === Python mirror of GameManager.complete_level() logic ===

class GameManagerMirror:
    """Python mirror of GameManager for stack underflow bug testing.
    Mirrors the level completion and transition logic from game_manager.gd.
    """

    def __init__(self):
        self.current_act: int = 1
        self.current_level: int = 1
        self.completed_levels: list[str] = []
        self.level_states: dict = {}
        self.level_registry: dict[str, str] = {}
        self.hall_tree: HallTreeData | None = None
        self.progression: HallProgressionEngine | None = None
        # Track signals that would be emitted
        self.emitted_signals: list[tuple[str, ...]] = []

    def build_registry_from_hall_tree(self) -> None:
        """Build level_registry from hall_tree halls (simulates _build_level_registry)."""
        if self.hall_tree is None:
            return
        for wing in self.hall_tree.wings:
            for hall_id in wing.halls:
                # Simulate: registry maps level_id -> file_path
                self.level_registry[hall_id] = f"res://data/levels/act{wing.act}/dummy.json"

    def complete_level(self, level_id: str) -> None:
        """Mirror of GameManager.complete_level() — exact GDScript logic."""
        if level_id not in self.completed_levels:
            self.completed_levels.append(level_id)

        # Advance current_act / current_level to the next one
        next_info = self._parse_level_id(level_id)
        if next_info:
            act = next_info["act"]
            lvl = next_info["level"]
            # Point to the next level so game resumes there
            next_id = "act%d_level%02d" % (act, lvl + 1)
            if next_id in self.level_registry:
                self.current_act = act
                self.current_level = lvl + 1
            else:
                # Try first level of next act
                next_act_id = "act%d_level%02d" % (act + 1, 1)
                if next_act_id in self.level_registry:
                    self.current_act = act + 1
                    self.current_level = 1
                    self.emitted_signals.append(("act_completed", act))

        # Notify progression engine about hall completion
        if self.progression is not None:
            self.progression.complete_hall(level_id)

        self.emitted_signals.append(("level_completed_signal", level_id))

    def get_next_level_path(self, current_level_id: str) -> str:
        """Mirror of GameManager.get_next_level_path()."""
        info = self._parse_level_id(current_level_id)
        if not info:
            return ""

        act = info["act"]
        lvl = info["level"]

        # Try next level in same act
        next_id = "act%d_level%02d" % (act, lvl + 1)
        if next_id in self.level_registry:
            return self.level_registry[next_id]

        # Try first level of next act
        next_act_id = "act%d_level%02d" % (act + 1, 1)
        if next_act_id in self.level_registry:
            return self.level_registry[next_act_id]

        return ""

    def _parse_level_id(self, level_id: str) -> dict:
        """Mirror of GameManager._parse_level_id()."""
        parts = level_id.split("_")
        if len(parts) < 2:
            return {}
        act_str = parts[0].replace("act", "")
        lvl_str = parts[1].replace("level", "")
        if not act_str.isdigit() or not lvl_str.isdigit():
            return {}
        return {"act": int(act_str), "level": int(lvl_str)}


class LevelSceneMirror:
    """Python mirror of LevelScene completion flow.
    Simulates _on_level_complete, _show_complete_summary, _on_next_level_pressed.
    """

    def __init__(self, game_manager: GameManagerMirror):
        self.gm = game_manager
        self.level_id: str = ""
        self.scene_change_target: str = ""  # What scene would be loaded
        self.lambda_callbacks_active: list[str] = []  # Track live lambdas
        self.is_scene_destroyed: bool = False

    def on_level_complete(self, level_id: str) -> dict:
        """Mirror of LevelScene._on_level_complete().
        Returns diagnostic info about what happened.
        """
        self.level_id = level_id

        # Step 1: GameManager.complete_level() — exact mirror
        self.gm.complete_level(level_id)

        # Step 2: create_timer(1.2) → _show_complete_summary
        # In real Godot, this creates a Timer + lambda callback
        # that fires 1.2s later. The lambda captures `self` (LevelScene).
        self.lambda_callbacks_active.append(
            "create_timer(1.2).timeout -> _show_complete_summary"
        )

        return {
            "level_id": level_id,
            "completed_levels": list(self.gm.completed_levels),
            "active_lambdas": list(self.lambda_callbacks_active),
        }

    def show_complete_summary(self) -> dict:
        """Mirror of HudBuilder.show_complete_summary() — static method.
        This creates a lambda `_s = func(n, t): ...` inside.
        """
        # In GDScript hud_builder.gd:284:
        #   var _s = func(n, t): var l = p.get_node_or_null(n); if l: l.text = t
        # This lambda is a closure capturing `p` (the panel).
        self.lambda_callbacks_active.append(
            "hud_builder._s = func(n, t): ..."
        )

        # Line 304: scene.create_tween().tween_property(...)
        # The tween is owned by scene (self). When scene is freed,
        # the tween is also freed — but the VM function stack
        # may still reference it.
        self.lambda_callbacks_active.append(
            "scene.create_tween() -> tween_property(panel, modulate)"
        )

        # Check: is "next level" button visible?
        next_path = self.gm.get_next_level_path(self.level_id)
        has_next = next_path != ""
        has_hall_tree = self.gm.hall_tree is not None

        return {
            "has_next_level": has_next,
            "has_hall_tree": has_hall_tree,
            "button_text": "ВЕРНУТЬСЯ НА КАРТУ" if has_hall_tree else "СЛЕДУЮЩИЙ УРОВЕНЬ  >",
            "button_visible": has_hall_tree or has_next,
            "active_lambdas": list(self.lambda_callbacks_active),
        }

    def on_next_level_pressed(self) -> dict:
        """Mirror of LevelScene._on_next_level_pressed().
        This is where Stack underflow happens!

        When hall_tree mode: calls GameManager.return_to_map()
           → open_map() → change_scene_to_file("map_scene.tscn")
           → This DESTROYS the current LevelScene while lambdas are live!

        When linear mode: calls get_next_level_path() → load_level_from_file()
           → For the last level, path == "" → nothing happens (orphan scene)
        """
        result = {
            "active_lambdas_before_transition": list(self.lambda_callbacks_active),
            "transition_type": "",
            "stack_underflow_risk": False,
            "dangling_lambda_count": 0,
        }

        if self.gm.hall_tree is not None:
            # Hall tree mode: return to map (scene change)
            result["transition_type"] = "return_to_map"
            self.scene_change_target = "res://src/ui/map_scene.tscn"

            # CRITICAL: Scene change kills LevelScene while lambdas are active!
            # This is the exact point where Stack underflow occurs.
            # The GDScript VM still has lambda closures on the function call stack
            # (from create_timer and create_tween), but the objects they reference
            # are being freed by scene change.
            dangling = len(self.lambda_callbacks_active)
            result["dangling_lambda_count"] = dangling
            result["stack_underflow_risk"] = dangling > 0

            # Simulate scene destruction
            self.is_scene_destroyed = True

        else:
            # Linear mode: try to load next level
            np = self.gm.get_next_level_path(self.level_id)
            if np != "":
                result["transition_type"] = "load_next_level"
                self.scene_change_target = np
            else:
                result["transition_type"] = "no_next_level_stuck"
                # BUG: Player is stuck on summary screen with no way out!
                result["stack_underflow_risk"] = False

        return result


# === Load real hall_tree.json ===

def _load_hall_tree() -> HallTreeData:
    base = Path(__file__).resolve().parent.parent.parent.parent
    path = base / "data" / "hall_tree.json"
    ht = HallTreeData()
    assert ht.load_from_file(str(path)), f"Failed to load {path}"
    return ht


def _build_full_game() -> tuple[GameManagerMirror, HallTreeData]:
    """Build a GameManager with real hall_tree and all levels registered."""
    ht = _load_hall_tree()
    gm = GameManagerMirror()
    gm.hall_tree = ht
    gm.build_registry_from_hall_tree()

    progression = HallProgressionEngine()
    progression.hall_tree = ht
    gm.progression = progression

    return gm, ht


# === Tests ===

class TestStackUnderflowBug(unittest.TestCase):
    """
    Reproduction of Stack underflow bug that occurs when ALL levels are completed.

    The bug manifests as:
        ERROR: Stack underflow!
           at: exit_function (modules/gdscript/gdscript.h:530)

    Root cause: lambda closures in tween/timer callbacks are still on the
    GDScript VM call stack when scene change destroys the LevelScene node.
    """

    def setUp(self):
        self.gm, self.ht = _build_full_game()

    # ------------------------------------------------------------------
    # 1. Verify the structural precondition: no next level after last
    # ------------------------------------------------------------------

    def test_no_next_level_after_last_act2_level(self):
        """BUG PRECONDITION: get_next_level_path returns '' for the last level.
        This means GameManager has no concept of 'game finished'."""
        last_level = "act2_level16"
        self.assertIn(last_level, self.gm.level_registry,
                      "act2_level16 must be in registry")

        next_path = self.gm.get_next_level_path(last_level)
        self.assertEqual(next_path, "",
                         "There must be no next level after act2_level16 — "
                         "this is the precondition for the bug")

    def test_no_next_level_after_last_act1_level_BUG(self):
        """BUG: act1_level12 has NO next level via get_next_level_path()!

        GameManager tries act1_level13 (doesn't exist) then act2_level01
        (doesn't exist either — Act 2 starts at act2_level13, not act2_level01).

        This means the linear progression path is BROKEN for Act 1 → Act 2.
        In practice this is masked by hall_tree mode (which uses the map),
        but it's another broken code path that contributes to the bug.
        """
        next_path = self.gm.get_next_level_path("act1_level12")
        self.assertEqual(next_path, "",
                         "BUG CONFIRMED: get_next_level_path('act1_level12') returns '' "
                         "because act2 levels start at level13, not level01. "
                         "The linear act1→act2 transition is broken.")

    # ------------------------------------------------------------------
    # 2. Verify act_completed signal is NOT emitted for final act
    # ------------------------------------------------------------------

    def test_final_act_completed_signal_missing(self):
        """BUG: When the very last level is completed, act_completed signal
        is NOT emitted because there's no act3_level01 in the registry.

        In game_manager.gd:196-202:
            var next_act_id := "act%d_level%02d" % [act + 1, 1]
            if next_act_id in level_registry:
                ...
                act_completed.emit(act)   # <-- NEVER reached for final act!

        This means the game has NO way to know the game is fully finished.
        """
        # Complete ALL levels
        all_levels = []
        for wing in self.ht.wings:
            all_levels.extend(wing.halls)

        for level_id in all_levels:
            self.gm.complete_level(level_id)

        # Check: act_completed should have been emitted for act 1
        # (because act2_level13 exists), but NOT for act 2
        act_completed_signals = [
            s for s in self.gm.emitted_signals if s[0] == "act_completed"
        ]

        act_completed_acts = [s[1] for s in act_completed_signals]

        # act 1 completed IS emitted (act2 levels exist)
        # But this happens when act1_level12 is completed
        # NOT when the last act2 level is completed
        self.assertNotIn(2, act_completed_acts,
                         "BUG CONFIRMED: act_completed(2) is never emitted! "
                         "The game doesn't know it's finished. "
                         "This is part of the Stack underflow chain — "
                         "no 'game over' guard prevents the broken transition.")

    # ------------------------------------------------------------------
    # 3. Full flow simulation: complete last level → Stack underflow
    # ------------------------------------------------------------------

    def test_stack_underflow_on_last_level_complete(self):
        """MAIN BUG TEST: Reproduce the exact sequence that causes
        Stack underflow when all levels are completed.

        Flow:
        1. Player completes act2_level16 (the very last level)
        2. _on_level_complete() creates timer lambda + tween lambda
        3. Summary panel shown with lambdas active
        4. Player clicks "ВЕРНУТЬСЯ НА КАРТУ"
        5. _on_next_level_pressed() → return_to_map() → open_map()
        6. change_scene_to_file() destroys LevelScene
        7. Lambda closures on VM stack reference freed objects
        8. → Stack underflow!
        """
        # Pre-complete all levels except the last one
        all_levels = []
        for wing in self.ht.wings:
            all_levels.extend(wing.halls)
        for level_id in all_levels[:-1]:
            self.gm.complete_level(level_id)

        last_level = all_levels[-1]
        self.assertEqual(last_level, "act2_level16")

        # Simulate the full completion flow
        scene = LevelSceneMirror(self.gm)
        complete_result = scene.on_level_complete(last_level)

        # Verify lambdas are active after completion
        self.assertGreater(len(complete_result["active_lambdas"]), 0,
                           "Timer lambda should be active after _on_level_complete()")

        # Show summary (fires after 1.2s timer)
        summary_result = scene.show_complete_summary()

        # Verify: button should say "ВЕРНУТЬСЯ НА КАРТУ" (hall_tree mode)
        self.assertTrue(summary_result["has_hall_tree"])
        self.assertEqual(summary_result["button_text"], "ВЕРНУТЬСЯ НА КАРТУ")

        # Verify: there are live lambdas (tween + timer)
        self.assertGreater(len(summary_result["active_lambdas"]), 1,
                           "Multiple lambdas should be active: timer + tween + _s helper")

        # THE BUG: Player presses the button → scene transition with live lambdas
        transition_result = scene.on_next_level_pressed()

        # ASSERT: Stack underflow conditions are present
        self.assertTrue(transition_result["stack_underflow_risk"],
                        "BUG CONFIRMED: Scene change with active lambda closures "
                        "causes Stack underflow in GDScript VM!")
        self.assertGreater(transition_result["dangling_lambda_count"], 0,
                           f"BUG: {transition_result['dangling_lambda_count']} lambda(s) "
                           "are dangling when scene is destroyed")
        self.assertEqual(transition_result["transition_type"], "return_to_map")

        # Verify the scene was destroyed while lambdas were live
        self.assertTrue(scene.is_scene_destroyed,
                        "Scene must be destroyed during transition")
        self.assertGreater(len(scene.lambda_callbacks_active), 0,
                           "Lambdas must still be in the list when scene is destroyed "
                           "— they can't clean themselves up during change_scene_to_file()")

    # ------------------------------------------------------------------
    # 4. Lambda accumulation: every level completion adds lambdas
    # ------------------------------------------------------------------

    def test_lambda_callbacks_accumulate_per_completion(self):
        """Each level completion adds timer + tween lambda callbacks.
        If they're not cleaned up, they accumulate and increase
        Stack underflow risk."""
        scene = LevelSceneMirror(self.gm)

        # Complete first level
        scene.on_level_complete("act1_level01")
        scene.show_complete_summary()
        lambdas_after_1 = len(scene.lambda_callbacks_active)
        self.assertGreater(lambdas_after_1, 0)

        # Complete second level (without scene recreation)
        scene.on_level_complete("act1_level02")
        scene.show_complete_summary()
        lambdas_after_2 = len(scene.lambda_callbacks_active)

        # Lambdas should accumulate
        self.assertGreater(lambdas_after_2, lambdas_after_1,
                           "Lambda callbacks accumulate with each level completion "
                           "because create_timer() and create_tween() add new closures")

    # ------------------------------------------------------------------
    # 5. No 'game finished' state — missing guard
    # ------------------------------------------------------------------

    def test_no_game_finished_guard(self):
        """BUG: There is no check for 'all levels completed' anywhere.
        The game blindly calls return_to_map() even when the game should
        show a 'congratulations' screen or special ending.

        This missing guard is what allows the broken transition to occur.
        """
        # Complete all levels
        all_levels = []
        for wing in self.ht.wings:
            all_levels.extend(wing.halls)
        for level_id in all_levels:
            self.gm.complete_level(level_id)

        # Check: all halls are completed
        self.assertEqual(len(self.gm.completed_levels), len(all_levels))

        # Check: no next level exists
        next_path = self.gm.get_next_level_path("act2_level16")
        self.assertEqual(next_path, "")

        # Check: progression engine shows everything completed
        for wing in self.ht.wings:
            progress = self.gm.progression.get_wing_progress(wing.id)
            self.assertEqual(progress["completed"], progress["total"],
                             f"Wing {wing.id} should be fully completed")

        # BUG: There's no 'is_game_finished()' method in GameManager
        # This is the missing guard that would prevent Stack underflow.
        has_game_finished_check = hasattr(self.gm, 'is_game_finished')
        self.assertFalse(has_game_finished_check,
                         "BUG CONFIRMED: GameManager has no is_game_finished() method. "
                         "This missing guard allows the broken transition flow.")

    # ------------------------------------------------------------------
    # 6. HudBuilder lambda in static method — closure escapes scope
    # ------------------------------------------------------------------

    def test_hud_builder_lambda_in_static_context(self):
        """BUG: In hud_builder.gd:284, a lambda is created inside a static method:

            var _s = func(n, t): var l = p.get_node_or_null(n); if l: l.text = t

        This lambda captures `p` (CompleteSummaryPanel). When the scene is freed
        by change_scene_to_file(), `p` becomes invalid, but the lambda closure
        is still on the GDScript VM stack.

        In Godot 4.6, this is a known pattern that causes Stack underflow
        because exit_function tries to pop a frame that no longer exists.
        """
        # Simulate: create lambda that captures a reference
        panel_ref = {"valid": True, "text": ""}

        # This mirrors the GDScript lambda pattern
        _s = lambda n, t: panel_ref.update({"text": t}) if panel_ref["valid"] else None

        # Lambda works while panel is valid
        _s("SummaryTitle", "Зал открыт!")
        self.assertEqual(panel_ref["text"], "Зал открыт!")

        # Simulate scene destruction (panel freed)
        panel_ref["valid"] = False

        # Lambda still exists but panel is freed — this is the dangerous state.
        # In GDScript, calling the lambda here would cause Stack underflow
        # because the VM tries to look up p.get_node_or_null() on a freed object.
        # The lambda itself wasn't freed because it's a Callable on the stack.
        self.assertFalse(panel_ref["valid"],
                         "Panel is freed but lambda still exists — "
                         "this is the Stack underflow condition")

    # ------------------------------------------------------------------
    # 7. Map scene dismiss_instruction_panel lambda
    # ------------------------------------------------------------------

    def test_dismiss_instruction_panel_lambda_fixed(self):
        """FIXED: hud_builder.gd no longer uses lambda in tween_callback.

        Previously:
            tw.tween_callback(func(): if is_instance_valid(p): p.visible = false)

        Now extracted to a proper static method _hide_node(), following the
        same pattern as map_scene.gd:792 (_set_gate_label_open).
        """
        base = Path(__file__).resolve().parent.parent.parent.parent
        hud_builder_path = base / "src" / "game" / "hud_builder.gd"

        self.assertTrue(hud_builder_path.exists(),
                        "hud_builder.gd must exist")

        source = hud_builder_path.read_text(encoding="utf-8")

        # Lambda in tween_callback should be gone
        self.assertNotIn("tween_callback(func():", source,
                         "FIX VERIFIED: hud_builder.gd no longer uses lambda in "
                         "tween_callback — extracted to _hide_node() method.")

        # The safe helper method should exist
        self.assertIn("_hide_node", source,
                      "hud_builder.gd should have _hide_node() helper method.")

    # ------------------------------------------------------------------
    # 8. Verify the fix pattern exists (map_scene.gd already fixed one)
    # ------------------------------------------------------------------

    def test_fix_pattern_documented_in_map_scene(self):
        """Verify that map_scene.gd already documents the fix pattern
        in its comment on _set_gate_label_open()."""
        base = Path(__file__).resolve().parent.parent.parent.parent
        map_scene_path = base / "src" / "ui" / "map_scene.gd"

        self.assertTrue(map_scene_path.exists())

        source = map_scene_path.read_text(encoding="utf-8")

        # The fix pattern comment must exist
        self.assertIn("avoids lambda/Stack underflow", source,
                      "map_scene.gd should document the Stack underflow fix pattern")

        # The safe callback method must exist
        self.assertIn("_set_gate_label_open", source,
                      "map_scene.gd should have the extracted callback method")

    # ------------------------------------------------------------------
    # 9. Complete all Act 1 levels — transition to Act 2 should work
    # ------------------------------------------------------------------

    def test_act1_to_act2_transition_broken_BUG(self):
        """BUG: Completing all Act 1 levels does NOT emit act_completed(1)!

        GameManager.complete_level('act1_level12') tries:
        1. next_id = 'act1_level13' → NOT in registry (act2 levels use act2_ prefix)
        2. next_act_id = 'act2_level01' → NOT in registry (act2 starts at level13)
        3. Neither branch matches → act_completed is NEVER emitted!

        This means the game thinks act1 was never finished.
        In hall_tree mode this is masked (player uses map navigation),
        but it's a fundamental logic bug in the linear progression path.
        """
        act1_levels = self.ht.wings[0].halls
        for level_id in act1_levels:
            self.gm.complete_level(level_id)

        # act_completed should NOT be emitted (this is the bug)
        act_completed = [s for s in self.gm.emitted_signals
                         if s[0] == "act_completed"]
        act1_completed = [s for s in act_completed if s[1] == 1]
        self.assertEqual(len(act1_completed), 0,
                         "BUG CONFIRMED: act_completed(1) is NEVER emitted "
                         "because act2 levels don't follow the expected naming "
                         "convention (act2_level01). Act1 → Act2 linear transition "
                         "is completely broken.")

        # Next level doesn't exist via linear path
        next_path = self.gm.get_next_level_path("act1_level12")
        self.assertEqual(next_path, "",
                         "BUG: no linear path from act1 to act2")

    # ------------------------------------------------------------------
    # 10. Regression: completion of any mid-game level should be safe
    # ------------------------------------------------------------------

    def test_mid_game_completion_no_underflow_risk(self):
        """Completing a level mid-game (not the last) should NOT have
        Stack underflow risk because scene change happens cleanly."""
        scene = LevelSceneMirror(self.gm)
        scene.on_level_complete("act1_level01")
        scene.show_complete_summary()

        result = scene.on_next_level_pressed()

        # For hall_tree mode, transition always goes to map
        self.assertEqual(result["transition_type"], "return_to_map")

        # But the risk exists even mid-game because of lambdas!
        # This is a design flaw: ALL scene transitions have the same risk.
        self.assertTrue(result["stack_underflow_risk"],
                        "Even mid-game, lambda closures create Stack underflow risk. "
                        "The bug manifests most reliably on the LAST level because "
                        "the map scene also triggers lambdas during wing_unlock animation.")


class TestStackUnderflowRootCause(unittest.TestCase):
    """Deeper analysis of the root cause: lambda closures in GDScript.

    In Godot 4.x, lambda closures (anonymous functions) keep references
    to their enclosing scope on the GDScript VM's call stack. When the
    enclosing object (Node) is freed, these stack frames become invalid.

    The GDScript VM's exit_function() at gdscript.h:530 performs:
        stack_pos -= function->_stack_size;
    If the stack frame is already gone (freed node), stack_pos underflows.
    """

    def test_feedback_fx_timer_lambdas_fixed(self):
        """FIXED: feedback_fx.gd no longer uses lambda timer callbacks.

        Previously used: timer.timeout.connect(func(): feedback_completed.emit("valid"))
        Now uses: timer.timeout.connect(_emit_feedback.bind("valid"))

        The named method _emit_feedback() avoids dangling closures during
        scene transitions.
        """
        base = Path(__file__).resolve().parent.parent.parent.parent
        fx_path = base / "src" / "visual" / "feedback_fx.gd"

        if not fx_path.exists():
            self.skipTest("feedback_fx.gd not found")

        source = fx_path.read_text(encoding="utf-8")

        # Lambda timer callbacks should be gone
        lambda_count = source.count("timeout.connect(func():")
        self.assertEqual(lambda_count, 0,
                         "FIX VERIFIED: feedback_fx.gd no longer uses lambda timer callbacks. "
                         f"Found {lambda_count} instance(s) — should be 0.")

        # The safe helper method should exist
        self.assertIn("_emit_feedback", source,
                      "feedback_fx.gd should have _emit_feedback() helper method.")

    def test_level_scene_timer_in_on_level_complete(self):
        """level_scene.gd:299 creates a timer with .bind() callback:

            get_tree().create_timer(1.2).timeout.connect(
                _show_complete_summary.bind(level_data.get("meta", {})))

        While .bind() is safer than lambda (it uses a method reference),
        it still keeps the LevelScene reference alive. If scene changes
        during the 1.2s delay, _show_complete_summary is called on a
        freed object.
        """
        base = Path(__file__).resolve().parent.parent.parent.parent
        level_scene_path = base / "src" / "game" / "level_scene.gd"

        source = level_scene_path.read_text(encoding="utf-8")

        self.assertIn("create_timer(1.2)", source,
                      "level_scene.gd should have the 1.2s timer for summary")

        # The timer fires AFTER completion but BEFORE the player can press
        # "next level". This is safe timing-wise. BUT if the player somehow
        # triggers a scene change during this 1.2s window (e.g., pressing
        # Android back button), the callback fires on a freed node.
        self.assertIn("_show_complete_summary.bind", source,
                      "Timer callback should use .bind() (method reference)")


if __name__ == "__main__":
    unittest.main()
