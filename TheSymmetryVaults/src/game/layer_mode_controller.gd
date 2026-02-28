## LayerModeController — Orchestrates layer-specific behavior within LevelScene.
##
## Layer 2 REDESIGN: reuses the SAME UI as Layer 1 (room map + key bar + crystal view).
## Player discovers inverse pairs by pressing keys and observing when they
## return to the same room. No separate pairing panel.
##
## Gameplay flow:
##   1. All keys visible from start (already discovered in Layer 1)
##   2. Crystal dragging disabled — player navigates via keys only
##   3. Player presses key A → moves to room X
##   4. Player presses key B → returns to the starting room
##   5. System detects: A then B returned to start → A and B are an inverse pair!
##   6. Keys A and B are visually paired in the KeyBar
##   7. Self-inverse: pressing key C takes you somewhere, pressing C again returns
##
## Future layers (3-5) will add new modes here.
class_name LayerModeController
extends RefCounted

# ── Layer mode enum ──────────────────────────────────────────────────

enum LayerMode {
	LAYER_1,             ## Default: crystal swapping, key discovery
	LAYER_2_INVERSE,     ## Inverse key pairing via key presses
	LAYER_3_SUBGROUPS,   ## Keyring assembly — find all subgroups
	LAYER_4_NORMAL,      ## Normal subgroup identification via conjugation cracking
	## Future:
	## LAYER_5_QUOTIENT,  ## Quotient group construction
}

# ── Signals ──────────────────────────────────────────────────────────

signal layer_completed(layer: int, hall_id: String)
signal pair_found(key_a_idx: int, key_b_idx: int, is_self_inverse: bool)
signal keyring_subgroup_found(slot_index: int, elements: Array)
signal conjugation_result(g_sym_id: String, h_sym_id: String, result_sym_id: String, stayed_in: bool)

# ── State ────────────────────────────────────────────────────────────

var current_layer: LayerMode = LayerMode.LAYER_1
var layer_number: int = 1
var inverse_pair_mgr: InversePairManager = null
var keyring_assembly_mgr: KeyringAssemblyManager = null
var conjugation_cracking_mgr: ConjugationCrackingManager = null
var _level_scene = null  ## Weak reference to LevelScene (no type to avoid circular)
var _room_state: RoomState = null
var _hall_id: String = ""
var _keyring_panel = null  ## KeyringPanel for Layer 3 UI
var _cracking_panel = null  ## CrackingPanel for Layer 4 UI

## Key-press tracking for pair detection
var _prev_key_idx: int = -1       ## The previous key pressed (-1 = none)
var _room_before_prev: int = -1   ## Room the player was in BEFORE pressing _prev_key_idx

## Layer 4: conjugation test state
var _selected_g: String = ""       ## Selected conjugator (g ∈ G)
var _selected_h: String = ""       ## Selected target (h ∈ H)

# ── Layer 2 color scheme constants ───────────────────────────────────

const L2_GREEN := Color(0.2, 0.85, 0.4, 1.0)
const L2_GREEN_DIM := Color(0.15, 0.55, 0.3, 0.7)
const L2_GREEN_BG := Color(0.02, 0.06, 0.03, 0.8)
const L2_GREEN_BORDER := Color(0.15, 0.45, 0.25, 0.7)

# ── Layer 3 color scheme constants ───────────────────────────────────

const L3_GOLD := Color(0.95, 0.80, 0.20, 1.0)
const L3_GOLD_DIM := Color(0.70, 0.60, 0.15, 0.7)
const L3_GOLD_BG := Color(0.06, 0.05, 0.02, 0.8)
const L3_GOLD_BORDER := Color(0.55, 0.45, 0.10, 0.7)
const L3_GOLD_GLOW := Color(1.0, 0.90, 0.30, 0.9)

# ── Layer 4 color scheme constants ───────────────────────────────────

const L4_RED := Color(0.9, 0.35, 0.3, 1.0)
const L4_RED_DIM := Color(0.65, 0.25, 0.22, 0.7)
const L4_RED_BG := Color(0.06, 0.02, 0.02, 0.8)
const L4_RED_BORDER := Color(0.5, 0.15, 0.12, 0.7)
const L4_RED_GLOW := Color(1.0, 0.4, 0.3, 0.9)


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
		2:
			current_layer = LayerMode.LAYER_2_INVERSE
			_setup_layer_2(level_data, level_scene)
		3:
			current_layer = LayerMode.LAYER_3_SUBGROUPS
			_setup_layer_3(level_data, level_scene)
		4:
			current_layer = LayerMode.LAYER_4_NORMAL
			_setup_layer_4(level_data, level_scene)
		_:
			push_warning("LayerModeController: Layer %d not yet implemented" % layer)
			current_layer = LayerMode.LAYER_1


## Clean up all layer-specific resources.
func cleanup() -> void:
	# Disable Layer 3 mode on KeyBar if active
	if _level_scene and _level_scene._key_bar:
		_level_scene._key_bar.disable_layer3_mode()
	inverse_pair_mgr = null
	keyring_assembly_mgr = null
	conjugation_cracking_mgr = null
	if _keyring_panel != null and is_instance_valid(_keyring_panel):
		_keyring_panel.cleanup()
		_keyring_panel.queue_free()
	_keyring_panel = null
	# Clean up Layer 4 cracking panel
	if _cracking_panel != null and is_instance_valid(_cracking_panel):
		_cracking_panel.cleanup()
		_cracking_panel.queue_free()
	_cracking_panel = null
	_level_scene = null
	_room_state = null
	_prev_key_idx = -1
	_room_before_prev = -1
	_selected_g = ""
	_selected_h = ""


# ── Layer 2: Inverse Key Pairing via Key Presses ────────────────────

func _setup_layer_2(level_data: Dictionary, level_scene) -> void:
	_room_state = level_scene._room_state

	# 1. Disable crystal dragging (graph is read-only on Layer 2)
	for crystal in level_scene.crystals.values():
		if crystal is CrystalNode:
			crystal.set_draggable(false)

	# 2. Reset crystals to identity (home) arrangement.
	#    Layer 2 starts from "home" — the identity permutation.
	var sm: ShuffleManager = level_scene._shuffle_mgr
	sm.current_arrangement = sm.identity_arrangement.duplicate()
	level_scene._swap_mgr.apply_arrangement_to_crystals()

	# 3. Make ALL rooms discovered (player already found them in Layer 1)
	for i in range(_room_state.group_order):
		_room_state.discover_room(i)

	# 4. Show Home key immediately
	if level_scene._key_bar:
		level_scene._key_bar.home_visible = true
		level_scene._key_bar.rebuild(_room_state)

	# 5. Hide target preview (every key application is valid in Layer 2)
	_hide_target_preview(level_scene)

	# 6. Hide action buttons (Reset, Check — not used in Layer 2)
	_hide_action_buttons(level_scene)

	# 7. Initialize inverse pair manager
	var layer_config: Dictionary = level_data.get("layers", {}).get("layer_2", {})
	inverse_pair_mgr = InversePairManager.new()
	inverse_pair_mgr.setup(level_data, layer_config)

	# 8. Connect InversePairManager signals
	inverse_pair_mgr.pair_matched.connect(_on_pair_matched)
	inverse_pair_mgr.all_pairs_matched.connect(_on_all_pairs_matched)

	# 9. Apply Layer 2 theme (green accents)
	_apply_layer_2_theme(level_scene)

	# 10. Update counter for Layer 2 progress
	_update_layer_2_counter()

	# 11. Reset key-press tracking
	_prev_key_idx = -1
	_room_before_prev = -1

	# 12. Room map stays visible — update it with all rooms discovered
	if level_scene._room_map:
		level_scene._room_map.home_visible = true
		level_scene._room_map.queue_redraw()

	# 13. Save "in_progress" state
	GameManager.set_layer_progress(_hall_id, 2, {"status": "in_progress"})


