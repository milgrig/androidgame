## LevelScene — Main level orchestrator.
## Delegates to: ShuffleManager, SwapManager, ValidationManager,
## HudBuilder, LevelTextContent, InnerDoorManager.
## Uses RoomState + RoomMapPanel + KeyBar for the split-screen room-map UI.
class_name LevelScene
extends Node2D

const EchoHintSystem = preload("res://src/game/echo_hint_system.gd")
const TargetPreviewDraw = preload("res://src/visual/target_preview_draw.gd")
signal swap_performed(permutation: Array)
signal symmetry_found(symmetry_id: String, mapping: Array)
signal level_completed(level_id: String)
signal invalid_attempt(mapping: Array)
var _shuffle_mgr: ShuffleManager = ShuffleManager.new()
var _swap_mgr: SwapManager = SwapManager.new()
var _validation_mgr: ValidationManager = ValidationManager.new()
var _door_mgr: InnerDoorManager = InnerDoorManager.new()
var _room_state: RoomState = RoomState.new()
var _layer_controller: LayerModeController = LayerModeController.new()
var _current_layer: int = 1
var _room_map: RoomMapPanel = null
var _key_bar: KeyBar = null
var _crystal_rect: Rect2 = Rect2()
var _map_rect: Rect2 = Rect2()
# RoomBadge removed — current room is shown via KeyBar highlight
var crystal_container: Node2D
var edge_container: Node2D
var feedback_fx: FeedbackFX
var camera: CameraController
var hud_layer: CanvasLayer
var target_preview: Control
var level_data: Dictionary = {}
var level_id: String = ""
var crystals: Dictionary = {}
var edges: Array[EdgeRenderer] = []
var agent_mode: bool = false:
	set(v):
		agent_mode = v
		if _swap_mgr:
			_swap_mgr.agent_mode = v
var current_arrangement: Array[int]:
	get: return _shuffle_mgr.current_arrangement
	set(v): _shuffle_mgr.current_arrangement = v
var key_ring: KeyRing:
	get: return _validation_mgr.key_ring
var crystal_graph: CrystalGraph:
	get: return _validation_mgr.crystal_graph
var target_perms: Dictionary:
	get: return _validation_mgr.target_perms
var target_perm_names: Dictionary:
	get: return _validation_mgr.target_perm_names
var target_perm_descriptions: Dictionary:
	get: return _validation_mgr.target_perm_descriptions
var total_symmetries: int:
	get: return _validation_mgr.total_symmetries
var _shuffle_seed: int:
	get: return _shuffle_mgr.shuffle_seed
var _initial_arrangement: Array[int]:
	get: return _shuffle_mgr.initial_arrangement
var _identity_arrangement: Array[int]:
	get: return _shuffle_mgr.identity_arrangement
var _identity_found: bool:
	get: return _validation_mgr.identity_found
	set(v): _validation_mgr.identity_found = v
var _swap_count: int:
	get: return _swap_mgr.swap_count
	set(v): _swap_mgr.swap_count = v
var _inner_door_panel:
	get: return _door_mgr.panel
var _instruction_panel_visible: bool = false
var _first_symmetry_celebrated: bool = false
var _level_completed_flag: bool = false  ## T100: true after level is completed (stay-and-play mode)
var _show_generators_hint: bool = false
var echo_hint_system = null
var crystal_scene = preload("res://src/visual/crystal_node.tscn")
var edge_scene = preload("res://src/visual/edge_renderer.tscn")

func _ready() -> void:
	_setup_scene_structure()
	if level_data.is_empty():
		var p: String = ""
		if GameManager.current_hall_id != "": p = GameManager.get_level_path(GameManager.current_hall_id)
		if p == "":
			p = GameManager.get_level_path("act%d_level%02d" % [GameManager.current_act, GameManager.current_level])
		if p == "": p = "res://data/levels/act1/level_01.json"
		load_level_from_file(p)

func _setup_scene_structure() -> void:
	edge_container = Node2D.new(); edge_container.name = "EdgeContainer"; add_child(edge_container)
	crystal_container = Node2D.new(); crystal_container.name = "CrystalContainer"; add_child(crystal_container)
	feedback_fx = FeedbackFX.new(); feedback_fx.name = "FeedbackFX"; add_child(feedback_fx)
	camera = CameraController.new(); camera.name = "Camera"; add_child(camera)
	feedback_fx.set_camera_controller(camera)
	hud_layer = CanvasLayer.new(); hud_layer.name = "HUDLayer"; hud_layer.layer = 10; add_child(hud_layer)
	# Build split-screen HUD (crystals left, map right, keys bottom)
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size == Vector2.ZERO:
		vp_size = Vector2(1280, 720)
	var hud_info: Dictionary = HudBuilder.build_split_hud(hud_layer, vp_size, {
		"on_reset": _on_reset_pressed,
		"on_check": _on_check_pressed,
		"on_help": _show_instruction_panel,
		"on_next_level": _on_next_level_pressed,
		"on_map": _on_menu_map_pressed,
		"on_settings": _on_menu_settings_pressed,
	})
	_crystal_rect = hud_info["crystal_rect"]
	target_preview = hud_info["target_preview"]
	_map_rect = hud_info["map_rect"]
	# Offset crystal & edge containers so they render inside the crystal zone
	crystal_container.position = _crystal_rect.position
	edge_container.position = _crystal_rect.position
	# Create RoomMapPanel in the right zone (with padding inside frame)
	var map_rect: Rect2 = _map_rect
	var map_pad: int = 6  # padding inside the map frame
	_room_map = RoomMapPanel.new()
	_room_map.name = "RoomMapPanel"
	_room_map.position = Vector2(map_rect.position.x + map_pad, map_rect.position.y + 18)  # 18px below frame title
	add_child(_room_map)
	# Create KeyBar in the bottom-left zone
	var key_bar_rect: Rect2 = hud_info["key_bar_rect"]
	_key_bar = KeyBar.new()
	_key_bar.name = "KeyBar"
	# Position inside the key bar frame with small inset
	_key_bar.position = Vector2(key_bar_rect.position.x + 4, key_bar_rect.position.y + 16)
	_key_bar.size = Vector2(key_bar_rect.size.x - 8, key_bar_rect.size.y - 20)
	hud_layer.add_child(_key_bar)
	# Connect KeyBar signals
	_key_bar.key_pressed.connect(_on_key_bar_key_pressed)
	_key_bar.key_hovered.connect(_on_key_bar_key_hovered)
	_key_bar.key_add_to_keyring.connect(_on_key_bar_add_to_keyring)
	# Connect RoomMapPanel signals
	_room_map.room_clicked.connect(_on_room_map_clicked)
	_room_map.room_hovered.connect(_on_room_map_hovered)

