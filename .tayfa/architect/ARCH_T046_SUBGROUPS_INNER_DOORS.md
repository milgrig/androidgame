# ARCH_T046: Subgroups & Inner Doors Architecture (Act 2, Levels 13-16)

**Task:** T046
**Status:** Proposal
**Date:** 2026-02-27
**Author:** Architect (Game Systems)

---

## 1. Executive Summary

This document defines the architecture for **Act 2, Levels 13-16** — the "Inner Doors" (Внутренние двери) mechanic. The player discovers that certain subsets of found keys are **closed under composition** (form a subgroup). Each such subset unlocks an "inner door" within the hall.

**Core mechanic:** Player selects a subset of found keys → validates closure → if it forms a subgroup, an inner door opens.

**Design principles:**
- **Additive changes only** — Act 1 levels work unchanged (empty `subgroups`/`inner_doors` = no new UI)
- **Minimal coupling** — new logic lives in new files; existing files get surgical extensions
- **Forward-compatible** — data format supports Act 2 Levels 17-20 (normality) and 21-24 (factorization)

---

## 2. Current Architecture Snapshot

### Files to modify (minimal changes):
| File | Current Role | Change Scope |
|------|-------------|-------------|
| `src/core/key_ring.gd` | Tracks found permutations | +3 methods (~40 lines) |
| `src/game/level_scene.gd` | Main level controller | +inner door panel setup, +signal wiring (~80 lines) |
| `src/agent/agent_bridge.gd` | AI agent protocol | +2 command handlers (~40 lines) |
| `src/core/hall_progression_engine.gd` | Hall unlock states | +inner door state tracking (~20 lines) |

### New files:
| File | Role |
|------|------|
| `src/core/subgroup_checker.gd` | Pure math: closure check, subgroup generation |
| `src/game/inner_door_panel.gd` | UI: door panel, key selection, open button |
| `src/visual/inner_door_visual.gd` | Visual: door element on the graph |

---

## 3. Level JSON Format Extension

### 3.1 New fields in level JSON

```jsonc
{
  "meta": {
    "id": "act2_level13",
    "act": 2,
    "level": 13,
    "title": "Первые внутренние двери",
    "subtitle": "Какие ключи можно объединить?",
    "group_name": "D4",
    "group_order": 8
  },

  "graph": { /* ... unchanged ... */ },
  "symmetries": { /* ... unchanged ... */ },

  // ──── NEW: Subgroups & Inner Doors ────

  "subgroups": [
    {
      "id": "sg_rotations",
      "name": "Вращения",
      "order": 4,
      "elements": ["e", "r1", "r2", "r3"],
      "generators": ["r1"],
      "is_normal": true,
      "description": "Подгруппа чистых вращений"
    },
    {
      "id": "sg_flip_pair",
      "name": "Одно отражение",
      "order": 2,
      "elements": ["e", "s1"],
      "generators": ["s1"],
      "is_normal": false,
      "description": "Тождество и одно отражение"
    }
  ],

  "inner_doors": [
    {
      "id": "door_rotations",
      "subgroup_id": "sg_rotations",
      "name": "Дверь вращений",
      "visual_hint": "circular_glow",
      "position": [640, 350],
      "unlock_condition": "subgroup_found",
      "reward_text": "Вращения образуют замкнутую подгруппу!",
      "difficulty": "easy"
    },
    {
      "id": "door_flip",
      "subgroup_id": "sg_flip_pair",
      "name": "Дверь отражения",
      "visual_hint": "mirror_shimmer",
      "position": [800, 350],
      "unlock_condition": "subgroup_found",
      "reward_text": "Пара {e, s1} тоже замкнута!",
      "difficulty": "medium"
    }
  ],

  "mechanics": {
    "allowed_actions": ["swap"],
    "show_cayley_button": true,
    "show_generators_hint": true,
    "inner_doors": ["door_rotations", "door_flip"],
    "palette": null
  }
}
```

### 3.2 Schema details

**`subgroups[]` — defines all subgroups of the level's group:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `String` | yes | Unique identifier (e.g. `"sg_rotations"`) |
| `name` | `String` | yes | Player-facing name |
| `order` | `int` | yes | Number of elements |
| `elements` | `String[]` | yes | Array of automorphism IDs from `symmetries.automorphisms` |
| `generators` | `String[]` | no | Minimal generating set (for hint system) |
| `is_normal` | `bool` | yes | Whether this is a normal subgroup (used in Levels 17-20) |
| `description` | `String` | no | Player-facing explanation |

**`inner_doors[]` — doors the player must open:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `String` | yes | Unique door ID |
| `subgroup_id` | `String` | yes | References `subgroups[].id` |
| `name` | `String` | yes | Player-facing door name |
| `visual_hint` | `String` | no | Visual style: `"circular_glow"`, `"mirror_shimmer"`, `"diamond_pulse"` |
| `position` | `[x, y]` | no | Position on graph for visual element (null = auto-place) |
| `unlock_condition` | `String` | yes | `"subgroup_found"` (player selects correct keys) |
| `reward_text` | `String` | no | Text shown on successful open |
| `difficulty` | `String` | no | `"easy"`, `"medium"`, `"hard"` — for hint system pacing |

### 3.3 Backward compatibility

Both `subgroups` and `inner_doors` are **optional**. If absent or empty:
- No inner door UI is shown
- Level completion = all keys found (Act 1 behavior)
- `_build_level()` skips inner door setup entirely

Checked by: `level_data.get("inner_doors", []).size() > 0`

---

## 4. Core Engine: SubgroupChecker

New file: `src/core/subgroup_checker.gd`

### 4.1 Class design