## Called by LevelScene when a key is pressed during Layer 2.
## key_idx: the room index of the key pressed (0 = identity/Home)
## room_before: the room the player was in BEFORE this key press
## room_after: the room the player is in AFTER this key press
func on_key_pressed(key_idx: int, room_before: int, room_after: int) -> void:
	if inverse_pair_mgr == null or _room_state == null:
		return

	# Identity key press — reset tracking (doesn't form meaningful pairs)
	if key_idx == 0:
		_prev_key_idx = -1
		_room_before_prev = -1
		return

	if _prev_key_idx == -1:
		# First key press in a potential pair — record it
		_prev_key_idx = key_idx
		_room_before_prev = room_before
	else:
		# Second key press — check if we returned to the starting room
		if room_after == _room_before_prev:
			# Player returned to the room they started from!
			# Keys _prev_key_idx and key_idx are inverse pair candidates
			var sym_a: String = _room_state.get_room_sym_id(_prev_key_idx)
			var sym_b: String = _room_state.get_room_sym_id(key_idx)

			if sym_a != "" and sym_b != "":
				var result: Dictionary = inverse_pair_mgr.try_pair_by_sym_ids(sym_a, sym_b)
				if result["success"]:
					var is_self_inv: bool = result["is_self_inverse"]
					pair_found.emit(_prev_key_idx, key_idx, is_self_inv)

					# Update KeyBar pairing visualization
					_update_key_bar_pairing()

					# Show feedback message
					_show_pair_feedback(_prev_key_idx, key_idx, is_self_inv)

		# Reset tracking — start fresh for next potential pair
		# (Whether we found a pair or not, reset after 2 presses)
		_prev_key_idx = key_idx
		_room_before_prev = room_before


## Reset key-press tracking (e.g., when player uses Reset button)
func reset_tracking() -> void:
	_prev_key_idx = -1
	_room_before_prev = -1


# ── UI Helpers ───────────────────────────────────────────────────────

func _hide_target_preview(level_scene) -> void:
	## Hide the target preview (not relevant for Layer 2)
	if level_scene.target_preview:
		level_scene.target_preview.visible = false
	var target_frame = level_scene.hud_layer.get_node_or_null("TargetFrame")
	if target_frame:
		target_frame.visible = false


func _hide_action_buttons(level_scene) -> void:
	## Hide action buttons not used in Layer 2
	var hud = level_scene.hud_layer
	for btn_name in ["ResetButton", "CheckButton"]:
		var btn = hud.get_node_or_null(btn_name)
		if btn:
			btn.visible = false


func _apply_layer_2_theme(level_scene) -> void:
	## Apply green color accents to existing HUD elements.
	var hud = level_scene.hud_layer

	# Level number label — add "Слой 2" indicator
	var lvl_label = hud.get_node_or_null("LevelNumberLabel")
	if lvl_label:
		lvl_label.text += "  ·  Слой 2: Обратные"
		lvl_label.add_theme_color_override("font_color", L2_GREEN_DIM)

	# Map frame title → indicate Layer 2
	var map_frame = hud.get_node_or_null("MapFrame")
	if map_frame:
		var map_title = map_frame.get_node_or_null("MapFrameTitle")
		if map_title:
			map_title.text = "Карта комнат — Обратные"
			map_title.add_theme_color_override("font_color", L2_GREEN_DIM)

	# KeyBar frame title → indicate inverse pairing
	var key_frame = hud.get_node_or_null("KeyBarFrame")
	if key_frame:
		var key_title = key_frame.get_node_or_null("KeyBarFrameTitle")
		if key_title:
			key_title.text = "Ключи — найдите обратные пары"
			key_title.add_theme_color_override("font_color", L2_GREEN_DIM)

	# Counter label → green
	var counter = hud.get_node_or_null("CounterLabel")
	if counter:
		counter.add_theme_color_override("font_color", L2_GREEN_DIM)


func _update_layer_2_counter() -> void:
	## Update the counter label to show Layer 2 progress.
	if _level_scene == null or inverse_pair_mgr == null:
		return
	var cl = _level_scene.hud_layer.get_node_or_null("CounterLabel")
	if cl:
		var p: Dictionary = inverse_pair_mgr.get_progress()
		cl.text = "Обратные пары: %d / %d" % [p["matched"], p["total"]]


func _update_key_bar_pairing() -> void:
	## Notify KeyBar to update pairing visualization.
	if _level_scene == null or _level_scene._key_bar == null:
		return
	if inverse_pair_mgr == null or _room_state == null:
		return
	_level_scene._key_bar.update_layer2_pairs(_room_state, inverse_pair_mgr)


func _show_pair_feedback(key_a_idx: int, key_b_idx: int, is_self_inverse: bool) -> void:
	## Show a hint message when a pair is found.
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return

	var name_a: String = _room_state.get_room_name(key_a_idx)
	var name_b: String = _room_state.get_room_name(key_b_idx)
	var text: String
	var color: Color

	if is_self_inverse:
		text = "↻ %s — сам себе обратный!" % name_a
		color = Color(1.0, 0.85, 0.3, 0.9)
	else:
		text = "Пара найдена: %s ↔ %s" % [name_a, name_b]
		color = L2_GREEN

	hl.text = text
	var tw: Tween = _level_scene.create_tween()
	tw.tween_property(hl, "theme_override_colors/font_color", color, 0.3)
	tw.tween_interval(3.0)
	tw.tween_property(hl, "theme_override_colors/font_color", Color(0.5, 0.8, 0.5, 0.5), 1.0)


# ── Signal Handlers ──────────────────────────────────────────────────

func _on_pair_matched(_pair_index: int, _key_sym_id: String, _inverse_sym_id: String) -> void:
	if _level_scene == null:
		return

	# Update counter
	_update_layer_2_counter()

	# Play valid feedback on crystals
	if _level_scene.feedback_fx:
		_level_scene.feedback_fx.play_valid_feedback(
			_level_scene.crystals.values(), _level_scene.edges)


func _on_all_pairs_matched() -> void:
	_on_layer_2_completed()


func _on_layer_2_completed() -> void:
	if _level_scene == null:
		return

	# Save layer progress as completed
	var progress: Dictionary = inverse_pair_mgr.get_progress()
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
		cl.text = "Все обратные пары найдены!"
		cl.add_theme_color_override("font_color", L2_GREEN)

	# Show completion hint
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl:
		hl.text = "Каждое действие можно отменить"
		hl.add_theme_color_override("font_color", L2_GREEN)

	# Show completion summary after a delay
	var timer: SceneTreeTimer = _level_scene.get_tree().create_timer(1.5)
	timer.timeout.connect(_show_layer_2_summary)

	# Emit layer completed
	layer_completed.emit(2, _hall_id)


# ── Completion Summary ───────────────────────────────────────────────