func load_level_from_file(file_path: String) -> void:
	if not FileAccess.file_exists(file_path): push_error("LevelScene: not found: %s" % file_path); return
	var f = FileAccess.open(file_path, FileAccess.READ); var t = f.get_as_text(); f.close()
	var j = JSON.new()
	if j.parse(t) != OK: push_error("LevelScene: JSON error: %s" % j.get_error_message()); return
	level_data = j.data; _build_level()

func load_level_from_data(data: Dictionary) -> void:
	level_data = data; _build_level()

func _build_level() -> void:
	_clear_level()
	if level_data.is_empty(): return
	var meta = level_data.get("meta", {}); level_id = meta.get("id", "unknown")
	_set_hud_text("LevelNumberLabel", "Акт %d  ·  Уровень %d" % [meta.get("act", 1), meta.get("level", 1)])
	_set_hud_text("TitleLabel", meta.get("title", "Без названия"))
	_set_hud_text("SubtitleLabel", meta.get("subtitle", ""))
	var gd = level_data.get("graph", {}); var nd = gd.get("nodes", []); var ed = gd.get("edges", [])
	_validation_mgr.setup(level_data); _shuffle_mgr.setup(level_id, nd)
	# Initialize RoomState from level data (with rebase if available)
	_room_state.setup(level_data, _validation_mgr.rebase_inverse)
	# Crystal positions use crystal_rect (left half), not full viewport
	var crystal_size: Vector2 = _crystal_rect.size
	if crystal_size == Vector2.ZERO:
		crystal_size = get_viewport_rect().size
	var pm: Dictionary = ShuffleManager.build_positions_map(nd, crystal_size)
	for i in range(_shuffle_mgr.current_arrangement.size()):
		var cid: int = _shuffle_mgr.current_arrangement[i]
		var ndata: Dictionary = {}
		for n in nd:
			if n.get("id", -1) == cid: ndata = n; break
		var c = crystal_scene.instantiate() as CrystalNode
		c.crystal_id = cid; c.set_crystal_color(ndata.get("color", "blue")); c.set_label(ndata.get("label", ""))
		var pos: Vector2 = pm.get(_shuffle_mgr.identity_arrangement[i], Vector2.ZERO)
		c.position = pos; c.set_home_position(pos)
		c.crystal_dropped_on.connect(_on_crystal_dropped)
		c.drag_started.connect(_on_crystal_drag_started)
		c.drag_cancelled.connect(_on_crystal_drag_cancelled)
		crystal_container.add_child(c); crystals[cid] = c
	target_preview = HudBuilder.setup_target_preview(target_preview, hud_layer, nd, ed, TargetPreviewDraw)
	for e in ed:
		var edge = edge_scene.instantiate() as EdgeRenderer
		var fid: int = e.get("from", 0); var tid: int = e.get("to", 0)
		edge.from_node_id = fid; edge.to_node_id = tid
		edge.set_edge_type(e.get("type", "standard")); edge.weight = e.get("weight", 1); edge.directed = e.get("directed", false)
		if fid in crystals and tid in crystals: edge.bind_crystals(crystals[fid], crystals[tid])
		edge_container.add_child(edge); edges.append(edge)
	# Crystal positions are already computed to fit inside crystal_rect
	# by build_positions_map(). No camera centering needed — crystals
	# render directly in world coords matching the crystal zone.
	_swap_mgr.setup(self, crystals, edges, feedback_fx, hud_layer, _shuffle_mgr, level_data, agent_mode)
	var mech = level_data.get("mechanics", {})
	_show_generators_hint = mech.get("show_generators_hint", false)
	# Setup RoomMapPanel with room state data (use map frame inner size)
	if _room_map:
		var map_pad: int = 6
		var map_inner_w: float = _map_rect.size.x - map_pad * 2
		var map_inner_h: float = _map_rect.size.y - 18 - map_pad  # 18 for frame title
		var map_sz: Vector2 = Vector2(map_inner_w, map_inner_h)
		_room_map.home_visible = false  # Home hidden until first correct permutation
		_room_map.setup(_room_state, map_sz)
	# Setup KeyBar with room state (Home hidden until first correct permutation)
	if _key_bar:
		_key_bar.home_visible = false
		_key_bar.rebuild(_room_state)
	for pn in ["CompleteSummaryPanel"]:
		var node = hud_layer.get_node_or_null(pn)
		if node: node.visible = false
	_update_counter(); _update_status_label(); _setup_echo_hints()
	_first_symmetry_celebrated = false; _swap_mgr.swap_count = 0; _level_completed_flag = false
	if not agent_mode:
		_show_instruction_panel()
		if meta.get("act", 0) == 1:
			for c in crystals.values():
				if c is CrystalNode: c.set_idle_pulse(true)
	var idd: Array = mech.get("inner_doors", []); var sgl: Array = level_data.get("subgroups", [])
	if idd.size() > 0 and idd[0] is Dictionary:
		_door_mgr.setup(idd, sgl, key_ring, self, hud_layer, edge_container, level_data,
			_on_inner_door_opened, _on_inner_door_failed,
			_on_selector_door_opened, _on_selector_validated)
	# Layer-specific setup (Layer 2+ modes)
	_current_layer = GameManager.current_layer
	if _current_layer > 1:
		_layer_controller.setup(_current_layer, level_data, self)
		_layer_controller.layer_completed.connect(_on_layer_completed)

