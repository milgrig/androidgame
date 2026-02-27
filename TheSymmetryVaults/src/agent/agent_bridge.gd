## AgentBridge — AI Agent accessibility layer for The Symmetry Vaults
##
## Autoload that makes the entire game accessible to AI agents.
## Works like a browser DOM: automatically discovers every node in the scene tree.
## Programmer adds a button → agent sees it. No manual bridge updates needed.
##
## Communication: file-based JSON protocol (reliable on Windows).
##   Agent writes command  → cmd.jsonl
##   Bridge writes response → resp.jsonl
##
## Activation: pass --agent-mode on command line
##   godot --headless -- --agent-mode
##
## Or set environment variable: AGENT_CMD_FILE and AGENT_RESP_FILE

extends Node

const AgentProtocol = preload("res://src/agent/agent_protocol.gd")

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────

## Whether agent mode is active
var active: bool = false

## File paths for communication
var cmd_file_path: String = ""
var resp_file_path: String = ""

## Timestamp of last processed command (to detect new commands)
var _last_cmd_modified: int = 0

## Command ID of last processed command (to avoid duplicates)
var _last_cmd_id: int = -1

## Event queue: signals that fired since last drain
var _event_queue: Array[Dictionary] = []

## Cached reference to LevelScene (found dynamically)
var _level_scene: LevelScene = null

## Whether we've connected to the current level scene's signals
var _signals_connected: bool = false

## Stored callables for signal disconnection
var _signal_callbacks: Dictionary = {}

## Deferred load: when scene transition is needed, store info to respond after load.
var _deferred_load_cmd_id: int = -1
var _deferred_load_level_id: String = ""
var _deferred_load_file_path: String = ""
var _deferred_load_frames_waited: int = 0
const _DEFERRED_LOAD_MAX_FRAMES: int = 30  # ~0.5s at 60fps



# ──────────────────────────────────────────────
# Lifecycle
# ──────────────────────────────────────────────

func _ready() -> void:
	# Check for --agent-mode in command line
	var user_args := OS.get_cmdline_user_args()
	var all_args := OS.get_cmdline_args()

	for arg in user_args + all_args:
		if arg == "--agent-mode":
			active = true
			break

	if not active:
		# Also check environment variables
		if OS.get_environment("AGENT_CMD_FILE") != "":
			active = true

	if not active:
		return

	# Determine file paths
	cmd_file_path = _get_file_path("AGENT_CMD_FILE", "--cmd-file", "agent_cmd.jsonl")
	resp_file_path = _get_file_path("AGENT_RESP_FILE", "--resp-file", "agent_resp.jsonl")

	# Create/clear files
	_write_file(resp_file_path, "")
	_write_file(cmd_file_path, "")

	# Print to stderr so stdout stays clean for protocol
	printerr("[AgentBridge] Active. Protocol v%s" % AgentProtocol.PROTOCOL_VERSION)
	printerr("[AgentBridge] cmd:  %s" % cmd_file_path)
	printerr("[AgentBridge] resp: %s" % resp_file_path)

	# Write a ready marker so the client knows we're alive
	var ready_response := AgentProtocol.success({
		"status": "ready",
		"version": AgentProtocol.PROTOCOL_VERSION,
	}, [], 0)
	_write_file(resp_file_path, ready_response)


func _process(_delta: float) -> void:
	if not active:
		return

	# Try to find/reconnect to LevelScene if needed
	_ensure_level_scene()

	# Handle deferred load: scene transition was requested, wait for LevelScene
	if _deferred_load_cmd_id >= 0:
		_deferred_load_frames_waited += 1
		if _level_scene and is_instance_valid(_level_scene):
			# LevelScene appeared — it already loaded the level in _ready()
			# via GameManager.current_hall_id. If the level_id doesn't match
			# (e.g. due to registry mismatch), re-load from the resolved path.
			if _level_scene.level_data.is_empty():
				_level_scene.load_level_from_file(_deferred_load_file_path)
			if not _signals_connected:
				_connect_level_signals()
			var resp := AgentProtocol.success({
				"loaded": true,
				"level_id": _level_scene.level_id,
				"title": _level_scene.level_data.get("meta", {}).get("title", ""),
			}, [], _deferred_load_cmd_id)
			_write_response(resp)
			_deferred_load_cmd_id = -1
			_deferred_load_level_id = ""
			_deferred_load_file_path = ""
			_deferred_load_frames_waited = 0
		elif _deferred_load_frames_waited > _DEFERRED_LOAD_MAX_FRAMES:
			# Timed out waiting for scene transition
			var resp := AgentProtocol.error(
				"Scene transition timed out after %d frames" % _deferred_load_frames_waited,
				"TIMEOUT", _deferred_load_cmd_id)
			_write_response(resp)
			_deferred_load_cmd_id = -1
			_deferred_load_level_id = ""
			_deferred_load_file_path = ""
			_deferred_load_frames_waited = 0
		# Don't poll new commands while deferred load is pending
		return

	# Poll command file
	_poll_command_file()


