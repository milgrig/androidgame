## LevelScene — Main level controller that assembles and manages a puzzle level
##
## Responsibilities:
## - Load level data from JSON
## - Instantiate CrystalNode and EdgeRenderer instances
## - Handle drag-and-drop crystal swap interactions
## - Use core engine (Permutation, CrystalGraph, KeyRing) for validation
## - Trigger visual feedback via FeedbackFX
## - Track discovered symmetries via KeyRing
## - Check win condition (all automorphisms found)

class_name LevelScene
extends Node2D

# Preload required classes
const EchoHintSystem = preload("res://src/game/echo_hint_system.gd")
const TargetPreviewDraw = preload("res://src/visual/target_preview_draw.gd")
const InnerDoorVisualScene = preload("res://src/visual/inner_door_visual.gd")
const SubgroupSelectorScene = preload("res://src/ui/subgroup_selector.gd")
const InnerDoorPanelScene = preload("res://src/game/inner_door_panel.gd")

# --- Signals for game state integration ---
## Emitted when player performs a swap. Core engine should validate.
signal swap_performed(permutation: Array)
## Emitted when a valid symmetry is discovered
signal symmetry_found(symmetry_id: String, mapping: Array)
## Emitted when all symmetries are found (level complete)
signal level_completed(level_id: String)
## Emitted when an invalid permutation is attempted
signal invalid_attempt(mapping: Array)

# --- Scene references ---
var crystal_container: Node2D
var edge_container: Node2D
var feedback_fx: FeedbackFX
var camera: CameraController
var hud_layer: CanvasLayer
var target_preview: Control  # TargetPreview HUD widget (goal miniature)

# --- Level Data ---
var level_data: Dictionary = {}
var level_id: String = ""

# --- Crystal Management ---
var crystals: Dictionary = {}  # crystal_id -> CrystalNode
var edges: Array[EdgeRenderer] = []
var crystal_positions: Dictionary = {}  # crystal_id -> position index (for tracking swaps)

# --- Game State (integrated with core engine from T004) ---
var current_arrangement: Array[int] = []  # Position i has crystal current_arrangement[i]
var key_ring: KeyRing = null              # Core engine: tracks found symmetries
var crystal_graph: CrystalGraph = null    # Core engine: graph for automorphism checks
var target_perms: Dictionary = {}         # sym_id -> Permutation (from level JSON)
var target_perm_names: Dictionary = {}    # sym_id -> display name
var target_perm_descriptions: Dictionary = {}  # sym_id -> description text
var total_symmetries: int = 0

# --- Agent Mode ---
## When true, animations are instant (duration=0) and resets are synchronous.
## Set by AgentBridge when --agent-mode is active.
var agent_mode: bool = false

# --- Tutorial / Onboarding State ---
var _instruction_panel_visible: bool = false
var _first_symmetry_celebrated: bool = false
var _swap_count: int = 0  # Track player swaps for progressive hints

# --- Cayley / Combine Keys ---
var _show_cayley_button: bool = false
var _combine_mode: bool = false
var _combine_first_index: int = -1  # index into key_ring.found

# --- Generators Hint ---
var _show_generators_hint: bool = false

# --- Repeat Key ---
var _active_repeat_key_index: int = -1  # Index into key_ring.found for the active repeat key
var _repeat_animating: bool = false     # True while repeat animation is playing

# --- Shuffled Start ---
var _shuffle_seed: int = 0                    # Seed for reproducible shuffle
var _initial_arrangement: Array[int] = []     # Shuffled starting arrangement (for RESET)
var _identity_arrangement: Array[int] = []    # Identity arrangement [0,1,...,n-1] (the GOAL)
var _identity_found: bool = false             # True once player finds identity (goal reached)

# --- First-key-is-identity rebasing ---
var _first_key_relabeled: bool = false  # True once we rebase so the first found key = "Тождество"
var _rebase_inverse: Permutation = null  # first_perm.inverse(), used to rebase all subsequent checks

# --- Inner Doors (Act 2) ---
var _inner_door_panel = null  # InnerDoorPanel instance (null if no inner doors)
var _subgroup_selector = null  # SubgroupSelector instance (enhanced UI panel)
var _inner_door_visuals: Array = []  # Array[InnerDoorVisual] on the game field
var _first_door_ever_opened: bool = false  # For "Момент понимания" (global, once per game)

# --- Echo Hint System ---
var echo_hint_system = null  # EchoHintSystem instance (type removed to avoid parse error)

# --- Preloaded scenes ---
var crystal_scene = preload("res://src/visual/crystal_node.tscn")
var edge_scene = preload("res://src/visual/edge_renderer.tscn")


func _ready() -> void:
	_setup_scene_structure()

	# Try to load the level
	if level_data.is_empty():
		# Check if coming from MapScene with a specific hall_id
		if GameManager.current_hall_id != "":
			var hall_path := GameManager.get_level_path(GameManager.current_hall_id)
			if hall_path != "":
				load_level_from_file(hall_path)
			else:
				push_warning("LevelScene: No level file for hall '%s'" % GameManager.current_hall_id)
				load_level_from_file("res://data/levels/act1/level_01.json")
		else:
			# Linear fallback: load player's saved level
			var saved_id := "act%d_level%02d" % [GameManager.current_act, GameManager.current_level]
			var saved_path := GameManager.get_level_path(saved_id)
			if saved_path != "":
				load_level_from_file(saved_path)
			else:
				load_level_from_file("res://data/levels/act1/level_01.json")


func _setup_scene_structure() -> void:
	# Create container nodes for organization
	edge_container = Node2D.new()
	edge_container.name = "EdgeContainer"
	add_child(edge_container)

	crystal_container = Node2D.new()
	crystal_container.name = "CrystalContainer"
	add_child(crystal_container)

	# Feedback FX layer
	feedback_fx = FeedbackFX.new()
	feedback_fx.name = "FeedbackFX"
	add_child(feedback_fx)

	# Camera
	camera = CameraController.new()
	camera.name = "Camera"
	add_child(camera)

	feedback_fx.set_camera_controller(camera)

	# HUD layer
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	hud_layer.layer = 10
	add_child(hud_layer)

	_setup_hud()