func _clear_level() -> void:
	_layer_controller.cleanup()
	_door_mgr.cleanup()
	if echo_hint_system: echo_hint_system.cleanup(); echo_hint_system.queue_free(); echo_hint_system = null
	for c in crystals.values(): c.queue_free()
	crystals.clear()
	for e in edges: e.queue_free()
	edges.clear()
	_shuffle_mgr.clear(); _validation_mgr.clear(); _swap_mgr.clear()
	_room_state.clear()
	# T100: clean up post-completion UI
	HudBuilder.hide_post_completion_exit_button(hud_layer)
	var sp = hud_layer.get_node_or_null("SettingsPopup")
	if sp: sp.queue_free()
	# Clean up layer summary panels
	for panel_name in ["Layer2SummaryPanel", "Layer3SummaryPanel", "Layer4SummaryPanel"]:
		var lp = hud_layer.get_node_or_null(panel_name)
		if lp: lp.queue_free()

func _set_hud_text(n: String, t: String) -> void:
	var l = hud_layer.get_node_or_null(n)
	if l: l.text = t
func _on_inner_door_opened(sg_name: String) -> void:
	_door_mgr.on_door_opened(sg_name, self, feedback_fx, crystals, edges, hud_layer, camera)
	_update_counter()
	if _is_level_complete(): _on_level_complete()
func _on_inner_door_failed(_door_id: String, _reason: Dictionary) -> void:
	_door_mgr.on_door_failed(_door_id, crystals)
func _is_level_complete() -> bool:
	# Layer 2+: delegate to layer controller
	if _current_layer > 1:
		return _layer_controller.is_layer_complete()
	var mech = level_data.get("mechanics", {})
	var wc: String = mech.get("win_condition", "all_keys")
	if wc == "inner_doors_only":
		# Act 2+: level completes when all inner doors (subgroups) are found
		return _door_mgr.panel != null and _door_mgr.is_all_doors_opened()
	# Default (Act 1): all keys + all doors
	if not _validation_mgr.is_keys_complete(): return false
	return _door_mgr.panel == null or _door_mgr.is_all_doors_opened()

func _on_crystal_drag_cancelled(_cid: int) -> void:
	pass
func _on_selector_door_opened(did: String, _si) -> void:
	_on_inner_door_opened(did)
func _on_selector_validated(valid: bool, _si) -> void:
	_door_mgr.on_subgroup_validated(valid, crystals)
func _on_echo_hint_shown(_l, _t) -> void:
	pass
func _on_echo_perfect_seal_lost() -> void:
	pass
func _on_crystal_drag_started(cid: int) -> void:
	_dismiss_instruction_panel(); _notify_echo_activity()
	for id in crystals:
		if id != cid: crystals[id].play_glow()
func _on_crystal_dropped(fid: int, tid: int) -> void:
	if fid == tid or not (fid in crystals and tid in crystals): return
	_perform_swap(crystals[fid], crystals[tid])
func _perform_swap(ca: CrystalNode, cb: CrystalNode) -> void:
	var perm: Permutation = _swap_mgr.perform_swap(ca, cb); _notify_echo_activity()
	swap_performed.emit(_shuffle_mgr.current_arrangement.duplicate()); _validate_permutation(perm)

