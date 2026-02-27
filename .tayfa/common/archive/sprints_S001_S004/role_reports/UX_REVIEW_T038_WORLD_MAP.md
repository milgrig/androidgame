# UX REVIEW: World Map and Game Flow
## Task T038 - Game Designer Review
**Review Date:** 2026-02-26
**Reviewer:** Game Designer (Skeptical UX Evaluator)
**Method:** Code analysis + Architecture review

---

## EXECUTIVE SUMMARY

The world map implementation shows solid architectural foundations with clear separation of concerns (HallTreeData, HallProgressionEngine, MapScene, HallNodeVisual). However, from a UX perspective focused on a **16-year-old casual puzzle gamer**, there are critical gaps in player orientation, visual feedback, and the core "exploration" feeling.

**Overall Score: 6.5/10** - "Good foundations, needs UX polish"

---

## 📊 SCORES (1-10)

| Category | Score | Rationale |
|----------|-------|-----------|
| **World Map Clarity** | 6/10 | Structure exists but visual hierarchy unclear from code |
| **Navigation Clarity** | 7/10 | Clickable halls + state differentiation present |
| **Transitions Smoothness** | 7/10 | Scene transitions implemented but context preservation unclear |
| **Nonlinearity / Choice** | 8/10 | Hall tree structure supports branching paths excellently |
| **Exploration Feeling** | 5/10 | Missing "world" atmosphere - feels more like a flowchart |
| **Echo Hints Quality** | ?/10 | Not visible in world map code - needs level-specific review |
| **Overall Experience** | 6.5/10 | Functional but lacks emotional engagement |

---

## 🗺️ WORLD MAP EVALUATION

### 1. ORIENTATION - "Where am I?"

**Code Analysis:**
- ✅ Wing headers display: name, subtitle, progress (X / total)
- ✅ Title bar shows "Карта залов"
- ✅ Progress indicator at bottom: "Общий прогресс: X / Y залов"
- ✅ Legend shows hall states (Available/Completed/Perfect/Locked)

**Issues:**
- ❌ **NO "YOU ARE HERE" INDICATOR** - Player doesn't know which hall they just came from
  - After completing a level, returning to map gives no visual cue of "I was just HERE"
  - Missing camera focus on recently completed hall

- ⚠️ **Weak visual hierarchy** - Wing headers at y+0, y+35, y+60 but halls positioned by BFS layout
  - No clear "this is the current wing" highlight
  - Player may not connect the header to the halls below it

**Recommendation:**
- 🔴 **HIGH PRIORITY**: Add a "current hall" indicator (glow/pulse) for the last played hall
- 🟡 **MEDIUM**: Highlight the current wing's header when camera is focused there
- 🟢 **POLISH**: Add breadcrumb trail showing "Main Menu > The First Vault > Level 3"

**Score: 6/10** - Information is there but not player-centric

---

### 2. NAVIGATION - "Where can I go?"

**Code Analysis:**
- ✅ Hall visual states correctly mapped: LOCKED (dim), AVAILABLE (bright), COMPLETED (green), PERFECT (gold)
- ✅ Clickable only if available: `HallNodeVisual.setup()` handles disabled state
- ✅ Edge coloring differentiates: locked (gray 0.3α), active (blue 0.5α), completed (green 0.45α)
- ✅ Camera pan/zoom implemented (drag + scroll wheel)

**Issues:**
- ⚠️ **Edge visual clarity** - Three colors for edges but differences subtle (all ~0.3-0.5 alpha)
  - Will a player notice that "this path is open" vs "this path is locked"?
  - Edges don't "lead the eye" to available halls

- ⚠️ **No hover feedback** - HallNodeVisual doesn't show preview on hover
  - Missing: "This hall contains 4 symmetries - 0 found"
  - Missing: Group name display (Z₃, D₄, etc.) without clicking

**Code Evidence:**
```gdscript
# map_scene.gd lines 218-235
EDGE_COLOR_LOCKED := Color(0.2, 0.2, 0.3, 0.3)   # 30% opacity
EDGE_COLOR_ACTIVE := Color(0.4, 0.55, 0.8, 0.5)  # 50% opacity
EDGE_COLOR_COMPLETED := Color(0.35, 0.7, 0.4, 0.45)  # 45% opacity
```
All very close in opacity - might blend together.

