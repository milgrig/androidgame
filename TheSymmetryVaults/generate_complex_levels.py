#!/usr/bin/env python3
"""
Level generator CLI tool for The Symmetry Vaults.

Generates level JSON files with auto-computed automorphism groups,
Cayley tables, subgroup lattices, and graph structures.

Usage:
    python generate_complex_levels.py --group Z5 --graph cycle_5 --level-id 25
    python generate_complex_levels.py --group S3 --graph complete_3 --level-id 26
    python generate_complex_levels.py --group D4 --graph cycle_4 --level-id 27
    python generate_complex_levels.py --list-groups
    python generate_complex_levels.py --list-graphs
    python generate_complex_levels.py --auto --graph petersen --level-id 28
    python generate_complex_levels.py --validate data/levels/act1/level_01.json
"""

import argparse
import io
import itertools
import json
import math
import os
import sys
from pathlib import Path
from typing import Optional

def _fix_encoding():
    """Fix stdout/stderr encoding for Windows (cp1254 etc.)."""
    if hasattr(sys.stdout, "buffer"):
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "buffer"):
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


# ============================================================================
# Permutation class (mirrors test_core_engine.py)
# ============================================================================

class Permutation:
    """Permutation of [0..n-1]."""

    def __init__(self, mapping: list[int]):
        self.mapping = list(mapping)

    def size(self) -> int:
        return len(self.mapping)

    def apply(self, i: int) -> int:
        return self.mapping[i]

    def is_valid(self) -> bool:
        n = self.size()
        return n > 0 and sorted(self.mapping) == list(range(n))

    def is_identity(self) -> bool:
        return all(self.mapping[i] == i for i in range(self.size()))

    def compose(self, other: "Permutation") -> "Permutation":
        assert self.size() == other.size()
        return Permutation([other.apply(self.apply(i)) for i in range(self.size())])

    def inverse(self) -> "Permutation":
        inv = [0] * self.size()
        for i, v in enumerate(self.mapping):
            inv[v] = i
        return Permutation(inv)

    def order(self) -> int:
        current = Permutation(list(self.mapping))
        identity = Permutation.identity(self.size())
        for k in range(1, 1000):
            if current.equals(identity):
                return k
            current = current.compose(self)
        return -1

    def equals(self, other: "Permutation") -> bool:
        return self.mapping == other.mapping

    def to_cycle_notation(self) -> str:
        visited = set()
        cycles = []
        for i in range(self.size()):
            if i in visited:
                continue
            cycle = []
            j = i
            while j not in visited:
                visited.add(j)
                cycle.append(j)
                j = self.mapping[j]
            if len(cycle) > 1:
                cycles.append("(" + " ".join(str(c) for c in cycle) + ")")
        return "".join(cycles) if cycles else "()"

    @staticmethod
    def identity(n: int) -> "Permutation":
        return Permutation(list(range(n)))

    def __repr__(self) -> str:
        return f"Perm({self.mapping})"

    def __eq__(self, other) -> bool:
        return isinstance(other, Permutation) and self.mapping == other.mapping

    def __hash__(self) -> int:
        return hash(tuple(self.mapping))


# ============================================================================
# Graph structures
# ============================================================================