# --- Validation ---
func _validate_permutation(perm: Permutation, show_invalid: bool = false) -> void:
	var r: Dictionary = _validation_mgr.validate_permutation(perm)
	if r.get("match", false):
		if r.get("is_new", false):
			symmetry_found.emit(r["sym_id"], perm.mapping)
			feedback_fx.play_valid_feedback(crystals.values(), edges)
			_swap_mgr.set_active_repeat_key_latest(key_ring)
			# Reveal Home on the map and KeyBar after first correct permutation found
			if _room_map and not _room_map.home_visible:
				_room_map.home_visible = true
				_room_map.queue_redraw()
			if _key_bar and not _key_bar.home_visible:
				_key_bar.reveal_home(_room_state)
			# Discover the corresponding room in RoomState
			var room_idx: int = _room_state.find_room_for_perm(perm, _validation_mgr.rebase_inverse)
			if room_idx >= 0:
				_room_state.discover_room(room_idx)
				_room_state.set_current_room(room_idx)
				if _room_map: _room_map.queue_redraw()
				if _key_bar: _key_bar.update_state(_room_state)
			_update_counter(); _update_status_label()
			if r.get("check_perm", perm).is_identity(): HudBuilder.update_target_preview_border(target_preview, true)
			if not _first_symmetry_celebrated: _first_symmetry_celebrated = true; _show_first_symmetry_message(r["sym_id"])
			_check_triggered_hints()
			if _door_mgr.panel: _door_mgr.panel.refresh_keys()
			if _door_mgr.selector: _door_mgr.selector.refresh_keys()
			if _is_level_complete(): _on_level_complete()
		else:
			for c in crystals.values():
				if c is CrystalNode: c.play_glow()
			_update_status_label()
		return
	invalid_attempt.emit(perm.mapping); _update_status_label()
	if show_invalid and crystal_graph:
		var v: Dictionary = crystal_graph.find_violations(perm)
		feedback_fx.play_violation_feedback(v, crystals, edges, crystals.values())
		var vl = hud_layer.get_node_or_null("ViolationLabel")
		if vl and v.get("summary", "") != "":
			vl.text = v["summary"]; var tw = create_tween()
			tw.tween_property(vl, "theme_override_colors/font_color", Color(1.0, 0.4, 0.35, 0.9), 0.25)
			tw.tween_interval(1.8); tw.tween_property(vl, "theme_override_colors/font_color", Color(1.0, 0.4, 0.35, 0.0), 0.6)
	elif show_invalid: feedback_fx.play_invalid_feedback(crystals.values(), edges)

func _reset_arrangement() -> void: _swap_mgr.reset_arrangement()
func _on_reset_pressed() -> void:
	_reset_arrangement(); _update_status_label(); _notify_echo_activity()
	# Reset room state to Home
	_room_state.set_current_room(0)
	if _room_map: _room_map.queue_redraw()
	if _key_bar: _key_bar.update_state(_room_state)
func _on_check_pressed() -> void:
	_notify_echo_activity(); _validate_permutation(Permutation.from_array(_shuffle_mgr.current_arrangement), true)

# --- Key Bar handlers ---

## Handle key press from KeyBar. key_idx is a RoomState index (0..group_order-1).
func _on_key_bar_key_pressed(key_idx: int) -> void:
	_notify_echo_activity()
	_dismiss_instruction_panel()
	if _room_state.group_order == 0: return
	if key_idx < 0 or key_idx >= _room_state.group_order: return

	# Get the permutation for this key (already rebased in RoomState)
	var key_perm: Permutation = _room_state.get_room_perm(key_idx)
	if key_perm == null: return
	# Identity key — just glow, no movement
	if key_perm.is_identity():
		for crystal in crystals.values():
			if crystal is CrystalNode: crystal.play_glow()
		return
	# Record transition in room state
	var from_room: int = _room_state.current_room
	var to_room: int = _room_state.apply_key(key_idx)
	# Add fading edge on the map
	if _room_map: _room_map.add_fading_edge(from_room, to_room, key_idx)
	# Apply the permutation to the crystal arrangement
	# We need to undo the rebase: the permutation stored in room_state is rebased,
	# but swap_mgr.apply_repeat_key expects to compose with rebase_inverse.
	# Since room_state perms ARE already rebased, we can use them directly as auto_perm.
	var auto_perm: Permutation = key_perm
	var n: int = _shuffle_mgr.current_arrangement.size()
	if n == 0: return
	var new_arr: Array[int] = []; new_arr.resize(n)
	for i in range(n): new_arr[i] = _shuffle_mgr.current_arrangement[auto_perm.apply(i)]
	var nd = level_data.get("graph", {}).get("nodes", [])
	var pm: Dictionary = ShuffleManager.build_positions_map(nd, _crystal_rect.size if _crystal_rect.size != Vector2.ZERO else get_viewport_rect().size)
	if agent_mode:
		# Instant mode for agent
		_shuffle_mgr.current_arrangement = new_arr
		_swap_mgr.apply_arrangement_to_crystals()
		var result_perm: Permutation = Permutation.from_array(_shuffle_mgr.current_arrangement)
		_validate_permutation(result_perm)
	else:
		# Animated mode for human player
		_swap_mgr.repeat_animating = true
		_swap_mgr._repeat_anim_start_ms = Time.get_ticks_msec()
		var gc: Vector2 = Vector2.ZERO
		for pos in pm.values(): gc += pos
		if pm.size() > 0: gc /= float(pm.size())
		# Phase 1: slight scale up
		var prep = create_tween().set_parallel(true)
		for crystal in crystals.values():
			if crystal is CrystalNode:
				prep.tween_property(crystal, "scale", Vector2(1.08, 1.08), 0.2).set_ease(Tween.EASE_OUT)
		# Phase 2: move crystals
		var chain: Tween = create_tween(); chain.tween_interval(0.22)
		chain.tween_callback(_key_apply_phase2.bind(n, auto_perm, pm, gc, new_arr))
	# Discover the destination room if new
	_room_state.discover_room(to_room)
	if _room_map: _room_map.queue_redraw()
	if _key_bar: _key_bar.update_state(_room_state)
	_update_counter()
	# Layer 2: notify controller about key press for inverse pair detection
	if _current_layer == 2:
		_layer_controller.on_key_pressed(key_idx, from_room, to_room)
	# Layer 4: key press selects "g" conjugator for conjugation test
	if _current_layer == 4:
		var sym_id: String = _room_state.get_room_sym_id(key_idx)
		if sym_id != "":
			_layer_controller.on_conjugator_selected(sym_id)