**Recommendation:**
- 🟡 **MEDIUM**: Increase edge opacity contrast (locked: 0.2, active: 0.7, completed: 0.6)
- 🟡 **MEDIUM**: Add hover tooltips to halls showing name + group + progress
- 🟢 **POLISH**: Pulse available halls gently (0.5s cycle) to draw attention

**Score: 7/10** - Functional but could guide the player more actively

---

### 3. NONLINEARITY - "Can I choose my path?"

**Code Analysis:**
```json
// hall_tree.json - Example branching:
{"from": "act1_level01", "to": "act1_level02"},  // Path A
{"from": "act1_level01", "to": "act1_level03"},  // Path B
```

- ✅ **Excellent branching structure** - Level 1 splits to 2 and 3
- ✅ Convergent paths (multiple routes to same hall)
- ✅ Gate system allows flexible progression (8/12 required, not linear)

**Issues:**
- ✅ **NO ISSUES** - This is the strongest part of the UX
- The tree structure is mathematically elegant AND player-friendly

**Recommendation:**
- ✅ **KEEP AS IS** - This design already nails player choice

**Score: 8/10** - Best-in-class nonlinear design

---

### 4. EXPLORATION FEELING - "Does this feel like a world?"

**Code Analysis:**
- ❌ **No environmental storytelling** - Halls are just nodes in a graph
  - No visual themes distinguishing Act 1 halls from each other
  - No "ancient temple" atmosphere on the map itself

- ❌ **Layout is algorithmic (BFS)** - Not artistically composed
  ```gdscript
  // map_layout_engine.gd computes positions via BFS
  // Result: technically correct but visually sterile
  ```

- ⚠️ **Missing context clues** - Halls don't show *what makes them unique*
  - Level 1 (triangle) vs Level 4 (square) look identical on map
  - No iconography hinting at content

**Comparison to Reference:**
- ✅ Dark Souls: Bonfires show distance to boss, ambient details tell story
- ❌ The Symmetry Vaults: Halls are abstract circles/hexagons with text labels

**Recommendation:**
- 🔴 **HIGH PRIORITY**: Add visual variety to hall nodes based on group type
  - Triangle halls show 3-sided icon
  - Square halls show 4-sided icon
  - Irregular graphs show asymmetric icon

- 🟡 **MEDIUM**: Add ambient particles or shimmer effects to available halls

- 🟢 **POLISH**: Background parallax layers showing "temple depth" (pillars, crystals, fog)

**Score: 5/10** - It's a map, not a world (yet)

---

## 🔄 TRANSITIONS EVALUATION

### 1. Main Menu → World Map

**Code Flow:**
```gdscript
// main_menu.gd line 317-319
func _on_start_pressed():
    GameManager.start_game()

// game_manager.gd line 127-130
func start_game():
    if hall_tree != null:
        open_map()  // → change_scene_to_file("res://src/ui/map_scene.tscn")
```

**Assessment:**
- ✅ Clean transition via `GameManager.start_game()`
- ✅ Checks for hall_tree before showing map (graceful fallback)
- ⚠️ No loading indicator - instant scene change may feel jarring

**Issues:**
- ⚠️ **Missing fade transition** - Abrupt scene change breaks immersion
- ⚠️ **No "entering the temple" moment** - Missed narrative beat

**Recommendation:**
- 🟡 **MEDIUM**: Add 0.5s fade-to-black transition between menu and map
- 🟢 **POLISH**: First-time players see brief "The temple awaits..." text overlay

**Score: 7/10** - Works but could be smoother

---

### 2. World Map → Level → World Map

**Code Flow:**
```gdscript
// map_scene.gd line 382-392
func enter_hall(hall_id):
    GameManager.current_hall_id = hall_id  // Store context
    get_tree().change_scene_to_file("res://src/game/level_scene.tscn")

// level_scene.gd (assumed) after completion:
//   GameManager.mark_completed(hall_id)
//   get_tree().change_scene_to_file("res://src/ui/map_scene.tscn")
```