func _setup_hud() -> void:
	# Level number indicator (e.g. "Act 1  ·  Level 4")
	var level_number_label = Label.new()
	level_number_label.name = "LevelNumberLabel"
	level_number_label.text = ""
	level_number_label.add_theme_font_size_override("font_size", 12)
	level_number_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 0.8))
	level_number_label.position = Vector2(20, 8)
	level_number_label.size = Vector2(300, 18)
	hud_layer.add_child(level_number_label)

	# Level title label
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = ""
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 0.9))
	title_label.position = Vector2(20, 26)
	hud_layer.add_child(title_label)

	# Subtitle label
	var subtitle_label = Label.new()
	subtitle_label.name = "SubtitleLabel"
	subtitle_label.text = ""
	subtitle_label.add_theme_font_size_override("font_size", 14)
	subtitle_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
	subtitle_label.position = Vector2(20, 56)
	hud_layer.add_child(subtitle_label)

	# --- Target Preview (goal miniature in upper-left corner) ---
	target_preview = Control.new()
	target_preview.name = "TargetPreview"
	target_preview.position = Vector2(20, 80)
	target_preview.size = Vector2(150, 150)
	target_preview.custom_minimum_size = Vector2(150, 150)
	target_preview.visible = false
	target_preview.clip_contents = false
	target_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(target_preview)

	# Target preview border/background panel
	var target_bg = Panel.new()
	target_bg.name = "TargetBG"
	target_bg.position = Vector2.ZERO
	target_bg.size = Vector2(150, 150)
	target_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var target_style = StyleBoxFlat.new()
	target_style.bg_color = Color(0.04, 0.04, 0.08, 0.85)
	target_style.corner_radius_top_left = 8
	target_style.corner_radius_top_right = 8
	target_style.corner_radius_bottom_left = 8
	target_style.corner_radius_bottom_right = 8
	target_style.border_color = Color(0.75, 0.65, 0.2, 0.7)  # Gold border initially
	target_style.border_width_left = 2
	target_style.border_width_right = 2
	target_style.border_width_top = 2
	target_style.border_width_bottom = 2
	target_bg.add_theme_stylebox_override("panel", target_style)
	target_preview.add_child(target_bg)

	# "Цель" label above the miniature
	var target_title_label = Label.new()
	target_title_label.name = "TargetTitle"
	target_title_label.text = "Цель"
	target_title_label.add_theme_font_size_override("font_size", 11)
	target_title_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9))
	target_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_title_label.position = Vector2(0, 2)
	target_title_label.size = Vector2(150, 16)
	target_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_preview.add_child(target_title_label)

	# Keys counter (how many valid arrangements found)
	var counter_label = Label.new()
	counter_label.name = "CounterLabel"
	counter_label.text = "Ключи: 0 / 0"
	counter_label.add_theme_font_size_override("font_size", 18)
	counter_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.85))
	counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter_label.position = Vector2(1020, 15)
	counter_label.size = Vector2(240, 30)
	hud_layer.add_child(counter_label)

	# Key ring display (simple list of found symmetries)
	var keyring_label = Label.new()
	keyring_label.name = "KeyRingLabel"
	keyring_label.text = ""
	keyring_label.add_theme_font_size_override("font_size", 13)
	keyring_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6, 0.8))
	keyring_label.position = Vector2(880, 45)
	keyring_label.size = Vector2(400, 20)
	keyring_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(keyring_label)

	# Hint label (bottom center)
	var hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = ""
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5, 0.0))  # Initially transparent
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(340, 670)
	hint_label.size = Vector2(600, 40)
	hud_layer.add_child(hint_label)

	# --- Action Buttons (RESET and TEST PATTERN) ---

	# RESET button — returns crystals to identity arrangement
	var reset_btn = Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = "СБРОС"
	reset_btn.add_theme_font_size_override("font_size", 14)
	reset_btn.position = Vector2(20, 620)
	reset_btn.size = Vector2(120, 40)
	reset_btn.pressed.connect(_on_reset_pressed)
	hud_layer.add_child(reset_btn)

	# TEST CURRENT PATTERN button — validates current arrangement as-is
	# With shuffled start, the player must first ASSEMBLE the target arrangement
	# (identity) by swapping, then press this to discover the first key.
	var check_btn = Button.new()
	check_btn.name = "CheckButton"
	check_btn.text = "ПРОВЕРИТЬ УЗОР"
	check_btn.add_theme_font_size_override("font_size", 14)
	check_btn.position = Vector2(150, 620)
	check_btn.size = Vector2(190, 40)
	check_btn.tooltip_text = "Проверить, открывает ли текущее расположение кристаллов замок.\nСоберите картинку-цель и проверьте!"
	check_btn.pressed.connect(_on_check_pressed)
	hud_layer.add_child(check_btn)

	# Status label — shows current arrangement state
	var status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 0.7))
	status_label.position = Vector2(20, 590)
	status_label.size = Vector2(400, 25)
	hud_layer.add_child(status_label)

	# Violation tooltip — brief text explaining WHY a swap failed
	var violation_label = Label.new()
	violation_label.name = "ViolationLabel"
	violation_label.text = ""
	violation_label.add_theme_font_size_override("font_size", 14)
	violation_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35, 0.0))  # Initially transparent
	violation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	violation_label.position = Vector2(290, 640)
	violation_label.size = Vector2(700, 30)
	hud_layer.add_child(violation_label)

	# --- Instruction panel (shown at every level start) ---
	var instr_panel = Panel.new()
	instr_panel.name = "InstructionPanel"
	instr_panel.visible = false
	instr_panel.position = Vector2(190, 130)
	instr_panel.size = Vector2(900, 370)
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.06, 0.06, 0.12, 0.94)
	style_box.corner_radius_top_left = 14
	style_box.corner_radius_top_right = 14
	style_box.corner_radius_bottom_left = 14
	style_box.corner_radius_bottom_right = 14
	style_box.border_color = Color(0.35, 0.45, 0.75, 0.6)
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	instr_panel.add_theme_stylebox_override("panel", style_box)
	hud_layer.add_child(instr_panel)

	var instr_title = Label.new()
	instr_title.name = "InstrTitle"
	instr_title.text = ""
	instr_title.add_theme_font_size_override("font_size", 22)
	instr_title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1.0))
	instr_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr_title.position = Vector2(20, 18)
	instr_title.size = Vector2(860, 30)
	instr_panel.add_child(instr_title)

	var instr_goal = Label.new()
	instr_goal.name = "InstrGoal"
	instr_goal.text = ""
	instr_goal.add_theme_font_size_override("font_size", 17)
	instr_goal.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5, 1.0))
	instr_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr_goal.position = Vector2(40, 58)
	instr_goal.size = Vector2(820, 28)
	instr_panel.add_child(instr_goal)

	var instr_body = Label.new()
	instr_body.name = "InstrBody"
	instr_body.text = ""
	instr_body.add_theme_font_size_override("font_size", 15)
	instr_body.add_theme_color_override("font_color", Color(0.72, 0.77, 0.88, 0.95))
	instr_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr_body.position = Vector2(50, 98)
	instr_body.size = Vector2(800, 150)
	instr_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instr_panel.add_child(instr_body)

	var instr_new = Label.new()
	instr_new.name = "InstrNewMechanic"
	instr_new.text = ""
	instr_new.add_theme_font_size_override("font_size", 15)
	instr_new.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.9))
	instr_new.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr_new.position = Vector2(50, 265)
	instr_new.size = Vector2(800, 30)
	instr_panel.add_child(instr_new)

	var instr_dismiss = Label.new()
	instr_dismiss.name = "InstrDismiss"
	instr_dismiss.text = "Нажмите в любом месте, чтобы начать"
	instr_dismiss.add_theme_font_size_override("font_size", 13)
	instr_dismiss.add_theme_color_override("font_color", Color(0.55, 0.65, 0.5, 0.75))
	instr_dismiss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr_dismiss.position = Vector2(20, 320)
	instr_dismiss.size = Vector2(860, 25)
	instr_panel.add_child(instr_dismiss)

	# Help "?" button — re-opens instruction panel
	var help_btn = Button.new()
	help_btn.name = "HelpButton"
	help_btn.text = "?"
	help_btn.add_theme_font_size_override("font_size", 18)
	help_btn.position = Vector2(1235, 15)
	help_btn.size = Vector2(35, 35)
	var help_style = StyleBoxFlat.new()
	help_style.bg_color = Color(0.15, 0.18, 0.28, 0.8)
	help_style.corner_radius_top_left = 16
	help_style.corner_radius_top_right = 16
	help_style.corner_radius_bottom_left = 16
	help_style.corner_radius_bottom_right = 16
	help_style.border_color = Color(0.4, 0.5, 0.7, 0.5)
	help_style.border_width_left = 1
	help_style.border_width_right = 1
	help_style.border_width_top = 1
	help_style.border_width_bottom = 1
	help_btn.add_theme_stylebox_override("normal", help_style)
	help_btn.pressed.connect(_show_instruction_panel)
	hud_layer.add_child(help_btn)

	# --- Button hint labels (small text near buttons explaining what they do) ---
	var reset_hint = Label.new()
	reset_hint.name = "ResetHintLabel"
	reset_hint.text = ""
	reset_hint.add_theme_font_size_override("font_size", 11)
	reset_hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8, 0.0))  # Initially transparent
	reset_hint.position = Vector2(20, 662)
	reset_hint.size = Vector2(120, 20)
	hud_layer.add_child(reset_hint)

	var check_hint = Label.new()
	check_hint.name = "CheckHintLabel"
	check_hint.text = ""
	check_hint.add_theme_font_size_override("font_size", 11)
	check_hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8, 0.0))  # Initially transparent
	check_hint.position = Vector2(150, 662)
	check_hint.size = Vector2(190, 20)
	hud_layer.add_child(check_hint)

	# REPEAT button — removed (repeat is now per-key in the key list)

	# COMBINE KEYS button — removed (was distracting from core gameplay)

	# Container for clickable key buttons (replaces coordinate-based hit detection)
	var key_buttons_container = VBoxContainer.new()
	key_buttons_container.name = "KeyButtonsContainer"
	key_buttons_container.position = Vector2(880, 65)
	key_buttons_container.size = Vector2(380, 280)
	key_buttons_container.visible = false
	key_buttons_container.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_layer.add_child(key_buttons_container)

	# Combine mode status label
	var combine_label = Label.new()
	combine_label.name = "CombineLabel"
	combine_label.text = ""
	combine_label.add_theme_font_size_override("font_size", 14)
	combine_label.add_theme_color_override("font_color", Color(0.8, 0.7, 1.0, 0.0))
	combine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combine_label.position = Vector2(290, 590)
	combine_label.size = Vector2(700, 25)
	hud_layer.add_child(combine_label)

	# Generators panel (shown on level complete if show_generators_hint is true)
	var gen_panel = Panel.new()
	gen_panel.name = "GeneratorsPanel"
	gen_panel.visible = false
	gen_panel.position = Vector2(340, 140)
	gen_panel.size = Vector2(600, 120)
	var gen_style = StyleBoxFlat.new()
	gen_style.bg_color = Color(0.06, 0.08, 0.16, 0.92)
	gen_style.corner_radius_top_left = 10
	gen_style.corner_radius_top_right = 10
	gen_style.corner_radius_bottom_left = 10
	gen_style.corner_radius_bottom_right = 10
	gen_style.border_color = Color(0.5, 0.7, 0.4, 0.6)
	gen_style.border_width_left = 2
	gen_style.border_width_right = 2
	gen_style.border_width_top = 2
	gen_style.border_width_bottom = 2
	gen_panel.add_theme_stylebox_override("panel", gen_style)
	hud_layer.add_child(gen_panel)

	var gen_title = Label.new()
	gen_title.name = "GenTitle"
	gen_title.text = "Генераторы"
	gen_title.add_theme_font_size_override("font_size", 18)
	gen_title.add_theme_color_override("font_color", Color(0.5, 0.9, 0.4, 1.0))
	gen_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gen_title.position = Vector2(20, 12)
	gen_title.size = Vector2(560, 28)
	gen_panel.add_child(gen_title)

	var gen_body = Label.new()
	gen_body.name = "GenBody"
	gen_body.text = ""
	gen_body.add_theme_font_size_override("font_size", 14)
	gen_body.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.95))
	gen_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gen_body.position = Vector2(20, 45)
	gen_body.size = Vector2(560, 60)
	gen_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gen_panel.add_child(gen_body)

	# --- Level Complete Summary Panel ---
	var summary_panel = Panel.new()
	summary_panel.name = "CompleteSummaryPanel"
	summary_panel.visible = false
	summary_panel.position = Vector2(240, 60)
	summary_panel.size = Vector2(800, 560)
	var sum_style = StyleBoxFlat.new()
	sum_style.bg_color = Color(0.05, 0.07, 0.13, 0.95)
	sum_style.corner_radius_top_left = 14
	sum_style.corner_radius_top_right = 14
	sum_style.corner_radius_bottom_left = 14
	sum_style.corner_radius_bottom_right = 14
	sum_style.border_color = Color(0.3, 0.9, 0.4, 0.6)
	sum_style.border_width_left = 2
	sum_style.border_width_right = 2
	sum_style.border_width_top = 2
	sum_style.border_width_bottom = 2
	summary_panel.add_theme_stylebox_override("panel", sum_style)
	hud_layer.add_child(summary_panel)

	var sum_title = Label.new()
	sum_title.name = "SummaryTitle"
	sum_title.text = ""
	sum_title.add_theme_font_size_override("font_size", 24)
	sum_title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 1.0))
	sum_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum_title.position = Vector2(20, 16)
	sum_title.size = Vector2(760, 35)
	summary_panel.add_child(sum_title)

	var sum_level = Label.new()
	sum_level.name = "SummaryLevelInfo"
	sum_level.text = ""
	sum_level.add_theme_font_size_override("font_size", 16)
	sum_level.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.9))
	sum_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum_level.position = Vector2(20, 55)
	sum_level.size = Vector2(760, 25)
	summary_panel.add_child(sum_level)

	var sum_group = Label.new()
	sum_group.name = "SummaryGroupInfo"
	sum_group.text = ""
	sum_group.add_theme_font_size_override("font_size", 15)
	sum_group.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5, 0.9))
	sum_group.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum_group.position = Vector2(20, 82)
	sum_group.size = Vector2(760, 25)
	summary_panel.add_child(sum_group)

	var sum_divider = Panel.new()
	sum_divider.name = "SummaryDivider"
	sum_divider.position = Vector2(80, 115)
	sum_divider.size = Vector2(640, 2)
	var div_style = StyleBoxFlat.new()
	div_style.bg_color = Color(0.3, 0.4, 0.6, 0.4)
	sum_divider.add_theme_stylebox_override("panel", div_style)
	summary_panel.add_child(sum_divider)

	var sum_keys_title = Label.new()
	sum_keys_title.name = "SummaryKeysTitle"
	sum_keys_title.text = "Найденные ключи:"
	sum_keys_title.add_theme_font_size_override("font_size", 14)
	sum_keys_title.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 0.8))
	sum_keys_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum_keys_title.position = Vector2(20, 125)
	sum_keys_title.size = Vector2(760, 22)
	summary_panel.add_child(sum_keys_title)

	var sum_keys_list = Label.new()
	sum_keys_list.name = "SummaryKeysList"
	sum_keys_list.text = ""
	sum_keys_list.add_theme_font_size_override("font_size", 14)
	sum_keys_list.add_theme_color_override("font_color", Color(0.72, 0.8, 0.68, 0.95))
	sum_keys_list.position = Vector2(60, 152)
	sum_keys_list.size = Vector2(680, 240)
	sum_keys_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_panel.add_child(sum_keys_list)

	var sum_learned = Label.new()
	sum_learned.name = "SummaryLearnedNote"
	sum_learned.text = ""
	sum_learned.add_theme_font_size_override("font_size", 13)
	sum_learned.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8, 0.8))
	sum_learned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum_learned.position = Vector2(40, 400)
	sum_learned.size = Vector2(720, 45)
	sum_learned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_panel.add_child(sum_learned)

	var sum_gen_info = Label.new()
	sum_gen_info.name = "SummaryGenInfo"
	sum_gen_info.text = ""
	sum_gen_info.add_theme_font_size_override("font_size", 13)
	sum_gen_info.add_theme_color_override("font_color", Color(0.5, 0.9, 0.4, 0.85))
	sum_gen_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum_gen_info.position = Vector2(40, 448)
	sum_gen_info.size = Vector2(720, 40)
	sum_gen_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_panel.add_child(sum_gen_info)

	var sum_next_btn = Button.new()
	sum_next_btn.name = "SummaryNextButton"
	# Use map-appropriate text if hall tree is loaded
	if GameManager.hall_tree != null:
		sum_next_btn.text = "ВЕРНУТЬСЯ НА КАРТУ"
	else:
		sum_next_btn.text = "СЛЕДУЮЩИЙ УРОВЕНЬ  >"
	sum_next_btn.add_theme_font_size_override("font_size", 20)
	sum_next_btn.position = Vector2(200, 495)
	sum_next_btn.size = Vector2(400, 50)
	sum_next_btn.visible = false
	sum_next_btn.pressed.connect(_on_next_level_pressed)
	summary_panel.add_child(sum_next_btn)


# --- Level Loading ---

