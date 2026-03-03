# Plan: Universal Room Cluster Outline on room_map

## Problem
Currently rooms on the room_map are only grouped by color (Layer 5 cosets) or individual glows (Layer 3 subgroups). There is no visual "enclosure" — a beautiful outline/border that clearly shows "these rooms belong together". This is needed for:

| Layer | What to outline | Size | Color |
|-------|----------------|------|-------|
| 2 (Green) | Mirror pairs: {a, b} or {a} (self-inverse) | 1-2 rooms | Green theme |
| 3 (Gold) | Subgroups (keyrings) | 1-N rooms | Gold theme |
| 4 (Red) | Normal/non-normal subgroups | 1-N rooms | Red/Green theme |
| 5 (Purple) | Coset classes gN | 1-N rooms | Coset palette (12 colors) |

A single room cluster (size 1) must also look good (e.g., self-inverse key on Layer 2).

## Approach: Convex Hull Outline with Rounded Corners

### Algorithm: `_draw_cluster_outline(room_indices, color, thickness, padding)`

1. **Collect positions**: Get Vector2 positions of all rooms in the cluster
2. **Single room**: Draw a rounded rectangle (larger than the room square) with glow
3. **Two rooms**: Draw a "pill" shape (rounded rect enclosing both)
4. **3+ rooms**: Compute **convex hull** of room positions, then draw a rounded polygon:
   - Graham scan or gift-wrapping for convex hull
   - Expand hull by `padding` (room_size/2 + extra margin)
   - Round corners with bezier arcs
   - Fill with semi-transparent color (alpha ~0.08)
   - Stroke with theme color (alpha ~0.5, width = thickness)

### Visual Style
- **Fill**: Very subtle tint (alpha 0.05-0.10) — just enough to see the region
- **Stroke**: Clean outline (alpha 0.4-0.6, 1.5-2.5px width)
- **Corner radius**: ~8px for smooth look
- **Glow**: Optional outer glow ring (alpha 0.1, +3px)
- **Label**: Optional text label near centroid (e.g., "gN", "H", "↔")

## Implementation Plan

### Step 1: Add `_draw_cluster_outline()` method to `room_map_panel.gd`

New private method with signature:
```gdscript
func _draw_cluster_outline(
    room_indices: Array,  # Array[int]
    color: Color,
    thickness: float = 2.0,
    padding: float = 8.0,
    fill_alpha: float = 0.08,
    label_text: String = "",
) -> void:
```

Internal logic:
- If `room_indices.size() == 0`: return
- Collect valid positions from `positions[]`
- If 1 position: draw rounded rect centered on room, size = room_sz + padding*2
- If 2 positions: draw "pill" (rounded rect aligned to the two rooms)
- If 3+ positions: compute convex hull, expand, draw rounded polygon

Helper methods needed:
- `_convex_hull(points: Array[Vector2]) -> Array[Vector2]`
- `_expand_hull(hull: Array[Vector2], padding: float) -> Array[Vector2]`
- `_draw_rounded_polygon(points: Array[Vector2], color: Color, fill_alpha: float, stroke_color: Color, stroke_width: float, corner_radius: float)`

### Step 2: Add cluster data structure

New state variable:
```gdscript
## Active cluster outlines to draw
## Each entry: {rooms: Array[int], color: Color, label: String, thickness: float}
var _cluster_outlines: Array = []
```

Public API:
```gdscript
## Set cluster outlines to display. Replaces any previous outlines.
func set_cluster_outlines(clusters: Array) -> void:
    # clusters: Array of {rooms: Array[int], color: Color, label: String}
    _cluster_outlines = clusters
    queue_redraw()

## Clear all cluster outlines.
func clear_cluster_outlines() -> void:
    _cluster_outlines.clear()
    queue_redraw()
```

### Step 3: Integrate into `_draw()` pipeline

In `_draw()`, add cluster outline drawing BEFORE room nodes but AFTER edges:
```gdscript
# --- Cluster outlines (universal grouping visual) ---
_draw_all_cluster_outlines()

# --- Room nodes ---
_draw_room_nodes(n)
```

This ensures outlines appear as a background layer behind the room squares.

### Step 4: Wire up from layer_mode_controller.gd

