## HudBuilder — Creates and manages all HUD elements for LevelScene.
##
## Responsibilities:
## - Create all HUD labels, buttons, panels
## - Instruction panel, generators panel, complete summary panel
## - Target preview container
## - Key buttons container
## - Split-screen HUD for map mode (build_split_hud)
## - Provide helper methods for stylebox creation

class_name HudBuilder
extends RefCounted


## Create a StyleBoxFlat with common settings.
static func make_stylebox(bg: Color, corner: int, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, corner)
	style.border_color = border_color
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		style.set(prop, border_width)
	return style


## Add a label to a parent node.
static func add_label(parent: Node, lname: String, text: String, font_size: int,
		color: Color, pos: Vector2, sz: Vector2 = Vector2.ZERO,
		align: int = -1, ignore_mouse: bool = false) -> Label:
	var label = Label.new()
	label.name = lname
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.position = pos
	if sz != Vector2.ZERO:
		label.size = sz
	if align >= 0:
		label.horizontal_alignment = align
	if ignore_mouse:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Build all HUD elements. Returns the target_preview Control.
static func build_hud(hud_layer: CanvasLayer,
		on_reset: Callable, on_check: Callable,
		on_help: Callable, on_next_level: Callable,
		on_repeat: Callable = Callable(),
		on_combine: Callable = Callable()) -> Control:
	# Top-left labels
	add_label(hud_layer, "LevelNumberLabel", "", 12, Color(0.55, 0.6, 0.7, 0.8), Vector2(20, 8), Vector2(300, 18))
	add_label(hud_layer, "TitleLabel", "", 24, Color(0.8, 0.85, 0.95, 0.9), Vector2(20, 26))
	add_label(hud_layer, "SubtitleLabel", "", 14, Color(0.6, 0.65, 0.75, 0.7), Vector2(20, 56))

	# Target preview
	var target_preview := _build_target_preview_container(hud_layer)

	# Right-side counter/keyring
	add_label(hud_layer, "CounterLabel", "Ключи: 0 / 0", 18, Color(0.7, 0.8, 0.9, 0.85), Vector2(1020, 15), Vector2(240, 30), HORIZONTAL_ALIGNMENT_RIGHT)
	add_label(hud_layer, "KeyRingLabel", "", 13, Color(0.6, 0.75, 0.6, 0.8), Vector2(880, 45), Vector2(400, 20), HORIZONTAL_ALIGNMENT_LEFT, true)

	# Hint label (bottom center)
	add_label(hud_layer, "HintLabel", "", 15, Color(0.7, 0.7, 0.5, 0.0), Vector2(340, 670), Vector2(600, 40), HORIZONTAL_ALIGNMENT_CENTER)

	# Action buttons
	_build_action_buttons(hud_layer, on_reset, on_check)

	# Repeat and Combine buttons (hidden by default, shown when keys are found)
	_build_repeat_combine_buttons(hud_layer, on_repeat, on_combine)

	# Status label
	add_label(hud_layer, "StatusLabel", "", 13, Color(0.65, 0.7, 0.8, 0.7), Vector2(20, 590), Vector2(400, 25))
	add_label(hud_layer, "ViolationLabel", "", 14, Color(1.0, 0.4, 0.35, 0.0), Vector2(290, 640), Vector2(700, 30), HORIZONTAL_ALIGNMENT_CENTER)

	# Instruction panel
	_build_instruction_panel(hud_layer)

	# Help button
	_build_help_button(hud_layer, on_help)

	# Button hint labels
	add_label(hud_layer, "ResetHintLabel", "", 11, Color(0.6, 0.65, 0.8, 0.0), Vector2(20, 662), Vector2(120, 20))
	add_label(hud_layer, "CheckHintLabel", "", 11, Color(0.6, 0.65, 0.8, 0.0), Vector2(150, 662), Vector2(190, 20))

	# Key buttons container
	var kbc = VBoxContainer.new()
	kbc.name = "KeyButtonsContainer"
	kbc.position = Vector2(880, 65)
	kbc.size = Vector2(380, 280)
	kbc.visible = false
	kbc.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_layer.add_child(kbc)

	# Combine label
	add_label(hud_layer, "CombineLabel", "", 14, Color(0.8, 0.7, 1.0, 0.0), Vector2(290, 590), Vector2(700, 25), HORIZONTAL_ALIGNMENT_CENTER)

	# Generators panel
	_build_generators_panel(hud_layer)

	# Complete summary panel
	_build_complete_summary_panel(hud_layer, on_next_level)

	return target_preview