func _show_layer_2_summary() -> void:
	if _level_scene == null:
		return

	var hud: CanvasLayer = _level_scene.hud_layer

	# Build a summary panel
	var panel: Panel = Panel.new()
	panel.name = "Layer2SummaryPanel"
	var vp_size: Vector2 = Vector2(1280, 720)
	if _level_scene.get_viewport():
		var vr: Rect2 = _level_scene.get_viewport_rect()
		if vr.size != Vector2.ZERO:
			vp_size = vr.size
	var pw: float = minf(vp_size.x * 0.6, 800.0)
	var ph: float = minf(vp_size.y * 0.7, 500.0)
	panel.position = Vector2((vp_size.x - pw) / 2.0, (vp_size.y - ph) / 2.0)
	panel.size = Vector2(pw, ph)
	var style: StyleBoxFlat = StyleBoxFlat.new()
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

	var inner_w: float = pw - 40.0

	# Title
	var title: Label = Label.new()
	title.text = "Слой 2 — Обратные ключи завершён!"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", L2_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(20, 20)
	title.size = Vector2(inner_w, 30)
	panel.add_child(title)

	# Insight message
	var insight: Label = Label.new()
	insight.text = "Каждое действие можно отменить"
	insight.add_theme_font_size_override("font_size", 16)
	insight.add_theme_color_override("font_color", Color(0.7, 0.9, 0.75, 0.9))
	insight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	insight.position = Vector2(20, 58)
	insight.size = Vector2(inner_w, 25)
	panel.add_child(insight)

	# Divider
	var div: Panel = Panel.new()
	div.position = Vector2(60, 92)
	div.size = Vector2(inner_w - 80, 1)
	var div_style: StyleBoxFlat = StyleBoxFlat.new()
	div_style.bg_color = L2_GREEN_BORDER
	div.add_theme_stylebox_override("panel", div_style)
	panel.add_child(div)

	# List all pairs
	var pairs: Array = inverse_pair_mgr.get_pairs()
	var y_offset: int = 105
	for pair in pairs:
		var pair_label: Label = Label.new()
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
		pair_label.size = Vector2(inner_w, 22)
		panel.add_child(pair_label)
		y_offset += 26

	# "Return to map" button
	var btn: Button = Button.new()
	btn.name = "ReturnToMapBtn"
	btn.text = "ВЕРНУТЬСЯ НА КАРТУ"
	btn.add_theme_font_size_override("font_size", 18)
	var btn_w: float = minf(300.0, inner_w * 0.6)
	btn.position = Vector2((pw - btn_w) / 2.0, ph - 60.0)
	btn.size = Vector2(btn_w, 45)
	btn.pressed.connect(_on_return_to_map)

	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.06, 0.18, 0.08, 0.9)
	btn_style.border_color = L2_GREEN
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		btn_style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		btn_style.set(prop, 8)
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover: StyleBoxFlat = btn_style.duplicate()
	btn_hover.bg_color = Color(0.1, 0.25, 0.12, 0.95)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_color_override("font_color", L2_GREEN)
	panel.add_child(btn)

	# T100: "Continue playing" dismiss button
	var dismiss_btn: Button = Button.new()
	dismiss_btn.name = "L2DismissBtn"
	dismiss_btn.text = "Продолжить играть"
	dismiss_btn.add_theme_font_size_override("font_size", 14)
	var dismiss_w: float = minf(240.0, inner_w * 0.45)
	dismiss_btn.position = Vector2((pw - dismiss_w) / 2.0, ph - 108.0)
	dismiss_btn.size = Vector2(dismiss_w, 36)
	var dismiss_style: StyleBoxFlat = StyleBoxFlat.new()
	dismiss_style.bg_color = Color(0.04, 0.08, 0.05, 0.7)
	dismiss_style.border_color = L2_GREEN_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		dismiss_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		dismiss_style.set(prop, 6)
	dismiss_btn.add_theme_stylebox_override("normal", dismiss_style)
	var dismiss_hover: StyleBoxFlat = dismiss_style.duplicate()
	dismiss_hover.bg_color = Color(0.08, 0.14, 0.09, 0.85)
	dismiss_btn.add_theme_stylebox_override("hover", dismiss_hover)
	dismiss_btn.add_theme_color_override("font_color", L2_GREEN_DIM)
	dismiss_btn.pressed.connect(_on_dismiss_layer_2_summary)
	panel.add_child(dismiss_btn)

	# Fade in
	panel.modulate = Color(1, 1, 1, 0)
	_level_scene.create_tween().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.5)


func _on_return_to_map() -> void:
	GameManager.return_to_map()


## T100: Dismiss the Layer 2 summary panel and allow continued play.
func _on_dismiss_layer_2_summary() -> void:
	if _level_scene == null:
		return
	var hud: CanvasLayer = _level_scene.hud_layer
	var panel = hud.get_node_or_null("Layer2SummaryPanel")
	if panel and panel.visible:
		var tw: Tween = _level_scene.create_tween()
		tw.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.3)
		tw.tween_callback(panel.queue_free)
	# Show persistent exit button
	HudBuilder.show_post_completion_exit_button(hud, _on_return_to_map)


# ── Layer 3: Subgroup Discovery via Keyring Assembly ─────────────────

func _setup_layer_3(level_data: Dictionary, level_scene) -> void:
	_room_state = level_scene._room_state

	# 1. Disable crystal dragging (graph is read-only on Layer 3)
	for crystal in level_scene.crystals.values():
		if crystal is CrystalNode:
			crystal.set_draggable(false)

	# 2. Reset crystals to identity (home) arrangement
	var sm: ShuffleManager = level_scene._shuffle_mgr
	sm.current_arrangement = sm.identity_arrangement.duplicate()
	level_scene._swap_mgr.apply_arrangement_to_crystals()

	# 3. Make ALL rooms discovered (player already found them in Layer 1)
	for i in range(_room_state.group_order):
		_room_state.discover_room(i)

	# 4. Show Home key and all keys immediately, enable Layer 3 ⊕ buttons
	if level_scene._key_bar:
		level_scene._key_bar.home_visible = true
		level_scene._key_bar.enable_layer3_mode()
		level_scene._key_bar.rebuild(_room_state)

	# 5. Hide target preview and action buttons
	_hide_target_preview(level_scene)
	_hide_action_buttons(level_scene)

	# 6. Initialize KeyringAssemblyManager
	var layer_config: Dictionary = level_data.get("layers", {}).get("layer_3", {})
	keyring_assembly_mgr = KeyringAssemblyManager.new()
	keyring_assembly_mgr.setup(level_data, layer_config)

	# 7. Connect KeyringAssemblyManager signals
	keyring_assembly_mgr.subgroup_found.connect(_on_keyring_subgroup_found)
	keyring_assembly_mgr.duplicate_subgroup.connect(_on_keyring_duplicate_subgroup)
	keyring_assembly_mgr.all_subgroups_found.connect(_on_all_subgroups_found)

	# 8. Apply Layer 3 theme (gold accents)
	_apply_layer_3_theme(level_scene)

	# 9. Update counter for Layer 3 progress
	_update_layer_3_counter()

	# 10. Room map stays visible
	if level_scene._room_map:
		level_scene._room_map.home_visible = true
		level_scene._room_map.queue_redraw()

	# 11. Build keyring panel UI — split the crystal zone
	_build_keyring_panel(level_scene)

	# 12. Restore from save (if resuming)
	var saved: Dictionary = {}
	if GameManager.level_states.has(_hall_id):
		var lp: Dictionary = GameManager.level_states[_hall_id].get("layer_progress", {})
		saved = lp.get("layer_3", {})
	if saved.get("status") == "in_progress":
		keyring_assembly_mgr.restore_from_save(saved)
		if _keyring_panel:
			_keyring_panel.refresh_from_state()
		_update_layer_3_counter()

	# 13. Save "in_progress" state
	GameManager.set_layer_progress(_hall_id, 3, keyring_assembly_mgr.save_state())


## Called when a key is tapped in Layer 3 (tap-to-add from KeyBar).
## sym_id: the sym_id of the key tapped
func on_key_tapped_layer3(sym_id: String) -> void:
	if keyring_assembly_mgr == null:
		return

	var active_slot: int = keyring_assembly_mgr.get_active_slot_index()

	# Check if key is already in the active slot — if so, remove it
	if keyring_assembly_mgr.get_active_keys().has(sym_id):
		keyring_assembly_mgr.remove_key_from_active(sym_id)
		if _keyring_panel:
			_keyring_panel.remove_key_visual(active_slot, sym_id)
		_update_layer_3_counter()
		_update_keybar_keyring_state()
		return

	# Add key to active slot
	var add_result: Dictionary = keyring_assembly_mgr.add_key_to_active(sym_id)
	if not add_result["added"]:
		return

	# Update panel visual — add the dot BEFORE validation
	# (if it's a new subgroup, auto_validate will advance the slot)
	if _keyring_panel:
		_keyring_panel.add_key_visual(active_slot, sym_id)

	# Auto-validate
	var val_result: Dictionary = keyring_assembly_mgr.auto_validate()

	if val_result["is_subgroup"] and val_result["is_new"]:
		# Subgroup found! Lock the slot in the panel, update counter and save
		if _keyring_panel:
			var found: Array = keyring_assembly_mgr.get_found_subgroups()
			if found.size() > 0:
				_keyring_panel.lock_slot(active_slot, found[found.size() - 1])
			_keyring_panel.update_progress()
		_update_layer_3_counter()
		_save_layer_3_progress()
	elif val_result["is_subgroup"] and val_result["is_duplicate"]:
		# Duplicate — show feedback
		_show_duplicate_feedback()
		if _keyring_panel:
			_keyring_panel.show_duplicate_flash(active_slot)
	else:
		# Not a subgroup (yet) — just update display
		_update_layer_3_counter()

	# Update ⊕/− display on KeyBar
	_update_keybar_keyring_state()

