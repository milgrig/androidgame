## AgentProtocol — JSON serialization for the AI Agent Bridge
##
## Pure-data class: no scene tree access, no side effects.
## Converts Godot nodes and game objects into dictionaries
## that an AI agent can understand.
##
## Design principle: serialize everything automatically.
## If a programmer adds a Button to the scene — the agent sees it.
## Nothing needs to be manually registered.

class_name AgentProtocol
extends RefCounted

const PROTOCOL_VERSION := "1.0.0"

# ──────────────────────────────────────────────
# Command parsing
# ──────────────────────────────────────────────

static func parse_command(json_str: String) -> Dictionary:
	## Parse a JSON command string into {cmd, args, id}.
	## Returns {error: "..."} on failure.
	var json := JSON.new()
	var err := json.parse(json_str.strip_edges())
	if err != OK:
		return {"error": "JSON parse error: %s" % json.get_error_message()}
	var data = json.data
	if not data is Dictionary:
		return {"error": "Command must be a JSON object"}
	if not data.has("cmd"):
		return {"error": "Command must have a 'cmd' field"}
	return {
		"cmd": data.get("cmd", ""),
		"args": data.get("args", {}),
		"id": data.get("id", 0),
	}


# ──────────────────────────────────────────────
# Response formatting
# ──────────────────────────────────────────────

static func success(data: Dictionary, events: Array = [], cmd_id: int = 0) -> String:
	var response := {"ok": true, "id": cmd_id, "data": data, "events": events}
	return JSON.stringify(response)


static func error(message: String, code: String = "ERROR", cmd_id: int = 0) -> String:
	var response := {"ok": false, "id": cmd_id, "error": message, "code": code}
	return JSON.stringify(response)


# ──────────────────────────────────────────────
# Generic node serialization (the "DOM" builder)
# ──────────────────────────────────────────────

static func serialize_tree(root: Node, max_depth: int = 20) -> Dictionary:
	## Recursively serialize entire scene tree from root.
	## This is the equivalent of browser DevTools "Elements" tab.
	return _serialize_node_recursive(root, 0, max_depth)


static func _serialize_node_recursive(node: Node, depth: int, max_depth: int) -> Dictionary:
	if depth > max_depth:
		return {"name": node.name, "type": node.get_class(), "_truncated": true}

	var result := _serialize_node_properties(node)

	# Recurse into children
	var children_data: Array = []
	for child in node.get_children():
		# Skip internal Godot nodes (start with @)
		if child.name.begins_with("@"):
			continue
		children_data.append(_serialize_node_recursive(child, depth + 1, max_depth))

	if not children_data.is_empty():
		result["children"] = children_data

	return result


static func _serialize_node_properties(node: Node) -> Dictionary:
	## Serialize a single node's properties based on its type.
	## Automatically detects type and extracts relevant data.
	var result := {
		"name": str(node.name),
		"class": node.get_class(),
		"path": str(node.get_path()),
	}

	# Custom game classes — check these first (most specific)
	if node.get_script():
		var script_name := ""
		var script: Script = node.get_script()
		if script.has_method("get_global_name"):
			script_name = script.get_global_name()
		if script_name.is_empty() and script.resource_path:
			script_name = script.resource_path.get_file().get_basename()
		if not script_name.is_empty():
			result["script_class"] = script_name

	# --- Game-specific types (detected by script class_name) ---

	# CrystalNode
	if node is CrystalNode:
		result["crystal_id"] = node.crystal_id
		result["color"] = node.get_crystal_color()
		result["label"] = node.label_text
		result["draggable"] = node.draggable
		result["position"] = _vec2_to_array(node.position)
		result["home_position"] = _vec2_to_array(node.get_home_position())
		result["radius"] = node.crystal_radius
		result["actions"] = _crystal_actions(node)

	# EdgeRenderer
	elif node is EdgeRenderer:
		result["from_node_id"] = node.from_node_id
		result["to_node_id"] = node.to_node_id
		result["edge_type"] = node.edge_type
		result["weight"] = node.weight

	# FeedbackFX
	elif node is FeedbackFX:
		pass  # Presence is enough; no inspectable state needed

	# CameraController
	elif node is CameraController:
		result["zoom"] = _vec2_to_array(node.zoom)
		result["position"] = _vec2_to_array(node.position)

	# --- Godot built-in UI types (automatic discovery) ---

	# Buttons (Button, TextureButton, CheckButton, etc.)
	elif node is BaseButton:
		result["disabled"] = node.disabled
		result["visible"] = node.visible
		result["actions"] = ["press"]
		if node is Button:
			result["text"] = node.text
		if node is CheckBox or node is CheckButton:
			result["pressed"] = node.button_pressed

	# Labels
	elif node is Label:
		result["text"] = node.text
		result["visible"] = node.visible

	# RichTextLabel
	elif node is RichTextLabel:
		result["text"] = node.get_parsed_text()
		result["visible"] = node.visible

	# TextEdit / LineEdit
	elif node is LineEdit:
		result["text"] = node.text
		result["placeholder"] = node.placeholder_text
		result["editable"] = node.editable
		result["visible"] = node.visible
		result["actions"] = ["set_text"]
	elif node is TextEdit:
		result["text"] = node.text
		result["editable"] = not node.editable
		result["visible"] = node.visible
		result["actions"] = ["set_text"]

	# Sliders / SpinBox
	elif node is Range:
		result["value"] = node.value
		result["min_value"] = node.min_value
		result["max_value"] = node.max_value
		result["step"] = node.step
		result["visible"] = node.visible
		result["actions"] = ["set_value"]

	# OptionButton / ItemList
	elif node is OptionButton:
		result["selected"] = node.selected
		result["visible"] = node.visible
		var items: Array = []
		for i in range(node.item_count):
			items.append(node.get_item_text(i))
		result["items"] = items
		result["actions"] = ["select"]

	# TabBar / TabContainer
	elif node is TabBar:
		result["current_tab"] = node.current_tab
		result["tab_count"] = node.tab_count
		var tabs: Array = []
		for i in range(node.tab_count):
			tabs.append(node.get_tab_title(i))
		result["tabs"] = tabs
		result["actions"] = ["select_tab"]

	# CanvasLayer (HUD, overlays)
	elif node is CanvasLayer:
		result["layer"] = node.layer
		result["visible"] = node.visible

	# Generic Node2D — position info
	elif node is Node2D:
		result["position"] = _vec2_to_array(node.position)
		result["visible"] = node.visible
		result["rotation"] = node.rotation
		result["scale"] = _vec2_to_array(node.scale)

	# Generic Control — position and size
	elif node is Control:
		result["position"] = _vec2_to_array(node.position)
		result["size"] = _vec2_to_array(node.size)
		result["visible"] = node.visible

	return result


