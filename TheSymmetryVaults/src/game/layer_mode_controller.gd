## LayerModeController — Orchestrates layer-specific behavior within LevelScene.
##
## When LevelScene loads a level for Layer 2+, this controller:
##   - Disables crystal dragging (graph is read-only)
##   - Creates the appropriate UI panel (InversePairingPanel for Layer 2)
##   - Manages layer-specific validation and completion
##   - Saves layer progress to GameManager
##
## Future layers (3-5) will add new modes here.
class_name LayerModeController
extends RefCounted

# ── Layer mode enum ──────────────────────────────────────────────────

enum LayerMode {
	LAYER_1,             ## Default: crystal swapping, key discovery
	LAYER_2_INVERSE,     ## Inverse key pairing
	## Future:
	## LAYER_3_GROUP,     ## Composition table / closure
	## LAYER_4_NORMAL,    ## Normal subgroup identification
	## LAYER_5_QUOTIENT,  ## Quotient group construction
}

# ── Signals ──────────────────────────────────────────────────────────

signal layer_completed(layer: int, hall_id: String)

# ── State ────────────────────────────────────────────────────────────

var current_layer: LayerMode = LayerMode.LAYER_1
var layer_number: int = 1
var inverse_pair_mgr: InversePairManager = null
var pairing_panel: InversePairingPanel = null
var _level_scene = null  ## Weak reference to LevelScene (no type to avoid circular)
var _hall_id: String = ""

# ── Layer 2 color scheme constants ───────────────────────────────────

const L2_GREEN := Color(0.2, 0.85, 0.4, 1.0)
const L2_GREEN_DIM := Color(0.15, 0.55, 0.3, 0.7)
const L2_GREEN_BG := Color(0.02, 0.06, 0.03, 0.8)
const L2_GREEN_BORDER := Color(0.15, 0.45, 0.25, 0.7)


# ── Setup ────────────────────────────────────────────────────────────

## Initialize for a specific layer.
## layer: the layer number (1-5)
## level_data: the full level JSON dictionary
## level_scene: the LevelScene instance
func setup(layer: int, level_data: Dictionary, level_scene) -> void:
	layer_number = layer
	_level_scene = level_scene
	_hall_id = GameManager.current_hall_id

	match layer:
		1:
			current_layer = LayerMode.LAYER_1
			# No special setup — default LevelScene behavior
		2:
			current_layer = LayerMode.LAYER_2_INVERSE
			_setup_layer_2(level_data, level_scene)
		_:
			push_warning("LayerModeController: Layer %d not yet implemented" % layer)
			current_layer = LayerMode.LAYER_1


## Clean up all layer-specific resources.
func cleanup() -> void:
	if pairing_panel != null and is_instance_valid(pairing_panel):
		pairing_panel.queue_free()
		pairing_panel = null
	inverse_pair_mgr = null
	_level_scene = null


# ── Layer 2: Inverse Key Pairing ─────────────────────────────────────

func _setup_layer_2(level_data: Dictionary, level_scene) -> void:
	# 1. Disable crystal dragging (graph is read-only on Layer 2)
	for crystal in level_scene.crystals.values():
		if crystal is CrystalNode:
			crystal.set_draggable(false)

	# 2. Hide Layer 1 UI elements that aren't relevant
	_hide_layer1_ui(level_scene)

	# 3. Initialize inverse pair manager
	var layer_config: Dictionary = level_data.get("layers", {}).get("layer_2", {})
	inverse_pair_mgr = InversePairManager.new()
	inverse_pair_mgr.setup(level_data, layer_config)

	# 4. Create and show pairing panel in the right zone (map area)
	pairing_panel = InversePairingPanel.new()
	pairing_panel.name = "InversePairingPanel"

	# Use the map_rect area for the panel
	var map_rect: Rect2 = level_scene._map_rect
	var panel_rect := Rect2(
		Vector2(map_rect.position.x + 4, map_rect.position.y + 4),
		Vector2(map_rect.size.x - 8, map_rect.size.y - 8)
	)
	pairing_panel.setup(inverse_pair_mgr, panel_rect)
	level_scene.hud_layer.add_child(pairing_panel)

	# 5. Connect panel signals
	pairing_panel.layer_completed.connect(_on_layer_2_completed)
	pairing_panel.key_selected.connect(_on_key_selected_for_preview)
	pairing_panel.candidate_hovered.connect(_on_candidate_hovered_for_preview)

	# 6. Connect InversePairManager signals
	inverse_pair_mgr.pair_matched.connect(_on_pair_matched)
	inverse_pair_mgr.all_pairs_matched.connect(_on_all_pairs_matched)

	# 7. Update HUD elements for Layer 2 theme
	_apply_layer_2_theme(level_scene)

	# 8. Update the counter for Layer 2
	_update_layer_2_counter(level_scene)

	# 9. Set layer progress to "in_progress"
	GameManager.set_layer_progress(_hall_id, 2, {"status": "in_progress"})


