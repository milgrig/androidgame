# T149: Manual Testing Guide - KeyBar and Layer 2

**Task:** QA: тестирование key_bar и Layer 2 выбора пары
**Date:** 2026-03-03
**Status:** Ready for Manual Verification

---

## Overview

This guide provides step-by-step instructions for manually testing:
1. **KeyBar Horizontal Layout** - All levels 1-24 should display keys horizontally
2. **Button Sizing** - Buttons adapt based on key count (normal/compact/tiny)
3. **Horizontal Scroll** - Level 13 (23 keys) needs horizontal scroll
4. **Layer 2 Key Selection** - Pairing mode with green/yellow color feedback

---

## Automated Test Results

### Unit Tests (15 tests)
```
tests/fast/unit/test_key_bar.py::TestKeyBarLayout::test_key_bar_is_horizontal PASSED
tests/fast/unit/test_key_bar.py::TestKeyBarLayout::test_button_size_normal_for_few_keys PASSED
tests/fast/unit/test_key_bar.py::TestKeyBarLayout::test_button_size_compact_for_medium_keys PASSED
tests/fast/unit/test_key_bar.py::TestKeyBarLayout::test_button_size_tiny_for_many_keys PASSED
tests/fast/unit/test_key_bar.py::TestKeyBarLayout::test_button_gaps_decrease_with_more_keys PASSED
tests/fast/unit/test_key_bar.py::TestLevelKeyBarSizes::test_level_01_z3_has_3_keys PASSED
tests/fast/unit/test_key_bar.py::TestLevelKeyBarSizes::test_level_04_s3_has_6_keys PASSED
tests/fast/unit/test_key_bar.py::TestLevelKeyBarSizes::test_level_05_d4_has_8_keys PASSED
tests/fast/unit/test_key_bar.py::TestLevelKeyBarSizes::test_level_13_has_23_keys PASSED
tests/fast/unit/test_key_bar.py::TestHorizontalScroll::test_wide_key_bar_needs_scroll PASSED
tests/fast/unit/test_key_bar.py::TestHorizontalScroll::test_level_13_width_calculation PASSED
tests/fast/unit/test_key_bar.py::TestLayer2Pairing::test_layer2_pairing_state_structure PASSED
tests/fast/unit/test_key_bar.py::TestLayer2Pairing::test_layer2_selected_key_tracking PASSED
tests/fast/unit/test_key_bar.py::TestLayer2Pairing::test_layer2_colors PASSED
tests/fast/unit/test_key_bar.py::TestAllLevels::test_all_levels_have_valid_key_counts PASSED

Result: 15/15 PASSED ✓
```

### Agent Bridge Tests (1 test)
```
tests/agent/test_key_bar_visual.py::TestManualVerificationChecklist::test_manual_checklist PASSED

Result: 1/1 PASSED ✓
Note: Visual tests require Godot binary (GODOT_PATH env var) and are skipped without it.
```

---

## Manual Test Cases

### Test 1: KeyBar Horizontal Layout on All Levels

**Objective:** Verify KeyBar displays keys horizontally on levels 1-24

**Prerequisites:**
- Game running in development mode
- Access to all 24 levels (or use level select cheat)

**Steps:**

#### 1.1 Test Level 01 (Z3 - 3 keys)
- [ ] Load level_01
- [ ] Observe KeyBar at bottom of screen
- [ ] **Expected:** 3 key buttons arranged horizontally
- [ ] **Expected:** Button size: normal (64x36 px)
- [ ] **Expected:** Button gap: 5px
- [ ] **Expected:** Total width: ~202px (fits in viewport)

#### 1.2 Test Level 04 (S3 - 6 keys)
- [ ] Load level_04
- [ ] Observe KeyBar
- [ ] **Expected:** 6 key buttons arranged horizontally
- [ ] **Expected:** Button size: normal (64x36 px)
- [ ] **Expected:** Button gap: 5px
- [ ] **Expected:** Total width: ~409px (fits in viewport)