## Load a level from a JSON file path
func load_level_from_file(file_path: String) -> void:
	if not FileAccess.file_exists(file_path):
		push_error("LevelScene: Level file not found: %s" % file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("LevelScene: Failed to parse JSON: %s" % json.get_error_message())
		return

	level_data = json.data
	_build_level()


## Load level from a pre-parsed dictionary
func load_level_from_data(data: Dictionary) -> void:
	level_data = data
	_build_level()


func _build_level() -> void:
	# Clear existing level
	_clear_level()

	if level_data.is_empty():
		return

	# Extract metadata
	var meta = level_data.get("meta", {})
	level_id = meta.get("id", "unknown")
	var title = meta.get("title", "Без названия")
	var subtitle = meta.get("subtitle", "")

	# Update HUD
	var level_number_label = hud_layer.get_node_or_null("LevelNumberLabel")
	if level_number_label:
		var act_num: int = meta.get("act", 1)
		var lvl_num: int = meta.get("level", 1)
		level_number_label.text = "Акт %d  ·  Уровень %d" % [act_num, lvl_num]
	var title_label = hud_layer.get_node_or_null("TitleLabel")
	if title_label:
		title_label.text = title
	var subtitle_label = hud_layer.get_node_or_null("SubtitleLabel")
	if subtitle_label:
		subtitle_label.text = subtitle

	# Build core engine objects from level data
	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var edges_data = graph_data.get("edges", [])

	# Create CrystalGraph for engine-based automorphism validation
	var gd_nodes: Array[Dictionary] = []
	for n in nodes_data:
		gd_nodes.append(n)
	var gd_edges: Array[Dictionary] = []
	for e in edges_data:
		gd_edges.append(e)
	crystal_graph = CrystalGraph.new(gd_nodes, gd_edges)

	# Parse target symmetries from JSON and build Permutation objects
	var symmetries_data = level_data.get("symmetries", {})
	var automorphisms = symmetries_data.get("automorphisms", [])
	total_symmetries = automorphisms.size()
	target_perms.clear()
	target_perm_names.clear()
	target_perm_descriptions.clear()
	for auto in automorphisms:
		var sym_id: String = auto.get("id", "")
		var perm := Permutation.from_array(auto.get("mapping", []))
		target_perms[sym_id] = perm
		target_perm_names[sym_id] = auto.get("name", sym_id)
		target_perm_descriptions[sym_id] = auto.get("description", "")

	# Initialize KeyRing from core engine
	key_ring = KeyRing.new(total_symmetries)

	_update_counter()

	# Calculate viewport center offset for positioning
	var viewport_size = get_viewport_rect().size
	var center_offset = viewport_size / 2.0

	# Build position map: node_id -> world position
	var positions_map: Dictionary = {}  # node_id -> Vector2
	for node_data in nodes_data:
		var node_id: int = node_data.get("id", 0)
		var pos_arr = node_data.get("position", [0, 0])
		var pos: Vector2
		if pos_arr is Array and pos_arr.size() >= 2:
			pos = Vector2(pos_arr[0], pos_arr[1])
		else:
			pos = Vector2.ZERO
		# Scale positions: if they're normalized (-1 to 1 range), scale up
		if abs(pos.x) <= 2.0 and abs(pos.y) <= 2.0:
			pos = pos * 200.0 + center_offset
		positions_map[node_id] = pos

	# Build identity arrangement: [0, 1, 2, ..., n-1]
	_identity_arrangement.clear()
	for node_data in nodes_data:
		_identity_arrangement.append(node_data.get("id", 0))

	# Generate shuffled start arrangement (Fisher-Yates, guaranteed != identity)
	var n_nodes: int = _identity_arrangement.size()
	_shuffle_seed = _generate_shuffle_seed()
	var shuffle_perm: Array[int] = _generate_shuffle(n_nodes, _shuffle_seed)

	# Apply shuffle: current_arrangement[i] = identity[shuffle[i]]
	# This means crystal identity[shuffle[i]] is placed at position i
	_initial_arrangement.clear()
	current_arrangement.clear()
	for i in range(n_nodes):
		_initial_arrangement.append(_identity_arrangement[shuffle_perm[i]])
		current_arrangement.append(_identity_arrangement[shuffle_perm[i]])

	_identity_found = false
	_first_key_relabeled = false
	_rebase_inverse = null

	# Create crystals at SHUFFLED positions
	for i in range(n_nodes):
		var crystal_id: int = current_arrangement[i]
		# Find the node_data for this crystal_id to get its color/label
		var node_data: Dictionary = {}
		for nd in nodes_data:
			if nd.get("id", -1) == crystal_id:
				node_data = nd
				break

		var crystal = crystal_scene.instantiate() as CrystalNode
		crystal.crystal_id = crystal_id
		crystal.set_crystal_color(node_data.get("color", "blue"))
		crystal.set_label(node_data.get("label", ""))

		# Crystal is placed at position i (which is the slot for identity[i])
		var slot_id: int = _identity_arrangement[i]
		var pos: Vector2 = positions_map.get(slot_id, Vector2.ZERO)
		crystal.position = pos
		crystal.set_home_position(pos)

		# Connect signals
		crystal.crystal_dropped_on.connect(_on_crystal_dropped)
		crystal.drag_started.connect(_on_crystal_drag_started)
		crystal.drag_cancelled.connect(_on_crystal_drag_cancelled)

		crystal_container.add_child(crystal)
		crystals[crystal_id] = crystal

	# Setup target preview miniature
	_setup_target_preview(nodes_data, edges_data)

	# Create edges
	for edge_data in edges_data:
		var edge = edge_scene.instantiate() as EdgeRenderer
		var from_id: int = edge_data.get("from", 0)
		var to_id: int = edge_data.get("to", 0)
		var edge_type: String = edge_data.get("type", "standard")

		edge.from_node_id = from_id
		edge.to_node_id = to_id
		edge.set_edge_type(edge_type)
		edge.weight = edge_data.get("weight", 1)
		edge.directed = edge_data.get("directed", false)

		# Bind to crystal nodes
		if from_id in crystals and to_id in crystals:
			edge.bind_crystals(crystals[from_id], crystals[to_id])

		edge_container.add_child(edge)
		edges.append(edge)

	# Center camera on graph
	var positions: Array[Vector2] = []
	for crystal in crystals.values():
		positions.append(crystal.position)
	if not positions.is_empty():
		camera.center_on_points(positions, 150.0)

	# Read mechanics flags
	var mechanics = level_data.get("mechanics", {})
	_show_cayley_button = mechanics.get("show_cayley_button", false)
	_show_generators_hint = mechanics.get("show_generators_hint", false)
	_combine_mode = false
	_combine_first_index = -1

	# Reset repeat key state
	_active_repeat_key_index = -1
	_repeat_animating = false

	# Hide repeat button initially (shown in _update_counter when keys found)
	var repeat_btn = hud_layer.get_node_or_null("RepeatButton")
	if repeat_btn:
		repeat_btn.visible = false

	# Hide combine button initially (shown in _update_counter when conditions met)
	var combine_btn = hud_layer.get_node_or_null("CombineButton")
	if combine_btn:
		combine_btn.visible = false

	# Hide generators panel
	var gen_panel = hud_layer.get_node_or_null("GeneratorsPanel")
	if gen_panel:
		gen_panel.visible = false

	# Hide summary panel from previous level
	var summary_panel = hud_layer.get_node_or_null("CompleteSummaryPanel")
	if summary_panel:
		summary_panel.visible = false

	# Update status to show identity hint at start
	_update_status_label()

	# Initialize Echo Hint System (replaces legacy hint timer)
	_setup_echo_hints()

	# Start legacy hint timer as fallback for trigger-based hints
	_start_hint_timer()

	# Show instruction panel on every level start (unless in agent mode)
	_first_symmetry_celebrated = false
	_swap_count = 0
	if not agent_mode:
		_show_instruction_panel()
		# Enable idle pulse on Act 1 levels to hint crystals are draggable
		var act: int = meta.get("act", 0)
		if act == 1:
			for crystal in crystals.values():
				if crystal is CrystalNode:
					crystal.set_idle_pulse(true)
			_show_button_hints()

	# Inner Doors (Act 2) — setup after all other UI
	var inner_doors_data: Array = mechanics.get("inner_doors", [])
	var subgroups_list: Array = level_data.get("subgroups", [])
	if inner_doors_data.size() > 0 and inner_doors_data[0] is Dictionary:
		_setup_inner_doors(inner_doors_data, subgroups_list)


# --- Inner Doors (Act 2) ---

func _setup_inner_doors(doors_data: Array, subgroups_list: Array) -> void:
	## Create and configure the inner door UI for Act 2 levels.
	## Sets up:
	## 1. InnerDoorPanel (logic, hidden)
	## 2. SubgroupSelector (enhanced HUD panel with mini diagrams)
	## 3. InnerDoorVisual instances on the game field

	# 1. Logic panel (hidden — SubgroupSelector wraps it)
	_inner_door_panel = InnerDoorPanelScene.new()
	_inner_door_panel.name = "InnerDoorPanel"
	_inner_door_panel.visible = false
	_inner_door_panel.setup(doors_data, subgroups_list, key_ring, self)
	_inner_door_panel.door_opened.connect(_on_inner_door_opened)
	_inner_door_panel.door_attempt_failed.connect(_on_inner_door_failed)
	hud_layer.add_child(_inner_door_panel)

	# 2. SubgroupSelector (enhanced visual panel in HUD)
	_subgroup_selector = SubgroupSelectorScene.new()
	_subgroup_selector.name = "SubgroupSelector"
	_subgroup_selector.position = Vector2(880, 360)
	_subgroup_selector.size = Vector2(360, 340)
	_subgroup_selector.setup(doors_data, subgroups_list, key_ring, self)
	_subgroup_selector.door_open_requested.connect(_on_selector_door_open)
	_subgroup_selector.subgroup_validated.connect(_on_subgroup_validated)
	hud_layer.add_child(_subgroup_selector)

	# 3. InnerDoorVisual on the game field (between crystal clusters)
	_inner_door_visuals.clear()
	var graph_data: Dictionary = level_data.get("graph", {})
	var nodes_array: Array = graph_data.get("nodes", [])

	for door in doors_data:
		var door_visual: Node2D = InnerDoorVisualScene.new()
		var door_id: String = door.get("id", "")
		var visual_hint: String = door.get("visual_hint", "")

		# Find required subgroup order
		var req_sg: String = door.get("required_subgroup", "")
		var sg_order: int = 0
		for sg in subgroups_list:
			if sg.get("name", "") == req_sg:
				sg_order = sg.get("order", 0)
				break

		# Calculate position: centroid of all crystal nodes
		var centroid := Vector2.ZERO
		if nodes_array.size() > 0:
			for node_data in nodes_array:
				var pos_arr: Array = node_data.get("position", [0, 0])
				centroid += Vector2(pos_arr[0], pos_arr[1])
			centroid /= float(nodes_array.size())
			# Offset slightly to not overlap crystals
			centroid += Vector2(0, 60)

		door_visual.setup(door_id, visual_hint, sg_order, centroid)
		door_visual.door_clicked.connect(_on_door_visual_clicked)
		edge_container.add_child(door_visual)
		_inner_door_visuals.append(door_visual)

	# Check if first door was ever opened (from save data)
	_first_door_ever_opened = GameManager.get_save_flag("first_inner_door_opened", false)


func _on_selector_door_open(door_id: String, _selected_indices: Array) -> void:
	## Forwarded from SubgroupSelector when a door opens.
	_on_inner_door_opened(door_id)


func _on_subgroup_validated(is_valid: bool, _selected_indices: Array) -> void:
	## Visual feedback on the field when subgroup check happens.
	if is_valid:
		# Flash crystals green briefly
		for c in crystals.values():
			if c is CrystalNode:
				c.play_flash()
	else:
		# Shake the door visuals
		for dv in _inner_door_visuals:
			if dv.state == InnerDoorVisualScene.DoorState.LOCKED:
				dv.play_failure_animation()


func _on_door_visual_clicked(door_id: String) -> void:
	## When player clicks a door on the field — scroll to the selector panel.
	# Highlight the selector panel briefly
	if _subgroup_selector:
		var tween := create_tween()
		tween.tween_property(_subgroup_selector, "modulate", Color(1.3, 1.2, 0.8, 1.0), 0.15)
		tween.tween_property(_subgroup_selector, "modulate", Color(1, 1, 1, 1), 0.4)


func _on_inner_door_opened(door_id: String) -> void:
	## Handle a successfully opened inner door.
	# Play unlock animation on the field door visual
	for dv in _inner_door_visuals:
		if dv.door_id == door_id:
			dv.play_unlock_animation()

	# Update the subgroup selector display
	if _subgroup_selector:
		_subgroup_selector.refresh_doors()

	# Show celebration effects
	feedback_fx.play_valid_feedback(crystals.values(), edges)

	# "Момент понимания" — first door EVER opened in the game
	if not _first_door_ever_opened:
		_first_door_ever_opened = true
		GameManager.set_save_flag("first_inner_door_opened", true)
		_play_moment_of_understanding(door_id)
	else:
		# Regular door opening message
		var hint_label = hud_layer.get_node_or_null("HintLabel")
		if hint_label:
			hint_label.text = "Внутренняя дверь открыта!"
			hint_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.9))
			hint_label.visible = true
			var tween := create_tween()
			tween.tween_interval(3.0)
			tween.tween_callback(_fade_hint_label.bind(hint_label))

	# Update counter to show door progress
	_update_counter()

	# Check if all doors opened + all keys found → level complete
	if _inner_door_panel and _inner_door_panel.is_all_doors_opened() and key_ring and key_ring.is_complete():
		_on_level_complete()


func _on_inner_door_failed(door_id: String, reason: Dictionary) -> void:
	## Handle a failed inner door attempt.
	# Play invalid feedback on crystals
	for c in crystals.values():
		if c is CrystalNode:
			c.play_dim()
	# Play failure animation on door visuals
	for dv in _inner_door_visuals:
		if dv.door_id == door_id:
			dv.play_failure_animation()


