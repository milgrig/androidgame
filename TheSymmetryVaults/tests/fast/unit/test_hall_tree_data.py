"""
Unit tests for HallTreeData — Python mirror of GDScript logic.
Validates parsing, caches, and validation of hall_tree.json
without requiring the Godot engine.
"""
import json
import os
import unittest
from pathlib import Path


# === Python mirror of HallTreeData (minimal, for testing) ===

class WingData:
    def __init__(self):
        self.id: str = ""
        self.name: str = ""
        self.subtitle: str = ""
        self.act: int = 0
        self.order: int = 0
        self.gate: "GateData | None" = None
        self.halls: list[str] = []
        self.start_halls: list[str] = []


class GateData:
    def __init__(self):
        self.type: str = "threshold"
        self.required_halls: int = 0
        self.total_halls: int = 0
        self.required_from_wing: str = ""
        self.required_specific: list[str] = []
        self.message: str = ""


class HallEdge:
    def __init__(self):
        self.from_hall: str = ""
        self.to_hall: str = ""
        self.type: str = "path"


class ResonanceData:
    def __init__(self):
        self.halls: list[str] = []
        self.type: str = ""
        self.description: str = ""
        self.discovered_when: str = "both_completed"


class HallTreeData:
    """Python mirror of hall_tree_data.gd for testability."""

    def __init__(self):
        self.version: int = 0
        self.wings: list[WingData] = []
        self.edges: list[HallEdge] = []
        self.resonances: list[ResonanceData] = []
        self._hall_to_wing: dict[str, WingData] = {}
        self._hall_edges: dict[str, list[str]] = {}
        self._hall_prereqs: dict[str, list[str]] = {}

    def load_from_file(self, path: str) -> bool:
        if not os.path.exists(path):
            return False
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.parse(data)
            return True
        except (json.JSONDecodeError, IOError):
            return False

    def parse(self, data: dict) -> None:
        self.version = int(data.get("version", 0))
        self.wings = []
        self.edges = []
        self.resonances = []
        self._hall_to_wing = {}
        self._hall_edges = {}
        self._hall_prereqs = {}

        # Wings
        for w in data.get("wings", []):
            wing = WingData()
            wing.id = str(w.get("id", ""))
            wing.name = str(w.get("name", ""))
            wing.subtitle = str(w.get("subtitle", ""))
            wing.act = int(w.get("act", 0))
            wing.order = int(w.get("order", 0))

            g = w.get("gate", {})
            if isinstance(g, dict) and g:
                gate = GateData()
                gate.type = str(g.get("type", "threshold"))
                gate.required_halls = int(g.get("required_halls", 0))
                gate.total_halls = int(g.get("total_halls", 0))
                rfw = g.get("required_from_wing")
                gate.required_from_wing = str(rfw) if rfw is not None else ""
                gate.required_specific = [str(s) for s in g.get("required_specific", [])]
                gate.message = str(g.get("message", ""))
                wing.gate = gate
            else:
                wing.gate = None

            wing.halls = [str(h) for h in w.get("halls", [])]
            wing.start_halls = [str(sh) for sh in w.get("start_halls", [])]
            self.wings.append(wing)

            for hall_id in wing.halls:
                self._hall_to_wing[hall_id] = wing

        # Edges
        for e in data.get("edges", []):
            edge = HallEdge()
            edge.from_hall = str(e.get("from", ""))
            edge.to_hall = str(e.get("to", ""))
            edge.type = str(e.get("type", "path"))
            self.edges.append(edge)

        self._build_edge_caches()

        # Resonances
        for r in data.get("resonances", []):
            res = ResonanceData()
            res.halls = [str(h) for h in r.get("halls", [])]
            res.type = str(r.get("type", ""))
            res.description = str(r.get("description", ""))
            res.discovered_when = str(r.get("discovered_when", "both_completed"))
            self.resonances.append(res)

    def _build_edge_caches(self) -> None:
        self._hall_edges = {}
        self._hall_prereqs = {}
        for edge in self.edges:
            self._hall_edges.setdefault(edge.from_hall, []).append(edge.to_hall)
            self._hall_prereqs.setdefault(edge.to_hall, []).append(edge.from_hall)

    def get_wing(self, wing_id: str) -> WingData | None:
        for wing in self.wings:
            if wing.id == wing_id:
                return wing
        return None

    def get_wing_halls(self, wing_id: str) -> list[str]:
        wing = self.get_wing(wing_id)
        return wing.halls if wing else []

    def get_hall_edges(self, hall_id: str) -> list[str]:
        return self._hall_edges.get(hall_id, [])

    def get_hall_prereqs(self, hall_id: str) -> list[str]:
        return self._hall_prereqs.get(hall_id, [])

    def get_hall_wing(self, hall_id: str) -> WingData | None:
        return self._hall_to_wing.get(hall_id)

    def get_hall_resonances(self, hall_id: str) -> list[ResonanceData]:
        return [r for r in self.resonances if hall_id in r.halls]

    def get_ordered_wings(self) -> list[WingData]:
        return sorted(self.wings, key=lambda w: w.order)

    def validate(self) -> list[str]:
        errors: list[str] = []

        if not self.wings:
            errors.append("No wings defined")

        all_halls: dict[str, bool] = {}
        for wing in self.wings:
            if not wing.id:
                errors.append("Wing with empty id")
            if not wing.halls:
                errors.append(f"Wing '{wing.id}' has no halls")
            for hall_id in wing.halls:
                if hall_id in all_halls:
                    errors.append(f"Hall '{hall_id}' appears in multiple wings")
                all_halls[hall_id] = True
            for sh in wing.start_halls:
                if sh not in wing.halls:
                    errors.append(f"Start hall '{sh}' not in wing '{wing.id}' halls list")
            if wing.gate is not None:
                if wing.gate.type not in ("threshold", "all", "specific"):
                    errors.append(f"Wing '{wing.id}' has unknown gate type '{wing.gate.type}'")
                if wing.gate.type == "threshold" and wing.gate.required_halls <= 0:
                    errors.append(f"Wing '{wing.id}' threshold gate requires required_halls > 0")

        for edge in self.edges:
            if edge.from_hall not in all_halls:
                errors.append(f"Edge from unknown hall '{edge.from_hall}'")
            if edge.to_hall not in all_halls:
                errors.append(f"Edge to unknown hall '{edge.to_hall}'")
            if edge.from_hall == edge.to_hall:
                errors.append(f"Self-loop edge on hall '{edge.from_hall}'")

        for res in self.resonances:
            if len(res.halls) < 2:
                errors.append("Resonance must link at least 2 halls")
            for h in res.halls:
                if h not in all_halls:
                    errors.append(f"Resonance references unknown hall '{h}'")

        # Cycle detection
        state = {h: 0 for h in all_halls}  # 0=unvisited, 1=visiting, 2=done
        for hall_id in all_halls:
            if state[hall_id] == 0:
                if self._dfs_has_cycle(hall_id, state):
                    errors.append(f"Cycle detected involving hall '{hall_id}'")
                    break

        return errors

    def _dfs_has_cycle(self, hall_id: str, state: dict) -> bool:
        state[hall_id] = 1
        for neighbor in self._hall_edges.get(hall_id, []):
            if neighbor not in state:
                continue
            if state[neighbor] == 1:
                return True
            if state[neighbor] == 0:
                if self._dfs_has_cycle(neighbor, state):
                    return True
        state[hall_id] = 2
        return False


