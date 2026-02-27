## GameManager — Autoload singleton for game-wide state management
##
## Handles:
## - Act/level progression
## - Save/load player data
## - Level transitions
## - Settings
##
## This is registered as an autoload in project.godot
## so it persists across scene changes.

extends Node

# Preload required classes
const HallTreeData = preload("res://src/core/hall_tree_data.gd")
const HallProgressionEngine = preload("res://src/core/hall_progression_engine.gd")

# --- Signals ---
signal level_started(level_id: String)
signal level_completed_signal(level_id: String)
signal act_completed(act: int)
signal map_requested()

# --- Player State ---
var current_act: int = 1
var current_level: int = 1
var current_layer: int = 1  ## Active layer (1-5). Set before transitioning to LevelScene.
var completed_levels: Array[String] = []
var level_states: Dictionary = {}  # level_id -> {found_keys, time_spent, attempts, layer_progress}
var _save_flags: Dictionary = {}   # Persistent boolean flags (e.g. "first_inner_door_opened")

# --- Settings ---
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var fullscreen: bool = false

# --- Save Path ---
const SAVE_PATH := "user://save_data.json"

# --- Level Registry ---
## Maps level IDs to file paths
var level_registry: Dictionary = {}

# --- Hall Tree (world map graph) ---
## Loaded from data/hall_tree.json on startup
var hall_tree = null  # HallTreeData instance (type removed to avoid parse error)
var progression = null  # HallProgressionEngine instance
var current_hall_id: String = ""  ## Set before transitioning to LevelScene


func _ready() -> void:
	# Build level registry
	_build_level_registry()

	# Load saved progress
	load_game()

	# Load hall tree (world map graph)
	_load_hall_tree()


func _build_level_registry() -> void:
	# Register all known levels, using meta.id from JSON as registry key
	for act in range(1, 5):
		var act_dir = "res://data/levels/act%d/" % act
		var dir = DirAccess.open(act_dir)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".json"):
					var file_path = act_dir + file_name
					var meta_id: String = _read_level_meta_id(file_path)
					if meta_id != "":
						level_registry[meta_id] = file_path
					else:
						# Fallback: use filename without extension
						level_registry[file_name.replace(".json", "")] = file_path
				file_name = dir.get_next()
			dir.list_dir_end()


## Read just the meta.id from a level JSON file
func _read_level_meta_id(file_path: String) -> String:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_text) != OK:
		return ""
	if json.data is Dictionary:
		return json.data.get("meta", {}).get("id", "")
	return ""


## Get the file path for a level ID
func get_level_path(level_id: String) -> String:
	return level_registry.get(level_id, "")


## Load the hall tree world graph from data/hall_tree.json.
## Creates a HallProgressionEngine child node for progression tracking.
func _load_hall_tree() -> void:
	var path: String = "res://data/hall_tree.json"
	if not FileAccess.file_exists(path):
		push_warning("GameManager: hall_tree.json not found, using linear fallback")
		return

	hall_tree = HallTreeData.new()
	if not hall_tree.load_from_file(path):
		push_warning("GameManager: Failed to load hall_tree.json, using linear fallback")
		hall_tree = null
		return

	# Validate
	var errors: Array = hall_tree.validate()
	if not errors.is_empty():
		push_warning("GameManager: hall_tree.json has %d validation errors:" % errors.size())
		for err in errors:
			push_warning("  - %s" % err)

	# Create progression engine
	progression = HallProgressionEngine.new()
	progression.name = "HallProgressionEngine"
	progression.hall_tree = hall_tree
	add_child(progression)


## Start the game — go to MapScene if hall tree is loaded,
## otherwise fall back to direct level loading.
func start_game() -> void:
	printerr("[GameManager] start_game() called")
	printerr("[GameManager] hall_tree = %s" % ("loaded" if hall_tree != null else "NULL"))
	if hall_tree != null:
		# Hall tree mode: go to map
		printerr("[GameManager] Going to map...")
		open_map()
	else:
		# Linear fallback
		printerr("[GameManager] No hall tree, falling back to direct level loading")
		var level_id: String = "act%d_level%02d" % [current_act, current_level]
		var level_path: String = get_level_path(level_id)

		if level_path == "":
			level_path = get_level_path("act1_level01")

		if level_path == "":
			push_error("GameManager: Cannot find any level to start!")
			return

		level_started.emit(level_id)
		get_tree().change_scene_to_file("res://src/game/level_scene.tscn")


## Open the world map scene.
func open_map() -> void:
	printerr("[GameManager] open_map() called")
	map_requested.emit()
	printerr("[GameManager] Calling change_scene_to_file(map_scene.tscn)...")
	var result = get_tree().change_scene_to_file("res://src/ui/map_scene.tscn")
	printerr("[GameManager] change_scene_to_file returned: %s (OK=%s)" % [result, OK])
	if result != OK:
		push_error("[GameManager] Failed to change scene! Error code: %d" % result)
	printerr("[GameManager] change_scene_to_file returned: %s" % result)