func _play_moment_of_understanding(door_id: String) -> void:
	## "Момент понимания" — special celebration for the FIRST inner door ever opened.
	## Shows only once in the entire game (not per level).
	##
	## Sequence:
	## 1. Camera smoothly zooms to the door
	## 2. Highlight the keys that formed the subgroup
	## 3. Show insight text explaining subgroups
	## 4. Return camera to normal

	# Find the door visual position for camera focus
	var door_pos := Vector2.ZERO
	for dv in _inner_door_visuals:
		if dv.door_id == door_id:
			door_pos = dv.position
			break

	# 1. Smooth camera zoom to the door
	if camera:
		camera.move_to(door_pos, 0.8)

	# 2. Create the insight overlay panel
	var insight_panel := Panel.new()
	insight_panel.name = "MomentOfUnderstandingPanel"
	insight_panel.position = Vector2(240, 500)
	insight_panel.size = Vector2(800, 120)
	insight_panel.modulate = Color(1, 1, 1, 0)  # Start transparent

	var insight_style := StyleBoxFlat.new()
	insight_style.bg_color = Color(0.05, 0.04, 0.1, 0.95)
	insight_style.corner_radius_top_left = 12
	insight_style.corner_radius_top_right = 12
	insight_style.corner_radius_bottom_left = 12
	insight_style.corner_radius_bottom_right = 12
	insight_style.border_color = Color(0.85, 0.75, 0.3, 0.8)
	insight_style.border_width_left = 2
	insight_style.border_width_right = 2
	insight_style.border_width_top = 2
	insight_style.border_width_bottom = 2
	insight_panel.add_theme_stylebox_override("panel", insight_style)

	var insight_icon := Label.new()
	insight_icon.text = "✨"
	insight_icon.add_theme_font_size_override("font_size", 28)
	insight_icon.position = Vector2(20, 12)
	insight_icon.size = Vector2(40, 40)
	insight_panel.add_child(insight_icon)

	var insight_title := Label.new()
	insight_title.text = "Вы нашли подгруппу!"
	insight_title.add_theme_font_size_override("font_size", 20)
	insight_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
	insight_title.position = Vector2(70, 14)
	insight_title.size = Vector2(700, 30)
	insight_panel.add_child(insight_title)

	var insight_body := Label.new()
	insight_body.text = "Эти ключи замкнуты — любая комбинация двух из них даёт третий."
	insight_body.add_theme_font_size_override("font_size", 15)
	insight_body.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9, 0.95))
	insight_body.position = Vector2(70, 52)
	insight_body.size = Vector2(700, 26)
	insight_panel.add_child(insight_body)

	var insight_sub := Label.new()
	insight_sub.text = "Это фундаментальная идея алгебры: часть структуры сама образует структуру."
	insight_sub.add_theme_font_size_override("font_size", 13)
	insight_sub.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 0.8))
	insight_sub.position = Vector2(70, 82)
	insight_sub.size = Vector2(700, 22)
	insight_panel.add_child(insight_sub)

	hud_layer.add_child(insight_panel)

	# 3. Animate: fade in, hold, fade out
	var tween := create_tween()
	tween.tween_property(insight_panel, "modulate", Color(1, 1, 1, 1), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_interval(5.0)
	tween.tween_property(insight_panel, "modulate", Color(1, 1, 1, 0), 0.8)
	tween.tween_callback(_free_if_valid.bind(insight_panel))


func _is_level_complete() -> bool:
	## Check if the level is fully complete (all keys found + all doors opened for Act 2).
	if key_ring == null or not key_ring.is_complete():
		return false
	# For Act 2 levels with inner doors, all doors must also be opened
	if _inner_door_panel != null:
		return _inner_door_panel.is_all_doors_opened()
	return true


func _clear_level() -> void:
	# Clean up inner door panel and visuals
	if _inner_door_panel:
		_inner_door_panel.queue_free()
		_inner_door_panel = null
	if _subgroup_selector:
		_subgroup_selector.queue_free()
		_subgroup_selector = null
	for dv in _inner_door_visuals:
		if is_instance_valid(dv):
			dv.queue_free()
	_inner_door_visuals.clear()

	# Clean up echo hint system
	if echo_hint_system:
		echo_hint_system.cleanup()
		echo_hint_system.queue_free()
		echo_hint_system = null

	# Remove all crystals
	for crystal in crystals.values():
		crystal.queue_free()
	crystals.clear()

	# Remove all edges
	for edge in edges:
		edge.queue_free()
	edges.clear()

	current_arrangement.clear()
	_initial_arrangement.clear()
	_identity_arrangement.clear()
	_identity_found = false
	_first_key_relabeled = false
	_rebase_inverse = null
	if key_ring:
		key_ring.clear()
	target_perms.clear()
	target_perm_names.clear()
	target_perm_descriptions.clear()

	# Clear key buttons
	var key_container = hud_layer.get_node_or_null("KeyButtonsContainer") if hud_layer else null
	if key_container:
		for child in key_container.get_children():
			child.queue_free()
		key_container.visible = false


# --- Drag and Drop Handling ---

func _on_crystal_drag_started(crystal_id: int) -> void:
	# Dismiss instruction panel on first interaction
	_dismiss_instruction_panel()
	# Reset echo idle timer on any interaction
	_notify_echo_activity()

	# Visual feedback: highlight potential drop targets
	for id in crystals:
		if id != crystal_id:
			var crystal = crystals[id]
			# Subtle glow to show valid targets
			crystal.play_glow()


func _on_crystal_drag_cancelled(crystal_id: int) -> void:
	pass  # Crystal returns to home position automatically


func _on_crystal_dropped(from_id: int, to_id: int) -> void:
	# Player dropped crystal from_id onto crystal to_id — attempt swap
	if from_id == to_id:
		return

	if not (from_id in crystals and to_id in crystals):
		return

	var crystal_a = crystals[from_id]
	var crystal_b = crystals[to_id]

	# Perform the visual swap
	_perform_swap(crystal_a, crystal_b)


func _perform_swap(crystal_a: CrystalNode, crystal_b: CrystalNode) -> void:
	var pos_a = crystal_a.get_home_position()
	var pos_b = crystal_b.get_home_position()

	# Animate crystals swapping positions (instant in agent mode)
	var swap_duration := 0.0 if agent_mode else 0.35
	crystal_a.animate_to_position(pos_b, swap_duration)
	crystal_b.animate_to_position(pos_a, swap_duration)

	# Update home positions
	crystal_a.set_home_position(pos_b)
	crystal_b.set_home_position(pos_a)

	# Swap in our tracking array
	var idx_a = current_arrangement.find(crystal_a.crystal_id)
	var idx_b = current_arrangement.find(crystal_b.crystal_id)
	if idx_a >= 0 and idx_b >= 0:
		var temp = current_arrangement[idx_a]
		current_arrangement[idx_a] = current_arrangement[idx_b]
		current_arrangement[idx_b] = temp

	# Build Permutation object from current arrangement
	var perm := Permutation.from_array(current_arrangement)

	# Swap feedback particles
	feedback_fx.play_swap_feedback(crystal_a, crystal_b)

	# Track swap count for progressive hints
	_swap_count += 1

	# Reset echo idle timer on swap
	_notify_echo_activity()

	# Emit signal
	swap_performed.emit(current_arrangement.duplicate())

	# Validate the permutation using core engine
	_validate_permutation(perm)


## Validate a permutation using core engine objects (Permutation, KeyRing).
## Checks against the level's target automorphisms from JSON.
## show_invalid_feedback: if true, plays dim/red feedback when no match (used by CHECK button).
##   If false, stays silent on no match so swaps can accumulate (used after each swap).
func _validate_permutation(perm: Permutation, show_invalid_feedback: bool = false) -> void:
	# Rebase the permutation relative to the first found key (if any)
	var check_perm := perm
	if _rebase_inverse != null:
		check_perm = perm.compose(_rebase_inverse)

	# Check if this (rebased) permutation matches any target automorphism
	for sym_id in target_perms:
		var target_perm: Permutation = target_perms[sym_id]
		if check_perm.equals(target_perm):
			# It matches a known automorphism — store ORIGINAL perm in KeyRing
			# (so repeat applies the real permutation to move crystals)
			if key_ring.add_key(perm):
				# New symmetry discovered!

				# First found key becomes "Тождество" — set up rebasing
				if not _first_key_relabeled:
					_first_key_relabeled = true
					_relabel_first_key_as_identity(sym_id)

				symmetry_found.emit(sym_id, perm.mapping)
				feedback_fx.play_valid_feedback(crystals.values(), edges)
				_set_active_repeat_key_latest()
				_update_counter()
				_update_keyring_display()
				_update_status_label()

				# Track identity found — update target preview border to green
				# After rebase, check_perm.is_identity() means "first found arrangement"
				if check_perm.is_identity():
					_identity_found = true
					_update_target_preview_border()

				# Show encouraging message after first symmetry (onboarding)
				if not _first_symmetry_celebrated:
					_first_symmetry_celebrated = true
					_show_first_symmetry_message(sym_id)

				# Check triggered hints (after_first_valid, after_N_found)
				_check_triggered_hints()

				# Refresh inner door panel (new key available for subgroup selection)
				if _inner_door_panel:
					_inner_door_panel.refresh_keys()
				if _subgroup_selector:
					_subgroup_selector.refresh_keys()

				# Check win condition via KeyRing (+ inner doors for Act 2)
				if _is_level_complete():
					_on_level_complete()
				return
			else:
				# Already found — subtle positive feedback
				for c in crystals.values():
					if c is CrystalNode:
						c.play_glow()
				_update_status_label()
				return

	# No match — permutation is not a valid automorphism (yet).
	# Swaps accumulate: do NOT reset. Let the player keep experimenting.
	invalid_attempt.emit(perm.mapping)
	_update_status_label()

	if show_invalid_feedback:
		# Show detailed violation feedback highlighting WHY it failed
		if crystal_graph:
			var violations := crystal_graph.find_violations(perm)
			feedback_fx.play_violation_feedback(violations, crystals, edges, crystals.values())
			_show_violation_tooltip(violations.get("summary", ""))
		else:
			feedback_fx.play_invalid_feedback(crystals.values(), edges)


func _reset_arrangement() -> void:
	# Return all crystals to the SHUFFLED starting arrangement (not identity!)
	# This is "start over" — go back to the beginning, not to the answer.
	if _initial_arrangement.is_empty():
		return

	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var viewport_size = get_viewport_rect().size
	var center_offset = viewport_size / 2.0

	# Build position map
	var pos_map: Dictionary = {}
	for node_data in nodes_data:
		var node_id = node_data.get("id", 0)
		var pos_arr = node_data.get("position", [0, 0])
		var pos: Vector2
		if pos_arr is Array and pos_arr.size() >= 2:
			pos = Vector2(pos_arr[0], pos_arr[1])
		else:
			pos = Vector2.ZERO
		if abs(pos.x) <= 2.0 and abs(pos.y) <= 2.0:
			pos = pos * 200.0 + center_offset
		pos_map[node_id] = pos

	# Restore each crystal to its shuffled start position
	for i in range(_initial_arrangement.size()):
		var crystal_id: int = _initial_arrangement[i]
		var slot_id: int = _identity_arrangement[i]
		if crystal_id in crystals and slot_id in pos_map:
			var pos: Vector2 = pos_map[slot_id]
			var reset_duration := 0.0 if agent_mode else 0.3
			crystals[crystal_id].animate_to_position(pos, reset_duration)
			crystals[crystal_id].set_home_position(pos)

	# Reset tracking to initial shuffled arrangement
	current_arrangement = _initial_arrangement.duplicate()


# --- Button Handlers ---

## Called when the player presses the RESET button.
## Returns all crystals to the shuffled starting arrangement (not identity!).
func _on_reset_pressed() -> void:
	_reset_arrangement()
	_update_status_label()
	_notify_echo_activity()


## Called when the player presses the TEST PATTERN button.
## Validates the current arrangement as-is, with full feedback.
## With shuffled start, the player must first assemble the target
## arrangement by swapping crystals, then press this to validate.
func _on_check_pressed() -> void:
	_notify_echo_activity()
	var perm := Permutation.from_array(current_arrangement)
	# show_invalid_feedback=true so the player gets dim/red feedback if not valid
	_validate_permutation(perm, true)


## Called when the player presses the COMBINE KEYS button.
## Enters combine mode where the player selects two keys from the KeyRing.
func _on_combine_pressed() -> void:
	_notify_echo_activity()
	if _combine_mode:
		# Already in combine mode — toggle off
		_exit_combine_mode()
		return

	if key_ring == null or key_ring.count() < 2:
		return

	_combine_mode = true
	_combine_first_index = -1

	# Update KeyRing display with clickable indices
	_update_keyring_display_combine()

	# Show combine status
	var combine_label = hud_layer.get_node_or_null("CombineLabel")
	if combine_label:
		combine_label.text = "Выберите первый ключ (нажмите на номер в связке)..."
		var tween = create_tween()
		tween.tween_property(combine_label, "theme_override_colors/font_color",
			Color(0.8, 0.7, 1.0, 0.9), 0.25)

	# Change button text
	var combine_btn = hud_layer.get_node_or_null("CombineButton")
	if combine_btn:
		combine_btn.text = "ОТМЕНА"


## Select a key by index during combine mode. Called from KeyRing button clicks.
func _on_combine_key_selected(index: int) -> void:
	if not _combine_mode or key_ring == null:
		return

	if _combine_first_index < 0:
		# First selection
		_combine_first_index = index
		var combine_label = hud_layer.get_node_or_null("CombineLabel")
		if combine_label:
			var first_name := _get_key_display_name(index)
			combine_label.text = "Первый: %s. Теперь выберите второй ключ..." % first_name
		_update_keyring_display_combine()
	else:
		# Second selection — compose!
		var result_perm: Permutation = key_ring.compose_keys(_combine_first_index, index)

		var first_name := _get_key_display_name(_combine_first_index)
		var second_name := _get_key_display_name(index)

		# Exit combine mode before validating (which may trigger celebrations)
		_exit_combine_mode()

		# Check if result matches a target automorphism
		for sym_id in target_perms:
			var target_perm: Permutation = target_perms[sym_id]
			if result_perm.equals(target_perm):
				if key_ring.add_key(result_perm):
					# New symmetry discovered via combination!
					var result_name: String = target_perm_names.get(sym_id, result_perm.to_cycle_notation())
					symmetry_found.emit(sym_id, result_perm.mapping)
					feedback_fx.play_valid_feedback(crystals.values(), edges)
					_set_active_repeat_key_latest()
					_update_counter()
					_update_keyring_display()
					_update_status_label()
					_show_combine_result_message(first_name, second_name, result_name, true)
					_check_triggered_hints()
					# Refresh inner door panel (new key available for subgroup selection)
					if _inner_door_panel:
						_inner_door_panel.refresh_keys()
					if _is_level_complete():
						_on_level_complete()
				else:
					# Already known
					var result_name: String = target_perm_names.get(sym_id, result_perm.to_cycle_notation())
					_show_combine_result_message(first_name, second_name, result_name, false)
				return

		# Not a target automorphism (shouldn't happen if targets are correct)
		_show_combine_result_message(first_name, second_name, result_perm.to_cycle_notation(), false)


func _exit_combine_mode() -> void:
	_combine_mode = false
	_combine_first_index = -1
	_update_keyring_display()

	var combine_label = hud_layer.get_node_or_null("CombineLabel")
	if combine_label:
		var tween = create_tween()
		tween.tween_property(combine_label, "theme_override_colors/font_color",
			Color(0.8, 0.7, 1.0, 0.0), 0.3)

	var combine_btn = hud_layer.get_node_or_null("CombineButton")
	if combine_btn:
		combine_btn.text = "СКОМБИНИРОВАТЬ"


## Rebase the group around the first found key.
## Stores the inverse of the first found permutation. All subsequent
## permutation checks are rebased: rebased = perm.compose(_rebase_inverse).
## This way the first found arrangement maps to identity → "Тождество".
## target_perms and target_perm_names stay UNCHANGED (original from JSON).
func _relabel_first_key_as_identity(first_sym_id: String) -> void:
	var first_perm: Permutation = target_perms.get(first_sym_id)
	if first_perm == null:
		return

	# If first found IS already identity, no rebase needed
	if first_perm.is_identity():
		_rebase_inverse = null
		return

	# Store inverse for rebasing all future checks
	_rebase_inverse = first_perm.inverse()


func _get_key_display_name(index: int) -> String:
	if key_ring == null or index < 0 or index >= key_ring.count():
		return "?"
	var perm: Permutation = key_ring.get_key(index)
	# Rebase for display: show name relative to first found key
	var display_perm := perm
	if _rebase_inverse != null:
		display_perm = perm.compose(_rebase_inverse)
	for sym_id in target_perms:
		if target_perms[sym_id].equals(display_perm):
			return target_perm_names.get(sym_id, display_perm.to_cycle_notation())
	return display_perm.to_cycle_notation()


func _update_keyring_display_combine() -> void:
	## Show KeyRing with numbered indices for selection during combine mode.
	var kr_label = hud_layer.get_node_or_null("KeyRingLabel")
	if kr_label == null or key_ring == null:
		return

	kr_label.text = "Нажмите на ключ для выбора:"

	# Rebuild buttons in combine mode
	_rebuild_key_buttons(true)


func _show_combine_result_message(first: String, second: String, result: String, is_new: bool) -> void:
	var hint_label = hud_layer.get_node_or_null("HintLabel")
	if hint_label == null:
		return

	var msg: String
	if is_new:
		msg = "%s + %s = %s (новый ключ найден!)" % [first, second, result]
	else:
		msg = "%s + %s = %s (уже найден)" % [first, second, result]

	hint_label.text = msg
	var color := Color(0.3, 1.0, 0.5, 0.95) if is_new else Color(0.7, 0.7, 0.5, 0.85)
	var tween = create_tween()
	tween.tween_property(hint_label, "theme_override_colors/font_color", color, 0.3)
	tween.tween_interval(3.0)
	tween.tween_property(hint_label, "theme_override_colors/font_color",
		Color(0.5, 0.8, 0.5, 0.5), 1.0)


## Update the status label to show current arrangement state.
func _update_status_label() -> void:
	var status = hud_layer.get_node_or_null("StatusLabel")
	if status == null:
		return

	var perm := Permutation.from_array(current_arrangement)
	if perm.is_identity():
		# Identity reached — this IS the goal arrangement (matches the target preview)
		var identity_discovered := key_ring != null and key_ring.contains(perm) if key_ring else false
		if identity_discovered:
			status.text = "Совпадает с целью! (ключ найден)"
			status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.9))
		else:
			status.text = "Совпадает с целью — нажмите ПРОВЕРИТЬ УЗОР!"
			status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5, 0.85))
	else:
		# Check if it matches a known automorphism
		var is_valid := false
		for sym_id in target_perms:
			if target_perms[sym_id].equals(perm):
				is_valid = true
				break
		if is_valid:
			status.text = "Текущее: допустимое расположение"
			status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.9))
		else:
			status.text = "Расположите кристаллы как на картинке-цели"
			status.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5, 0.7))


