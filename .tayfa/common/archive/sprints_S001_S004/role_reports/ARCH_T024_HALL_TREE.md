# Architecture: Hall Tree (Древо Залов)

**Task:** T024
**Author:** Architect
**Date:** 2026-02-26
**Status:** Proposal
**References:** redesign.md (Section 1), Game.txt, T002.md

---

## 0. Executive Summary

This document describes the architecture for replacing the linear level progression with a **branching Hall Tree** — a directed acyclic graph (DAG) of halls grouped into wings. The design covers:

1. **Data format** for the hall graph (`hall_tree.json`)
2. **MapScene** — a new visual navigation screen
3. **Progression engine** — wing gates, unlock conditions, thresholds
4. **Resonance threads** — post-completion visual rewards linking mathematically related halls
5. **Integration plan** with existing `GameManager` and `LevelScene`
6. **Sprint prioritization** — what ships in S004 vs. later

Key design principle: **additive, not destructive**. Every change extends existing systems; nothing currently working is broken.

---

## 1. Current Architecture Snapshot

```
┌──────────────────────────────────────────────────────┐
│                    GameManager (autoload)             │
│  current_act: int           completed_levels: Array  │
│  current_level: int         level_registry: Dict     │
│  complete_level(id)         get_next_level_path(id)  │
│  save_game() / load_game()                           │
└────────────────────────┬─────────────────────────────┘
                         │  uses
                         ▼
┌──────────────────────────────────────────────────────┐
│                    LevelScene (Node2D)                │
│  load_level_from_file(path)                          │
│  _on_level_complete() → GameManager.complete_level() │
│  _on_next_level_pressed() → get_next_level_path()   │
└──────────────────────────────────────────────────────┘
```

### Problems the current system has with Hall Tree:

| Issue | Current code | Impact |
|-------|-------------|--------|
| **Linear progression** | `get_next_level_path()` returns `act{N}_level{M+1}` | Cannot express branches or choice |
| **Hard-coded act/level IDs** | `"act%d_level%02d"` format throughout | No room for non-linear ordering |
| **No map concept** | `current_level` is a single integer | Player can't choose between available halls |
| **No wing gates** | Act transition is "did I complete the last level?" | Need "7 of 10" threshold logic |
| **No resonance data** | Levels don't know about mathematical relations to each other | Cannot show resonance threads |

---

## 2. Hall Tree Data Structure

### 2.1. File: `res://data/hall_tree.json`

A **single JSON file** defines the entire world graph. This is intentional — it's the "world map" and should be authored/versioned as one unit.

```json
{
  "version": 1,

  "wings": [
    {
      "id": "wing_1",
      "name": "The First Vault",
      "subtitle": "Groups",
      "act": 1,
      "order": 1,
      "gate": {
        "type": "threshold",
        "required_halls": 7,
        "total_halls": 10,
        "required_from_wing": null,
        "message": "Open 7 halls in the First Vault to proceed"
      },
      "halls": [
        "act1_level01", "act1_level02", "act1_level03",
        "act1_level04", "act1_level05", "act1_level06",
        "act1_level07", "act1_level08", "act1_level09",
        "act1_level10", "act1_level11", "act1_level12"
      ],
      "start_halls": ["act1_level01"]
    },
    {
      "id": "wing_2",
      "name": "The Inner Sanctum",
      "subtitle": "Subgroups & Normality",
      "act": 2,
      "order": 2,
      "gate": {
        "type": "threshold",
        "required_halls": 8,
        "total_halls": 12,
        "required_from_wing": "wing_1",
        "message": "Open 8 halls in the Inner Sanctum to proceed"
      },
      "halls": [
        "act2_level01", "act2_level02", "act2_level03",
        "act2_level04", "act2_level05", "act2_level06",
        "act2_level07", "act2_level08", "act2_level09",
        "act2_level10", "act2_level11", "act2_level12"
      ],
      "start_halls": ["act2_level01"]
    }
  ],

  "edges": [
    {
      "from": "act1_level01",
      "to": "act1_level02",
      "type": "path"
    },
    {
      "from": "act1_level01",
      "to": "act1_level03",
      "type": "path"
    },
    {
      "from": "act1_level02",
      "to": "act1_level04",
      "type": "path"
    },
    {
      "from": "act1_level02",
      "to": "act1_level05",
      "type": "path"
    },
    {
      "from": "act1_level03",
      "to": "act1_level05",
      "type": "path"
    },
    {
      "from": "act1_level03",
      "to": "act1_level06",
      "type": "path"
    }
  ],

  "resonances": [
    {
      "halls": ["act1_level01", "act1_level04"],
      "type": "subgroup",
      "description": "Z3 is a subgroup of Z6",
      "discovered_when": "both_completed"
    },
    {
      "halls": ["act1_level05", "act1_level06"],
      "type": "isomorphic",
      "description": "Both have the same symmetry group D4",
      "discovered_when": "both_completed"
    },
    {
      "halls": ["act1_level04", "act2_level01"],
      "type": "quotient",
      "description": "The quotient of S4 by V4 gives S3",
      "discovered_when": "both_completed"
    }
  ]
}
```