static func _build_target_preview_container(hud_layer: CanvasLayer) -> Control:
	var tp = Control.new()
	tp.name = "TargetPreview"
	tp.position = Vector2(20, 80)
	tp.size = Vector2(150, 150)
	tp.custom_minimum_size = Vector2(150, 150)
	tp.visible = false
	tp.clip_contents = false
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(tp)

	var bg = Panel.new()
	bg.name = "TargetBG"
	bg.position = Vector2.ZERO
	bg.size = Vector2(150, 150)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", make_stylebox(
		Color(0.04, 0.04, 0.08, 0.85), 8, Color(0.75, 0.65, 0.2, 0.7), 2))
	tp.add_child(bg)

	var title = Label.new()
	title.name = "TargetTitle"
	title.text = "Цель"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 2)
	title.size = Vector2(150, 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.add_child(title)
	return tp


static func _build_action_buttons(hud_layer: CanvasLayer, on_reset: Callable, on_check: Callable) -> void:
	var reset_btn = Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = "СБРОС"
	reset_btn.add_theme_font_size_override("font_size", 14)
	reset_btn.position = Vector2(20, 620)
	reset_btn.size = Vector2(120, 40)
	reset_btn.pressed.connect(on_reset)
	hud_layer.add_child(reset_btn)

	var check_btn = Button.new()
	check_btn.name = "CheckButton"
	check_btn.text = "ПРОВЕРИТЬ УЗОР"
	check_btn.add_theme_font_size_override("font_size", 14)
	check_btn.position = Vector2(150, 620)
	check_btn.size = Vector2(190, 40)
	check_btn.tooltip_text = "Проверить, открывает ли текущее расположение кристаллов замок.\nСоберите картинку-цель и проверьте!"
	check_btn.pressed.connect(on_check)
	hud_layer.add_child(check_btn)


static func _build_repeat_combine_buttons(hud_layer: CanvasLayer,
		on_repeat: Callable, on_combine: Callable) -> void:
	var repeat_btn = Button.new()
	repeat_btn.name = "RepeatButton"
	repeat_btn.text = "ПОВТОРИТЬ"
	repeat_btn.add_theme_font_size_override("font_size", 14)
	repeat_btn.position = Vector2(350, 620)
	repeat_btn.size = Vector2(170, 40)
	repeat_btn.visible = false
	if on_repeat.is_valid():
		repeat_btn.pressed.connect(on_repeat)
	hud_layer.add_child(repeat_btn)

	var combine_btn = Button.new()
	combine_btn.name = "CombineButton"
	combine_btn.text = "СКОМБИНИРОВАТЬ"
	combine_btn.add_theme_font_size_override("font_size", 14)
	combine_btn.position = Vector2(530, 620)
	combine_btn.size = Vector2(200, 40)
	combine_btn.visible = false
	if on_combine.is_valid():
		combine_btn.pressed.connect(on_combine)
	hud_layer.add_child(combine_btn)


static func _build_instruction_panel(hud_layer: CanvasLayer) -> void:
	var panel = Panel.new()
	panel.name = "InstructionPanel"
	panel.visible = false
	panel.position = Vector2(190, 130)
	panel.size = Vector2(900, 370)
	panel.add_theme_stylebox_override("panel", make_stylebox(
		Color(0.06, 0.06, 0.12, 0.94), 14, Color(0.35, 0.45, 0.75, 0.6), 2))
	hud_layer.add_child(panel)

	add_label(panel, "InstrTitle", "", 22, Color(0.85, 0.9, 1.0, 1.0), Vector2(20, 18), Vector2(860, 30), HORIZONTAL_ALIGNMENT_CENTER)
	add_label(panel, "InstrGoal", "", 17, Color(0.4, 0.9, 0.5, 1.0), Vector2(40, 58), Vector2(820, 28), HORIZONTAL_ALIGNMENT_CENTER)
	var body = add_label(panel, "InstrBody", "", 15, Color(0.72, 0.77, 0.88, 0.95), Vector2(50, 98), Vector2(800, 150), HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_label(panel, "InstrNewMechanic", "", 15, Color(1.0, 0.85, 0.3, 0.9), Vector2(50, 265), Vector2(800, 30), HORIZONTAL_ALIGNMENT_CENTER)
	var dismiss = add_label(panel, "InstrDismiss", "Нажмите в любом месте, чтобы начать", 13,
		Color(0.55, 0.65, 0.5, 0.75), Vector2(20, 320), Vector2(860, 25), HORIZONTAL_ALIGNMENT_CENTER)


static func _build_help_button(hud_layer: CanvasLayer, on_help: Callable) -> void:
	var btn = Button.new()
	btn.name = "HelpButton"
	btn.text = "?"
	btn.add_theme_font_size_override("font_size", 18)
	btn.position = Vector2(1235, 15)
	btn.size = Vector2(35, 35)
	btn.add_theme_stylebox_override("normal", make_stylebox(
		Color(0.15, 0.18, 0.28, 0.8), 16, Color(0.4, 0.5, 0.7, 0.5), 1))
	btn.pressed.connect(on_help)
	hud_layer.add_child(btn)


static func _build_generators_panel(hud_layer: CanvasLayer) -> void:
	var panel = Panel.new()
	panel.name = "GeneratorsPanel"
	panel.visible = false
	panel.position = Vector2(340, 140)
	panel.size = Vector2(600, 120)
	panel.add_theme_stylebox_override("panel", make_stylebox(
		Color(0.06, 0.08, 0.16, 0.92), 10, Color(0.5, 0.7, 0.4, 0.6), 2))
	hud_layer.add_child(panel)
	add_label(panel, "GenTitle", "Генераторы", 18, Color(0.5, 0.9, 0.4, 1.0), Vector2(20, 12), Vector2(560, 28), HORIZONTAL_ALIGNMENT_CENTER)
	var body = add_label(panel, "GenBody", "", 14, Color(0.75, 0.82, 0.9, 0.95), Vector2(20, 45), Vector2(560, 60), HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func _build_complete_summary_panel(hud_layer: CanvasLayer, on_next_level: Callable) -> void:
	var panel = Panel.new()
	panel.name = "CompleteSummaryPanel"
	panel.visible = false
	panel.position = Vector2(240, 60)
	panel.size = Vector2(800, 560)
	panel.add_theme_stylebox_override("panel", make_stylebox(
		Color(0.05, 0.07, 0.13, 0.95), 14, Color(0.3, 0.9, 0.4, 0.6), 2))
	hud_layer.add_child(panel)

	add_label(panel, "SummaryTitle", "", 24, Color(0.3, 1.0, 0.5, 1.0), Vector2(20, 16), Vector2(760, 35), HORIZONTAL_ALIGNMENT_CENTER)
	add_label(panel, "SummaryLevelInfo", "", 16, Color(0.7, 0.75, 0.85, 0.9), Vector2(20, 55), Vector2(760, 25), HORIZONTAL_ALIGNMENT_CENTER)
	add_label(panel, "SummaryGroupInfo", "", 15, Color(0.8, 0.75, 0.5, 0.9), Vector2(20, 82), Vector2(760, 25), HORIZONTAL_ALIGNMENT_CENTER)

	var div = Panel.new()
	div.name = "SummaryDivider"
	div.position = Vector2(80, 115)
	div.size = Vector2(640, 2)
	var ds = StyleBoxFlat.new()
	ds.bg_color = Color(0.3, 0.4, 0.6, 0.4)
	div.add_theme_stylebox_override("panel", ds)
	panel.add_child(div)

	add_label(panel, "SummaryKeysTitle", "Найденные ключи:", 14, Color(0.6, 0.7, 0.8, 0.8), Vector2(20, 125), Vector2(760, 22), HORIZONTAL_ALIGNMENT_CENTER)
	var skl = add_label(panel, "SummaryKeysList", "", 14, Color(0.72, 0.8, 0.68, 0.95), Vector2(60, 152), Vector2(680, 240))
	skl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sln = add_label(panel, "SummaryLearnedNote", "", 13, Color(0.6, 0.65, 0.8, 0.8), Vector2(40, 400), Vector2(720, 45), HORIZONTAL_ALIGNMENT_CENTER)
	sln.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sgi = add_label(panel, "SummaryGenInfo", "", 13, Color(0.5, 0.9, 0.4, 0.85), Vector2(40, 448), Vector2(720, 40), HORIZONTAL_ALIGNMENT_CENTER)
	sgi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var btn = Button.new()
	btn.name = "SummaryNextButton"
	btn.text = "ВЕРНУТЬСЯ НА КАРТУ" if GameManager.hall_tree != null else "СЛЕДУЮЩИЙ УРОВЕНЬ  >"
	btn.add_theme_font_size_override("font_size", 20)
	btn.position = Vector2(200, 495)
	btn.size = Vector2(400, 50)
	btn.visible = false
	btn.pressed.connect(on_next_level)
	panel.add_child(btn)


## Populate and show the complete summary panel.
static func show_complete_summary(hud_layer: CanvasLayer, meta: Dictionary,
		show_generators_hint: bool, level_data: Dictionary, level_id: String,
		target_perm_names: Dictionary, keys_text: String,
		echo_hint_system, scene: Node2D) -> void:
	var p = hud_layer.get_node_or_null("CompleteSummaryPanel")
	if p == null: return
	var _s := func(n: String, t: String) -> void: var l = p.get_node_or_null(n); if l: l.text = t
	_s.call("SummaryTitle", "Зал открыт!")
	_s.call("SummaryLevelInfo", "Уровень %d — %s" % [meta.get("level", 0), meta.get("title", "")])
	_s.call("SummaryGroupInfo", LevelTextContent.format_group_name(meta.get("group_name", ""), meta.get("group_order", 0)))
	_s.call("SummaryKeysList", keys_text)
	_s.call("SummaryLearnedNote", LevelTextContent.get_learned_note(meta))
	var sgi = p.get_node_or_null("SummaryGenInfo")
	if sgi: sgi.text = LevelTextContent.get_generators_text(level_data, target_perm_names) if show_generators_hint else ""; sgi.visible = show_generators_hint
	var seal = p.get_node_or_null("SummarySealInfo")
	if seal == null:
		seal = Label.new(); seal.name = "SummarySealInfo"; seal.add_theme_font_size_override("font_size", 14)
		seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; seal.position = Vector2(50, 465); seal.size = Vector2(700, 25); p.add_child(seal)
	if echo_hint_system and echo_hint_system.used_solution_hint():
		seal.text = "Эхо-видение использовано — Печать совершенства потеряна"; seal.add_theme_color_override("font_color", Color(0.8, 0.5, 0.3, 0.8))
	else: seal.text = "Печать совершенства получена"; seal.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 0.8))
	seal.visible = true
	var nb = p.get_node_or_null("SummaryNextButton")
	if nb:
		if GameManager.hall_tree != null: nb.text = "ВЕРНУТЬСЯ НА КАРТУ"; nb.visible = true
		else: nb.visible = GameManager.get_next_level_path(level_id) != ""
	p.visible = true; p.modulate = Color(1, 1, 1, 0); scene.create_tween().tween_property(p, "modulate", Color(1, 1, 1, 1), 0.5)


## Setup or update the target preview miniature.
static func setup_target_preview(target_preview: Control, hud_layer: CanvasLayer,
		nodes_data: Array, edges_data: Array, TargetPreviewDrawClass) -> Control:
	if target_preview == null:
		target_preview = Control.new(); target_preview.name = "TargetPreview"
		target_preview.position = Vector2(20, 80); target_preview.size = Vector2(150, 150)
		target_preview.custom_minimum_size = Vector2(150, 150); target_preview.clip_contents = false
		target_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE; hud_layer.add_child(target_preview)
		var bg = Panel.new(); bg.name = "TargetBG"; bg.position = Vector2.ZERO; bg.size = Vector2(150, 150)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_theme_stylebox_override("panel", make_stylebox(Color(0.04, 0.04, 0.08, 0.85), 8, Color(0.75, 0.65, 0.2, 0.7), 2))
		target_preview.add_child(bg)
		var tl = Label.new(); tl.name = "TargetTitle"; tl.text = "Цель"
		tl.add_theme_font_size_override("font_size", 11); tl.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.position = Vector2(0, 2); tl.size = Vector2(150, 16)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE; target_preview.add_child(tl)
	var old = target_preview.get_node_or_null("TargetGraphDraw")
	if old: target_preview.remove_child(old); old.queue_free()
	target_preview.visible = true
	var dn = TargetPreviewDrawClass.new(); dn.name = "TargetGraphDraw"; dn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dn.position = Vector2(5, 18); dn.size = Vector2(140, 127); dn.custom_minimum_size = Vector2(140, 127)
	target_preview.add_child(dn); dn.setup(nodes_data, edges_data, Vector2(140, 127))
	update_target_preview_border(target_preview, false)
	return target_preview


## Update the target preview border based on identity found.
static func update_target_preview_border(target_preview: Control, identity_found: bool) -> void:
	if target_preview == null: return
	var bg = target_preview.get_node_or_null("TargetBG")
	if bg == null: return
	var st: StyleBoxFlat = bg.get_theme_stylebox("panel") as StyleBoxFlat
	if st == null: return
	var ns := st.duplicate() as StyleBoxFlat
	ns.border_color = Color(0.3, 0.9, 0.4, 0.7) if identity_found else Color(0.75, 0.65, 0.2, 0.7)
	bg.add_theme_stylebox_override("panel", ns)
	var tl = target_preview.get_node_or_null("TargetTitle")
	if tl:
		if identity_found: tl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 0.9)); tl.text = "Цель ✓"
		else: tl.add_theme_color_override("font_color", Color(0.75, 0.65, 0.2, 0.9)); tl.text = "Цель"