```gdscript
class_name SubgroupChecker
extends RefCounted
## Pure math utility: checks subgroup properties of permutation sets.
## Stateless — all methods are static or take explicit parameters.
## Separated from KeyRing to keep KeyRing focused on game state tracking.

## Check if a subset of permutations is closed under composition.
## Returns true if for all a, b in subset: a.compose(b) is also in subset.
static func is_closed(subset: Array[Permutation]) -> bool:
    for a in subset:
        for b in subset:
            var product := a.compose(b)
            if not _contains(subset, product):
                return false
    return true

## Check if a subset forms a valid subgroup (closure + identity + inverses).
static func is_subgroup(subset: Array[Permutation]) -> bool:
    if subset.is_empty():
        return false
    # Must contain identity
    var has_id := false
    for p in subset:
        if p.is_identity():
            has_id = true
            break
    if not has_id:
        return false
    # Must have inverses
    for p in subset:
        if not _contains(subset, p.inverse()):
            return false
    # Must be closed
    return is_closed(subset)

## Given a subset, find which compositions are MISSING from it.
## Returns: Array[Dictionary] where each dict = {a_index, b_index, product: Permutation}
static func find_missing_products(subset: Array[Permutation]) -> Array[Dictionary]:
    var missing: Array[Dictionary] = []
    for i in range(subset.size()):
        for j in range(subset.size()):
            var product := subset[i].compose(subset[j])
            if not _contains(subset, product):
                missing.append({
                    "a_index": i,
                    "b_index": j,
                    "product": product,
                })
    return missing

## Generate the full subgroup from a set of generators.
## Uses iterative closure: keep composing until no new elements appear.
## Returns all elements of the generated subgroup.
static func generate_subgroup(generators: Array[Permutation]) -> Array[Permutation]:
    if generators.is_empty():
        return []
    var n := generators[0].size()
    var result: Array[Permutation] = [Permutation.create_identity(n)]
    # Add generators and their inverses
    for g in generators:
        if not _contains(result, g):
            result.append(g)
        var inv := g.inverse()
        if not _contains(result, inv):
            result.append(inv)
    # Iterate: compose all pairs, add new elements
    var changed := true
    while changed:
        changed = false
        var new_elements: Array[Permutation] = []
        for a in result:
            for b in result:
                var product := a.compose(b)
                if not _contains(result, product) and not _contains(new_elements, product):
                    new_elements.append(product)
                    changed = true
        result.append_array(new_elements)
    return result

## Check if a subgroup H is normal in G.
## H is normal if for all g in G, h in H: g * h * g^(-1) is in H.
## Parameters:
##   subgroup: elements of H
##   full_group: elements of G
static func is_normal_subgroup(
        subgroup: Array[Permutation],
        full_group: Array[Permutation]) -> bool:
    for g in full_group:
        var g_inv := g.inverse()
        for h in subgroup:
            var conjugate := g.compose(h).compose(g_inv)
            if not _contains(subgroup, conjugate):
                return false
    return true

## Helper: check if a permutation is in an array.
static func _contains(arr: Array[Permutation], p: Permutation) -> bool:
    for q in arr:
        if q.equals(p):
            return true
    return false
```

### 4.2 Complexity analysis

For Act 2 levels, groups are small (|G| ≤ 24, typically 8-12):
- `is_closed()`: O(|H|² × |H|) — at most 24² × 24 = 13,824 comparisons. **Instant.**
- `generate_subgroup()`: O(|G|³) worst case — at most 13,824. **Instant.**
- `is_normal_subgroup()`: O(|G| × |H| × |H|) — at most 13,824. **Instant.**

No performance concerns for these group sizes.

---

## 5. KeyRing Extensions

### 5.1 New methods in `key_ring.gd`

```gdscript
# ──── Subgroup checking (Act 2) ────

func check_subgroup(key_indices: Array[int]) -> Dictionary:
    ## Check if the subset of keys at given indices forms a subgroup.
    ## Returns: {
    ##   "is_subgroup": bool,
    ##   "missing": Array[Dictionary],  # missing compositions
    ##   "has_identity": bool,
    ##   "has_inverses": bool,
    ##   "is_closed": bool,
    ##   "subset_size": int
    ## }
    var subset: Array[Permutation] = get_subset(key_indices)
    if subset.is_empty():
        return {"is_subgroup": false, "missing": [], "has_identity": false,
                "has_inverses": false, "is_closed": false, "subset_size": 0}

    var has_id := false
    for p in subset:
        if p.is_identity():
            has_id = true
            break

    var has_inv := true
    for p in subset:
        if not _subset_contains(subset, p.inverse()):
            has_inv = false
            break

    var is_closed := SubgroupChecker.is_closed(subset)
    var missing := SubgroupChecker.find_missing_products(subset) if not is_closed else []

    return {
        "is_subgroup": has_id and has_inv and is_closed,
        "missing": missing,
        "has_identity": has_id,
        "has_inverses": has_inv,
        "is_closed": is_closed,
        "subset_size": subset.size(),
    }

func get_subset(key_indices: Array[int]) -> Array[Permutation]:
    ## Extract permutations at the given indices.
    var result: Array[Permutation] = []
    for idx in key_indices:
        if idx >= 0 and idx < found.size():
            result.append(found[idx])
    return result

func _subset_contains(subset: Array[Permutation], p: Permutation) -> bool:
    for q in subset:
        if q.equals(p):
            return true
    return false
```

### 5.2 Integration notes

- `check_subgroup()` is the main API for the inner door mechanic
- It returns a **rich result** so the UI can show detailed feedback:
  - If not closed: show which compositions are missing
  - If no identity: tell player "this set doesn't include the 'do nothing' key"
  - If no inverses: tell player "some keys don't have their reverse"
- `SubgroupChecker` does the heavy math; `KeyRing` wraps it with index-based access

---

## 6. InnerDoorPanel — UI Component

New file: `src/game/inner_door_panel.gd`

### 6.1 Design overview

```
┌──────────────────────────────────────────────────────┐
│  Внутренние двери                                     │
│                                                       │
│  ┌─────────────────────┐  ┌─────────────────────┐    │
│  │ 🚪 Дверь вращений   │  │ 🔒 Дверь отражения  │    │
│  │ Порядок: 4          │  │ Порядок: 2          │    │
│  │ ✅ ОТКРЫТА          │  │ Выберите ключи...   │    │
│  └─────────────────────┘  └─────────────────────┘    │
│                                                       │
│  Ваш выбор:                                          │
│  [✓] Тождество  [✓] Поворот 120°  [ ] Отражение     │
│  [✓] Поворот 240°  [ ] ...                           │
│                                                       │
│  [  ОТКРЫТЬ ДВЕРЬ  ]    (4 из 4 ключей выбрано)      │
└──────────────────────────────────────────────────────┘
```

### 6.2 Class design