## Phase 2 of key application animation: move crystals along arcs.
func _key_apply_phase2(n: int, active_perm: Permutation, pm: Dictionary,
		gc: Vector2, new_arr: Array[int]) -> void:
	var max_delay: float = 0.0
	for i in range(n):
		var si: int = active_perm.apply(i)
		if si == i or si >= n: continue
		var cid: int = _shuffle_mgr.current_arrangement[si]
		if cid not in crystals or i not in pm: continue
		var crystal: CrystalNode = crystals[cid]
		var from_pos: Vector2 = crystal.position; var to_pos: Vector2 = pm[i]
		var mid: Vector2 = (from_pos + to_pos) / 2.0; var to_c: Vector2 = gc - mid
		if to_c.length() > 0:
			_swap_mgr._animate_arc(crystal, from_pos, mid + to_c.normalized() * 40.0, to_pos, 0.5, max_delay)
		else:
			var tw: Tween = create_tween()
			if max_delay > 0: tw.tween_interval(max_delay)
			tw.tween_property(crystal, "position", to_pos, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		max_delay += 0.03
	var wait: Tween = create_tween(); wait.tween_interval(0.5 + max_delay + 0.05)
	wait.tween_callback(_key_apply_phase3.bind(n, new_arr, pm))

## Phase 3 of key application animation: landing bounce + state update + validation.
func _key_apply_phase3(n: int, new_arr: Array[int], pm: Dictionary) -> void:
	_shuffle_mgr.current_arrangement = new_arr
	for i in range(n):
		var cid: int = _shuffle_mgr.current_arrangement[i]
		if cid in crystals and i in pm: crystals[cid].set_home_position(pm[i])
	for crystal in crystals.values():
		if crystal is CrystalNode:
			var b: Tween = create_tween()
			b.tween_property(crystal, "scale", Vector2(0.95, 0.95), 0.1).set_ease(Tween.EASE_IN)
			b.tween_property(crystal, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_OUT)
			feedback_fx._spawn_burst(crystal.position, crystal._glow_color, 3)
	var ft: Tween = create_tween(); ft.tween_interval(0.25)
	ft.tween_callback(_key_apply_finalize)

## Final step of key application: validate and unlock animation.
func _key_apply_finalize() -> void:
	var p: Permutation = Permutation.from_array(_shuffle_mgr.current_arrangement)
	_validate_permutation(p); _update_status_label()
	_swap_mgr.repeat_animating = false

## Handle ⊕ button press from KeyBar — add/remove key to active keyring (Layer 3)
## or select h target for conjugation test (Layer 4).
func _on_key_bar_add_to_keyring(key_idx: int) -> void:
	_notify_echo_activity()
	_dismiss_instruction_panel()
	if _room_state.group_order == 0: return
	if key_idx < 0 or key_idx >= _room_state.group_order: return
	# Block during animation
	if _swap_mgr and _swap_mgr.repeat_animating: return
	var sym_id: String = _room_state.get_room_sym_id(key_idx)
	if sym_id == "": return
	if _current_layer == 3:
		_layer_controller.on_key_tapped_layer3(sym_id)
	elif _current_layer == 4:
		_layer_controller.on_target_selected(sym_id)


## Handle key hover from KeyBar. key_idx == -1 means hover ended.
func _on_key_bar_key_hovered(key_idx: int) -> void:
	if _room_map:
		if key_idx < 0:
			_room_map.clear_hover_key()
		else:
			_room_map.set_hover_key(key_idx)

## Handle room click from RoomMapPanel.
func _on_room_map_clicked(_room_idx: int) -> void:
	pass  # Room badge removed — current room shown via KeyBar highlight

## Handle room hover from RoomMapPanel.
func _on_room_map_hovered(_room_idx: int) -> void:
	pass  # Room badge removed

func _on_layer_completed(layer: int, hall_id: String) -> void:
	# Layer 2+ completion — handled by LayerModeController internally
	# (summary panel, save progress, etc.)
	_level_completed_flag = true  # T100: mark as completed
	level_completed.emit(level_id)

func _update_counter() -> void:
	# Layer 2: counter is managed by LayerModeController
	if _current_layer > 1:
		return
	var cl = hud_layer.get_node_or_null("CounterLabel")
	if cl:
		var disc: int = _room_state.discovered_count() if _room_state.group_order > 0 else (key_ring.count() if key_ring else 0)
		var total: int = _room_state.group_order if _room_state.group_order > 0 else total_symmetries
		var t: String = "Комнаты: %d / %d" % [disc, total]
		if _door_mgr.panel: t += " | Подгруппы: %d / %d" % [_door_mgr.panel.get_opened_count(), _door_mgr.panel.get_total_count()]
		cl.text = t

func _update_status_label() -> void:
	var s = hud_layer.get_node_or_null("StatusLabel")
	if s == null: return
	var info: Dictionary = _validation_mgr.get_status_info(_shuffle_mgr.current_arrangement)
	s.text = info["text"]; s.add_theme_color_override("font_color", info["color"])
func _on_level_complete() -> void:
	if _level_completed_flag:
		return  # T100: prevent re-triggering completion
	_level_completed_flag = true
	if echo_hint_system: echo_hint_system.notify_level_completed()
	# T100: temporarily disable crystals during celebration, re-enabled on dismiss
	for c in crystals.values(): c.set_draggable(false)
	feedback_fx.play_completion_feedback(crystals.values(), edges)
	if _door_mgr.panel: _door_mgr.panel.visible = false
	if _door_mgr.selector: _door_mgr.selector.visible = false
	level_completed.emit(level_id); GameManager.complete_level(level_id)
	get_tree().create_timer(1.2).timeout.connect(_show_complete_summary.bind(level_data.get("meta", {})))
func _show_complete_summary(meta: Dictionary) -> void:
	HudBuilder.show_complete_summary(hud_layer, meta, _show_generators_hint, level_data,
		level_id, target_perm_names, _validation_mgr.build_summary_keys_text(), echo_hint_system, self)
	# T100: connect dismiss button for stay-and-play
	var p = hud_layer.get_node_or_null("CompleteSummaryPanel")
	if p:
		var db = p.get_node_or_null("SummaryDismissButton")
		if db and not db.is_connected("pressed", _on_summary_dismissed):
			db.pressed.connect(_on_summary_dismissed)
func _on_next_level_pressed() -> void:
	if GameManager.hall_tree != null: GameManager.return_to_map(); return
	var np: String = GameManager.get_next_level_path(level_id)
	if np != "": load_level_from_file(np)

## T100: Dismiss the completion summary and allow continued play.
func _on_summary_dismissed() -> void:
	HudBuilder.dismiss_complete_summary(hud_layer, self)
	# Re-enable crystal interaction (Layer 1 only — Layer 2 keeps crystals disabled)
	if _current_layer == 1:
		for c in crystals.values():
			if c is CrystalNode: c.set_draggable(true)
	# Show persistent exit button
	HudBuilder.show_post_completion_exit_button(hud_layer, _on_menu_map_pressed)

## T100: Menu → Карта (return to map).
func _on_menu_map_pressed() -> void:
	HudBuilder.hide_menu_popup(hud_layer)
	GameManager.return_to_map()

## T100: Menu → Настройки (placeholder).
func _on_menu_settings_pressed() -> void:
	HudBuilder.hide_menu_popup(hud_layer)
	_show_settings_popup()

## T100: Simple settings popup (placeholder).
func _show_settings_popup() -> void:
	var existing = hud_layer.get_node_or_null("SettingsPopup")
	if existing:
		existing.visible = not existing.visible
		return

	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size == Vector2.ZERO: vp_size = Vector2(1280, 720)
	var pw: float = 300.0
	var ph: float = 200.0

	var panel: Panel = Panel.new()
	panel.name = "SettingsPopup"
	panel.position = Vector2((vp_size.x - pw) / 2.0, (vp_size.y - ph) / 2.0)
	panel.size = Vector2(pw, ph)
	panel.z_index = 100
	panel.add_theme_stylebox_override("panel", HudBuilder.make_stylebox(
		Color(0.05, 0.06, 0.1, 0.95), 12, Color(0.3, 0.4, 0.6, 0.7), 2))
	hud_layer.add_child(panel)

	var title: Label = Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(10, 15)
	title.size = Vector2(pw - 20, 25)
	panel.add_child(title)

	var placeholder: Label = Label.new()
	placeholder.text = "Скоро здесь появятся настройки\nзвука и интерфейса."
	placeholder.add_theme_font_size_override("font_size", 13)
	placeholder.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placeholder.position = Vector2(20, 55)
	placeholder.size = Vector2(pw - 40, 60)
	panel.add_child(placeholder)

	var close_btn: Button = Button.new()
	close_btn.text = "Закрыть"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.position = Vector2((pw - 120) / 2.0, ph - 50)
	close_btn.size = Vector2(120, 36)
	close_btn.add_theme_stylebox_override("normal", HudBuilder.make_stylebox(
		Color(0.08, 0.12, 0.2, 0.8), 6, Color(0.3, 0.5, 0.7, 0.5), 1))
	close_btn.add_theme_stylebox_override("hover", HudBuilder.make_stylebox(
		Color(0.12, 0.18, 0.3, 0.9), 6, Color(0.4, 0.6, 0.8, 0.7), 1))
	close_btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.9))
	close_btn.pressed.connect(_hide_settings_popup)
	panel.add_child(close_btn)