# --- Win Condition ---

func _on_level_complete() -> void:
	# Stop echo hint system
	if echo_hint_system:
		echo_hint_system.notify_level_completed()

	# Disable further interaction
	for crystal in crystals.values():
		crystal.set_draggable(false)

	# Disable buttons
	var reset_btn = hud_layer.get_node_or_null("ResetButton")
	if reset_btn:
		reset_btn.disabled = true
	var check_btn = hud_layer.get_node_or_null("CheckButton")
	if check_btn:
		check_btn.disabled = true

	# Play completion celebration
	feedback_fx.play_completion_feedback(crystals.values(), edges)

	# Disable repeat button
	var repeat_btn = hud_layer.get_node_or_null("RepeatButton")
	if repeat_btn:
		repeat_btn.disabled = true

	# Disable combine button
	var combine_btn = hud_layer.get_node_or_null("CombineButton")
	if combine_btn:
		combine_btn.disabled = true
	if _combine_mode:
		_exit_combine_mode()

	# Disable inner door UI (Act 2)
	if _inner_door_panel:
		_inner_door_panel.visible = false
	if _subgroup_selector:
		_subgroup_selector.visible = false

	# Emit completion signal
	level_completed.emit(level_id)

	# Register completion in GameManager (saves progress to disk)
	GameManager.complete_level(level_id)

	# Show summary panel after celebration delay
	var meta = level_data.get("meta", {})
	get_tree().create_timer(1.2).timeout.connect(_show_complete_summary.bind(meta))


func _show_generators_panel() -> void:
	var gen_panel = hud_layer.get_node_or_null("GeneratorsPanel")
	if gen_panel == null:
		return

	var symmetries_data = level_data.get("symmetries", {})
	var generator_ids: Array = symmetries_data.get("generators", [])

	if generator_ids.is_empty():
		return

	# Build generator names list
	var gen_names: Array = []
	for gen_id in generator_ids:
		var name: String = target_perm_names.get(gen_id, gen_id)
		gen_names.append(name)

	var gen_body = gen_panel.get_node_or_null("GenBody")
	if gen_body:
		var names_str := ", ".join(gen_names)
		if generator_ids.size() == 1:
			gen_body.text = "У этого зала один генератор: %s\nКаждый ключ можно получить, комбинируя его с самим собой." % names_str
		else:
			gen_body.text = "Генераторы этого зала: %s\nКаждый ключ можно получить, комбинируя эти %d ключа." % [names_str, generator_ids.size()]

	# Fade in
	gen_panel.visible = true
	gen_panel.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(gen_panel, "modulate", Color(1, 1, 1, 1), 0.5)


## Called when the player presses the NEXT LEVEL / RETURN TO MAP button.
func _on_next_level_pressed() -> void:
	# If hall tree is loaded, return to the map scene
	if GameManager.hall_tree != null:
		GameManager.return_to_map()
		return

	# Linear fallback: load the next level directly
	var next_path: String = GameManager.get_next_level_path(level_id)
	if next_path != "":
		load_level_from_file(next_path)
	else:
		# No more levels — show congratulations in summary
		var summary = hud_layer.get_node_or_null("CompleteSummaryPanel")
		if summary:
			var learned = summary.get_node_or_null("SummaryLearnedNote")
			if learned:
				learned.text = "Поздравляем! Вы прошли все доступные уровни!"
				learned.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
			var next_btn = summary.get_node_or_null("SummaryNextButton")
			if next_btn:
				next_btn.visible = false


## Show the completion summary panel with all discovered keys.
func _show_complete_summary(meta: Dictionary) -> void:
	var panel = hud_layer.get_node_or_null("CompleteSummaryPanel")
	if panel == null:
		return

	# Title
	var sum_title = panel.get_node_or_null("SummaryTitle")
	if sum_title:
		sum_title.text = "Зал открыт!"

	# Level info
	var sum_level = panel.get_node_or_null("SummaryLevelInfo")
	if sum_level:
		sum_level.text = "Уровень %d — %s" % [meta.get("level", 0), meta.get("title", "")]

	# Group info
	var sum_group = panel.get_node_or_null("SummaryGroupInfo")
	if sum_group:
		sum_group.text = _format_group_name(meta.get("group_name", ""), meta.get("group_order", 0))

	# Keys list
	var sum_keys = panel.get_node_or_null("SummaryKeysList")
	if sum_keys:
		sum_keys.text = _build_summary_keys_text()

	# What you learned
	var sum_learned = panel.get_node_or_null("SummaryLearnedNote")
	if sum_learned:
		sum_learned.text = _get_learned_note(meta)

	# Generators info (if enabled)
	var sum_gen = panel.get_node_or_null("SummaryGenInfo")
	if sum_gen:
		if _show_generators_hint:
			sum_gen.text = _get_generators_text()
			sum_gen.visible = true
		else:
			sum_gen.text = ""
			sum_gen.visible = false

	# Echo hint seal status
	var sum_seal = panel.get_node_or_null("SummarySealInfo")
	if sum_seal == null:
		# Create seal info label dynamically if not present
		sum_seal = Label.new()
		sum_seal.name = "SummarySealInfo"
		sum_seal.add_theme_font_size_override("font_size", 14)
		sum_seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sum_seal.position = Vector2(50, 465)
		sum_seal.size = Vector2(700, 25)
		panel.add_child(sum_seal)
	if echo_hint_system and echo_hint_system.used_solution_hint():
		sum_seal.text = "Эхо-видение использовано — Печать совершенства потеряна"
		sum_seal.add_theme_color_override("font_color", Color(0.8, 0.5, 0.3, 0.8))
		sum_seal.visible = true
	elif echo_hint_system and echo_hint_system.get_max_echo_used() > 0:
		sum_seal.text = "Печать совершенства получена"
		sum_seal.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 0.8))
		sum_seal.visible = true
	else:
		sum_seal.text = "Печать совершенства получена"
		sum_seal.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 0.8))
		sum_seal.visible = true

	# NEXT / RETURN TO MAP button
	var next_btn = panel.get_node_or_null("SummaryNextButton")
	if next_btn:
		if GameManager.hall_tree != null:
			# Hall tree mode: always show "return to map" button
			next_btn.text = "ВЕРНУТЬСЯ НА КАРТУ"
			next_btn.visible = true
		else:
			# Linear mode: show only if there's a next level
			var next_path = GameManager.get_next_level_path(level_id)
			next_btn.visible = next_path != ""

	# Fade in
	panel.visible = true
	panel.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.5)