```gdscript
class_name InnerDoorPanel
extends PanelContainer
## UI panel for the Inner Doors mechanic (Act 2, Levels 13-16).
## Displays doors, allows key selection, validates subgroup closure.

signal door_opened(door_id: String)
signal door_attempt_failed(door_id: String, reason: Dictionary)

# ── State ──
var doors_data: Array[Dictionary] = []      # From level JSON inner_doors[]
var subgroups_data: Array[Dictionary] = []   # From level JSON subgroups[]
var door_states: Dictionary = {}             # door_id -> "locked" | "opened"
var selected_door_id: String = ""            # Currently selected door
var selected_key_indices: Array[int] = []    # Checked key indices

# ── References ──
var key_ring: KeyRing = null                 # Reference to level's KeyRing
var level_scene: LevelScene = null           # Parent level scene

# ── UI Elements ──
var door_buttons: Dictionary = {}            # door_id -> Button
var key_checkboxes: Array[CheckBox] = []
var open_button: Button = null
var status_label: Label = null
var key_selection_container: VBoxContainer = null

func setup(p_doors: Array, p_subgroups: Array, p_key_ring: KeyRing,
           p_level_scene: LevelScene) -> void:
    doors_data.clear()
    for d in p_doors:
        doors_data.append(d)
    subgroups_data.clear()
    for s in p_subgroups:
        subgroups_data.append(s)
    key_ring = p_key_ring
    level_scene = p_level_scene

    # Initialize door states
    door_states.clear()
    for door in doors_data:
        door_states[door["id"]] = "locked"

    _build_ui()

func _build_ui() -> void:
    # ... (creates door buttons, key checkboxes, open button)
    pass

func refresh_keys() -> void:
    ## Called when KeyRing changes (new key found).
    ## Rebuilds key checkboxes with current found keys.
    _rebuild_key_checkboxes()

func _on_door_selected(door_id: String) -> void:
    selected_door_id = door_id
    selected_key_indices.clear()
    _rebuild_key_checkboxes()

func _on_key_toggled(index: int, pressed: bool) -> void:
    if pressed:
        if index not in selected_key_indices:
            selected_key_indices.append(index)
    else:
        selected_key_indices.erase(index)
    _update_open_button_state()

func _on_open_pressed() -> void:
    if selected_door_id.is_empty() or key_ring == null:
        return

    # Find the target subgroup for this door
    var door_data := _get_door_data(selected_door_id)
    if door_data.is_empty():
        return

    var target_sg := _get_subgroup_data(door_data["subgroup_id"])
    if target_sg.is_empty():
        return

    # Validate: check if selected keys form the required subgroup
    var result := key_ring.check_subgroup(selected_key_indices)

    if not result["is_subgroup"]:
        # NOT a subgroup — crack animation + diagnostic feedback
        var reason := _build_failure_reason(result)
        door_attempt_failed.emit(selected_door_id, reason)
        _play_crack_animation(selected_door_id)
        _show_failure_feedback(reason)
        return

    # IS a subgroup — check if it matches the target
    var selected_perms := key_ring.get_subset(selected_key_indices)
    if _matches_target_subgroup(selected_perms, target_sg):
        # Correct subgroup found!
        door_states[selected_door_id] = "opened"
        door_opened.emit(selected_door_id)
        _play_open_animation(selected_door_id)
        _show_success_feedback(door_data)
    else:
        # Valid subgroup but wrong one for this door
        # Still acknowledge it's a valid subgroup!
        door_attempt_failed.emit(selected_door_id, {
            "reason": "wrong_subgroup",
            "message": "Это подгруппа, но не та, которая нужна для этой двери!"
        })
        _play_wrong_subgroup_animation(selected_door_id)

func _matches_target_subgroup(selected: Array[Permutation],
                               target_sg: Dictionary) -> bool:
    ## Check if the selected permutations match the target subgroup elements.
    var target_element_ids: Array = target_sg.get("elements", [])
    if selected.size() != target_element_ids.size():
        return false
    # Get target permutations from level data
    var target_perms := level_scene.target_perms
    for elem_id in target_element_ids:
        var target_p: Permutation = target_perms.get(elem_id)
        if target_p == null:
            return false
        var found_match := false
        for sel_p in selected:
            # Compare rebased permutations
            var rebased := sel_p
            if level_scene._rebase_inverse != null:
                rebased = sel_p.compose(level_scene._rebase_inverse)
            if rebased.equals(target_p):
                found_match = true
                break
        if not found_match:
            return false
    return true

func _build_failure_reason(result: Dictionary) -> Dictionary:
    if not result["has_identity"]:
        return {"reason": "no_identity",
                "message": "Набор не содержит Тождество — 'ничего не делать' тоже ключ!"}
    if not result["has_inverses"]:
        return {"reason": "no_inverses",
                "message": "Не у всех ключей есть обратный — набор не замкнут!"}
    if not result["is_closed"]:
        var missing = result["missing"]
        if missing.size() > 0:
            return {"reason": "not_closed",
                    "message": "Комбинация двух выбранных ключей даёт ключ вне набора!",
                    "missing_count": missing.size()}
    return {"reason": "unknown", "message": "Это не подгруппа."}

func is_all_doors_opened() -> bool:
    for door_id in door_states:
        if door_states[door_id] != "opened":
            return false
    return true

func get_opened_count() -> int:
    var count := 0
    for door_id in door_states:
        if door_states[door_id] == "opened":
            count += 1
    return count

func get_state() -> Dictionary:
    ## Serializable state for Agent Bridge / save system.
    return {
        "doors": door_states.duplicate(),
        "selected_door": selected_door_id,
        "selected_keys": selected_key_indices.duplicate(),
        "all_opened": is_all_doors_opened(),
    }

# ── Animation stubs ──

func _play_open_animation(door_id: String) -> void:
    # Tween: door icon changes from 🔒 to 🚪, green glow burst
    pass

func _play_crack_animation(door_id: String) -> void:
    # Tween: door shakes, red crack lines appear briefly
    pass

func _play_wrong_subgroup_animation(door_id: String) -> void:
    # Tween: door pulses yellow — acknowledged but wrong target
    pass

func _show_failure_feedback(reason: Dictionary) -> void:
    # Show reason message near the door
    pass

func _show_success_feedback(door_data: Dictionary) -> void:
    # Show reward_text
    pass

func _get_door_data(door_id: String) -> Dictionary:
    for d in doors_data:
        if d["id"] == door_id:
            return d
    return {}

func _get_subgroup_data(sg_id: String) -> Dictionary:
    for s in subgroups_data:
        if s["id"] == sg_id:
            return s
    return {}

func _rebuild_key_checkboxes() -> void:
    pass

func _update_open_button_state() -> void:
    pass
```

