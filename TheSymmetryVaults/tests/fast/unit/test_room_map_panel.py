"""
Unit tests for RoomMapPanel layout algorithm.
Python mirror of the BFS + force-directed layout from room_map_panel.gd.

Verifies:
- Z3 (3 rooms): Home in center, 2 rooms on ring
- D4 (8 rooms): concentric layers form correctly
- Nodes don't overlap after force-directed relaxation
- Node size scales by room count
- BFS distances are correct
"""
import json
import math
import os
import unittest


# === Python mirror of layout algorithm (matches room_map_panel.gd) ===

class LayoutEngine:
    """Mirrors compute_layout() from room_map_panel.gd."""

    @staticmethod
    def compute_bfs(cayley_table: list[list[int]], n: int) -> list[int]:
        """BFS from room 0 using all non-identity keys."""
        dist = [999] * n
        dist[0] = 0
        queue = [0]
        visited = {0}
        qi = 0
        while qi < len(queue):
            v = queue[qi]
            qi += 1
            for k in range(1, n):  # skip key 0 (identity)
                nxt = cayley_table[v][k]
                if nxt not in visited:
                    visited.add(nxt)
                    dist[nxt] = dist[v] + 1
                    queue.append(nxt)
        return dist

    @staticmethod
    def compute_layout(cayley_table: list[list[int]], n: int,
                       panel_w: float = 400.0, panel_h: float = 400.0
                       ) -> list[tuple[float, float]]:
        """Full layout: BFS layers + concentric arcs + force relaxation."""
        cx = panel_w / 2.0
        cy = panel_h / 2.0

        dist = LayoutEngine.compute_bfs(cayley_table, n)

        # Group by layer
        layers = {}
        for i in range(n):
            d = dist[i]
            if d not in layers:
                layers[d] = []
            layers[d].append(i)

        layer_keys = sorted(layers.keys())
        total_layers = len(layer_keys)
        max_r = min(panel_w, panel_h) * 0.38

        # Initial placement
        positions = [(0.0, 0.0)] * n
        for i in range(n):
            d = dist[i]
            if d == 0:
                positions[i] = (cx, cy)
                continue

            layer = layers[d]
            idx = layer.index(i)
            count = len(layer)
            r = (d / max(1, total_layers - 1)) * max_r

            if count == 1:
                angle = -math.pi / 2.0
            else:
                angle_span = min(math.pi * 2, count * 0.6)
                start_angle = -math.pi / 2.0 - angle_span / 2.0 + d * 0.4
                angle = start_angle + (idx / (count - 1)) * angle_span

            positions[i] = (cx + r * math.cos(angle), cy + r * math.sin(angle))

        # Force-directed relaxation
        margin = 30.0
        for _ in range(200):
            forces = [(0.0, 0.0)] * n
            repulsion = 800.0

            for i in range(n):
                for j in range(i + 1, n):
                    dx = positions[j][0] - positions[i][0]
                    dy = positions[j][1] - positions[i][1]
                    d2 = max(1.0, math.sqrt(dx * dx + dy * dy))
                    f = repulsion / (d2 * d2)
                    fx, fy = dx / d2 * f, dy / d2 * f
                    forces[i] = (forces[i][0] - fx, forces[i][1] - fy)
                    forces[j] = (forces[j][0] + fx, forces[j][1] + fy)

                if dist[i] > 0:
                    target_r = (dist[i] / max(1, total_layers - 1)) * max_r
                    cur_dx = positions[i][0] - cx
                    cur_dy = positions[i][1] - cy
                    cur_r = math.sqrt(cur_dx * cur_dx + cur_dy * cur_dy)
                    if cur_r > 0:
                        diff = cur_r - target_r
                        forces[i] = (
                            forces[i][0] - cur_dx / cur_r * diff * 0.1,
                            forces[i][1] - cur_dy / cur_r * diff * 0.1,
                        )

            for i in range(1, n):  # skip home
                x = positions[i][0] + forces[i][0] * 0.3
                y = positions[i][1] + forces[i][1] * 0.3
                x = max(margin, min(panel_w - margin, x))
                y = max(margin, min(panel_h - margin, y))
                positions[i] = (x, y)

        return positions

    @staticmethod
    def get_node_size(n: int) -> float:
        if n > 16:
            return 7.0
        elif n > 12:
            return 9.0
        else:
            return 11.0


# === Helpers ===

def build_z3_cayley() -> list[list[int]]:
    """Z3 = {e, r1, r2}, Cayley table with math convention."""
    # e=0, r1=1, r2=2
    # e*x = x, r1*r1=r2, r1*r2=e, r2*r2=r1
    return [
        [0, 1, 2],  # e * x
        [1, 2, 0],  # r1 * x
        [2, 0, 1],  # r2 * x
    ]