### 2.2. Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Separate file vs. embedded** | Separate `hall_tree.json` | Level JSONs stay unchanged; world structure is a higher-level concern |
| **DAG vs. free graph** | DAG (directed, acyclic) | Hall dependencies are naturally ordered; prevents cycles in unlock logic |
| **Wings contain halls** | Wing holds array of hall IDs | Grouping for gate checks; halls still reference their own JSON files |
| **Edges are explicit** | `edges[]` array with from/to | Easy to validate, easy to render paths on map |
| **Resonances are separate** | Top-level `resonances[]` | Not part of progression — purely visual/educational reward |
| **Hall IDs = level IDs** | Reuse existing `act1_level01` convention | Zero migration cost for existing level JSONs |

### 2.3. GDScript Data Classes

```gdscript
## HallTreeData — parsed representation of hall_tree.json
class_name HallTreeData

var wings: Array[WingData] = []
var edges: Array[HallEdge] = []
var resonances: Array[ResonanceData] = []

## Lookup caches (built on load)
var _hall_to_wing: Dictionary = {}    # hall_id -> WingData
var _hall_edges: Dictionary = {}      # hall_id -> Array[hall_id] (outgoing neighbors)
var _hall_prereqs: Dictionary = {}    # hall_id -> Array[hall_id] (incoming neighbors)


class WingData:
    var id: String
    var name: String
    var subtitle: String
    var act: int
    var order: int
    var gate: GateData
    var halls: Array[String]
    var start_halls: Array[String]


class GateData:
    var type: String              # "threshold", "all", "specific"
    var required_halls: int       # for "threshold": how many halls needed
    var total_halls: int          # total in the wing (for display "7/10")
    var required_from_wing: String  # which wing's gate this checks (null = previous)
    var required_specific: Array[String]  # for "specific": exact hall IDs needed
    var message: String


class HallEdge:
    var from_hall: String
    var to_hall: String
    var type: String              # "path", "secret"


class ResonanceData:
    var halls: Array[String]
    var type: String              # "subgroup", "quotient", "isomorphic", "extension"
    var description: String
    var discovered_when: String   # "both_completed", "wing_completed"
```

---

## 3. Navigation: The Map Scene

### 3.1. Scene Architecture

```
MapScene (Node2D)
├── Background (TextureRect — temple overview art)
├── WingContainer (Node2D)
│   ├── Wing_1 (Node2D)
│   │   ├── WingLabel (Label — "The First Vault")
│   │   ├── WingGate (Sprite2D + shader — locked/unlocked)
│   │   └── HallNodes (Node2D)
│   │       ├── HallNode_act1_level01 (HallNodeVisual)
│   │       ├── HallNode_act1_level02 (HallNodeVisual)
│   │       └── ...
│   └── Wing_2 (Node2D)
│       └── ...
├── PathContainer (Node2D — rendered hall-to-hall paths)
├── ResonanceContainer (Node2D — glowing threads between resonant halls)
├── Camera (CameraController — pan/zoom across the tree)
└── HUDLayer (CanvasLayer)
    ├── WingProgressBar (TextureProgress — "7/10 halls opened")
    ├── BackButton (Button)
    └── HallInfoTooltip (Panel — appears on hover/tap)
```

### 3.2. HallNodeVisual Component

Each hall appears as a clickable node on the map.