### 6.3 Design decisions

**D1: Any valid subgroup or only the target?**
Each inner door has a **specific target subgroup** (defined in JSON). The player must find THAT subgroup. However, if they select a valid subgroup that doesn't match, we give positive feedback ("It IS a subgroup, but not the right one for this door!"). This teaches the concept without frustration.

**D2: Must all keys be found first?**
No. The player can attempt to open doors AS they find keys. This encourages experimentation. The door panel refreshes whenever a new key is found.

**D3: Checkbox vs drag-to-door?**
**Checkbox** for MVP (simpler, mobile-friendly). Drag-to-door can be added as polish in S006+.

**D4: Panel placement?**
The inner door panel appears **below the key list** on the right side (position ~(880, 360)). It's only visible when `inner_doors` is non-empty.

---

## 7. InnerDoorVisual — Graph Decoration

New file: `src/visual/inner_door_visual.gd`

### 7.1 Design

```gdscript
class_name InnerDoorVisual
extends Node2D
## Visual representation of an inner door on the graph.
## Decorative element — no gameplay logic.

enum DoorState { LOCKED, OPENED, CRACKING }

var door_id: String = ""
var door_state: DoorState = DoorState.LOCKED
var visual_hint: String = "circular_glow"

func setup(p_door_id: String, p_position: Vector2, p_visual_hint: String) -> void:
    door_id = p_door_id
    position = p_position
    visual_hint = p_visual_hint
    _build_visual()

func set_state(state: DoorState) -> void:
    door_state = state
    _update_visual()

func _build_visual() -> void:
    ## Creates the door visual based on visual_hint style.
    ## Styles: circular_glow (rotation subgroup), mirror_shimmer (reflection),
    ##         diamond_pulse (generic)
    pass

func _update_visual() -> void:
    ## Updates visual based on current state (locked/opened/cracking).
    pass

func play_open_animation() -> void:
    ## Door opens: golden glow expands, particles burst outward.
    set_state(DoorState.OPENED)

func play_crack_animation() -> void:
    ## Door cracks: red lines appear, shake, then fade.
    set_state(DoorState.CRACKING)
    # Auto-return to LOCKED after animation
    var tween := create_tween()
    tween.tween_interval(1.5)
    tween.tween_callback(func(): set_state(DoorState.LOCKED))
```

### 7.2 Placement strategy

- If `position` is specified in JSON → place there (absolute coords)
- If `position` is null → auto-place at **graph centroid** offset by door index
- Doors are placed on the `edge_container` layer (between edges and crystals)

---

## 8. LevelScene Integration

### 8.1 Changes to `_build_level()`

After existing key ring and graph setup, add inner door initialization:

```gdscript
# ── In _build_level(), after KeyRing initialization ──

# Inner Doors (Act 2)
var inner_doors_data: Array = level_data.get("inner_doors", [])
var subgroups_data: Array = level_data.get("subgroups", [])
_inner_door_panel = null
_inner_door_visuals.clear()

if inner_doors_data.size() > 0:
    _setup_inner_doors(inner_doors_data, subgroups_data)
```

### 8.2 New member variables in LevelScene

```gdscript
# ── Inner Doors (Act 2) ──
var _inner_door_panel: InnerDoorPanel = null
var _inner_door_visuals: Dictionary = {}  # door_id -> InnerDoorVisual
```

### 8.3 New methods in LevelScene

```gdscript
func _setup_inner_doors(doors_data: Array, subgroups_data: Array) -> void:
    # Create inner door panel in HUD
    _inner_door_panel = InnerDoorPanel.new()
    _inner_door_panel.name = "InnerDoorPanel"
    _inner_door_panel.setup(doors_data, subgroups_data, key_ring, self)
    hud_layer.add_child(_inner_door_panel)

    # Connect signals
    _inner_door_panel.door_opened.connect(_on_inner_door_opened)
    _inner_door_panel.door_attempt_failed.connect(_on_inner_door_failed)

    # Create visual elements on graph
    for door_data in doors_data:
        var visual := InnerDoorVisual.new()
        var pos_arr = door_data.get("position", null)
        var pos := Vector2(640, 350)  # default center
        if pos_arr is Array and pos_arr.size() >= 2:
            pos = Vector2(pos_arr[0], pos_arr[1])
        visual.setup(door_data["id"], pos,
                     door_data.get("visual_hint", "circular_glow"))
        edge_container.add_child(visual)
        _inner_door_visuals[door_data["id"]] = visual

func _on_inner_door_opened(door_id: String) -> void:
    # Update visual
    if door_id in _inner_door_visuals:
        _inner_door_visuals[door_id].play_open_animation()

    # Play celebration feedback
    feedback_fx.play_valid_feedback(crystals.values(), edges)

    # Check if ALL doors opened → enhanced completion
    if _inner_door_panel and _inner_door_panel.is_all_doors_opened():
        _on_all_doors_opened()

func _on_inner_door_failed(door_id: String, reason: Dictionary) -> void:
    # Update visual
    if door_id in _inner_door_visuals:
        _inner_door_visuals[door_id].play_crack_animation()

func _on_all_doors_opened() -> void:
    # Show special feedback: "All inner doors opened!"
    var hint_label = hud_layer.get_node_or_null("HintLabel")
    if hint_label:
        hint_label.text = "Все внутренние двери открыты!"
        var tween := create_tween()
        tween.tween_property(hint_label, "theme_override_colors/font_color",
            Color(1.0, 0.85, 0.3, 1.0), 0.3)
```

### 8.4 Modification to `_update_counter()` / key discovery

When a new key is found, refresh the inner door panel:

```gdscript
# ── In existing _validate_permutation(), after key_ring.add_key() succeeds ──

# Refresh inner door panel with new key
if _inner_door_panel:
    _inner_door_panel.refresh_keys()
```

### 8.5 Modification to `_on_level_complete()`

```gdscript
# ── In existing _on_level_complete() ──

# Disable inner door panel
if _inner_door_panel:
    _inner_door_panel.set_process_input(false)
```

### 8.6 Modification to `_clear_level()`