func _hide_settings_popup() -> void:
	var p = hud_layer.get_node_or_null("SettingsPopup")
	if p: p.visible = false
func _show_instruction_panel() -> void:
	if _current_layer == 4:
		_show_layer_4_instruction_panel()
		return
	if _current_layer == 3:
		_show_layer_3_instruction_panel()
		return
	if _current_layer > 1:
		# Layer 2: show layer-specific instruction
		_show_layer_2_instruction_panel()
		return
	HudBuilder.show_instruction_panel(hud_layer, level_data)
	_instruction_panel_visible = true
	for c in crystals.values():
		if c is CrystalNode: c.set_draggable(false)

func _show_layer_2_instruction_panel() -> void:
	var p = hud_layer.get_node_or_null("InstructionPanel")
	if p == null: return
	var _s: Callable = func(n: String, t: String) -> void: var l = p.get_node_or_null(n); if l: l.text = t
	var meta: Dictionary = level_data.get("meta", {})
	var layer_config: Dictionary = level_data.get("layers", {}).get("layer_2", {})
	_s.call("InstrTitle", "Слой 2 — %s" % meta.get("title", ""))
	_s.call("InstrGoal", layer_config.get("title", "Обратные ключи"))
	_s.call("InstrBody", layer_config.get("instruction", "Нажимайте ключи и наблюдайте за перемещениями по комнатам.\n\nЕсли после двух нажатий вы вернулись в ту же комнату — эти ключи обратные друг другу!"))
	var inm = p.get_node_or_null("InstrNewMechanic")
	if inm: inm.text = layer_config.get("subtitle", "Каждое действие можно отменить"); inm.visible = true
	# Apply green theme to instruction panel
	var title = p.get_node_or_null("InstrTitle")
	if title: title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 1.0))
	var goal = p.get_node_or_null("InstrGoal")
	if goal: goal.add_theme_color_override("font_color", Color(0.2, 0.85, 0.4, 1.0))
	p.visible = true; p.modulate = Color(1, 1, 1, 1)
	_instruction_panel_visible = true

