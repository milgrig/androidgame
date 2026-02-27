# T036: Architecture Review — Hall Tree Implementation

**Reviewer:** Architect
**Date:** 2026-02-26
**Scope:** T030 (data), T031 (progression), T032 (UI), integration, Agent Bridge
**Reference:** ARCH_T024_HALL_TREE.md

---

## Executive Summary

The Hall Tree implementation is **architecturally sound** and closely follows the ARCH_T024_HALL_TREE.md specification. Data structures match the spec, dependency direction is clean (core knows nothing about UI), testability is excellent via inject_state(), and backward compatibility with linear mode is preserved. The implementation is production-ready for Wing 1.

Below: 3 critical issues, 9 non-critical issues, and 5 recommendations.

---

## 1. Code Review: Data Layer (T030 — HallTreeData)

### Conformance with Spec: **PASS** ✅

| Spec Requirement | Implementation | Status |
|---|---|---|
| `class_name HallTreeData` | ✅ `extends RefCounted` | ✅ |
| Inner classes: WingData, GateData, HallEdge, ResonanceData | ✅ All 4 present, fields match | ✅ |
| `parse(data: Dictionary)` | ✅ Present, handles all fields | ✅ |
| `load_from_file(path)` | ✅ Added (bonus, not in spec) | ✅ |
| Lookup caches: `_hall_to_wing`, `_hall_edges`, `_hall_prereqs` | ✅ Built during parse() | ✅ |
| `get_wing_halls(wing_id)` | ✅ Present | ✅ |
| `get_hall_neighbors(hall_id)` → named `get_hall_edges()` | ✅ Semantic match | ✅ |
| `get_hall_prerequisites(hall_id)` → named `get_hall_prereqs()` | ✅ Semantic match | ✅ |
| `get_hall_wing(hall_id)` | ✅ Present | ✅ |
| `get_hall_resonances(hall_id)` | ✅ Present | ✅ |
| `get_ordered_wings()` | ✅ Present with sort_custom | ✅ |
| `validate()` → returns `Array[String]` | ✅ Present with comprehensive checks | ✅ |

### Positive Observations:
- **Cycle detection** (DFS-based) is implemented in `validate()` — spec didn't mandate algorithm, implementation chose well
- **Self-loop detection** included — good defensive check
- **Duplicate hall across wings** detected — important for multi-wing correctness
- **`load_from_file()`** convenience method added beyond spec — good ergonomics
- **`extends RefCounted`** — correct choice for a data-only class, no scene tree dependency

### Issues Found:

**[NC-01] Return type mismatch: `get_hall_edges()` and `get_hall_prereqs()` return `Array` instead of `Array[String]`**
Spec declares `Array[String]`, implementation returns untyped `Array`. This works at runtime but loses GDScript static typing benefits and IDE autocomplete.

```gdscript
# Current (line 212):
func get_hall_edges(hall_id: String) -> Array:
# Spec expects:
func get_hall_edges(hall_id: String) -> Array[String]:
```

**Severity:** Non-critical (runtime behavior is identical)
**Fix:** Change return type annotations to `Array[String]`

**[NC-02] `get_ordered_wings()` returns `Array` instead of `Array[WingData]`**
Same typing issue as above.
**Severity:** Non-critical

**[NC-03] Missing `get_wing_neighbors()` API mentioned in spec section 8.1**
The spec lists `get_hall_neighbors(hall_id)` as a named method. Implementation uses `get_hall_edges()` which is semantically equivalent but naming diverges. This is acceptable — just documenting the delta.
**Severity:** Informational only

---

## 2. Code Review: Progression Layer (T031 — HallProgressionEngine)

### Conformance with Spec: **PASS** ✅

