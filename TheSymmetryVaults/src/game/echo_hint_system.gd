## EchoHintSystem — Three-level progressive hint system ("Эхо-подсказки")
##
## Implements the Echo Hint System from redesign.md (section 9):
##   Level 1 — Эхо-шёпот (Direction): vague hint after idle timeout
##   Level 2 — Эхо-голос (Structure): concrete hint after further idle
##   Level 3 — Эхо-видение (Solution): step-by-step + crystal glow pulsation
##
## Hints are framed as notes from a "previous researcher" for narrative immersion.
## Using Level 3 hint removes "Печать совершенства" (perfect seal).
##
## Usage:
##   var echo = EchoHintSystem.new()
##   add_child(echo)
##   echo.setup(level_data, hud_layer, crystals_dict)
##   # Call echo.notify_player_action() on any player interaction to reset idle timer.

class_name EchoHintSystem
extends Node

# --- Signals ---
## Emitted when a hint is shown. level: 1/2/3, text: hint text displayed.
signal hint_shown(level: int, text: String)
## Emitted when a hint is dismissed by the player.
signal hint_dismissed()
## Emitted when Level 3 hint is used — caller should mark "perfect seal" as lost.
signal perfect_seal_lost()

# --- Configuration ---
## Idle seconds before each echo level triggers.
## Level 1: 60s, Level 2: 120s after level start (60s after L1), Level 3: 180s (60s after L2).
const IDLE_THRESHOLDS := [60.0, 120.0, 180.0]

## Narrative prefix for each echo level (researcher's notes framing).
const ECHO_PREFIXES := [
	"Шёпот эха: ",       # Level 1 — whisper
	"Голос эха: ",        # Level 2 — voice
	"Видение эха: ",      # Level 3 — vision
]

## Colors for each echo level label (progressively more vivid).
const ECHO_COLORS := [
	Color(0.6, 0.65, 0.55, 0.85),   # L1: muted, dusty
	Color(0.75, 0.7, 0.45, 0.9),    # L2: warm amber
	Color(0.9, 0.8, 0.3, 0.95),     # L3: bright gold
]

# --- State ---
var _idle_time: float = 0.0          # Seconds since last player action
var _current_echo_level: int = 0     # 0 = no hint shown, 1/2/3 = hint level displayed
var _max_echo_used: int = 0          # Highest echo level ever shown this level
var _echo_hints: Array = []          # Parsed echo hints from level JSON (up to 3 entries)
var _target_crystal_ids: Array = []  # Crystal IDs to pulse for Level 3 vision
var _active: bool = false            # Whether the system is running
var _level_completed: bool = false   # Stop showing hints after level is done

# --- References ---
var _hud_layer: CanvasLayer = null
var _crystals: Dictionary = {}       # crystal_id -> CrystalNode
var _echo_panel: PanelContainer = null
var _echo_label: Label = null
var _echo_level_indicator: Label = null
var _dismiss_timer: Timer = null
var _pulse_tweens: Array = []        # Active glow tweens for Level 3


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _active or _level_completed:
		return

	_idle_time += delta

	# Check if next echo level should trigger
	var next_level: int = _current_echo_level + 1
	if next_level <= 3 and next_level <= _echo_hints.size():
		var threshold: float = IDLE_THRESHOLDS[next_level - 1]
		if _idle_time >= threshold:
			_show_echo(next_level)


## Initialize the echo system with level data and UI references.
## Call this after level is loaded and HUD is built.
func setup(level_data: Dictionary, hud_layer: CanvasLayer, crystals: Dictionary) -> void:
	_hud_layer = hud_layer
	_crystals = crystals
	_idle_time = 0.0
	_current_echo_level = 0
	_max_echo_used = 0
	_level_completed = false
	_echo_hints.clear()
	_target_crystal_ids.clear()

	# Parse echo hints from level data
	_parse_echo_hints(level_data)

	# Build the echo hint UI panel
	_build_echo_panel()

	_active = _echo_hints.size() > 0


## Notify the system that the player performed an action (swap, check, reset, combine).
## Resets the idle timer and dismisses currently shown hint.
func notify_player_action() -> void:
	_idle_time = 0.0
	if _echo_panel and _echo_panel.visible:
		_dismiss_echo()


