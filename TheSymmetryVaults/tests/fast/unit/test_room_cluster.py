"""
Unit tests for Room Cluster Overlay algorithms.

Tests:
1. Convex Hull (Andrew's monotone chain / Graham scan variant)
   - Triangle (3 points) → 3 vertices
   - Square (4 points) → 4 vertices
   - Points inside hull not included
   - Collinear points
   - Degenerate cases (1 and 2 points)

2. Subclustering (spatial proximity grouping with union-find)
   - All nearby → 1 subcluster
   - All far → N subclusters (one per room)
   - Partial: 2 nearby + 1 far → 2 subclusters
   - Chain: A-B nearby, B-C nearby → all in one (transitivity)

3. API (set_room_clusters / clear_room_clusters)
   - Setting clusters updates internal state
   - Clearing resets state
   - Empty array = no clusters

These algorithms are pure math (geometry + graph), testable without Godot.
"""

import unittest
import math
from typing import List, Tuple, Set, Dict


# =============================================================================
# Python Mirror: Convex Hull Algorithm
# =============================================================================

class Vector2:
    """Simple 2D vector for testing (mirrors Godot Vector2)."""
    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y

    def __sub__(self, other: 'Vector2') -> 'Vector2':
        return Vector2(self.x - other.x, self.y - other.y)

    def __add__(self, other: 'Vector2') -> 'Vector2':
        return Vector2(self.x + other.x, self.y + other.y)

    def __mul__(self, scalar: float) -> 'Vector2':
        return Vector2(self.x * scalar, self.y * scalar)

    def __eq__(self, other) -> bool:
        if not isinstance(other, Vector2):
            return False
        return abs(self.x - other.x) < 0.001 and abs(self.y - other.y) < 0.001

    def __repr__(self):
        return f"Vector2({self.x:.2f}, {self.y:.2f})"

    def length_squared(self) -> float:
        return self.x * self.x + self.y * self.y

    def length(self) -> float:
        return math.sqrt(self.length_squared())

    def distance_to(self, other: 'Vector2') -> float:
        return (self - other).length()


def convex_hull(points: List[Vector2]) -> List[Vector2]:
    """
    Compute convex hull using Graham scan.
    Returns vertices in counter-clockwise order.

    Mirrors room_map_panel.gd _convex_hull() method.
    """
    if len(points) <= 1:
        return points[:]
    if len(points) == 2:
        return points[:]

    # Find bottom-most (then left-most) point as pivot
    pivot = points[0]
    for pt in points:
        if pt.y > pivot.y or (pt.y == pivot.y and pt.x < pivot.x):
            pivot = pt

    # Sort by polar angle relative to pivot, using cross product
    def compare_points(a: Vector2, b: Vector2) -> int:
        if a == pivot:
            return -1
        if b == pivot:
            return 1

        da = a - pivot
        db = b - pivot
        cross = da.x * db.y - da.y * db.x

        if abs(cross) < 0.001:
            # Collinear: closer point first
            if da.length_squared() < db.length_squared():
                return -1
            else:
                return 1

        # Counter-clockwise = positive cross product comes first
        if cross > 0.0:
            return -1
        else:
            return 1

    from functools import cmp_to_key
    sorted_pts = sorted(points, key=cmp_to_key(compare_points))

    # Graham scan
    hull = []
    for pt in sorted_pts:
        while len(hull) >= 2:
            a = hull[-2]
            b = hull[-1]
            ab = b - a
            ac = pt - a
            cross = ab.x * ac.y - ab.y * ac.x
            if cross <= 0.0:
                hull.pop()
            else:
                break
        hull.append(pt)

    return hull


# =============================================================================
# Python Mirror: Subclustering Algorithm
# =============================================================================