# ──────────────────────────────────────────────
# File path resolution
# ──────────────────────────────────────────────

func _get_file_path(env_var: String, cli_flag: String, default_name: String) -> String:
	# 1. Environment variable
	var env := OS.get_environment(env_var)
	if env != "":
		return env

	# 2. Command line flag
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in range(args.size() - 1):
		if args[i] == cli_flag:
			return args[i + 1]

	# 3. Default: in project directory
	return ProjectSettings.globalize_path("res://") + default_name


# ──────────────────────────────────────────────
# LevelScene discovery
# ──────────────────────────────────────────────

func _ensure_level_scene() -> void:
	## Find LevelScene in the tree. Reconnect signals if it changed.
	# Guard against stale/freed references (T057 fix)
	if _level_scene != null and not is_instance_valid(_level_scene):
		_level_scene = null
		_signals_connected = false
		_signal_callbacks.clear()

	var scene := _find_level_scene()
	if scene == _level_scene and _signals_connected:
		return

	# Disconnect old signals before switching to a new scene
	_disconnect_level_signals()
	_level_scene = scene
	_signals_connected = false

	if _level_scene:
		_connect_level_signals()


func _find_level_scene() -> LevelScene:
	## Walk the tree to find the first LevelScene node
	return _find_node_of_type(get_tree().root, "LevelScene") as LevelScene


func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node is LevelScene:
		return node
	for child in node.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found
	return null


func _connect_level_signals() -> void:
	if not _level_scene or _signals_connected:
		return

	# Disconnect any previous signal connections to avoid duplicates
	_disconnect_level_signals()

	# Connect all LevelScene signals → event queue
	# Store callables so we can disconnect them later
	if _level_scene.has_signal("swap_performed"):
		var cb := func(mapping): _push_event("swap_performed", {"mapping": Array(mapping)})
		_signal_callbacks["swap_performed"] = cb
		_level_scene.swap_performed.connect(cb)
	if _level_scene.has_signal("symmetry_found"):
		var cb := func(sym_id, mapping): _push_event("symmetry_found", {"sym_id": sym_id, "mapping": Array(mapping)})
		_signal_callbacks["symmetry_found"] = cb
		_level_scene.symmetry_found.connect(cb)
	if _level_scene.has_signal("level_completed"):
		var cb := func(lid): _push_event("level_completed", {"level_id": lid})
		_signal_callbacks["level_completed"] = cb
		_level_scene.level_completed.connect(cb)
	if _level_scene.has_signal("invalid_attempt"):
		var cb := func(mapping): _push_event("invalid_attempt", {"mapping": Array(mapping)})
		_signal_callbacks["invalid_attempt"] = cb
		_level_scene.invalid_attempt.connect(cb)

	# Connect inner door panel signals (Act 2)
	if _level_scene._inner_door_panel != null and is_instance_valid(_level_scene._inner_door_panel):
		var panel = _level_scene._inner_door_panel
		if panel.has_signal("subgroup_found"):
			var cb := func(sg_name): _push_event("subgroup_found", {"subgroup_name": sg_name, "subgroups": panel.get_state()})
			_signal_callbacks["subgroup_found"] = cb
			panel.subgroup_found.connect(cb)
		if panel.has_signal("subgroup_check_failed"):
			var cb := func(reason): _push_event("subgroup_check_failed", {"reason": reason})
			_signal_callbacks["subgroup_check_failed"] = cb
			panel.subgroup_check_failed.connect(cb)

	# Enable agent_mode on the level scene
	if "agent_mode" in _level_scene:
		_level_scene.agent_mode = true

	_signals_connected = true
	printerr("[AgentBridge] Connected to LevelScene: %s" % str(_level_scene.get_path()))


func _disconnect_level_signals() -> void:
	## Disconnect any previously connected signal callbacks from the level scene.
	if not _level_scene or not is_instance_valid(_level_scene):
		_signal_callbacks.clear()
		return
	for sig_name in _signal_callbacks:
		if _level_scene.has_signal(sig_name):
			var cb: Callable = _signal_callbacks[sig_name]
			if _level_scene.is_connected(sig_name, cb):
				_level_scene.disconnect(sig_name, cb)
	_signal_callbacks.clear()


