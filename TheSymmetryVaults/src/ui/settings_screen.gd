## SettingsScreen — Settings overlay panel
##
## Responsibilities:
## - Music/SFX volume sliders (stubs for now, no audio system yet)
## - Reset progress with confirmation dialog
## - Back button to return to main menu

class_name SettingsScreen
extends Control

signal settings_closed

# --- UI references ---
var _panel: Panel
var _title_label: Label
var _music_label: Label
var _music_slider: HSlider
var _music_value_label: Label
var _sfx_label: Label
var _sfx_slider: HSlider
var _sfx_value_label: Label
var _reset_button: Button
var _back_button: Button
var _confirm_panel: Panel
var _confirm_label: Label
var _confirm_yes: Button
var _confirm_no: Button


func _ready() -> void:
	_setup_ui()
	_load_current_settings()


func _setup_ui() -> void:
	# Full-screen semi-transparent overlay
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Main settings panel
	_panel = Panel.new()
	_panel.name = "SettingsPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-280, -230)
	_panel.size = Vector2(560, 460)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.07, 0.13, 0.96)
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_left = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.border_color = Color(0.3, 0.4, 0.7, 0.5)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	# --- Title ---
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "Настройки"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0, 1.0))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(20, 20)
	_title_label.size = Vector2(520, 40)
	_panel.add_child(_title_label)

	# --- Divider ---
	var divider = Panel.new()
	divider.position = Vector2(40, 70)
	divider.size = Vector2(480, 2)
	var div_style = StyleBoxFlat.new()
	div_style.bg_color = Color(0.3, 0.4, 0.6, 0.4)
	divider.add_theme_stylebox_override("panel", div_style)
	_panel.add_child(divider)

	# --- Music Volume ---
	_music_label = Label.new()
	_music_label.name = "MusicLabel"
	_music_label.text = "Громкость музыки"
	_music_label.add_theme_font_size_override("font_size", 16)
	_music_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 0.9))
	_music_label.position = Vector2(40, 90)
	_music_label.size = Vector2(200, 25)
	_panel.add_child(_music_label)

	_music_slider = HSlider.new()
	_music_slider.name = "MusicSlider"
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step = 0.05
	_music_slider.position = Vector2(40, 120)
	_music_slider.size = Vector2(400, 30)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_panel.add_child(_music_slider)

	_music_value_label = Label.new()
	_music_value_label.name = "MusicValueLabel"
	_music_value_label.text = "80%"
	_music_value_label.add_theme_font_size_override("font_size", 14)
	_music_value_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.8))
	_music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_music_value_label.position = Vector2(450, 90)
	_music_value_label.size = Vector2(70, 25)
	_panel.add_child(_music_value_label)

	# --- SFX Volume ---
	_sfx_label = Label.new()
	_sfx_label.name = "SfxLabel"
	_sfx_label.text = "Громкость звуков"
	_sfx_label.add_theme_font_size_override("font_size", 16)
	_sfx_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 0.9))
	_sfx_label.position = Vector2(40, 170)
	_sfx_label.size = Vector2(200, 25)
	_panel.add_child(_sfx_label)

	_sfx_slider = HSlider.new()
	_sfx_slider.name = "SfxSlider"
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.05
	_sfx_slider.position = Vector2(40, 200)
	_sfx_slider.size = Vector2(400, 30)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_panel.add_child(_sfx_slider)

	_sfx_value_label = Label.new()
	_sfx_value_label.name = "SfxValueLabel"
	_sfx_value_label.text = "100%"
	_sfx_value_label.add_theme_font_size_override("font_size", 14)
	_sfx_value_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.8))
	_sfx_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sfx_value_label.position = Vector2(450, 170)
	_sfx_value_label.size = Vector2(70, 25)
	_panel.add_child(_sfx_value_label)

	# --- Divider 2 ---
	var divider2 = Panel.new()
	divider2.position = Vector2(40, 255)
	divider2.size = Vector2(480, 2)
	divider2.add_theme_stylebox_override("panel", div_style)
	_panel.add_child(divider2)

	# --- Reset Progress Button ---
	var reset_style = StyleBoxFlat.new()
	reset_style.bg_color = Color(0.25, 0.08, 0.08, 0.85)
	reset_style.corner_radius_top_left = 8
	reset_style.corner_radius_top_right = 8
	reset_style.corner_radius_bottom_left = 8
	reset_style.corner_radius_bottom_right = 8
	reset_style.border_color = Color(0.7, 0.25, 0.2, 0.6)
	reset_style.border_width_left = 2
	reset_style.border_width_right = 2
	reset_style.border_width_top = 2
	reset_style.border_width_bottom = 2

	var reset_hover = StyleBoxFlat.new()
	reset_hover.bg_color = Color(0.35, 0.1, 0.1, 0.95)
	reset_hover.corner_radius_top_left = 8
	reset_hover.corner_radius_top_right = 8
	reset_hover.corner_radius_bottom_left = 8
	reset_hover.corner_radius_bottom_right = 8
	reset_hover.border_color = Color(0.9, 0.3, 0.25, 0.8)
	reset_hover.border_width_left = 2
	reset_hover.border_width_right = 2
	reset_hover.border_width_top = 2
	reset_hover.border_width_bottom = 2

	_reset_button = Button.new()
	_reset_button.name = "ResetButton"
	_reset_button.text = "Сбросить прогресс"
	_reset_button.add_theme_font_size_override("font_size", 16)
	_reset_button.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5, 0.9))
	_reset_button.position = Vector2(130, 280)
	_reset_button.size = Vector2(300, 44)
	_reset_button.add_theme_stylebox_override("normal", reset_style)
	_reset_button.add_theme_stylebox_override("hover", reset_hover)
	_reset_button.pressed.connect(_on_reset_pressed)
	_panel.add_child(_reset_button)

	# --- Back Button ---
	var back_style_normal = StyleBoxFlat.new()
	back_style_normal.bg_color = Color(0.1, 0.12, 0.2, 0.85)
	back_style_normal.corner_radius_top_left = 8
	back_style_normal.corner_radius_top_right = 8
	back_style_normal.corner_radius_bottom_left = 8
	back_style_normal.corner_radius_bottom_right = 8
	back_style_normal.border_color = Color(0.35, 0.45, 0.75, 0.5)
	back_style_normal.border_width_left = 2
	back_style_normal.border_width_right = 2
	back_style_normal.border_width_top = 2
	back_style_normal.border_width_bottom = 2

	var back_style_hover = StyleBoxFlat.new()
	back_style_hover.bg_color = Color(0.15, 0.18, 0.3, 0.95)
	back_style_hover.corner_radius_top_left = 8
	back_style_hover.corner_radius_top_right = 8
	back_style_hover.corner_radius_bottom_left = 8
	back_style_hover.corner_radius_bottom_right = 8
	back_style_hover.border_color = Color(0.4, 0.6, 0.9, 0.8)
	back_style_hover.border_width_left = 2
	back_style_hover.border_width_right = 2
	back_style_hover.border_width_top = 2
	back_style_hover.border_width_bottom = 2

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "Назад"
	_back_button.add_theme_font_size_override("font_size", 20)
	_back_button.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 1.0))
	_back_button.position = Vector2(170, 390)
	_back_button.size = Vector2(220, 48)
	_back_button.add_theme_stylebox_override("normal", back_style_normal)
	_back_button.add_theme_stylebox_override("hover", back_style_hover)
	_back_button.pressed.connect(_on_back_pressed)
	_panel.add_child(_back_button)

	# --- Confirmation dialog (hidden by default) ---
	_setup_confirm_dialog()


