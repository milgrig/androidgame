# T021: Full Runtime QA Test Report - All 12 Act 1 Levels

**Date:** 2026-02-26
**Test Type:** Comprehensive Agent Bridge Integration Test
**Status:** Test Suite Created - Awaiting Execution

## Test Overview

This document describes the comprehensive QA test suite for all 12 levels of Act 1, tested through the Agent Bridge runtime interface.

## Test Coverage

### Test File
`tests/agent/test_all_levels_comprehensive.py`

### Levels Tested

| Level | ID | Title | Group | Order | Crystals | Edges |
|-------|-----------|------|-------|-------|----------|-------|
| 1 | act1_level01 | Треугольный зал | Z3 | 3 | 3 | 3 |
| 2 | act1_level02 | Направленный поток | Z3 | 3 | 3 | 3 |
| 3 | act1_level03 | Цвет имеет значение | Z2 | 2 | 3 | 3 |
| 4 | act1_level04 | Квадратный зал | Z4 | 4 | 4 | 4 |
| 5 | act1_level05 | Зеркальный квадрат | D4 | 8 | 4 | 4 |
| 6 | act1_level06 | Разноцветный квадрат | V4 | 4 | 4 | 4 |
| 7 | act1_level07 | Кривая тропа | Z2 | 2 | 5 | 4 |
| 8 | act1_level08 | Звёзды-близнецы | Z2 | 2 | 6 | 7 |
| 9 | act1_level09 | Скрытый треугольник | S3 | 6 | 6 | 9 |
| 10 | act1_level10 | Цепь силы | Z5 | 5 | 5 | 5 |
| 11 | act1_level11 | Две шестерёнки | Z6 | 6 | 6 | 6 |
| 12 | act1_level12 | Зал двух ключей | D4 | 8 | 4 | 4 |

### Test Categories

Each level is tested for the following aspects:

#### 1. Level Metadata Validation (6 tests)
- ✓ `test_01_level_metadata` - Verify level ID, title, group name
- ✓ `test_02_crystal_count` - Correct number of crystals
- ✓ `test_03_edge_count` - Correct number of edges
- ✓ `test_04_crystal_colors` - Crystal colors match specification
- ✓ `test_05_initial_arrangement` - Arrangement starts at identity
- ✓ `test_06_total_symmetries` - Total symmetries = group order

#### 2. Automorphism Validation (1 test)
- ✓ `test_10_find_all_automorphisms` - All valid automorphisms accepted

#### 3. Invalid Permutations (1 test)
- ✓ `test_20_invalid_permutations_rejected` - Invalid perms trigger invalid_attempt

#### 4. Level Completion (1 test)
- ✓ `test_30_level_completion` - level_completed event fires

#### 5. Keyring Validation (2 tests)
- ✓ `test_40_keyring_updates` - Keyring updates as symmetries found
- ✓ `test_41_keyring_completion` - Keyring shows complete=true

#### 6. HUD Label Validation (3 tests)
- ✓ `test_50_hud_labels_exist` - TitleLabel, CounterLabel exist
- ✓ `test_51_title_label_correct` - TitleLabel shows correct title
- ✓ `test_52_counter_label_updates` - CounterLabel updates

#### 7. Button Functionality (2 tests)
- ✓ `test_60_reset_button_exists` - RESET button exists
- ✓ `test_61_reset_button_works` - RESET restores identity

#### 8. Swap Functionality (3 tests)
- ✓ `test_70_swap_valid_crystals` - swap() works for valid IDs
- ✓ `test_71_swap_same_crystal_noop` - Swapping same crystal is no-op
- ✓ `test_72_swap_invalid_crystal_errors` - Invalid crystal ID errors

#### 9. Edge Cases (2 tests)
- ✓ `test_80_duplicate_submission` - No duplicate keyring entries
- ✓ `test_81_load_nonexistent_level_errors` - Non-existent level errors

**Total Tests Per Level:** 20 tests
**Total Tests Across All Levels:** 240 tests

## Running the Tests

### Prerequisites
1. Godot 4.6+ binary in PATH (or set `GODOT_PATH` environment variable)
2. TheSymmetryVaults project built and ready

### Run All Tests
```bash
cd /c/Cursor/TayfaProject/AndroidGame/TheSymmetryVaults
pytest tests/agent/test_all_levels_comprehensive.py -v -s
```

### Run Specific Level
```bash
pytest tests/agent/test_all_levels_comprehensive.py::TestLevel01 -v -s
pytest tests/agent/test_all_levels_comprehensive.py::TestLevel12 -v -s
```

### Run Specific Test Category
```bash
pytest tests/agent/test_all_levels_comprehensive.py -k "test_10" -v -s  # Automorphisms
pytest tests/agent/test_all_levels_comprehensive.py -k "test_40" -v -s  # Keyring
```

