# T086: Layer 2 (Inverse Keys) — Architecture & Design

**Task:** T086
**Status:** Proposal
**Date:** 2026-02-27
**Author:** Architect (Game Systems)

---

## 1. Executive Summary

This document defines the architecture for **Layer 2 (Green / Inverse Keys)** — the second gameplay layer in the unified-map progression system described in `redesign.md` section 0.

**Core concept:** For each automorphism (key) the player found on Layer 1, they must now discover its **inverse** — the key that "undoes" it. The player learns that every symmetry operation is reversible.

**Pedagogical goal:** Internalize the concept: *"Any action can be undone."* This prepares the player for Layer 3 (group axioms), where inverses are one of three required properties.

**Key design decisions:**
1. **Same level JSON files** — Layer 2 data is stored as a new `"layers"` section in existing level JSON files (Option A from task description)
2. **Overlay on existing map** — Layer 2 reuses the same hall_tree graph; halls gain a `layer_progress` field in save data
3. **Pairing mechanic** — Player pairs each key with its inverse by drag-and-drop (or tap-tap selection on mobile)
4. **Additive-only changes** — Layer 1 gameplay is completely unaffected; Layer 2 is a new mode entered from the map

---

## 2. Architecture Overview

### 2.1 Design Principles

| Principle | Description |
|-----------|-------------|
| **Same geography** | Layer 2 uses the same halls (levels) as Layer 1 — player revisits familiar locations |
| **Additive schema** | Level JSON gains an optional `"layers"` object; absence = Layer 1 only (backward compatible) |
| **Layer state in save data** | `GameManager.level_states[hall_id].layer_progress` tracks per-layer completion |
| **Color identity** | Layer 2 UI uses green palette (matching redesign.md spec); Layer 1 = blue |
| **Forward-compatible** | Architecture supports Layers 3-5 without structural changes |

### 2.2 System Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         MAP SCENE                                │
│                                                                  │
│  Hall Node Visual                                                │
│  ┌─────────────────┐                                            │
│  │ act1_level01    │  Layer badges:                              │
│  │ [🔵✓] [🟢·]    │  🔵 = Layer 1 complete                     │
│  │ [🟡·] [🔴·]    │  🟢 = Layer 2 available/in-progress        │
│  └─────────────────┘                                            │
│         │ click (layer 2)                                        │
│         ▼                                                        │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                    LEVEL SCENE                               ││
│  │                   (Layer 2 mode)                              ││
│  │                                                              ││
│  │  ┌────────────┐  ┌──────────────────────────┐               ││
│  │  │ GRAPH VIEW │  │ INVERSE PAIRING PANEL     │               ││
│  │  │ (read-only │  │                           │               ││
│  │  │  crystals) │  │  Key         Inverse      │               ││
│  │  │            │  │  ┌───┐      ┌───┐        │               ││
│  │  │            │  │  │r1 │ ←──→ │ ? │        │               ││
│  │  │            │  │  └───┘      └───┘        │               ││
│  │  │            │  │  ┌───┐      ┌───┐        │               ││
│  │  │            │  │  │r2 │ ←──→ │r2 │ ✓      │               ││
│  │  │            │  │  └───┘      └───┘        │               ││
│  │  │            │  │  ┌───┐      ┌───┐        │               ││
│  │  │            │  │  │s01│ ←──→ │ ? │        │               ││
│  │  │            │  │  └───┘      └───┘        │               ││
│  │  │            │  │                           │               ││
│  │  │            │  │  Candidate Keys:          │               ││
│  │  │            │  │  [r1] [r2] [s01] [s02]   │               ││
│  │  └────────────┘  └──────────────────────────┘               ││
│  └──────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Model

### 3.1 Decision: Layer Data Inside Existing Level JSON (Option A)

**Rationale:** Each layer's tasks are intrinsically tied to a specific hall's group structure. The inverse keys for Z₃ are determined entirely by the Z₃ automorphisms already defined in `level_01.json`. Putting layer metadata in the same file keeps everything in one place and avoids cross-file references that can drift.

**No new level files are needed.** The inverse-key challenge is computationally derivable from the existing `symmetries.automorphisms` — the game computes inverses at runtime using `Permutation.inverse()`. The JSON only needs optional **hints, UI customization, and override data** per layer.

### 3.2 Level JSON Extension

Add an optional `"layers"` object to each level JSON:

```jsonc
{
  "meta": { /* unchanged */ },
  "graph": { /* unchanged */ },
  "symmetries": { /* unchanged */ },
  "mechanics": { /* unchanged — Layer 1 config */ },

  // NEW: Layer-specific configuration
  "layers": {
    "layer_2": {
      "enabled": true,
      "title": "Обратные ключи",
      "subtitle": "Каждое действие можно отменить",
      "instruction": "Для каждого ключа найдите обратный — тот, который отменяет его действие.",

      // Optional: override which keys need inverse-pairing.
      // If omitted, ALL non-identity automorphisms require inverse-pairing.
      // Identity (e) is always pre-paired (inverse of identity is identity).
      "target_pairs": null,

      // Optional: pre-reveal some pairs for tutorial levels.
      // Each entry is [sym_id_key, sym_id_inverse].
      "revealed_pairs": [],

      // Optional: layer-specific hints
      "echo_hints": [
        {
          "text": "Если ключ поворачивает на 120°, какой ключ повернёт обратно?",
          "target_crystals": []
        }
      ],

      // Optional: custom win_condition for this layer.
      // Default: "all_inverses" (all non-identity keys paired).
      "win_condition": "all_inverses"
    },

    // FUTURE: Layer 3-5 configs go here
    "layer_3": { /* ... */ },
    "layer_4": { /* ... */ },
    "layer_5": { /* ... */ }
  }
}
```

**Key design points:**
- `"layers"` is **optional** — if absent, the level only has Layer 1
- `"target_pairs": null` means "derive all pairs from `symmetries.automorphisms`" (default behavior)
- `"revealed_pairs"` allows tutorial scaffolding (e.g., level_01 could pre-reveal that identity maps to itself)
- Each layer config is self-contained within its key (`layer_2`, `layer_3`, etc.)

### 3.3 Inverse Pair Data Structure (Runtime)

At runtime, `InversePairManager` (new class) builds the pair table:

```gdscript
## Runtime data for a single inverse pair
class InversePair:
    var key_sym_id: String       # e.g. "r1"
    var key_perm: Permutation    # [1, 2, 0]
    var key_name: String         # "Поворот на 120°"
    var inverse_sym_id: String   # e.g. "r2"
    var inverse_perm: Permutation # [2, 0, 1]
    var inverse_name: String     # "Поворот на 240°"
    var is_self_inverse: bool    # true if key == inverse (involutions)
    var is_identity: bool        # true for the identity element
    var paired: bool = false     # player has matched this pair
    var revealed: bool = false   # pre-revealed by level config
```

### 3.4 Save Data Extension

`GameManager.level_states` currently stores per-level state. Extend with layer progress:

```jsonc
// In save_data.json → player.level_states
{
  "act1_level01": {
    "found_keys": 3,
    "time_spent": 142,
    "attempts": 7,
    "hints_used": 0,

    // NEW: per-layer progress
    "layer_progress": {
      "layer_1": {
        "status": "completed",     // "locked" | "available" | "in_progress" | "completed" | "perfect"
        "keys_found": 3,
        "total_keys": 3,
        "hints_used": 0
      },
      "layer_2": {
        "status": "completed",
        "pairs_found": 2,          // excluding identity (auto-paired)
        "total_pairs": 2,
        "hints_used": 0,
        "paired_keys": ["r1", "r2"]  // sym_ids of keys whose inverses were found
      },
      "layer_3": {
        "status": "locked"
      }
    }
  }
}
```

### 3.5 Hall Tree Extension

`hall_tree.json` does **NOT** need structural changes. The existing wing/gate/threshold system handles inter-act progression. Layer progression is orthogonal — it's tracked in save data, not in the world graph.

However, we add a **layer-aware query API** to `HallProgressionEngine`:

```gdscript
## Get the layer completion status for a hall
func get_layer_state(hall_id: String, layer: int) -> String:
    # Returns: "locked", "available", "in_progress", "completed", "perfect"

## Count how many halls have completed a given layer (within a wing or globally)
func count_layer_completed(wing_id: String, layer: int) -> int:

## Check if a layer is globally unlocked (enough prior-layer halls completed)
func is_layer_unlocked(layer: int) -> bool:
```

---

## 4. Gameplay Flow

### 4.1 Entering Layer 2

```
MAP SCENE
  │
  ├─ Player sees hall with Layer 1 completed (blue badge ✓)
  │  Next to it: Layer 2 badge (green, pulsing = available)
  │
  ├─ Player taps the green badge (or the hall, if Layer 2 is the current active layer)
  │
  ▼
LEVEL SCENE loads in LAYER 2 MODE
  │
  ├─ Graph is displayed read-only (crystals in their identity positions, not draggable)
  ├─ Room map shows all discovered rooms from Layer 1 (greyed out, for reference)
  ├─ InversePairingPanel opens in the right panel area
  │
  ▼
PAIRING PHASE
```

### 4.2 The Inverse Pairing Mechanic

**UI Layout (Split-Screen, reusing existing HUD zones):**