```gdscript
class_name HallNodeVisual
extends Node2D

signal hall_selected(hall_id: String)

enum HallState {
    LOCKED,        # Prerequisites not met — greyed out, no interaction
    AVAILABLE,     # Prerequisites met, not yet completed — glowing, clickable
    COMPLETED,     # Completed — golden, clickable (for replay)
    PERFECT        # Completed with "Seal of Perfection" (no hints used)
}

var hall_id: String
var state: HallState = HallState.LOCKED
var hall_meta: Dictionary = {}  # cached meta from level JSON

## Visual components
var icon: Sprite2D           # Crystal icon representing the hall
var glow_shader: ShaderMaterial
var label: Label             # Hall name (shown on hover or always for key halls)
var state_indicator: Sprite2D  # Lock icon / checkmark / gold seal

func set_state(new_state: HallState) -> void:
    state = new_state
    _update_visuals()

func _update_visuals() -> void:
    match state:
        HallState.LOCKED:
            icon.modulate = Color(0.3, 0.3, 0.4, 0.5)
            glow_shader.set_shader_parameter("glow_intensity", 0.0)
        HallState.AVAILABLE:
            icon.modulate = Color(0.7, 0.8, 1.0, 1.0)
            glow_shader.set_shader_parameter("glow_intensity", 0.6)
            _start_pulse_animation()
        HallState.COMPLETED:
            icon.modulate = Color(0.9, 0.85, 0.5, 1.0)
            glow_shader.set_shader_parameter("glow_intensity", 0.3)
        HallState.PERFECT:
            icon.modulate = Color(1.0, 0.95, 0.7, 1.0)
            glow_shader.set_shader_parameter("glow_intensity", 0.5)

func _on_input_event(_viewport, event, _shape_idx) -> void:
    if event is InputEventMouseButton and event.pressed:
        if state != HallState.LOCKED:
            hall_selected.emit(hall_id)
```

### 3.3. Map Layout Algorithm

The map uses a **layer-based tree layout** (not force-directed — too chaotic for a temple metaphor).

```
Algorithm: Wing Layout
For each wing (ordered by wing.order):
  1. Position start_halls at the top of the wing's vertical zone
  2. BFS from start_halls through edges within this wing
  3. Each BFS layer = one row; space nodes evenly within the row
  4. Y increases downward (deeper = further into the temple)
  5. Wing gate drawn at the bottom of the wing
  6. Next wing starts below the gate
```

```gdscript
## MapLayoutEngine — positions hall nodes on the map
class_name MapLayoutEngine

const WING_VERTICAL_GAP := 200.0    # Space between wings
const LAYER_HEIGHT := 120.0          # Vertical distance between layers
const NODE_HORIZONTAL_SPACING := 150.0  # Min horizontal gap between nodes
const WING_HEADER_HEIGHT := 80.0     # Space for wing title

## Returns Dictionary: hall_id -> Vector2 (position)
static func compute_layout(tree: HallTreeData) -> Dictionary:
    var positions: Dictionary = {}
    var current_y := 0.0

    for wing in tree.wings:
        current_y += WING_HEADER_HEIGHT

        # BFS layer assignment
        var layers: Array[Array] = _bfs_layers(
            wing.start_halls,
            wing.halls,
            tree._hall_edges
        )

        for layer_idx in range(layers.size()):
            var layer: Array = layers[layer_idx]
            var layer_width: float = layer.size() * NODE_HORIZONTAL_SPACING
            var start_x: float = -layer_width / 2.0 + NODE_HORIZONTAL_SPACING / 2.0

            for i in range(layer.size()):
                var hall_id: String = layer[i]
                positions[hall_id] = Vector2(
                    start_x + i * NODE_HORIZONTAL_SPACING,
                    current_y + layer_idx * LAYER_HEIGHT
                )

        current_y += layers.size() * LAYER_HEIGHT + WING_VERTICAL_GAP

    return positions


static func _bfs_layers(starts: Array, hall_set: Array, edges: Dictionary) -> Array[Array]:
    var visited: Dictionary = {}
    var queue: Array = []
    var layers: Array[Array] = []

    # Initialize with start halls
    var current_layer: Array = []
    for start in starts:
        if start in hall_set:
            current_layer.append(start)
            visited[start] = true

    while not current_layer.is_empty():
        layers.append(current_layer)
        var next_layer: Array = []
        for hall_id in current_layer:
            var neighbors: Array = edges.get(hall_id, [])
            for neighbor in neighbors:
                if neighbor in hall_set and not (neighbor in visited):
                    next_layer.append(neighbor)
                    visited[neighbor] = true
        current_layer = next_layer

    # Add any unreachable halls (orphans) to the last layer
    for hall_id in hall_set:
        if not (hall_id in visited):
            if layers.is_empty():
                layers.append([])
            layers[-1].append(hall_id)

    return layers
```

### 3.4. Map Interaction Flow