Each layer sets its own clusters via the public API:

**Layer 2 (mirror pairs)**:
```gdscript
# For each mirror pair, create a cluster of 2 rooms (or 1 for self-inverse)
var clusters = []
for pair in mirror_pairs:
    clusters.append({
        rooms: [pair.key_room, pair.mirror_room],  # or just [pair.key_room] if self-inverse
        color: L2_GREEN,
        label: "↔"
    })
room_map.set_cluster_outlines(clusters)
```

**Layer 3 (subgroups)**:
```gdscript
# When a subgroup is selected, outline it
var clusters = [{
    rooms: subgroup_room_indices,
    color: L3_GOLD,
    label: "H"
}]
room_map.set_cluster_outlines(clusters)
```

**Layer 4 (normal subgroups)**:
```gdscript
# Outline the active subgroup being tested
var clusters = [{
    rooms: subgroup_room_indices,
    color: is_normal ? L4_GREEN : L4_RED,
    label: is_normal ? "N" : "H"
}]
room_map.set_cluster_outlines(clusters)
```

**Layer 5 (coset classes)**:
```gdscript
# Outline each coset class
var clusters = []
for i in range(cosets.size()):
    clusters.append({
        rooms: coset_room_indices[i],
        color: coset_colors[i],
        label: "g%dN" % i  # or representative label
    })
room_map.set_cluster_outlines(clusters)
```

### Step 5: Convex hull algorithm

Graham scan implementation (standard O(n log n)):
```
1. Find lowest-leftmost point as pivot
2. Sort remaining points by polar angle
3. Iterate, keeping only left-turns on the hull stack
```

For expanding the hull by `padding`:
- Offset each edge outward by `padding` along its normal
- Clip resulting polygon (simplified: just move each vertex outward from centroid)

### Step 6: Rounded polygon drawing

Since Godot's `draw_polygon()` only does sharp corners:
- Generate rounded corner points using small arc segments (4-6 points per corner)
- This creates a smooth outline with `draw_polyline()` for stroke
- Use `draw_colored_polygon()` for fill

## Files to Modify

| File | Changes |
|------|---------|
| `room_map_panel.gd` | Add `_draw_cluster_outline()`, `_convex_hull()`, `_expand_hull()`, `_draw_rounded_polygon()`, `set_cluster_outlines()`, `clear_cluster_outlines()`, `_cluster_outlines` state, integrate into `_draw()` |
| `layer_mode_controller.gd` | Wire up `set_cluster_outlines()` calls in `_setup_layer_2/3/4/5()` and related handlers |

## Risks & Considerations

1. **Performance**: Convex hull is O(n log n), called only when clusters change (not every frame). Drawing rounded polygons adds ~20 draw calls per cluster. For ≤12 clusters with ≤24 rooms total, this is negligible.

2. **Edge case: collinear rooms**: Hull may degenerate to a line for 2+ rooms in a line. Handle by falling back to a "pill" shape (elongated rounded rect).

3. **Edge case: overlapping clusters**: Layer 5 cosets partition the group, so no overlap. Layer 3 subgroups don't overlap when only one is shown. Layer 2 pairs don't overlap.

4. **Label placement**: Center of the convex hull (centroid) works for most cases. For 2-room clusters, place label at midpoint above/below.

5. **Existing subgroup highlight**: The current `_draw_subgroup_highlight()` (gold glow + edges) can be REPLACED by the cluster outline + internal edges. Or kept alongside for now.

## Sprint Structure

**Sprint S016**: "Universal cluster outline on room_map"

| Task | Description | Executor |
|------|-------------|----------|
| T133 | Implement `_draw_cluster_outline()` with convex hull, rounded polygon, pill shape, single-room | developer_ui |
| T134 | Add `set_cluster_outlines()` / `clear_cluster_outlines()` API + integrate into `_draw()` pipeline | developer_ui |
| T135 | Wire up cluster outlines for Layers 2, 3, 4, 5 in `layer_mode_controller.gd` | developer_game |
| T136 | Unit tests for convex hull, expand hull, edge cases (1 room, 2 rooms, collinear) | qa_tester |
| T137 | QA: Visual verification of cluster outlines on all layers | qa_tester |
| T138 | Finalize sprint S016 | boss |