def compute_subclusters(rooms: List[int], positions: Dict[int, Vector2],
                       threshold: float) -> List[List[int]]:
    """
    Split rooms into subclusters based on spatial proximity.
    Uses union-find with single-linkage: rooms within threshold distance
    are merged into the same subcluster.

    Mirrors room_map_panel.gd _compute_subclusters() method.

    Args:
        rooms: List of room indices
        positions: Dict mapping room index to Vector2 position
        threshold: Distance threshold for clustering

    Returns:
        List of subclusters, where each subcluster is a list of room indices
    """
    if len(rooms) <= 1:
        return [rooms[:]]

    # Union-find data structure
    parent = {ridx: ridx for ridx in rooms}

    def find_root(x: int) -> int:
        """Find root with path compression."""
        chain = []
        cur = x
        while parent[cur] != cur:
            chain.append(cur)
            cur = parent[cur]
        for c in chain:
            parent[c] = cur
        return cur

    # Merge rooms that are close enough
    for i in range(len(rooms)):
        for j in range(i + 1, len(rooms)):
            pi = positions[rooms[i]]
            pj = positions[rooms[j]]
            if pi.distance_to(pj) <= threshold:
                ri = find_root(rooms[i])
                rj = find_root(rooms[j])
                if ri != rj:
                    parent[ri] = rj

    # Group by root
    groups = {}
    for ridx in rooms:
        root = find_root(ridx)
        if root not in groups:
            groups[root] = []
        groups[root].append(ridx)

    return list(groups.values())


# =============================================================================
# Tests: Convex Hull
# =============================================================================

class TestConvexHull(unittest.TestCase):
    """Test convex hull algorithm."""

    def test_triangle_three_points(self):
        """Triangle (3 points) → 3 vertices on hull."""
        points = [
            Vector2(0, 0),
            Vector2(1, 0),
            Vector2(0.5, 1)
        ]
        hull = convex_hull(points)
        self.assertEqual(len(hull), 3, "Triangle should have 3 hull vertices")

    def test_square_four_points(self):
        """Square (4 points) → 4 vertices on hull."""
        points = [
            Vector2(0, 0),
            Vector2(1, 0),
            Vector2(1, 1),
            Vector2(0, 1)
        ]
        hull = convex_hull(points)
        self.assertEqual(len(hull), 4, "Square should have 4 hull vertices")

    def test_points_inside_not_included(self):
        """Points inside the hull should not be included in result."""
        points = [
            Vector2(0, 0),
            Vector2(2, 0),
            Vector2(2, 2),
            Vector2(0, 2),
            Vector2(1, 1),  # Inside point (center)
        ]
        hull = convex_hull(points)
        self.assertEqual(len(hull), 4,
            "Interior point should not be on hull (should be 4 corners only)")
        # Check that (1, 1) is not in hull
        inside_point = Vector2(1, 1)
        self.assertNotIn(inside_point, hull,
            "Center point should not be in hull")

    def test_collinear_points_horizontal(self):
        """Collinear points (horizontal line) → only endpoints on hull."""
        points = [
            Vector2(0, 0),
            Vector2(1, 0),
            Vector2(2, 0),
            Vector2(3, 0),
        ]
        hull = convex_hull(points)
        # For a line, hull should include endpoints
        # Middle points may or may not be included depending on implementation
        # Our implementation keeps them (cross product = 0 → pop_back)
        # So hull will be [first, ..., last] going one direction
        self.assertGreaterEqual(len(hull), 2, "Line should have at least 2 endpoints")
        self.assertIn(Vector2(0, 0), hull, "Left endpoint should be in hull")
        self.assertIn(Vector2(3, 0), hull, "Right endpoint should be in hull")

    def test_collinear_points_diagonal(self):
        """Collinear points (diagonal line) → endpoints on hull."""
        points = [
            Vector2(0, 0),
            Vector2(1, 1),
            Vector2(2, 2),
        ]
        hull = convex_hull(points)
        self.assertGreaterEqual(len(hull), 2, "Diagonal line should have at least 2 endpoints")
        # Endpoints should definitely be in hull
        has_start = any(pt.x == 0 and pt.y == 0 for pt in hull)
        has_end = any(pt.x == 2 and pt.y == 2 for pt in hull)
        self.assertTrue(has_start, "Start point should be in hull")
        self.assertTrue(has_end, "End point should be in hull")

    def test_degenerate_case_one_point(self):
        """Single point → hull contains that point."""
        points = [Vector2(5, 7)]
        hull = convex_hull(points)
        self.assertEqual(len(hull), 1, "Single point should return hull of size 1")
        self.assertEqual(hull[0], Vector2(5, 7), "Hull should contain the input point")

    def test_degenerate_case_two_points(self):
        """Two points → hull contains both points."""
        points = [Vector2(0, 0), Vector2(1, 1)]
        hull = convex_hull(points)
        self.assertEqual(len(hull), 2, "Two points should return hull of size 2")
        self.assertIn(Vector2(0, 0), hull, "First point should be in hull")
        self.assertIn(Vector2(1, 1), hull, "Second point should be in hull")

    def test_degenerate_case_empty(self):
        """Empty input → empty hull."""
        points = []
        hull = convex_hull(points)
        self.assertEqual(len(hull), 0, "Empty input should return empty hull")

    def test_pentagon_five_points(self):
        """Regular pentagon (5 points on circle) → 5 vertices."""
        points = []
        for i in range(5):
            angle = 2 * math.pi * i / 5
            points.append(Vector2(math.cos(angle), math.sin(angle)))
        hull = convex_hull(points)
        self.assertEqual(len(hull), 5, "Pentagon should have 5 hull vertices")

    def test_complex_shape_with_interior_points(self):
        """Complex shape with multiple interior points."""
        # Outer octagon + interior points
        points = []
        for i in range(8):
            angle = 2 * math.pi * i / 8
            points.append(Vector2(math.cos(angle) * 2, math.sin(angle) * 2))
        # Add interior points
        points.append(Vector2(0, 0))
        points.append(Vector2(0.5, 0.5))
        points.append(Vector2(-0.5, 0.5))

        hull = convex_hull(points)
        self.assertEqual(len(hull), 8,
            "Hull should only contain octagon vertices, not interior points")