## Called when a key is removed from the keyring panel by tapping a dot.
func _on_keyring_key_removed(sym_id: String) -> void:
	if keyring_assembly_mgr == null:
		return
	var active_slot: int = keyring_assembly_mgr.get_active_slot_index()
	keyring_assembly_mgr.remove_key_from_active(sym_id)
	if _keyring_panel:
		_keyring_panel.remove_key_visual(active_slot, sym_id)
	_update_layer_3_counter()
	_update_keybar_keyring_state()


## Handle locked slot selection — highlight subgroup rooms on the map.
func _on_keyring_slot_selected(elements: Array) -> void:
	if _level_scene == null or _level_scene._room_map == null:
		return
	if elements.is_empty():
		_level_scene._room_map.clear_subgroup_highlight()
	else:
		_level_scene._room_map.highlight_subgroup(elements)


## Sync ⊕/− indicators on KeyBar with the current active keyring slot contents.
func _update_keybar_keyring_state() -> void:
	if _level_scene == null or _level_scene._key_bar == null:
		return
	if keyring_assembly_mgr == null or _room_state == null:
		return
	_level_scene._key_bar.update_layer3_keyring_state(
		keyring_assembly_mgr.get_active_keys(), _room_state)


## Layer 3 theme application.
func _apply_layer_3_theme(level_scene) -> void:
	var hud = level_scene.hud_layer

	# Level number label — add "Слой 3" indicator
	var lvl_label = hud.get_node_or_null("LevelNumberLabel")
	if lvl_label:
		lvl_label.text += "  ·  Слой 3: Группы"
		lvl_label.add_theme_color_override("font_color", L3_GOLD_DIM)

	# Map frame title → indicate Layer 3
	var map_frame = hud.get_node_or_null("MapFrame")
	if map_frame:
		var map_title = map_frame.get_node_or_null("MapFrameTitle")
		if map_title:
			map_title.text = "Карта комнат — Группы"
			map_title.add_theme_color_override("font_color", L3_GOLD_DIM)

	# KeyBar frame title → indicate keyring assembly
	var key_frame = hud.get_node_or_null("KeyBarFrame")
	if key_frame:
		var key_title = key_frame.get_node_or_null("KeyBarFrameTitle")
		if key_title:
			key_title.text = "Ключи — нажмите ⊕ для брелка"
			key_title.add_theme_color_override("font_color", L3_GOLD_DIM)

	# Counter label → gold
	var counter = hud.get_node_or_null("CounterLabel")
	if counter:
		counter.add_theme_color_override("font_color", L3_GOLD_DIM)


## Update the counter label for Layer 3 progress.
func _update_layer_3_counter() -> void:
	if _level_scene == null or keyring_assembly_mgr == null:
		return
	var cl = _level_scene.hud_layer.get_node_or_null("CounterLabel")
	if cl:
		var p: Dictionary = keyring_assembly_mgr.get_progress()
		cl.text = "Брелки: %d / %d" % [p["found"], p["total"]]


## Save Layer 3 progress.
func _save_layer_3_progress() -> void:
	if keyring_assembly_mgr == null:
		return
	GameManager.set_layer_progress(_hall_id, 3, keyring_assembly_mgr.save_state())


## Show feedback for duplicate subgroup.
func _show_duplicate_feedback() -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return
	hl.text = "Этот брелок уже найден"
	var tw: Tween = _level_scene.create_tween()
	tw.tween_property(hl, "theme_override_colors/font_color",
		Color(1.0, 0.6, 0.2, 0.9), 0.3)
	tw.tween_interval(2.0)
	tw.tween_property(hl, "theme_override_colors/font_color",
		Color(0.7, 0.6, 0.3, 0.5), 1.0)


## Build the Layer 3 keyring panel — split layout.
## Takes 30% of the left column for keyrings, shrinks crystal zone to 70%.
func _build_keyring_panel(level_scene) -> void:
	var hud: CanvasLayer = level_scene.hud_layer
	if keyring_assembly_mgr == null or _room_state == null:
		return

	# Get the current crystal zone rectangle
	var crystal_rect: Rect2 = level_scene._crystal_rect
	if crystal_rect.size == Vector2.ZERO:
		return

	# Split: keyring gets 30% of the crystal zone width
	var keyring_ratio: float = 0.30
	var keyring_w: float = floorf(crystal_rect.size.x * keyring_ratio)
	var crystal_new_w: float = crystal_rect.size.x - keyring_w - 2  # 2px gap

	# Keyring panel rectangle (left side of old crystal zone)
	var keyring_rect: Rect2 = Rect2(
		crystal_rect.position.x,
		crystal_rect.position.y,
		keyring_w,
		crystal_rect.size.y
	)

	# New crystal zone (right side, narrower)
	var new_crystal_rect: Rect2 = Rect2(
		crystal_rect.position.x + keyring_w + 2,
		crystal_rect.position.y,
		crystal_new_w,
		crystal_rect.size.y
	)

	# Resize crystal frame
	var crystal_frame = hud.get_node_or_null("CrystalFrame")
	if crystal_frame:
		crystal_frame.position = new_crystal_rect.position
		crystal_frame.size = new_crystal_rect.size

	# Reposition crystal and edge containers
	level_scene.crystal_container.position = new_crystal_rect.position
	level_scene.edge_container.position = new_crystal_rect.position

	# Reposition crystals to fit in the narrower zone
	var nd: Array = level_scene.level_data.get("graph", {}).get("nodes", [])
	var pm: Dictionary = ShuffleManager.build_positions_map(nd, new_crystal_rect.size)
	var sm: ShuffleManager = level_scene._shuffle_mgr
	for i in range(sm.current_arrangement.size()):
		var cid: int = sm.current_arrangement[i]
		if cid in level_scene.crystals and i in pm:
			var crystal: CrystalNode = level_scene.crystals[cid]
			crystal.position = pm[i]
			crystal.set_home_position(pm[i])

	# Update the stored crystal rect
	level_scene._crystal_rect = new_crystal_rect

	# Create the KeyringPanel
	_keyring_panel = KeyringPanel.new()
	_keyring_panel.setup(hud, keyring_rect, _room_state, keyring_assembly_mgr)
	hud.add_child(_keyring_panel)

	# Connect keyring panel signals
	_keyring_panel.key_removed.connect(_on_keyring_key_removed)
	_keyring_panel.slot_selected.connect(_on_keyring_slot_selected)


## Show feedback for new subgroup found.
func _show_subgroup_found_feedback(elements: Array) -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return
	var count: int = elements.size()
	hl.text = "Брелок найден! (порядок %d)" % count
	var tw: Tween = _level_scene.create_tween()
	tw.tween_property(hl, "theme_override_colors/font_color", L3_GOLD, 0.3)
	tw.tween_interval(3.0)
	tw.tween_property(hl, "theme_override_colors/font_color",
		Color(0.7, 0.6, 0.3, 0.5), 1.0)


# ── Layer 3 Signal Handlers ──────────────────────────────────────────

func _on_keyring_subgroup_found(slot_index: int, elements: Array) -> void:
	if _level_scene == null:
		return

	# Update counter
	_update_layer_3_counter()

	# Update keyring panel progress
	if _keyring_panel:
		_keyring_panel.update_progress()

	# Show feedback
	_show_subgroup_found_feedback(elements)

	# Play valid feedback on crystals
	if _level_scene.feedback_fx:
		_level_scene.feedback_fx.play_valid_feedback(
			_level_scene.crystals.values(), _level_scene.edges)

	# Emit signal
	keyring_subgroup_found.emit(slot_index, elements)


func _on_keyring_duplicate_subgroup(slot_index: int) -> void:
	_show_duplicate_feedback()
	if _keyring_panel:
		_keyring_panel.show_duplicate_flash(slot_index)


func _on_all_subgroups_found() -> void:
	_on_layer_3_completed()