## Populate and show the instruction panel.
static func show_instruction_panel(hud_layer: CanvasLayer, level_data: Dictionary) -> void:
	var p = hud_layer.get_node_or_null("InstructionPanel")
	if p == null: return
	var meta = level_data.get("meta", {})
	var _s := func(n: String, t: String) -> void: var l = p.get_node_or_null(n); if l: l.text = t
	_s.call("InstrTitle", "Уровень %d — %s" % [meta.get("level", 1), meta.get("title", "")])
	_s.call("InstrGoal", "Найдите все %d ключей, чтобы открыть этот зал" % meta.get("group_order", 1))
	var texts := LevelTextContent.get_instruction_text(meta, level_data.get("mechanics", {}))
	_s.call("InstrBody", texts["body"])
	var inm = p.get_node_or_null("InstrNewMechanic")
	if inm: inm.text = texts["new_mechanic"]; inm.visible = texts["new_mechanic"] != ""
	p.visible = true; p.modulate = Color(1, 1, 1, 1)

## Fade-dismiss the instruction panel.
static func dismiss_instruction_panel(hud_layer: CanvasLayer, scene: Node2D) -> void:
	var p = hud_layer.get_node_or_null("InstructionPanel")
	if p: var tw = scene.create_tween(); tw.tween_property(p, "modulate", Color(1, 1, 1, 0), 0.3); tw.tween_callback(_hide_node.bind(p))