```gdscript
# ── In existing _clear_level() ──

# Clean up inner doors
if _inner_door_panel:
    _inner_door_panel.queue_free()
    _inner_door_panel = null
for visual in _inner_door_visuals.values():
    visual.queue_free()
_inner_door_visuals.clear()
```

---

## 9. HallTree / Progression Integration

### 9.1 Extended completion model

Currently, `HallProgressionEngine` tracks two states per hall:
- `COMPLETED` — all keys found
- `PERFECT` — all keys found + no level 3 hints

For Act 2, we add a richer model:

```gdscript
# In HallProgressionEngine or GameManager save data:

# Extended level_states dictionary:
# level_id -> {
#   "completed": true,          # All keys found
#   "perfect_seal": true,       # No level 3 hints used
#   "inner_doors_opened": 3,    # How many inner doors opened
#   "inner_doors_total": 3,     # Total inner doors in level
#   "all_doors_opened": true,   # All doors opened
# }
```

### 9.2 Modified `complete_hall()` call

```gdscript
# In LevelScene._on_level_complete():
var level_state := {
    "completed": true,
    "perfect_seal": not (echo_hint_system and echo_hint_system.used_solution_hint()),
}

# Add inner door info if applicable
if _inner_door_panel:
    level_state["inner_doors_opened"] = _inner_door_panel.get_opened_count()
    level_state["inner_doors_total"] = _inner_door_panel.doors_data.size()
    level_state["all_doors_opened"] = _inner_door_panel.is_all_doors_opened()

GameManager.complete_level_extended(level_id, level_state)
```

### 9.3 PERFECT seal definition for Act 2

```
PERFECT = all keys found
         + all inner doors opened
         + no level 3 echo hints used
```

This is checked in `HallProgressionEngine`:

```gdscript
func _compute_hall_state(hall_id: String) -> HallState:
    var state_data: Dictionary = _get_level_state(hall_id)
    if not state_data.get("completed", false):
        return HallState.AVAILABLE  # or LOCKED
    # Check for PERFECT
    var perfect_seal: bool = state_data.get("perfect_seal", false)
    var all_doors: bool = state_data.get("all_doors_opened", true)  # true if no doors exist
    if perfect_seal and all_doors:
        return HallState.PERFECT
    return HallState.COMPLETED
```

---

## 10. Agent Bridge Extensions

### 10.1 New commands

Two new commands in `agent_bridge.gd`:

```gdscript
# In _dispatch() match block:
"check_subgroup":
    return _cmd_check_subgroup(args, cmd_id)
"open_inner_door":
    return _cmd_open_inner_door(args, cmd_id)
```

### 10.2 Command: `check_subgroup`

```gdscript
func _cmd_check_subgroup(args: Dictionary, cmd_id: int) -> String:
    if not _level_scene:
        return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

    var key_indices = args.get("key_indices", [])
    if key_indices.is_empty():
        return AgentProtocol.error(
            "Missing 'key_indices' array", "MISSING_ARG", cmd_id)

    if not _level_scene.key_ring:
        return AgentProtocol.error(
            "No key ring initialized", "NO_KEYRING", cmd_id)

    # Convert to typed array
    var typed_indices: Array[int] = []
    for idx in key_indices:
        typed_indices.append(int(idx))

    var result: Dictionary = _level_scene.key_ring.check_subgroup(typed_indices)

    # Enrich with key names for readability
    var key_names: Array = []
    for idx in typed_indices:
        key_names.append(_level_scene._get_key_display_name(idx))
    result["key_names"] = key_names

    return AgentProtocol.success(result, [], cmd_id)
```

**Protocol:**
```jsonc
// Request:
{"cmd": "check_subgroup", "args": {"key_indices": [0, 1, 2, 3]}, "id": 42}

// Response (success):
{
  "status": "ok",
  "data": {
    "is_subgroup": true,
    "missing": [],
    "has_identity": true,
    "has_inverses": true,
    "is_closed": true,
    "subset_size": 4,
    "key_names": ["Тождество", "Поворот 90°", "Поворот 180°", "Поворот 270°"]
  },
  "events": [],
  "id": 42
}

// Response (not a subgroup):
{
  "status": "ok",
  "data": {
    "is_subgroup": false,
    "missing": [{"a_index": 1, "b_index": 2, "product": "(0 3 1 2)"}],
    "has_identity": true,
    "has_inverses": false,
    "is_closed": false,
    "subset_size": 3,
    "key_names": ["Тождество", "Поворот 90°", "Отражение"]
  },
  "events": [],
  "id": 42
}
```

### 10.3 Command: `open_inner_door`

```gdscript
func _cmd_open_inner_door(args: Dictionary, cmd_id: int) -> String:
    if not _level_scene:
        return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

    var door_id: String = args.get("door_id", "")
    var key_indices = args.get("key_indices", [])

    if door_id.is_empty():
        return AgentProtocol.error(
            "Missing 'door_id' argument", "MISSING_ARG", cmd_id)
    if key_indices.is_empty():
        return AgentProtocol.error(
            "Missing 'key_indices' array", "MISSING_ARG", cmd_id)

    if not _level_scene._inner_door_panel:
        return AgentProtocol.error(
            "No inner doors in this level", "NO_INNER_DOORS", cmd_id)

    var panel: InnerDoorPanel = _level_scene._inner_door_panel

    # Programmatically select door and keys, then trigger open
    panel.selected_door_id = door_id
    panel.selected_key_indices.clear()
    for idx in key_indices:
        panel.selected_key_indices.append(int(idx))
    panel._on_open_pressed()

    # Return current state
    var state := panel.get_state()
    return AgentProtocol.success(state, [], cmd_id)
```

**Protocol:**
```jsonc
// Request:
{"cmd": "open_inner_door", "args": {"door_id": "door_rotations", "key_indices": [0, 1, 2, 3]}, "id": 43}

// Response (success):
{
  "status": "ok",
  "data": {
    "doors": {"door_rotations": "opened", "door_flip": "locked"},
    "selected_door": "door_rotations",
    "selected_keys": [0, 1, 2, 3],
    "all_opened": false
  },
  "events": [
    {"type": "door_opened", "data": {"door_id": "door_rotations"}, "timestamp_ms": 12345}
  ],
  "id": 43
}
```

### 10.4 Extended `get_state` response

In `_cmd_get_state()`, add inner door state:

```gdscript
# After existing state fields:
if _level_scene._inner_door_panel:
    state["inner_doors"] = _level_scene._inner_door_panel.get_state()
else:
    state["inner_doors"] = null
```

### 10.5 New event type

```gdscript
# In LevelScene, connect inner door signals to emit events:
_inner_door_panel.door_opened.connect(func(door_id):
    # AgentBridge picks this up via signal → _push_event
    pass
)
```

To support this in AgentBridge, add signal connections for inner door events:

```gdscript
# In _connect_level_signals():
if _level_scene._inner_door_panel:
    var panel = _level_scene._inner_door_panel
    if panel.has_signal("door_opened"):
        var cb := func(door_id): _push_event("door_opened", {"door_id": door_id})
        _signal_callbacks["door_opened"] = cb
        panel.door_opened.connect(cb)
    if panel.has_signal("door_attempt_failed"):
        var cb := func(door_id, reason): _push_event("door_attempt_failed",
            {"door_id": door_id, "reason": reason})
        _signal_callbacks["door_attempt_failed"] = cb
        panel.door_attempt_failed.connect(cb)
```

---

## 11. Instruction Panel & Onboarding

### 11.1 New instruction text for Levels 13-16

In `_get_instruction_text()`:

```gdscript
13:
    new_mechanic = "НОВОЕ: Внутренние двери! Некоторые наборы ключей замкнуты — комбинация любых двух из них тоже в наборе. Найдите такие наборы и откройте двери."
14:
    body += "\n\nОбратите внимание: не любой набор ключей подходит. Набор должен быть замкнут — комбинация любых двух выбранных ключей тоже должна быть среди выбранных."
15:
    new_mechanic = "ПОДСКАЗКА: Тождество всегда должно быть в замкнутом наборе."
16:
    body += "\n\nНекоторые двери требуют больших наборов ключей. Попробуйте начать с малых подгрупп."
```

---

## 12. Complete Summary Panel Extension

### 12.1 Inner door info in completion summary

In `_show_complete_summary()`:

```gdscript
# After existing summary fields:

# Inner doors info
if _inner_door_panel and _inner_door_panel.doors_data.size() > 0:
    var doors_label = Label.new()
    doors_label.name = "SummaryDoorsInfo"
    doors_label.add_theme_font_size_override("font_size", 14)
    doors_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    doors_label.position = Vector2(40, 430)  # Below keys list
    doors_label.size = Vector2(720, 25)
    var opened := _inner_door_panel.get_opened_count()
    var total := _inner_door_panel.doors_data.size()
    if opened == total:
        doors_label.text = "Внутренние двери: %d/%d — все открыты!" % [opened, total]
        doors_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.9))
    else:
        doors_label.text = "Внутренние двери: %d/%d (попробуйте открыть остальные!)" % [opened, total]
        doors_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5, 0.8))
    panel.add_child(doors_label)
```

---

## 13. Data Flow Diagram

```
┌──────────────┐     load JSON      ┌──────────────────┐
│  level_XX.json│──────────────────→ │  LevelScene      │
│  + subgroups  │                    │  ._build_level() │
│  + inner_doors│                    └──────┬───────────┘
└──────────────┘                           │
                                           │ setup()
                                    ┌──────▼───────────┐
                                    │ InnerDoorPanel    │
                                    │ (UI: checkboxes,  │
                                    │  open button)     │
                                    └──────┬───────────┘
                                           │
                     ┌─────────────────────┼──────────────────────┐
                     │                     │                      │
              key selection          open_pressed()          door visuals
                     │                     │                      │
              ┌──────▼──────┐    ┌─────────▼────────┐    ┌───────▼────────┐
              │ KeyRing     │    │ SubgroupChecker   │    │ InnerDoorVisual│
              │ .check_     │───→│ .is_closed()      │    │ (graph overlay)│
              │  subgroup() │    │ .is_subgroup()    │    └────────────────┘
              └─────────────┘    │ .find_missing()   │
                                 └──────────────────┘

                    ┌────────────────┐
                    │ AgentBridge    │
                    │ check_subgroup │──→ KeyRing.check_subgroup()
                    │ open_inner_door│──→ InnerDoorPanel._on_open_pressed()
                    │ get_state      │──→ InnerDoorPanel.get_state()
                    └────────────────┘
```

---

## 14. File Structure

### New files:
```
src/core/subgroup_checker.gd          # Pure math: closure, subgroup, normality checks
src/game/inner_door_panel.gd          # UI panel: door list, key selection, open button
src/visual/inner_door_visual.gd       # Graph decoration: door visual element
```

### Modified files:
```
src/core/key_ring.gd                  # +check_subgroup(), +get_subset() (~30 lines)
src/game/level_scene.gd               # +inner door setup/teardown, signal wiring (~80 lines)
src/agent/agent_bridge.gd             # +check_subgroup, +open_inner_door commands (~60 lines)
src/core/hall_progression_engine.gd   # +inner_doors_opened in state (~20 lines)
src/game/game_manager.gd              # +complete_level_extended() method (~15 lines)
data/levels/act2/level_13.json        # New level file (first inner doors level)
data/levels/act2/level_14.json        # New level file
data/levels/act2/level_15.json        # New level file
data/levels/act2/level_16.json        # New level file
```

---

## 15. Story Points & Sprint Prioritization

### 15.1 Estimation (total: ~21 SP)

| Task | SP | Priority | Sprint |
|------|----|----------|--------|
| **SubgroupChecker** — pure math class | 2 | P0 (core) | S005 |
| **KeyRing extensions** — check_subgroup(), get_subset() | 1 | P0 (core) | S005 |
| **Level JSON schema** — define format, create level_13.json | 2 | P0 (core) | S005 |
| **InnerDoorPanel** — UI panel (door buttons, checkboxes, open) | 5 | P0 (core) | S005 |
| **InnerDoorPanel** — failure feedback (crack, diagnostic messages) | 2 | P1 (UX) | S005 |
| **LevelScene integration** — setup/teardown, signal wiring | 2 | P0 (core) | S005 |
| **InnerDoorVisual** — graph decoration (3 styles) | 3 | P1 (visual) | S005/S006 |
| **Agent Bridge** — check_subgroup, open_inner_door commands | 2 | P0 (agent) | S005 |
| **Progression** — inner_doors_opened tracking, PERFECT seal | 1 | P1 (progression) | S005 |
| **Level design** — 4 level JSON files (levels 13-16) | 3 | P0 (content) | S005 |
| **Instruction text** — level 13-16 onboarding messages | 1 | P1 (UX) | S005 |
| **Complete summary** — inner doors info in completion panel | 1 | P1 (UX) | S005 |
| **Unit tests** — SubgroupChecker, KeyRing extensions | 2 | P0 (quality) | S005 |

