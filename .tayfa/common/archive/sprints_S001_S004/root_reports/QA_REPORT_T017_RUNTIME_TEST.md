# QA Report T017: Full Runtime Test of Fixed Prototype

**Date:** 2026-02-21
**Tester:** QA Tester
**Test Environment:** Windows, Godot v4.6.1.stable.official
**Status:** ❌ **CRITICAL FAILURE - GAME DOES NOT LAUNCH**

## Executive Summary

**The game fails to launch completely due to critical script parsing errors.** No runtime testing could be performed. The game window does not appear, and Godot exits with fatal errors during script loading.

## Test Execution

### Attempt to Launch
- **Command:** `run_game.bat`
- **Result:** ❌ FAILED
- **Godot Process:** Crashed/hung after script loading errors
- **Window:** Never appeared

## Critical Blocking Issues

### 🔴 BLOCKER 1: AgentProtocol Class Not Found
**Severity:** CRITICAL
**File:** `res://src/agent/agent_bridge.gd`
**Impact:** Game cannot start - autoload script fails to load

**Error Details:**
```
SCRIPT ERROR: Parse Error: Identifier "AgentProtocol" not declared in the current scope.
   at: GDScript::reload (res://src/agent/agent_bridge.gd:76)
```

This error repeats **60+ times** throughout `agent_bridge.gd` (lines 76, 81, 83, 210, 212, 295, 305, 306, 308, 325, 328, 329, 334, 339, 344, 349, 354, 363, 382, 439, 472, 477, 481, 486, 496, 505, 511, 515, 520, 525, 529, 533, 543, 549, 553, 557, 562, 568, 580, 584, 594, 598, 606, 608, 612, 620, 624, 629, 633, 642, 646, 650, 669, 675, 679)

**Root Cause Analysis:**
- `agent_protocol.gd` defines `class_name AgentProtocol` (line 11)
- `agent_bridge.gd` attempts to use `AgentProtocol` without importing it
- In Godot 4.x, even with `class_name`, the class needs to be explicitly loaded if it's not an autoload
- **Missing:** `const AgentProtocol = preload("res://src/agent/agent_protocol.gd")`

**Related Errors:**
```
SCRIPT ERROR: Parse Error: Cannot infer the type of "ready_response" variable
SCRIPT ERROR: Parse Error: Cannot infer the type of "parsed" variable
SCRIPT ERROR: Parse Error: Cannot infer the type of "tree" variable
SCRIPT ERROR: Parse Error: Cannot infer the type of "data" variable
SCRIPT ERROR: Parse Error: Cannot infer the type of "response" variable
ERROR: Failed to load script "res://src/agent/agent_bridge.gd" with error "Parse error"
ERROR: Failed to instantiate an autoload, script does not inherit from 'Node'
```

---

### 🔴 BLOCKER 2: Type Inference Errors in LevelScene
**Severity:** CRITICAL
**File:** `res://src/game/level_scene.gd`
**Impact:** Main game scene cannot load

**Error Details:**
```
SCRIPT ERROR: Parse Error: Cannot infer the type of "act" variable because the value doesn't have a set type.
   at: GDScript::reload (res://src/game/level_scene.gd:432)
SCRIPT ERROR: Parse Error: Cannot infer the type of "level_num" variable because the value doesn't have a set type.
   at: GDScript::reload (res://src/game/level_scene.gd:433)
ERROR: Failed to load script "res://src/game/level_scene.gd" with error "Parse error"
```

**Code Context (lines 432-433):**
```gdscript
var act := meta.get("act", 0)
var level_num := meta.get("level", 0)
```

**Root Cause Analysis:**
- Type inference (`:=`) cannot determine type from `Dictionary.get()` return value
- Godot 4.x static typing is stricter about type inference
- **Fix needed:** Explicit type annotation: `var act: int = meta.get("act", 0)`

---

### 🔴 BLOCKER 3: Coroutine Not Awaited
**Severity:** CRITICAL
**File:** `res://src/agent/agent_bridge.gd:293`

**Error Details:**
```
SCRIPT ERROR: Parse Error: Function "_cmd_quit()" is a coroutine, so it must be called with "await".
   at: GDScript::reload (res://src/agent/agent_bridge.gd:293)
```