## Hide a node if it is still valid (used as tween_callback to avoid lambdas).
static func _hide_node(node: Node) -> void:
	if is_instance_valid(node): node.visible = false

## Rebuild the clickable key buttons in the KeyButtonsContainer.
static func rebuild_key_buttons(hud_layer: CanvasLayer, key_ring: KeyRing,
		get_display_name: Callable, on_repeat_clicked: Callable) -> void:
	var container = hud_layer.get_node_or_null("KeyButtonsContainer")
	if container == null or key_ring == null:
		return
	for child in container.get_children():
		child.queue_free()
	if key_ring.count() == 0:
		container.visible = false
		return
	container.visible = true
	for i in range(key_ring.count()):
		var display_name: String = get_display_name.call(i)
		var row = HBoxContainer.new()
		row.name = "KeyRow_%d" % i
		row.custom_minimum_size = Vector2(380, 28)
		var label = Label.new()
		label.text = "[%d] %s" % [i + 1, display_name]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6, 0.9))
		label.custom_minimum_size = Vector2(220, 24)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var repeat_btn = Button.new()
		repeat_btn.name = "RepeatBtn_%d" % i
		repeat_btn.text = "▶ Повторить"
		repeat_btn.add_theme_font_size_override("font_size", 11)
		repeat_btn.custom_minimum_size = Vector2(120, 24)
		repeat_btn.pressed.connect(on_repeat_clicked.bind(i))
		repeat_btn.add_theme_stylebox_override("normal", make_stylebox(Color(0.12, 0.18, 0.28, 0.6), 4, Color.TRANSPARENT, 0))
		repeat_btn.add_theme_stylebox_override("hover", make_stylebox(Color(0.18, 0.28, 0.42, 0.7), 4, Color.TRANSPARENT, 0))
		repeat_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 0.9))
		row.add_child(repeat_btn)
		container.add_child(row)