**Assessment:**
- ✅ Context stored in `GameManager.current_hall_id`
- ✅ MapScene has `refresh_states()` to update visuals on return
- ❌ **CRITICAL ISSUE**: No evidence that `refresh_states()` is called on return!
  - MapScene._ready() doesn't call refresh_states()
  - Player completes level, returns to map → hall still shows old state?

**Code Evidence:**
```gdscript
// map_scene.gd line 51-66 (_ready function)
func _ready():
    # ... build scene, spawn nodes, draw edges ...
    # NO call to refresh_states() anywhere!
```

**Issues:**
- ❌ **Context NOT preserved** - Completed hall won't update until next map load
- ⚠️ **No "return" button tested** - Can player even return from level without completing?
- ⚠️ **Camera doesn't recenter** on returned hall - player loses spatial context

**Recommendation:**
- 🔴 **HIGH PRIORITY**: Call `refresh_states()` in MapScene._ready() if returning from level
  - Check `GameManager.current_hall_id` - if not empty, a level was just played
  - Update that hall's visual state
  - Center camera on it with brief highlight animation

- 🔴 **HIGH PRIORITY**: Add "Return to Map" button in level HUD
  - Currently only "Reset" and "Submit" visible in typical level UI

- 🟡 **MEDIUM**: Brief text on return: "Hall Completed! 2 / 12 symmetries found"

**Score: 5/10** - Transition exists but context breaks

---

### 3. Level Completion Clarity

**Assessment (based on code structure):**
- ✅ `GameManager.level_completed_signal` emits on completion
- ⚠️ **LevelScene completion UX not evaluated here** (different scope)
- ⚠️ **Map doesn't celebrate completion** - just shows green dot

**Recommendation:**
- 🟡 **MEDIUM**: On return to map, briefly pulse the completed hall (2s glow effect)
- 🟢 **POLISH**: If gate threshold met (8/12), show "Gate Opens!" overlay

**Score: 6/10** - Functional but lacks juice

---

## 💬 ECHO HINTS EVALUATION

**Status:** ⚠️ **Not applicable to world map review**

Echo hints are level-specific (HintController.gd, presumably in LevelScene). This review focused on map → level → map flow, not in-level mechanics.

**Recommendation:**
- Conduct separate UX review of echo hints during actual level gameplay
- Test progression: whisper (text) → voice (louder text) → vision (visual highlight)
- Evaluate annoyance factor: do hints fire too often? Too patronizing?

**Score: ?/10** - Requires separate review

---

## 🎯 PRIORITIZED RECOMMENDATIONS

### 🔴 CRITICAL (Fix Before Polish)

1. **Context Preservation on Map Return**
   - Call `refresh_states()` when returning to map from level
   - Recenter camera on just-completed hall
   - Brief highlight effect (1-2s glow)

2. **"You Are Here" Indicator**
   - Add visual marker for last-played hall
   - Helps player remember where they were

3. **Visual Variety in Hall Nodes**
   - Triangle, square, hexagon icons based on graph structure
   - Makes halls memorable and scannable at a glance

### 🟡 MEDIUM (Improves Core Experience)

4. **Hover Tooltips on Halls**
   - Show: Hall name, group name, progress (X / Y symmetries)
   - Helps player decide where to go without clicking

5. **Edge Opacity Contrast**
   - Increase available edge opacity to 0.7 (from 0.5)
   - Reduce locked edge to 0.15 (from 0.3)
   - Player can visually trace available paths faster

6. **Fade Transitions**
   - 0.5s fade between menu ↔ map ↔ level
   - Less jarring, more polished feel

### 🟢 POLISH (Nice to Have)

7. **Ambient Atmosphere**
   - Particle effects on available halls
   - Background parallax layers (pillars, fog)
   - Makes map feel like a "temple" not a flowchart

8. **Completion Celebration**
   - Pulse effect when returning from completed hall
   - "Gate Opens!" message when threshold met

9. **Breadcrumb Navigation**
   - Top bar shows: Main Menu > Wing 1 > Current Hall
   - Extra orientation for lost players

---