```
Player opens Map
  │
  ├─ Sees all wings; current wing expanded, others collapsed
  │
  ├─ Taps AVAILABLE hall node
  │   ├─ Hall info tooltip slides in (title, group order, preview)
  │   ├─ "ENTER" button on tooltip
  │   └─ Tap ENTER → transition to LevelScene with hall_id
  │
  ├─ Taps COMPLETED hall node
  │   ├─ Same tooltip + "REPLAY" button + completion stats
  │   └─ Tap REPLAY → load level for replay (no progress change)
  │
  ├─ Taps LOCKED hall node
  │   └─ Tooltip: "Complete [prerequisite halls] to unlock"
  │
  └─ Taps Wing Gate
      ├─ If threshold met: gate opens, next wing expands
      └─ If not: "Open N more halls to pass" message
```

---

## 4. Progression Engine

### 4.1. HallProgressionEngine

A new autoload that replaces the linear act/level tracking with graph-aware progression.

```gdscript
## HallProgressionEngine — manages hall unlock states and wing progression
class_name HallProgressionEngine
extends Node

signal hall_unlocked(hall_id: String)
signal wing_unlocked(wing_id: String)
signal resonance_discovered(resonance: ResonanceData)

var hall_tree: HallTreeData = null

## Get the state of a specific hall
func get_hall_state(hall_id: String) -> HallNodeVisual.HallState:
    if GameManager.is_level_completed(hall_id):
        if _has_perfection_seal(hall_id):
            return HallNodeVisual.HallState.PERFECT
        return HallNodeVisual.HallState.COMPLETED

    if _is_hall_available(hall_id):
        return HallNodeVisual.HallState.AVAILABLE

    return HallNodeVisual.HallState.LOCKED


## Check if a hall is available (all prerequisites met)
func _is_hall_available(hall_id: String) -> bool:
    # Check wing unlock first
    var wing: HallTreeData.WingData = hall_tree._hall_to_wing.get(hall_id)
    if wing == null:
        return false

    if not _is_wing_accessible(wing):
        return false

    # Check if this is a start hall (always available if wing is accessible)
    if hall_id in wing.start_halls:
        return true

    # Check if at least one predecessor is completed
    var prereqs: Array = hall_tree._hall_prereqs.get(hall_id, [])
    for prereq_id in prereqs:
        if GameManager.is_level_completed(prereq_id):
            return true

    return false


## Check if a wing is accessible (previous wing gate satisfied)
func _is_wing_accessible(wing: HallTreeData.WingData) -> bool:
    if wing.order == 1:
        return true  # First wing always accessible

    var gate := wing.gate
    if gate == null:
        return true

    match gate.type:
        "threshold":
            var source_wing_id: String = gate.required_from_wing
            if source_wing_id == null or source_wing_id == "":
                # Default: check previous wing
                source_wing_id = _get_previous_wing_id(wing)
            var source_wing := _get_wing_by_id(source_wing_id)
            if source_wing == null:
                return false
            var completed_count := _count_completed_in_wing(source_wing)
            return completed_count >= gate.required_halls

        "all":
            var source_wing := _get_wing_by_id(gate.required_from_wing)
            if source_wing == null:
                return false
            return _count_completed_in_wing(source_wing) >= source_wing.halls.size()

        "specific":
            for required_id in gate.required_specific:
                if not GameManager.is_level_completed(required_id):
                    return false
            return true

    return false


## Count completed halls in a wing
func _count_completed_in_wing(wing: HallTreeData.WingData) -> int:
    var count := 0
    for hall_id in wing.halls:
        if GameManager.is_level_completed(hall_id):
            count += 1
    return count


## Get progress for a wing: {completed: int, total: int, threshold: int}
func get_wing_progress(wing_id: String) -> Dictionary:
    var wing := _get_wing_by_id(wing_id)
    if wing == null:
        return {"completed": 0, "total": 0, "threshold": 0}

    var completed := _count_completed_in_wing(wing)
    var threshold := wing.gate.required_halls if wing.gate else wing.halls.size()

    return {
        "completed": completed,
        "total": wing.halls.size(),
        "threshold": threshold
    }


## Called after level completion — check for new unlocks and resonances
func on_hall_completed(hall_id: String) -> void:
    # Check if any new halls were unlocked
    var wing := hall_tree._hall_to_wing.get(hall_id)
    if wing == null:
        return

    var neighbors: Array = hall_tree._hall_edges.get(hall_id, [])
    for neighbor_id in neighbors:
        if not GameManager.is_level_completed(neighbor_id):
            if _is_hall_available(neighbor_id):
                hall_unlocked.emit(neighbor_id)

    # Check if next wing was unlocked
    var next_wing := _get_next_wing(wing)
    if next_wing and _is_wing_accessible(next_wing):
        wing_unlocked.emit(next_wing.id)

    # Check for new resonances
    for resonance in hall_tree.resonances:
        if hall_id in resonance.halls:
            if _is_resonance_discovered(resonance):
                resonance_discovered.emit(resonance)


## Check if a resonance should be revealed
func _is_resonance_discovered(resonance: HallTreeData.ResonanceData) -> bool:
    match resonance.discovered_when:
        "both_completed":
            for h_id in resonance.halls:
                if not GameManager.is_level_completed(h_id):
                    return false
            return true
        "wing_completed":
            # All halls in resonance must be in completed wings
            for h_id in resonance.halls:
                var wing := hall_tree._hall_to_wing.get(h_id)
                if wing and _count_completed_in_wing(wing) < wing.halls.size():
                    return false
            return true
    return false


func _get_wing_by_id(wing_id: String) -> HallTreeData.WingData:
    for wing in hall_tree.wings:
        if wing.id == wing_id:
            return wing
    return null

func _get_previous_wing_id(wing: HallTreeData.WingData) -> String:
    for w in hall_tree.wings:
        if w.order == wing.order - 1:
            return w.id
    return ""

func _get_next_wing(wing: HallTreeData.WingData) -> HallTreeData.WingData:
    for w in hall_tree.wings:
        if w.order == wing.order + 1:
            return w
    return null

func _has_perfection_seal(hall_id: String) -> bool:
    var state: Dictionary = GameManager.level_states.get(hall_id, {})
    return state.get("hints_used", 0) == 0 and GameManager.is_level_completed(hall_id)
```