# === Helpers ===

def _project_root() -> Path:
    """Get path to TheSymmetryVaults directory."""
    return Path(__file__).resolve().parent.parent.parent.parent


def _make_test_data() -> dict:
    """Minimal valid hall_tree.json structure for unit tests."""
    return {
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
                    "required_halls": 8,
                    "total_halls": 12,
                    "required_from_wing": None,
                    "required_specific": [],
                    "message": "Open 8 halls to proceed",
                },
                "halls": [f"act1_level{i:02d}" for i in range(1, 13)],
                "start_halls": ["act1_level01"],
            }
        ],
        "edges": [
            {"from": "act1_level01", "to": "act1_level02", "type": "path"},
            {"from": "act1_level01", "to": "act1_level03", "type": "path"},
            {"from": "act1_level02", "to": "act1_level04", "type": "path"},
            {"from": "act1_level03", "to": "act1_level06", "type": "path"},
            {"from": "act1_level04", "to": "act1_level05", "type": "path"},
            {"from": "act1_level05", "to": "act1_level09", "type": "path"},
            {"from": "act1_level09", "to": "act1_level11", "type": "path"},
            {"from": "act1_level10", "to": "act1_level11", "type": "path"},
        ],
        "resonances": [
            {
                "halls": ["act1_level01", "act1_level11"],
                "type": "subgroup",
                "description": "Z3 is a subgroup of Z6",
                "discovered_when": "both_completed",
            },
            {
                "halls": ["act1_level05", "act1_level12"],
                "type": "isomorphic",
                "description": "Both share D4",
                "discovered_when": "both_completed",
            },
        ],
    }