func _hide_layer1_ui(level_scene) -> void:
	## Hide Layer 1 specific UI elements that don't apply in Layer 2.
	var hud := level_scene.hud_layer
	# Hide the room map panel (replaced by inverse pairing panel)
	if level_scene._room_map:
		level_scene._room_map.visible = false
	# Hide the map frame title (will show Layer 2 title instead)
	var map_frame = hud.get_node_or_null("MapFrame")
	if map_frame:
		var title = map_frame.get_node_or_null("MapFrameTitle")
		if title:
			title.text = "Обратные ключи"
			title.add_theme_color_override("font_color", L2_GREEN_DIM)
	# Hide action buttons (Reset, Check) — not used in Layer 2
	for btn_name in ["ResetButton", "CheckButton", "RepeatButton", "CombineButton"]:
		var btn = hud.get_node_or_null(btn_name)
		if btn:
			btn.visible = false
	# Make crystal graph visually read-only (dimmed, non-interactive)
	# Crystals are already non-draggable, but pulse them gently
	for crystal in level_scene.crystals.values():
		if crystal is CrystalNode:
			crystal.set_idle_pulse(true)
			crystal.modulate = Color(0.7, 0.9, 0.75, 0.85)


func _apply_layer_2_theme(level_scene) -> void:
	## Apply green color theme to existing HUD elements.
	var hud := level_scene.hud_layer

	# Level number label — add "Слой 2" indicator
	var lvl_label = hud.get_node_or_null("LevelNumberLabel")
	if lvl_label:
		lvl_label.text += "  ·  Слой 2: Обратные"
		lvl_label.add_theme_color_override("font_color", L2_GREEN_DIM)

	# Target frame border → green
	var target_frame = hud.get_node_or_null("TargetFrame")
	if target_frame:
		var style: StyleBoxFlat = target_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style := style.duplicate() as StyleBoxFlat
			new_style.border_color = L2_GREEN_BORDER
			target_frame.add_theme_stylebox_override("panel", new_style)

	# Crystal frame border → green
	var crystal_frame = hud.get_node_or_null("CrystalFrame")
	if crystal_frame:
		var style: StyleBoxFlat = crystal_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style := style.duplicate() as StyleBoxFlat
			new_style.border_color = L2_GREEN_BORDER
			crystal_frame.add_theme_stylebox_override("panel", new_style)

	# KeyBar frame → green
	var key_frame = hud.get_node_or_null("KeyBarFrame")
	if key_frame:
		var style: StyleBoxFlat = key_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style := style.duplicate() as StyleBoxFlat
			new_style.border_color = L2_GREEN_BORDER
			key_frame.add_theme_stylebox_override("panel", new_style)
		var key_title = key_frame.get_node_or_null("KeyBarFrameTitle")
		if key_title:
			key_title.text = "Ключи (Слой 1)"
			key_title.add_theme_color_override("font_color", L2_GREEN_DIM)

	# Hints frame → green
	var hints_frame = hud.get_node_or_null("HintsFrame")
	if hints_frame:
		var style: StyleBoxFlat = hints_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style := style.duplicate() as StyleBoxFlat
			new_style.border_color = L2_GREEN_BORDER
			hints_frame.add_theme_stylebox_override("panel", new_style)

	# Counter label → green
	var counter = hud.get_node_or_null("CounterLabel")
	if counter:
		counter.add_theme_color_override("font_color", L2_GREEN_DIM)


func _update_layer_2_counter(level_scene) -> void:
	## Update the counter label to show Layer 2 progress.
	var cl = level_scene.hud_layer.get_node_or_null("CounterLabel")
	if cl and inverse_pair_mgr:
		var p := inverse_pair_mgr.get_progress()
		cl.text = "Обратные: %d / %d" % [p["matched"], p["total"]]


# ── Signal Handlers ──────────────────────────────────────────────────

func _on_pair_matched(pair_index: int, key_sym_id: String, inverse_sym_id: String) -> void:
	if _level_scene == null:
		return

	# Update counter
	_update_layer_2_counter(_level_scene)

	# Play valid feedback on crystals (visual confirmation)
	if _level_scene.feedback_fx:
		_level_scene.feedback_fx.play_valid_feedback(
			_level_scene.crystals.values(), _level_scene.edges)

	# Animate the key's permutation on the graph (visual-only)
	_preview_key_on_graph(key_sym_id)


func _on_all_pairs_matched() -> void:
	pass  # Handled via pairing_panel.layer_completed signal


func _on_layer_2_completed() -> void:
	if _level_scene == null:
		return

	# Save layer progress as completed
	var progress := inverse_pair_mgr.get_progress()
	GameManager.set_layer_progress(_hall_id, 2, {
		"status": "completed",
		"pairs_found": progress["matched"],
		"total_pairs": progress["total"],
	})

	# Play completion feedback
	if _level_scene.feedback_fx:
		_level_scene.feedback_fx.play_completion_feedback(
			_level_scene.crystals.values(), _level_scene.edges)

	# Update HUD
	var cl = _level_scene.hud_layer.get_node_or_null("CounterLabel")
	if cl:
		cl.text = "Слой 2 завершён!"
		cl.add_theme_color_override("font_color", L2_GREEN)

	# Show completion summary after a delay
	var timer := _level_scene.get_tree().create_timer(1.5)
	timer.timeout.connect(_show_layer_2_summary)

	# Emit layer completed
	layer_completed.emit(2, _hall_id)