func _push_event(event_type: String, data: Dictionary = {}) -> void:
	_event_queue.append({
		"type": event_type,
		"data": data,
		"timestamp_ms": Time.get_ticks_msec(),
	})


# ──────────────────────────────────────────────
# Command file polling
# ──────────────────────────────────────────────

func _poll_command_file() -> void:
	if not FileAccess.file_exists(cmd_file_path):
		return

	# Read command file contents every frame (file modified time has
	# only 1-second resolution on Windows, which causes missed commands).
	var file := FileAccess.open(cmd_file_path, FileAccess.READ)
	if not file:
		return
	var content := file.get_as_text().strip_edges()
	file.close()

	if content.is_empty():
		return

	# Parse and dispatch
	var parsed := AgentProtocol.parse_command(content)
	if parsed.has("error"):
		_write_response(AgentProtocol.error(parsed["error"], "PARSE_ERROR"))
		return

	var cmd_id: int = parsed.get("id", 0)

	# Skip if we already processed this command
	if cmd_id == _last_cmd_id and cmd_id != 0:
		return
	_last_cmd_id = cmd_id

	# Clear stale events that accumulated between commands (already reported
	# or irrelevant). Only events that fire DURING the command matter.
	_event_queue.clear()

	# Dispatch command
	var response := _dispatch(parsed["cmd"], parsed["args"], cmd_id)

	# Empty response means deferred — will be sent later (e.g. scene transition)
	if response.is_empty():
		return

	# Collect only events that fired during this command's execution
	var cmd_events: Array = _event_queue.duplicate()
	_event_queue.clear()

	# Inject events into response
	if response.contains("\"events\":[]"):
		response = response.replace("\"events\":[]",
			"\"events\":" + JSON.stringify(cmd_events))
	elif not cmd_events.is_empty():
		# If response already has events, this is fine — events are in the response
		pass

	_write_response(response)


func _write_response(response_json: String) -> void:
	_write_file(resp_file_path, response_json)


func _write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()


# ──────────────────────────────────────────────
# Command dispatch
# ──────────────────────────────────────────────

func _dispatch(cmd: String, args: Dictionary, cmd_id: int) -> String:
	match cmd:
		"hello":
			return _cmd_hello(cmd_id)
		"get_tree":
			return _cmd_get_tree(args, cmd_id)
		"get_state":
			return _cmd_get_state(cmd_id)
		"list_actions":
			return _cmd_list_actions(cmd_id)
		"list_levels":
			return _cmd_list_levels(cmd_id)
		"load_level":
			return _cmd_load_level(args, cmd_id)
		"swap":
			return _cmd_swap(args, cmd_id)
		"submit_permutation":
			return _cmd_submit_permutation(args, cmd_id)
		"press_button":
			return _cmd_press_button(args, cmd_id)
		"set_text":
			return _cmd_set_text(args, cmd_id)
		"set_value":
			return _cmd_set_value(args, cmd_id)
		"reset":
			return _cmd_reset(cmd_id)
		"repeat_key":
			return _cmd_repeat_key(args, cmd_id)
		"get_node":
			return _cmd_get_node(args, cmd_id)
		"get_events":
			return _cmd_get_events(cmd_id)
		"get_map_state":
			return _cmd_get_map_state(cmd_id)
		"navigate":
			return _cmd_navigate(args, cmd_id)
		"select_keys":
			return _cmd_select_keys(args, cmd_id)
		"try_open_door", "check_subgroup":
			return _cmd_check_subgroup(args, cmd_id)
		"quit":
			return _cmd_quit(cmd_id)
		_:
			return AgentProtocol.error(
				"Unknown command: '%s'. Use 'hello' for available commands." % cmd,
				"UNKNOWN_COMMAND", cmd_id)


# ──────────────────────────────────────────────
# Command handlers
# ──────────────────────────────────────────────

func _cmd_hello(cmd_id: int) -> String:
	return AgentProtocol.success({
		"version": AgentProtocol.PROTOCOL_VERSION,
		"game": "The Symmetry Vaults",
		"commands": AgentProtocol.get_command_catalog(),
		"level_loaded": _level_scene != null,
		"current_level": _level_scene.level_id if _level_scene else "",
	}, [], cmd_id)