def _make_tree(data: dict | None = None) -> HallTreeData:
    tree = HallTreeData()
    tree.parse(data if data is not None else _make_test_data())
    return tree


# === Test Cases ===

class TestHallTreeDataParsing(unittest.TestCase):
    """Tests for parse() — converting raw dict to typed structures."""

    def test_parse_version(self):
        tree = _make_tree()
        self.assertEqual(tree.version, 1)

    def test_parse_wings(self):
        tree = _make_tree()
        self.assertEqual(len(tree.wings), 1)
        wing = tree.wings[0]
        self.assertEqual(wing.id, "wing_1")
        self.assertEqual(wing.name, "The First Vault")
        self.assertEqual(wing.subtitle, "Groups")
        self.assertEqual(wing.act, 1)
        self.assertEqual(wing.order, 1)
        self.assertEqual(len(wing.halls), 12)
        self.assertEqual(wing.start_halls, ["act1_level01"])

    def test_parse_gate(self):
        tree = _make_tree()
        gate = tree.wings[0].gate
        self.assertIsNotNone(gate)
        self.assertEqual(gate.type, "threshold")
        self.assertEqual(gate.required_halls, 8)
        self.assertEqual(gate.total_halls, 12)
        self.assertEqual(gate.message, "Open 8 halls to proceed")

    def test_parse_edges(self):
        tree = _make_tree()
        self.assertEqual(len(tree.edges), 8)
        self.assertEqual(tree.edges[0].from_hall, "act1_level01")
        self.assertEqual(tree.edges[0].to_hall, "act1_level02")
        self.assertEqual(tree.edges[0].type, "path")

    def test_parse_resonances(self):
        tree = _make_tree()
        self.assertEqual(len(tree.resonances), 2)
        r0 = tree.resonances[0]
        self.assertEqual(r0.halls, ["act1_level01", "act1_level11"])
        self.assertEqual(r0.type, "subgroup")
        self.assertEqual(r0.discovered_when, "both_completed")

    def test_parse_empty_data(self):
        tree = _make_tree({})
        self.assertEqual(len(tree.wings), 0)
        self.assertEqual(len(tree.edges), 0)
        self.assertEqual(len(tree.resonances), 0)