```
┌────────────────────────┬──────────────────────────────┐
│                        │  INVERSE PAIRING PANEL       │
│   GRAPH VIEW           │                              │
│   (read-only)          │  ┌─ Pair 1 ──────────────┐  │
│                        │  │ [r1: 120°] ↔ [?????]  │  │
│   Shows crystal graph  │  └───────────────────────┘  │
│   with labels.         │  ┌─ Pair 2 ──────────────┐  │
│   Crystals pulse when  │  │ [r2: 240°] ↔ [?????]  │  │
│   player hovers a key. │  └───────────────────────┘  │
│                        │  ┌─ Pair 3 ──────────────┐  │
│   Tapping a key in the │  │ [s01: отр.] ↔ [s01] ✓│  │
│   panel animates the   │  └───────────────────────┘  │
│   permutation on the   │                              │
│   graph (visual only). │  ─── Available Keys ───      │
│                        │  [e] [r1] [r2] [s01] [s02]  │
│                        │  [s12]                       │
├────────────────────────┴──────────────────────────────┤
│  STATUS BAR: "Найдите обратный для каждого ключа"     │
│  Progress: 1/3 pairs matched                          │
└───────────────────────────────────────────────────────┘
```

### 4.3 Interaction Flow (Step-by-Step)

1. **Panel displays all non-identity keys** in the left column of the pairing panel
   - Identity (e) is shown at the top with "e ↔ e ✓" pre-paired (grayed, completed)
   - Self-inverse keys (involutions, like reflections where `s⁻¹ = s`) are listed normally

2. **Player selects a key slot** (left column) — this becomes the "active key"
   - The graph animates showing this key's permutation (crystals glow and shift)
   - The key's name and cycle notation are displayed prominently

3. **Player drags a candidate key** from the "Available Keys" pool to the inverse slot
   - **OR** taps a candidate key (mobile-friendly alternative)
   - When hovering/selecting a candidate, the graph shows a **composition animation**: apply the original key, then apply the candidate. If the result is identity, all crystals return to their original positions (satisfying visual feedback)

4. **Validation occurs immediately** on drop/tap:
   - If `key.compose(candidate).is_identity()` → **correct!** Pair is locked with ✓
   - If incorrect → gentle shake animation, candidate bounces back, hint: "Результат — не тождество. Попробуйте другой ключ."

5. **Visual feedback for correct pairing:**
   - Graph animates: apply key → apply inverse → crystals return to identity
   - Green glow on both paired keys
   - Progress counter increments
   - If pair was a self-inverse (involution), special callout: "Этот ключ — сам себе обратный!"

6. **Level complete** when all pairs are matched:
   - Green completion animation
   - Layer 2 badge on map turns green-complete
   - Summary screen shows all inverse pairs with the insight: "Каждое действие можно отменить"

### 4.4 Alternative Interaction: Composition Testing Area

For pedagogical depth, add an optional **"Composition Lab"** zone below the pairing panel:

```
┌─ Зона Композиции ─────────────────┐
│  [Slot A]  ∘  [Slot B]  =  [???]  │
│                                     │
│  Перетащите два ключа, чтобы       │
│  увидеть их композицию.            │
└─────────────────────────────────────┘
```

- Player drags any two keys into slots A and B
- Game shows the result of `A.compose(B)` visually on the graph AND as a key
- When result is identity: fireworks, "Тождество! Значит, B — обратный к A"
- This is **optional** — not required for completion, but helps build intuition
- Becomes the basis for Layer 3 (full composition table exploration)

---

## 5. Validation Logic

### 5.1 Inverse Verification

The mathematical check is simple and already implemented in `Permutation`:

```gdscript
## Check if candidate is the inverse of key
static func is_inverse_of(key: Permutation, candidate: Permutation) -> bool:
    return key.compose(candidate).is_identity()
    # Equivalent to: candidate.compose(key).is_identity()
    # (because p.compose(p.inverse()) == p.inverse().compose(p) == identity)
```

### 5.2 InversePairManager Validation API

```gdscript
class_name InversePairManager
extends RefCounted

var pairs: Array = []           # Array[InversePair]
var key_ring: KeyRing = null    # Reference to Layer 1's found keys

## Attempt to pair a key with a candidate inverse.
## Returns: {success: bool, reason: String, pair_index: int}
func try_pair(key_sym_id: String, candidate_sym_id: String) -> Dictionary:
    var pair := _find_pair_by_key(key_sym_id)
    if pair == null:
        return {"success": false, "reason": "unknown_key"}
    if pair.paired:
        return {"success": false, "reason": "already_paired"}

    var candidate_perm := _get_perm_by_sym_id(candidate_sym_id)
    if candidate_perm == null:
        return {"success": false, "reason": "unknown_candidate"}

    # THE CORE CHECK: is candidate the inverse of key?
    if pair.key_perm.compose(candidate_perm).is_identity():
        pair.paired = true
        return {"success": true, "reason": "correct", "pair_index": pairs.find(pair)}
    else:
        return {"success": false, "reason": "not_inverse",
                "result_name": _lookup_composition_name(pair.key_perm, candidate_perm)}


## Check if all pairs are matched (Layer 2 complete for this level).
func is_complete() -> bool:
    for pair in pairs:
        if not pair.paired and not pair.is_identity:
            return false
    return true


## Get the composition result as a display name (for "not_inverse" feedback).
func _lookup_composition_name(a: Permutation, b: Permutation) -> String:
    var result: Permutation = a.compose(b)
    # Look up in validation_manager's target_perms for display name
    # ...
```