## Expected Behavior

### Normal Flow (Per Level)
1. **Load Level** → state shows correct metadata
2. **Submit identity [0,1,2,...]** → symmetry_found event, keyring updates
3. **Submit valid automorphisms** → symmetry_found for each, keyring increments
4. **Submit last symmetry** → symmetry_found + level_completed events
5. **Check keyring** → complete=true, found_count==total
6. **Check HUD** → CounterLabel shows "N / N"
7. **Reset** → arrangement returns to identity
8. **Swap valid crystals** → arrangement changes (may trigger invalid_attempt or symmetry_found)
9. **Swap same crystal** → no_op result
10. **Swap invalid ID** → error response

### Edge Cases Behavior
- **Duplicate submission:** Same automorphism submitted twice → keyring count doesn't increase
- **Invalid permutation:** Non-automorphism submitted → invalid_attempt event
- **Load nonexistent level:** Error with code NOT_FOUND
- **Swap nonexistent crystal:** Error response

## Bug Documentation Template

When bugs are found, document them using this format:

```markdown
### BUG-XXX: [Short Description]

**Level:** [Level ID(s) affected]
**Test:** [Test method that failed]
**Severity:** Critical / High / Medium / Low
**Category:** [Metadata / Automorphism / Keyring / HUD / Buttons / Swap / Edge Case]

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happened]

**Steps to Reproduce:**
1. Load level [ID]
2. [Action]
3. [Observe result]

**Test Output:**
```
[Paste test failure output]
```

**Root Cause Analysis:**
[Technical explanation if known]

**Suggested Fix:**
[How to fix it]
```

## Automorphism Specifications

### Level 01 (Z3) - Triangle
- Identity: [0,1,2]
- Rotation 120°: [1,2,0]
- Rotation 240°: [2,0,1]

### Level 02 (Z3) - Directed Triangle
- Same as Level 01 but with directed edges

### Level 03 (Z2) - Color Constraint
- Identity: [0,1,2]
- Swap greens: [0,2,1]

### Level 04 (Z4) - Square with Arrows
- Identity: [0,1,2,3]
- Rotation 90°: [1,2,3,0]
- Rotation 180°: [2,3,0,1]
- Rotation 270°: [3,0,1,2]

### Level 05 (D4) - Mirror Square
- 4 rotations (same as Level 04)
- Reflection horizontal: [1,0,3,2]
- Reflection vertical: [3,2,1,0]
- Reflection diagonal: [0,3,2,1]
- Reflection anti-diagonal: [2,1,0,3]

### Level 06 (V4) - Klein Four Group
- Identity: [0,1,2,3]
- Rotation 180°: [2,3,0,1]
- Reflection diagonal: [0,3,2,1]
- Reflection anti-diagonal: [2,1,0,3]

### Level 07 (Z2) - Palindrome Path
- Identity: [0,1,2,3,4]
- Reverse: [4,3,2,1,0]

### Level 08 (Z2) - Twin Stars
- Identity: [0,1,2,3,4,5]
- Swap twins: [3,4,5,0,1,2]

### Level 09 (S3) - Hidden Triangle
- Identity: [0,1,2,3,4,5]
- Rotate pairs: [1,2,0,4,5,3], [2,0,1,5,3,4]
- Swap pairs: [1,0,2,4,3,5], [2,1,0,5,4,3], [0,2,1,3,5,4]

### Level 10 (Z5) - Pentagon
- Identity: [0,1,2,3,4]
- Rotations: [1,2,3,4,0], [2,3,4,0,1], [3,4,0,1,2], [4,0,1,2,3]

### Level 11 (Z6) - Hexagon
- Identity: [0,1,2,3,4,5]
- Rotations: [1,2,3,4,5,0], [2,3,4,5,0,1], [3,4,5,0,1,2], [4,5,0,1,2,3], [5,0,1,2,3,4]

### Level 12 (D4) - Two Generators
- Same as Level 05 (D4)

## Notes

- **Test Duration:** Each level takes ~5-10 seconds to test (total ~2-4 minutes for all 12)
- **Parallelization:** Tests cannot be parallelized (Godot instance conflict)
- **Godot Headless:** Tests run in headless mode (no GUI)
- **Protocol:** File-based JSON protocol (agent_cmd.jsonl ↔ agent_resp.jsonl)

## Test Results

_This section will be filled after test execution_

### Summary
- **Total Tests:** 240
- **Passed:** [TBD]
- **Failed:** [TBD]
- **Skipped:** [TBD]
- **Bugs Found:** [TBD]

### Bugs Found

[This section will be populated with bugs during testing]

---

**Test Suite Created By:** Claude Agent (QA Tester)
**Task:** T021
**Next Steps:** Execute tests and document findings