## Return to the main menu
func return_to_menu() -> void:
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")


## Return to the map scene (after completing a level)
func return_to_map() -> void:
	if hall_tree != null:
		open_map()
	else:
		return_to_menu()


## Mark a level as completed and advance current_act/current_level
func complete_level(level_id: String) -> void:
	if level_id not in completed_levels:
		completed_levels.append(level_id)

	# Advance current_act / current_level to the next one
	var next_info: Dictionary = _parse_level_id(level_id)
	if next_info.size() > 0:
		var act: int = next_info["act"]
		var lvl: int = next_info["level"]
		# Point to the next level so game resumes there
		var next_id: String = "act%d_level%02d" % [act, lvl + 1]
		if next_id in level_registry:
			current_act = act
			current_level = lvl + 1
		else:
			# Try first level of next act
			var next_act_id: String = "act%d_level%02d" % [act + 1, 1]
			if next_act_id in level_registry:
				current_act = act + 1
				current_level = 1
				act_completed.emit(act)

	# Notify progression engine about hall completion
	if progression != null:
		progression.complete_hall(level_id)

	level_completed_signal.emit(level_id)
	save_game()


## Check if a level is completed
func is_level_completed(level_id: String) -> bool:
	return level_id in completed_levels


## Get a persistent save flag (bool). Used for one-time events like "first inner door opened".
func get_save_flag(flag_name: String, default_value: bool = false) -> bool:
	return _save_flags.get(flag_name, default_value)


## Set a persistent save flag and auto-save.
func set_save_flag(flag_name: String, value: bool) -> void:
	_save_flags[flag_name] = value
	save_game()


## Get the file path for the next level after current_level_id.
## Returns "" if there are no more levels.
func get_next_level_path(current_level_id: String) -> String:
	var info: Dictionary = _parse_level_id(current_level_id)
	if info.is_empty():
		return ""

	var act: int = info["act"]
	var lvl: int = info["level"]

	# Try next level in same act
	var next_id: String = "act%d_level%02d" % [act, lvl + 1]
	if next_id in level_registry:
		return level_registry[next_id]

	# Try first level of next act
	var next_act_id: String = "act%d_level%02d" % [act + 1, 1]
	if next_act_id in level_registry:
		return level_registry[next_act_id]

	return ""


## Parse a level ID like "act1_level04" into {act: 1, level: 4}
func _parse_level_id(level_id: String) -> Dictionary:
	var parts = level_id.split("_")
	if parts.size() < 2:
		return {}
	var act_str = parts[0].replace("act", "")
	var lvl_str = parts[1].replace("level", "")
	if not act_str.is_valid_int() or not lvl_str.is_valid_int():
		return {}
	return {"act": int(act_str), "level": int(lvl_str)}


## Get layer progress for a specific hall and layer number.
## Returns: {status: "locked"/"available"/"in_progress"/"completed"/"perfect", ...}
func get_layer_progress(hall_id: String, layer: int) -> Dictionary:
	var state: Dictionary = level_states.get(hall_id, {})
	var lp: Dictionary = state.get("layer_progress", {})
	return lp.get("layer_%d" % layer, {"status": "locked"})


## Set layer progress for a specific hall and layer number.
## progress should be a dict like: {status: "completed", pairs_found: 2, total_pairs: 2}
func set_layer_progress(hall_id: String, layer: int, progress: Dictionary) -> void:
	if not level_states.has(hall_id):
		level_states[hall_id] = {}
	if not level_states[hall_id].has("layer_progress"):
		level_states[hall_id]["layer_progress"] = {}
	level_states[hall_id]["layer_progress"]["layer_%d" % layer] = progress
	save_game()


## Save game state to disk
func save_game() -> void:
	var save_data = {
		"player": {
			"current_act": current_act,
			"current_level": current_level,
			"current_layer": current_layer,
			"completed_levels": completed_levels,
			"level_states": level_states,
			"flags": _save_flags,
		},
		"settings": {
			"music_volume": music_volume,
			"sfx_volume": sfx_volume,
			"fullscreen": fullscreen,
		}
	}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "  "))
		file.close()


## Load game state from disk
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_warning("GameManager: Failed to load save data")
		return

	var data = json.data
	if data is Dictionary:
		var player = data.get("player", {})
		current_act = player.get("current_act", 1)
		current_level = player.get("current_level", 1)
		current_layer = player.get("current_layer", 1)
		completed_levels.assign(player.get("completed_levels", []))
		level_states = player.get("level_states", {})
		_save_flags = player.get("flags", {})

		var settings = data.get("settings", {})
		music_volume = settings.get("music_volume", 0.8)
		sfx_volume = settings.get("sfx_volume", 1.0)
		fullscreen = settings.get("fullscreen", false)