#### 1.3 Test Level 05 (D4 - 8 keys)
- [ ] Load level_05
- [ ] Observe KeyBar
- [ ] **Expected:** 8 key buttons arranged horizontally
- [ ] **Expected:** Button size: normal (64x36 px) - threshold boundary
- [ ] **Expected:** Button gap: 5px
- [ ] **Expected:** Total width: ~547px (fits in viewport)

#### 1.4 Test Level with 9-16 Keys (Compact Size)
- [ ] Load a level with 9-16 keys
- [ ] Observe KeyBar
- [ ] **Expected:** Buttons use compact size (52x30 px)
- [ ] **Expected:** Button gap: 4px
- [ ] **Expected:** Font size: 12px (smaller than normal)

#### 1.5 Test Level 13 (23 keys - Tiny Size)
- [ ] Load level_13
- [ ] Observe KeyBar
- [ ] **Expected:** 23 key buttons arranged horizontally
- [ ] **Expected:** Button size: tiny (44x26 px)
- [ ] **Expected:** Button gap: 3px
- [ ] **Expected:** Total width: ~1078px (exceeds viewport)
- [ ] **Expected:** Horizontal scroll bar appears

---

### Test 2: Horizontal Scroll on Level 13

**Objective:** Verify horizontal scrolling works for levels with many keys

**Prerequisites:**
- Level 13 loaded (23 keys)

**Steps:**

#### 2.1 Verify Scroll Container
- [ ] Load level_13
- [ ] Locate KeyBar at bottom of screen
- [ ] **Expected:** ScrollContainer is visible
- [ ] **Expected:** Horizontal scroll bar appears
- [ ] **Expected:** No vertical scroll bar

#### 2.2 Test Scrolling Left/Right
- [ ] Use mouse/touch to scroll KeyBar left
- [ ] **Expected:** Can see leftmost keys (keys 0-10)
- [ ] Scroll KeyBar right
- [ ] **Expected:** Can see rightmost keys (keys 13-22)
- [ ] **Expected:** Smooth scrolling (no jumps or glitches)

#### 2.3 Verify All Keys Visible
- [ ] Scroll to leftmost position
- [ ] Count visible keys (should see ~8-12 keys depending on viewport width)
- [ ] Scroll to rightmost position
- [ ] Count visible keys
- [ ] **Expected:** Total 23 keys accessible via scrolling
- [ ] **Expected:** No keys hidden or unreachable

#### 2.4 Test Key Click While Scrolled
- [ ] Scroll to middle position
- [ ] Click on a visible key button
- [ ] **Expected:** Key selection works correctly
- [ ] **Expected:** Crystals teleport (if key is discovered)
- [ ] **Expected:** ScrollContainer doesn't reset position

---

### Test 3: Layer 2 Key Selection (Pairing Mode)

**Objective:** Verify Layer 2 pairing mode with green/yellow color feedback

**Prerequisites:**
- Level with inverses loaded (e.g., level_04 - S3)
- All keys discovered (use discovery cheat if needed)
- Layer 2 unlocked and accessible

**Steps:**

#### 3.1 Enter Layer 2 Mode
- [ ] Load level_04 (S3)
- [ ] Discover all 6 keys
- [ ] Switch to Layer 2 mode (via layer selector)
- [ ] **Expected:** KeyBar enters pairing mode
- [ ] **Expected:** Instructions appear (e.g., "Select two keys to check pairing")

#### 3.2 Select First Key
- [ ] Click on key button 1 (e.g., rotation r)
- [ ] **Expected:** Key 1 is highlighted (border or background change)
- [ ] **Expected:** _layer2_selected_key_idx = 1
- [ ] **Expected:** Other keys remain clickable

#### 3.3 Select Valid Pair (Inverse)
- [ ] Click on key button 4 (e.g., r^-1, the inverse of key 1)
- [ ] **Expected:** Both keys highlight in **green** (L2_PAIR_COLOR)
- [ ] **Expected:** Feedback: "Correct! These keys are inverses"
- [ ] **Expected:** Selection resets after 1-2 seconds
- [ ] **Expected:** _layer2_selected_key_idx = -1