class GraphBuilder:
    """Builds various graph structures."""

    @staticmethod
    def cycle(n: int) -> dict:
        """Cycle graph C_n: n nodes in a cycle."""
        if n < 3:
            raise ValueError(f"Cycle graph needs n >= 3, got {n}")
        nodes = []
        edges = []
        # Place nodes on a circle
        cx, cy = 640, 360
        radius = min(200, 50 * n)
        for i in range(n):
            angle = -math.pi / 2 + 2 * math.pi * i / n
            x = int(cx + radius * math.cos(angle))
            y = int(cy + radius * math.sin(angle))
            nodes.append({
                "id": i,
                "color": "gold",
                "position": [x, y],
                "label": chr(65 + i) if i < 26 else f"N{i}"
            })
        for i in range(n):
            edges.append({
                "from": i,
                "to": (i + 1) % n,
                "type": "standard",
                "weight": 1
            })
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def directed_cycle(n: int) -> dict:
        """Directed cycle graph: n nodes in a directed cycle."""
        if n < 3:
            raise ValueError(f"Directed cycle needs n >= 3, got {n}")
        graph = GraphBuilder.cycle(n)
        for edge in graph["edges"]:
            edge["directed"] = True
        return graph

    @staticmethod
    def path(n: int) -> dict:
        """Path graph P_n: n nodes in a line."""
        if n < 2:
            raise ValueError(f"Path graph needs n >= 2, got {n}")
        nodes = []
        edges = []
        x_start = 200
        x_step = min(200, 800 // (n - 1)) if n > 1 else 0
        for i in range(n):
            nodes.append({
                "id": i,
                "color": "blue",
                "position": [x_start + x_step * i, 360],
                "label": chr(65 + i) if i < 26 else f"N{i}"
            })
        for i in range(n - 1):
            edges.append({
                "from": i,
                "to": i + 1,
                "type": "standard",
                "weight": 1
            })
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def complete(n: int) -> dict:
        """Complete graph K_n: every pair connected."""
        if n < 2:
            raise ValueError(f"Complete graph needs n >= 2, got {n}")
        nodes = []
        edges = []
        cx, cy = 640, 360
        radius = min(200, 50 * n)
        for i in range(n):
            angle = -math.pi / 2 + 2 * math.pi * i / n
            x = int(cx + radius * math.cos(angle))
            y = int(cy + radius * math.sin(angle))
            nodes.append({
                "id": i,
                "color": "red",
                "position": [x, y],
                "label": chr(65 + i) if i < 26 else f"N{i}"
            })
        for i in range(n):
            for j in range(i + 1, n):
                edges.append({
                    "from": i,
                    "to": j,
                    "type": "standard",
                    "weight": 1
                })
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def bipartite(m: int, n: int) -> dict:
        """Complete bipartite graph K_{m,n}."""
        if m < 1 or n < 1:
            raise ValueError(f"Bipartite graph needs m >= 1, n >= 1, got m={m}, n={n}")
        nodes = []
        edges = []
        total = m + n
        # Top row (group 1)
        x_step_top = 800 // (m + 1)
        for i in range(m):
            nodes.append({
                "id": i,
                "color": "cyan",
                "position": [200 + x_step_top * (i + 1) - x_step_top, 240],
                "label": chr(65 + i) if i < 26 else f"A{i}"
            })
        # Bottom row (group 2)
        x_step_bot = 800 // (n + 1)
        for j in range(n):
            nodes.append({
                "id": m + j,
                "color": "purple",
                "position": [200 + x_step_bot * (j + 1) - x_step_bot, 480],
                "label": chr(65 + m + j) if m + j < 26 else f"B{j}"
            })
        # All edges between groups
        for i in range(m):
            for j in range(n):
                edges.append({
                    "from": i,
                    "to": m + j,
                    "type": "standard",
                    "weight": 1
                })
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def prism(n: int) -> dict:
        """Prism graph: two copies of C_n connected by vertical edges."""
        if n < 3:
            raise ValueError(f"Prism graph needs n >= 3, got {n}")
        nodes = []
        edges = []
        cx, cy_top, cy_bot = 640, 240, 480
        radius = min(160, 40 * n)
        # Top ring
        for i in range(n):
            angle = -math.pi / 2 + 2 * math.pi * i / n
            x = int(cx + radius * math.cos(angle))
            y = int(cy_top + radius * math.sin(angle) * 0.6)
            nodes.append({
                "id": i,
                "color": "cyan",
                "position": [x, y],
                "label": f"{chr(65 + i)}0" if i < 26 else f"T{i}"
            })
        # Bottom ring
        for i in range(n):
            angle = -math.pi / 2 + 2 * math.pi * i / n
            x = int(cx + radius * math.cos(angle))
            y = int(cy_bot + radius * math.sin(angle) * 0.6)
            nodes.append({
                "id": n + i,
                "color": "purple",
                "position": [x, y],
                "label": f"{chr(65 + i)}1" if i < 26 else f"B{i}"
            })
        # Top ring edges
        for i in range(n):
            edges.append({
                "from": i,
                "to": (i + 1) % n,
                "type": "standard",
                "weight": 1
            })
        # Bottom ring edges
        for i in range(n):
            edges.append({
                "from": n + i,
                "to": n + (i + 1) % n,
                "type": "standard",
                "weight": 1
            })
        # Vertical edges
        for i in range(n):
            edges.append({
                "from": i,
                "to": n + i,
                "type": "thick",
                "weight": 1
            })
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def wheel(n: int) -> dict:
        """Wheel graph W_n: cycle of n nodes + central hub."""
        if n < 3:
            raise ValueError(f"Wheel graph needs n >= 3, got {n}")
        nodes = []
        edges = []
        cx, cy = 640, 360
        radius = min(200, 50 * n)
        # Hub
        nodes.append({
            "id": 0,
            "color": "gold",
            "position": [cx, cy],
            "label": "H"
        })
        # Rim nodes
        for i in range(n):
            angle = -math.pi / 2 + 2 * math.pi * i / n
            x = int(cx + radius * math.cos(angle))
            y = int(cy + radius * math.sin(angle))
            nodes.append({
                "id": i + 1,
                "color": "blue",
                "position": [x, y],
                "label": chr(65 + i) if i < 26 else f"R{i}"
            })
        # Rim edges
        for i in range(n):
            edges.append({
                "from": i + 1,
                "to": ((i + 1) % n) + 1,
                "type": "standard",
                "weight": 1
            })
        # Spoke edges
        for i in range(n):
            edges.append({
                "from": 0,
                "to": i + 1,
                "type": "thick",
                "weight": 1
            })
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def petersen() -> dict:
        """Petersen graph: 10 nodes, 15 edges. Famous non-planar graph."""
        nodes = []
        cx, cy = 640, 360
        outer_r = 220
        inner_r = 100
        # Outer pentagon (0-4)
        for i in range(5):
            angle = -math.pi / 2 + 2 * math.pi * i / 5
            x = int(cx + outer_r * math.cos(angle))
            y = int(cy + outer_r * math.sin(angle))
            nodes.append({
                "id": i,
                "color": "green",
                "position": [x, y],
                "label": chr(65 + i)
            })
        # Inner pentagram (5-9)
        for i in range(5):
            angle = -math.pi / 2 + 2 * math.pi * i / 5
            x = int(cx + inner_r * math.cos(angle))
            y = int(cy + inner_r * math.sin(angle))
            nodes.append({
                "id": 5 + i,
                "color": "green",
                "position": [x, y],
                "label": chr(70 + i)
            })
        edges = []
        # Outer cycle
        for i in range(5):
            edges.append({"from": i, "to": (i + 1) % 5, "type": "standard", "weight": 1})
        # Inner pentagram
        for i in range(5):
            edges.append({"from": 5 + i, "to": 5 + (i + 2) % 5, "type": "standard", "weight": 1})
        # Spokes
        for i in range(5):
            edges.append({"from": i, "to": 5 + i, "type": "thick", "weight": 1})
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def tetrahedron() -> dict:
        """Tetrahedron graph K4 with uniform colors."""
        return GraphBuilder.complete(4)

    @staticmethod
    def cube() -> dict:
        """Cube graph: 8 nodes, 12 edges."""
        nodes = [
            {"id": 0, "color": "blue", "position": [480, 240], "label": "A"},
            {"id": 1, "color": "blue", "position": [720, 240], "label": "B"},
            {"id": 2, "color": "blue", "position": [720, 420], "label": "C"},
            {"id": 3, "color": "blue", "position": [480, 420], "label": "D"},
            {"id": 4, "color": "blue", "position": [540, 180], "label": "E"},
            {"id": 5, "color": "blue", "position": [780, 180], "label": "F"},
            {"id": 6, "color": "blue", "position": [780, 360], "label": "G"},
            {"id": 7, "color": "blue", "position": [540, 360], "label": "H"},
        ]
        edges = [
            # Front face
            {"from": 0, "to": 1, "type": "standard", "weight": 1},
            {"from": 1, "to": 2, "type": "standard", "weight": 1},
            {"from": 2, "to": 3, "type": "standard", "weight": 1},
            {"from": 3, "to": 0, "type": "standard", "weight": 1},
            # Back face
            {"from": 4, "to": 5, "type": "standard", "weight": 1},
            {"from": 5, "to": 6, "type": "standard", "weight": 1},
            {"from": 6, "to": 7, "type": "standard", "weight": 1},
            {"from": 7, "to": 4, "type": "standard", "weight": 1},
            # Connecting edges
            {"from": 0, "to": 4, "type": "standard", "weight": 1},
            {"from": 1, "to": 5, "type": "standard", "weight": 1},
            {"from": 2, "to": 6, "type": "standard", "weight": 1},
            {"from": 3, "to": 7, "type": "standard", "weight": 1},
        ]
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def octahedron() -> dict:
        """Octahedron graph: 6 nodes, 12 edges."""
        nodes = [
            {"id": 0, "color": "red", "position": [640, 160], "label": "T"},   # top
            {"id": 1, "color": "red", "position": [440, 320], "label": "L"},   # left
            {"id": 2, "color": "red", "position": [640, 280], "label": "F"},   # front
            {"id": 3, "color": "red", "position": [840, 320], "label": "R"},   # right
            {"id": 4, "color": "red", "position": [640, 440], "label": "K"},   # back
            {"id": 5, "color": "red", "position": [640, 560], "label": "B"},   # bottom
        ]
        # Each vertex connects to all except its opposite
        adj = [
            (0, 1), (0, 2), (0, 3), (0, 4),  # top connects to equator
            (5, 1), (5, 2), (5, 3), (5, 4),  # bottom connects to equator
            (1, 2), (2, 3), (3, 4), (4, 1),  # equator cycle
        ]
        edges = [{"from": a, "to": b, "type": "standard", "weight": 1} for a, b in adj]
        return {"nodes": nodes, "edges": edges}

    @staticmethod
    def star(n: int) -> dict:
        """Star graph S_n: central node connected to n leaves (= K_{1,n})."""
        return GraphBuilder.bipartite(1, n)


# Registry of available graphs
GRAPH_REGISTRY: dict[str, dict] = {}


def _build_graph_registry():
    """Build the registry of available graph constructors."""
    registry = {}

    # Parameterized graphs: name_N format
    for n in range(3, 13):
        registry[f"cycle_{n}"] = ("cycle", n)
    for n in range(2, 13):
        registry[f"path_{n}"] = ("path", n)
    for n in range(3, 13):
        registry[f"directed_cycle_{n}"] = ("directed_cycle", n)
    for n in range(2, 8):
        registry[f"complete_{n}"] = ("complete", n)
    for n in range(3, 9):
        registry[f"prism_{n}"] = ("prism", n)
    for n in range(3, 9):
        registry[f"wheel_{n}"] = ("wheel", n)
    for n in range(3, 9):
        registry[f"star_{n}"] = ("star", n)
    # Bipartite K_{m,n}
    for m in range(1, 6):
        for n in range(m, 6):
            registry[f"bipartite_{m}_{n}"] = ("bipartite", m, n)

    # Named graphs
    registry["petersen"] = ("petersen",)
    registry["tetrahedron"] = ("tetrahedron",)
    registry["cube"] = ("cube",)
    registry["octahedron"] = ("octahedron",)

    return registry


def build_graph(graph_name: str) -> dict:
    """Build a graph by name from the registry."""
    registry = _build_graph_registry()
    if graph_name not in registry:
        raise ValueError(
            f"Unknown graph: '{graph_name}'. Use --list-graphs to see available graphs."
        )
    spec = registry[graph_name]
    method_name = spec[0]
    args = spec[1:]
    method = getattr(GraphBuilder, method_name)
    return method(*args)


# ============================================================================
# Automorphism computation
# ============================================================================

class AutomorphismFinder:
    """Computes graph automorphisms via brute force or structured methods."""

    @staticmethod
    def find_all(graph: dict) -> list[Permutation]:
        """Find all automorphisms of the given graph.
        Uses brute-force for small graphs, pruned search for larger ones."""
        nodes = graph["nodes"]
        edges = graph["edges"]
        n = len(nodes)

        if n > 12:
            print(f"WARNING: Graph has {n} nodes. Brute-force automorphism search "
                  f"may be very slow (n! = {math.factorial(n)}).", file=sys.stderr)

        # Build adjacency with edge types for fast lookup
        adj: dict[tuple[int, int], str] = {}
        directed_edges: set[tuple[int, int]] = set()
        for e in edges:
            a, b = e["from"], e["to"]
            etype = e.get("type", "standard")
            is_directed = e.get("directed", False)
            adj[(a, b)] = etype
            if is_directed:
                directed_edges.add((a, b))
            else:
                adj[(b, a)] = etype

        # Node colors
        colors = [nodes[i]["color"] for i in range(n)]

        # Group nodes by color for pruning
        color_groups: dict[str, list[int]] = {}
        for i in range(n):
            c = colors[i]
            if c not in color_groups:
                color_groups[c] = []
            color_groups[c].append(i)

        # Node degree (considering edge types)
        def node_signature(i: int) -> tuple:
            """Compute a signature for node i that automorphisms must preserve."""
            incident = []
            for (a, b), etype in adj.items():
                if a == i:
                    incident.append(("out" if (a, b) in directed_edges else "und", etype, colors[b]))
                elif b == i and (a, b) not in directed_edges:
                    pass  # undirected already counted
            incident.sort()
            return (colors[i], tuple(incident))

        # Group nodes by signature
        sig_groups: dict[tuple, list[int]] = {}
        for i in range(n):
            sig = node_signature(i)
            if sig not in sig_groups:
                sig_groups[sig] = []
            sig_groups[sig].append(i)

        # Build candidates: node i can only map to nodes with same signature
        candidates: list[list[int]] = [[] for _ in range(n)]
        for sig, group in sig_groups.items():
            for i in group:
                candidates[i] = list(group)

        result: list[Permutation] = []

        def check_perm(mapping: list[int]) -> bool:
            """Check if a complete mapping is an automorphism."""
            for (a, b), etype in adj.items():
                ma, mb = mapping[a], mapping[b]
                if (ma, mb) not in adj:
                    return False
                if adj[(ma, mb)] != etype:
                    return False
                # Check directedness
                if (a, b) in directed_edges:
                    if (ma, mb) not in directed_edges:
                        return False
            return True

        def backtrack(mapping: list[int], used: set[int], depth: int):
            """Backtracking search with pruning."""
            if depth == n:
                if check_perm(mapping):
                    result.append(Permutation(list(mapping)))
                return

            for target in candidates[depth]:
                if target in used:
                    continue
                # Quick edge check: verify edges from depth to already-assigned nodes
                ok = True
                for prev in range(depth):
                    has_orig = (depth, prev) in adj or (prev, depth) in adj
                    has_mapped = (target, mapping[prev]) in adj or (mapping[prev], target) in adj
                    if has_orig != has_mapped:
                        ok = False
                        break
                    if has_orig:
                        # Check edge type
                        if (depth, prev) in adj:
                            orig_type = adj[(depth, prev)]
                            if (target, mapping[prev]) in adj:
                                if adj[(target, mapping[prev])] != orig_type:
                                    ok = False
                                    break
                            elif (mapping[prev], target) in adj:
                                if adj[(mapping[prev], target)] != orig_type:
                                    ok = False
                                    break
                        elif (prev, depth) in adj:
                            orig_type = adj[(prev, depth)]
                            if (mapping[prev], target) in adj:
                                if adj[(mapping[prev], target)] != orig_type:
                                    ok = False
                                    break
                            elif (target, mapping[prev]) in adj:
                                if adj[(target, mapping[prev])] != orig_type:
                                    ok = False
                                    break
                if not ok:
                    continue
                mapping[depth] = target
                used.add(target)
                backtrack(mapping, used, depth + 1)
                used.remove(target)

        mapping = [0] * n
        backtrack(mapping, set(), 0)
        return result


# ============================================================================
# Group generators (abstract groups, independent of graphs)
# ============================================================================

class GroupGenerator:
    """Generate well-known groups as sets of permutations."""

    @staticmethod
    def cyclic(n: int) -> list[Permutation]:
        """Cyclic group Z_n as rotations of n elements."""
        perms = []
        for k in range(n):
            mapping = [(i + k) % n for i in range(n)]
            perms.append(Permutation(mapping))
        return perms

    @staticmethod
    def dihedral(n: int) -> list[Permutation]:
        """Dihedral group D_n (symmetries of regular n-gon).
        Order = 2n. Contains n rotations and n reflections."""
        perms = []
        # Rotations
        for k in range(n):
            mapping = [(i + k) % n for i in range(n)]
            perms.append(Permutation(mapping))
        # Reflections: reflect then rotate
        for k in range(n):
            mapping = [(n - i + k) % n for i in range(n)]
            perms.append(Permutation(mapping))
        return perms

    @staticmethod
    def symmetric(n: int) -> list[Permutation]:
        """Symmetric group S_n: all permutations of n elements.
        Order = n!"""
        if n > 7:
            raise ValueError(f"S_{n} has {math.factorial(n)} elements, too large")
        return [Permutation(list(p)) for p in itertools.permutations(range(n))]

    @staticmethod
    def alternating(n: int) -> list[Permutation]:
        """Alternating group A_n: even permutations of n elements.
        Order = n!/2"""
        if n > 7:
            raise ValueError(f"A_{n} has {math.factorial(n) // 2} elements, too large")
        result = []
        for p_tuple in itertools.permutations(range(n)):
            p = Permutation(list(p_tuple))
            if _perm_sign(p) == 1:
                result.append(p)
        return result

    @staticmethod
    def klein_four() -> list[Permutation]:
        """Klein four-group V4 (Z2 x Z2) on 4 elements."""
        return [
            Permutation([0, 1, 2, 3]),  # e
            Permutation([1, 0, 3, 2]),  # (01)(23)
            Permutation([2, 3, 0, 1]),  # (02)(13)
            Permutation([3, 2, 1, 0]),  # (03)(12)
        ]


def _perm_sign(p: Permutation) -> int:
    """Compute the sign (parity) of a permutation. +1 for even, -1 for odd."""
    n = p.size()
    visited = [False] * n
    sign = 1
    for i in range(n):
        if visited[i]:
            continue
        cycle_len = 0
        j = i
        while not visited[j]:
            visited[j] = True
            j = p.apply(j)
            cycle_len += 1
        if cycle_len > 1:
            sign *= (-1) ** (cycle_len - 1)
    return sign


# Registry of available groups
GROUP_REGISTRY: dict[str, tuple[str, ...]] = {}


def _build_group_registry():
    """Build the registry of available group names."""
    registry = {}
    for n in range(2, 13):
        registry[f"Z{n}"] = ("cyclic", n)
    for n in range(3, 9):
        registry[f"D{n}"] = ("dihedral", n)
    for n in range(2, 7):
        registry[f"S{n}"] = ("symmetric", n)
    for n in range(3, 7):
        registry[f"A{n}"] = ("alternating", n)
    registry["V4"] = ("klein_four",)
    return registry


def generate_group(group_name: str) -> list[Permutation]:
    """Generate a group by name."""
    registry = _build_group_registry()
    if group_name not in registry:
        raise ValueError(
            f"Unknown group: '{group_name}'. Use --list-groups to see available groups."
        )
    spec = registry[group_name]
    method_name = spec[0]
    args = spec[1:]
    method = getattr(GroupGenerator, method_name)
    return method(*args)


# ============================================================================
# Cayley table computation
# ============================================================================

def compute_cayley_table(
    perms: list[Permutation],
    ids: list[str]
) -> dict[str, dict[str, str]]:
    """Compute the Cayley table for a list of permutations.

    Convention: Cayley[row][col] = product where product = col.compose(row).
    This matches the game's convention.
    """
    assert len(perms) == len(ids)
    perm_to_id: dict[tuple[int, ...], str] = {}
    for p, pid in zip(perms, ids):
        perm_to_id[tuple(p.mapping)] = pid

    table: dict[str, dict[str, str]] = {}
    for i, (row_p, row_id) in enumerate(zip(perms, ids)):
        row: dict[str, str] = {}
        for j, (col_p, col_id) in enumerate(zip(perms, ids)):
            product = col_p.compose(row_p)
            product_key = tuple(product.mapping)
            if product_key not in perm_to_id:
                raise ValueError(
                    f"Cayley table: {row_id} * {col_id} = {product.mapping} "
                    f"not in the group (not closed!)"
                )
            row[col_id] = perm_to_id[product_key]
        table[row_id] = row
    return table


# ============================================================================
# Subgroup finding
# ============================================================================

def find_all_subgroups(
    perms: list[Permutation],
    ids: list[str]
) -> list[dict]:
    """Find all subgroups of the given group.
    Returns a list of subgroup dicts suitable for level JSON."""
    n = len(perms)
    perm_set = {tuple(p.mapping) for p in perms}

    # Map from mapping tuple to id
    mapping_to_id: dict[tuple[int, ...], str] = {}
    for p, pid in zip(perms, ids):
        mapping_to_id[tuple(p.mapping)] = pid

    subgroups: list[set[int]] = []

    # Check all subsets (only feasible for small groups)
    if n > 16:
        # For large groups, only find subgroups generated by single elements
        # and pairs of elements
        subgroups = _find_subgroups_by_generation(perms)
    else:
        # Check all subsets whose size divides the group order (Lagrange's theorem)
        for size in range(1, n + 1):
            if n % size != 0:
                continue
            for subset_indices in itertools.combinations(range(n), size):
                subset = [perms[i] for i in subset_indices]
                if _is_subgroup(subset, perm_set):
                    subgroups.append(set(subset_indices))

    # Deduplicate
    unique: list[set[int]] = []
    for sg in subgroups:
        if sg not in unique:
            unique.append(sg)

    # Convert to JSON format
    result = []
    for sg_indices in sorted(unique, key=lambda s: len(s)):
        elements = [ids[i] for i in sorted(sg_indices)]
        order = len(elements)
        is_normal = _is_normal_subgroup(
            [perms[i] for i in sg_indices], perms, perm_set
        )
        sg_dict = {
            "name": _subgroup_name(elements, ids, perms),
            "order": order,
            "elements": elements,
            "is_normal": is_normal,
            "is_inner_door": order > 1 and order < n,
            "description": f"Subgroup of order {order}",
            "lattice_level": _lattice_level(order, n)
        }
        result.append(sg_dict)

    return result


def _is_subgroup(subset: list[Permutation], full_set: set[tuple[int, ...]]) -> bool:
    """Check if subset forms a subgroup (closed, identity, inverses)."""
    subset_set = {tuple(p.mapping) for p in subset}

    # Must contain identity
    n = subset[0].size()
    identity = tuple(range(n))
    if identity not in subset_set:
        return False

    # Closure
    for a in subset:
        for b in subset:
            prod = tuple(a.compose(b).mapping)
            if prod not in subset_set:
                return False

    # Inverses
    for p in subset:
        inv = tuple(p.inverse().mapping)
        if inv not in subset_set:
            return False

    return True


def _is_normal_subgroup(
    subgroup: list[Permutation],
    full_group: list[Permutation],
    full_set: set[tuple[int, ...]]
) -> bool:
    """Check if subgroup is normal: gHg^{-1} = H for all g."""
    sg_set = {tuple(p.mapping) for p in subgroup}
    for g in full_group:
        g_inv = g.inverse()
        for h in subgroup:
            conjugate = g.compose(h).compose(g_inv)
            if tuple(conjugate.mapping) not in sg_set:
                return False
    return True


def _find_subgroups_by_generation(perms: list[Permutation]) -> list[set[int]]:
    """Find subgroups by generating from single elements and pairs."""
    n = len(perms)
    perm_set = {tuple(p.mapping): i for i, p in enumerate(perms)}
    subgroups: list[set[int]] = []

    # Trivial subgroup
    identity_idx = None
    for i, p in enumerate(perms):
        if p.is_identity():
            identity_idx = i
            break
    if identity_idx is not None:
        subgroups.append({identity_idx})

    # Full group
    subgroups.append(set(range(n)))

    # Subgroups generated by single elements
    for i in range(n):
        sg = _generate_subgroup([perms[i]], perm_set)
        if sg is not None:
            subgroups.append(sg)

    # Subgroups generated by pairs
    for i in range(n):
        for j in range(i + 1, n):
            sg = _generate_subgroup([perms[i], perms[j]], perm_set)
            if sg is not None:
                subgroups.append(sg)

    return subgroups


def _generate_subgroup(
    generators: list[Permutation],
    perm_set: dict[tuple[int, ...], int]
) -> Optional[set[int]]:
    """Generate a subgroup from the given generators."""
    current: set[tuple[int, ...]] = set()
    queue = list(generators)

    while queue:
        p = queue.pop()
        key = tuple(p.mapping)
        if key in current:
            continue
        if key not in perm_set:
            return None  # Not in the group
        current.add(key)
        # Multiply with everything in current
        for existing in list(current):
            ep = Permutation(list(existing))
            # p * existing
            prod1 = p.compose(ep)
            k1 = tuple(prod1.mapping)
            if k1 not in current and k1 in perm_set:
                queue.append(prod1)
            # existing * p
            prod2 = ep.compose(p)
            k2 = tuple(prod2.mapping)
            if k2 not in current and k2 in perm_set:
                queue.append(prod2)
            # inverse of p
            inv = p.inverse()
            ki = tuple(inv.mapping)
            if ki not in current and ki in perm_set:
                queue.append(inv)

    return {perm_set[k] for k in current}


def _subgroup_name(elements: list[str], all_ids: list[str], all_perms: list[Permutation]) -> str:
    """Generate a reasonable name for a subgroup."""
    n = len(all_ids)
    order = len(elements)
    if order == 1:
        return "Trivial"
    if order == n:
        return "Full_group"
    # Check if it's a cyclic subgroup
    if order == 2:
        return f"Z2_{elements[1]}"
    if order <= n // 2:
        return f"Subgroup_order_{order}"
    return f"Subgroup_order_{order}"


def _lattice_level(order: int, total: int) -> int:
    """Assign a lattice level based on subgroup size."""
    if order == 1:
        return 0
    if order == total:
        return 3
    if order <= total // 4:
        return 1
    return 2


# ============================================================================
# Automorphism ID and name generation
# ============================================================================

def assign_ids_and_names(
    perms: list[Permutation],
    group_name: str
) -> list[dict]:
    """Assign IDs, names, and descriptions to automorphisms."""
    n = perms[0].size()
    result = []

    for i, p in enumerate(perms):
        if p.is_identity():
            auto = {
                "id": "e",
                "mapping": p.mapping,
                "name": "Тождество",
                "description": "Всё остаётся на месте"
            }
        else:
            ord_p = p.order()
            cycle_str = p.to_cycle_notation()

            # Try to give a meaningful name
            if group_name.startswith("Z") or group_name.startswith("D"):
                # Rotation-style naming
                if _is_rotation_like(p, n):
                    k = _rotation_amount(p, n)
                    if k is not None:
                        angle = 360 * k // n
                        auto = {
                            "id": f"r{k}",
                            "mapping": p.mapping,
                            "name": f"Поворот на {angle}°",
                            "description": f"Циклический сдвиг на {k} (порядок {ord_p})"
                        }
                    else:
                        auto = {
                            "id": f"s{i}",
                            "mapping": p.mapping,
                            "name": f"Отражение {cycle_str}",
                            "description": f"Отражение (порядок {ord_p})"
                        }
                else:
                    auto = {
                        "id": f"s{i - n}" if i >= n else f"g{i}",
                        "mapping": p.mapping,
                        "name": f"Отражение {cycle_str}",
                        "description": f"Отражение (порядок {ord_p})"
                    }
            elif group_name.startswith("S") or group_name.startswith("A"):
                auto = {
                    "id": f"p{i}",
                    "mapping": p.mapping,
                    "name": f"Перестановка {cycle_str}",
                    "description": f"Порядок {ord_p}"
                }
            else:
                auto = {
                    "id": f"g{i}",
                    "mapping": p.mapping,
                    "name": f"Элемент {cycle_str}",
                    "description": f"Порядок {ord_p}"
                }
        result.append(auto)

    # Ensure unique IDs
    seen_ids: set[str] = set()
    for auto in result:
        if auto["id"] in seen_ids:
            # Make unique by appending index
            orig_id = auto["id"]
            counter = 2
            while f"{orig_id}_{counter}" in seen_ids:
                counter += 1
            auto["id"] = f"{orig_id}_{counter}"
        seen_ids.add(auto["id"])

    return result


def _is_rotation_like(p: Permutation, n: int) -> bool:
    """Check if permutation is a cyclic rotation of [0..n-1]."""
    if p.size() != n:
        return False
    offset = p.apply(0)
    return all(p.apply(i) == (i + offset) % n for i in range(n))


def _rotation_amount(p: Permutation, n: int) -> Optional[int]:
    """If p is a rotation of [0..n-1], return the rotation amount."""
    offset = p.apply(0)
    if all(p.apply(i) == (i + offset) % n for i in range(n)):
        return offset
    return None


def find_generators(perms: list[Permutation], ids: list[str]) -> list[str]:
    """Find a minimal set of generators for the group."""
    n = len(perms)
    perm_set = {tuple(p.mapping) for p in perms}
    perm_id_map = {tuple(p.mapping): pid for p, pid in zip(perms, ids)}

    # Try single generators first
    for i, p in enumerate(perms):
        if p.is_identity():
            continue
        generated = _generate_from([p], perms[0].size())
        if generated == perm_set:
            return [ids[i]]

    # Try pairs
    for i in range(n):
        if perms[i].is_identity():
            continue
        for j in range(i + 1, n):
            if perms[j].is_identity():
                continue
            generated = _generate_from([perms[i], perms[j]], perms[0].size())
            if generated == perm_set:
                return [ids[i], ids[j]]

    # Try triples (fallback)
    for i in range(n):
        if perms[i].is_identity():
            continue
        for j in range(i + 1, n):
            if perms[j].is_identity():
                continue
            for k in range(j + 1, n):
                if perms[k].is_identity():
                    continue
                generated = _generate_from(
                    [perms[i], perms[j], perms[k]], perms[0].size()
                )
                if generated == perm_set:
                    return [ids[i], ids[j], ids[k]]

    # Fallback: return all non-identity elements
    return [pid for p, pid in zip(perms, ids) if not p.is_identity()]


def _generate_from(generators: list[Permutation], size: int) -> set[tuple[int, ...]]:
    """Generate the group from given generators."""
    generated: set[tuple[int, ...]] = set()
    queue = [Permutation.identity(size)] + list(generators)

    while queue:
        p = queue.pop()
        key = tuple(p.mapping)
        if key in generated:
            continue
        generated.add(key)
        for g in generators:
            prod1 = p.compose(g)
            if tuple(prod1.mapping) not in generated:
                queue.append(prod1)
            prod2 = g.compose(p)
            if tuple(prod2.mapping) not in generated:
                queue.append(prod2)

    return generated


# ============================================================================
# Level validation
# ============================================================================

def validate_level(data: dict) -> list[str]:
    """Validate a level JSON structure. Returns list of warning/error messages."""
    warnings = []

    # 1. Structure check
    required_top = {"meta", "graph", "symmetries", "mechanics", "visuals", "hints", "echo_hints"}
    missing_top = required_top - set(data.keys())
    if missing_top:
        warnings.append(f"ERROR: Missing top-level keys: {missing_top}")

    # 2. Meta check
    meta = data.get("meta", {})
    required_meta = {"id", "act", "level", "title", "subtitle", "group_name", "group_order"}
    missing_meta = required_meta - set(meta.keys())
    if missing_meta:
        warnings.append(f"ERROR: Missing meta keys: {missing_meta}")

    group_order = meta.get("group_order", 0)

    # 3. Graph check
    graph = data.get("graph", {})
    nodes = graph.get("nodes", [])
    edges = graph.get("edges", [])
    n = len(nodes)

    if n == 0:
        warnings.append("ERROR: Graph has no nodes")
    else:
        # Check node IDs sequential
        node_ids = sorted([node["id"] for node in nodes])
        if node_ids != list(range(n)):
            warnings.append(f"ERROR: Node IDs {node_ids} should be [0..{n - 1}]")

        # Check required node fields
        for i, node in enumerate(nodes):
            for field in ["id", "color", "position", "label"]:
                if field not in node:
                    warnings.append(f"ERROR: Node {i} missing '{field}'")

    if len(edges) == 0:
        warnings.append("WARNING: Graph has no edges")
    else:
        for i, edge in enumerate(edges):
            for field in ["from", "to", "type", "weight"]:
                if field not in edge:
                    warnings.append(f"ERROR: Edge {i} missing '{field}'")
            if edge.get("from", -1) >= n or edge.get("to", -1) >= n:
                warnings.append(f"ERROR: Edge {i} references invalid node")

    # Check connectivity
    if n > 0 and edges:
        adj_list: dict[int, set[int]] = {i: set() for i in range(n)}
        for e in edges:
            a, b = e["from"], e["to"]
            adj_list[a].add(b)
            if not e.get("directed", False):
                adj_list[b].add(a)
        visited: set[int] = set()
        queue = [0]
        while queue:
            node = queue.pop()
            if node in visited:
                continue
            visited.add(node)
            for neighbor in adj_list[node]:
                if neighbor not in visited:
                    queue.append(neighbor)
        if len(visited) != n:
            warnings.append(f"WARNING: Graph is not connected! "
                            f"Reached {len(visited)}/{n} nodes")

    # 4. Symmetries check
    sym = data.get("symmetries", {})
    autos = sym.get("automorphisms", [])
    actual_count = len(autos)

    if actual_count != group_order:
        warnings.append(f"ERROR: {actual_count} automorphisms listed, "
                        f"but group_order={group_order}")

    # Check valid permutations
    for auto in autos:
        mapping = auto.get("mapping", [])
        if sorted(mapping) != list(range(n)):
            warnings.append(f"ERROR: Auto '{auto.get('id', '?')}' mapping "
                            f"{mapping} is not a valid permutation")

    # Check identity present
    identity = list(range(n))
    if not any(auto.get("mapping") == identity for auto in autos):
        warnings.append("ERROR: Identity permutation not found in automorphisms")

    # Check uniqueness
    mappings = [tuple(auto.get("mapping", [])) for auto in autos]
    if len(set(mappings)) != len(mappings):
        warnings.append("ERROR: Duplicate automorphism mappings found")

    auto_ids = [auto.get("id", "") for auto in autos]
    if len(set(auto_ids)) != len(auto_ids):
        warnings.append("ERROR: Duplicate automorphism IDs found")

    # Check closure
    if actual_count > 0 and actual_count <= 100:
        perms = [Permutation(auto["mapping"]) for auto in autos]
        perm_set = {tuple(p.mapping) for p in perms}
        closed = True
        for a in perms:
            for b in perms:
                prod = tuple(a.compose(b).mapping)
                if prod not in perm_set:
                    closed = False
                    break
            if not closed:
                break
        if not closed:
            warnings.append("WARNING: Automorphisms are NOT closed under composition")

    # Check generators
    generators = sym.get("generators", [])
    for gen_id in generators:
        if gen_id not in auto_ids:
            warnings.append(f"ERROR: Generator '{gen_id}' not in automorphisms")

    # 5. Check automorphisms are actual graph automorphisms (uniform color only)
    if n > 0 and autos:
        colors = {node["color"] for node in nodes}
        if len(colors) == 1:  # Uniform color
            adj_set: set[tuple[int, int, str]] = set()
            for e in edges:
                a, b, t = e["from"], e["to"], e.get("type", "standard")
                adj_set.add((a, b, t))
                if not e.get("directed", False):
                    adj_set.add((b, a, t))

            for auto in autos:
                mapping = auto["mapping"]
                is_graph_auto = True
                for e in edges:
                    ma = mapping[e["from"]]
                    mb = mapping[e["to"]]
                    t = e.get("type", "standard")
                    if (ma, mb, t) not in adj_set and (mb, ma, t) not in adj_set:
                        is_graph_auto = False
                        break
                if not is_graph_auto:
                    warnings.append(
                        f"WARNING: Auto '{auto['id']}' is NOT a graph automorphism "
                        f"(uniform-color graph)")

    # 6. Size warnings
    if group_order > 48:
        warnings.append(f"WARNING: Very large group order ({group_order}). "
                        f"May be too complex for gameplay.")
    if group_order < 2:
        warnings.append(f"WARNING: Very small group order ({group_order}). "
                        f"May be too simple for gameplay.")

    return warnings


# ============================================================================
# Level JSON generation
# ============================================================================

def generate_level(
    group_name: str,
    graph_name: str,
    level_id: int,
    act: int = 1,
    title: Optional[str] = None,
    subtitle: Optional[str] = None,
    auto_group: bool = False,
    include_subgroups: bool = True,
    output_path: Optional[str] = None,
) -> dict:
    """Generate a complete level JSON.

    Args:
        group_name: Name of the group (e.g., "Z5", "D4", "S3")
                   If auto_group is True, this is computed from the graph.
        graph_name: Name of the graph structure (e.g., "cycle_5", "petersen")
        level_id: Level number
        act: Act number (1-4)
        title: Level title (auto-generated if None)
        subtitle: Level subtitle (auto-generated if None)
        auto_group: If True, compute Aut(G) automatically instead of using group_name
        include_subgroups: If True, compute and include subgroups
        output_path: If set, write JSON to this file
    """
    # 1. Build graph
    graph = build_graph(graph_name)
    n = len(graph["nodes"])

    # 2. Get automorphisms
    if auto_group:
        print(f"Computing automorphisms of {graph_name} (n={n})...", file=sys.stderr)
        perms = AutomorphismFinder.find_all(graph)
        if not perms:
            raise ValueError(f"Graph {graph_name} has no automorphisms (impossible)!")
        group_order = len(perms)
        group_name = f"Aut({graph_name})"
        print(f"Found {group_order} automorphisms.", file=sys.stderr)
    else:
        perms = generate_group(group_name)
        group_order = len(perms)

        # Validate: group element size must match graph node count
        if perms[0].size() != n:
            raise ValueError(
                f"Group {group_name} acts on {perms[0].size()} elements, "
                f"but graph {graph_name} has {n} nodes. "
                f"These must match!"
            )

    # 3. Assign IDs and names
    auto_data = assign_ids_and_names(perms, group_name)
    ids = [a["id"] for a in auto_data]

    # 4. Compute Cayley table
    print(f"Computing Cayley table ({group_order}x{group_order})...", file=sys.stderr)
    try:
        cayley = compute_cayley_table(perms, ids)
    except ValueError as e:
        print(f"WARNING: {e}", file=sys.stderr)
        cayley = {}

    # 5. Find generators
    generators = find_generators(perms, ids)

    # 6. Find subgroups
    subgroups = []
    subgroup_lattice = None
    if include_subgroups and group_order <= 48:
        print(f"Finding subgroups...", file=sys.stderr)
        subgroups = find_all_subgroups(perms, ids)
        print(f"Found {len(subgroups)} subgroups.", file=sys.stderr)

        # Build lattice edges
        if subgroups:
            lattice_edges = []
            for i, sg_i in enumerate(subgroups):
                for j, sg_j in enumerate(subgroups):
                    if i == j:
                        continue
                    # sg_i is subgroup of sg_j if sg_i.elements ⊂ sg_j.elements
                    if (set(sg_i["elements"]) < set(sg_j["elements"])
                            and not any(
                                set(sg_i["elements"]) < set(sg_k["elements"]) < set(sg_j["elements"])
                                for k, sg_k in enumerate(subgroups) if k != i and k != j
                            )):
                        lattice_edges.append({
                            "from": sg_i["name"],
                            "to": sg_j["name"]
                        })
            subgroup_lattice = {
                "description": f"Решётка подгрупп {group_name}",
                "edges": lattice_edges
            }

    # 7. Auto-generate title/subtitle
    if title is None:
        title = f"Зал {graph_name}"
    if subtitle is None:
        subtitle = f"Группа {group_name}, порядок {group_order}"

    # 8. Build level JSON
    level = {
        "meta": {
            "id": f"act{act}_level{level_id:02d}",
            "act": act,
            "level": level_id,
            "title": title,
            "subtitle": subtitle,
            "group_name": group_name,
            "group_order": group_order
        },
        "graph": graph,
        "symmetries": {
            "automorphisms": auto_data,
            "generators": generators,
            "cayley_table": cayley if group_order <= 24 else {}
        },
        "mechanics": {
            "allowed_actions": ["swap"],
            "show_cayley_button": group_order <= 12,
            "show_generators_hint": group_order >= 5,
            "inner_doors": [],
            "palette": None
        },
        "visuals": {
            "background_theme": "stone_vault",
            "ambient_particles": "dust_motes",
            "crystal_style": "basic_gem",
            "edge_style": _choose_edge_style(graph)
        },
        "hints": [
            {
                "trigger": "after_30_seconds_no_action",
                "text": f"Граф типа {graph_name} с группой {group_name}. "
                        f"Найдите все {group_order} симметрий!"
            }
        ],
        "echo_hints": [
            {
                "text": f"Группа {group_name} порядка {group_order}. "
                        f"Генераторы: {', '.join(generators)}.",
                "target_crystals": []
            }
        ]
    }

    # Add subgroups if computed
    if subgroups:
        level["subgroups"] = subgroups
        # Mark inner doors for non-trivial proper subgroups
        inner_doors = []
        for sg in subgroups:
            if sg["is_inner_door"]:
                inner_doors.append({
                    "id": f"door_{sg['name']}",
                    "required_subgroup": sg["name"],
                    "visual_hint": f"Дверь для подгруппы {sg['name']} (порядок {sg['order']})",
                    "unlock_message": f"Подгруппа {sg['name']} открыла дверь!",
                    "reward": f"Подгруппа порядка {sg['order']}"
                })
        if inner_doors:
            level["mechanics"]["inner_doors"] = inner_doors

    if subgroup_lattice:
        level["subgroup_lattice"] = subgroup_lattice

    # 9. Validate
    validation_warnings = validate_level(level)
    if validation_warnings:
        print("Validation results:", file=sys.stderr)
        for w in validation_warnings:
            print(f"  {w}", file=sys.stderr)

    # 10. Output
    if output_path:
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(level, f, ensure_ascii=False, indent=2)
        print(f"Level written to: {output_path}", file=sys.stderr)
    else:
        print(json.dumps(level, ensure_ascii=False, indent=2))

    return level


def _choose_edge_style(graph: dict) -> str:
    """Choose edge style based on graph properties."""
    edge_types = {e.get("type", "standard") for e in graph["edges"]}
    has_directed = any(e.get("directed", False) for e in graph["edges"])
    if has_directed:
        return "directed_thread"
    if "thick" in edge_types:
        return "glowing"
    return "thin_thread"


# ============================================================================
# CLI
# ============================================================================

def cmd_list_groups():
    """List all available groups."""
    registry = _build_group_registry()
    print("Available groups:")
    print(f"{'Name':<12} {'Type':<15} {'Order':<8}")
    print("-" * 40)
    for name in sorted(registry.keys()):
        spec = registry[name]
        method_name = spec[0]
        try:
            perms = generate_group(name)
            order = len(perms)
        except ValueError:
            order = "?"
        print(f"{name:<12} {method_name:<15} {order:<8}")


def cmd_list_graphs():
    """List all available graph structures."""
    registry = _build_graph_registry()
    print("Available graphs:")
    print(f"{'Name':<25} {'Type':<18} {'Nodes':<8}")
    print("-" * 55)
    for name in sorted(registry.keys()):
        spec = registry[name]
        method_name = spec[0]
        try:
            graph = build_graph(name)
            nodes = len(graph["nodes"])
        except Exception:
            nodes = "?"
        print(f"{name:<25} {method_name:<18} {nodes:<8}")


def cmd_validate(filepath: str):
    """Validate an existing level JSON file."""
    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)
    warnings = validate_level(data)
    if warnings:
        print(f"Validation of {filepath}:")
        for w in warnings:
            print(f"  {w}")
        errors = [w for w in warnings if w.startswith("ERROR")]
        if errors:
            print(f"\n{len(errors)} error(s), {len(warnings) - len(errors)} warning(s)")
            return 1
        else:
            print(f"\n0 errors, {len(warnings)} warning(s)")
            return 0
    else:
        print(f"Validation of {filepath}: OK (no issues found)")
        return 0