### 4.2. Gate Types

| Gate Type | Condition | Use Case |
|-----------|-----------|----------|
| `threshold` | N of M halls completed in source wing | Standard: "7 of 10" |
| `all` | All halls in source wing completed | Special: 100% required |
| `specific` | Named hall IDs all completed | Boss prerequisites |

---

## 5. Resonance Threads

### 5.1. Types of Mathematical Resonance

| Resonance Type | Mathematical Relationship | Visual |
|----------------|--------------------------|--------|
| `subgroup` | Group A is a subgroup of Group B | Thin blue thread |
| `quotient` | Group A = Group B / Group C | Thick golden thread |
| `isomorphic` | Groups are isomorphic | Pulsing green thread |
| `extension` | Field extension relationship | Woven multi-color thread |
| `galois` | Galois correspondence pair | Dual-colored interleaved thread |

### 5.2. ResonanceRenderer

```gdscript
class_name ResonanceRenderer
extends Node2D

## Visual resonance thread between two (or more) hall nodes on the map.
## Appears only after discovery condition is met.

var resonance_data: ResonanceData
var hall_positions: Array[Vector2] = []
var line: Line2D
var glow_shader: ShaderMaterial
var particles: GPUParticles2D

## Color map by resonance type
const RESONANCE_COLORS := {
    "subgroup":   Color(0.3, 0.5, 1.0, 0.7),
    "quotient":   Color(0.9, 0.75, 0.2, 0.8),
    "isomorphic": Color(0.3, 0.9, 0.4, 0.7),
    "extension":  Color(0.8, 0.4, 0.9, 0.7),
    "galois":     Color(0.9, 0.3, 0.5, 0.7),
}

func setup(data: ResonanceData, positions: Array[Vector2]) -> void:
    resonance_data = data
    hall_positions = positions

    line = Line2D.new()
    line.width = 3.0 if data.type == "quotient" else 2.0
    line.default_color = RESONANCE_COLORS.get(data.type, Color.WHITE)
    line.texture_mode = Line2D.LINE_TEXTURE_TILE

    # Curved path between hall nodes (not straight line)
    var curve := _compute_bezier_points(positions)
    for point in curve:
        line.add_point(point)

    add_child(line)
    _setup_glow_and_particles()

func reveal_with_animation() -> void:
    ## Animate the thread appearing — grows from first hall to second
    modulate.a = 0.0
    var tween := create_tween()
    tween.tween_property(self, "modulate:a", 1.0, 1.5)
```

### 5.3. Resonance Discovery UX