func _on_layer_3_completed() -> void:
	if _level_scene == null:
		return

	# Save layer progress as completed
	_save_layer_3_progress()

	# Play completion feedback
	if _level_scene.feedback_fx:
		_level_scene.feedback_fx.play_completion_feedback(
			_level_scene.crystals.values(), _level_scene.edges)

	# Update HUD
	var cl = _level_scene.hud_layer.get_node_or_null("CounterLabel")
	if cl:
		cl.text = "Все брелки собраны!"
		cl.add_theme_color_override("font_color", L3_GOLD)

	# Show completion hint
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl:
		hl.text = "Некоторые ключи образуют подгруппы"
		hl.add_theme_color_override("font_color", L3_GOLD)

	# Show completion summary after a delay
	var timer: SceneTreeTimer = _level_scene.get_tree().create_timer(1.5)
	timer.timeout.connect(_show_layer_3_summary)

	# Emit layer completed
	layer_completed.emit(3, _hall_id)


# ── Layer 3 Completion Summary ───────────────────────────────────────

func _show_layer_3_summary() -> void:
	if _level_scene == null:
		return

	var hud: CanvasLayer = _level_scene.hud_layer

	# Build a summary panel
	var panel: Panel = Panel.new()
	panel.name = "Layer3SummaryPanel"
	var vp_size: Vector2 = Vector2(1280, 720)
	if _level_scene.get_viewport():
		var vr: Rect2 = _level_scene.get_viewport_rect()
		if vr.size != Vector2.ZERO:
			vp_size = vr.size
	var pw: float = minf(vp_size.x * 0.6, 800.0)
	var ph: float = minf(vp_size.y * 0.7, 500.0)
	panel.position = Vector2((vp_size.x - pw) / 2.0, (vp_size.y - ph) / 2.0)
	panel.size = Vector2(pw, ph)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = L3_GOLD_BG
	style.border_color = L3_GOLD
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 14)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)

	var inner_w: float = pw - 40.0

	# Title
	var title: Label = Label.new()
	title.text = "Слой 3 — Все брелки собраны!"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", L3_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(20, 20)
	title.size = Vector2(inner_w, 30)
	panel.add_child(title)

	# Insight message
	var insight: Label = Label.new()
	insight.text = "Некоторые ключи образуют подгруппы"
	insight.add_theme_font_size_override("font_size", 16)
	insight.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5, 0.9))
	insight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	insight.position = Vector2(20, 58)
	insight.size = Vector2(inner_w, 25)
	panel.add_child(insight)

	# Divider
	var div: Panel = Panel.new()
	div.position = Vector2(60, 92)
	div.size = Vector2(inner_w - 80, 1)
	var div_style: StyleBoxFlat = StyleBoxFlat.new()
	div_style.bg_color = L3_GOLD_BORDER
	div.add_theme_stylebox_override("panel", div_style)
	panel.add_child(div)

	# List found subgroups
	var found: Array = keyring_assembly_mgr.get_found_subgroups() if keyring_assembly_mgr else []
	var y_offset: int = 105
	for sg in found:
		var sg_label: Label = Label.new()
		var elements_str: String = ", ".join(sg)
		sg_label.text = "  {%s}  (порядок %d)" % [elements_str, sg.size()]
		if sg.size() == 1:
			sg_label.add_theme_color_override("font_color", L3_GOLD_DIM)
		else:
			sg_label.add_theme_color_override("font_color", L3_GOLD)
		sg_label.add_theme_font_size_override("font_size", 14)
		sg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sg_label.position = Vector2(20, y_offset)
		sg_label.size = Vector2(inner_w, 22)
		panel.add_child(sg_label)
		y_offset += 26

	# "Return to map" button
	var btn: Button = Button.new()
	btn.name = "ReturnToMapBtn"
	btn.text = "ВЕРНУТЬСЯ НА КАРТУ"
	btn.add_theme_font_size_override("font_size", 18)
	var btn_w: float = minf(300.0, inner_w * 0.6)
	btn.position = Vector2((pw - btn_w) / 2.0, ph - 60.0)
	btn.size = Vector2(btn_w, 45)
	btn.pressed.connect(_on_return_to_map)

	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.08, 0.07, 0.02, 0.9)
	btn_style.border_color = L3_GOLD
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		btn_style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		btn_style.set(prop, 8)
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover: StyleBoxFlat = btn_style.duplicate()
	btn_hover.bg_color = Color(0.12, 0.10, 0.04, 0.95)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_color_override("font_color", L3_GOLD)
	panel.add_child(btn)

	# "Continue playing" dismiss button
	var dismiss_btn: Button = Button.new()
	dismiss_btn.name = "L3DismissBtn"
	dismiss_btn.text = "Продолжить играть"
	dismiss_btn.add_theme_font_size_override("font_size", 14)
	var dismiss_w: float = minf(240.0, inner_w * 0.45)
	dismiss_btn.position = Vector2((pw - dismiss_w) / 2.0, ph - 108.0)
	dismiss_btn.size = Vector2(dismiss_w, 36)
	var dismiss_style: StyleBoxFlat = StyleBoxFlat.new()
	dismiss_style.bg_color = Color(0.06, 0.05, 0.02, 0.7)
	dismiss_style.border_color = L3_GOLD_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		dismiss_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		dismiss_style.set(prop, 6)
	dismiss_btn.add_theme_stylebox_override("normal", dismiss_style)
	var dismiss_hover: StyleBoxFlat = dismiss_style.duplicate()
	dismiss_hover.bg_color = Color(0.10, 0.08, 0.03, 0.85)
	dismiss_btn.add_theme_stylebox_override("hover", dismiss_hover)
	dismiss_btn.add_theme_color_override("font_color", L3_GOLD_DIM)
	dismiss_btn.pressed.connect(_on_dismiss_layer_3_summary)
	panel.add_child(dismiss_btn)

	# Fade in
	panel.modulate = Color(1, 1, 1, 0)
	_level_scene.create_tween().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.5)


## Dismiss the Layer 3 summary panel and allow continued play.
func _on_dismiss_layer_3_summary() -> void:
	if _level_scene == null:
		return
	var hud: CanvasLayer = _level_scene.hud_layer
	var panel = hud.get_node_or_null("Layer3SummaryPanel")
	if panel and panel.visible:
		var tw: Tween = _level_scene.create_tween()
		tw.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.3)
		tw.tween_callback(panel.queue_free)
	# Show persistent exit button
	HudBuilder.show_post_completion_exit_button(hud, _on_return_to_map)


# ── Layer 4: Normal Subgroup Identification via Conjugation Cracking ──

func _setup_layer_4(level_data: Dictionary, level_scene) -> void:
	_room_state = level_scene._room_state

	# 1. Disable crystal dragging (graph is read-only on Layer 4)
	for crystal in level_scene.crystals.values():
		if crystal is CrystalNode:
			crystal.set_draggable(false)

	# 2. Reset crystals to identity (home) arrangement
	var sm: ShuffleManager = level_scene._shuffle_mgr
	sm.current_arrangement = sm.identity_arrangement.duplicate()
	level_scene._swap_mgr.apply_arrangement_to_crystals()

	# 3. Make ALL rooms discovered
	for i in range(_room_state.group_order):
		_room_state.discover_room(i)

	# 4. Show Home key and all keys, enable ⊕ buttons for h-selection
	if level_scene._key_bar:
		level_scene._key_bar.home_visible = true
		level_scene._key_bar.enable_layer3_mode()  # Reuse ⊕ buttons for h-selection
		level_scene._key_bar.rebuild(_room_state)

	# 5. Hide target preview and action buttons
	_hide_target_preview(level_scene)
	_hide_action_buttons(level_scene)

	# 6. Initialize ConjugationCrackingManager
	var layer_config: Dictionary = level_data.get("layers", {}).get("layer_4", {})
	conjugation_cracking_mgr = ConjugationCrackingManager.new()
	conjugation_cracking_mgr.setup(level_data, layer_config)

	# 7. Connect ConjugationCrackingManager signals
	conjugation_cracking_mgr.subgroup_cracked.connect(_on_subgroup_cracked)
	conjugation_cracking_mgr.subgroup_confirmed_normal.connect(_on_subgroup_confirmed_normal)
	conjugation_cracking_mgr.all_subgroups_classified.connect(_on_all_subgroups_classified)

	# 8. Apply Layer 4 theme (red accents)
	_apply_layer_4_theme(level_scene)

	# 9. Update counter for Layer 4 progress
	_update_layer_4_counter()

	# 10. Room map stays visible
	if level_scene._room_map:
		level_scene._room_map.home_visible = true
		level_scene._room_map.queue_redraw()

	# 11. Build conjugation panel UI
	_build_cracking_panel(level_scene)

	# 12. Restore from save (if resuming)
	var saved: Dictionary = {}
	if GameManager.level_states.has(_hall_id):
		var lp: Dictionary = GameManager.level_states[_hall_id].get("layer_progress", {})
		saved = lp.get("layer_4", {})
	if saved.get("status") == "in_progress":
		conjugation_cracking_mgr.restore_from_save(saved)
		_update_layer_4_counter()
		_refresh_cracking_panel()

	# 13. Save "in_progress" state
	GameManager.set_layer_progress(_hall_id, 4, conjugation_cracking_mgr.save_state())