### 5.3 Layer 2 Completion Criteria

A level's Layer 2 is **complete** when:

1. **All non-identity keys have been paired with their correct inverse** — `InversePairManager.is_complete() == true`
2. Identity is auto-paired (always pre-matched at level start)

**Special cases:**
- **Self-inverse keys** (involutions, e.g., reflections): player must still explicitly pair them with themselves. This teaches that `s ∘ s = e` for involutions.
- **Mutual pairs** (e.g., r1 and r2 where r1⁻¹ = r2 and r2⁻¹ = r1): pairing r1→r2 does NOT auto-complete r2→r1. Player must pair both directions explicitly. This reinforces the concept and is pedagogically valuable.
  - **ALTERNATIVE (simpler UX):** Pairing r1→r2 auto-completes r2→r1 since the relationship is symmetric. **Recommended for mobile UX** — reduces tedium without losing the core insight. Configurable via a `"bidirectional_pairing": true` flag in the layer config.

### 5.4 Mathematical Properties by Group Type

| Group | Order | # Non-trivial pairs | Notes |
|-------|-------|---------------------|-------|
| Z₂ | 2 | 1 (self-inverse) | Trivial — good tutorial |
| Z₃ | 3 | 1 mutual pair (r1↔r2) | First non-trivial case |
| Z₄ | 4 | 1 self-inverse + 1 mutual pair | Mix of both types |
| V₄ (Klein) | 4 | 3 self-inverses | All non-identity elements are involutions |
| Z₅ | 5 | 2 mutual pairs | Pure mutual pairs |
| S₃ | 6 | 1 mutual pair + 3 self-inverses | Reflections are involutions, rotations are mutual |
| Z₆ | 6 | 1 self-inverse + 2 mutual pairs | |
| D₄ | 8 | 1 self-inverse + 1 mutual pair + 4 self-inverses (reflections) | Rich variety |

---

## 6. Progression System

### 6.1 When Layer 2 Unlocks

**Rule:** Layer 2 unlocks globally when the player completes **8 out of 12 Layer 1 halls** (matching the existing wing_1 gate threshold).

This aligns with the existing progression gate:
- Wing 1 gate: 8/12 halls → unlocks Wing 2
- Layer 2 gate: 8/12 Layer 1 completions → unlocks Layer 2 across **all** Layer-1-completed halls

**Implementation:** Reuse the threshold gate pattern. In `HallProgressionEngine`:

```gdscript
## Layer unlock thresholds (configurable)
const LAYER_THRESHOLDS := {
    2: {"required_layer_1_completions": 8, "percentage": 0.67},
    3: {"required_layer_2_completions": 8, "percentage": 0.67},
    4: {"required_layer_3_completions": 8, "percentage": 0.67},
    5: {"required_layer_4_completions": 6, "percentage": 0.50},
}

func is_layer_unlocked(layer: int) -> bool:
    if layer <= 1:
        return true
    var threshold = LAYER_THRESHOLDS.get(layer, {})
    var required: int = threshold.get("required_layer_%d_completions" % (layer - 1), 0)
    var completed := count_layer_completed_globally(layer - 1)
    return completed >= required
```

### 6.2 Per-Hall Layer Availability

A specific hall's Layer 2 is **available** when:
1. Layer 2 is globally unlocked (threshold met)
2. The hall's Layer 1 is completed (player found all keys)

```gdscript
func get_hall_layer_state(hall_id: String, layer: int) -> String:
    if layer <= 0:
        return "locked"
    if layer == 1:
        return get_hall_state(hall_id)  # existing logic

    # Layer 2+: check global unlock + prior layer completion
    if not is_layer_unlocked(layer):
        return "locked"

    var prior_state := get_hall_layer_state(hall_id, layer - 1)
    if prior_state != "completed" and prior_state != "perfect":
        return "locked"

    # Check save data for this layer's progress
    var layer_data := _get_layer_progress(hall_id, layer)
    return layer_data.get("status", "available")
```

### 6.3 Map Visual Indicators

Each hall node on the map shows **layer badges** — small colored dots:

```
┌──────────────┐
│ act1_level01 │
│  Треугольный │
│     зал      │
│              │
│ 🔵✓ 🟢· 🟡🔒│
└──────────────┘
  L1  L2  L3
```

Badge states:
- 🔒 Locked (gray, padlock icon)
- ·  Available (pulsing, layer color)
- ▶  In progress (layer color, partially filled)
- ✓  Completed (layer color, checkmark)
- ⭐ Perfect (layer color, star — no hints used)

### 6.4 Layer-Aware Progression Flow

```
Layer 1 complete (8+ halls)
  │
  ├─ Layer 2 UNLOCKS globally
  │  Green badges appear on all L1-completed halls
  │
  ├─ Player can freely choose which hall to do Layer 2 on
  │  (nonlinear within a layer — same as Layer 1)
  │
  ├─ Layer 2 complete (8+ halls)
  │  │
  │  └─ Layer 3 UNLOCKS globally
  │     Gold badges appear on all L2-completed halls
  │     (future implementation)
  │
  └─ Resonances: new resonance types for Layer 2:
     {"type": "inverse_structure", "description": "Both halls have the same inverse pattern"}
```

---

## 7. File Changes & New Files

### 7.1 New Files

| File | Role | Lines (est.) |
|------|------|-------------|
| `src/core/inverse_pair_manager.gd` | Runtime inverse pair tracking & validation | ~120 |
| `src/game/inverse_pairing_panel.gd` | UI panel for inverse key pairing | ~200 |
| `src/game/composition_lab.gd` | Optional composition testing zone | ~100 |
| `src/game/layer_mode_controller.gd` | Orchestrates layer-specific behavior in LevelScene | ~150 |

### 7.2 Modified Files

| File | Change | Scope |
|------|--------|-------|
| `src/game/level_scene.gd` | Add layer mode detection; delegate to `LayerModeController` | ~30 lines |
| `src/game/game_manager.gd` | Extend `level_states` with `layer_progress`; add `current_layer` field | ~40 lines |
| `src/core/hall_progression_engine.gd` | Add `is_layer_unlocked()`, `get_hall_layer_state()`, `count_layer_completed()` | ~60 lines |
| `src/ui/map_scene.gd` / `hall_node_visual.gd` | Render layer badges on hall nodes | ~50 lines |
| `data/levels/act1/level_01.json` ... `level_12.json` | Add optional `"layers"` section | ~10 lines each |

### 7.3 New File: `src/core/inverse_pair_manager.gd`

```gdscript
class_name InversePairManager
extends RefCounted
## Manages inverse key pairing for Layer 2.
## Given a set of automorphisms, builds inverse pairs and validates player choices.

class InversePair:
    var key_sym_id: String
    var key_perm: Permutation
    var key_name: String
    var inverse_sym_id: String
    var inverse_perm: Permutation
    var inverse_name: String
    var is_self_inverse: bool    # key == inverse (involutions)
    var is_identity: bool
    var paired: bool = false
    var revealed: bool = false

signal pair_matched(pair_index: int, key_sym_id: String, inverse_sym_id: String)
signal all_pairs_matched()

var pairs: Array = []                     # Array[InversePair]
var bidirectional: bool = true            # Pairing A→B auto-pairs B→A
var _sym_id_to_perm: Dictionary = {}      # sym_id → Permutation
var _sym_id_to_name: Dictionary = {}      # sym_id → display name

## Setup from level data and optional layer config
func setup(level_data: Dictionary, layer_config: Dictionary = {}) -> void:
    pairs.clear()
    _sym_id_to_perm.clear()
    _sym_id_to_name.clear()

    var autos: Array = level_data.get("symmetries", {}).get("automorphisms", [])
    for auto in autos:
        var sym_id: String = auto.get("id", "")
        var perm := Permutation.from_array(auto.get("mapping", []))
        _sym_id_to_perm[sym_id] = perm
        _sym_id_to_name[sym_id] = auto.get("name", sym_id)

    # Build inverse pairs
    var processed: Dictionary = {}  # sym_id → true (to avoid duplicate mutual pairs)
    for sym_id in _sym_id_to_perm:
        if processed.has(sym_id):
            continue
        var perm: Permutation = _sym_id_to_perm[sym_id]
        var inv_perm: Permutation = perm.inverse()

        # Find the sym_id of the inverse
        var inv_sym_id := _find_sym_id_for_perm(inv_perm)
        if inv_sym_id == "":
            push_warning("InversePairManager: no inverse found for %s" % sym_id)
            continue

        var pair := InversePair.new()
        pair.key_sym_id = sym_id
        pair.key_perm = perm
        pair.key_name = _sym_id_to_name.get(sym_id, sym_id)
        pair.inverse_sym_id = inv_sym_id
        pair.inverse_perm = inv_perm
        pair.inverse_name = _sym_id_to_name.get(inv_sym_id, inv_sym_id)
        pair.is_self_inverse = (sym_id == inv_sym_id)
        pair.is_identity = perm.is_identity()

        # Auto-pair identity
        if pair.is_identity:
            pair.paired = true
            pair.revealed = true

        pairs.append(pair)

        # Mark both as processed (for bidirectional mode)
        processed[sym_id] = true
        if bidirectional and not pair.is_self_inverse:
            processed[inv_sym_id] = true

    # Apply revealed_pairs from config
    var revealed: Array = layer_config.get("revealed_pairs", [])
    for rp in revealed:
        if rp is Array and rp.size() >= 2:
            _reveal_pair(rp[0], rp[1])

## Attempt to pair key_sym_id with candidate_sym_id
func try_pair(key_sym_id: String, candidate_sym_id: String) -> Dictionary:
    # ... (as shown in section 5.2)

func is_complete() -> bool:
    for pair in pairs:
        if not pair.paired:
            return false
    return true

func get_progress() -> Dictionary:
    var matched := 0
    var total := 0
    for pair in pairs:
        if not pair.is_identity:
            total += 1
            if pair.paired:
                matched += 1
    return {"matched": matched, "total": total}
```