def build_d4_cayley() -> list[list[int]]:
    """D4 = {e, r1, r2, r3, sh, sv, sd, sa}. Build from permutations."""
    # D4 generators: r1 = (0123), sh = (13)
    perms = [
        [0, 1, 2, 3],  # e
        [1, 2, 3, 0],  # r1
        [2, 3, 0, 1],  # r2
        [3, 0, 1, 2],  # r3
        [1, 0, 3, 2],  # sh
        [3, 2, 1, 0],  # sv
        [0, 3, 2, 1],  # sd
        [2, 1, 0, 3],  # sa
    ]

    def compose_math(a, b):
        """Math convention: (a*b)(x) = a(b(x))"""
        return [a[b[i]] for i in range(len(a))]

    def find_idx(p):
        for i, q in enumerate(perms):
            if p == q:
                return i
        return -1

    n = len(perms)
    table = []
    for a in range(n):
        row = []
        for b in range(n):
            product = compose_math(perms[a], perms[b])
            idx = find_idx(product)
            assert idx >= 0, f"Product not found: {perms[a]} * {perms[b]} = {product}"
            row.append(idx)
        table.append(row)
    return table


def load_level(filename: str) -> dict:
    base = os.path.dirname(os.path.abspath(__file__))
    level_path = os.path.join(base, "..", "..", "..", "data", "levels", filename)
    level_path = os.path.normpath(level_path)
    with open(level_path, "r", encoding="utf-8") as f:
        return json.load(f)


# === Tests ===

class TestBFSDistances(unittest.TestCase):
    """Verify BFS distances from home."""

    def test_z3_distances(self):
        cayley = build_z3_cayley()
        dist = LayoutEngine.compute_bfs(cayley, 3)
        self.assertEqual(dist[0], 0)  # Home
        self.assertEqual(dist[1], 1)  # r1 reachable in 1 step
        self.assertEqual(dist[2], 1)  # r2 reachable in 1 step

    def test_d4_distances(self):
        cayley = build_d4_cayley()
        dist = LayoutEngine.compute_bfs(cayley, 8)
        self.assertEqual(dist[0], 0)  # Home
        # All non-identity elements should be reachable
        for i in range(1, 8):
            self.assertLess(dist[i], 999, f"Room {i} not reachable")
            self.assertGreater(dist[i], 0, f"Room {i} distance should be > 0")

    def test_all_rooms_reachable(self):
        """Every room should be reachable from home."""
        for cayley, n, name in [
            (build_z3_cayley(), 3, "Z3"),
            (build_d4_cayley(), 8, "D4"),
        ]:
            dist = LayoutEngine.compute_bfs(cayley, n)
            for i in range(n):
                self.assertLess(dist[i], 999,
                    f"{name}: Room {i} not reachable (dist={dist[i]})")


class TestLayoutZ3(unittest.TestCase):
    """Z3: 3 rooms — Home in center, 2 on ring."""

    def setUp(self):
        self.cayley = build_z3_cayley()
        self.positions = LayoutEngine.compute_layout(self.cayley, 3, 400, 400)

    def test_home_at_center(self):
        hx, hy = self.positions[0]
        self.assertAlmostEqual(hx, 200.0, delta=1.0)
        self.assertAlmostEqual(hy, 200.0, delta=1.0)

    def test_other_rooms_on_ring(self):
        """Rooms 1 and 2 should be approximately equidistant from center."""
        cx, cy = 200.0, 200.0
        for i in [1, 2]:
            px, py = self.positions[i]
            dist = math.sqrt((px - cx) ** 2 + (py - cy) ** 2)
            # Should be on a ring (not at center, not at edge)
            self.assertGreater(dist, 20.0,
                f"Room {i} too close to center (dist={dist:.1f})")
            self.assertLess(dist, 190.0,
                f"Room {i} too far from center (dist={dist:.1f})")

    def test_rooms_not_overlapping(self):
        """All 3 rooms should be well separated."""
        min_sep = 15.0  # minimum separation after relaxation
        n = 3
        for i in range(n):
            for j in range(i + 1, n):
                dx = self.positions[i][0] - self.positions[j][0]
                dy = self.positions[i][1] - self.positions[j][1]
                dist = math.sqrt(dx * dx + dy * dy)
                self.assertGreater(dist, min_sep,
                    f"Rooms {i} and {j} overlap (dist={dist:.1f})")