func _cmd_get_tree(args: Dictionary, cmd_id: int) -> String:
	## Full scene tree — the "DOM" of the game.
	var max_depth: int = args.get("max_depth", 20)
	var root_path: String = args.get("root", "")

	var root_node: Node
	if root_path.is_empty():
		root_node = get_tree().root
	else:
		root_node = get_tree().root.get_node_or_null(root_path)
		if not root_node:
			return AgentProtocol.error(
				"Node not found: '%s'" % root_path, "NOT_FOUND", cmd_id)

	var tree := AgentProtocol.serialize_tree(root_node, max_depth)
	return AgentProtocol.success({"tree": tree}, [], cmd_id)


func _cmd_get_state(cmd_id: int) -> String:
	if not _level_scene or not is_instance_valid(_level_scene):
		return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

	# Crystals
	var crystals_data: Array = []
	for crystal in _level_scene.crystals.values():
		crystals_data.append(AgentProtocol.serialize_crystal(crystal))

	# Edges
	var edges_data: Array = []
	for edge in _level_scene.edges:
		edges_data.append(AgentProtocol.serialize_edge(edge))

	# KeyRing — always provide a well-formed dict even when key_ring is null
	var keyring_data := {}
	if _level_scene.key_ring:
		keyring_data = AgentProtocol.serialize_keyring(_level_scene.key_ring)
	else:
		keyring_data = {
			"found": [],
			"found_count": 0,
			"total": _level_scene.total_symmetries,
			"complete": false,
			"has_identity": false,
			"is_closed": false,
			"has_inverses": false,
		}

	# Graph
	var graph_data := {}
	if _level_scene.crystal_graph:
		graph_data = AgentProtocol.serialize_graph(_level_scene.crystal_graph)

	# Level meta
	var meta: Dictionary = _level_scene.level_data.get("meta", {})

	# Current permutation
	var perm_data := {}
	if not _level_scene.current_arrangement.is_empty():
		var perm := Permutation.from_array(_level_scene.current_arrangement)
		perm_data = AgentProtocol.serialize_permutation(perm)

	var state := {
		"level": {
			"id": _level_scene.level_id,
			"title": meta.get("title", ""),
			"subtitle": meta.get("subtitle", ""),
			"group_name": meta.get("group_name", ""),
			"group_order": meta.get("group_order", 0),
		},
		"crystals": crystals_data,
		"edges": edges_data,
		"arrangement": Array(_level_scene.current_arrangement),
		"current_permutation": perm_data,
		"keyring": keyring_data,
		"graph": graph_data,
		"total_symmetries": _level_scene.total_symmetries,
		"is_shuffled": true,
		"initial_arrangement": Array(_level_scene._initial_arrangement),
		"target_arrangement": Array(_level_scene._identity_arrangement),
		"shuffle_seed": _level_scene._shuffle_seed,
		"identity_found": _level_scene._identity_found,
	}

	# Inner doors / subgroups state (Act 2 levels)
	if _level_scene._inner_door_panel != null:
		state["inner_doors"] = _level_scene._inner_door_panel.get_state()
	else:
		state["inner_doors"] = {
			"found_subgroups": [],
			"target_subgroups": [],
			"selected_keys": [],
			"all_found": false,
			"found_count": 0,
			"total_count": 0,
		}

	return AgentProtocol.success(state, [], cmd_id)


func _cmd_list_actions(cmd_id: int) -> String:
	var actions: Array = []

	if _level_scene:
		# Swap actions: which crystals can be swapped
		var draggable_ids: Array = []
		for crystal in _level_scene.crystals.values():
			if crystal.draggable:
				draggable_ids.append(crystal.crystal_id)

		if draggable_ids.size() >= 2:
			actions.append({
				"action": "swap",
				"params": {"from": "crystal_id", "to": "crystal_id"},
				"available_ids": draggable_ids,
				"description": "Swap two crystals by ID",
			})

		actions.append({
			"action": "submit_permutation",
			"params": {"mapping": "array of ints"},
			"description": "Submit a permutation directly for validation",
		})

		actions.append({
			"action": "reset",
			"description": "Reset arrangement to shuffled start position",
		})

	# Discover all pressable buttons in the tree
	var buttons := _find_all_pressable_buttons(get_tree().root)
	for btn_info in buttons:
		actions.append({
			"action": "press_button",
			"params": {"path": btn_info["path"]},
			"button_text": btn_info["text"],
			"description": "Press button: %s" % btn_info["text"],
		})

	# Discover all text inputs
	var inputs := _find_all_inputs(get_tree().root)
	for input_info in inputs:
		actions.append({
			"action": "set_text",
			"params": {"path": input_info["path"], "text": "string"},
			"description": "Set text on: %s" % input_info["name"],
		})

	actions.append({
		"action": "load_level",
		"params": {"level_id": "string"},
		"description": "Load a level by ID",
	})

	return AgentProtocol.success({"actions": actions}, [], cmd_id)