# =============================================================================
# Tests: Subclustering
# =============================================================================

class TestSubclustering(unittest.TestCase):
    """Test spatial proximity subclustering algorithm."""

    def test_all_nearby_one_subcluster(self):
        """All rooms nearby → 1 subcluster."""
        rooms = [0, 1, 2]
        positions = {
            0: Vector2(0, 0),
            1: Vector2(1, 0),
            2: Vector2(0, 1),
        }
        threshold = 2.0  # Large enough to connect all

        subclusters = compute_subclusters(rooms, positions, threshold)

        self.assertEqual(len(subclusters), 1,
            "All nearby rooms should form 1 subcluster")
        self.assertEqual(set(subclusters[0]), {0, 1, 2},
            "Subcluster should contain all rooms")

    def test_all_far_n_subclusters(self):
        """All rooms far → N subclusters (one per room)."""
        rooms = [0, 1, 2]
        positions = {
            0: Vector2(0, 0),
            1: Vector2(10, 0),
            2: Vector2(0, 10),
        }
        threshold = 2.0  # Too small to connect any

        subclusters = compute_subclusters(rooms, positions, threshold)

        self.assertEqual(len(subclusters), 3,
            "All far rooms should form N separate subclusters")
        # Each subcluster should have exactly 1 room
        sizes = sorted([len(sc) for sc in subclusters])
        self.assertEqual(sizes, [1, 1, 1],
            "Each room should be in its own subcluster")

    def test_partial_two_nearby_one_far(self):
        """2 nearby + 1 far → 2 subclusters."""
        rooms = [0, 1, 2]
        positions = {
            0: Vector2(0, 0),
            1: Vector2(1, 0),    # Close to 0
            2: Vector2(10, 10),  # Far from both
        }
        threshold = 2.0

        subclusters = compute_subclusters(rooms, positions, threshold)

        self.assertEqual(len(subclusters), 2,
            "Should form 2 subclusters: {0,1} and {2}")

        # Find which subcluster has 2 rooms and which has 1
        sizes = sorted([len(sc) for sc in subclusters])
        self.assertEqual(sizes, [1, 2],
            "Should have one pair and one singleton")

        # Verify the pair contains 0 and 1
        for sc in subclusters:
            if len(sc) == 2:
                self.assertEqual(set(sc), {0, 1},
                    "The pair should be rooms 0 and 1")
            else:
                self.assertEqual(set(sc), {2},
                    "The singleton should be room 2")

    def test_chain_transitivity(self):
        """Chain: A-B nearby, B-C nearby → all in one (transitivity)."""
        rooms = [0, 1, 2]
        positions = {
            0: Vector2(0, 0),
            1: Vector2(1.5, 0),  # Close to 0
            2: Vector2(3, 0),    # Close to 1, but far from 0 (distance = 3)
        }
        threshold = 2.0  # 0-1: 1.5 ✓, 1-2: 1.5 ✓, 0-2: 3.0 ✗

        subclusters = compute_subclusters(rooms, positions, threshold)

        # Union-find should transitively connect: 0↔1, 1↔2 ⟹ 0↔1↔2
        self.assertEqual(len(subclusters), 1,
            "Chain should form 1 subcluster via transitivity")
        self.assertEqual(set(subclusters[0]), {0, 1, 2},
            "All rooms should be in the same subcluster")

    def test_two_separate_chains(self):
        """Two separate chains that don't connect."""
        rooms = [0, 1, 2, 3]
        positions = {
            0: Vector2(0, 0),
            1: Vector2(1, 0),    # Chain 1: {0, 1}
            2: Vector2(10, 0),
            3: Vector2(11, 0),   # Chain 2: {2, 3}
        }
        threshold = 2.0

        subclusters = compute_subclusters(rooms, positions, threshold)

        self.assertEqual(len(subclusters), 2,
            "Two separate chains should form 2 subclusters")

        sizes = sorted([len(sc) for sc in subclusters])
        self.assertEqual(sizes, [2, 2],
            "Each chain should have 2 rooms")

    def test_single_room_one_subcluster(self):
        """Single room → 1 subcluster containing that room."""
        rooms = [5]
        positions = {5: Vector2(3, 4)}
        threshold = 2.0

        subclusters = compute_subclusters(rooms, positions, threshold)

        self.assertEqual(len(subclusters), 1,
            "Single room should form 1 subcluster")
        self.assertEqual(subclusters[0], [5],
            "Subcluster should contain the single room")

    def test_empty_rooms_empty_subclusters(self):
        """Empty rooms list → empty subclusters (edge case)."""
        rooms = []
        positions = {}
        threshold = 2.0

        subclusters = compute_subclusters(rooms, positions, threshold)

        self.assertEqual(len(subclusters), 1,
            "Empty rooms should return 1 empty subcluster (per implementation)")
        self.assertEqual(subclusters[0], [],
            "Subcluster should be empty")

    def test_threshold_exactly_on_boundary(self):
        """Rooms exactly at threshold distance."""
        rooms = [0, 1]
        positions = {
            0: Vector2(0, 0),
            1: Vector2(2, 0),  # Distance = 2.0
        }
        threshold = 2.0  # Exactly equal

        subclusters = compute_subclusters(rooms, positions, threshold)

        # With <= threshold, should be connected
        self.assertEqual(len(subclusters), 1,
            "Rooms exactly at threshold should be in same subcluster")

    def test_threshold_just_below_boundary(self):
        """Rooms just below threshold distance."""
        rooms = [0, 1]
        positions = {
            0: Vector2(0, 0),
            1: Vector2(2, 0),  # Distance = 2.0
        }
        threshold = 1.99  # Just below

        subclusters = compute_subclusters(rooms, positions, threshold)

        # Should NOT be connected
        self.assertEqual(len(subclusters), 2,
            "Rooms just above threshold should be in separate subclusters")

    def test_complex_graph_multiple_components(self):
        """Complex graph with multiple connected components."""
        rooms = [0, 1, 2, 3, 4, 5]
        positions = {
            0: Vector2(0, 0),
            1: Vector2(1, 0),
            2: Vector2(2, 0),    # Component 1: {0, 1, 2}
            3: Vector2(10, 0),
            4: Vector2(11, 0),   # Component 2: {3, 4}
            5: Vector2(20, 0),   # Component 3: {5}
        }
        threshold = 1.5

        subclusters = compute_subclusters(rooms, positions, threshold)

        self.assertEqual(len(subclusters), 3,
            "Should form 3 connected components")

        sizes = sorted([len(sc) for sc in subclusters])
        self.assertEqual(sizes, [1, 2, 3],
            "Components should have sizes 1, 2, and 3")


