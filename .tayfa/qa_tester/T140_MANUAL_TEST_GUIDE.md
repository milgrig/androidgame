# Manual Testing Guide: T140 - Cluster Visual QA

**Date**: 2026-03-03
**Task**: T140 - Visual testing of cluster overlays across all 5 layers
**Automated Tests**: `tests/agent/test_cluster_visual.py` (10 tests)
**Status**: Infrastructure complete, manual verification needed

---

## Quick Start

### Option 1: Automated Tests (Infrastructure Validation)

```bash
# Requires Godot 4.6+ in PATH
cd TheSymmetryVaults
pytest tests/agent/test_cluster_visual.py -v -s

# Tests will verify:
✓ RoomMapPanel exists in scene tree
✓ Cluster data structures are initialized
✓ Positions are computed for all group orders
✓ Layer integration is wired up correctly
```

**Note**: Automated tests validate STATE but NOT VISUALS. Manual testing required for colors, rendering quality, etc.

### Option 2: Manual Visual Testing (Complete QA)

1. **Launch the game** (not headless)
2. **Select a test level** from the table below
3. **Follow the checklist** for each layer

---

## Test Levels

| Level | Group | Order | Why Test This? |
|-------|-------|-------|----------------|
| level_01 | Z3 | 3 | Prime cyclic (no quotients) - auto-complete |
| level_04 | S3 | 6 | Simple non-abelian (1 normal subgroup) |
| level_05 | D4 | 8 | Dihedral (multiple subgroups, sizes 2, 4) |
| level_23 or level_24 | S4 | 24 | Large group (distant rooms, many subgroups) |

---

## Layer-by-Layer Checklist

### Layer 1: Symmetry Discovery (Baseline)

**Expected**: No clusters visible (just rooms and edges)

**Test**:
- [ ] Load any level
- [ ] Verify NO cluster outlines appear
- [ ] Verify game still functions normally (swap crystals, submit permutations)

**Why**: Ensures clusters don't break existing functionality when inactive.

---

### Layer 2: Mirror Pairs (Green Clusters)

**Expected**: Green clusters around inverse pairs, yellow halos for self-inverse