func _setup_confirm_dialog() -> void:
	_confirm_panel = Panel.new()
	_confirm_panel.name = "ConfirmPanel"
	_confirm_panel.visible = false
	_confirm_panel.set_anchors_preset(Control.PRESET_CENTER)
	_confirm_panel.position = Vector2(-220, -90)
	_confirm_panel.size = Vector2(440, 180)
	var confirm_style = StyleBoxFlat.new()
	confirm_style.bg_color = Color(0.08, 0.05, 0.05, 0.97)
	confirm_style.corner_radius_top_left = 12
	confirm_style.corner_radius_top_right = 12
	confirm_style.corner_radius_bottom_left = 12
	confirm_style.corner_radius_bottom_right = 12
	confirm_style.border_color = Color(0.8, 0.3, 0.25, 0.7)
	confirm_style.border_width_left = 2
	confirm_style.border_width_right = 2
	confirm_style.border_width_top = 2
	confirm_style.border_width_bottom = 2
	_confirm_panel.add_theme_stylebox_override("panel", confirm_style)
	add_child(_confirm_panel)

	_confirm_label = Label.new()
	_confirm_label.name = "ConfirmLabel"
	_confirm_label.text = "Вы уверены?\nВесь прогресс будет потерян!"
	_confirm_label.add_theme_font_size_override("font_size", 16)
	_confirm_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6, 1.0))
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.position = Vector2(20, 20)
	_confirm_label.size = Vector2(400, 60)
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_panel.add_child(_confirm_label)

	# Yes / No buttons
	var yes_style = StyleBoxFlat.new()
	yes_style.bg_color = Color(0.6, 0.15, 0.1, 0.9)
	yes_style.corner_radius_top_left = 6
	yes_style.corner_radius_top_right = 6
	yes_style.corner_radius_bottom_left = 6
	yes_style.corner_radius_bottom_right = 6

	_confirm_yes = Button.new()
	_confirm_yes.name = "ConfirmYes"
	_confirm_yes.text = "Да, сбросить"
	_confirm_yes.add_theme_font_size_override("font_size", 16)
	_confirm_yes.add_theme_color_override("font_color", Color(1.0, 0.85, 0.8, 1.0))
	_confirm_yes.position = Vector2(40, 110)
	_confirm_yes.size = Vector2(160, 44)
	_confirm_yes.add_theme_stylebox_override("normal", yes_style)
	_confirm_yes.pressed.connect(_on_confirm_reset)
	_confirm_panel.add_child(_confirm_yes)

	var no_style = StyleBoxFlat.new()
	no_style.bg_color = Color(0.12, 0.14, 0.25, 0.9)
	no_style.corner_radius_top_left = 6
	no_style.corner_radius_top_right = 6
	no_style.corner_radius_bottom_left = 6
	no_style.corner_radius_bottom_right = 6

	_confirm_no = Button.new()
	_confirm_no.name = "ConfirmNo"
	_confirm_no.text = "Отмена"
	_confirm_no.add_theme_font_size_override("font_size", 16)
	_confirm_no.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 1.0))
	_confirm_no.position = Vector2(240, 110)
	_confirm_no.size = Vector2(160, 44)
	_confirm_no.add_theme_stylebox_override("normal", no_style)
	_confirm_no.pressed.connect(_on_cancel_reset)
	_confirm_panel.add_child(_confirm_no)