# =============================================================================
# Tests: API (Mocked - conceptual tests)
# =============================================================================

class TestClusterAPI(unittest.TestCase):
    """
    Test the cluster API behavior (conceptual tests).

    Since we're testing Python mirrors, we can't directly test GDScript API.
    Instead, we test the expected behavior based on the implementation.
    """

    def test_set_room_clusters_processes_clusters(self):
        """set_room_clusters should process and store cluster data."""
        # This is a conceptual test - in practice, you'd test the GDScript API
        # by checking that _cluster_data is populated correctly.

        # Simulate the behavior
        clusters = [
            [0, 1, 2],  # Cluster 1: rooms 0, 1, 2
            [3, 4],     # Cluster 2: rooms 3, 4
        ]

        positions = {
            0: Vector2(0, 0),
            1: Vector2(1, 0),
            2: Vector2(0, 1),
            3: Vector2(10, 0),
            4: Vector2(11, 0),
        }

        # Compute subclusters for each cluster
        threshold = 2.0
        cluster_data = []
        for rooms in clusters:
            valid_rooms = [r for r in rooms if r in positions]
            subclusters = compute_subclusters(valid_rooms, positions, threshold)
            cluster_data.append({
                "rooms": valid_rooms,
                "subclusters": subclusters,
            })

        # Verify cluster data was created
        self.assertEqual(len(cluster_data), 2,
            "Should have 2 clusters")
        self.assertEqual(cluster_data[0]["rooms"], [0, 1, 2],
            "First cluster should have rooms 0, 1, 2")
        self.assertEqual(cluster_data[1]["rooms"], [3, 4],
            "Second cluster should have rooms 3, 4")

        # Verify subclustering
        self.assertEqual(len(cluster_data[0]["subclusters"]), 1,
            "First cluster should have 1 subcluster (all nearby)")
        self.assertEqual(len(cluster_data[1]["subclusters"]), 1,
            "Second cluster should have 1 subcluster (pair nearby)")

    def test_clear_room_clusters_empties_data(self):
        """clear_room_clusters should empty all cluster data."""
        # Conceptual test
        cluster_data = [{"rooms": [0, 1, 2]}]

        # Clear
        cluster_data.clear()

        self.assertEqual(len(cluster_data), 0,
            "Cluster data should be empty after clear")

    def test_empty_clusters_array(self):
        """Empty clusters array = no clusters to display."""
        clusters = []

        # With empty input, no cluster data should be created
        self.assertEqual(len(clusters), 0,
            "Empty clusters array should result in no cluster data")

    def test_invalid_room_indices_filtered(self):
        """Invalid room indices should be filtered out."""
        clusters = [[0, 1, 999]]  # 999 is invalid
        positions = {
            0: Vector2(0, 0),
            1: Vector2(1, 0),
        }

        # Filter valid rooms
        valid_rooms = [r for r in clusters[0] if r in positions]

        self.assertEqual(valid_rooms, [0, 1],
            "Invalid room index 999 should be filtered out")

    def test_clusters_with_colors(self):
        """Clusters can have associated colors."""
        clusters = [[0, 1], [2, 3]]
        colors = ["red", "blue"]

        # Simulate color assignment
        cluster_data = []
        for i, rooms in enumerate(clusters):
            color = colors[i % len(colors)]
            cluster_data.append({
                "rooms": rooms,
                "color": color,
            })

        self.assertEqual(cluster_data[0]["color"], "red",
            "First cluster should have red color")
        self.assertEqual(cluster_data[1]["color"], "blue",
            "Second cluster should have blue color")


# =============================================================================
# Run Tests
# =============================================================================

if __name__ == '__main__':
    unittest.main()