func _show_layer_3_instruction_panel() -> void:
	var p = hud_layer.get_node_or_null("InstructionPanel")
	if p == null: return
	var _s: Callable = func(n: String, t: String) -> void: var l = p.get_node_or_null(n); if l: l.text = t
	var meta: Dictionary = level_data.get("meta", {})
	var layer_config: Dictionary = level_data.get("layers", {}).get("layer_3", {})
	_s.call("InstrTitle", "Слой 3 — %s" % meta.get("title", ""))
	_s.call("InstrGoal", layer_config.get("title", "Брелки — наборы ключей"))
	_s.call("InstrBody", layer_config.get("instruction", "Нажмите ключ — кристаллы покажут его действие.\nНажмите ⊕ рядом с ключом — добавить его в брелок.\n\nНайдите все наборы ключей, замкнутые по композиции."))
	var inm = p.get_node_or_null("InstrNewMechanic")
	if inm: inm.text = layer_config.get("subtitle", "Некоторые ключи естественно группируются"); inm.visible = true
	# Apply gold theme to instruction panel
	var title = p.get_node_or_null("InstrTitle")
	if title: title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.20, 1.0))
	var goal = p.get_node_or_null("InstrGoal")
	if goal: goal.add_theme_color_override("font_color", Color(0.85, 0.72, 0.18, 1.0))
	p.visible = true; p.modulate = Color(1, 1, 1, 1)
	_instruction_panel_visible = true

func _show_layer_4_instruction_panel() -> void:
	var p = hud_layer.get_node_or_null("InstructionPanel")
	if p == null: return
	var _s: Callable = func(n: String, t: String) -> void: var l = p.get_node_or_null(n); if l: l.text = t
	var meta: Dictionary = level_data.get("meta", {})
	var layer_config: Dictionary = level_data.get("layers", {}).get("layer_4", {})
	_s.call("InstrTitle", "Слой 4 — %s" % meta.get("title", ""))
	_s.call("InstrGoal", layer_config.get("title", "Нормальные подгруппы"))
	_s.call("InstrBody", layer_config.get("instruction", "Выберите подгруппу из списка слева.\nВыберите g (ключ) и h (элемент подгруппы).\nСистема вычислит g·h·g⁻¹.\n\nЕсли результат вышел за пределы подгруппы — она взломана!\nЕсли все сопряжения остаются внутри — подгруппа нормальная."))
	var inm = p.get_node_or_null("InstrNewMechanic")
	if inm: inm.text = layer_config.get("subtitle", "Не все подгруппы равноценны"); inm.visible = true
	# Apply red theme to instruction panel
	var title_node = p.get_node_or_null("InstrTitle")
	if title_node: title_node.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3, 1.0))
	var goal = p.get_node_or_null("InstrGoal")
	if goal: goal.add_theme_color_override("font_color", Color(0.8, 0.3, 0.25, 1.0))
	p.visible = true; p.modulate = Color(1, 1, 1, 1)
	_instruction_panel_visible = true

func _dismiss_instruction_panel() -> void:
	if not _instruction_panel_visible: return
	HudBuilder.dismiss_instruction_panel(hud_layer, self)
	_instruction_panel_visible = false
	for c in crystals.values():
		if c is CrystalNode: c.set_draggable(true)
func _input(event: InputEvent) -> void:
	if _instruction_panel_visible and event is InputEventMouseButton and event.pressed:
		_dismiss_instruction_panel(); get_viewport().set_input_as_handled()
		return
	# T100: close menu popup on click outside
	if event is InputEventMouseButton and event.pressed:
		var popup = hud_layer.get_node_or_null("MenuPopup") if hud_layer else null
		if popup and popup.visible:
			var popup_rect: Rect2 = Rect2(popup.position, popup.size)
			var menu_btn = hud_layer.get_node_or_null("MenuButton")
			var menu_rect: Rect2 = Rect2(menu_btn.position, menu_btn.size) if menu_btn else Rect2()
			var click_pos: Vector2 = event.position
			if not popup_rect.has_point(click_pos) and not menu_rect.has_point(click_pos):
				popup.visible = false
func _show_first_symmetry_message(sym_id: String) -> void:
	var rem: int = total_symmetries - (key_ring.count() if key_ring else 0)
	var sn: String = target_perm_names.get(sym_id, "ключ")
	if key_ring and key_ring.count() == 1: _show_hint_msg("Тождество найдено — первый ключ! Осталось: %d. А есть ли ДРУГИЕ правильные расположения?" % rem, Color(0.3, 1.0, 0.5, 0.95))
	elif sn == "Тождество" or sym_id == "e": _show_hint_msg("Вы собрали картинку-цель — первый ключ найден! Осталось: %d." % rem, Color(0.3, 1.0, 0.5, 0.95))
	else: _show_hint_msg("Новый ключ: «%s»! Осталось найти: %d." % [sn, rem], Color(0.3, 1.0, 0.5, 0.95))