## Notify the system that the level is completed. Stop all echo activity.
func notify_level_completed() -> void:
	_level_completed = true
	_active = false
	_dismiss_echo()
	_stop_crystal_pulses()


## Returns the highest echo level used during this level (0 = none, 3 = solution).
func get_max_echo_used() -> int:
	return _max_echo_used


## Returns true if the player used Level 3 (solution), losing perfect seal.
func used_solution_hint() -> bool:
	return _max_echo_used >= 3


## Clean up when removed from scene.
func cleanup() -> void:
	_stop_crystal_pulses()
	if _echo_panel and is_instance_valid(_echo_panel):
		_echo_panel.queue_free()
		_echo_panel = null
	_active = false


# --- Private: Hint Parsing ---

func _parse_echo_hints(level_data: Dictionary) -> void:
	var hints_data = level_data.get("echo_hints", [])

	# Fallback: if no echo_hints, try to convert legacy "hints" array
	if hints_data.is_empty():
		hints_data = _convert_legacy_hints(level_data.get("hints", []))

	for i in range(mini(hints_data.size(), 3)):
		var hint = hints_data[i]
		if hint is Dictionary:
			_echo_hints.append({
				"text": hint.get("text", ""),
				"target_crystals": hint.get("target_crystals", []),
			})
		elif hint is String:
			_echo_hints.append({
				"text": hint,
				"target_crystals": [],
			})

	# Extract target crystals from Level 3 if present
	if _echo_hints.size() >= 3:
		_target_crystal_ids = _echo_hints[2].get("target_crystals", [])


## Convert legacy flat hints array to echo_hints format.
## Maps: first "after_30_seconds_no_action" -> L1, others -> L2, L3.
func _convert_legacy_hints(legacy_hints: Array) -> Array:
	var result: Array = []
	for hint in legacy_hints:
		if hint is Dictionary:
			var text: String = hint.get("text", "")
			if text.is_empty():
				continue
			result.append({"text": text, "target_crystals": []})
	# Only keep up to 3
	if result.size() > 3:
		result.resize(3)
	return result


# --- Private: Echo Panel UI ---

func _build_echo_panel() -> void:
	if _hud_layer == null:
		return

	# Remove old panel if exists
	if _echo_panel and is_instance_valid(_echo_panel):
		_echo_panel.queue_free()

	# Container panel — centered at bottom of screen
	_echo_panel = PanelContainer.new()
	_echo_panel.name = "EchoHintPanel"
	_echo_panel.visible = false
	_echo_panel.position = Vector2(240, 640)
	_echo_panel.size = Vector2(800, 70)
	_echo_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Style: dark semi-transparent with subtle border
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.92)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_color = Color(0.5, 0.5, 0.3, 0.5)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_echo_panel.add_theme_stylebox_override("panel", style)

	# Inner VBox for level indicator + text
	var vbox = VBoxContainer.new()
	vbox.name = "EchoVBox"

	# Echo level indicator (small text: "Шёпот эха" / "Голос эха" / "Видение эха")
	_echo_level_indicator = Label.new()
	_echo_level_indicator.name = "EchoLevelIndicator"
	_echo_level_indicator.text = ""
	_echo_level_indicator.add_theme_font_size_override("font_size", 11)
	_echo_level_indicator.add_theme_color_override("font_color", Color(0.5, 0.55, 0.45, 0.7))
	vbox.add_child(_echo_level_indicator)

	# Main hint text
	_echo_label = Label.new()
	_echo_label.name = "EchoLabel"
	_echo_label.text = ""
	_echo_label.add_theme_font_size_override("font_size", 15)
	_echo_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5, 0.0))
	_echo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_echo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_echo_label)

	_echo_panel.add_child(vbox)
	_hud_layer.add_child(_echo_panel)

	# Connect click-to-dismiss
	_echo_panel.gui_input.connect(_on_echo_panel_input)


# --- Private: Show / Dismiss Echo ---