#### 3.4 Select Invalid Pair (Not Inverse)
- [ ] Click on key button 2 (e.g., r^2)
- [ ] **Expected:** Key 2 is highlighted
- [ ] Click on key button 3 (e.g., a different symmetry)
- [ ] **Expected:** Error feedback: "Incorrect - not inverses"
- [ ] **Expected:** Selection resets immediately
- [ ] **Expected:** No green highlight

#### 3.5 Select Self-Inverse Key
- [ ] Click on key button 0 (identity - always self-inverse)
- [ ] **Expected:** Key 0 highlights in **yellow** (L2_SELF_COLOR)
- [ ] Click on key 0 again (pair with itself)
- [ ] **Expected:** Feedback: "Correct! This key is self-inverse"
- [ ] **Expected:** Both clicks use yellow highlight
- [ ] **Expected:** Selection resets

#### 3.6 Test Self-Inverse Reflection
- [ ] Click on a reflection key (e.g., key 3 in S3)
- [ ] **Expected:** Highlights in yellow (reflections are self-inverse)
- [ ] Click on key 3 again
- [ ] **Expected:** Validation succeeds
- [ ] **Expected:** Feedback confirms self-inverse

---

### Test 4: Layer 2 Pairing Colors

**Objective:** Verify color constants match design

**Prerequisites:**
- Layer 2 mode active
- Keys discovered

**Steps:**

#### 4.1 Verify Pair Color (Green)
- [ ] Select two keys that are inverses
- [ ] Observe highlight color
- [ ] **Expected:** Color matches L2_PAIR_COLOR = Color(0.2, 0.85, 0.4, 0.7)
- [ ] **Expected:** Green-ish appearance (high G channel)
- [ ] **Expected:** Semi-transparent (alpha = 0.7)

#### 4.2 Verify Self-Inverse Color (Yellow)
- [ ] Select identity or reflection key twice
- [ ] Observe highlight color
- [ ] **Expected:** Color matches L2_SELF_COLOR = Color(1.0, 0.85, 0.3, 0.7)
- [ ] **Expected:** Yellow appearance (high R and G channels)
- [ ] **Expected:** Semi-transparent (alpha = 0.7)

#### 4.3 Verify Color Contrast
- [ ] Check green and yellow colors are easily distinguishable
- [ ] **Expected:** No confusion between pair and self-inverse feedback
- [ ] **Expected:** Colors work on both light and dark backgrounds

---

### Test 5: Regression Testing

**Objective:** Ensure KeyBar changes don't break existing functionality

**Prerequisites:**
- Multiple levels loaded

**Steps:**

#### 5.1 Verify KeyBar on All 24 Levels
- [ ] Load each level from 1-24
- [ ] **Expected:** KeyBar appears correctly on every level
- [ ] **Expected:** No missing keys or layout glitches
- [ ] **Expected:** Button count matches group order

#### 5.2 Verify Button Sizing Adapts
- [ ] Levels 1-5: normal size (64x36)
- [ ] Levels 6-10: varies (check key count)
- [ ] Levels 11-24: compact or tiny based on group size
- [ ] **Expected:** No overlapping buttons
- [ ] **Expected:** Gaps are consistent per size tier

#### 5.3 Verify Key Clicks Still Work
- [ ] Click key buttons in normal mode (not Layer 2)
- [ ] **Expected:** Crystals teleport correctly
- [ ] **Expected:** Current room updates
- [ ] **Expected:** No interference with Layer 2 state

#### 5.4 Verify Layer 2 Doesn't Break Normal Mode
- [ ] Enter Layer 2 mode
- [ ] Select some keys
- [ ] Exit Layer 2 mode (switch to Layer 1)
- [ ] Click key buttons in Layer 1
- [ ] **Expected:** Normal key clicks work
- [ ] **Expected:** No residual Layer 2 highlighting
- [ ] **Expected:** _layer2_selected_key_idx reset to -1

---

## Edge Cases and Error Conditions