### 7.4 New File: `src/game/layer_mode_controller.gd`

```gdscript
class_name LayerModeController
extends RefCounted
## Orchestrates layer-specific behavior within LevelScene.
## LevelScene delegates to this controller when layer > 1.

enum LayerMode { LAYER_1, LAYER_2_INVERSE, LAYER_3_GROUP, LAYER_4_NORMAL, LAYER_5_QUOTIENT }

var current_layer: LayerMode = LayerMode.LAYER_1
var inverse_pair_mgr: InversePairManager = null
var pairing_panel: InversePairingPanel = null
# Future: var composition_mgr, var conjugation_mgr, etc.

## Initialize for a specific layer
func setup(layer: int, level_data: Dictionary, level_scene: LevelScene) -> void:
    match layer:
        1:
            current_layer = LayerMode.LAYER_1
            # No special setup — default LevelScene behavior
        2:
            current_layer = LayerMode.LAYER_2_INVERSE
            _setup_layer_2(level_data, level_scene)
        # 3, 4, 5: future

func _setup_layer_2(level_data: Dictionary, level_scene: LevelScene) -> void:
    # Disable crystal dragging (graph is read-only on Layer 2)
    for crystal in level_scene.crystals.values():
        crystal.set_draggable(false)

    # Initialize inverse pair manager
    var layer_config: Dictionary = level_data.get("layers", {}).get("layer_2", {})
    inverse_pair_mgr = InversePairManager.new()
    inverse_pair_mgr.setup(level_data, layer_config)

    # Create and show pairing panel
    pairing_panel = InversePairingPanel.new()
    pairing_panel.setup(inverse_pair_mgr, level_scene)
    # ... add to HUD layer

    # Connect signals
    inverse_pair_mgr.pair_matched.connect(_on_pair_matched)
    inverse_pair_mgr.all_pairs_matched.connect(_on_all_pairs_matched)

func is_layer_complete() -> bool:
    match current_layer:
        LayerMode.LAYER_2_INVERSE:
            return inverse_pair_mgr != null and inverse_pair_mgr.is_complete()
        _:
            return false
```

### 7.5 Changes to `src/game/level_scene.gd`

Minimal changes — delegate to `LayerModeController`:

```gdscript
# Add to class variables:
var _layer_controller := LayerModeController.new()
var _current_layer: int = 1  # Set from GameManager before loading

# In _build_level(), after existing setup:
func _build_level() -> void:
    # ... existing Layer 1 setup ...

    # Layer-specific setup
    _current_layer = GameManager.current_layer  # NEW field on GameManager
    if _current_layer > 1:
        _layer_controller.setup(_current_layer, level_data, self)

# Override _is_level_complete:
func _is_level_complete() -> bool:
    if _current_layer > 1:
        return _layer_controller.is_layer_complete()
    # ... existing Layer 1 logic ...
```

### 7.6 Changes to `src/game/game_manager.gd`

```gdscript
# Add to class variables:
var current_layer: int = 1  # Active layer (1-5)

# Extend save/load:
# In save_game():
#   Add "current_layer" to save_data.player
# In load_game():
#   Read "current_layer" from saved data

# Add layer progress helpers:
func get_layer_progress(hall_id: String, layer: int) -> Dictionary:
    var state: Dictionary = level_states.get(hall_id, {})
    var lp: Dictionary = state.get("layer_progress", {})
    return lp.get("layer_%d" % layer, {"status": "locked"})

func set_layer_progress(hall_id: String, layer: int, progress: Dictionary) -> void:
    if not level_states.has(hall_id):
        level_states[hall_id] = {}
    if not level_states[hall_id].has("layer_progress"):
        level_states[hall_id]["layer_progress"] = {}
    level_states[hall_id]["layer_progress"]["layer_%d" % layer] = progress
    save_game()
```

