## MainMenu — Title screen and entry point for the game
##
## Responsibilities:
## - Display game title with fade-in animation
## - Show animated crystal background
## - Provide navigation: Start/Continue, Settings, Exit
## - Detect save data to show "Continue" vs "Start"

class_name MainMenu
extends Control

# --- Scene references ---
var _title_label: Label
var _subtitle_label: Label
var _start_button: Button
var _settings_button: Button
var _exit_button: Button
var _version_label: Label
var _crystal_canvas: Node2D
var _settings_screen: Control

# --- Animation state ---
var _title_alpha: float = 0.0
var _subtitle_alpha: float = 0.0
var _buttons_alpha: float = 0.0
var _animation_time: float = 0.0
var _crystals: Array[Dictionary] = []  # {pos, color, size, speed, angle, pulse_offset}

# --- Crystal shimmer shader params ---
const CRYSTAL_COLORS := [
	Color(0.4, 0.6, 1.0, 0.15),   # Blue
	Color(0.3, 0.9, 0.5, 0.12),   # Green
	Color(1.0, 0.7, 0.3, 0.10),   # Gold
	Color(0.7, 0.4, 1.0, 0.12),   # Purple
	Color(0.3, 0.8, 0.9, 0.10),   # Cyan
	Color(1.0, 0.4, 0.5, 0.08),   # Red-pink
]


func _ready() -> void:
	_setup_background_crystals()
	_setup_ui()
	_start_entrance_animation()


func _process(delta: float) -> void:
	_animation_time += delta
	_update_entrance_animation(delta)
	_update_crystals(delta)
	_crystal_canvas.queue_redraw()


# --- Background Crystal System ---

func _setup_background_crystals() -> void:
	# Create a canvas for drawing crystals behind UI
	_crystal_canvas = Node2D.new()
	_crystal_canvas.name = "CrystalCanvas"
	_crystal_canvas.z_index = -1
	add_child(_crystal_canvas)
	_crystal_canvas.draw.connect(_draw_crystals)

	# Spawn floating crystal shapes
	var viewport_size = Vector2(1280, 720)
	var rng = RandomNumberGenerator.new()
	rng.seed = 42  # Deterministic for consistent look

	for i in range(18):
		var crystal = {
			"pos": Vector2(rng.randf() * viewport_size.x, rng.randf() * viewport_size.y),
			"color": CRYSTAL_COLORS[i % CRYSTAL_COLORS.size()],
			"size": rng.randf_range(20.0, 80.0),
			"speed": rng.randf_range(5.0, 20.0),
			"angle": rng.randf() * TAU,
			"rotation_speed": rng.randf_range(-0.3, 0.3),
			"pulse_offset": rng.randf() * TAU,
			"sides": rng.randi_range(3, 6),  # Triangle to hexagon
		}
		_crystals.append(crystal)


func _update_crystals(delta: float) -> void:
	for crystal in _crystals:
		# Slow float movement
		crystal["pos"].y += sin(_animation_time * 0.5 + crystal["pulse_offset"]) * crystal["speed"] * delta
		crystal["pos"].x += cos(_animation_time * 0.3 + crystal["pulse_offset"]) * crystal["speed"] * delta * 0.5
		crystal["angle"] += crystal["rotation_speed"] * delta

		# Wrap around screen
		var viewport_size = Vector2(1280, 720)
		if crystal["pos"].x < -100: crystal["pos"].x = viewport_size.x + 100
		if crystal["pos"].x > viewport_size.x + 100: crystal["pos"].x = -100
		if crystal["pos"].y < -100: crystal["pos"].y = viewport_size.y + 100
		if crystal["pos"].y > viewport_size.y + 100: crystal["pos"].y = -100


func _draw_crystals() -> void:
	for crystal in _crystals:
		var pos: Vector2 = crystal["pos"]
		var base_size: float = crystal["size"]
		var color: Color = crystal["color"]
		var angle: float = crystal["angle"]
		var sides: int = crystal["sides"]

		# Pulse size
		var pulse = sin(_animation_time * 1.5 + crystal["pulse_offset"]) * 0.15 + 1.0
		var current_size = base_size * pulse

		# Draw crystal polygon
		var points: PackedVector2Array = []
		for i in range(sides):
			var a = angle + (TAU / sides) * i
			points.append(pos + Vector2(cos(a), sin(a)) * current_size)

		# Fill with semi-transparent color
		var fill_color = color
		fill_color.a *= (0.6 + sin(_animation_time + crystal["pulse_offset"]) * 0.4)
		_crystal_canvas.draw_colored_polygon(points, fill_color)

		# Edge glow
		var edge_color = Color(color.r, color.g, color.b, color.a * 2.0)
		edge_color.a = clamp(edge_color.a, 0.0, 0.3)
		for i in range(sides):
			_crystal_canvas.draw_line(points[i], points[(i + 1) % sides], edge_color, 1.5)