## Called when the player selects a subgroup in the conjugation panel.
func on_subgroup_selected_layer4(subgroup_index: int) -> void:
	if conjugation_cracking_mgr == null:
		return
	if conjugation_cracking_mgr.select_subgroup(subgroup_index):
		# Highlight subgroup rooms on the map
		var elements: Array = conjugation_cracking_mgr.get_subgroup_elements(subgroup_index)
		if _level_scene and _level_scene._room_map:
			_level_scene._room_map.highlight_subgroup(elements)
		_refresh_cracking_panel()


## Called when the player tests a conjugation: g · h · g⁻¹
func on_conjugation_test(g_sym_id: String, h_sym_id: String) -> void:
	if conjugation_cracking_mgr == null:
		return

	var result: Dictionary = conjugation_cracking_mgr.test_conjugation(g_sym_id, h_sym_id)
	if result.has("error"):
		return

	# Show the conjugation result on crystals via animation
	_animate_conjugation(g_sym_id, h_sym_id, result)

	# Show result in CrackingPanel
	if _cracking_panel != null and is_instance_valid(_cracking_panel):
		_cracking_panel.show_result(g_sym_id, h_sym_id, result)

	# Emit signal for UI updates
	conjugation_result.emit(g_sym_id, h_sym_id,
		result["result_sym_id"], result["stayed_in"])

	# Update counter
	_update_layer_4_counter()

	# Show feedback
	_show_conjugation_feedback(g_sym_id, h_sym_id, result)

	# Refresh panel state
	_refresh_cracking_panel()


## Called when the player confirms the active subgroup is normal.
func on_confirm_normal_layer4() -> void:
	if conjugation_cracking_mgr == null:
		return

	var result: Dictionary = conjugation_cracking_mgr.confirm_normal()
	if result["confirmed"]:
		_show_normal_confirmed_feedback()
		_update_layer_4_counter()
		_save_layer_4_progress()
		_refresh_cracking_panel()
		# Show confirmation animation on the CrackingPanel
		if _cracking_panel != null and is_instance_valid(_cracking_panel):
			_cracking_panel.show_normal_confirmed()
	else:
		_show_wrong_normal_feedback()
		# Show error animation on the CrackingPanel
		if _cracking_panel != null and is_instance_valid(_cracking_panel):
			_cracking_panel.show_wrong_normal()


## Called when a key press selects the conjugator g for Layer 4.
func on_conjugator_selected(sym_id: String) -> void:
	if conjugation_cracking_mgr == null:
		return
	# Route through CrackingPanel — fills the g slot visually
	if _cracking_panel != null and is_instance_valid(_cracking_panel):
		_cracking_panel.set_g(sym_id)
	else:
		# Fallback: direct test (if panel not available)
		_selected_g = sym_id
		if _selected_h != "":
			on_conjugation_test(_selected_g, _selected_h)
			_selected_g = ""
			_selected_h = ""
		else:
			_show_g_selected_feedback(sym_id)


## Called when the ⊕ button selects the target h for Layer 4.
func on_target_selected(sym_id: String) -> void:
	if conjugation_cracking_mgr == null:
		return
	# Only allow h from the active subgroup
	var active_idx: int = conjugation_cracking_mgr.get_active_subgroup_index()
	if active_idx < 0:
		_show_no_subgroup_selected_feedback()
		return
	var elements: Array = conjugation_cracking_mgr.get_subgroup_elements(active_idx)
	if not elements.has(sym_id):
		_show_h_not_in_subgroup_feedback(sym_id)
		return
	# Route through CrackingPanel — fills the h slot visually
	if _cracking_panel != null and is_instance_valid(_cracking_panel):
		_cracking_panel.set_h(sym_id)
	else:
		# Fallback: direct test (if panel not available)
		_selected_h = sym_id
		if _selected_g != "":
			on_conjugation_test(_selected_g, _selected_h)
			_selected_g = ""
			_selected_h = ""
		else:
			_show_h_selected_feedback(sym_id)


func _show_g_selected_feedback(sym_id: String) -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return
	var name: String = conjugation_cracking_mgr.get_name(sym_id)
	hl.text = "g = %s  — теперь выберите h (⊕)" % name
	hl.add_theme_color_override("font_color", L4_RED_DIM)


func _show_h_selected_feedback(sym_id: String) -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return
	var name: String = conjugation_cracking_mgr.get_name(sym_id)
	hl.text = "h = %s  — теперь нажмите ключ (g)" % name
	hl.add_theme_color_override("font_color", L4_RED_DIM)


func _show_no_subgroup_selected_feedback() -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return
	hl.text = "Сначала выберите подгруппу на панели слева"
	hl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3, 0.8))


func _show_h_not_in_subgroup_feedback(sym_id: String) -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return
	var name: String = conjugation_cracking_mgr.get_name(sym_id)
	hl.text = "%s не принадлежит выбранной подгруппе" % name
	hl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3, 0.8))


## Layer 4 theme application.
func _apply_layer_4_theme(level_scene) -> void:
	var hud = level_scene.hud_layer

	# Level number label — add "Слой 4" indicator
	var lvl_label = hud.get_node_or_null("LevelNumberLabel")
	if lvl_label:
		lvl_label.text += "  ·  Слой 4: Нормальные"
		lvl_label.add_theme_color_override("font_color", L4_RED_DIM)

	# Map frame title → indicate Layer 4
	var map_frame = hud.get_node_or_null("MapFrame")
	if map_frame:
		var map_title = map_frame.get_node_or_null("MapFrameTitle")
		if map_title:
			map_title.text = "Карта комнат — Нормальные"
			map_title.add_theme_color_override("font_color", L4_RED_DIM)

	# KeyBar frame title → indicate conjugation testing
	var key_frame = hud.get_node_or_null("KeyBarFrame")
	if key_frame:
		var key_title = key_frame.get_node_or_null("KeyBarFrameTitle")
		if key_title:
			key_title.text = "Ключи — сопряжение g·h·g⁻¹"
			key_title.add_theme_color_override("font_color", L4_RED_DIM)

	# Counter label → red
	var counter = hud.get_node_or_null("CounterLabel")
	if counter:
		counter.add_theme_color_override("font_color", L4_RED_DIM)


## Update the counter label for Layer 4 progress.
func _update_layer_4_counter() -> void:
	if _level_scene == null or conjugation_cracking_mgr == null:
		return
	var cl = _level_scene.hud_layer.get_node_or_null("CounterLabel")
	if cl:
		var p: Dictionary = conjugation_cracking_mgr.get_progress()
		cl.text = "Подгруппы: %d / %d" % [p["classified"], p["total"]]


## Save Layer 4 progress.
func _save_layer_4_progress() -> void:
	if conjugation_cracking_mgr == null:
		return
	GameManager.set_layer_progress(_hall_id, 4, conjugation_cracking_mgr.save_state())