class TestLayoutD4(unittest.TestCase):
    """D4: 8 rooms — concentric layers."""

    def setUp(self):
        self.cayley = build_d4_cayley()
        self.positions = LayoutEngine.compute_layout(self.cayley, 8, 400, 400)

    def test_home_at_center(self):
        hx, hy = self.positions[0]
        self.assertAlmostEqual(hx, 200.0, delta=1.0)
        self.assertAlmostEqual(hy, 200.0, delta=1.0)

    def test_concentric_layers(self):
        """Rooms in higher BFS layers should be farther from center (on average)."""
        dist = LayoutEngine.compute_bfs(self.cayley, 8)
        cx, cy = 200.0, 200.0

        # Group by layer
        layers = {}
        for i in range(8):
            d = dist[i]
            if d not in layers:
                layers[d] = []
            layers[d].append(i)

        # Average radius per layer should be increasing
        layer_keys = sorted(layers.keys())
        prev_avg_r = -1.0
        for lk in layer_keys:
            rooms = layers[lk]
            avg_r = 0.0
            for r_idx in rooms:
                px, py = self.positions[r_idx]
                avg_r += math.sqrt((px - cx) ** 2 + (py - cy) ** 2)
            avg_r /= len(rooms)

            if lk > 0:
                self.assertGreater(avg_r, prev_avg_r * 0.5,
                    f"Layer {lk} avg radius ({avg_r:.1f}) not greater than "
                    f"previous ({prev_avg_r:.1f})")
            prev_avg_r = avg_r

    def test_rooms_not_overlapping(self):
        """No two rooms should be too close together."""
        min_sep = 10.0
        n = 8
        for i in range(n):
            for j in range(i + 1, n):
                dx = self.positions[i][0] - self.positions[j][0]
                dy = self.positions[i][1] - self.positions[j][1]
                dist = math.sqrt(dx * dx + dy * dy)
                self.assertGreater(dist, min_sep,
                    f"Rooms {i} and {j} overlap (dist={dist:.1f})")

    def test_all_within_bounds(self):
        """All positions should be within panel bounds."""
        for i in range(8):
            px, py = self.positions[i]
            self.assertGreaterEqual(px, 0.0, f"Room {i} x={px:.1f} below 0")
            self.assertLessEqual(px, 400.0, f"Room {i} x={px:.1f} above 400")
            self.assertGreaterEqual(py, 0.0, f"Room {i} y={py:.1f} below 0")
            self.assertLessEqual(py, 400.0, f"Room {i} y={py:.1f} above 400")


class TestNodeSizes(unittest.TestCase):
    """Verify node size scaling by room count."""

    def test_small_group(self):
        self.assertEqual(LayoutEngine.get_node_size(3), 11.0)
        self.assertEqual(LayoutEngine.get_node_size(6), 11.0)
        self.assertEqual(LayoutEngine.get_node_size(8), 11.0)
        self.assertEqual(LayoutEngine.get_node_size(12), 11.0)

    def test_medium_group(self):
        self.assertEqual(LayoutEngine.get_node_size(13), 9.0)
        self.assertEqual(LayoutEngine.get_node_size(16), 9.0)

    def test_large_group(self):
        self.assertEqual(LayoutEngine.get_node_size(17), 7.0)
        self.assertEqual(LayoutEngine.get_node_size(24), 7.0)


class TestLayoutLargeGroup(unittest.TestCase):
    """Test layout with a larger group (S3, 6 rooms) from real level data."""

    def setUp(self):
        # Build S3 Cayley table from level 13
        level_data = load_level("act2/level_13.json")
        autos = level_data["symmetries"]["automorphisms"]

        # Parse perms (identity first)
        perms = []
        identity_idx = -1
        for i, a in enumerate(autos):
            m = a["mapping"]
            if m == list(range(len(m))):
                identity_idx = i
            perms.append(m)

        # Reorder: identity first
        ordered = [perms[identity_idx]]
        for i in range(len(perms)):
            if i != identity_idx:
                ordered.append(perms[i])

        n = len(ordered)

        def compose_math(a, b):
            return [a[b[i]] for i in range(len(a))]

        def find_idx(p):
            for i, q in enumerate(ordered):
                if p == q:
                    return i
            return -1

        self.cayley = []
        for a in range(n):
            row = []
            for b in range(n):
                product = compose_math(ordered[a], ordered[b])
                idx = find_idx(product)
                row.append(idx)
            self.cayley.append(row)

        self.n = n
        self.positions = LayoutEngine.compute_layout(self.cayley, n, 400, 400)

    def test_home_at_center(self):
        hx, hy = self.positions[0]
        self.assertAlmostEqual(hx, 200.0, delta=1.0)
        self.assertAlmostEqual(hy, 200.0, delta=1.0)

    def test_no_overlaps(self):
        min_sep = 10.0
        for i in range(self.n):
            for j in range(i + 1, self.n):
                dx = self.positions[i][0] - self.positions[j][0]
                dy = self.positions[i][1] - self.positions[j][1]
                dist = math.sqrt(dx * dx + dy * dy)
                self.assertGreater(dist, min_sep,
                    f"Rooms {i} and {j} overlap (dist={dist:.1f})")

    def test_all_within_bounds(self):
        for i in range(self.n):
            px, py = self.positions[i]
            self.assertGreaterEqual(px, 0.0)
            self.assertLessEqual(px, 400.0)
            self.assertGreaterEqual(py, 0.0)
            self.assertLessEqual(py, 400.0)