When a resonance is discovered (player completes the second of two linked halls):

1. **Map notification**: The map camera smoothly pans to show both halls
2. **Thread animation**: A glowing thread grows between them (1.5s)
3. **Tooltip**: Brief description appears: *"These two vaults share a hidden bond: Z3 lives inside S3"*
4. **Sound**: A harmonic chord based on the resonance type
5. **Journal entry**: Resonance is logged in the Glossary (future feature)

---

## 6. Integration with Current Systems

### 6.1. GameManager Changes

**Changes to `game_manager.gd`** — minimal, additive:

```gdscript
## === NEW ADDITIONS TO GameManager ===

## Hall tree reference (loaded on ready)
var hall_tree: HallTreeData = null
var progression: HallProgressionEngine = null

## New signal
signal map_requested()

## Load hall tree on startup (after level registry)
func _load_hall_tree() -> void:
    var path := "res://data/hall_tree.json"
    if not FileAccess.file_exists(path):
        push_warning("GameManager: hall_tree.json not found, using linear fallback")
        return

    var file := FileAccess.open(path, FileAccess.READ)
    var json := JSON.new()
    if json.parse(file.get_as_text()) == OK:
        hall_tree = HallTreeData.new()
        hall_tree.parse(json.data)
        progression = HallProgressionEngine.new()
        progression.hall_tree = hall_tree
        add_child(progression)

## New save data fields (backward-compatible)
## Add to save_game():
##   "discovered_resonances": Array[String]  (resonance IDs)
##   "perfection_seals": Array[String]  (hall IDs with no hints used)

var discovered_resonances: Array[String] = []
var perfection_seals: Array[String] = []
```

**Preserved interfaces** — these continue to work unchanged:
- `complete_level(level_id)` — still marks halls complete
- `is_level_completed(level_id)` — still checks completion
- `level_registry` — still maps IDs to file paths
- `save_game()` / `load_game()` — extended, not replaced

### 6.2. LevelScene Changes

**Changes to `level_scene.gd`** — minimal:

```gdscript
## === CHANGES IN LevelScene ===

## REPLACE: _on_next_level_pressed() linear navigation
## WITH: Return to Map after level completion

func _on_next_level_pressed() -> void:
    # Old: load next linear level
    # New: return to map scene where player chooses next hall
    if GameManager.hall_tree != null:
        _return_to_map()
    else:
        # Fallback: linear navigation (backward compatibility)
        var next_path: String = GameManager.get_next_level_path(level_id)
        if next_path != "":
            load_level_from_file(next_path)

func _return_to_map() -> void:
    get_tree().change_scene_to_file("res://src/ui/map_scene.tscn")

## CHANGE: Summary panel button text
## "NEXT LEVEL >" → "RETURN TO MAP" (when hall tree is active)
## Implement in _show_complete_summary():
##   sum_next_btn.text = "RETURN TO MAP" if GameManager.hall_tree else "NEXT LEVEL  >"
##   sum_next_btn.visible = true  # Always visible (map is always available)
```

### 6.3. Scene Flow Diagram

```
                    ┌─────────────────┐
                    │   MainMenu      │
                    │                 │
                    │  [Continue]  ─────────┐
                    │  [New Game]  ──────────┤
                    └─────────────────┘      │
                                             ▼
                    ┌─────────────────────────────┐
                    │        MapScene              │
                    │                              │
                    │  Shows Hall Tree             │
                    │  Player selects a hall       │
                    │  Wing gates shown            │
                    │  Resonance threads visible   │
                    │                              │
                    │  [Hall selected] ──────────────────┐
                    │  [Back to menu] ──→ MainMenu      │
                    └─────────────────────────────┘      │
                         ▲                               ▼
                         │                  ┌─────────────────────┐
                         │                  │    LevelScene       │
                         │                  │                     │
                         │                  │  Plays level        │
                         │                  │  On complete:       │
                         │                  │    → save progress  │
                         │                  │    → show summary   │
                         │◄─────────────────│    → [RETURN TO MAP]│
                              on completion └─────────────────────┘
```

### 6.4. Save Data Format (Extended)

```json
{
  "player": {
    "current_act": 1,
    "current_level": 3,
    "completed_levels": ["act1_level01", "act1_level02"],
    "level_states": {
      "act1_level01": {
        "found_keys": ["e", "r1", "r2"],
        "time_spent_seconds": 120,
        "attempts": 12,
        "hints_used": 0
      }
    },
    "discovered_resonances": ["res_act1_01_04"],
    "perfection_seals": ["act1_level01"],
    "last_wing": "wing_1"
  },
  "settings": {
    "music_volume": 0.8,
    "sfx_volume": 1.0,
    "fullscreen": false
  }
}
```