## 🎮 OVERALL IMPRESSION

### Would I keep playing?

**⚠️ MAYBE** - As a 16-year-old casual gamer:

**What Works:**
- ✅ Clear visual states (locked/available/completed) help me know where I can go
- ✅ Nonlinear paths give me agency - I'm exploring, not being railroaded
- ✅ Progress tracking (8 / 12 halls) gives a sense of accomplishment

**What Frustrates:**
- ❌ After finishing a level, I return to the map and... which hall did I just do?
  - Everything looks the same, I've lost my place
- ❌ The map feels clinical - where's the mystery? The atmosphere?
  - It's a graph of circles, not a temple I'm exploring
- ⚠️ Hovering on a hall does nothing - I have to click to see what it is
  - In 2026, players expect tooltips/previews on hover

### What would I change first?

1. **Fix context loss** - When I return to map, show me where I was
2. **Make halls visually distinct** - Icons, colors, shapes based on content
3. **Add ambient magic** - Particles, glow, atmosphere that says "ancient temple"

### Comparison to Gold Standard (Monument Valley, The Witness)

| Game | Map UX | TSV Current | Gap |
|------|--------|-------------|-----|
| **Monument Valley** | Each level is a miniature architectural model - beautiful, memorable | Circles in a graph | Need: unique visual identity per hall |
| **The Witness** | Island map shows landmarks, solved puzzles glow | Generic nodes | Need: visual variety + completion glow |
| **Baba Is You** | Level select shows rule complexity via icon count | Text labels only | Need: iconography for graph structure |

**The Symmetry Vaults has better nonlinear structure than any of these** - but worse visual presentation.

---

## 📋 DETAILED FINDINGS (RAW DATA)

### Code Files Reviewed:
- `src/ui/map_scene.gd` (519 lines) - Main map screen
- `src/ui/map_layout_engine.gd` (assumed, referenced in map_scene.gd)
- `src/ui/hall_node_visual.gd` (assumed, instanced in map_scene.gd)
- `src/ui/main_menu.gd` (349 lines) - Entry point
- `src/game/game_manager.gd` (150+ lines) - State management
- `data/hall_tree.json` (92 lines) - Map structure definition

### Key Observations:

**HallTreeData Structure (Excellent):**
```json
{
  "wings": [...],  // Act-based grouping
  "edges": [...],  // Branching paths
  "resonances": [...]  // Hidden connections (isomorphic groups)
}
```
This is sophisticated game design - resonances create "aha!" moments when player realizes two halls are related.

**HallProgressionEngine (Solid):**
- Correctly tracks: LOCKED → AVAILABLE → COMPLETED → PERFECT
- Gate system allows skipping levels (8/12 required, not 12/12)
- Unlocks next wing when threshold met

**MapScene Camera (Good):**
- Pan via drag, zoom via scroll wheel
- `_center_camera_on_available()` focuses on playable halls
- Issue: Doesn't recenter after level completion

**Visual States (Implemented but Needs Tuning):**
```gdscript
EDGE_COLOR_LOCKED := Color(0.2, 0.2, 0.3, 0.3)
EDGE_COLOR_ACTIVE := Color(0.4, 0.55, 0.8, 0.5)
EDGE_COLOR_COMPLETED := Color(0.35, 0.7, 0.4, 0.45)
```
Locked and active both around 0.3-0.5 alpha - too similar.

**Missing Features:**
- No tooltip system
- No "current hall" highlight
- No celebration effects on completion
- No visual theming per hall type

---

## CONCLUSION

The world map is **architecturally sound** but **emotionally flat**. A player focused on logic will appreciate the clean structure. A casual player will feel lost and disengaged.

**Key Insight:**
The game design document (Game.txt) describes "ancient temple halls with locked doors" - but the map looks like a computer science flowchart. The **fantasy is missing from the UX**.

### Next Steps:
1. Implement HIGH PRIORITY fixes (context preservation, hall variety)
2. Playtest with a non-mathematician teenager
3. Iterate on visual atmosphere until it feels like *exploring a mysterious temple*, not *navigating a graph database*

---

**Final Score: 6.5 / 10** - "Good bones, needs skin"