class TestHallTreeDataCaches(unittest.TestCase):
    """Tests for lookup caches built during parse()."""

    def test_hall_to_wing_cache(self):
        tree = _make_tree()
        for i in range(1, 13):
            hall_id = f"act1_level{i:02d}"
            self.assertIn(hall_id, tree._hall_to_wing)
            self.assertEqual(tree._hall_to_wing[hall_id].id, "wing_1")

    def test_hall_edges_cache_outgoing(self):
        tree = _make_tree()
        edges_01 = tree._hall_edges.get("act1_level01", [])
        self.assertEqual(len(edges_01), 2)
        self.assertIn("act1_level02", edges_01)
        self.assertIn("act1_level03", edges_01)

    def test_hall_edges_cache_single(self):
        tree = _make_tree()
        edges_02 = tree._hall_edges.get("act1_level02", [])
        self.assertEqual(len(edges_02), 1)
        self.assertIn("act1_level04", edges_02)

    def test_hall_prereqs_cache(self):
        tree = _make_tree()
        prereqs_11 = tree._hall_prereqs.get("act1_level11", [])
        self.assertEqual(len(prereqs_11), 2)
        self.assertIn("act1_level09", prereqs_11)
        self.assertIn("act1_level10", prereqs_11)

    def test_start_hall_no_prereqs(self):
        tree = _make_tree()
        prereqs_01 = tree._hall_prereqs.get("act1_level01", [])
        self.assertEqual(len(prereqs_01), 0)

    def test_leaf_hall_no_outgoing(self):
        tree = _make_tree()
        edges_11 = tree._hall_edges.get("act1_level11", [])
        self.assertEqual(len(edges_11), 0)


class TestHallTreeDataQueryAPI(unittest.TestCase):
    """Tests for the public query methods."""

    def test_get_wing_found(self):
        tree = _make_tree()
        wing = tree.get_wing("wing_1")
        self.assertIsNotNone(wing)
        self.assertEqual(wing.id, "wing_1")

    def test_get_wing_not_found(self):
        tree = _make_tree()
        self.assertIsNone(tree.get_wing("nonexistent"))

    def test_get_wing_halls(self):
        tree = _make_tree()
        halls = tree.get_wing_halls("wing_1")
        self.assertEqual(len(halls), 12)
        self.assertIn("act1_level01", halls)
        self.assertIn("act1_level12", halls)

    def test_get_wing_halls_nonexistent(self):
        tree = _make_tree()
        self.assertEqual(tree.get_wing_halls("nope"), [])

    def test_get_hall_edges(self):
        tree = _make_tree()
        edges = tree.get_hall_edges("act1_level01")
        self.assertEqual(len(edges), 2)

    def test_get_hall_edges_nonexistent(self):
        tree = _make_tree()
        self.assertEqual(tree.get_hall_edges("nope"), [])

    def test_get_hall_prereqs(self):
        tree = _make_tree()
        prereqs = tree.get_hall_prereqs("act1_level04")
        self.assertEqual(len(prereqs), 1)
        self.assertIn("act1_level02", prereqs)

    def test_get_hall_wing(self):
        tree = _make_tree()
        wing = tree.get_hall_wing("act1_level05")
        self.assertIsNotNone(wing)
        self.assertEqual(wing.id, "wing_1")

    def test_get_hall_wing_nonexistent(self):
        tree = _make_tree()
        self.assertIsNone(tree.get_hall_wing("nope"))

    def test_get_hall_resonances(self):
        tree = _make_tree()
        res = tree.get_hall_resonances("act1_level01")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0].type, "subgroup")

    def test_get_hall_resonances_multiple(self):
        tree = _make_tree()
        res = tree.get_hall_resonances("act1_level05")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0].type, "isomorphic")

    def test_get_hall_resonances_none(self):
        tree = _make_tree()
        res = tree.get_hall_resonances("act1_level07")
        self.assertEqual(len(res), 0)

    def test_get_ordered_wings(self):
        tree = _make_tree()
        ordered = tree.get_ordered_wings()
        self.assertEqual(len(ordered), 1)
        self.assertEqual(ordered[0].id, "wing_1")

    def test_get_ordered_wings_multi(self):
        """Test ordering when multiple wings are present."""
        data = _make_test_data()
        data["wings"].append({
            "id": "wing_2",
            "name": "Second Wing",
            "subtitle": "More",
            "act": 2,
            "order": 2,
            "gate": {"type": "threshold", "required_halls": 5, "total_halls": 6,
                     "required_from_wing": "wing_1", "required_specific": [],
                     "message": "Need 5"},
            "halls": ["act2_level01", "act2_level02"],
            "start_halls": ["act2_level01"],
        })
        tree = _make_tree(data)
        ordered = tree.get_ordered_wings()
        self.assertEqual(len(ordered), 2)
        self.assertEqual(ordered[0].id, "wing_1")
        self.assertEqual(ordered[1].id, "wing_2")


