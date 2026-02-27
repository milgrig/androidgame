"""
AgentClient — Python client for The Symmetry Vaults Agent Bridge.

Launches Godot in headless mode with --agent-mode, communicates via
file-based JSON protocol (cmd.jsonl ↔ resp.jsonl).

Usage:
    from agent_client import AgentClient

    client = AgentClient()
    client.start(level_id="level_01")

    # See everything on screen (like browser DOM)
    tree = client.get_tree()

    # Game state
    state = client.get_state()
    print(state["crystals"])
    print(state["keyring"])

    # Play!
    result = client.swap(0, 1)
    result = client.submit_permutation([1, 2, 0])

    # Press any button by its path in the scene tree
    client.press_button("/root/LevelScene/HUDLayer/ResetButton")

    # What can I do right now?
    actions = client.list_actions()

    client.quit()
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional


class AgentClientError(Exception):
    """Error from the agent protocol."""
    def __init__(self, message: str, code: str = "ERROR"):
        super().__init__(message)
        self.code = code


class AgentClient:
    """
    Python client for The Symmetry Vaults Agent Bridge.

    Manages Godot subprocess and file-based communication.
    """

    def __init__(
        self,
        godot_path: str = "godot",
        project_path: Optional[str] = None,
        timeout: float = 10.0,
        poll_interval: float = 0.05,
    ):
        """
        Args:
            godot_path: Path to Godot executable (default: 'godot' in PATH)
            project_path: Path to TheSymmetryVaults project directory
            timeout: Default timeout for commands in seconds
            poll_interval: How often to check for responses (seconds)
        """
        self.godot_path = godot_path
        # Default: TheSymmetryVaults root (2 levels up from tests/agent/)
        self.project_path = project_path or str(
            Path(__file__).resolve().parents[2]
        )
        self.timeout = timeout
        self.poll_interval = poll_interval

        self._process: Optional[subprocess.Popen] = None
        self._cmd_file: Optional[str] = None
        self._resp_file: Optional[str] = None
        self._cmd_counter: int = 0
        self._started: bool = False

    # ──────────────────────────────────────────
    # Lifecycle
    # ──────────────────────────────────────────

    def start(self, level_id: Optional[str] = None) -> Dict:
        """
        Start Godot in headless agent mode.

        Args:
            level_id: Optional level to load immediately after start.

        Returns:
            Handshake response data.
        """
        # Use default file paths in project directory (matches AgentBridge defaults).
        # AgentBridge in Godot ignores --cmd-file/--resp-file passed after '--'
        # because OS.get_cmdline_user_args() concatenation order may vary.
        # Using project-dir defaults is the reliable approach.
        self._cmd_file = os.path.join(self.project_path, "agent_cmd.jsonl")
        self._resp_file = os.path.join(self.project_path, "agent_resp.jsonl")

        # Create/clear files
        Path(self._cmd_file).write_text("")
        Path(self._resp_file).write_text("")

        # Launch Godot
        cmd = [
            self.godot_path,
            "--headless",
            "--path", self.project_path,
            "--",
            "--agent-mode",
        ]

        # Use DEVNULL for stdout/stderr — Godot console edition writes
        # extensively to stdout which fills PIPE buffers and blocks the process.
        # All communication happens via file-based protocol instead.
        self._process = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        # Wait for ready marker
        self._wait_for_ready()
        self._started = True

        # Handshake
        hello = self.hello()

        # Load level if requested
        if level_id:
            self.load_level(level_id)

        return hello

    def _wait_for_ready(self, timeout: float = 30.0):
        """Wait for Godot to write the ready marker to resp file."""
        start = time.time()
        while time.time() - start < timeout:
            # Check if process died
            if self._process.poll() is not None:
                raise AgentClientError(
                    f"Godot process exited with code {self._process.returncode}.",
                    "PROCESS_DIED"
                )

            try:
                content = Path(self._resp_file).read_text(encoding='utf-8').strip()
                if content:
                    resp = json.loads(content)
                    if resp.get("ok") and resp.get("data", {}).get("status") == "ready":
                        # Clear the ready marker
                        Path(self._resp_file).write_text("", encoding='utf-8')
                        return
            except (json.JSONDecodeError, FileNotFoundError, OSError):
                pass

            time.sleep(self.poll_interval)

        # Gather diagnostic info
        diag = f"Godot did not become ready within {timeout}s."
        diag += f"\n  resp_file: {self._resp_file}"
        diag += f"\n  resp_file exists: {os.path.exists(self._resp_file)}"
        if os.path.exists(self._resp_file):
            diag += f"\n  resp_file content: {Path(self._resp_file).read_text(encoding='utf-8')[:200]!r}"
        diag += f"\n  process alive: {self._process.poll() is None if self._process else False}"
        raise AgentClientError(diag, "TIMEOUT"
        )

    def quit(self):
        """Shut down Godot and clean up protocol files."""
        if self._started:
            try:
                self._send_command("quit", timeout=3.0)
            except (AgentClientError, TimeoutError):
                pass

        if self._process:
            try:
                self._process.terminate()
                self._process.wait(timeout=5)
            except (subprocess.TimeoutExpired, OSError):
                try:
                    self._process.kill()
                except OSError:
                    pass

        # Clean up protocol files in project directory
        for f in [self._cmd_file, self._resp_file]:
            if f and os.path.exists(f):
                try:
                    os.remove(f)
                except OSError:
                    pass

        self._started = False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.quit()

    # ──────────────────────────────────────────
    # Low-level communication
    # ──────────────────────────────────────────

    def _send_command(
        self,
        cmd: str,
        args: Optional[Dict] = None,
        timeout: Optional[float] = None,
    ) -> Dict:
        """
        Send a command and wait for response.

        Args:
            cmd: Command name.
            args: Command arguments.
            timeout: Timeout in seconds (default: self.timeout).

        Returns:
            Response data dictionary.

        Raises:
            AgentClientError: On protocol errors.
            TimeoutError: If no response within timeout.
        """
        if timeout is None:
            timeout = self.timeout

        self._cmd_counter += 1
        cmd_id = self._cmd_counter

        command = {"cmd": cmd, "id": cmd_id}
        if args:
            command["args"] = args

        # Clear response file first
        Path(self._resp_file).write_text("")

        # Write command
        Path(self._cmd_file).write_text(json.dumps(command) + "\n")

        # Poll for response
        start = time.time()
        while time.time() - start < timeout:
            # Check if process died
            if self._process and self._process.poll() is not None:
                raise AgentClientError(
                    f"Godot died during '{cmd}' (exit code {self._process.returncode}).",
                    "PROCESS_DIED"
                )

            try:
                content = Path(self._resp_file).read_text(encoding='utf-8').strip()
                if content:
                    resp = json.loads(content)
                    if resp.get("id") == cmd_id:
                        if not resp.get("ok", False):
                            raise AgentClientError(
                                resp.get("error", "Unknown error"),
                                resp.get("code", "ERROR")
                            )
                        return resp
            except json.JSONDecodeError:
                pass  # File might be partially written
            except FileNotFoundError:
                pass

            time.sleep(self.poll_interval)

        raise TimeoutError(
            f"No response for '{cmd}' (id={cmd_id}) within {timeout}s"
        )

    def _send_raw(
        self,
        cmd: str,
        args: Optional[Dict] = None,
        timeout: Optional[float] = None,
    ) -> Dict:
        """Like _send_command but returns the full response including errors."""
        if timeout is None:
            timeout = self.timeout

        self._cmd_counter += 1
        cmd_id = self._cmd_counter

        command = {"cmd": cmd, "id": cmd_id}
        if args:
            command["args"] = args

        Path(self._resp_file).write_text("")
        Path(self._cmd_file).write_text(json.dumps(command) + "\n")

        start = time.time()
        while time.time() - start < timeout:
            if self._process and self._process.poll() is not None:
                raise AgentClientError("Godot process died", "PROCESS_DIED")
            try:
                content = Path(self._resp_file).read_text(encoding='utf-8').strip()
                if content:
                    resp = json.loads(content)
                    if resp.get("id") == cmd_id:
                        return resp
            except (json.JSONDecodeError, FileNotFoundError):
                pass
            time.sleep(self.poll_interval)

        raise TimeoutError(f"No response for '{cmd}' within {timeout}s")

    # ──────────────────────────────────────────
    # High-level API — Inspection
    # ──────────────────────────────────────────

    def hello(self) -> Dict:
        """Handshake: get protocol version, available commands, game info."""
        return self._send_command("hello")["data"]

    def get_tree(self, root: str = "", max_depth: int = 20) -> Dict:
        """
        Get full scene tree — the "DOM" of the game.

        Every node, every button, every label. If a programmer added it,
        it appears here. Like browser DevTools Elements tab.

        Args:
            root: Optional path to start from (default: entire tree).
            max_depth: Maximum recursion depth.

        Returns:
            Tree dictionary with nested children.
        """
        args = {"max_depth": max_depth}
        if root:
            args["root"] = root
        return self._send_command("get_tree", args)["data"]["tree"]

    def get_state(self) -> Dict:
        """
        Get current game state: crystals, edges, keyring, arrangement.

        Returns:
            State dictionary with level info, crystals, edges, etc.
        """
        return self._send_command("get_state")["data"]

    def list_actions(self) -> List[Dict]:
        """
        List all currently available actions.

        Automatically discovers buttons, inputs, and game actions.
        If a programmer added a new button — it appears here.

        Returns:
            List of action dictionaries.
        """
        return self._send_command("list_actions")["data"]["actions"]

    def list_levels(self) -> List[Dict]:
        """List all available level IDs and metadata."""
        return self._send_command("list_levels")["data"]["levels"]

    def get_node(self, path: str) -> Dict:
        """
        Get detailed information about a single node by its scene tree path.

        Args:
            path: Scene tree path (e.g. "/root/LevelScene/HUDLayer/TitleLabel").

        Returns:
            Node info dictionary with properties, signals, children.
        """
        return self._send_command("get_node", {"path": path})["data"]["node"]

    def get_events(self) -> List[Dict]:
        """
        Drain the event queue — signals that fired since last check.

        Returns:
            List of event dictionaries.
        """
        return self._send_command("get_events")["data"]["events"]

    # ──────────────────────────────────────────
    # High-level API — Actions
    # ──────────────────────────────────────────

    def load_level(self, level_id: str) -> Dict:
        """
        Load a level by ID.

        Args:
            level_id: Level identifier (e.g. "level_01", "act1_level01").

        Returns:
            Load result with level info.
        """
        return self._send_command("load_level", {"level_id": level_id})["data"]

    def swap(self, from_id: int, to_id: int) -> Dict:
        """
        Swap two crystals by their IDs (simulates drag-and-drop).

        Args:
            from_id: Crystal to drag.
            to_id: Crystal to drop onto.

        Returns:
            Full response including events (symmetry_found, invalid_attempt, etc.)
        """
        return self._send_command("swap", {"from": from_id, "to": to_id})

    def submit_permutation(self, mapping: List[int]) -> Dict:
        """
        Submit an arbitrary permutation for validation.

        Bypasses drag-and-drop. Can test identity [0,1,2], rotations, etc.

        Args:
            mapping: Permutation as array (e.g. [1, 2, 0] for rotation).

        Returns:
            Full response including events.
        """
        return self._send_command("submit_permutation", {"mapping": mapping})

    def press_button(self, path: str) -> Dict:
        """
        Press any button in the scene tree by its path.

        The button is discovered automatically — no need to register it
        in the bridge. If a programmer added a Button node, this works.

        Args:
            path: Scene tree path to the button.

        Returns:
            Press result.
        """
        return self._send_command("press_button", {"path": path})["data"]

    def set_text(self, path: str, text: str) -> Dict:
        """
        Set text on any LineEdit or TextEdit by its scene tree path.

        Args:
            path: Scene tree path to the input.
            text: Text to set.

        Returns:
            Result dictionary.
        """
        return self._send_command("set_text", {"path": path, "text": text})["data"]

    def set_value(self, path: str, value: float) -> Dict:
        """
        Set value on any slider, spinbox, or option button.

        Args:
            path: Scene tree path.
            value: Value to set.

        Returns:
            Result dictionary.
        """
        return self._send_command("set_value", {"path": path, "value": value})["data"]

    def reset(self) -> Dict:
        """Reset crystal arrangement to identity."""
        return self._send_command("reset")["data"]

    # ──────────────────────────────────────────
    # Convenience helpers
    # ──────────────────────────────────────────

    def find_buttons(self, tree: Optional[Dict] = None) -> List[Dict]:
        """
        Find all buttons in the scene tree.

        Args:
            tree: Pre-fetched tree (fetches if None).

        Returns:
            List of button info dicts with path, text, disabled status.
        """
        if tree is None:
            tree = self.get_tree()
        buttons = []
        self._collect_by_type(tree, "BaseButton", buttons,
                              also_check=["Button", "TextureButton", "CheckBox",
                                          "CheckButton", "MenuButton"])
        return buttons

    def find_labels(self, tree: Optional[Dict] = None) -> List[Dict]:
        """Find all labels in the scene tree."""
        if tree is None:
            tree = self.get_tree()
        labels = []
        self._collect_by_type(tree, "Label", labels)
        return labels

    def find_crystals(self, tree: Optional[Dict] = None) -> List[Dict]:
        """Find all CrystalNode instances in the scene tree."""
        if tree is None:
            tree = self.get_tree()
        crystals = []
        self._collect_by_script_class(tree, "CrystalNode", crystals)
        return crystals

    def _collect_by_type(self, node: Dict, type_name: str,
                         result: List, also_check: Optional[List[str]] = None):
        """Recursively collect nodes of a given class type."""
        check_types = [type_name] + (also_check or [])
        if node.get("class") in check_types:
            result.append(node)
        for child in node.get("children", []):
            self._collect_by_type(child, type_name, result, also_check)

    def _collect_by_script_class(self, node: Dict, class_name: str, result: List):
        """Recursively collect nodes with a given script class_name."""
        if node.get("script_class") == class_name:
            result.append(node)
        for child in node.get("children", []):
            self._collect_by_script_class(child, class_name, result)

    def print_tree(self, tree: Optional[Dict] = None, indent: int = 0):
        """Pretty-print the scene tree to stdout (for debugging)."""
        if tree is None:
            tree = self.get_tree()
        self._print_node(tree, indent)

    def _print_node(self, node: Dict, indent: int):
        prefix = "  " * indent
        class_name = node.get("class", "?")
        script = node.get("script_class", "")
        name = node.get("name", "?")

        # Build info string
        info_parts = []
        if "text" in node:
            text = node["text"]
            if text:
                info_parts.append(f'"{text}"')
        if "crystal_id" in node:
            info_parts.append(f"id={node['crystal_id']}")
        if "color" in node:
            info_parts.append(f"color={node['color']}")
        if "actions" in node:
            info_parts.append(f"actions={node['actions']}")
        if node.get("disabled"):
            info_parts.append("DISABLED")
        if node.get("visible") is False:
            info_parts.append("HIDDEN")

        type_str = f"{script or class_name}"
        info_str = f"  [{', '.join(info_parts)}]" if info_parts else ""

        print(f"{prefix}{name} ({type_str}){info_str}")

        for child in node.get("children", []):
            self._print_node(child, indent + 1)