## Build text listing all discovered keys with names and descriptions.
func _build_summary_keys_text() -> String:
	if key_ring == null:
		return ""
	var text := ""
	for i in range(key_ring.count()):
		var perm: Permutation = key_ring.get_key(i)
		var display_name := perm.to_cycle_notation()
		var description := ""
		for sym_id in target_perms:
			if target_perms[sym_id].equals(perm):
				display_name = target_perm_names.get(sym_id, display_name)
				description = target_perm_descriptions.get(sym_id, "")
				break
		if description != "":
			text += "  %s  —  %s\n" % [display_name, description]
		else:
			text += "  %s\n" % display_name
	return text


## Format group name in player-friendly language.
func _format_group_name(group_name: String, group_order: int) -> String:
	match group_name:
		"Z2": return "2 ключа — один обмен и обратно"
		"Z3": return "3 ключа — цикл кристаллов"
		"Z4": return "4 ключа — четыре поворота квадрата"
		"Z5": return "5 ключей — пятишаговый цикл"
		"Z6": return "6 ключей — шестишаговый цикл"
		"D4": return "8 ключей — повороты и отражения квадрата"
		"V4": return "4 ключа — каждое действие отменяет само себя"
		"S3": return "6 ключей — все перестановки трёх пар"
		_:
			return "%d ключей" % group_order


## Get a player-friendly "what you learned" note.
func _get_learned_note(meta: Dictionary) -> String:
	var group_name: String = meta.get("group_name", "")
	var level_num: int = meta.get("level", 0)
	match group_name:
		"Z2":
			if level_num == 3:
				return "Цвета ограничивают, какие кристаллы можно менять местами."
			if level_num == 7:
				return "Кривой путь тоже может скрывать закономерность!"
			if level_num == 8:
				return "Два одинаковых скопления можно полностью поменять местами."
			return "Один обмен — сделай дважды, и всё вернётся."
		"Z3":
			return "Три поворота образуют цикл: каждый ведёт к следующему."
		"Z4":
			return "Стрелки задают направление — можно только вращать, но не отражать."
		"D4":
			if level_num == 12:
				return "Понадобились два разных вида ходов (поворот И отражение), чтобы получить все 8 расстановок."
			return "Без стрелок появляются отражения — число ключей удваивается!"
		"V4":
			return "Каждое действие здесь отменяет само себя: сделай дважды — вернёшься."
		"S3":
			return "Шесть способов переставить три пары — порядок ходов важен!"
		"Z5":
			return "Одного хода достаточно, чтобы породить все остальные — просто повторяйте."
		"Z6":
			return "Не каждый ход может породить все остальные — некоторые слишком малы."
		_:
			return ""


## Get generators text for the summary panel.
func _get_generators_text() -> String:
	var symmetries_data = level_data.get("symmetries", {})
	var generator_ids: Array = symmetries_data.get("generators", [])
	if generator_ids.is_empty():
		return ""
	var gen_names: Array = []
	for gen_id in generator_ids:
		var gname: String = target_perm_names.get(gen_id, gen_id)
		gen_names.append(gname)
	var names_str := ", ".join(gen_names)
	if generator_ids.size() == 1:
		return "Мастер-ключ: %s — повторяя его, можно получить все остальные ключи." % names_str
	else:
		return "Мастер-ключи: %s — комбинируя эти %d хода, можно получить все остальные." % [names_str, generator_ids.size()]


## Get adaptive instruction text based on level mechanics.
func _get_instruction_text(meta: Dictionary, mechanics: Dictionary) -> Dictionary:
	var level_num: int = meta.get("level", 1)
	var has_cayley: bool = mechanics.get("show_cayley_button", false)
	var has_generators: bool = mechanics.get("show_generators_hint", false)

	var body: String = ""
	var new_mechanic: String = ""

	# Core instructions — crystal language, no math jargon
	body = "Кристаллы перемешаны! Расположите их как на картинке-цели в углу.\n"
	body += "Перетащите один кристалл на другой, чтобы поменять их местами.\n"
	body += "Когда соберёте — нажмите ПРОВЕРИТЬ УЗОР. Но это лишь первый ключ..."

	# Level-specific additions
	match level_num:
		1:
			body += "\n\nПодсказка: соберите кристаллы как на маленькой картинке слева вверху, затем нажмите ПРОВЕРИТЬ УЗОР."
		2:
			new_mechanic = "НОВОЕ: Стрелки на нитях! Допустимое расположение должно сохранять направления стрелок."
		3:
			new_mechanic = "НОВОЕ: Разные цвета! Кристаллы могут оказаться только там, где подходит цвет."
		4:
			body += "\n\nПомните: стрелки должны указывать в ту же сторону после обмена."
		5:
			new_mechanic = "НОВОЕ: Кнопка СКОМБИНИРОВАТЬ! Найдя 2+ ключа, комбинируйте их для открытия новых."
		7:
			body += "\n\nЭтот граф выглядит неправильным — но присмотритесь к цветам."
		8:
			body += "\n\nДва отдельных скопления. Одинаковы ли они изнутри?"
		9:
			body += "\n\nТолстые связи объединяют кристаллы в пары. Можно ли поменять целые пары?"
		10:
			new_mechanic = "НОВОЕ: После решения вы увидите, какие ключи — мастер-ключи, минимальный набор, порождающий все остальные."
		_:
			# For levels with cayley but no special NEW text
			if has_cayley and level_num > 5:
				body += "\n\nИспользуйте СКОМБИНИРОВАТЬ, чтобы создать новые расстановки из уже найденных."
			if has_generators and level_num > 10:
				body += "\n\nИщите мастер-ключи — минимум ходов, порождающих всё остальное."

	return {"body": body, "new_mechanic": new_mechanic}


# --- HUD Updates ---

func _update_counter() -> void:
	var counter = hud_layer.get_node_or_null("CounterLabel")
	if counter:
		var found_count := key_ring.count() if key_ring else 0
		var counter_text := "Ключи: %d / %d" % [found_count, total_symmetries]
		# Add door progress for Act 2 levels
		if _inner_door_panel:
			var opened: int = _inner_door_panel.get_opened_count()
			var total: int = _inner_door_panel.get_total_count()
			counter_text += " | Двери: %d / %d" % [opened, total]
		counter.text = counter_text

	# Show/hide REPEAT button (visible when at least 1 key found)
	var repeat_btn = hud_layer.get_node_or_null("RepeatButton")
	if repeat_btn:
		var should_show_repeat := key_ring != null and key_ring.count() >= 1
		repeat_btn.visible = should_show_repeat
		if should_show_repeat:
			_update_repeat_button_text()

	# Show/hide COMBINE KEYS button
	var combine_btn = hud_layer.get_node_or_null("CombineButton")
	if combine_btn:
		var should_show := _show_cayley_button and key_ring != null and key_ring.count() >= 2
		combine_btn.visible = should_show


func _update_keyring_display() -> void:
	var kr_label = hud_layer.get_node_or_null("KeyRingLabel")
	if kr_label == null or key_ring == null:
		return

	kr_label.text = "Найденные ключи:"

	# Rebuild clickable key buttons
	_rebuild_key_buttons(false)


func _show_violation_tooltip(text: String) -> void:
	var viol_label = hud_layer.get_node_or_null("ViolationLabel")
	if viol_label == null or text == "":
		return

	viol_label.text = text
	# Fade in, hold, then fade out
	var tween = create_tween()
	tween.tween_property(viol_label, "theme_override_colors/font_color",
		Color(1.0, 0.4, 0.35, 0.9), 0.25)
	tween.tween_interval(1.8)
	tween.tween_property(viol_label, "theme_override_colors/font_color",
		Color(1.0, 0.4, 0.35, 0.0), 0.6)


# --- Tutorial / Onboarding ---

func _show_instruction_panel() -> void:
	var panel = hud_layer.get_node_or_null("InstructionPanel")
	if panel == null:
		return

	# Populate content from current level data
	var meta = level_data.get("meta", {})
	var mechanics = level_data.get("mechanics", {})
	var level_num: int = meta.get("level", 1)
	var group_order: int = meta.get("group_order", 1)

	var instr_title = panel.get_node_or_null("InstrTitle")
	if instr_title:
		instr_title.text = "Уровень %d — %s" % [level_num, meta.get("title", "")]

	var instr_goal = panel.get_node_or_null("InstrGoal")
	if instr_goal:
		instr_goal.text = "Найдите все %d ключей, чтобы открыть этот зал" % group_order

	var texts := _get_instruction_text(meta, mechanics)

	var instr_body = panel.get_node_or_null("InstrBody")
	if instr_body:
		instr_body.text = texts["body"]

	var instr_new = panel.get_node_or_null("InstrNewMechanic")
	if instr_new:
		instr_new.text = texts["new_mechanic"]
		instr_new.visible = texts["new_mechanic"] != ""

	panel.visible = true
	panel.modulate = Color(1, 1, 1, 1)
	_instruction_panel_visible = true

	# Disable crystals while instruction panel is showing
	for crystal in crystals.values():
		if crystal is CrystalNode:
			crystal.set_draggable(false)


func _dismiss_instruction_panel() -> void:
	if not _instruction_panel_visible:
		return
	var panel = hud_layer.get_node_or_null("InstructionPanel")
	if panel:
		var tween = create_tween()
		tween.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.3)
		tween.tween_callback(_hide_node.bind(panel))
	_instruction_panel_visible = false
	# Re-enable crystals
	for crystal in crystals.values():
		if crystal is CrystalNode:
			crystal.set_draggable(true)


func _input(event: InputEvent) -> void:
	# Dismiss instruction panel on any click/tap
	if _instruction_panel_visible:
		if event is InputEventMouseButton and event.pressed:
			_dismiss_instruction_panel()
			get_viewport().set_input_as_handled()
			return


# --- Key Buttons (replaces coordinate-based KeyRing click detection) ---

## Rebuild the clickable key buttons in the KeyButtonsContainer.
## Each key row has: key name label + "▶ Повторить" button.
func _rebuild_key_buttons(combine_mode_active: bool) -> void:
	var container = hud_layer.get_node_or_null("KeyButtonsContainer")
	if container == null or key_ring == null:
		return

	# Clear existing children
	for child in container.get_children():
		child.queue_free()

	if key_ring.count() == 0:
		container.visible = false
		return

	container.visible = true

	for i in range(key_ring.count()):
		var display_name := _get_key_display_name(i)

		# Row container for each key
		var row = HBoxContainer.new()
		row.name = "KeyRow_%d" % i
		row.custom_minimum_size = Vector2(380, 28)

		# Key name label
		var label = Label.new()
		label.text = "[%d] %s" % [i + 1, display_name]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6, 0.9))
		label.custom_minimum_size = Vector2(220, 24)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		# "▶ Повторить" button next to the key
		var repeat_btn = Button.new()
		repeat_btn.name = "RepeatBtn_%d" % i
		repeat_btn.text = "▶ Повторить"
		repeat_btn.add_theme_font_size_override("font_size", 11)
		repeat_btn.custom_minimum_size = Vector2(120, 24)
		var cb_index := i  # capture for lambda
		repeat_btn.pressed.connect(_on_repeat_key_clicked.bind(cb_index))

		# Style for repeat button
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.12, 0.18, 0.28, 0.6)
		btn_style.corner_radius_top_left = 4
		btn_style.corner_radius_top_right = 4
		btn_style.corner_radius_bottom_left = 4
		btn_style.corner_radius_bottom_right = 4
		repeat_btn.add_theme_stylebox_override("normal", btn_style)

		var btn_hover = StyleBoxFlat.new()
		btn_hover.bg_color = Color(0.18, 0.28, 0.42, 0.7)
		btn_hover.corner_radius_top_left = 4
		btn_hover.corner_radius_top_right = 4
		btn_hover.corner_radius_bottom_left = 4
		btn_hover.corner_radius_bottom_right = 4
		repeat_btn.add_theme_stylebox_override("hover", btn_hover)

		repeat_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 0.9))
		row.add_child(repeat_btn)

		container.add_child(row)