class TestHallTreeDataValidation(unittest.TestCase):
    """Tests for validate() — structural integrity checks."""

    def test_valid_tree_no_errors(self):
        tree = _make_tree()
        errors = tree.validate()
        self.assertEqual(errors, [], f"Expected no errors, got: {errors}")

    def test_empty_tree_has_errors(self):
        tree = _make_tree({})
        errors = tree.validate()
        self.assertTrue(len(errors) > 0)
        self.assertIn("No wings defined", errors)

    def test_edge_to_unknown_hall(self):
        data = _make_test_data()
        data["edges"].append({"from": "act1_level01", "to": "ghost_hall", "type": "path"})
        tree = _make_tree(data)
        errors = tree.validate()
        self.assertTrue(any("ghost_hall" in e for e in errors))

    def test_edge_from_unknown_hall(self):
        data = _make_test_data()
        data["edges"].append({"from": "ghost_hall", "to": "act1_level01", "type": "path"})
        tree = _make_tree(data)
        errors = tree.validate()
        self.assertTrue(any("ghost_hall" in e for e in errors))

    def test_self_loop_detected(self):
        data = _make_test_data()
        data["edges"].append({"from": "act1_level01", "to": "act1_level01", "type": "path"})
        tree = _make_tree(data)
        errors = tree.validate()
        self.assertTrue(any("Self-loop" in e for e in errors))

    def test_cycle_detected(self):
        data = _make_test_data()
        # Create cycle: level02 -> level04 (exists) and level04 -> level02 (new)
        data["edges"].append({"from": "act1_level04", "to": "act1_level02", "type": "path"})
        tree = _make_tree(data)
        errors = tree.validate()
        self.assertTrue(any("Cycle" in e or "cycle" in e for e in errors),
                        f"Expected cycle error, got: {errors}")

    def test_start_hall_not_in_wing(self):
        data = _make_test_data()
        data["wings"][0]["start_halls"] = ["ghost_start"]
        tree = _make_tree(data)
        errors = tree.validate()
        self.assertTrue(any("ghost_start" in e for e in errors))

    def test_resonance_unknown_hall(self):
        data = _make_test_data()
        data["resonances"].append({
            "halls": ["act1_level01", "ghost_resonance"],
            "type": "subgroup",
            "description": "test",
            "discovered_when": "both_completed",
        })
        tree = _make_tree(data)
        errors = tree.validate()
        self.assertTrue(any("ghost_resonance" in e for e in errors))

    def test_duplicate_hall_across_wings(self):
        data = _make_test_data()
        data["wings"].append({
            "id": "wing_dup",
            "name": "Dup",
            "subtitle": "",
            "act": 2,
            "order": 2,
            "gate": None,
            "halls": ["act1_level01"],  # duplicate!
            "start_halls": ["act1_level01"],
        })
        tree = _make_tree(data)
        errors = tree.validate()
        self.assertTrue(any("act1_level01" in e and "multiple wings" in e for e in errors))