# ──────────────────────────────────────────────
# Game object serialization
# ──────────────────────────────────────────────

static func serialize_crystal(crystal: CrystalNode) -> Dictionary:
	return {
		"id": crystal.crystal_id,
		"color": crystal.get_crystal_color(),
		"label": crystal.label_text,
		"position": _vec2_to_array(crystal.position),
		"home_position": _vec2_to_array(crystal.get_home_position()),
		"draggable": crystal.draggable,
		"radius": crystal.crystal_radius,
	}


static func serialize_edge(edge: EdgeRenderer) -> Dictionary:
	return {
		"from": edge.from_node_id,
		"to": edge.to_node_id,
		"type": edge.edge_type,
		"weight": edge.weight,
	}


static func serialize_keyring(kr: KeyRing) -> Dictionary:
	var found_list: Array = []
	for i in range(kr.count()):
		var p: Permutation = kr.get_key(i)
		found_list.append(serialize_permutation(p))
	return {
		"found": found_list,
		"found_count": kr.count(),
		"total": kr.target_count,
		"complete": kr.is_complete(),
		"has_identity": kr.has_identity(),
		"is_closed": kr.is_closed_under_composition() if kr.count() > 0 else false,
		"has_inverses": kr.has_inverses() if kr.count() > 0 else false,
	}


static func serialize_permutation(p: Permutation) -> Dictionary:
	return {
		"mapping": Array(p.mapping),
		"cycle_notation": p.to_cycle_notation(),
		"is_identity": p.is_identity(),
		"order": p.order(),
	}


static func serialize_graph(g: CrystalGraph) -> Dictionary:
	var nodes_data: Array = []
	for i in range(g.node_count()):
		nodes_data.append({
			"id": i,
			"color": g.get_node_color(i),
		})
	var edges_data: Array = []
	for edge in g.edges:
		edges_data.append({
			"from": edge.get("from", 0),
			"to": edge.get("to", 0),
			"type": edge.get("type", "standard"),
			"weight": edge.get("weight", 1),
		})
	return {
		"node_count": g.node_count(),
		"nodes": nodes_data,
		"edges": edges_data,
	}


# ──────────────────────────────────────────────
# Available commands list (self-describing protocol)
# ──────────────────────────────────────────────

static func get_command_catalog() -> Array:
	return [
		{"cmd": "hello", "description": "Handshake. Returns protocol version and command list."},
		{"cmd": "get_tree", "description": "Full scene tree (like browser DOM). Shows every node, button, label."},
		{"cmd": "get_state", "description": "Game state: crystals, edges, keyring, arrangement."},
		{"cmd": "list_actions", "description": "All actions available right now."},
		{"cmd": "list_levels", "description": "All available level IDs."},
		{"cmd": "load_level", "args": ["level_id"], "description": "Load a level by ID (e.g. 'act1_level01')."},
		{"cmd": "swap", "args": ["from", "to"], "description": "Swap two crystals by ID (like drag-and-drop)."},
		{"cmd": "submit_permutation", "args": ["mapping"], "description": "Submit a permutation directly (e.g. [1,2,0])."},
		{"cmd": "press_button", "args": ["path"], "description": "Press any button by its scene tree path."},
		{"cmd": "set_text", "args": ["path", "text"], "description": "Set text on any LineEdit/TextEdit by path."},
		{"cmd": "set_value", "args": ["path", "value"], "description": "Set value on any slider/spinbox by path."},
		{"cmd": "reset", "description": "Reset crystal arrangement to identity."},
		{"cmd": "repeat_key", "args": ["key_index"], "description": "Apply a found key by index to current arrangement (like pressing REPEAT)."},
		{"cmd": "get_node", "args": ["path"], "description": "Detailed info about one node by path."},
		{"cmd": "get_events", "description": "Drain the event queue (signals that fired)."},
		{"cmd": "select_keys", "args": ["indices"], "description": "Select keys by index on the inner door panel (Act 2). indices is an array of ints."},
		{"cmd": "try_open_door", "args": ["indices (optional)"], "description": "Try to open an inner door with selected keys. Optionally pass indices to select first."},
		{"cmd": "quit", "description": "Exit Godot."},
	]


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

static func _vec2_to_array(v: Vector2) -> Array:
	return [snapped(v.x, 0.01), snapped(v.y, 0.01)]


static func _crystal_actions(crystal: CrystalNode) -> Array:
	var actions: Array = []
	if crystal.draggable:
		actions.append("swap_to")
	return actions