### 15.2 Sprint plan

**S005 — Inner Doors MVP (~16 SP, ~7-8 days):**
- SubgroupChecker (2 SP)
- KeyRing extensions (1 SP)
- Level JSON schema + level_13.json (2 SP)
- InnerDoorPanel MVP (5 SP)
- LevelScene integration (2 SP)
- Agent Bridge commands (2 SP)
- Unit tests (2 SP)

**S006 — Polish & Content (~8 SP):**
- InnerDoorVisual (3 graph decoration styles) (3 SP)
- Failure feedback animations (2 SP)
- Levels 14-16 JSON (part of level design) (2 SP)
- Progression tracking + PERFECT seal (1 SP)

**Defer to S007+:**
- Drag-to-door interaction (alternative to checkboxes)
- "Impossible halls" (redesign.md point 5) — requires normality (Levels 17-20)
- Coset visualization
- Cayley table subgroup highlighting

---

## 16. Risk Analysis

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Subgroup check too slow** | Low | Very Low | Groups ≤ 24 elements, O(n³) is instant |
| **Rebase confusion** | Medium | Medium | `check_subgroup()` works on raw permutations; rebasing only for display names |
| **Mobile UI too cramped** | Medium | Medium | InnerDoorPanel as a collapsible panel; test on 720×1280 early |
| **Level design quality** | High | Medium | Start with D4 (well-understood subgroups); test with agent before human playtest |
| **Act 1 regression** | High | Low | All new code gated by `inner_doors.size() > 0`; Act 1 JSON has no inner_doors |
| **Rebase + subgroup matching** | Medium | Medium | `_matches_target_subgroup()` rebases each selected perm before comparing to JSON targets |

---

## 17. Open Questions

1. **Should inner doors be openable BEFORE all keys are found?**
   Current design: YES — the player can open doors as soon as they have the right subset. This encourages experimentation.
   Alternative: Require all keys first, then reveal inner doors as a post-completion challenge.
   **Recommendation:** Allow early opening (current design). It's more engaging.

2. **How to handle "any valid subgroup" vs "specific target subgroup"?**
   Current design: Each door requires a SPECIFIC subgroup defined in JSON.
   Alternative: Accept ANY valid subgroup of the correct order.
   **Recommendation:** Specific subgroup (current design). It's more educational — the player learns WHICH subsets are closed. For Act 2 Level 16 we can add a "free door" that accepts any subgroup.

3. **Visual placement of door decorations on the graph?**
   Option A: Manual positions in JSON (designer control).
   Option B: Auto-calculate from subgroup elements' positions.
   **Recommendation:** Manual with auto-fallback (current design: `position` field, nullable).

4. **Subgroup normality display for Levels 17-20?**
   The `is_normal` field is already in the JSON schema but **NOT used in Levels 13-16**. It's forward-compatible for when we implement conjugation checking in S007.

---

## 18. Appendix A: Example Level — act2_level13.json

```jsonc
{
  "meta": {
    "id": "act2_level13",
    "act": 2,
    "level": 13,
    "title": "Первая внутренняя дверь",
    "subtitle": "Какие ключи образуют замкнутый набор?",
    "group_name": "Z6",
    "group_order": 6
  },
  "graph": {
    "nodes": [
      {"id": 0, "color": "blue", "position": [640, 200], "label": "A"},
      {"id": 1, "color": "blue", "position": [840, 300], "label": "B"},
      {"id": 2, "color": "blue", "position": [840, 500], "label": "C"},
      {"id": 3, "color": "blue", "position": [640, 600], "label": "D"},
      {"id": 4, "color": "blue", "position": [440, 500], "label": "E"},
      {"id": 5, "color": "blue", "position": [440, 300], "label": "F"}
    ],
    "edges": [
      {"from": 0, "to": 1, "type": "standard", "weight": 1},
      {"from": 1, "to": 2, "type": "standard", "weight": 1},
      {"from": 2, "to": 3, "type": "standard", "weight": 1},
      {"from": 3, "to": 4, "type": "standard", "weight": 1},
      {"from": 4, "to": 5, "type": "standard", "weight": 1},
      {"from": 5, "to": 0, "type": "standard", "weight": 1}
    ]
  },
  "symmetries": {
    "automorphisms": [
      {"id": "e",  "mapping": [0,1,2,3,4,5], "name": "Тождество",       "description": "Всё на месте"},
      {"id": "r1", "mapping": [1,2,3,4,5,0], "name": "Поворот 60°",     "description": "Один шаг"},
      {"id": "r2", "mapping": [2,3,4,5,0,1], "name": "Поворот 120°",    "description": "Два шага"},
      {"id": "r3", "mapping": [3,4,5,0,1,2], "name": "Поворот 180°",    "description": "Три шага"},
      {"id": "r4", "mapping": [4,5,0,1,2,3], "name": "Поворот 240°",    "description": "Четыре шага"},
      {"id": "r5", "mapping": [5,0,1,2,3,4], "name": "Поворот 300°",    "description": "Пять шагов"}
    ],
    "generators": ["r1"],
    "cayley_table": {
      "e":  {"e":"e",  "r1":"r1","r2":"r2","r3":"r3","r4":"r4","r5":"r5"},
      "r1": {"e":"r1", "r1":"r2","r2":"r3","r3":"r4","r4":"r5","r5":"e"},
      "r2": {"e":"r2", "r1":"r3","r2":"r4","r3":"r5","r4":"e",  "r5":"r1"},
      "r3": {"e":"r3", "r1":"r4","r2":"r5","r3":"e",  "r4":"r1","r5":"r2"},
      "r4": {"e":"r4", "r1":"r5","r2":"e",  "r3":"r1","r4":"r2","r5":"r3"},
      "r5": {"e":"r5", "r1":"e",  "r2":"r1","r3":"r2","r4":"r3","r5":"r4"}
    }
  },
  "subgroups": [
    {
      "id": "sg_half_turns",
      "name": "Полуповороты",
      "order": 2,
      "elements": ["e", "r3"],
      "generators": ["r3"],
      "is_normal": true,
      "description": "Тождество и поворот на 180°"
    },
    {
      "id": "sg_third_turns",
      "name": "Треть-повороты",
      "order": 3,
      "elements": ["e", "r2", "r4"],
      "generators": ["r2"],
      "is_normal": true,
      "description": "Повороты на 0°, 120°, 240°"
    }
  ],
  "inner_doors": [
    {
      "id": "door_half",
      "subgroup_id": "sg_half_turns",
      "name": "Дверь полуповоротов",
      "visual_hint": "diamond_pulse",
      "position": [640, 400],
      "unlock_condition": "subgroup_found",
      "reward_text": "Тождество + 180° — два элемента, замкнутых друг на друге!",
      "difficulty": "easy"
    },
    {
      "id": "door_thirds",
      "subgroup_id": "sg_third_turns",
      "name": "Дверь треть-поворотов",
      "visual_hint": "circular_glow",
      "position": [640, 400],
      "unlock_condition": "subgroup_found",
      "reward_text": "0°, 120°, 240° — треугольник внутри шестиугольника!",
      "difficulty": "medium"
    }
  ],
  "mechanics": {
    "allowed_actions": ["swap"],
    "show_cayley_button": true,
    "show_generators_hint": true,
    "inner_doors": ["door_half", "door_thirds"],
    "palette": null
  },
  "visuals": {
    "background_theme": "stone_vault",
    "ambient_particles": "dust_motes",
    "crystal_style": "basic_gem",
    "edge_style": "thin_thread"
  },
  "hints": [
    {"trigger": "after_first_valid", "text": "Отлично! Теперь ищите замкнутые наборы ключей."},
    {"trigger": "after_3_found", "text": "Попробуйте выбрать Тождество и Поворот 180° — замкнут ли этот набор?"}
  ],
  "echo_hints": [
    {"text": "Замкнутый набор — значит комбинация любых двух ключей из набора тоже в наборе.", "target_crystals": []},
    {"text": "Начните с маленького: Тождество + один ключ. Какой ключ сам себе обратный?", "target_crystals": []},
    {"text": "Поворот на 180° два раза = 360° = Тождество. Набор {e, r3} замкнут!", "target_crystals": [0, 3]}
  ]
}
```