def main():
    _fix_encoding()
    parser = argparse.ArgumentParser(
        description="Level generator for The Symmetry Vaults",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --group Z5 --graph cycle_5 --level-id 25
  %(prog)s --group S3 --graph complete_3 --level-id 26
  %(prog)s --group D4 --graph cycle_4 --level-id 27
  %(prog)s --auto --graph petersen --level-id 28
  %(prog)s --list-groups
  %(prog)s --list-graphs
  %(prog)s --validate data/levels/act1/level_01.json
"""
    )

    parser.add_argument("--group", help="Group name (e.g., Z5, D4, S3, A4)")
    parser.add_argument("--graph", help="Graph structure (e.g., cycle_5, petersen, complete_4)")
    parser.add_argument("--level-id", type=int, help="Level number")
    parser.add_argument("--act", type=int, default=1, help="Act number (default: 1)")
    parser.add_argument("--title", help="Level title (auto-generated if omitted)")
    parser.add_argument("--subtitle", help="Level subtitle (auto-generated if omitted)")
    parser.add_argument("--auto", action="store_true",
                        help="Auto-compute Aut(G) from the graph instead of using --group")
    parser.add_argument("--no-subgroups", action="store_true",
                        help="Skip subgroup computation")
    parser.add_argument("-o", "--output", help="Output file path (stdout if omitted)")
    parser.add_argument("--list-groups", action="store_true",
                        help="List all available groups")
    parser.add_argument("--list-graphs", action="store_true",
                        help="List all available graph structures")
    parser.add_argument("--validate", metavar="FILE",
                        help="Validate an existing level JSON file")

    args = parser.parse_args()

    if args.list_groups:
        cmd_list_groups()
        return 0

    if args.list_graphs:
        cmd_list_graphs()
        return 0

    if args.validate:
        return cmd_validate(args.validate)

    # Generate mode
    if not args.graph:
        parser.error("--graph is required for level generation")
    if args.level_id is None:
        parser.error("--level-id is required for level generation")

    if not args.auto and not args.group:
        parser.error("Either --group or --auto is required")

    group_name = args.group or "auto"

    try:
        generate_level(
            group_name=group_name,
            graph_name=args.graph,
            level_id=args.level_id,
            act=args.act,
            title=args.title,
            subtitle=args.subtitle,
            auto_group=args.auto,
            include_subgroups=not args.no_subgroups,
            output_path=args.output,
        )
        return 0
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main() or 0)