## Animate a conjugation: briefly show g, then h, then g⁻¹ on crystals.
func _animate_conjugation(g_sym_id: String, h_sym_id: String, result: Dictionary) -> void:
	if _level_scene == null:
		return
	# Visual feedback — flash crystals based on the result
	if _level_scene.feedback_fx:
		if result["stayed_in"]:
			# Conjugate stayed in H — subtle green glow
			_level_scene.feedback_fx.play_valid_feedback(
				_level_scene.crystals.values(), _level_scene.edges)
		else:
			# Conjugate escaped H — red flash (the "crack")
			_level_scene.feedback_fx.play_invalid_feedback(
				_level_scene.crystals.values(), _level_scene.edges)


## Show feedback for a conjugation test result.
func _show_conjugation_feedback(g_sym_id: String, h_sym_id: String, result: Dictionary) -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return

	var g_name: String = conjugation_cracking_mgr.get_name(g_sym_id)
	var h_name: String = conjugation_cracking_mgr.get_name(h_sym_id)
	var r_name: String = result.get("result_name", "?")
	var text: String
	var color: Color

	if result["stayed_in"]:
		text = "%s · %s · %s⁻¹ = %s  ∈ H ✓" % [g_name, h_name, g_name, r_name]
		color = Color(0.3, 0.9, 0.4, 0.9)
	else:
		text = "%s · %s · %s⁻¹ = %s  ∉ H — взлом!" % [g_name, h_name, g_name, r_name]
		color = L4_RED

	hl.text = text
	var tw: Tween = _level_scene.create_tween()
	tw.tween_property(hl, "theme_override_colors/font_color", color, 0.3)
	tw.tween_interval(3.0)
	tw.tween_property(hl, "theme_override_colors/font_color",
		Color(0.6, 0.4, 0.4, 0.5), 1.0)


## Show feedback when normal confirmation is correct.
func _show_normal_confirmed_feedback() -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return
	hl.text = "Подгруппа нормальная — не взламывается!"
	var tw: Tween = _level_scene.create_tween()
	tw.tween_property(hl, "theme_override_colors/font_color",
		Color(0.3, 1.0, 0.5, 1.0), 0.3)
	tw.tween_interval(3.0)
	tw.tween_property(hl, "theme_override_colors/font_color",
		Color(0.6, 0.4, 0.4, 0.5), 1.0)

	if _level_scene.feedback_fx:
		_level_scene.feedback_fx.play_completion_feedback(
			_level_scene.crystals.values(), _level_scene.edges)


## Show feedback when player wrongly claims a subgroup is normal.
func _show_wrong_normal_feedback() -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl == null:
		return
	hl.text = "Эта подгруппа НЕ нормальная — попробуйте найти контрпример!"
	var tw: Tween = _level_scene.create_tween()
	tw.tween_property(hl, "theme_override_colors/font_color",
		Color(1.0, 0.5, 0.3, 0.9), 0.3)
	tw.tween_interval(3.0)
	tw.tween_property(hl, "theme_override_colors/font_color",
		Color(0.6, 0.4, 0.4, 0.5), 1.0)


## Build the Layer 4 cracking panel — three-slot maneuver zone + subgroup list.
## Uses 30% of the crystal zone width (same split as Layer 3 keyring).
func _build_cracking_panel(level_scene) -> void:
	var hud: CanvasLayer = level_scene.hud_layer
	if conjugation_cracking_mgr == null or _room_state == null:
		return

	# Get the current crystal zone rectangle
	var crystal_rect: Rect2 = level_scene._crystal_rect
	if crystal_rect.size == Vector2.ZERO:
		return

	# Split: cracking panel gets 30% of the crystal zone width
	var panel_ratio: float = 0.30
	var panel_w: float = floorf(crystal_rect.size.x * panel_ratio)
	var crystal_new_w: float = crystal_rect.size.x - panel_w - 2

	# Cracking panel rectangle (left side of old crystal zone)
	var panel_rect: Rect2 = Rect2(
		crystal_rect.position.x,
		crystal_rect.position.y,
		panel_w,
		crystal_rect.size.y
	)

	# New crystal zone (right side, narrower)
	var new_crystal_rect: Rect2 = Rect2(
		crystal_rect.position.x + panel_w + 2,
		crystal_rect.position.y,
		crystal_new_w,
		crystal_rect.size.y
	)

	# Resize crystal frame
	var crystal_frame = hud.get_node_or_null("CrystalFrame")
	if crystal_frame:
		crystal_frame.position = new_crystal_rect.position
		crystal_frame.size = new_crystal_rect.size

	# Reposition crystal and edge containers
	level_scene.crystal_container.position = new_crystal_rect.position
	level_scene.edge_container.position = new_crystal_rect.position

	# Reposition crystals to fit in the narrower zone
	var nd: Array = level_scene.level_data.get("graph", {}).get("nodes", [])
	var pm: Dictionary = ShuffleManager.build_positions_map(nd, new_crystal_rect.size)
	var shuffle_mgr: ShuffleManager = level_scene._shuffle_mgr
	for i in range(shuffle_mgr.current_arrangement.size()):
		var cid: int = shuffle_mgr.current_arrangement[i]
		if cid in level_scene.crystals and i in pm:
			var crystal: CrystalNode = level_scene.crystals[cid]
			crystal.position = pm[i]
			crystal.set_home_position(pm[i])

	# Update the stored crystal rect
	level_scene._crystal_rect = new_crystal_rect

	# Create the CrackingPanel
	_cracking_panel = CrackingPanel.new()
	_cracking_panel.setup(hud, panel_rect, _room_state, conjugation_cracking_mgr)
	hud.add_child(_cracking_panel)

	# Connect cracking panel signals
	_cracking_panel.subgroup_selected.connect(_on_cracking_subgroup_selected)
	_cracking_panel.conjugation_requested.connect(_on_cracking_conjugation_requested)
	_cracking_panel.confirm_normal_requested.connect(on_confirm_normal_layer4)
	_cracking_panel.g_slot_tapped.connect(_on_g_slot_tapped)
	_cracking_panel.h_slot_tapped.connect(_on_h_slot_tapped)


## Handle subgroup selection from CrackingPanel.
func _on_cracking_subgroup_selected(subgroup_index: int) -> void:
	on_subgroup_selected_layer4(subgroup_index)


## Handle conjugation test request from CrackingPanel.
func _on_cracking_conjugation_requested(g_sym_id: String, h_sym_id: String) -> void:
	on_conjugation_test(g_sym_id, h_sym_id)


## Handle g-slot tapped — update hint to tell player to press a key.
func _on_g_slot_tapped() -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl:
		hl.text = "Нажмите ключ для выбора g"
		hl.add_theme_color_override("font_color", L4_RED_DIM)


## Handle h-slot tapped — update hint to tell player to press ⊕.
func _on_h_slot_tapped() -> void:
	if _level_scene == null:
		return
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl:
		hl.text = "Нажмите ⊕ для выбора h из подгруппы"
		hl.add_theme_color_override("font_color", L4_RED_DIM)


## Refresh cracking panel visuals after state change.
func _refresh_cracking_panel() -> void:
	if _cracking_panel != null and is_instance_valid(_cracking_panel):
		_cracking_panel.refresh()


# ── Layer 4 Signal Handlers ──────────────────────────────────────────

func _on_subgroup_cracked(subgroup_index: int, witness_g: String, witness_h: String, result: String) -> void:
	if _level_scene == null:
		return

	_update_layer_4_counter()
	_save_layer_4_progress()

	# Play cracking feedback
	if _level_scene.feedback_fx:
		_level_scene.feedback_fx.play_invalid_feedback(
			_level_scene.crystals.values(), _level_scene.edges)


func _on_subgroup_confirmed_normal(subgroup_index: int) -> void:
	if _level_scene == null:
		return
	_update_layer_4_counter()
	_save_layer_4_progress()


func _on_all_subgroups_classified() -> void:
	_on_layer_4_completed()