---

## 7. New File Structure

```
TheSymmetryVaults/
├── data/
│   ├── hall_tree.json                  # NEW — world graph definition
│   └── levels/
│       ├── act1/                       # Existing — unchanged
│       └── act2/                       # Future levels
│
├── src/
│   ├── core/
│   │   ├── hall_tree_data.gd           # NEW — HallTreeData parser/model
│   │   └── hall_progression_engine.gd  # NEW — unlock logic
│   │
│   ├── game/
│   │   ├── game_manager.gd            # MODIFIED — add hall_tree loading
│   │   └── level_scene.gd             # MODIFIED — return-to-map flow
│   │
│   ├── ui/
│   │   ├── map_scene.gd               # NEW — map controller
│   │   ├── map_scene.tscn             # NEW — map scene template
│   │   ├── hall_node_visual.gd        # NEW — single hall on map
│   │   ├── hall_node_visual.tscn      # NEW
│   │   ├── wing_header.gd             # NEW — wing title + gate display
│   │   ├── wing_header.tscn           # NEW
│   │   ├── resonance_renderer.gd      # NEW — resonance thread visual
│   │   └── map_layout_engine.gd       # NEW — tree layout algorithm
│   │
│   ├── visual/                        # Existing — unchanged
│   │
│   └── shaders/
│       ├── hall_node_glow.gdshader    # NEW — hall node effects
│       └── resonance_thread.gdshader  # NEW — resonance thread glow
│
└── tests/
    ├── test_hall_tree_data.gd          # NEW
    ├── test_hall_progression.gd        # NEW
    └── test_map_layout.gd             # NEW
```

---

## 8. API Contracts

### 8.1. HallTreeData API

```gdscript
class_name HallTreeData

## Parse hall_tree.json data
func parse(data: Dictionary) -> void

## Get all halls in a wing
func get_wing_halls(wing_id: String) -> Array[String]

## Get outgoing edges from a hall
func get_hall_neighbors(hall_id: String) -> Array[String]

## Get incoming edges to a hall (prerequisites)
func get_hall_prerequisites(hall_id: String) -> Array[String]

## Get the wing containing a hall
func get_hall_wing(hall_id: String) -> WingData

## Get all resonances involving a hall
func get_hall_resonances(hall_id: String) -> Array[ResonanceData]

## Get all wings, ordered
func get_ordered_wings() -> Array[WingData]

## Validate the tree structure (no cycles, all refs valid)
func validate() -> Array[String]  # Returns list of errors, empty = valid
```

### 8.2. HallProgressionEngine API

```gdscript
class_name HallProgressionEngine

## Signals
signal hall_unlocked(hall_id: String)
signal wing_unlocked(wing_id: String)
signal resonance_discovered(resonance: ResonanceData)

## Get the display state of a hall
func get_hall_state(hall_id: String) -> HallNodeVisual.HallState

## Check if a wing is accessible
func is_wing_accessible(wing_id: String) -> bool

## Get progress stats for a wing
func get_wing_progress(wing_id: String) -> Dictionary
## Returns: {completed: int, total: int, threshold: int}

## Get all currently available (playable) halls
func get_available_halls() -> Array[String]

## Get all discovered resonances
func get_discovered_resonances() -> Array[ResonanceData]

## Called after completing a hall — triggers unlock checks
func on_hall_completed(hall_id: String) -> void
```

### 8.3. MapScene API

```gdscript
class_name MapScene

## Open the map, focused on a specific wing (or the latest)
func open(focus_wing_id: String = "") -> void

## Navigate to a specific hall (called from menu/continue)
func focus_hall(hall_id: String) -> void

## Enter a hall (transition to LevelScene)
func enter_hall(hall_id: String) -> void

## Refresh all node states (after returning from a level)
func refresh_states() -> void
```

---

## 9. Sprint Prioritization

### S004 — Ship These (MVP Hall Tree)