**Root Cause:**
- A coroutine function is being called without `await`
- Violates Godot 4.x async/await requirements

---

## Test Results: UNTESTABLE

Due to the critical launch failure, **none** of the planned tests could be executed:

### ❌ Planned Test 1: Complete Level 1 (Z3 Symmetries)
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Find all 3 symmetries of Z3
- **Result:** N/A

### ❌ Planned Test 2: Identity Discoverable via Test Button
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Test button reveals identity permutation
- **Result:** N/A

### ❌ Planned Test 3: Swap Accumulation
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Swaps accumulate correctly
- **Result:** N/A

### ❌ Planned Test 4: Reset Button Functionality
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Reset button works
- **Result:** N/A

### ❌ Planned Test 5: Tutorial Clarity
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Tutorial is clear enough for new players
- **Result:** N/A

### ❌ Planned Test 6: Key Ring Names Readability
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Key ring names are readable and understandable
- **Result:** N/A

### ❌ Planned Test 7: Failure Feedback
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Failure feedback explains why swap failed
- **Result:** N/A

### ❌ Planned Test 8: Complete Level 2
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Can complete Level 2
- **Result:** N/A

### ❌ Planned Test 9: Complete Level 3
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Can complete Level 3
- **Result:** N/A

### ❌ Planned Test 10: Crashes and Visual Glitches
- **Status:** CRASH ON LAUNCH
- **Result:** Game crashes immediately with script errors before window appears

### ❌ Planned Test 11: Performance
- **Status:** NOT TESTED - Game does not launch
- **Expected:** Performance is acceptable
- **Result:** N/A

---

## Recently Modified Files

The following files were modified in the last 5 hours (likely causing the regression):

1. `/src/agent/agent_bridge.gd` ⚠️ **PRIMARY CULPRIT**
2. `/src/agent/agent_protocol.gd` ⚠️ **PRIMARY CULPRIT**
3. `/src/core/graph_engine.gd`
4. `/src/game/level_scene.gd` ⚠️ **SECONDARY CULPRIT**
5. `/src/visual/crystal_node.gd`
6. `/src/visual/edge_renderer.gd`
7. `/src/visual/feedback_fx.gd`

---

## Recommendations

### Immediate Actions Required (P0 - Critical)

1. **Fix AgentProtocol Import** (agent_bridge.gd)
   - Add at top of file: `const AgentProtocol = preload("res://src/agent/agent_protocol.gd")`
   - OR: Add AgentProtocol to autoload in project.godot
   - OR: Remove agent bridge functionality if not needed for prototype

2. **Fix Type Inference** (level_scene.gd:432-433)
   - Change: `var act := meta.get("act", 0)`
   - To: `var act: int = meta.get("act", 0)`
   - Change: `var level_num := meta.get("level", 0)`
   - To: `var level_num: int = meta.get("level", 0)`

3. **Fix Coroutine Call** (agent_bridge.gd:293)
   - Add `await` before `_cmd_quit()` call
   - OR: Make calling function async if needed

4. **Retest Immediately After Fixes**
   - Verify game launches successfully
   - Then perform full T017 runtime test suite

### Process Recommendations

1. **Pre-commit Testing:** Developers should run the game before committing changes
2. **Automated CI/CD:** Add script loading checks to catch parse errors
3. **Version Control:** Consider using git to track changes and enable rollback
4. **Code Review:** Recent changes to agent_bridge.gd and level_scene.gd should be reviewed

---

## Conclusion

**The game is completely broken and unplayable.** Critical script parsing errors prevent the game from launching. The prototype regression is likely due to recent changes in the agent bridge system and level scene code.

**No gameplay testing could be performed.** All 11 planned runtime tests are blocked.

**Priority:** Developer must fix the 3 critical blockers before any QA testing can proceed.

---

## Technical Details

**Godot Version:** v4.6.1.stable.official.14d19694e
**Graphics API:** OpenGL 3.3.0 NVIDIA 580.97
**GPU:** NVIDIA GeForce RTX 4070 SUPER
**Launch Command:** `run_game.bat`
**Error Log:** See attached `ba7eb80.output`

**Test Duration:** 0 minutes (immediate crash)
**Tests Executed:** 0/11
**Blockers Found:** 3
**Critical Bugs:** 3
**Major Bugs:** 0
**Minor Bugs:** 0