func _cmd_list_levels(cmd_id: int) -> String:
	var levels: Array = []

	# Scan level directories
	var base_path := "res://data/levels/"
	var acts := ["act1", "act2", "act3", "act4"]
	for act in acts:
		var dir_path: String = base_path + act
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				var level_id := file_name.get_basename()
				var full_path: String = dir_path + "/" + file_name
				# Read level meta
				var meta := _read_level_meta(full_path)
				levels.append({
					"id": level_id,
					"act": act,
					"file": full_path,
					"title": meta.get("title", level_id),
					"group_name": meta.get("group_name", ""),
				})
			file_name = dir.get_next()

	return AgentProtocol.success({"levels": levels}, [], cmd_id)


func _cmd_load_level(args: Dictionary, cmd_id: int) -> String:
	var level_id: String = args.get("level_id", "")
	if level_id.is_empty():
		return AgentProtocol.error("Missing 'level_id' argument", "MISSING_ARG", cmd_id)

	# Try to find the level file
	var file_path := _resolve_level_path(level_id)
	if file_path.is_empty():
		return AgentProtocol.error(
			"Level not found: '%s'" % level_id, "NOT_FOUND", cmd_id)

	if _level_scene and is_instance_valid(_level_scene):
		# Already on a LevelScene — just load new level into it.
		# Disconnect old signals first, then load, then reconnect (T057 fix).
		_disconnect_level_signals()
		_signals_connected = false
		_level_scene.load_level_from_file(file_path)
		_connect_level_signals()
		return AgentProtocol.success({
			"loaded": true,
			"level_id": _level_scene.level_id,
			"title": _level_scene.level_data.get("meta", {}).get("title", ""),
		}, [], cmd_id)
	else:
		# Not on a LevelScene (e.g. on MapScene or MainMenu).
		# Switch to LevelScene via scene change. Use deferred response:
		# _process() will detect the new LevelScene, load the level, and
		# send the response AFTER the scene is ready.
		var gm := get_node_or_null("/root/GameManager")
		if gm:
			# Try to resolve the level_id to a registry key that GameManager
			# understands. level_registry uses meta.id (e.g. "act1_level04")
			# but agent may pass "level_04". Register the file_path under
			# the raw level_id so LevelScene._ready() can find it. (T057 fix)
			if not gm.level_registry.has(level_id):
				gm.level_registry[level_id] = file_path
			gm.current_hall_id = level_id
		# Change scene — LevelScene._ready() reads current_hall_id and loads level
		get_tree().change_scene_to_file("res://src/game/level_scene.tscn")
		# Reset cached reference so _ensure_level_scene() picks up the new one
		_level_scene = null
		_signals_connected = false
		_signal_callbacks.clear()
		# Store deferred load info — response will be sent from _process()
		# after the LevelScene is ready. This prevents race conditions where
		# the client sends get_tree() before the scene transition completes.
		_deferred_load_cmd_id = cmd_id
		_deferred_load_level_id = level_id
		_deferred_load_file_path = file_path
		_deferred_load_frames_waited = 0
		# Return empty string — _poll_command_file caller will skip writing
		# the response. The deferred handler in _process() will write it.
		return ""


func _cmd_swap(args: Dictionary, cmd_id: int) -> String:
	if not _level_scene or not is_instance_valid(_level_scene):
		return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

	var from_id: int = args.get("from", -1)
	var to_id: int = args.get("to", -1)

	if from_id < 0 or to_id < 0:
		return AgentProtocol.error(
			"Missing 'from' and 'to' crystal IDs", "MISSING_ARG", cmd_id)

	if not _level_scene.has_method("perform_swap_by_id"):
		return AgentProtocol.error(
			"LevelScene missing perform_swap_by_id — update level_scene.gd",
			"NOT_IMPLEMENTED", cmd_id)

	var result: Dictionary = _level_scene.perform_swap_by_id(from_id, to_id)
	return AgentProtocol.success(result, [], cmd_id)