## Called when a key button is clicked in normal mode (not combine mode).
## Sets the active repeat key.
func _on_key_button_clicked(index: int) -> void:
	if _combine_mode:
		return  # In combine mode, use _on_combine_key_selected instead

	_active_repeat_key_index = index
	_update_repeat_button_text()
	_rebuild_key_buttons(false)
	_notify_echo_activity()


# --- Repeat Key Feature ---

## Update the REPEAT button text to show the active key name.
func _update_repeat_button_text() -> void:
	var repeat_btn = hud_layer.get_node_or_null("RepeatButton")
	if repeat_btn == null:
		return

	if _active_repeat_key_index < 0 or key_ring == null or _active_repeat_key_index >= key_ring.count():
		repeat_btn.text = "ПОВТОРИТЬ"
		return

	var name := _get_key_display_name(_active_repeat_key_index)
	# Truncate long names
	if name.length() > 14:
		name = name.substr(0, 12) + ".."
	repeat_btn.text = "ПОВТОРИТЬ: %s" % name


## Called when a per-key "▶ Повторить" button is clicked.
func _on_repeat_key_clicked(key_index: int) -> void:
	_notify_echo_activity()

	if _repeat_animating:
		return  # Don't allow overlapping animations

	if key_ring == null or key_index < 0 or key_index >= key_ring.count():
		return

	_active_repeat_key_index = key_index
	_apply_repeat_key(key_index)


## Called when the old global REPEAT button is pressed (kept for compatibility).
func _on_repeat_pressed() -> void:
	_notify_echo_activity()

	if _repeat_animating:
		return  # Don't allow overlapping animations

	if key_ring == null or _active_repeat_key_index < 0 or _active_repeat_key_index >= key_ring.count():
		return

	_apply_repeat_key(_active_repeat_key_index)


## Apply a key by index from the key ring to the current arrangement.
## Uses the REBASED permutation (automorphism) so that:
##   - "Тождество" (first found key) = identity → nothing moves
##   - Other keys apply their automorphism relative to the current state
## The automorphism P acts on positions: crystal at position i moves to P[i].
func _apply_repeat_key(key_index: int) -> void:
	if key_ring == null or key_index < 0 or key_index >= key_ring.count():
		return

	# Get the rebased automorphism for this key.
	# raw_perm is the arrangement stored when the key was found.
	# Composing with _rebase_inverse gives the automorphism relative to the first found key:
	#   - First found key → identity (flash, no movement) — correct!
	#   - Other keys → their actual group action relative to "Тождество"
	# The REAL bug was in positions_map having float keys (JSON parser) vs int lookups.
	var raw_perm: Permutation = key_ring.get_key(key_index)
	var auto_perm: Permutation = raw_perm
	if _rebase_inverse != null:
		auto_perm = raw_perm.compose(_rebase_inverse)

	var n := current_arrangement.size()
	if n == 0:
		return

	# If this is the identity automorphism, nothing should move — just flash
	if auto_perm.is_identity():
		for crystal in crystals.values():
			if crystal is CrystalNode:
				crystal.play_glow()
		return

	# Apply automorphism P to current arrangement as LEFT composition:
	# new_arrangement[i] = current_arrangement[P[i]]
	# "Position i receives the crystal that was at position P[i]."
	# This is P ∘ current (standard left group action on arrangements).
	# Example: current=r3=[3,0,1,2], P=r3 → new=[2,3,0,1]=r2 (270°+270°=180°) ✓
	var new_arrangement: Array[int] = []
	new_arrangement.resize(n)
	for i in range(n):
		new_arrangement[i] = current_arrangement[auto_perm.apply(i)]

	# Build positions map: position_index -> world_position
	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var viewport_size = get_viewport_rect().size
	var center_offset = viewport_size / 2.0

	var positions_map: Dictionary = {}  # position_index (int) -> Vector2
	for node_data in nodes_data:
		var node_id: int = int(node_data.get("id", 0))
		var pos_arr = node_data.get("position", [0, 0])
		var pos: Vector2
		if pos_arr is Array and pos_arr.size() >= 2:
			pos = Vector2(pos_arr[0], pos_arr[1])
		else:
			pos = Vector2.ZERO
		if abs(pos.x) <= 2.0 and abs(pos.y) <= 2.0:
			pos = pos * 200.0 + center_offset
		positions_map[node_id] = pos

	# Compute center of graph for arc control points
	var graph_center := Vector2.ZERO
	for pos in positions_map.values():
		graph_center += pos
	if positions_map.size() > 0:
		graph_center /= float(positions_map.size())

	if agent_mode:
		# Instant mode: no animation
		current_arrangement = new_arrangement
		_apply_arrangement_to_crystals()
		var perm := Permutation.from_array(current_arrangement)
		_validate_permutation(perm)
		return

	# Beautiful animation — fully Tween-based, no await/coroutines to avoid Stack underflow.
	_repeat_animating = true

	# Phase 1: PREPARATION (0.2 sec) — lift crystals slightly
	var prep_tween = create_tween().set_parallel(true)
	for crystal in crystals.values():
		if crystal is CrystalNode:
			prep_tween.tween_property(crystal, "scale", Vector2(1.08, 1.08), 0.2).set_ease(Tween.EASE_OUT)

	# Chain to Phase 2 via a separate sequenced tween (avoids set_parallel toggle issues)
	var chain := create_tween()
	chain.tween_interval(0.22)  # Wait for prep to finish
	chain.tween_callback(_repeat_phase2.bind(n, auto_perm, positions_map, graph_center,
		new_arrangement))


## Animate a crystal along a quadratic Bezier arc using Tween (no coroutines).
## Returns the Tween so the caller can track completion if needed.
func _animate_crystal_arc_tween(crystal: CrystalNode, from: Vector2, control: Vector2, to: Vector2, duration: float, delay: float) -> Tween:
	var tween := create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_method(_bezier_step.bind(crystal, from, control, to), 0.0, 1.0, duration)
	# Snap to final position at end
	tween.tween_callback(_snap_crystal_pos.bind(crystal, to))
	return tween


## Bezier interpolation step — called by tween_method (avoids lambda/Stack underflow).
func _bezier_step(t: float, crystal: CrystalNode, from: Vector2, control: Vector2, to: Vector2) -> void:
	var eased_t: float
	if t < 0.5:
		eased_t = 2.0 * t * t
	else:
		eased_t = 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
	var one_minus_t := 1.0 - eased_t
	crystal.position = one_minus_t * one_minus_t * from + 2.0 * one_minus_t * eased_t * control + eased_t * eased_t * to


## Snap crystal to final position — used as tween callback (avoids lambda/Stack underflow).
func _snap_crystal_pos(crystal: CrystalNode, pos: Vector2) -> void:
	crystal.position = pos


## Hide a node — used as tween callback (avoids lambda/Stack underflow).
func _hide_node(node: Node) -> void:
	if is_instance_valid(node):
		node.visible = false


## Free a node if still valid — used as tween callback (avoids lambda/Stack underflow).
func _free_if_valid(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


## Fade hint label color to transparent — used as tween callback (avoids lambda/Stack underflow).
func _fade_hint_label(label: Label) -> void:
	if is_instance_valid(label):
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5, 0.0))


## Phase 2 of repeat animation: crystal movement along arcs (no coroutines).
func _repeat_phase2(n: int, active_perm: Permutation, positions_map: Dictionary,
		graph_center: Vector2, new_arrangement: Array[int]) -> void:
	var max_delay := 0.0

	for i in range(n):
		# new_arrangement[i] = current_arrangement[P[i]]
		# → crystal at position P[i] flies TO position i
		var source_pos_index: int = active_perm.apply(i)

		if source_pos_index == i:
			continue  # This position doesn't change
		if source_pos_index >= n:
			continue

		var crystal_id: int = current_arrangement[source_pos_index]
		if crystal_id not in crystals:
			continue
		if i not in positions_map:
			continue

		var crystal: CrystalNode = crystals[crystal_id]
		var from_pos: Vector2 = crystal.position
		var to_pos: Vector2 = positions_map[i]

		# Calculate Bezier arc control point — offset perpendicular toward center
		var midpoint: Vector2 = (from_pos + to_pos) / 2.0
		var to_center: Vector2 = graph_center - midpoint
		var arc_offset: float = 40.0
		if to_center.length() > 0:
			var control_point: Vector2 = midpoint + to_center.normalized() * arc_offset
			_animate_crystal_arc_tween(crystal, from_pos, control_point, to_pos, 0.5, max_delay)
		else:
			var straight_tween := create_tween()
			if max_delay > 0:
				straight_tween.tween_interval(max_delay)
			straight_tween.tween_property(crystal, "position", to_pos, 0.5)\
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

		max_delay += 0.03  # Stagger between crystals

	# Chain to Phase 3 after all movement finishes
	var wait_tween := create_tween()
	wait_tween.tween_interval(0.5 + max_delay + 0.05)
	wait_tween.tween_callback(_repeat_phase3.bind(n, new_arrangement, positions_map))


## Phase 3 of repeat animation: landing bounce + state update (no coroutines).
func _repeat_phase3(n: int, new_arrangement: Array[int], positions_map: Dictionary) -> void:
	# Update state
	current_arrangement = new_arrangement

	# Update home positions for all crystals
	for i in range(n):
		var crystal_id: int = current_arrangement[i]
		if crystal_id in crystals and i in positions_map:
			crystals[crystal_id].set_home_position(positions_map[i])

	# Phase 3: LANDING (0.2 sec) — bounce effect
	for crystal in crystals.values():
		if crystal is CrystalNode:
			# Bounce: 1.08 → 0.95 → 1.0
			var bounce := create_tween()
			bounce.tween_property(crystal, "scale", Vector2(0.95, 0.95), 0.1).set_ease(Tween.EASE_IN)
			bounce.tween_property(crystal, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_OUT)
			# Landing flash
			feedback_fx._spawn_burst(crystal.position, crystal._glow_color, 3)

	# Chain to finish after bounce completes
	var finish_tween := create_tween()
	finish_tween.tween_interval(0.25)
	finish_tween.tween_callback(_repeat_finish)


## Final phase of repeat animation: validate + re-enable buttons.
func _repeat_finish() -> void:
	# Validate the new arrangement
	var perm := Permutation.from_array(current_arrangement)
	_validate_permutation(perm)

	# Re-enable buttons
	_repeat_animating = false
	_update_status_label()


## Set the active repeat key when a new symmetry is discovered.
func _set_active_repeat_key_latest() -> void:
	if key_ring and key_ring.count() > 0:
		_active_repeat_key_index = key_ring.count() - 1
		_update_repeat_button_text()


func _show_first_symmetry_message(sym_id: String) -> void:
	## Show an encouraging message after the player's first symmetry discovery.
	## Explains what just happened in simple terms.
	var hint_label = hud_layer.get_node_or_null("HintLabel")
	if hint_label == null:
		return

	var sym_name: String = target_perm_names.get(sym_id, "ключ")
	var found_count := key_ring.count() if key_ring else 0
	var remaining := total_symmetries - found_count

	var msg: String
	# First found key is always relabeled to "Тождество"
	if key_ring and key_ring.count() == 1:
		msg = "Тождество найдено — первый ключ! Осталось: %d. А есть ли ДРУГИЕ правильные расположения?" % remaining
	elif sym_name == "Тождество" or sym_id == "e":
		msg = "Вы собрали картинку-цель — первый ключ найден! Осталось: %d. А есть ли ДРУГИЕ правильные расположения?" % remaining
	else:
		msg = "Новый ключ: «%s»! Это тоже допустимое расположение. Осталось найти: %d." % [sym_name, remaining]

	hint_label.text = msg
	# Animate: fade in green, hold, then fade to subtle
	var tween = create_tween()
	tween.tween_property(hint_label, "theme_override_colors/font_color",
		Color(0.3, 1.0, 0.5, 0.95), 0.3)
	tween.tween_interval(3.5)
	tween.tween_property(hint_label, "theme_override_colors/font_color",
		Color(0.5, 0.8, 0.5, 0.5), 1.0)