### Edge Case 1: Single Key (Order 1)
- [ ] If there's a level with order 1:
  - **Expected:** KeyBar shows 1 button (identity)
  - **Expected:** Normal size (64x36)
  - **Expected:** No scroll needed

### Edge Case 2: Exactly 8 Keys (Threshold Boundary)
- [ ] Load level_05 (D4, order 8)
- [ ] **Expected:** Button size = normal (64x36)
- [ ] **Expected:** Uses COMPACT_THRESHOLD boundary correctly

### Edge Case 3: Exactly 16 Keys (Threshold Boundary)
- [ ] If there's a level with order 16:
  - **Expected:** Button size = compact (52x30)
  - **Expected:** Uses TINY_THRESHOLD boundary correctly

### Edge Case 4: Very Wide Screen
- [ ] Test on wide viewport (e.g., 1920x1080)
- [ ] Load level_13 (23 keys)
- [ ] **Expected:** Scroll bar still appears if total width > viewport width
- [ ] **Expected:** More keys visible at once

### Edge Case 5: Very Narrow Screen
- [ ] Test on narrow viewport (e.g., 800x600 mobile)
- [ ] Load level_01 (3 keys)
- [ ] **Expected:** All 3 keys visible (no scroll)
- [ ] Load level_13 (23 keys)
- [ ] **Expected:** Scroll bar appears
- [ ] **Expected:** Can scroll to see all keys

### Edge Case 6: Layer 2 with No Inverses
- [ ] If a level has keys with no distinct inverses:
  - **Expected:** All keys are self-inverse (yellow)
  - **Expected:** Pairing still works (key with itself)

---

## Known Limitations (Agent Bridge)

The following features **cannot be tested automatically** with current Agent Bridge:
1. **Layer switching** - No `switch_layer(layer_num)` command
2. **KeyBar button clicks** - No `click_key_button(key_idx)` command
3. **Layer 2 state inspection** - No `get_layer2_state()` command
4. **Visual rendering** - Can't verify actual pixel colors or button sizes

**Recommendation:** Extend Agent Bridge with these commands for full automation.

---

## Test Results Summary

| Test Category | Unit Tests | Agent Tests | Manual Tests |
|---------------|-----------|-------------|--------------|
| Horizontal Layout | 5 PASSED | N/A | To be verified |
| Button Sizing | 4 PASSED | N/A | To be verified |
| Horizontal Scroll | 2 PASSED | N/A | To be verified |
| Layer 2 Pairing | 3 PASSED | N/A | To be verified |
| All Levels | 1 PASSED | N/A | To be verified |
| **Total** | **15/15 PASSED** | **1/1 PASSED** | **Pending** |

---

## Conclusion

### Automated Testing
- ✅ **15 unit tests** verify KeyBar layout logic and constants
- ✅ **1 manual checklist test** documents visual verification steps
- ✅ All tests pass without errors

### Manual Testing Required
- 🔍 Visual verification of KeyBar on all 24 levels
- 🔍 Horizontal scroll behavior on level 13
- 🔍 Layer 2 key selection with green/yellow colors
- 🔍 Regression testing of existing key click functionality

### Recommendation
**APPROVE** automated test coverage. Proceed with manual testing using this guide.

---

## Test Environment

- **Python:** 3.12.10
- **pytest:** 9.0.2
- **Unit Test Framework:** unittest
- **Agent Bridge:** tests/agent/agent_client.py
- **Test Files:**
  - `tests/fast/unit/test_key_bar.py` (15 tests)
  - `tests/agent/test_key_bar_visual.py` (9 tests, 8 skipped without Godot)

---

## References

- **Task:** `.tayfa/common/discussions/T149.md`
- **Implementation:** `src/game/key_bar.gd`
- **Related Tests:**
  - `tests/fast/unit/test_cluster_colors_and_clicks.py` (T145)
  - `tests/agent/test_cluster_colors_visual.py` (T145)

---

**Tester:** QA Tester Agent
**Date:** 2026-03-03
**Version:** 1.0