---

## 8. UI Design: InversePairingPanel

### 8.1 Panel Layout

```gdscript
class_name InversePairingPanel
extends Control
## UI panel for Layer 2 inverse key pairing.
## Displays key→inverse slots and a candidate key pool.

# Layout:
# ┌─ Title ─────────────────────────────┐
# │ "Обратные ключи"  Progress: 2/5     │
# ├─────────────────────────────────────┤
# │ PAIR SLOTS (scrollable):            │
# │  ┌──────────────────────────────┐   │
# │  │ [e: Тождество] ↔ [e] ✓     │   │
# │  └──────────────────────────────┘   │
# │  ┌──────────────────────────────┐   │
# │  │ [r1: 120°] ↔ [_DROP_HERE_]  │   │
# │  └──────────────────────────────┘   │
# │  ┌──────────────────────────────┐   │
# │  │ [s01: отр.] ↔ [s01] ✓      │   │
# │  └──────────────────────────────┘   │
# ├─────────────────────────────────────┤
# │ CANDIDATE KEYS (draggable):         │
# │  [r1] [r2] [s01] [s02] [s12]       │
# ├─────────────────────────────────────┤
# │ COMPOSITION LAB (optional):         │
# │  [___] ∘ [___] = [???]             │
# └─────────────────────────────────────┘
```

### 8.2 Interaction Details

**Drag-and-drop (desktop):**
- Candidate keys are draggable tokens at the bottom
- Drop zones are the `[_DROP_HERE_]` slots next to each key
- On hover over a drop zone, the graph shows a preview animation

**Tap-tap (mobile):**
- Tap a pair slot to select it (highlight)
- Tap a candidate key to attempt pairing
- Two-tap selection avoids the need for drag on small screens

**Visual feedback:**
- **Correct pair:** green flash, key locks in place, graph shows key→inverse→identity animation
- **Wrong pair:** red shake, candidate bounces back, message: "r1 ∘ s01 = s02 — не тождество"
- **Self-inverse discovered:** special golden flash, message: "Этот ключ — сам себе обратный! s ∘ s = e"

### 8.3 Graph Animation Support

When the player interacts with the pairing panel, the graph (left side) shows **animations**:

1. **Hover/select a key:** Graph animates the key's permutation (crystals move to show where each element goes)
2. **Hover a candidate for pairing:** Graph animates: key → candidate → result (shows whether it returns to identity)
3. **Correct pair confirmed:** Full animation: key → inverse → identity (crystals return home), with green particle burst

This reuses the existing `SwapManager` animation system — specifically the `_key_apply_phase2` / `_key_apply_phase3` pattern already in `level_scene.gd`. We add a `preview_permutation(perm: Permutation, auto_revert: bool)` method that shows the animation and optionally reverts.

---

## 9. Extensibility to Layers 3-5

### 9.1 Architecture Pattern

Each layer follows the same pattern:

| Component | Layer 2 | Layer 3 | Layer 4 | Layer 5 |
|-----------|---------|---------|---------|---------|
| **Manager** | `InversePairManager` | `GroupClosureManager` | `NormalityChecker` (uses `SubgroupChecker`) | `QuotientBuilder` |
| **Panel** | `InversePairingPanel` | `CompositionTablePanel` | `ConjugationPanel` | `CosetGluingPanel` |
| **Validation** | `p.compose(q).is_identity()` | `KeyRing.is_closed_under_composition()` | `SubgroupChecker.is_normal()` | `SubgroupChecker.coset_decomposition()` |
| **JSON config** | `layers.layer_2` | `layers.layer_3` | `layers.layer_4` | `layers.layer_5` |
| **Save key** | `layer_progress.layer_2` | `layer_progress.layer_3` | `layer_progress.layer_4` | `layer_progress.layer_5` |

### 9.2 LayerModeController as Extension Point

`LayerModeController` is the single orchestrator that selects which manager/panel to instantiate based on the current layer. Adding Layer 3 requires:

1. Create `GroupClosureManager` + `CompositionTablePanel`
2. Add `LayerMode.LAYER_3_GROUP` case in `LayerModeController.setup()`
3. Add `"layer_3"` config support in level JSON
4. Add Layer 3 threshold in `HallProgressionEngine.LAYER_THRESHOLDS`

No changes to LevelScene, GameManager save format, or hall_tree.json.

### 9.3 JSON Schema Extensibility