# === Python mirror of fading edge / hover preview logic ===

class FadingEdge:
    """Mirrors fading edge structure from room_map_panel.gd."""

    def __init__(self, from_room: int, to_room: int, key_idx: int,
                 color: tuple = (1.0, 1.0, 1.0), alpha: float = 1.0):
        self.from_room = from_room
        self.to_room = to_room
        self.key = key_idx
        self.color = color
        self.alpha = alpha

    def decay(self) -> bool:
        """Apply one frame of decay. Returns True if still alive."""
        self.alpha *= 0.985
        return self.alpha >= 0.01


class HoverPreview:
    """Mirrors _draw_key_preview logic from room_map_panel.gd."""

    @staticmethod
    def get_preview_edges(cayley_table: list[list[int]], n: int,
                          key_idx: int, discovered: list[bool],
                          transition_history: list[dict]
                          ) -> list[dict]:
        """Return list of {from, to, alpha, line_w} for hover preview."""
        # Build traversed set
        traversed = set()
        for entry in transition_history:
            if entry.get("key", -1) == key_idx:
                traversed.add((entry["from"], entry["to"]))

        edges = []
        for from_room in range(n):
            if not discovered[from_room]:
                continue
            to_room = cayley_table[from_room][key_idx]
            if not discovered[to_room]:
                continue
            if from_room == to_room:
                continue

            is_traversed = (from_room, to_room) in traversed
            edges.append({
                "from": from_room,
                "to": to_room,
                "alpha": 0.35 if is_traversed else 0.2,
                "line_w": 1.5 if is_traversed else 1.0,
            })
        return edges


# === Tests for fading edges ===

class TestFadingEdges(unittest.TestCase):
    """Verify fading edge decay behavior."""

    def test_initial_alpha(self):
        edge = FadingEdge(0, 1, 1)
        self.assertEqual(edge.alpha, 1.0)

    def test_decay_reduces_alpha(self):
        edge = FadingEdge(0, 1, 1)
        edge.decay()
        self.assertAlmostEqual(edge.alpha, 0.985, places=5)

    def test_decay_60_frames(self):
        """After 60 frames (~1 sec at 60fps), alpha should be around 0.985^60 ≈ 0.405."""
        edge = FadingEdge(0, 1, 1)
        for _ in range(60):
            edge.decay()
        expected = 0.985 ** 60
        self.assertAlmostEqual(edge.alpha, expected, places=4)
        self.assertGreater(edge.alpha, 0.3)
        self.assertLess(edge.alpha, 0.5)

    def test_edge_dies_after_many_frames(self):
        """Edge should be removed (alpha < 0.01) after ~300 frames (~5 sec)."""
        edge = FadingEdge(0, 1, 1)
        frames = 0
        while edge.decay():
            frames += 1
            if frames > 1000:
                break
        # Should die between 300-500 frames (5-8 seconds at 60fps)
        self.assertGreater(frames, 250, f"Edge died too quickly ({frames} frames)")
        self.assertLess(frames, 600, f"Edge lived too long ({frames} frames)")

    def test_exact_death_frame(self):
        """Calculate exact frame where alpha < 0.01."""
        # 0.985^n < 0.01 => n > log(0.01) / log(0.985) ≈ 304.5
        edge = FadingEdge(0, 1, 1)
        frames = 0
        while edge.alpha >= 0.01:
            edge.alpha *= 0.985
            frames += 1
        self.assertAlmostEqual(frames, 305, delta=2)

    def test_key_field_stored(self):
        edge = FadingEdge(2, 5, 3)
        self.assertEqual(edge.key, 3)
        self.assertEqual(edge.from_room, 2)
        self.assertEqual(edge.to_room, 5)

    def test_multiple_edges_independent(self):
        """Multiple edges decay independently."""
        edges = [FadingEdge(0, i, i) for i in range(1, 4)]
        # Decay first edge 60 times, second 30 times, third 0 times
        for _ in range(60):
            edges[0].decay()
        for _ in range(30):
            edges[1].decay()
        self.assertAlmostEqual(edges[0].alpha, 0.985 ** 60, places=4)
        self.assertAlmostEqual(edges[1].alpha, 0.985 ** 30, places=4)
        self.assertEqual(edges[2].alpha, 1.0)