| # | Task | Effort | Why now |
|---|------|--------|---------|
| 1 | `hall_tree_data.gd` — parser + data model | 1 day | Foundation for everything |
| 2 | `hall_tree.json` — Wing 1 (12 halls, existing levels) | 0.5 day | Data to drive the map |
| 3 | `hall_progression_engine.gd` — unlock logic | 1 day | Core gameplay gate |
| 4 | `map_scene.gd/.tscn` — basic map with clickable nodes | 2 days | Player needs to see and choose |
| 5 | `hall_node_visual.gd/.tscn` — 4 states, click handling | 1 day | Map building block |
| 6 | `map_layout_engine.gd` — BFS layer layout | 0.5 day | Positions nodes on map |
| 7 | GameManager integration — load hall tree, extended save | 0.5 day | Glue code |
| 8 | LevelScene integration — return-to-map flow | 0.5 day | Complete the loop |
| 9 | Unit tests for progression engine | 0.5 day | Must validate gate logic |
| **Total** | | **~7.5 days** | |

### S005 — Ship These (Polish + Resonance)

| # | Task | Effort | Why later |
|---|------|--------|-----------|
| 1 | Resonance threads — visual renderer | 1.5 days | Nice-to-have, not blocking gameplay |
| 2 | Resonance discovery animation | 1 day | Polish |
| 3 | Wing gate animation (opening/locked) | 1 day | Polish |
| 4 | Map camera — smooth pan/zoom | 0.5 day | UX polish |
| 5 | Hall info tooltip on hover | 0.5 day | UX polish |
| 6 | Wing 2 hall_tree data (Act 2 levels) | 1 day | Content |

### S006+ — Defer These

| Feature | Why defer |
|---------|-----------|
| Active Notes system (redesign.md #2) | Independent system, no Hall Tree dependency |
| Loom / Weaving mechanic (redesign.md #3) | Act 3 content — not needed until Act 2 is done |
| Dual Vision mode (redesign.md #4) | Requires Loom first |
| Impossible Halls (redesign.md #5) | Can be added as new halls in existing tree |
| Co-op Multiplayer (redesign.md #6) | Large feature, orthogonal to structure |
| Sandbox (redesign.md #7) | Post-main-game feature |
| Echo hints (redesign.md #9) | Can layer on later; existing hint system works |
| Living Glossary (redesign.md #10) | Independent UI feature |
| Sound design (redesign.md #11) | Polish phase |
| Library (redesign.md #12) | Post-game content |

---

## 10. Risk Analysis

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Hall tree JSON grows unwieldy** | Hard to author | Keep validation in `hall_tree_data.validate()`, provide editor tool |
| **Map visual complexity** | Performance on mobile | Use instanced scenes, cull off-screen nodes, LOD for distant wings |
| **Player confusion** ("where do I go?") | Drop-off | Always pulse the most "natural" next hall; show wing progress prominently |
| **Save migration** | Old saves break | `load_game()` checks for new fields, defaults to linear fallback |
| **Resonance spoilers** | Shows math connections too early | Resonances only appear after BOTH halls are completed |

---

## 11. Open Questions for Discussion

1. **How many halls per wing?** redesign.md says "10" but we have 12 levels in Act 1. Recommend keeping 12 with threshold 8 (2/3).

2. **Secret paths?** Should some edges be hidden until conditions are met? (e.g., completing both neighbors reveals a shortcut.) Recommend: defer to S005.

3. **Hall preview on map?** Should hovering over a hall show a small crystal graph preview? Recommend: yes, but S005.

4. **Multiple start halls per wing?** The design allows it (array), but Wing 1 probably starts with a single entry point. Wing 2 could have 2 start halls if the player has different paths through Wing 1.

---

## Appendix A: Migration Checklist

```
□ Create data/hall_tree.json with Wing 1 data
□ Add HallTreeData class (src/core/hall_tree_data.gd)
□ Add HallProgressionEngine class (src/core/hall_progression_engine.gd)
□ Modify GameManager._ready() to call _load_hall_tree()
□ Add hall_tree, progression, discovered_resonances to GameManager
□ Extend save_game()/load_game() for new fields
□ Create MapScene (src/ui/map_scene.tscn + .gd)
□ Create HallNodeVisual (src/ui/hall_node_visual.tscn + .gd)
□ Create MapLayoutEngine (src/ui/map_layout_engine.gd)
□ Modify LevelScene._on_next_level_pressed() for return-to-map
□ Modify LevelScene._show_complete_summary() button text
□ Add MapScene to project scene flow (MainMenu → MapScene → LevelScene)
□ Register MapScene in project.godot if needed
□ Write tests: test_hall_tree_data.gd, test_hall_progression.gd
□ Verify backward compatibility: game works without hall_tree.json (linear fallback)
```