func _show_hint_msg(text: String, color: Color) -> void:
	var hl = hud_layer.get_node_or_null("HintLabel")
	if hl == null: return
	hl.text = text; var tw = create_tween()
	tw.tween_property(hl, "theme_override_colors/font_color", color, 0.3)
	tw.tween_interval(3.0); tw.tween_property(hl, "theme_override_colors/font_color", Color(0.5, 0.8, 0.5, 0.5), 1.0)

# --- Old repeat key support (used by Agent API via SwapManager) ---
func _on_repeat_key_clicked(ki: int) -> void:
	_notify_echo_activity()
	_swap_mgr.check_repeat_timeout()
	if _swap_mgr.repeat_animating or key_ring == null or ki < 0 or ki >= key_ring.count(): return
	_swap_mgr.active_repeat_key_index = ki
	_swap_mgr.apply_repeat_key(ki, key_ring, _validation_mgr.rebase_inverse, Callable(self, "_on_repeat_validate"))
func _on_repeat_validate(perm: Permutation) -> void: _validate_permutation(perm); _update_status_label()

func _setup_echo_hints() -> void:
	if echo_hint_system: echo_hint_system.cleanup(); echo_hint_system.queue_free(); echo_hint_system = null
	echo_hint_system = EchoHintSystem.new(); echo_hint_system.name = "EchoHintSystem"; add_child(echo_hint_system)
	echo_hint_system.setup(level_data, hud_layer, crystals)
	echo_hint_system.hint_shown.connect(_on_echo_hint_shown)
	echo_hint_system.perfect_seal_lost.connect(_on_echo_perfect_seal_lost)
func _notify_echo_activity() -> void:
	if echo_hint_system: echo_hint_system.notify_player_action()
func _check_triggered_hints() -> void:
	if key_ring == null: return
	var fc: int = key_ring.count()
	for h in level_data.get("hints", []):
		var tr: String = h.get("trigger", ""); var tx: String = h.get("text", "")
		if tx.is_empty(): continue
		if tr == "after_first_valid" and fc == 1: get_tree().create_timer(4.5).timeout.connect(_show_hint.bind(tx))
		elif tr.begins_with("after_") and tr.ends_with("_found"):
			var ns: String = tr.trim_prefix("after_").trim_suffix("_found")
			if ns.is_valid_int() and fc == int(ns): _show_hint(tx)
func _show_hint(text: String) -> void:
	var hl = hud_layer.get_node_or_null("HintLabel")
	if hl: hl.text = text; create_tween().tween_property(hl, "theme_override_colors/font_color", Color(0.7, 0.7, 0.5, 0.8), 1.0)

# --- Agent API (preserved unchanged) ---

func perform_swap_by_id(from_id: int, to_id: int) -> Dictionary:
	if from_id == to_id: return {"result": "no_op", "reason": "same_crystal"}
	if not (from_id in crystals and to_id in crystals): return {"result": "error", "reason": "invalid_crystal_id", "available_ids": crystals.keys()}
	var ca = crystals[from_id]; var cb = crystals[to_id]
	if not ca.draggable or not cb.draggable: return {"result": "error", "reason": "crystal_not_draggable"}
	_perform_swap(ca, cb); return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement)}
func submit_permutation(mapping: Array) -> Dictionary:
	var n: int = crystal_graph.node_count() if crystal_graph else 0
	if mapping.size() != n: return {"result": "error", "reason": "wrong_size", "expected": n, "got": mapping.size()}
	var perm: Permutation = Permutation.from_array(mapping)
	if not perm.is_valid(): return {"result": "error", "reason": "invalid_permutation"}
	_shuffle_mgr.set_arrangement(mapping); _swap_mgr.apply_arrangement_to_crystals(); _validate_permutation(perm, true)
	return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement)}
func agent_reset() -> Dictionary:
	_reset_arrangement(); _update_status_label(); return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement)}
func agent_check_current() -> Dictionary:
	var perm: Permutation = Permutation.from_array(_shuffle_mgr.current_arrangement); _validate_permutation(perm, true)
	return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement), "is_automorphism": crystal_graph.is_automorphism(perm) if crystal_graph else false}
func agent_repeat_key(key_index: int) -> Dictionary:
	if key_ring == null or key_index < 0 or key_index >= key_ring.count():
		return {"result": "error", "reason": "invalid_key_index", "available_range": [0, key_ring.count() - 1] if key_ring else []}
	_swap_mgr.active_repeat_key_index = key_index
	# Force instant mode for agent calls — ensures arrangement is updated
	# synchronously before we return the result.
	var was_agent: bool = _swap_mgr.agent_mode
	_swap_mgr.agent_mode = true
	_swap_mgr.repeat_animating = false
	_swap_mgr.apply_repeat_key(key_index, key_ring, _validation_mgr.rebase_inverse, Callable(self, "_on_repeat_validate"))
	_swap_mgr.agent_mode = was_agent
	return {"result": "ok", "arrangement": Array(_shuffle_mgr.current_arrangement), "key_index": key_index, "key_name": _validation_mgr.get_key_display_name(key_index)}