func _show_button_hints() -> void:
	## Show subtle text hints near the RESET and TEST PATTERN buttons (Act 1 only)
	var reset_hint = hud_layer.get_node_or_null("ResetHintLabel")
	if reset_hint:
		reset_hint.text = "Вернуть к началу"
		var tween1 = create_tween()
		tween1.tween_property(reset_hint, "theme_override_colors/font_color",
			Color(0.6, 0.65, 0.8, 0.7), 1.5)

	var check_hint = hud_layer.get_node_or_null("CheckHintLabel")
	if check_hint:
		check_hint.text = "Проверить расстановку"
		var tween2 = create_tween()
		tween2.tween_property(check_hint, "theme_override_colors/font_color",
			Color(0.6, 0.65, 0.8, 0.7), 1.5)


# --- Echo Hint System Integration ---

func _setup_echo_hints() -> void:
	# Clean up previous echo system if exists
	if echo_hint_system:
		echo_hint_system.cleanup()
		echo_hint_system.queue_free()
		echo_hint_system = null

	# Create new echo hint system
	echo_hint_system = EchoHintSystem.new()
	echo_hint_system.name = "EchoHintSystem"
	add_child(echo_hint_system)
	echo_hint_system.setup(level_data, hud_layer, crystals)

	# Connect signals
	echo_hint_system.hint_shown.connect(_on_echo_hint_shown)
	echo_hint_system.perfect_seal_lost.connect(_on_perfect_seal_lost)


func _on_echo_hint_shown(level: int, text: String) -> void:
	# Optional: log or track hint usage
	pass


func _on_perfect_seal_lost() -> void:
	# Mark that the player used a Level 3 hint — no perfect seal
	# This can be checked via echo_hint_system.used_solution_hint() at level completion
	pass


## Notify echo system of player activity (resets idle timer).
func _notify_echo_activity() -> void:
	if echo_hint_system:
		echo_hint_system.notify_player_action()


# --- Legacy Hints (trigger-based: after_first_valid, after_N_found) ---

var _hint_timer: Timer = null

func _start_hint_timer() -> void:
	# Legacy idle hint is now handled by EchoHintSystem.
	# Only keep trigger-based hints (after_first_valid, after_N_found) here.
	pass


func _check_triggered_hints() -> void:
	## Check if any hints should fire based on current key_ring count.
	## These are event-based hints (not idle-based), so they remain separate from Echo system.
	if key_ring == null:
		return
	var hints = level_data.get("hints", [])
	var found_count := key_ring.count()
	for hint in hints:
		var trigger: String = hint.get("trigger", "")
		var text: String = hint.get("text", "")
		if text.is_empty():
			continue
		if trigger == "after_first_valid" and found_count == 1:
			# Small delay so it doesn't overlap first_symmetry_message
			var timer = get_tree().create_timer(4.5)
			timer.timeout.connect(_show_hint.bind(text))
		elif trigger.begins_with("after_") and trigger.ends_with("_found"):
			# Parse "after_N_found" pattern
			var num_str := trigger.trim_prefix("after_").trim_suffix("_found")
			if num_str.is_valid_int():
				var target_n := int(num_str)
				if found_count == target_n:
					_show_hint(text)


func _show_hint(text: String) -> void:
	var hint_label = hud_layer.get_node_or_null("HintLabel")
	if hint_label:
		hint_label.text = text
		# Fade in
		var tween = create_tween()
		tween.tween_property(hint_label, "theme_override_colors/font_color",
			Color(0.7, 0.7, 0.5, 0.8), 1.0)


# --- Public API ---

## Get the current crystal arrangement as a Permutation object
func get_current_permutation() -> Permutation:
	return Permutation.from_array(current_arrangement)


## Get the KeyRing tracking discovered symmetries
func get_key_ring() -> KeyRing:
	return key_ring


## Get the CrystalGraph for this level
func get_crystal_graph() -> CrystalGraph:
	return crystal_graph


## Get all crystal nodes (for external access)
func get_crystals() -> Dictionary:
	return crystals


## Get all edge renderers
func get_edges() -> Array[EdgeRenderer]:
	return edges


## Get feedback FX manager
func get_feedback_fx() -> FeedbackFX:
	return feedback_fx


# --- Agent API ---
# These methods are called by AgentBridge for programmatic control.

## Perform a swap by crystal IDs, without drag-and-drop.
## Swaps accumulate — no auto-reset on invalid permutation.
## Returns a result dictionary with the outcome.
func perform_swap_by_id(from_id: int, to_id: int) -> Dictionary:
	if from_id == to_id:
		return {"result": "no_op", "reason": "same_crystal"}
	if not (from_id in crystals and to_id in crystals):
		return {"result": "error", "reason": "invalid_crystal_id",
				"available_ids": crystals.keys()}
	var crystal_a = crystals[from_id]
	var crystal_b = crystals[to_id]
	if not crystal_a.draggable or not crystal_b.draggable:
		return {"result": "error", "reason": "crystal_not_draggable"}
	_perform_swap(crystal_a, crystal_b)
	return {"result": "ok", "arrangement": Array(current_arrangement)}


## Submit an arbitrary permutation directly for validation.
## Bypasses drag-and-drop — lets agent test any permutation including identity.
## Returns a result dictionary with the outcome.
func submit_permutation(mapping: Array) -> Dictionary:
	var n := crystal_graph.node_count() if crystal_graph else 0
	if mapping.size() != n:
		return {"result": "error", "reason": "wrong_size",
				"expected": n, "got": mapping.size()}

	var perm := Permutation.from_array(mapping)
	if not perm.is_valid():
		return {"result": "error", "reason": "invalid_permutation"}

	# Set the arrangement to match this permutation
	current_arrangement = Array(mapping, TYPE_INT, "", null)
	# Update crystal positions to match the permutation
	_apply_arrangement_to_crystals()
	# Validate (show feedback since this is an explicit submission)
	_validate_permutation(perm, true)
	return {"result": "ok", "arrangement": Array(current_arrangement)}


## Reset the arrangement to shuffled start (agent equivalent of RESET button).
func agent_reset() -> Dictionary:
	_reset_arrangement()
	_update_status_label()
	return {"result": "ok", "arrangement": Array(current_arrangement)}


## Check the current arrangement (agent equivalent of CHECK CURRENT button).
func agent_check_current() -> Dictionary:
	var perm := Permutation.from_array(current_arrangement)
	_validate_permutation(perm, true)
	return {"result": "ok", "arrangement": Array(current_arrangement),
			"is_automorphism": crystal_graph.is_automorphism(perm) if crystal_graph else false}


## Apply a repeat key by index (agent equivalent of selecting key + pressing REPEAT).
func agent_repeat_key(key_index: int) -> Dictionary:
	if key_ring == null or key_index < 0 or key_index >= key_ring.count():
		return {"result": "error", "reason": "invalid_key_index",
				"available_range": [0, key_ring.count() - 1] if key_ring else []}

	_active_repeat_key_index = key_index
	_apply_repeat_key(key_index)
	return {"result": "ok", "arrangement": Array(current_arrangement),
			"key_index": key_index, "key_name": _get_key_display_name(key_index)}


## Move crystals to match current_arrangement (used by submit_permutation)
func _apply_arrangement_to_crystals() -> void:
	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var viewport_size = get_viewport_rect().size
	var center_offset = viewport_size / 2.0

	# Build position map: position_index -> world_position
	var positions_map: Dictionary = {}
	for node_data in nodes_data:
		var node_id = node_data.get("id", 0)
		var pos_arr = node_data.get("position", [0, 0])
		var pos: Vector2
		if pos_arr is Array and pos_arr.size() >= 2:
			pos = Vector2(pos_arr[0], pos_arr[1])
		else:
			pos = Vector2.ZERO
		if abs(pos.x) <= 2.0 and abs(pos.y) <= 2.0:
			pos = pos * 200.0 + center_offset
		positions_map[node_id] = pos

	# Place each crystal at the position dictated by current_arrangement
	for i in range(current_arrangement.size()):
		var crystal_id = current_arrangement[i]
		if crystal_id in crystals and i in positions_map:
			var target_pos = positions_map[i]
			var duration := 0.0 if agent_mode else 0.35
			crystals[crystal_id].animate_to_position(target_pos, duration)
			crystals[crystal_id].set_home_position(target_pos)


# --- Shuffled Start Helpers ---

## Generate a deterministic seed for the level shuffle.
## Uses level_id hash so the same level always gets the same shuffle.
## Players who reload get the same initial arrangement.
func _generate_shuffle_seed() -> int:
	return level_id.hash()


## Generate a Fisher-Yates shuffle permutation that is NOT identity.
## Returns an array where result[i] = which position to take from.
func _generate_shuffle(size: int, seed_val: int) -> Array[int]:
	if size <= 1:
		return [0]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var perm: Array[int] = []
	for i in range(size):
		perm.append(i)

	# Fisher-Yates shuffle
	for i in range(size - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := perm[i]
		perm[i] = perm[j]
		perm[j] = tmp

	# Guarantee not identity: if shuffle == identity, swap first two elements
	var is_identity := true
	for i in range(size):
		if perm[i] != i:
			is_identity = false
			break
	if is_identity:
		var tmp := perm[0]
		perm[0] = perm[1]
		perm[1] = tmp

	return perm


## Setup the target preview miniature in the HUD.
func _setup_target_preview(nodes_data: Array, edges_data: Array) -> void:
	if target_preview == null:
		push_warning("LevelScene: target_preview is null in _setup_target_preview — recreating")
		# Fallback: recreate TargetPreview if it was lost (should not happen)
		target_preview = Control.new()
		target_preview.name = "TargetPreview"
		target_preview.position = Vector2(20, 80)
		target_preview.size = Vector2(150, 150)
		target_preview.custom_minimum_size = Vector2(150, 150)
		target_preview.clip_contents = false
		target_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(target_preview)
		# Recreate background panel
		var bg = Panel.new()
		bg.name = "TargetBG"
		bg.position = Vector2.ZERO
		bg.size = Vector2(150, 150)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.04, 0.04, 0.08, 0.85)
		st.corner_radius_top_left = 8
		st.corner_radius_top_right = 8
		st.corner_radius_bottom_left = 8
		st.corner_radius_bottom_right = 8
		st.border_color = Color(0.75, 0.65, 0.2, 0.7)
		st.border_width_left = 2
		st.border_width_right = 2
		st.border_width_top = 2
		st.border_width_bottom = 2
		bg.add_theme_stylebox_override("panel", st)
		target_preview.add_child(bg)
		# Recreate title label
		var tl = Label.new()
		tl.name = "TargetTitle"
		tl.text = "Цель"
		tl.add_theme_font_size_override("font_size", 11)
		tl.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.position = Vector2(0, 2)
		tl.size = Vector2(150, 16)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target_preview.add_child(tl)

	# Remove old graph draw child if exists (remove_child + queue_free to avoid
	# name collision when adding the new node in the same frame)
	var old_draw = target_preview.get_node_or_null("TargetGraphDraw")
	if old_draw:
		target_preview.remove_child(old_draw)
		old_draw.queue_free()

	# IMPORTANT: make parent visible BEFORE adding draw child,
	# otherwise Godot skips _draw() for nodes under invisible parents.
	target_preview.visible = true

	# Create new graph draw node (TargetPreviewDraw uses Control._draw() for rendering)
	var draw_node = TargetPreviewDraw.new()
	draw_node.name = "TargetGraphDraw"
	draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_node.position = Vector2(5, 18)
	draw_node.size = Vector2(140, 127)
	draw_node.custom_minimum_size = Vector2(140, 127)
	target_preview.add_child(draw_node)
	# Pass explicit draw_size so _compute_draw_data doesn't depend on self.size.
	# setup() must be called AFTER add_child() so queue_redraw() works.
	draw_node.setup(nodes_data, edges_data, Vector2(140, 127))

	# Set initial border color (gold = goal not yet reached)
	_update_target_preview_border()


## Update the target preview border color based on identity found status.
func _update_target_preview_border() -> void:
	if target_preview == null:
		return
	var target_bg = target_preview.get_node_or_null("TargetBG")
	if target_bg == null:
		return

	var style: StyleBoxFlat = target_bg.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return

	# Clone the style to avoid shared reference issues
	var new_style := style.duplicate() as StyleBoxFlat
	if _identity_found:
		new_style.border_color = Color(0.3, 0.9, 0.4, 0.7)  # Green — identity found!
	else:
		new_style.border_color = Color(0.75, 0.65, 0.2, 0.7)  # Gold — still searching

	target_bg.add_theme_stylebox_override("panel", new_style)

	# Update title label color too
	var title_label = target_preview.get_node_or_null("TargetTitle")
	if title_label:
		if _identity_found:
			title_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 0.9))
			title_label.text = "Цель ✓"
		else:
			title_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9))
			title_label.text = "Цель"