## ─── Split-screen HUD ────────────────────────────────────────────────
## Divides the screen into 5 framed zones:
##   1. Target zone (top-left corner) — target pattern preview (seal)
##   2. Crystal zone (left, below target) — crystal puzzle + controls
##   3. Map zone (top-right) — room map (Cayley graph)
##   4. Key bar zone (bottom-left) — discovered keys
##   5. Hints zone (bottom-right) — status / hints / echo
## Each zone has a visible border/frame so they never overlap.
## Returns Dictionary {crystal_rect, map_rect, key_bar_rect, hints_rect,
##                     target_rect, target_preview}.

## Height of the bottom row (keys + hints).
const BOTTOM_ROW_HEIGHT := 100

## Border style constants for zone frames.
const FRAME_BORDER_COLOR := Color(0.2, 0.28, 0.45, 0.7)
const FRAME_BG_COLOR := Color(0.03, 0.03, 0.06, 0.6)
const FRAME_CORNER := 6
const FRAME_BORDER_WIDTH := 2

## Create a Panel frame for a zone.
static func _build_zone_frame(parent: Node, frame_name: String, rect: Rect2,
		title: String = "", title_color: Color = Color.WHITE) -> Panel:
	var frame := Panel.new()
	frame.name = frame_name
	frame.position = rect.position
	frame.size = rect.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := make_stylebox(FRAME_BG_COLOR, FRAME_CORNER, FRAME_BORDER_COLOR, FRAME_BORDER_WIDTH)
	frame.add_theme_stylebox_override("panel", style)
	parent.add_child(frame)
	if title != "":
		var tl := Label.new()
		tl.name = frame_name + "Title"
		tl.text = title
		tl.add_theme_font_size_override("font_size", 10)
		tl.add_theme_color_override("font_color", title_color)
		tl.position = Vector2(8, 3)
		tl.size = Vector2(rect.size.x - 16, 14)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tl)
	return frame