class TestHallTreeDataLoadFile(unittest.TestCase):
    """Tests for load_from_file() using the actual hall_tree.json."""

    def _get_json_path(self) -> str:
        return str(_project_root() / "data" / "hall_tree.json")

    def test_load_real_file(self):
        path = self._get_json_path()
        if not os.path.exists(path):
            self.skipTest(f"hall_tree.json not found at {path}")
        tree = HallTreeData()
        ok = tree.load_from_file(path)
        self.assertTrue(ok, "load_from_file should succeed")
        self.assertTrue(len(tree.wings) >= 1, "Should have at least 1 wing")

    def test_load_real_file_validates(self):
        path = self._get_json_path()
        if not os.path.exists(path):
            self.skipTest(f"hall_tree.json not found at {path}")
        tree = HallTreeData()
        tree.load_from_file(path)
        errors = tree.validate()
        self.assertEqual(errors, [], f"Real hall_tree.json has validation errors: {errors}")

    def test_load_real_file_wing1_has_12_halls(self):
        path = self._get_json_path()
        if not os.path.exists(path):
            self.skipTest(f"hall_tree.json not found at {path}")
        tree = HallTreeData()
        tree.load_from_file(path)
        wing1 = tree.get_wing("wing_1")
        self.assertIsNotNone(wing1)
        self.assertEqual(len(wing1.halls), 12)

    def test_load_nonexistent_file(self):
        tree = HallTreeData()
        ok = tree.load_from_file("/tmp/nonexistent_hall_tree.json")
        self.assertFalse(ok)

    def test_load_real_file_has_two_wings(self):
        """Verify the real hall_tree.json now contains Wing 1 and Wing 2."""
        path = self._get_json_path()
        if not os.path.exists(path):
            self.skipTest(f"hall_tree.json not found at {path}")
        tree = HallTreeData()
        tree.load_from_file(path)
        self.assertEqual(len(tree.wings), 2, "hall_tree.json should have 2 wings")

    def test_load_real_file_wing2_has_4_halls(self):
        """Verify Wing 2 has the 4 Act 2 halls."""
        path = self._get_json_path()
        if not os.path.exists(path):
            self.skipTest(f"hall_tree.json not found at {path}")
        tree = HallTreeData()
        tree.load_from_file(path)
        wing2 = tree.get_wing("wing_2")
        self.assertIsNotNone(wing2)
        self.assertEqual(len(wing2.halls), 4)
        self.assertIn("act2_level13", wing2.halls)
        self.assertIn("act2_level16", wing2.halls)

    def test_load_real_file_wing2_gate(self):
        """Verify Wing 2 gate requires 8 halls from Wing 1."""
        path = self._get_json_path()
        if not os.path.exists(path):
            self.skipTest(f"hall_tree.json not found at {path}")
        tree = HallTreeData()
        tree.load_from_file(path)
        wing2 = tree.get_wing("wing_2")
        self.assertIsNotNone(wing2)
        self.assertIsNotNone(wing2.gate)
        self.assertEqual(wing2.gate.type, "threshold")
        self.assertEqual(wing2.gate.required_halls, 8)
        self.assertEqual(wing2.gate.required_from_wing, "wing_1")

    def test_load_real_file_cross_wing_resonances(self):
        """Verify cross-wing resonances of type same_group_deeper exist."""
        path = self._get_json_path()
        if not os.path.exists(path):
            self.skipTest(f"hall_tree.json not found at {path}")
        tree = HallTreeData()
        tree.load_from_file(path)
        sgd_resonances = [r for r in tree.resonances if r.type == "same_group_deeper"]
        self.assertEqual(len(sgd_resonances), 2,
                         "Should have 2 same_group_deeper resonances")
        # S3 resonance: act1_level09 <-> act2_level13
        s3_res = [r for r in sgd_resonances
                  if "act1_level09" in r.halls and "act2_level13" in r.halls]
        self.assertEqual(len(s3_res), 1, "Missing S3 cross-wing resonance")
        # D4 resonance: act1_level05 <-> act2_level14
        d4_res = [r for r in sgd_resonances
                  if "act1_level05" in r.halls and "act2_level14" in r.halls]
        self.assertEqual(len(d4_res), 1, "Missing D4 cross-wing resonance")

    def test_load_real_file_wing2_edges_nonlinear(self):
        """Verify Wing 2 has nonlinear graph (2+ paths from start to end)."""
        path = self._get_json_path()
        if not os.path.exists(path):
            self.skipTest(f"hall_tree.json not found at {path}")
        tree = HallTreeData()
        tree.load_from_file(path)
        # act2_level13 should have 2 outgoing edges (to 14 and 15)
        edges_13 = tree.get_hall_edges("act2_level13")
        self.assertGreaterEqual(len(edges_13), 2,
                                "act2_level13 should have 2+ outgoing paths for nonlinear graph")
        # act2_level16 should have 2 incoming edges (from 14 and 15)
        prereqs_16 = tree.get_hall_prereqs("act2_level16")
        self.assertGreaterEqual(len(prereqs_16), 2,
                                "act2_level16 should have 2+ prereqs for nonlinear graph")