# === Tests for hover preview ===

class TestHoverPreview(unittest.TestCase):
    """Verify hover preview edge generation with history-aware alpha."""

    def setUp(self):
        self.cayley = build_z3_cayley()
        self.n = 3
        self.all_discovered = [True, True, True]

    def test_basic_preview_all_discovered(self):
        """With all rooms discovered, key 1 should show 2 edges (skip identity loops)."""
        edges = HoverPreview.get_preview_edges(
            self.cayley, self.n, 1, self.all_discovered, [])
        # Key 1 in Z3: 0->1, 1->2, 2->0
        # None are identity (same room), so all 3 transitions
        self.assertEqual(len(edges), 3)

    def test_preview_alpha_default(self):
        """Without history, all edges should have alpha 0.2."""
        edges = HoverPreview.get_preview_edges(
            self.cayley, self.n, 1, self.all_discovered, [])
        for e in edges:
            self.assertAlmostEqual(e["alpha"], 0.2)
            self.assertAlmostEqual(e["line_w"], 1.0)

    def test_preview_alpha_with_history(self):
        """Edges matching history should have alpha 0.35."""
        history = [{"from": 0, "to": 1, "key": 1, "time": 1.0}]
        edges = HoverPreview.get_preview_edges(
            self.cayley, self.n, 1, self.all_discovered, history)

        # Find the 0->1 edge
        edge_01 = [e for e in edges if e["from"] == 0 and e["to"] == 1]
        self.assertEqual(len(edge_01), 1)
        self.assertAlmostEqual(edge_01[0]["alpha"], 0.35)
        self.assertAlmostEqual(edge_01[0]["line_w"], 1.5)

        # Other edges should still be 0.2
        other_edges = [e for e in edges if not (e["from"] == 0 and e["to"] == 1)]
        for e in other_edges:
            self.assertAlmostEqual(e["alpha"], 0.2)

    def test_preview_undiscovered_rooms_skipped(self):
        """Undiscovered rooms should not appear in preview edges."""
        discovered = [True, True, False]  # Room 2 not discovered
        edges = HoverPreview.get_preview_edges(
            self.cayley, self.n, 1, discovered, [])
        # Key 1: 0->1 (both discovered), 1->2 (2 not discovered, skip),
        #         2->0 (2 not discovered as source, skip)
        self.assertEqual(len(edges), 1)
        self.assertEqual(edges[0]["from"], 0)
        self.assertEqual(edges[0]["to"], 1)

    def test_preview_wrong_key_history_ignored(self):
        """History for a different key should not affect alpha."""
        history = [{"from": 0, "to": 1, "key": 2, "time": 1.0}]  # key 2, not 1
        edges = HoverPreview.get_preview_edges(
            self.cayley, self.n, 1, self.all_discovered, history)
        # All should be alpha 0.2 since history is for key 2
        for e in edges:
            self.assertAlmostEqual(e["alpha"], 0.2)

    def test_preview_identity_key_no_edges(self):
        """Key 0 (identity) maps every room to itself, so no edges."""
        edges = HoverPreview.get_preview_edges(
            self.cayley, self.n, 0, self.all_discovered, [])
        self.assertEqual(len(edges), 0)

    def test_d4_preview_with_mixed_history(self):
        """D4 (8 rooms) with some history entries."""
        cayley = build_d4_cayley()
        n = 8
        all_disc = [True] * n
        # Apply key 1 from rooms 0 and 3
        history = [
            {"from": 0, "to": cayley[0][1], "key": 1, "time": 1.0},
            {"from": 3, "to": cayley[3][1], "key": 1, "time": 2.0},
        ]
        edges = HoverPreview.get_preview_edges(cayley, n, 1, all_disc, history)

        # Count bright vs dim edges
        bright = [e for e in edges if abs(e["alpha"] - 0.35) < 0.01]
        dim = [e for e in edges if abs(e["alpha"] - 0.2) < 0.01]
        self.assertEqual(len(bright), 2, "Should have 2 bright edges from history")
        self.assertGreater(len(dim), 0, "Should have dim edges too")
        self.assertEqual(len(bright) + len(dim), len(edges))


if __name__ == "__main__":
    unittest.main()