**Test on level_04 (S3)**:
- [ ] Enter Layer 2 mode (after discovering some keys)
- [ ] **Green capsules** appear around pairs {a, a⁻¹}
- [ ] Capsule smoothly wraps **exactly 2 rooms** (pill shape)
- [ ] If self-inverse element exists (like in D4), **yellow halo** around single room
- [ ] Capsule color: **GREEN** (theme: #00CC66 or similar)
- [ ] Room numbers are **readable** inside capsules

**Edge Case - Self-Inverse**:
- [ ] Load level with reflection symmetry (e.g., D4)
- [ ] Verify self-inverse elements get **single-room yellow halo** (not capsule)

---

### Layer 3: Subgroup Highlight (Gold Cluster)

**Expected**: Gold outline around selected subgroup

**Test on level_04 (S3)**:
- [ ] Enter Layer 3 mode
- [ ] Select a subgroup from keyring (e.g., rotation subgroup Z3)
- [ ] **Gold cluster outline** appears around all rooms in subgroup
- [ ] Outline color: **GOLD** (#FFD700 or similar)
- [ ] **Switch to different subgroup** → outline updates immediately
- [ ] For size-1 subgroup: **gold halo** around single room

**Test on level_05 (D4)**:
- [ ] Test subgroups of varying sizes: |H| = 2, |H| = 4
- [ ] Verify outline adapts to group size (halo, capsule, or convex hull)

---

### Layer 4: Normality Testing (Red/Green Cluster)

**Expected**: Red cluster during testing, turns green if normal

**Test on level_04 (S3)**:
- [ ] Enter Layer 4 mode
- [ ] Select a subgroup to test for normality
- [ ] **Red cluster outline** appears during test
- [ ] After confirming normality: outline turns **GREEN**
- [ ] For non-normal subgroup: stays **RED**

---

### Layer 5: Quotient Groups (Multi-Color Cosets)

**Expected**: Each coset class has distinct color from 12-color palette

**Test on level_04 (S3)**: S3/Z3 ≅ Z2 (2 cosets)
- [ ] Enter Layer 5 mode
- [ ] Build quotient groups (two-phase construction)
- [ ] After completing coset assignment:
  - [ ] **2 cluster outlines** appear (one per coset)
  - [ ] Each cluster has **distinct color** from palette
  - [ ] Colors are vibrant and distinguishable
- [ ] After merge animation: quotient graph nodes inherit coset colors

**Test on level_05 (D4)**: Multiple quotients
- [ ] D4 has 3 quotient groups (D4/Z2, D4/V4, etc.)
- [ ] Verify each quotient uses different coset coloring
- [ ] Verify **12 coset colors** cycle correctly (no repeats within one quotient)

---

## Edge Cases & Special Scenarios

### 1. Single-Room Clusters (Halos)

**Test**: Z2 or trivial subgroups
- [ ] Single room → **circular halo** (not degenerate polygon)
- [ ] Halo radius: ~8-12px larger than room square
- [ ] Halo is smooth (12+ segments, not octagon)

### 2. Two-Room Clusters (Capsules)

**Test**: Mirror pairs, order-2 subgroups
- [ ] Two rooms → **pill shape** (rounded rectangle)
- [ ] Capsule axis aligns with the two room centers
- [ ] Rounded ends are smooth (8+ segments per semicircle)

### 3. Three or More Rooms (Convex Hull)

**Test**: Z3 subgroup, larger cosets
- [ ] 3 colocated rooms → **triangle hull** with rounded corners
- [ ] 4 rooms in square → **quadrilateral hull**
- [ ] Corner radius: ~8px (visually smooth)

### 4. Distant Rooms (Subclustering + Dashed Arcs)

**Test**: Large groups like S4 (24 rooms)
- [ ] Load level_23 or level_24 (S4)
- [ ] Select a large subgroup or coset
- [ ] Verify:
  - [ ] **Distant rooms** (>4.5 node widths apart) get **separate outlines**
  - [ ] **Dashed arcs** connect subclusters (not filled region)
  - [ ] Nearby rooms share a **single convex hull bubble**

### 5. Collinear Rooms (Degenerate Hulls)

**Test**: Rooms arranged in a line
- [ ] If 3+ rooms are collinear → capsule shape (elongated pill)
- [ ] Not a degenerate line (should still have width/padding)

---

## Visual Quality Checks

### Colors

| Layer | Color | Hex (Approx) | Alpha |
|-------|-------|--------------|-------|
| Layer 2 | Green | #00CC66 | Fill: 0.08, Stroke: 0.5 |
| Layer 2 (self-inverse) | Yellow | #FFD700 | Fill: 0.08, Stroke: 0.5 |
| Layer 3 | Gold | #FFD700 | Fill: 0.08, Stroke: 0.5 |
| Layer 4 (testing) | Red | #FF0000 | Fill: 0.08, Stroke: 0.5 |
| Layer 4 (normal) | Green | #00FF00 | Fill: 0.08, Stroke: 0.5 |
| Layer 5 | Palette (12 colors) | Various | Fill: 0.08, Stroke: 0.5 |

**Verify**:
- [ ] Fill alpha is **very subtle** (~0.08) — just enough to see region
- [ ] Stroke alpha is **visible** (~0.5) — clear outline
- [ ] Colors match layer theme (green for Layer 2, gold for Layer 3, etc.)

### Rendering Quality

- [ ] **Rounded corners** are smooth (not jagged)
- [ ] **Stroke width** is consistent (~2px)
- [ ] **Room numbers** are readable under cluster fill
- [ ] **No z-fighting** or flickering
- [ ] **No overlap artifacts** between cluster and room nodes

### Performance

- [ ] **No lag** when switching layers (< 100ms)
- [ ] **No lag** when switching subgroups in Layer 3
- [ ] **Smooth rendering** on S4 (24 rooms with large clusters)
- [ ] **Merge animation** (Layer 5) is smooth (~1-2 seconds)

---

## Regression Testing

Verify that existing functionality still works:

### Layer 1-4 Unchanged

- [ ] **Layer 1**: Symmetry discovery works (swap, submit)
- [ ] **Layer 2**: Inverse relationships still display
- [ ] **Layer 3**: Subgroup discovery panel works
- [ ] **Layer 4**: Normality testing works (conjugation, cracking)

### Map Navigation

- [ ] Pan/zoom map (if implemented)
- [ ] Click rooms to focus
- [ ] Hover highlights still work

### Visual Consistency

- [ ] No broken UI elements
- [ ] No missing textures or colors
- [ ] Font rendering still correct

---

## Bug Reporting Template

If you find a visual issue, report it with:

```
**Bug**: [Brief description]
**Layer**: [1-5]
**Level**: [level_XX]
**Group**: [Z3, S3, D4, etc.]
**Steps to Reproduce**:
1. Load level_XX
2. Enter Layer Y mode
3. Select subgroup Z
4. Observe: [what goes wrong]

**Expected**: [what should happen]
**Actual**: [what actually happens]
**Screenshot**: [attach if possible]
```

---

## Automated Test Results

Run automated tests to verify infrastructure:

```bash
pytest tests/agent/test_cluster_visual.py -v -s
```

**Expected Output**:
```
TestLayer1NoClusters::test_layer1_no_clusters_on_level_01 PASSED ✓
TestLayer1NoClusters::test_layer1_no_clusters_on_level_04 PASSED ✓
TestClusterEdgeCases::test_z3_group_level_01 PASSED ✓
TestClusterEdgeCases::test_s3_group_level_04 PASSED ✓
TestClusterEdgeCases::test_d4_group_level_05 PASSED ✓
TestSubclustering::test_room_positions_loaded PASSED ✓
TestLayerModeIntegration::test_level_scene_has_room_map PASSED ✓
TestManualChecklistReport::test_manual_checklist PASSED ✓

10 passed (or 9 passed + 1 skipped if Godot not in PATH)
```

**If tests fail**: Check implementation in `room_map_panel.gd` and `layer_mode_controller.gd`

---

## Completion Criteria

Task T140 is **DONE** when:

✅ Automated tests pass (infrastructure validated)
✅ Manual checklist completed for all 5 layers
✅ Edge cases verified (Z2, Z3, D4, S4)
✅ Visual quality meets design spec
✅ Performance is acceptable (no lag)
✅ No regressions in Layers 1-4

---

## Notes

- **KB-005 Reminder**: Unit tests cannot verify visual rendering. Manual testing is REQUIRED.
- **Agent Bridge**: Automated tests use Godot headless mode to validate state (not visuals).
- **Test Duration**: Manual testing ~30-45 minutes for all layers and edge cases.

---

**Created by**: QA Agent (Claude)
**Date**: 2026-03-03
**Task**: T140