---

## 19. Appendix B: SubgroupChecker Unit Test Plan

```gdscript
# test/test_subgroup_checker.gd

func test_identity_is_subgroup():
    var e := Permutation.create_identity(3)
    assert(SubgroupChecker.is_subgroup([e]) == true)

func test_z3_is_subgroup():
    var e := Permutation.from_array([0,1,2])
    var r1 := Permutation.from_array([1,2,0])
    var r2 := Permutation.from_array([2,0,1])
    assert(SubgroupChecker.is_subgroup([e, r1, r2]) == true)

func test_non_subgroup_missing_identity():
    var r1 := Permutation.from_array([1,2,0])
    var r2 := Permutation.from_array([2,0,1])
    assert(SubgroupChecker.is_subgroup([r1, r2]) == false)

func test_non_subgroup_not_closed():
    var e := Permutation.from_array([0,1,2])
    var r1 := Permutation.from_array([1,2,0])
    # {e, r1} is not closed: r1*r1 = r2 not in set
    assert(SubgroupChecker.is_closed([e, r1]) == false)

func test_find_missing_products():
    var e := Permutation.from_array([0,1,2])
    var r1 := Permutation.from_array([1,2,0])
    var missing := SubgroupChecker.find_missing_products([e, r1])
    assert(missing.size() == 1)  # r1 * r1 = r2 missing

func test_generate_subgroup_from_generator():
    var r1 := Permutation.from_array([1,2,0])
    var generated := SubgroupChecker.generate_subgroup([r1])
    assert(generated.size() == 3)  # {e, r1, r2}

func test_is_normal_subgroup():
    # In Z6, {e, r3} is normal (Z6 is abelian)
    var all := [
        Permutation.from_array([0,1,2,3,4,5]),
        Permutation.from_array([1,2,3,4,5,0]),
        Permutation.from_array([2,3,4,5,0,1]),
        Permutation.from_array([3,4,5,0,1,2]),
        Permutation.from_array([4,5,0,1,2,3]),
        Permutation.from_array([5,0,1,2,3,4]),
    ]
    var subgroup := [all[0], all[3]]  # {e, r3}
    assert(SubgroupChecker.is_normal_subgroup(subgroup, all) == true)

func test_not_normal_subgroup():
    # In S3, {e, (0 1)} is NOT normal
    var e := Permutation.from_array([0,1,2])
    var s := Permutation.from_array([1,0,2])
    var r := Permutation.from_array([1,2,0])
    var all_s3 := [e, s, r, r.compose(r), s.compose(r), r.compose(s)]
    assert(SubgroupChecker.is_normal_subgroup([e, s], all_s3) == false)
```

---

## 20. Appendix C: Migration Checklist

- [ ] Create `src/core/subgroup_checker.gd`
- [ ] Add `check_subgroup()`, `get_subset()` to `key_ring.gd`
- [ ] Create `src/game/inner_door_panel.gd`
- [ ] Create `src/visual/inner_door_visual.gd`
- [ ] Add inner door setup/teardown to `level_scene.gd`
- [ ] Add `check_subgroup` command to `agent_bridge.gd`
- [ ] Add `open_inner_door` command to `agent_bridge.gd`
- [ ] Extend `get_state` response with inner_doors
- [ ] Add inner_doors_opened tracking to `hall_progression_engine.gd`
- [ ] Add `complete_level_extended()` to `game_manager.gd`
- [ ] Create `data/levels/act2/level_13.json`
- [ ] Create `data/levels/act2/level_14.json`
- [ ] Create `data/levels/act2/level_15.json`
- [ ] Create `data/levels/act2/level_16.json`
- [ ] Add instruction text for levels 13-16 in `level_scene.gd`
- [ ] Add inner doors info to completion summary panel
- [ ] Write unit tests for SubgroupChecker
- [ ] Write integration tests: load level_13, open doors via agent
- [ ] Test backward compatibility: all Act 1 levels still pass
- [ ] Mobile UI test: inner door panel on 720×1280