func _cmd_submit_permutation(args: Dictionary, cmd_id: int) -> String:
	if not _level_scene or not is_instance_valid(_level_scene):
		return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

	var mapping = args.get("mapping", [])
	if mapping.is_empty():
		return AgentProtocol.error(
			"Missing 'mapping' array", "MISSING_ARG", cmd_id)

	if not _level_scene.has_method("submit_permutation"):
		return AgentProtocol.error(
			"LevelScene missing submit_permutation — update level_scene.gd",
			"NOT_IMPLEMENTED", cmd_id)

	# Convert to Array[int]
	var int_mapping: Array[int] = []
	for val in mapping:
		int_mapping.append(int(val))

	var result: Dictionary = _level_scene.submit_permutation(int_mapping)
	return AgentProtocol.success(result, [], cmd_id)


func _cmd_press_button(args: Dictionary, cmd_id: int) -> String:
	var path: String = args.get("path", "")
	if path.is_empty():
		return AgentProtocol.error("Missing 'path' argument", "MISSING_ARG", cmd_id)

	var node := get_tree().root.get_node_or_null(path)
	if not node:
		return AgentProtocol.error(
			"Node not found: '%s'" % path, "NOT_FOUND", cmd_id)

	if not node is BaseButton:
		return AgentProtocol.error(
			"Node '%s' is %s, not a button" % [path, node.get_class()],
			"WRONG_TYPE", cmd_id)

	if node.disabled:
		return AgentProtocol.error(
			"Button '%s' is disabled" % path, "DISABLED", cmd_id)

	# Simulate button press
	node.pressed.emit()

	return AgentProtocol.success({
		"pressed": true,
		"button_path": path,
		"button_text": node.text if node is Button else "",
	}, [], cmd_id)


func _cmd_set_text(args: Dictionary, cmd_id: int) -> String:
	var path: String = args.get("path", "")
	var text: String = args.get("text", "")

	if path.is_empty():
		return AgentProtocol.error("Missing 'path' argument", "MISSING_ARG", cmd_id)

	var node := get_tree().root.get_node_or_null(path)
	if not node:
		return AgentProtocol.error(
			"Node not found: '%s'" % path, "NOT_FOUND", cmd_id)

	if node is LineEdit:
		node.text = text
		node.text_changed.emit(text)
	elif node is TextEdit:
		node.text = text
		node.text_changed.emit()
	else:
		return AgentProtocol.error(
			"Node '%s' is %s, not a text input" % [path, node.get_class()],
			"WRONG_TYPE", cmd_id)

	return AgentProtocol.success({"set": true, "path": path, "text": text}, [], cmd_id)


func _cmd_set_value(args: Dictionary, cmd_id: int) -> String:
	var path: String = args.get("path", "")
	var value = args.get("value", null)

	if path.is_empty():
		return AgentProtocol.error("Missing 'path' argument", "MISSING_ARG", cmd_id)
	if value == null:
		return AgentProtocol.error("Missing 'value' argument", "MISSING_ARG", cmd_id)

	var node := get_tree().root.get_node_or_null(path)
	if not node:
		return AgentProtocol.error(
			"Node not found: '%s'" % path, "NOT_FOUND", cmd_id)

	if node is Range:
		node.value = float(value)
	elif node is OptionButton:
		node.select(int(value))
	else:
		return AgentProtocol.error(
			"Node '%s' is %s, not a value control" % [path, node.get_class()],
			"WRONG_TYPE", cmd_id)

	return AgentProtocol.success({"set": true, "path": path, "value": value}, [], cmd_id)


func _cmd_reset(cmd_id: int) -> String:
	if not _level_scene or not is_instance_valid(_level_scene):
		return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

	_level_scene._reset_arrangement()

	return AgentProtocol.success({
		"reset": true,
		"arrangement": Array(_level_scene.current_arrangement),
	}, [], cmd_id)


func _cmd_repeat_key(args: Dictionary, cmd_id: int) -> String:
	if not _level_scene or not is_instance_valid(_level_scene):
		return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

	var key_index: int = args.get("key_index", -1)
	if key_index < 0:
		return AgentProtocol.error(
			"Missing or invalid 'key_index' argument", "MISSING_ARG", cmd_id)

	if not _level_scene.has_method("agent_repeat_key"):
		return AgentProtocol.error(
			"LevelScene missing agent_repeat_key — update level_scene.gd",
			"NOT_IMPLEMENTED", cmd_id)

	var result: Dictionary = _level_scene.agent_repeat_key(key_index)
	return AgentProtocol.success(result, [], cmd_id)