| Spec Requirement | Implementation | Status |
|---|---|---|
| `class_name HallProgressionEngine extends Node` | ✅ | ✅ |
| Signal: `hall_unlocked(hall_id)` | ✅ | ✅ |
| Signal: `wing_unlocked(wing_id)` | ✅ | ✅ |
| Signal: `resonance_discovered(resonance)` | ✅ | ✅ |
| `get_hall_state(hall_id) -> HallState` | ✅ | ✅ |
| `is_wing_accessible(wing_id) -> bool` | ✅ (public wrapper added) | ✅ |
| `get_wing_progress(wing_id) -> Dictionary` | ✅ | ✅ |
| `get_available_halls() -> Array[String]` | ✅ | ✅ |
| `get_discovered_resonances()` | ✅ | ✅ |
| `on_hall_completed(hall_id)` → named `complete_hall()` | ✅ Semantic match | ✅ |
| Gate types: threshold, all, specific | ✅ All 3 implemented | ✅ |
| Perfection seal logic | ✅ `hints_used == 0` check | ✅ |
| Orphan hall handling | ✅ Line 217: `if prereqs.is_empty(): return true` | ✅ |

### Positive Observations:
- **Dependency injection via `inject_state()`** — excellent design decision, enables pure unit testing without GameManager autoload
- **`_use_injected_state` flag** cleanly separates test vs. production paths
- **HallState enum defined locally** (not importing from UI) — correct dependency direction
- **All 3 gate types fully implemented** with proper fallback logic
- **`_get_previous_wing_id()` fallback** when `required_from_wing` is empty — handles spec's "null = previous" behavior

### Issues Found:

**[CRITICAL-01] `complete_hall()` calls `_mark_completed()` then immediately checks `_is_wing_accessible()`, which may emit `wing_unlocked` for already-unlocked wings**

When a hall is completed, `complete_hall()` checks if the next wing became accessible. But it doesn't check whether the wing was ALREADY accessible before this completion. This means if the threshold was already met (e.g., 8 of 7), completing hall #9 will emit `wing_unlocked` again.

```gdscript
# hall_progression_engine.gd line 168-170
var next_wing := _get_next_wing(wing)
if next_wing != null and _is_wing_accessible_internal(next_wing):
    wing_unlocked.emit(next_wing.id)  # May fire on EVERY completion after threshold
```

**Impact:** UI may show "wing unlocked" animation multiple times.
**Fix:** Add a pre-check: only emit if wing was NOT accessible before this completion:
```gdscript
var was_accessible := _is_wing_accessible_internal(next_wing) if next_wing else false
# ... then after _mark_completed() ...
if next_wing != null and not was_accessible and _is_wing_accessible_internal(next_wing):
    wing_unlocked.emit(next_wing.id)
```

Wait — actually `_mark_completed()` happens before the check. The issue is that `_is_wing_accessible_internal` checks current state AFTER the hall was marked completed. So the first time you cross threshold, it correctly fires. But the SECOND time you complete a hall (beyond threshold), the check `_is_wing_accessible_internal(next_wing)` is still true. **So yes, `wing_unlocked` fires on every completion after threshold.**

**Severity:** Critical — causes duplicate "wing unlocked" animations/sounds
**Recommended fix:** Track which wings have already been unlocked (e.g., `_unlocked_wings: Array[String]`), and only emit if wing_id not yet in set.

**[CRITICAL-02] Same issue applies to `resonance_discovered` signal — may fire repeatedly**

Every time a hall involved in a resonance is completed (after both are already complete), `_is_resonance_discovered()` returns true and the signal fires again.

```gdscript
# hall_progression_engine.gd line 173-176
var hall_resonances: Array = hall_tree.get_hall_resonances(hall_id)
for resonance in hall_resonances:
    if _is_resonance_discovered(resonance):
        resonance_discovered.emit(resonance)  # Fires on every subsequent completion
```

**Severity:** Critical — resonance animation replays unnecessarily
**Recommended fix:** Track `_discovered_resonances: Array` and only emit if not already discovered. This also aligns with the spec's `discovered_resonances` save field (Section 6.4).

**[NC-04] HallState enum duplicated between HallProgressionEngine and HallNodeVisual**

`HallProgressionEngine` defines `enum HallState { LOCKED, AVAILABLE, COMPLETED, PERFECT }` and `HallNodeVisual` defines `enum VisualState { LOCKED, AVAILABLE, COMPLETED, PERFECT }`. MapScene manually maps between them (lines 162-173).