func _on_layer_4_completed() -> void:
	if _level_scene == null:
		return

	# Save layer progress as completed
	_save_layer_4_progress()

	# Play completion feedback
	if _level_scene.feedback_fx:
		_level_scene.feedback_fx.play_completion_feedback(
			_level_scene.crystals.values(), _level_scene.edges)

	# Update HUD
	var cl = _level_scene.hud_layer.get_node_or_null("CounterLabel")
	if cl:
		var p: Dictionary = conjugation_cracking_mgr.get_progress()
		cl.text = "Все подгруппы классифицированы! (%d N, %d ✗)" % [
			p["normal_count"], p["cracked_count"]]
		cl.add_theme_color_override("font_color", L4_RED)

	# Show completion hint
	var hl = _level_scene.hud_layer.get_node_or_null("HintLabel")
	if hl:
		hl.text = "Нормальные подгруппы сохраняются при сопряжении"
		hl.add_theme_color_override("font_color", L4_RED)

	# Show completion summary after a delay
	var timer: SceneTreeTimer = _level_scene.get_tree().create_timer(1.5)
	timer.timeout.connect(_show_layer_4_summary)

	# Emit layer completed
	layer_completed.emit(4, _hall_id)


# ── Layer 4 Completion Summary ───────────────────────────────────────

func _show_layer_4_summary() -> void:
	if _level_scene == null:
		return

	var hud: CanvasLayer = _level_scene.hud_layer

	var panel: Panel = Panel.new()
	panel.name = "Layer4SummaryPanel"
	var vp_size: Vector2 = Vector2(1280, 720)
	if _level_scene.get_viewport():
		var vr: Rect2 = _level_scene.get_viewport_rect()
		if vr.size != Vector2.ZERO:
			vp_size = vr.size
	var pw: float = minf(vp_size.x * 0.6, 800.0)
	var ph: float = minf(vp_size.y * 0.7, 500.0)
	panel.position = Vector2((vp_size.x - pw) / 2.0, (vp_size.y - ph) / 2.0)
	panel.size = Vector2(pw, ph)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = L4_RED_BG
	style.border_color = L4_RED
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(prop, 14)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)

	var inner_w: float = pw - 40.0

	# Title
	var title: Label = Label.new()
	title.text = "Слой 4 — Все подгруппы классифицированы!"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", L4_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(20, 20)
	title.size = Vector2(inner_w, 30)
	panel.add_child(title)

	# Insight message
	var insight: Label = Label.new()
	insight.text = "Нормальные подгруппы сохраняются при сопряжении"
	insight.add_theme_font_size_override("font_size", 16)
	insight.add_theme_color_override("font_color", Color(0.9, 0.7, 0.7, 0.9))
	insight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	insight.position = Vector2(20, 58)
	insight.size = Vector2(inner_w, 25)
	panel.add_child(insight)

	# Divider
	var div: Panel = Panel.new()
	div.position = Vector2(60, 92)
	div.size = Vector2(inner_w - 80, 1)
	var div_style: StyleBoxFlat = StyleBoxFlat.new()
	div_style.bg_color = L4_RED_BORDER
	div.add_theme_stylebox_override("panel", div_style)
	panel.add_child(div)

	# List classified subgroups
	var subgroups: Array = conjugation_cracking_mgr.get_target_subgroups() if conjugation_cracking_mgr else []
	var y_offset: int = 105
	for i in range(subgroups.size()):
		var sg: Dictionary = subgroups[i]
		var elements: Array = sg.get("elements", [])
		var classification: Dictionary = conjugation_cracking_mgr.get_classification(i)
		var sg_label: Label = Label.new()
		var elements_str: String = ", ".join(elements)
		if classification.get("is_normal", false):
			sg_label.text = "  ✓ {%s}  — нормальная" % elements_str
			sg_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 0.9))
		else:
			var witness_g: String = classification.get("witness_g", "?")
			sg_label.text = "  ✗ {%s}  — взломана (%s)" % [elements_str, witness_g]
			sg_label.add_theme_color_override("font_color", L4_RED)
		sg_label.add_theme_font_size_override("font_size", 14)
		sg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sg_label.position = Vector2(20, y_offset)
		sg_label.size = Vector2(inner_w, 22)
		panel.add_child(sg_label)
		y_offset += 26

	# "Return to map" button
	var btn: Button = Button.new()
	btn.name = "ReturnToMapBtn"
	btn.text = "ВЕРНУТЬСЯ НА КАРТУ"
	btn.add_theme_font_size_override("font_size", 18)
	var btn_w: float = minf(300.0, inner_w * 0.6)
	btn.position = Vector2((pw - btn_w) / 2.0, ph - 60.0)
	btn.size = Vector2(btn_w, 45)
	btn.pressed.connect(_on_return_to_map)

	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.08, 0.04, 0.04, 0.9)
	btn_style.border_color = L4_RED
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		btn_style.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		btn_style.set(prop, 8)
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover: StyleBoxFlat = btn_style.duplicate()
	btn_hover.bg_color = Color(0.12, 0.06, 0.06, 0.95)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_color_override("font_color", L4_RED)
	panel.add_child(btn)

	# "Continue playing" dismiss button
	var dismiss_btn: Button = Button.new()
	dismiss_btn.name = "L4DismissBtn"
	dismiss_btn.text = "Продолжить играть"
	dismiss_btn.add_theme_font_size_override("font_size", 14)
	var dismiss_w: float = minf(240.0, inner_w * 0.45)
	dismiss_btn.position = Vector2((pw - dismiss_w) / 2.0, ph - 108.0)
	dismiss_btn.size = Vector2(dismiss_w, 36)
	var dismiss_style: StyleBoxFlat = StyleBoxFlat.new()
	dismiss_style.bg_color = Color(0.06, 0.03, 0.03, 0.7)
	dismiss_style.border_color = L4_RED_BORDER
	for prop in ["border_width_left", "border_width_right",
				"border_width_top", "border_width_bottom"]:
		dismiss_style.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
				"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		dismiss_style.set(prop, 6)
	dismiss_btn.add_theme_stylebox_override("normal", dismiss_style)
	var dismiss_hover: StyleBoxFlat = dismiss_style.duplicate()
	dismiss_hover.bg_color = Color(0.10, 0.05, 0.05, 0.85)
	dismiss_btn.add_theme_stylebox_override("hover", dismiss_hover)
	dismiss_btn.add_theme_color_override("font_color", L4_RED_DIM)
	dismiss_btn.pressed.connect(_on_dismiss_layer_4_summary)
	panel.add_child(dismiss_btn)

	# Fade in
	panel.modulate = Color(1, 1, 1, 0)
	_level_scene.create_tween().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.5)


## Dismiss the Layer 4 summary panel and allow continued play.
func _on_dismiss_layer_4_summary() -> void:
	if _level_scene == null:
		return
	var hud: CanvasLayer = _level_scene.hud_layer
	var panel = hud.get_node_or_null("Layer4SummaryPanel")
	if panel and panel.visible:
		var tw: Tween = _level_scene.create_tween()
		tw.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.3)
		tw.tween_callback(panel.queue_free)
	# Show persistent exit button
	HudBuilder.show_post_completion_exit_button(hud, _on_return_to_map)


# ── Query API ────────────────────────────────────────────────────────

## Check if the current layer is complete.
func is_layer_complete() -> bool:
	match current_layer:
		LayerMode.LAYER_2_INVERSE:
			return inverse_pair_mgr != null and inverse_pair_mgr.is_complete()
		LayerMode.LAYER_3_SUBGROUPS:
			return keyring_assembly_mgr != null and keyring_assembly_mgr.is_complete()
		LayerMode.LAYER_4_NORMAL:
			return conjugation_cracking_mgr != null and conjugation_cracking_mgr.is_complete()
		_:
			return false


## Get a short display name for the current layer.
func get_layer_display_name() -> String:
	match current_layer:
		LayerMode.LAYER_1:
			return "Слой 1: Ключи"
		LayerMode.LAYER_2_INVERSE:
			return "Слой 2: Обратные"
		LayerMode.LAYER_3_SUBGROUPS:
			return "Слой 3: Группы"
		LayerMode.LAYER_4_NORMAL:
			return "Слой 4: Нормальные"
		_:
			return "Слой %d" % layer_number