func _cmd_get_node(args: Dictionary, cmd_id: int) -> String:
	var path: String = args.get("path", "")
	if path.is_empty():
		return AgentProtocol.error("Missing 'path' argument", "MISSING_ARG", cmd_id)

	var node := get_tree().root.get_node_or_null(path)
	if not node:
		return AgentProtocol.error(
			"Node not found: '%s'" % path, "NOT_FOUND", cmd_id)

	# Full serialization of this one node (without recursive children)
	var data := AgentProtocol._serialize_node_properties(node)

	# Add signal info
	var signals_info: Array = []
	for sig in node.get_signal_list():
		var connections_count := node.get_signal_connection_list(sig["name"]).size()
		signals_info.append({
			"name": sig["name"],
			"connections": connections_count,
		})
	data["signals"] = signals_info

	# Add children list (names only, for reference)
	var child_names: Array = []
	for child in node.get_children():
		if not child.name.begins_with("@"):
			child_names.append(str(child.name))
	data["child_names"] = child_names

	return AgentProtocol.success({"node": data}, [], cmd_id)


func _cmd_get_events(cmd_id: int) -> String:
	var events: Array = _event_queue.duplicate()
	_event_queue.clear()
	return AgentProtocol.success({"events": events, "count": events.size()}, [], cmd_id)


func _cmd_get_map_state(cmd_id: int) -> String:
	## Return the current state of the world map (halls, progression, etc.)
	var gm := get_node_or_null("/root/GameManager")
	if not gm:
		return AgentProtocol.error("GameManager not found", "NO_GM", cmd_id)

	var result := {
		"current_scene": "",
		"halls": [],
		"completed_levels": Array(gm.completed_levels) if gm.completed_levels else [],
		"current_hall_id": gm.current_hall_id if "current_hall_id" in gm else "",
	}

	# Determine current scene
	var root := get_tree().root
	for child in root.get_children():
		if child.get_class() == "Node" and child.name == "GameManager":
			continue
		if child.name == "AgentBridge":
			continue
		result["current_scene"] = str(child.name)

	# If progression engine exists, get hall states
	if gm.progression:
		var available: Array = gm.progression.get_available_halls()
		result["available_halls"] = available

		# Get all hall states
		var hall_states: Array = []
		if gm.hall_tree:
			for wing_data in gm.hall_tree.get_ordered_wings():
				var wing_id: String = wing_data.id
				var hall_ids: Array = gm.hall_tree.get_wing_halls(wing_id)
				for hall_id in hall_ids:
					var state_enum = gm.progression.get_hall_state(hall_id)
					var state_name := "unknown"
					match state_enum:
						0: state_name = "locked"
						1: state_name = "available"
						2: state_name = "completed"
						3: state_name = "perfect"
					hall_states.append({
						"hall_id": hall_id,
						"state": state_name,
						"wing_id": wing_id,
					})
		result["halls"] = hall_states

		# Wing progress
		if gm.hall_tree:
			var wings: Array = []
			for wing_data in gm.hall_tree.get_ordered_wings():
				var progress = gm.progression.get_wing_progress(wing_data.id)
				wings.append({
					"wing_id": wing_data.id,
					"name": wing_data.name,
					"completed": progress.get("completed", 0),
					"total": progress.get("total", 0),
					"accessible": gm.progression.is_wing_accessible(wing_data.id),
				})
			result["wings"] = wings

	return AgentProtocol.success(result, [], cmd_id)


func _cmd_navigate(args: Dictionary, cmd_id: int) -> String:
	## Navigate to a specific scene: "main_menu", "map", or load a level by ID.
	var target: String = args.get("to", "")
	if target.is_empty():
		return AgentProtocol.error("Missing 'to' argument. Use: 'main_menu', 'map', or a level_id.", "MISSING_ARG", cmd_id)

	match target:
		"main_menu":
			_disconnect_level_signals()
			get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
			_level_scene = null
			_signals_connected = false
			return AgentProtocol.success({"navigated": "main_menu"}, [], cmd_id)
		"map":
			_disconnect_level_signals()
			var gm := get_node_or_null("/root/GameManager")
			if gm and gm.has_method("open_map"):
				gm.open_map()
			else:
				get_tree().change_scene_to_file("res://src/ui/map_scene.tscn")
			_level_scene = null
			_signals_connected = false
			return AgentProtocol.success({"navigated": "map"}, [], cmd_id)
		_:
			# Treat as level_id
			return _cmd_load_level({"level_id": target}, cmd_id)
	# Unreachable but needed for GDScript parser
	return AgentProtocol.error("Unknown target", "UNKNOWN", cmd_id)