func _on_key_selected_for_preview(sym_id: String) -> void:
	## When a key is selected in the pairing panel, animate it on the graph.
	_preview_key_on_graph(sym_id)


func _on_candidate_hovered_for_preview(sym_id: String) -> void:
	## When a candidate is hovered, show composition preview.
	if sym_id == "" or _level_scene == null:
		return
	# For now, just show the candidate's permutation
	_preview_key_on_graph(sym_id)


# ── Graph Preview ────────────────────────────────────────────────────

func _preview_key_on_graph(sym_id: String) -> void:
	## Animate a key's permutation on the crystal graph (visual-only).
	if _level_scene == null or inverse_pair_mgr == null:
		return

	var perm := inverse_pair_mgr.get_perm(sym_id)
	if perm == null or perm.is_identity():
		return

	# Glow crystals that will move
	var n := perm.mapping.size()
	for i in range(n):
		var target_pos: int = perm.apply(i)
		if target_pos != i:
			# Find the crystal currently at slot i
			if i in _level_scene.crystals:
				var crystal: CrystalNode = _level_scene.crystals[i]
				crystal.play_glow()


# ── Completion Summary ───────────────────────────────────────────────

func _show_layer_2_summary() -> void:
	if _level_scene == null:
		return

	var hud := _level_scene.hud_layer

	# Build a summary panel
	var panel := Panel.new()
	panel.name = "Layer2SummaryPanel"
	panel.position = Vector2(240, 80)
	panel.size = Vector2(800, 480)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.07, 0.04, 0.95)
	style.border_color = L2_GREEN
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 14)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)

	# Title
	var title := Label.new()
	title.text = "Слой 2 — Обратные ключи завершён!"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", L2_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(20, 20)
	title.size = Vector2(760, 30)
	panel.add_child(title)

	# Insight message
	var insight := Label.new()
	insight.text = "Каждое действие можно отменить"
	insight.add_theme_font_size_override("font_size", 16)
	insight.add_theme_color_override("font_color", Color(0.7, 0.9, 0.75, 0.9))
	insight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	insight.position = Vector2(20, 58)
	insight.size = Vector2(760, 25)
	panel.add_child(insight)

	# Divider
	var div := Panel.new()
	div.position = Vector2(80, 92)
	div.size = Vector2(640, 1)
	var div_style := StyleBoxFlat.new()
	div_style.bg_color = L2_GREEN_BORDER
	div.add_theme_stylebox_override("panel", div_style)
	panel.add_child(div)

	# List all pairs
	var pairs := inverse_pair_mgr.get_pairs()
	var y_offset := 105
	for pair in pairs:
		var pair_label := Label.new()
		if pair.is_identity:
			pair_label.text = "  %s ↔ %s  (тождество)" % [pair.key_name, pair.inverse_name]
			pair_label.add_theme_color_override("font_color", L2_GREEN_DIM)
		elif pair.is_self_inverse:
			pair_label.text = "  %s ↔ %s  (сам себе обратный)" % [pair.key_name, pair.inverse_name]
			pair_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.9))
		else:
			pair_label.text = "  %s ↔ %s" % [pair.key_name, pair.inverse_name]
			pair_label.add_theme_color_override("font_color", L2_GREEN)
		pair_label.add_theme_font_size_override("font_size", 14)
		pair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pair_label.position = Vector2(20, y_offset)
		pair_label.size = Vector2(760, 22)
		panel.add_child(pair_label)
		y_offset += 26

	# "Return to map" button
	var btn := Button.new()
	btn.name = "ReturnToMapBtn"
	btn.text = "ВЕРНУТЬСЯ НА КАРТУ"
	btn.add_theme_font_size_override("font_size", 18)
	btn.position = Vector2(250, 420)
	btn.size = Vector2(300, 45)
	btn.pressed.connect(_on_return_to_map)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.06, 0.18, 0.08, 0.9)
	btn_style.border_color = L2_GREEN
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		btn_style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		btn_style.set(prop, 8)
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.1, 0.25, 0.12, 0.95)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_color_override("font_color", L2_GREEN)
	panel.add_child(btn)

	# Fade in
	panel.modulate = Color(1, 1, 1, 0)
	_level_scene.create_tween().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.5)


func _on_return_to_map() -> void:
	GameManager.return_to_map()


# ── Query API ────────────────────────────────────────────────────────

## Check if the current layer is complete.
func is_layer_complete() -> bool:
	match current_layer:
		LayerMode.LAYER_2_INVERSE:
			return inverse_pair_mgr != null and inverse_pair_mgr.is_complete()
		_:
			return false


## Get a short display name for the current layer.
func get_layer_display_name() -> String:
	match current_layer:
		LayerMode.LAYER_1:
			return "Слой 1: Ключи"
		LayerMode.LAYER_2_INVERSE:
			return "Слой 2: Обратные"
		_:
			return "Слой %d" % layer_number