func _show_echo(level: int) -> void:
	if level < 1 or level > _echo_hints.size():
		return
	if _level_completed:
		return

	_current_echo_level = level
	_max_echo_used = maxi(_max_echo_used, level)

	var hint_data: Dictionary = _echo_hints[level - 1]
	var raw_text: String = hint_data.get("text", "")

	if raw_text.is_empty():
		return

	# Narrative framing: wrap with researcher's notes prefix
	var prefix: String = ECHO_PREFIXES[level - 1]
	var display_text: String = prefix + raw_text

	# Level indicator labels
	var level_names: Array = ["Шёпот эха", "Голос эха", "Видение эха"]

	# Update panel content
	if _echo_level_indicator:
		_echo_level_indicator.text = "— %s (уровень %d/3) —" % [level_names[level - 1], level]
		_echo_level_indicator.add_theme_color_override("font_color",
			ECHO_COLORS[level - 1].darkened(0.3))

	if _echo_label:
		_echo_label.text = display_text
		# Start transparent for fade-in
		_echo_label.add_theme_color_override("font_color",
			Color(ECHO_COLORS[level - 1].r, ECHO_COLORS[level - 1].g,
				  ECHO_COLORS[level - 1].b, 0.0))

	# Update panel border color to match echo level
	if _echo_panel:
		var style = _echo_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style = style.duplicate() as StyleBoxFlat
			new_style.border_color = ECHO_COLORS[level - 1].darkened(0.2)
			new_style.border_color.a = 0.6
			_echo_panel.add_theme_stylebox_override("panel", new_style)

		_echo_panel.visible = true
		# Fade in the label
		var tween = create_tween()
		tween.tween_property(_echo_label, "theme_override_colors/font_color",
			ECHO_COLORS[level - 1], 0.8).set_ease(Tween.EASE_OUT)

	# Level 3: start crystal pulsation for target crystals
	if level == 3:
		_start_crystal_pulses()
		# Emit signal that perfect seal is lost
		perfect_seal_lost.emit()

	hint_shown.emit(level, display_text)


func _dismiss_echo() -> void:
	if _echo_panel == null or not _echo_panel.visible:
		return

	# Fade out
	if _echo_label:
		var tween = create_tween()
		var target_color = _echo_label.get_theme_color("font_color")
		target_color.a = 0.0
		tween.tween_property(_echo_label, "theme_override_colors/font_color",
			target_color, 0.4).set_ease(Tween.EASE_IN)
		tween.tween_callback(_hide_echo_panel)

	# Stop Level 3 crystal pulses
	_stop_crystal_pulses()

	hint_dismissed.emit()


func _on_echo_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_dismiss_echo()


# --- Private: Crystal Pulse (Level 3 — Эхо-видение) ---

func _start_crystal_pulses() -> void:
	_stop_crystal_pulses()  # Clean up any existing

	# If specific target crystals are defined, pulse only those
	var ids_to_pulse: Array = _target_crystal_ids
	# If no specific targets, pulse all crystals as a general "look at everything" hint
	if ids_to_pulse.is_empty():
		ids_to_pulse = _crystals.keys()

	for crystal_id in ids_to_pulse:
		if crystal_id in _crystals:
			var crystal: CrystalNode = _crystals[crystal_id]
			_start_single_pulse(crystal)


func _start_single_pulse(crystal: CrystalNode) -> void:
	# Create a looping glow tween for the crystal
	var tween = create_tween()
	tween.set_loops()  # Infinite loop

	# Pulse: scale up slightly and glow, then back down
	tween.tween_callback(_pulse_crystal_glow.bind(crystal))
	tween.tween_interval(1.2)  # Wait between pulses

	_pulse_tweens.append(tween)


func _stop_crystal_pulses() -> void:
	for tween in _pulse_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_pulse_tweens.clear()


## Hide the echo panel — used as tween callback (avoids lambda/Stack underflow).
func _hide_echo_panel() -> void:
	if _echo_panel and is_instance_valid(_echo_panel):
		_echo_panel.visible = false


## Pulse a crystal's glow — used as tween callback (avoids lambda/Stack underflow).
func _pulse_crystal_glow(crystal: CrystalNode) -> void:
	if is_instance_valid(crystal):
		crystal.play_glow()