## Build the split-screen HUD layout with framed zones.
## [br][br]
## [param hud_layer] – CanvasLayer to host HUD nodes.
## [param viewport_size] – current viewport size (Vector2).
## [param callbacks] – Dictionary with keys:
##   on_reset, on_check, on_help, on_next_level (all Callable).
static func build_split_hud(hud_layer: CanvasLayer,
		viewport_size: Vector2,
		callbacks: Dictionary) -> Dictionary:

	var w := viewport_size.x
	var h := viewport_size.y
	var bottom_h := BOTTOM_ROW_HEIGHT
	var gap := 2  # gap between zone frames

	# ── Zone rectangles (5-zone layout) ──────────────────────────────
	# Left column is split: target zone on top, crystal zone below.
	# Right column: map (top), hints (bottom).
	var top_h := h - bottom_h - gap
	var half_w := floorf(w * 0.5)
	var target_h := 170  # height for the target preview zone (seal)

	var target_rect  := Rect2(0, 0, half_w - gap, target_h)
	var crystal_rect := Rect2(0, target_h + gap, half_w - gap, top_h - target_h - gap)
	var map_rect     := Rect2(half_w + gap, 0, w - half_w - gap, top_h)
	var key_bar_rect := Rect2(0, top_h + gap, half_w - gap, bottom_h)
	var hints_rect   := Rect2(half_w + gap, top_h + gap, w - half_w - gap, bottom_h)

	# ── Build visible frame panels ───────────────────────────────────
	_build_zone_frame(hud_layer, "TargetFrame", target_rect,
		"Цель", Color(0.75, 0.65, 0.2, 0.7))
	_build_zone_frame(hud_layer, "CrystalFrame", crystal_rect,
		"", Color(0.4, 0.5, 0.7, 0.5))
	_build_zone_frame(hud_layer, "MapFrame", map_rect,
		"Карта комнат", Color(0.4, 0.6, 0.5, 0.7))
	_build_zone_frame(hud_layer, "KeyBarFrame", key_bar_rect,
		"Ключи", Color(0.6, 0.55, 0.3, 0.7))
	_build_zone_frame(hud_layer, "HintsFrame", hints_rect,
		"Подсказки", Color(0.5, 0.5, 0.35, 0.7))

	# ── Internal padding ─────────────────────────────────────────────
	var pad := 10  # padding inside frames
	var lw := crystal_rect.size.x   # left-half width

	# ── Target zone: labels + target preview ─────────────────────────
	var tgt_x := target_rect.position.x
	var tgt_y := target_rect.position.y

	add_label(hud_layer, "LevelNumberLabel", "", 11,
		Color(0.55, 0.6, 0.7, 0.8),
		Vector2(tgt_x + pad, tgt_y + 18), Vector2(lw * 0.4, 16))
	add_label(hud_layer, "TitleLabel", "", 16,
		Color(0.8, 0.85, 0.95, 0.9),
		Vector2(tgt_x + pad, tgt_y + 34), Vector2(lw * 0.4, 22))
	add_label(hud_layer, "SubtitleLabel", "", 11,
		Color(0.6, 0.65, 0.75, 0.7),
		Vector2(tgt_x + pad, tgt_y + 56), Vector2(lw * 0.4, 16))

	# Counter (rooms)
	add_label(hud_layer, "CounterLabel", "Комнаты: 0 / 0", 13,
		Color(0.7, 0.8, 0.9, 0.85),
		Vector2(tgt_x + pad, tgt_y + 76), Vector2(lw * 0.4, 20),
		HORIZONTAL_ALIGNMENT_LEFT, true)

	# Target preview miniature — positioned right-side of target zone
	var target_preview := _build_target_preview_container(hud_layer)
	target_preview.position = Vector2(tgt_x + lw - 160, tgt_y + 14)

	# ── Help button (top-right of target zone) ───────────────────────
	var on_help: Callable = callbacks.get("on_help", Callable())
	if on_help.is_valid():
		_build_help_button_split(hud_layer, on_help, lw)

	# ── Hint / violation / status labels — placed inside HintsFrame ──
	var hints_x := hints_rect.position.x + pad
	var hints_y := hints_rect.position.y + 18  # below frame title
	var hints_w := hints_rect.size.x - pad * 2
	var hints_inner_h := hints_rect.size.y - 22

	add_label(hud_layer, "HintLabel", "", 13,
		Color(0.7, 0.7, 0.5, 0.0),
		Vector2(hints_x, hints_y), Vector2(hints_w, hints_inner_h * 0.4),
		HORIZONTAL_ALIGNMENT_CENTER)

	add_label(hud_layer, "ViolationLabel", "", 12,
		Color(1.0, 0.4, 0.35, 0.0),
		Vector2(hints_x, hints_y + hints_inner_h * 0.4), Vector2(hints_w, hints_inner_h * 0.3),
		HORIZONTAL_ALIGNMENT_CENTER)

	add_label(hud_layer, "StatusLabel", "", 11,
		Color(0.65, 0.7, 0.8, 0.7),
		Vector2(hints_x, hints_y + hints_inner_h * 0.7), Vector2(hints_w, hints_inner_h * 0.3))

	# ── Overlay panels (centred over the full viewport) ──────────────
	_build_instruction_panel(hud_layer)
	_build_complete_summary_panel(hud_layer,
		callbacks.get("on_next_level", Callable()))

	return {
		"crystal_rect": crystal_rect,
		"map_rect": map_rect,
		"key_bar_rect": key_bar_rect,
		"hints_rect": hints_rect,
		"target_rect": target_rect,
		"target_preview": target_preview,
	}


## Help button positioned in the top-right corner of the left half.
static func _build_help_button_split(hud_layer: CanvasLayer,
		on_help: Callable, half_w: float) -> void:
	var btn = Button.new()
	btn.name = "HelpButton"
	btn.text = "?"
	btn.add_theme_font_size_override("font_size", 16)
	btn.position = Vector2(half_w - 44, 10)
	btn.size = Vector2(32, 32)
	btn.add_theme_stylebox_override("normal", make_stylebox(
		Color(0.15, 0.18, 0.28, 0.8), 14, Color(0.4, 0.5, 0.7, 0.5), 1))
	btn.pressed.connect(on_help)
	hud_layer.add_child(btn)