This is intentionally correct from a dependency perspective (progression engine shouldn't import UI types), but the manual mapping in MapScene is verbose. The spec originally had progression return `HallNodeVisual.HallState` directly, which is an upward dependency.

**Severity:** Non-critical — current approach (separate enums) is actually better than spec
**Recommendation:** Consider a shared enum in a core constants file if the mapping code grows

**[NC-05] `get_available_halls()` only returns AVAILABLE state, not COMPLETED/PERFECT**

The spec says "all currently available (playable) halls" and the comment in code says "state AVAILABLE or COMPLETED". But implementation only appends halls with `state == HallState.AVAILABLE`.

```gdscript
# Line 123
if state == HallState.AVAILABLE:
    result.append(hall_id)
```

COMPLETED halls ARE playable (for replay). The spec comment says both states.

**Severity:** Non-critical — MapScene doesn't rely on this for replay (it uses direct click handling), but the API semantics are slightly misleading
**Fix:** Either update the comment, or include COMPLETED/PERFECT in results and add a separate `get_newly_available_halls()` method

---

## 3. Code Review: UI Layer (T032 — MapScene, HallNodeVisual, MapLayoutEngine)

### 3.1 MapScene Conformance: **PASS** ✅

| Spec Requirement | Implementation | Status |
|---|---|---|
| Scene structure: EdgeCanvas, HallNodes, Camera, HUD | ✅ Programmatically built | ✅ |
| Reads `hall_tree` and `progression` from GameManager | ✅ Lines 53-54 | ✅ |
| BFS layout via MapLayoutEngine | ✅ | ✅ |
| Edge rendering (Line2D between halls) | ✅ With color states | ✅ |
| Wing headers with progress | ✅ With subtitle | ✅ |
| Camera pan/zoom | ✅ Drag + scroll wheel | ✅ |
| Hall click → transition to LevelScene | ✅ `enter_hall()` | ✅ |
| Back button → MainMenu | ✅ `_on_back_pressed()` | ✅ |
| HUD with progress display | ✅ Top bar + bottom bar | ✅ |
| `refresh_states()` | ✅ Re-maps hall states to visual | ✅ |

### 3.2 HallNodeVisual Conformance: **PASS** ✅

| Spec Requirement | Implementation | Status |
|---|---|---|
| 4 visual states: LOCKED, AVAILABLE, COMPLETED, PERFECT | ✅ VisualState enum | ✅ |
| Signal: `hall_selected(hall_id)` | ✅ | ✅ |
| Click detection via Area2D | ✅ CollisionShape2D + CircleShape2D | ✅ |
| LOCKED: no interaction | ✅ Checked in `_on_area_input_event` | ✅ |
| AVAILABLE: pulsing animation | ✅ Sine-based pulse in `_process()` | ✅ |
| PERFECT: shimmer animation | ✅ Sine-based shimmer | ✅ |
| Crystal polygon (hexagon) | ✅ 6-sided, custom draw | ✅ |
| Hover effect | ✅ Scale interpolation + font enlarge | ✅ |
| State-dependent colors + glow | ✅ Constants dicts | ✅ |

### 3.3 MapLayoutEngine Conformance: **PASS** ✅

| Spec Requirement | Implementation | Status |
|---|---|---|
| BFS layer-based layout | ✅ `_bfs_layers()` | ✅ |
| Wings stacked vertically | ✅ `current_y` accumulator | ✅ |
| `compute_layout()` returns positions | ✅ + wing_headers + total_height | ✅ |
| Orphan halls appended to last layer | ✅ Lines 94-105 | ✅ |
| Constants: WING_VERTICAL_GAP, LAYER_HEIGHT, etc. | ✅ Slightly adjusted values | ✅ |

### Issues Found:

**[NC-06] MapScene: Hardcoded screen dimensions (1280x720)**

HUD elements use fixed pixel positions:
```gdscript
title_bg.size = Vector2(1280, 55)   # Line 287
bottom_bg.position = Vector2(0, 680)  # Line 318
bottom_bg.size = Vector2(1280, 40)   # Line 319
```

This breaks on non-1280x720 resolutions (mobile devices, different aspect ratios).

**Severity:** Non-critical for MVP (Godot's stretch mode can handle this), but should be addressed for mobile
**Fix:** Use `get_viewport_rect().size` or anchor-based Control nodes instead of hardcoded positions

**[NC-07] MapScene: `_read_level_meta()` reads level JSON on every hall spawn — O(N) file reads**

For each of the 12 halls, `_get_hall_display_name()` and `_get_hall_group_name()` both call `_read_level_meta()`, which opens and parses a JSON file. That's 24 file reads for 12 halls.

```gdscript
# Lines 176-177 — called per hall
var display_name := _get_hall_display_name(hall_id)
var display_group := _get_hall_group_name(hall_id)
```

**Severity:** Non-critical (12 halls is fast), but scales poorly for Act 2-4 with 48+ halls
**Fix:** Cache level meta in a Dictionary after first read, or batch-read on startup

**[NC-08] MapScene: `refresh_states()` doesn't redraw edges**

After returning from LevelScene, `refresh_states()` updates hall node visuals but doesn't update edge colors. Edges still show their original colors from initial draw.

```gdscript
func refresh_states() -> void:
    for hall_id in _hall_nodes:
        # ... updates node states
        # But edges in _edge_canvas are not redrawn!
```

**Severity:** Non-critical — cosmetic issue (edge colors slightly stale after level completion)
**Fix:** Either redraw edges in `refresh_states()` or call `_draw_edges()` with edge clear/rebuild

**[CRITICAL-03] MapScene: `refresh_states()` is never actually called**

The method exists but nothing invokes it. When the player completes a level and returns to MapScene via `GameManager.return_to_map()`, which calls `get_tree().change_scene_to_file("res://src/ui/map_scene.tscn")` — this creates a NEW MapScene instance. So `_ready()` runs fresh and builds everything correctly from current state.

However, this means `refresh_states()` is dead code. This is NOT actually a bug (the flow works because MapScene is recreated), but it's misleading dead code.

**Severity:** Non-critical but confusing — the method exists suggesting it's needed, but scene re-instantiation makes it unnecessary.
**Recommendation:** Either (a) remove refresh_states() or (b) document that it's for future use when MapScene is kept alive across level completions (which would be better for performance/animation continuity)

Actually, wait — on re-examination, this IS potentially a critical architectural consideration. The current flow:

```
MapScene → LevelScene → change_scene_to_file(map_scene.tscn) → NEW MapScene
```

This means any MapScene state (camera position, scroll offset, selected wing) is lost on every level completion return. The player is always reset to the default camera position.

**Revised Severity:** Critical for UX (camera position reset after every level), but not a correctness bug
**Recommended fix:** Either (a) store last camera position in GameManager and restore in MapScene._ready(), or (b) keep MapScene alive in the scene tree and overlay LevelScene

---

## 4. Code Review: GameManager Integration

### Conformance with Spec: **PASS** ✅

| Spec Requirement | Implementation | Status |
|---|---|---|
| `hall_tree: HallTreeData` field | ✅ Line 40 | ✅ |
| `progression: HallProgressionEngine` field | ✅ Line 41 | ✅ |
| `current_hall_id: String` field | ✅ Line 42 | ✅ |
| `_load_hall_tree()` in `_ready()` | ✅ Lines 53, 99-122 | ✅ |
| Validates tree on load | ✅ Lines 112-116 | ✅ |
| Linear fallback when hall_tree.json missing | ✅ Lines 101-103, 127-144 | ✅ |
| `complete_level()` notifies progression | ✅ Lines 190-191 | ✅ |
| `map_requested` signal | ✅ Line 18 | ✅ |
| `open_map()` method | ✅ Lines 148-150 | ✅ |
| `return_to_map()` method | ✅ Lines 159-163 | ✅ |
| `start_game()` routes to map or linear | ✅ Lines 127-144 | ✅ |
| Preserved: `complete_level()`, `is_level_completed()` | ✅ Unchanged signatures | ✅ |
| Preserved: `level_registry`, `save_game()`, `load_game()` | ✅ Working | ✅ |

### Issues Found:

**[NC-09] Save data does NOT include spec's new fields: `discovered_resonances`, `perfection_seals`, `last_wing`**

The spec (Section 6.4) adds these fields to save data:
```json
"discovered_resonances": ["res_act1_01_04"],
"perfection_seals": ["act1_level01"],
"last_wing": "wing_1"
```

Current `save_game()` (lines 238-255) does NOT save these fields. `load_game()` also doesn't restore them. This means:
- Discovered resonances are re-computed on every load (functional, but repeated "discovery" animations)
- Perfection seals are derived from `level_states.hints_used` (functional, correct)
- Last active wing is not saved (camera resets)

**Severity:** Non-critical for correctness — resonances and seals can be re-derived from `level_states` and `completed_levels`. But `last_wing` is useful for UX.

**Fix:** Add these fields to save/load:
```gdscript
# In save_game():
"discovered_resonances": discovered_resonances,
"last_wing": current_hall_id_to_wing(),

# In load_game():
discovered_resonances.assign(player.get("discovered_resonances", []))
```

---

## 5. Code Review: LevelScene Integration

### Conformance with Spec: **PASS** ✅

| Spec Requirement | Implementation | Status |
|---|---|---|
| Load level from `current_hall_id` on `_ready()` | ✅ Lines 91-98 | ✅ |
| `_on_next_level_pressed()` returns to map | ✅ Lines 1313-1316 | ✅ |
| Linear fallback when no hall_tree | ✅ Lines 1319-1324 | ✅ |
| Button text: "ВЕРНУТЬСЯ НА КАРТУ" (return to map) | ✅ Line 1406 (Russian locale) | ✅ |
| Summary shows seal of perfection status | ✅ Lines 1396-1399 | ✅ |

### Positive Observations:
- Clean integration point via `GameManager.current_hall_id`
- Backward-compatible linear fallback preserved
- Russian localization present (consistent with game locale)

---

## 6. Code Review: Agent Bridge

### MapScene Compatibility: **PARTIAL** ⚠️

The Agent Bridge (`agent_bridge.gd`) currently only discovers and interacts with `LevelScene`. There is **no MapScene awareness**.

| Capability | Status | Notes |
|---|---|---|
| Discover MapScene in scene tree | ❌ Not implemented | `_find_level_scene()` only looks for LevelScene |
| List available halls on map | ❌ Not implemented | No command to query map state |
| Select a hall from map | ❌ Not implemented | No command to click a hall node |
| Get map/wing progression state | ❌ Not implemented | No command for wing progress |
| Navigate map camera | ❌ Not implemented | No pan/zoom commands for map |

**However:** The Agent Bridge CAN still test the map indirectly:
- `get_tree` command can see MapScene nodes (it walks full scene tree)
- `press_button` can press the Back button (by path)
- `list_actions` discovers all visible buttons including HallNodeVisual click areas

**But critically:** HallNodeVisual uses Area2D.input_event (not Button.pressed), so `press_button` won't work. The agent cannot select a hall on the map without new commands.

**Severity:** Not blocking for current sprint (agent testing was only for LevelScene), but blocks future agent testing of the full game flow.

**Recommended additions for future sprint:**
```gdscript
# New agent commands for MapScene:
"get_map_state"     # Returns halls, states, positions, wing progress
"select_hall"       # Click a hall node by hall_id
"get_wing_progress" # Returns threshold progress for each wing
```

---

## 7. Architecture Quality Review

### 7.1 Dependency Cleanliness: **PASS** ✅

```
                    ┌─────────────────────┐
                    │   hall_tree.json     │  (pure data)
                    └──────────┬──────────┘
                               │ parsed by
                    ┌──────────▼──────────┐
                    │    HallTreeData      │  src/core/ — no UI imports ✅
                    │    (RefCounted)      │
                    └──────────┬──────────┘
                               │ consumed by
                    ┌──────────▼──────────┐
                    │ HallProgressionEngine│  src/core/ — no UI imports ✅
                    │    (Node)            │  imports only HallTreeData ✅
                    │    + GameManager     │  GameManager is autoload (ok) ✅
                    └──────────┬──────────┘
                               │ consumed by
              ┌────────────────┼────────────────┐
   ┌──────────▼──────────┐  ┌─▼──────────────┐  ┌▼──────────────┐
   │     MapScene         │  │  LevelScene     │  │ AgentBridge   │
   │    (Node2D)          │  │  (Node2D)       │  │ (Node)        │
   │  imports:            │  │  imports:       │  │ imports:      │
   │  - HallTreeData ✅   │  │  - GameManager ✅│  │ - LevelScene ✅│
   │  - Progression ✅    │  │                 │  │               │
   │  - HallNodeVisual ✅ │  │                 │  │               │
   │  - MapLayoutEngine ✅│  │                 │  │               │
   └──────────────────────┘  └─────────────────┘  └───────────────┘
```

**Key observation:** HallTreeData imports nothing. HallProgressionEngine imports only HallTreeData. UI imports both — correct unidirectional flow. **No circular dependencies.**

### 7.2 Extensibility for Future Wings: **GOOD** ✅

The data-driven design makes adding Acts 2-4 straightforward:

1. **Add wing to `hall_tree.json`** — JSON only, no code changes needed
2. **Add level JSONs** to `data/levels/act2/` etc.
3. **Gate system handles it** — threshold/all/specific logic is generic
4. **MapLayoutEngine scales** — BFS layout adds wings vertically

**Potential concern for 4+ wings:** The vertical stacking may produce a very tall map requiring significant scrolling. The current camera zoom range (0.5x–2.0x) may not be sufficient for 4 wings × 12 halls = 48 nodes.

**Recommendation:** Add a wing selector/tab UI for Act 3-4 so players can jump between wings without excessive scrolling.

### 7.3 BFS Layout Performance: **ACCEPTABLE** ✅

For the current graph (12 halls, 16 edges), BFS is trivially fast.

**Scalability analysis for future:**
- Wing 1: 12 halls, 16 edges → BFS visits 12 nodes, O(12+16) = O(28)
- 4 wings × 12 halls = 48 nodes, ~64 edges → O(112), still trivial
- Theoretical max (100 halls, 200 edges): O(300), still sub-millisecond

**Verdict:** BFS layout will NOT be a performance bottleneck even at 10× current scale.

**The real performance concern is `_draw_edges()` and `HallNodeVisual._process()`:**
- Each HallNodeVisual runs `_process()` every frame (pulse/shimmer animation + `queue_redraw()`)
- With 48+ nodes, that's 48 `queue_redraw()` calls per frame
- Recommendation: Only run animations on visible/on-screen nodes, or use shader-based animation

---

## 8. Data Review: hall_tree.json

### Wing 1 Structure Analysis:

```
Graph structure (16 edges across 12 halls):

level01 ──┬── level02 ──┬── level04 ──┬── level05 ──┬── level09 ──┬── level11
          │             │             │             │             │
          │             └── level05 ──┘             └── level12   │
          │                                                       │
          └── level03 ──┬── level06 ── level08 ──── level09       │
                        │                                         │
                        └── level07 ── level08                    │
                                                                  │
                                  level04 ── level10 ── level11 ──┘
                                  level05 ── level12
```

**Observations:**
- level05 has 3 incoming edges (from level02, level04, and possibly level03's path) — good convergence point
- level09 is a major convergence (from level05 and level08) — becomes "mini-boss" feel
- level11 is the "final challenge" — requires either level09 or level10 path
- level12 is an alternate endpoint (from level05 and level09)
- 6 resonances defined — good coverage of mathematical relationships

**Gate configuration:** `required_halls: 8` of 12 total (66.7%) — reasonable, allows skipping 4 halls.

### Validation: **PASS** ✅
- No cycles detected (DAG property holds)
- All edges reference valid halls
- All resonances reference valid halls
- Start hall is in wing's halls list
- All resonances use "both_completed" trigger (consistent)

---

## 9. Test Coverage Review

### GDScript Tests (test_hall_tree_data.gd): 21 test cases ✅
- Parsing: wings, edges, resonances
- Caches: hall_to_wing, hall_edges, hall_prereqs
- Query API: get_wing, get_wing_halls, get_hall_edges, etc.
- Validation: valid tree, missing hall in edge, cycle detection, start_hall not in wing
- Edge cases: empty data, nonexistent wing, leaf hall

### GDScript Tests (test_hall_progression.gd): 25 test cases ✅
- State transitions: LOCKED → AVAILABLE → COMPLETED → PERFECT
- Hall availability: prereqs, multiple prereqs (any sufficient), orphans
- Wing gates: threshold (met/not met/boundary), all (met/not met), specific (met/not met)
- Available halls: initial, after completion
- Signals: complete_hall unlocks neighbors, unlocks wing
- Resonances: not discovered until both completed, discovered after
- Edge cases: null hall_tree, unknown hall_id, wing without gate

### Python Tests (test_hall_tree_data.py): 27 test cases ✅
- Mirror of GDScript tests for CI/fast testing

### Python Tests (test_hall_progression.py): 35 test cases ✅
- Comprehensive — includes 3-wing chained progression test
- Tests edge cases like idempotent completion
- Boundary testing for thresholds

### Test Gaps:

**[GAP-01]** No tests for MapLayoutEngine — spec mentions `test_map_layout.gd` but file doesn't exist
**[GAP-02]** No tests for MapScene (integration test with mock GameManager)
**[GAP-03]** No tests for resonance_discovered signal duplication (see CRITICAL-02)
**[GAP-04]** No test for wing_unlocked signal duplication (see CRITICAL-01)
**[GAP-05]** No agent test for the MapScene → LevelScene → MapScene round-trip

---

## 10. Summary: Issues List

### Critical Issues (must fix before ship):

| ID | Component | Issue | Impact |
|---|---|---|---|
| **CRITICAL-01** | HallProgressionEngine | `wing_unlocked` signal fires on every completion after threshold | Duplicate "wing unlocked" animation |
| **CRITICAL-02** | HallProgressionEngine | `resonance_discovered` signal fires on every completion | Duplicate resonance animation |
| **CRITICAL-03** | MapScene | Camera position resets on every return from LevelScene | UX: player loses map scroll position |

### Non-Critical Issues:

| ID | Component | Issue | Severity |
|---|---|---|---|
| **NC-01** | HallTreeData | `get_hall_edges()` returns untyped Array | Low |
| **NC-02** | HallTreeData | `get_ordered_wings()` returns untyped Array | Low |
| **NC-03** | HallTreeData | Method naming: `get_hall_edges` vs spec's `get_hall_neighbors` | Info |
| **NC-04** | Progression/UI | HallState enum duplicated (intentionally correct) | Info |
| **NC-05** | HallProgressionEngine | `get_available_halls()` comment mentions COMPLETED but code doesn't include | Low |
| **NC-06** | MapScene | Hardcoded 1280x720 pixel positions in HUD | Medium |
| **NC-07** | MapScene | Level meta read per hall (24 file reads for 12 halls) | Low |
| **NC-08** | MapScene | `refresh_states()` doesn't update edge colors | Low |
| **NC-09** | GameManager | Missing save fields: discovered_resonances, last_wing | Medium |

---

## 11. Recommendations

### R-01: Add duplicate signal prevention (fixes CRITICAL-01 & CRITICAL-02)
Track unlocked wings and discovered resonances in the engine state:
```gdscript
var _unlocked_wing_ids: Array[String] = []
var _discovered_resonance_indices: Array[int] = []
```
This also enables proper save/load.

### R-02: Store camera position in GameManager (fixes CRITICAL-03)
```gdscript
# GameManager:
var map_camera_position: Vector2 = Vector2.ZERO
var map_camera_zoom: Vector2 = Vector2(1.0, 1.0)
```
MapScene restores on `_ready()`, saves before `enter_hall()`.

### R-03: Add Agent Bridge MapScene commands (future sprint)
Add `get_map_state`, `select_hall` commands to enable full flow testing.

### R-04: Add MapLayoutEngine tests
Create `tests/test_map_layout.gd` with tests for:
- Single wing layout
- Multi-wing vertical stacking
- Orphan hall placement
- Empty wing handling

### R-05: Consider wing navigation tabs for 4-wing map
As wings grow, add horizontal tabs or wing selector buttons to jump between wings without excessive scrolling.

---

## Verdict

**Implementation quality: 8.5/10**

The Hall Tree system is well-architected, clean, and closely follows the spec. The critical issues are all in the "duplicate signal" category — easy to fix with a tracked state set. The data layer and test coverage are particularly strong. The system is ready for MVP with the critical fixes applied.