# === Wing 2 Parsing Tests ===

def _make_two_wing_test_data() -> dict:
    """Two-wing test data with Wing 2 halls 13-16."""
    return {
        "version": 2,
        "wings": [
            {
                "id": "wing_1",
                "name": "The First Vault",
                "subtitle": "Groups",
                "act": 1,
                "order": 1,
                "gate": {
                    "type": "threshold",
                    "required_halls": 8,
                    "total_halls": 12,
                    "required_from_wing": None,
                    "required_specific": [],
                    "message": "Open 8 halls to proceed",
                },
                "halls": [f"act1_level{i:02d}" for i in range(1, 13)],
                "start_halls": ["act1_level01"],
            },
            {
                "id": "wing_2",
                "name": "Inner Locks",
                "subtitle": "Subgroups",
                "act": 2,
                "order": 2,
                "gate": {
                    "type": "threshold",
                    "required_halls": 8,
                    "total_halls": 12,
                    "required_from_wing": "wing_1",
                    "required_specific": [],
                    "message": "Open 8 halls in the First Vault to enter the Inner Locks",
                },
                "halls": ["act2_level13", "act2_level14", "act2_level15", "act2_level16"],
                "start_halls": ["act2_level13"],
            },
        ],
        "edges": [
            {"from": "act1_level01", "to": "act1_level02", "type": "path"},
            {"from": "act1_level01", "to": "act1_level03", "type": "path"},
            {"from": "act1_level02", "to": "act1_level04", "type": "path"},
            {"from": "act1_level03", "to": "act1_level06", "type": "path"},
            {"from": "act1_level04", "to": "act1_level05", "type": "path"},
            {"from": "act1_level05", "to": "act1_level09", "type": "path"},
            {"from": "act1_level09", "to": "act1_level11", "type": "path"},
            {"from": "act1_level10", "to": "act1_level11", "type": "path"},
            # Wing 2 edges (nonlinear: 2 paths)
            {"from": "act2_level13", "to": "act2_level14", "type": "path"},
            {"from": "act2_level13", "to": "act2_level15", "type": "path"},
            {"from": "act2_level14", "to": "act2_level16", "type": "path"},
            {"from": "act2_level15", "to": "act2_level16", "type": "path"},
        ],
        "resonances": [
            {
                "halls": ["act1_level01", "act1_level11"],
                "type": "subgroup",
                "description": "Z3 is a subgroup of Z6",
                "discovered_when": "both_completed",
            },
            {
                "halls": ["act1_level09", "act2_level13"],
                "type": "same_group_deeper",
                "description": "S3: the same group, now explored through its subgroups",
                "discovered_when": "both_completed",
            },
            {
                "halls": ["act1_level05", "act2_level14"],
                "type": "same_group_deeper",
                "description": "D4: the same symmetries, now revealing inner structure",
                "discovered_when": "both_completed",
            },
        ],
    }