The `"layers"` object in level JSON is a flat dictionary of layer configs. Each layer key (`layer_2`, `layer_3`, ...) is independent. New layers just add new keys — no structural migration needed:

```jsonc
"layers": {
    "layer_2": { "enabled": true, ... },
    "layer_3": { "enabled": true, "target_compositions": [...] },
    "layer_4": { "enabled": true, "target_subgroups": [...] },
    "layer_5": { "enabled": true, "target_normal_subgroups": [...] }
}
```

---

## 10. Edge Cases & Special Considerations

### 10.1 Trivial Groups (Z₁, Z₂)

- **Z₁** (order 1): Only identity → Layer 2 is auto-complete (no non-identity keys). Treat as pre-completed.
- **Z₂** (order 2): Single non-identity element is self-inverse → one pair to match. Good first tutorial.

### 10.2 Large Groups (D₄ = 8 elements, future: S₄ = 24)

For D₄ with 8 elements:
- Identity: 1 (auto-paired)
- Rotations: r1↔r3 (mutual pair), r2 (self-inverse)
- Reflections: sh, sv, sd1, sd2 (all self-inverse)
- Total pairs to match: **6** (1 mutual + 5 self-inverse, or with bidirectional: 1 + 5 = 6)

The UI must handle scrolling for many pairs. The panel uses a `ScrollContainer` for the pair list.

### 10.3 Player Returns to Layer 1

Player can always go back to Layer 1 from the map (click the blue badge). Layer progress is preserved independently.

### 10.4 Layer 2 Without Layer 1 Keys

Layer 2 is only available after Layer 1 is complete for that hall. This is enforced by `get_hall_layer_state()`.

### 10.5 Rebase Consistency

Layer 2 uses the **same rebasing** as Layer 1. The `InversePairManager` works with sym_ids from the JSON, not raw permutations, so rebasing is handled transparently by the existing `ValidationManager` / `RoomState` infrastructure.

---

## 11. Implementation Order

### Phase 1: Core (Sprint S009, Week 1)
1. **`InversePairManager`** — Pure logic, fully testable
2. **Unit tests** for inverse pair building and validation
3. **`GameManager` extension** — `layer_progress` in save data
4. **`HallProgressionEngine` extension** — `is_layer_unlocked()`, `get_hall_layer_state()`

### Phase 2: UI (Sprint S009, Week 2)
5. **`InversePairingPanel`** — Pair slots + candidate pool
6. **`LayerModeController`** — Wire into LevelScene
7. **Graph preview animations** — Reuse SwapManager patterns
8. **Level JSON updates** — Add `"layers"` to all 12 act1 levels

### Phase 3: Map & Polish (Sprint S009, Week 3)
9. **Map layer badges** — Visual indicators on hall nodes
10. **Composition Lab** — Optional bonus interaction
11. **Echo hints** — Layer 2-specific hint content
12. **Integration testing** — Full play-through of Layer 2

---

## 12. Open Questions

| # | Question | Recommendation | Impact |
|---|----------|---------------|--------|
| 1 | **Bidirectional pairing?** Should pairing r1→r2 auto-complete r2→r1? | **Yes** (reduce tedium, symmetric relationship) | UX simplicity |
| 2 | **Composition Lab mandatory or optional?** | Optional (bonus zone, not required for completion) | Scope control |
| 3 | **Layer 2 on act2 levels?** Act 2 levels have subgroups — should Layer 2 apply there too? | **Yes, eventually** — but prioritize act1 levels first | Scope |
| 4 | **"Невозможные" levels for Layer 2?** | Not applicable — every group element has an inverse. Impossible levels start at Layer 3+. | Design clarity |
| 5 | **Mobile drag UX** — is drag-and-drop viable on small screens? | Provide tap-tap alternative; test on device | UX quality |

---

## 13. Summary of Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data model | `"layers"` section in existing level JSON | Single source of truth; no cross-file refs |
| Inverse computation | Runtime via `Permutation.inverse()` | Already implemented; no pre-computation needed |
| Progression tracking | `level_states[hall_id].layer_progress` in save data | Extends existing save format naturally |
| Layer unlock | Threshold-based (8/12 prior-layer completions) | Matches existing wing gate pattern |
| hall_tree.json | No changes needed | Layers are orthogonal to world graph structure |
| UI | Split-screen: read-only graph + pairing panel | Reuses existing HUD layout |
| Interaction | Drag-and-drop + tap-tap fallback | Desktop-friendly + mobile-friendly |
| Bidirectional pairing | Recommended yes | Reduces tedium for mutual pairs |
| Graph animations | Reuse SwapManager patterns | Zero new animation code needed |
| Extensibility | `LayerModeController` + per-layer managers | Clean separation; each layer is independent |