func _cmd_select_keys(args: Dictionary, cmd_id: int) -> String:
	## Select keys on the inner door panel by indices (Act 2 levels).
	if not _level_scene or not is_instance_valid(_level_scene):
		return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

	if _level_scene._inner_door_panel == null:
		return AgentProtocol.error(
			"No inner doors on this level (Act 1 or no inner_doors defined)",
			"NO_INNER_DOORS", cmd_id)

	var indices = args.get("indices", [])
	if not (indices is Array):
		return AgentProtocol.error(
			"Missing 'indices' array argument", "MISSING_ARG", cmd_id)

	_level_scene._inner_door_panel.set_selected_keys(indices)

	return AgentProtocol.success({
		"selected": true,
		"indices": Array(indices),
		"subgroups": _level_scene._inner_door_panel.get_state(),
	}, [], cmd_id)


func _cmd_check_subgroup(args: Dictionary, cmd_id: int) -> String:
	## Check if the selected keys form a valid subgroup (Act 2 levels).
	## Equivalent to pressing the "ПРОВЕРИТЬ НАБОР" button.
	## Also accepts 'try_open_door' as alias for backward compatibility.
	if not _level_scene or not is_instance_valid(_level_scene):
		return AgentProtocol.error("No level loaded", "NO_LEVEL", cmd_id)

	if _level_scene._inner_door_panel == null:
		return AgentProtocol.error(
			"No inner doors on this level", "NO_INNER_DOORS", cmd_id)

	var panel = _level_scene._inner_door_panel

	# Optionally accept indices to select before trying
	if args.has("indices"):
		var indices = args.get("indices", [])
		if indices is Array and not indices.is_empty():
			panel.set_selected_keys(indices)

	# Check that keys are selected
	if panel.selected_key_indices.is_empty():
		return AgentProtocol.error(
			"No keys selected. Use select_keys first or pass 'indices' argument.",
			"NO_SELECTION", cmd_id)

	# Simulate pressing the check button
	panel._on_check_pressed()

	return AgentProtocol.success({
		"attempted": true,
		"subgroups": panel.get_state(),
	}, [], cmd_id)


func _cmd_quit(cmd_id: int) -> String:
	var response := AgentProtocol.success({"quit": true}, [], cmd_id)
	_write_response(response)
	# Give time for file to be written, then quit (deferred to avoid coroutine)
	get_tree().create_timer(0.1).timeout.connect(func(): get_tree().quit())
	return response


# ──────────────────────────────────────────────
# Discovery helpers
# ──────────────────────────────────────────────

func _find_all_pressable_buttons(root: Node) -> Array:
	## Walk tree and find all visible, enabled buttons
	var result: Array = []
	_collect_buttons(root, result)
	return result


func _collect_buttons(node: Node, result: Array) -> void:
	if node is BaseButton and node.visible and not node.disabled:
		var text := ""
		if node is Button:
			text = node.text
		result.append({
			"path": str(node.get_path()),
			"text": text,
			"name": str(node.name),
		})
	for child in node.get_children():
		_collect_buttons(child, result)


func _find_all_inputs(root: Node) -> Array:
	## Walk tree and find all text inputs
	var result: Array = []
	_collect_inputs(root, result)
	return result


func _collect_inputs(node: Node, result: Array) -> void:
	if (node is LineEdit or node is TextEdit) and node.visible:
		result.append({
			"path": str(node.get_path()),
			"name": str(node.name),
		})
	for child in node.get_children():
		_collect_inputs(child, result)


func _read_level_meta(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var data = json.data
	if data is Dictionary:
		return data.get("meta", {})
	return {}


func _resolve_level_path(level_id: String) -> String:
	## Try to find a level file by ID
	## Checks: direct path, act subdirs, with/without prefix
	var acts := ["act1", "act2", "act3", "act4"]

	# Try direct file path
	if FileAccess.file_exists(level_id):
		return level_id

	# Try as level_XX in each act directory
	for act in acts:
		var path := "res://data/levels/%s/%s.json" % [act, level_id]
		if FileAccess.file_exists(path):
			return path

	# Try with act prefix: "act1_level01" → "act1/level_01"
	if "_" in level_id:
		var parts := level_id.split("_", true, 1)
		if parts.size() == 2:
			var path := "res://data/levels/%s/%s.json" % [parts[0], parts[1]]
			if FileAccess.file_exists(path):
				return path

	# Try GameManager registry
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_level_path"):
		var path: String = gm.get_level_path(level_id)
		if not path.is_empty() and FileAccess.file_exists(path):
			return path

	return ""