class TestWing2Parsing(unittest.TestCase):
    """Tests for parsing Wing 2 data structures."""

    def test_parse_two_wings(self):
        tree = _make_tree(_make_two_wing_test_data())
        self.assertEqual(len(tree.wings), 2)

    def test_wing2_fields(self):
        tree = _make_tree(_make_two_wing_test_data())
        wing2 = tree.get_wing("wing_2")
        self.assertIsNotNone(wing2)
        self.assertEqual(wing2.name, "Inner Locks")
        self.assertEqual(wing2.subtitle, "Subgroups")
        self.assertEqual(wing2.act, 2)
        self.assertEqual(wing2.order, 2)
        self.assertEqual(len(wing2.halls), 4)
        self.assertEqual(wing2.start_halls, ["act2_level13"])

    def test_wing2_gate(self):
        tree = _make_tree(_make_two_wing_test_data())
        wing2 = tree.get_wing("wing_2")
        self.assertIsNotNone(wing2.gate)
        self.assertEqual(wing2.gate.type, "threshold")
        self.assertEqual(wing2.gate.required_halls, 8)
        self.assertEqual(wing2.gate.required_from_wing, "wing_1")

    def test_wing2_hall_to_wing_cache(self):
        tree = _make_tree(_make_two_wing_test_data())
        for h in ["act2_level13", "act2_level14", "act2_level15", "act2_level16"]:
            self.assertIn(h, tree._hall_to_wing)
            self.assertEqual(tree._hall_to_wing[h].id, "wing_2")

    def test_wing2_edges_nonlinear(self):
        tree = _make_tree(_make_two_wing_test_data())
        # act2_level13 -> act2_level14 and act2_level13 -> act2_level15
        edges_13 = tree.get_hall_edges("act2_level13")
        self.assertEqual(len(edges_13), 2)
        self.assertIn("act2_level14", edges_13)
        self.assertIn("act2_level15", edges_13)

    def test_wing2_prereqs_convergent(self):
        tree = _make_tree(_make_two_wing_test_data())
        # act2_level16 has prereqs from both 14 and 15
        prereqs_16 = tree.get_hall_prereqs("act2_level16")
        self.assertEqual(len(prereqs_16), 2)
        self.assertIn("act2_level14", prereqs_16)
        self.assertIn("act2_level15", prereqs_16)

    def test_ordered_wings_with_wing2(self):
        tree = _make_tree(_make_two_wing_test_data())
        ordered = tree.get_ordered_wings()
        self.assertEqual(len(ordered), 2)
        self.assertEqual(ordered[0].id, "wing_1")
        self.assertEqual(ordered[1].id, "wing_2")

    def test_cross_wing_resonances(self):
        tree = _make_tree(_make_two_wing_test_data())
        sgd = [r for r in tree.resonances if r.type == "same_group_deeper"]
        self.assertEqual(len(sgd), 2)

    def test_cross_wing_resonance_halls(self):
        tree = _make_tree(_make_two_wing_test_data())
        res_09_13 = tree.get_hall_resonances("act2_level13")
        found = any(r.type == "same_group_deeper" for r in res_09_13)
        self.assertTrue(found, "act2_level13 should have same_group_deeper resonance")

    def test_two_wing_validation_passes(self):
        tree = _make_tree(_make_two_wing_test_data())
        errors = tree.validate()
        self.assertEqual(errors, [], f"Two-wing data should validate: {errors}")

    def test_no_halls_shared_between_wings(self):
        tree = _make_tree(_make_two_wing_test_data())
        wing1_halls = set(tree.get_wing("wing_1").halls)
        wing2_halls = set(tree.get_wing("wing_2").halls)
        overlap = wing1_halls & wing2_halls
        self.assertEqual(len(overlap), 0, f"Wings should not share halls: {overlap}")


if __name__ == "__main__":
    unittest.main()