# --- UI Setup ---

func _setup_ui() -> void:
	printerr("[MainMenu] _setup_ui() started")
	# Main container — fills entire screen
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.03, 0.03, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Move background behind crystals
	move_child(bg, 0)

	# --- Title: "Хранители Симметрий" ---
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "Хранители Симметрий"
	_title_label.add_theme_font_size_override("font_size", 48)
	_title_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.0))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title_label.position = Vector2(-300, 120)
	_title_label.size = Vector2(600, 60)
	add_child(_title_label)

	# --- Subtitle ---
	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.text = "Тайны кристаллов ждут"
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.0))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_subtitle_label.position = Vector2(-250, 190)
	_subtitle_label.size = Vector2(500, 30)
	add_child(_subtitle_label)

	# --- Button container ---
	var button_container = VBoxContainer.new()
	button_container.name = "ButtonContainer"
	button_container.set_anchors_preset(Control.PRESET_CENTER)
	button_container.position = Vector2(-140, 40)
	button_container.size = Vector2(280, 220)
	button_container.add_theme_constant_override("separation", 16)
	add_child(button_container)

	# Common button style
	var btn_style_normal = StyleBoxFlat.new()
	btn_style_normal.bg_color = Color(0.1, 0.12, 0.2, 0.85)
	btn_style_normal.corner_radius_top_left = 8
	btn_style_normal.corner_radius_top_right = 8
	btn_style_normal.corner_radius_bottom_left = 8
	btn_style_normal.corner_radius_bottom_right = 8
	btn_style_normal.border_color = Color(0.35, 0.45, 0.75, 0.5)
	btn_style_normal.border_width_left = 2
	btn_style_normal.border_width_right = 2
	btn_style_normal.border_width_top = 2
	btn_style_normal.border_width_bottom = 2

	var btn_style_hover = StyleBoxFlat.new()
	btn_style_hover.bg_color = Color(0.15, 0.18, 0.3, 0.95)
	btn_style_hover.corner_radius_top_left = 8
	btn_style_hover.corner_radius_top_right = 8
	btn_style_hover.corner_radius_bottom_left = 8
	btn_style_hover.corner_radius_bottom_right = 8
	btn_style_hover.border_color = Color(0.4, 0.6, 0.9, 0.8)
	btn_style_hover.border_width_left = 2
	btn_style_hover.border_width_right = 2
	btn_style_hover.border_width_top = 2
	btn_style_hover.border_width_bottom = 2

	var btn_style_pressed = StyleBoxFlat.new()
	btn_style_pressed.bg_color = Color(0.2, 0.25, 0.4, 0.95)
	btn_style_pressed.corner_radius_top_left = 8
	btn_style_pressed.corner_radius_top_right = 8
	btn_style_pressed.corner_radius_bottom_left = 8
	btn_style_pressed.corner_radius_bottom_right = 8
	btn_style_pressed.border_color = Color(0.5, 0.7, 1.0, 0.9)
	btn_style_pressed.border_width_left = 2
	btn_style_pressed.border_width_right = 2
	btn_style_pressed.border_width_top = 2
	btn_style_pressed.border_width_bottom = 2

	# --- Start / Continue button ---
	_start_button = Button.new()
	_start_button.name = "StartButton"
	var has_save: bool = false
	if GameManager and "completed_levels" in GameManager:
		has_save = GameManager.completed_levels.size() > 0
	_start_button.text = "Продолжить" if has_save else "Начать игру"
	_start_button.add_theme_font_size_override("font_size", 22)
	_start_button.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	_start_button.custom_minimum_size = Vector2(280, 52)
	_start_button.add_theme_stylebox_override("normal", btn_style_normal)
	_start_button.add_theme_stylebox_override("hover", btn_style_hover)
	_start_button.add_theme_stylebox_override("pressed", btn_style_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_start_button.modulate = Color(1, 1, 1, 0)
	button_container.add_child(_start_button)
	printerr("[MainMenu] Start button created and added")

	# --- Settings button ---
	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = "Настройки"
	_settings_button.add_theme_font_size_override("font_size", 22)
	_settings_button.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 1.0))
	_settings_button.custom_minimum_size = Vector2(280, 52)
	_settings_button.add_theme_stylebox_override("normal", btn_style_normal)
	_settings_button.add_theme_stylebox_override("hover", btn_style_hover)
	_settings_button.add_theme_stylebox_override("pressed", btn_style_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_button.modulate = Color(1, 1, 1, 0)
	button_container.add_child(_settings_button)

	# --- Exit button ---
	_exit_button = Button.new()
	_exit_button.name = "ExitButton"
	_exit_button.text = "Выход"
	_exit_button.add_theme_font_size_override("font_size", 22)
	_exit_button.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1.0))
	_exit_button.custom_minimum_size = Vector2(280, 52)
	_exit_button.add_theme_stylebox_override("normal", btn_style_normal)
	_exit_button.add_theme_stylebox_override("hover", btn_style_hover)
	_exit_button.add_theme_stylebox_override("pressed", btn_style_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_exit_button.modulate = Color(1, 1, 1, 0)
	button_container.add_child(_exit_button)
	printerr("[MainMenu] All 3 buttons created successfully")

	# --- Progress indicator (if save exists) ---
	if has_save and GameManager and "completed_levels" in GameManager:
		var progress_label = Label.new()
		progress_label.name = "ProgressLabel"
		var completed_count: int = GameManager.completed_levels.size()
		progress_label.text = "Пройдено уровней: %d" % completed_count
		progress_label.add_theme_font_size_override("font_size", 14)
		progress_label.add_theme_color_override("font_color", Color(0.45, 0.55, 0.65, 0.7))
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		progress_label.position = Vector2(-200, -80)
		progress_label.size = Vector2(400, 25)
		add_child(progress_label)

	# --- Version label ---
	_version_label = Label.new()
	_version_label.name = "VersionLabel"
	_version_label.text = "v0.1"
	_version_label.add_theme_font_size_override("font_size", 12)
	_version_label.add_theme_color_override("font_color", Color(0.35, 0.4, 0.5, 0.5))
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_version_label.position = Vector2(-100, -30)
	_version_label.size = Vector2(80, 20)
	add_child(_version_label)


# --- Entrance Animation ---

func _start_entrance_animation() -> void:
	_title_alpha = 0.0
	_subtitle_alpha = 0.0
	_buttons_alpha = 0.0


func _update_entrance_animation(delta: float) -> void:
	# Title fades in from 0.5s to 1.5s
	if _animation_time > 0.5 and _title_alpha < 1.0:
		_title_alpha = minf(_title_alpha + delta * 1.0, 1.0)
		if _title_label:
			_title_label.add_theme_color_override("font_color",
				Color(0.75, 0.85, 1.0, _title_alpha))

	# Subtitle fades in from 1.5s to 2.5s
	if _animation_time > 1.5 and _subtitle_alpha < 1.0:
		_subtitle_alpha = minf(_subtitle_alpha + delta * 1.0, 1.0)
		if _subtitle_label:
			_subtitle_label.add_theme_color_override("font_color",
				Color(0.5, 0.6, 0.75, _subtitle_alpha * 0.7))

	# Buttons fade in from 2.0s to 3.0s
	if _animation_time > 2.0 and _buttons_alpha < 1.0:
		_buttons_alpha = minf(_buttons_alpha + delta * 1.2, 1.0)
		if _start_button:
			_start_button.modulate = Color(1, 1, 1, _buttons_alpha)
		if _settings_button:
			_settings_button.modulate = Color(1, 1, 1, _buttons_alpha)
		if _exit_button:
			_exit_button.modulate = Color(1, 1, 1, _buttons_alpha)

	# Title subtle pulse after fully visible
	if _title_alpha >= 1.0 and _title_label:
		var pulse = sin(_animation_time * 1.2) * 0.05 + 0.95
		_title_label.add_theme_color_override("font_color",
			Color(0.75 * pulse, 0.85 * pulse, 1.0, 1.0))


# --- Button Handlers ---

func _on_start_pressed() -> void:
	# Transition to the game
	printerr("[MainMenu] Start button pressed, calling GameManager.start_game()")
	GameManager.start_game()
	printerr("[MainMenu] start_game() returned")


func _on_settings_pressed() -> void:
	# Show settings screen overlay
	if _settings_screen and is_instance_valid(_settings_screen):
		return  # Already showing

	_settings_screen = preload("res://src/ui/settings_screen.tscn").instantiate()
	_settings_screen.settings_closed.connect(_on_settings_closed)
	add_child(_settings_screen)

	# Fade in
	_settings_screen.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(_settings_screen, "modulate", Color(1, 1, 1, 1), 0.3)


func _on_settings_closed() -> void:
	if _settings_screen and is_instance_valid(_settings_screen):
		var tween = create_tween()
		tween.tween_property(_settings_screen, "modulate", Color(1, 1, 1, 0), 0.25)
		tween.tween_callback(_cleanup_settings_screen)


## Free the settings screen — used as tween callback (avoids lambda/Stack underflow).
func _cleanup_settings_screen() -> void:
	if _settings_screen and is_instance_valid(_settings_screen):
		_settings_screen.queue_free()
	_settings_screen = null


func _on_exit_pressed() -> void:
	get_tree().quit()