func _load_current_settings() -> void:
	_music_slider.value = GameManager.music_volume
	_sfx_slider.value = GameManager.sfx_volume
	_music_value_label.text = "%d%%" % int(GameManager.music_volume * 100)
	_sfx_value_label.text = "%d%%" % int(GameManager.sfx_volume * 100)


# --- Signal Handlers ---

func _on_music_volume_changed(value: float) -> void:
	GameManager.music_volume = value
	_music_value_label.text = "%d%%" % int(value * 100)
	GameManager.save_game()


func _on_sfx_volume_changed(value: float) -> void:
	GameManager.sfx_volume = value
	_sfx_value_label.text = "%d%%" % int(value * 100)
	GameManager.save_game()


func _on_reset_pressed() -> void:
	# Show confirmation dialog
	_confirm_panel.visible = true
	_confirm_panel.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(_confirm_panel, "modulate", Color(1, 1, 1, 1), 0.2)


func _on_confirm_reset() -> void:
	# Actually reset all progress
	GameManager.current_act = 1
	GameManager.current_level = 1
	GameManager.completed_levels.clear()
	GameManager.level_states.clear()
	GameManager.save_game()

	# Hide confirm dialog
	_confirm_panel.visible = false

	# Update reset button text to confirm
	_reset_button.text = "Прогресс сброшен!"
	_reset_button.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 0.9))
	_reset_button.disabled = true

	# Restore after 2 seconds
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(_reset_button):
			_reset_button.text = "Сбросить прогресс"
			_reset_button.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5, 0.9))
			_reset_button.disabled = false
	)


func _on_cancel_reset() -> void:
	var tween = create_tween()
	tween.tween_property(_confirm_panel, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.tween_callback(_hide_confirm_panel)


## Hide confirm panel — used as tween callback (avoids lambda/Stack underflow).
func _hide_confirm_panel() -> void:
	if _confirm_panel and is_instance_valid(_confirm_panel):
		_confirm_panel.visible = false


func _on_back_pressed() -> void:
	settings_closed.emit()
