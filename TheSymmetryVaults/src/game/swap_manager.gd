## SwapManager — Handles crystal swaps, arrangement tracking,
## visual swap animations, reset, and repeat key application.

class_name SwapManager
extends RefCounted

var crystals: Dictionary = {}
var edges: Array[EdgeRenderer] = []
var feedback_fx: FeedbackFX = null
var hud_layer: CanvasLayer = null
var shuffle_mgr: ShuffleManager = null
var level_data: Dictionary = {}
var agent_mode: bool = false
var swap_count: int = 0
var active_repeat_key_index: int = -1
var repeat_animating: bool = false
var _repeat_anim_start_ms: int = 0
const _REPEAT_ANIM_TIMEOUT_MS: int = 3000
var _scene: Node2D = null

func setup(scene: Node2D, p_crystals: Dictionary, p_edges: Array[EdgeRenderer],
		p_feedback_fx: FeedbackFX, p_hud_layer: CanvasLayer,
		p_shuffle_mgr: ShuffleManager, p_level_data: Dictionary,
		p_agent_mode: bool) -> void:
	_scene = scene; crystals = p_crystals; edges = p_edges
	feedback_fx = p_feedback_fx; hud_layer = p_hud_layer
	shuffle_mgr = p_shuffle_mgr; level_data = p_level_data
	agent_mode = p_agent_mode; swap_count = 0
	active_repeat_key_index = -1; repeat_animating = false

func clear() -> void:
	swap_count = 0; active_repeat_key_index = -1; repeat_animating = false

## Perform a visual swap between two crystals. Returns the resulting Permutation.
func perform_swap(crystal_a: CrystalNode, crystal_b: CrystalNode) -> Permutation:
	var pos_a = crystal_a.get_home_position(); var pos_b = crystal_b.get_home_position()
	var dur: float = 0.0 if agent_mode else 0.35
	crystal_a.animate_to_position(pos_b, dur); crystal_b.animate_to_position(pos_a, dur)
	crystal_a.set_home_position(pos_b); crystal_b.set_home_position(pos_a)
	shuffle_mgr.swap_in_arrangement(crystal_a.crystal_id, crystal_b.crystal_id)
	var perm: Permutation = Permutation.from_array(shuffle_mgr.current_arrangement)
	feedback_fx.play_swap_feedback(crystal_a, crystal_b); swap_count += 1
	return perm

## Reset all crystals to the shuffled starting arrangement.
func reset_arrangement() -> void:
	if shuffle_mgr.initial_arrangement.is_empty(): return
	var nd = level_data.get("graph", {}).get("nodes", [])
	var pos_map: Dictionary = ShuffleManager.build_positions_map(nd, _scene._crystal_rect.size)
	for i in range(shuffle_mgr.initial_arrangement.size()):
		var cid: int = shuffle_mgr.initial_arrangement[i]
		var slot_id: int = shuffle_mgr.identity_arrangement[i]
		if cid in crystals and slot_id in pos_map:
			var pos: Vector2 = pos_map[slot_id]
			var dur: float = 0.0 if agent_mode else 0.3
			crystals[cid].animate_to_position(pos, dur); crystals[cid].set_home_position(pos)
	shuffle_mgr.reset_to_initial()

## Move crystals to match current_arrangement (used by submit_permutation).
func apply_arrangement_to_crystals() -> void:
	var nd = level_data.get("graph", {}).get("nodes", [])
	var pm: Dictionary = ShuffleManager.build_positions_map(nd, _scene._crystal_rect.size)
	for i in range(shuffle_mgr.current_arrangement.size()):
		var cid = shuffle_mgr.current_arrangement[i]
		if cid in crystals and i in pm:
			var dur: float = 0.0 if agent_mode else 0.35
			crystals[cid].animate_to_position(pm[i], dur); crystals[cid].set_home_position(pm[i])

## Set the active repeat key when a new symmetry is discovered.
func set_active_repeat_key_latest(key_ring: KeyRing) -> void:
	if key_ring and key_ring.count() > 0: active_repeat_key_index = key_ring.count() - 1

## Apply a repeat key by index. Handles both instant (agent) and animated modes.
func apply_repeat_key(key_index: int, key_ring: KeyRing,
		rebase_inverse: Permutation, validate_callback: Callable) -> void:
	if key_ring == null or key_index < 0 or key_index >= key_ring.count(): return
	var raw_perm: Permutation = key_ring.get_key(key_index)
	var auto_perm: Permutation = raw_perm
	if rebase_inverse != null: auto_perm = raw_perm.compose(rebase_inverse)
	var n: int = shuffle_mgr.current_arrangement.size()
	if n == 0: return
	if auto_perm.is_identity():
		for crystal in crystals.values():
			if crystal is CrystalNode: crystal.play_glow()
		return
	var new_arr: Array[int] = []; new_arr.resize(n)
	for i in range(n): new_arr[i] = shuffle_mgr.current_arrangement[auto_perm.apply(i)]
	var nd = level_data.get("graph", {}).get("nodes", [])
	var pm: Dictionary = ShuffleManager.build_positions_map(nd, _scene._crystal_rect.size)
	var gc: Vector2 = Vector2.ZERO
	for pos in pm.values(): gc += pos
	if pm.size() > 0: gc /= float(pm.size())
	if agent_mode:
		shuffle_mgr.current_arrangement = new_arr; apply_arrangement_to_crystals()
		validate_callback.call(Permutation.from_array(shuffle_mgr.current_arrangement)); return
	repeat_animating = true
	_repeat_anim_start_ms = Time.get_ticks_msec()
	var prep = _scene.create_tween().set_parallel(true)
	for crystal in crystals.values():
		if crystal is CrystalNode:
			prep.tween_property(crystal, "scale", Vector2(1.08, 1.08), 0.2).set_ease(Tween.EASE_OUT)
	var chain: Tween = _scene.create_tween(); chain.tween_interval(0.22)
	chain.tween_callback(_repeat_phase2.bind(n, auto_perm, pm, gc, new_arr, validate_callback))

## Phase 2: crystal movement along arcs.
func _repeat_phase2(n: int, active_perm: Permutation, pm: Dictionary,
		gc: Vector2, new_arr: Array[int], validate_callback: Callable) -> void:
	var max_delay: float = 0.0
	for i in range(n):
		var si: int = active_perm.apply(i)
		if si == i or si >= n: continue
		var cid: int = shuffle_mgr.current_arrangement[si]
		if cid not in crystals or i not in pm: continue
		var crystal: CrystalNode = crystals[cid]
		var from_pos: Vector2 = crystal.position; var to_pos: Vector2 = pm[i]
		var mid: Vector2 = (from_pos + to_pos) / 2.0; var to_c: Vector2 = gc - mid
		if to_c.length() > 0:
			_animate_arc(crystal, from_pos, mid + to_c.normalized() * 40.0, to_pos, 0.5, max_delay)
		else:
			var tw: Tween = _scene.create_tween()
			if max_delay > 0: tw.tween_interval(max_delay)
			tw.tween_property(crystal, "position", to_pos, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		max_delay += 0.03
	var wait: Tween = _scene.create_tween(); wait.tween_interval(0.5 + max_delay + 0.05)
	wait.tween_callback(_repeat_phase3.bind(n, new_arr, pm, validate_callback))

## Phase 3: landing bounce + state update.
func _repeat_phase3(n: int, new_arr: Array[int], pm: Dictionary,
		validate_callback: Callable) -> void:
	shuffle_mgr.current_arrangement = new_arr
	for i in range(n):
		var cid: int = shuffle_mgr.current_arrangement[i]
		if cid in crystals and i in pm: crystals[cid].set_home_position(pm[i])
	for crystal in crystals.values():
		if crystal is CrystalNode:
			var b: Tween = _scene.create_tween()
			b.tween_property(crystal, "scale", Vector2(0.95, 0.95), 0.1).set_ease(Tween.EASE_IN)
			b.tween_property(crystal, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_OUT)
			feedback_fx._spawn_burst(crystal.position, crystal._glow_color, 3)
	var ft: Tween = _scene.create_tween(); ft.tween_interval(0.25)
	ft.tween_callback(_repeat_finalize.bind(validate_callback))

## Final step of repeat key application: validate and unlock animation.
func _repeat_finalize(validate_callback: Callable) -> void:
	var p: Permutation = Permutation.from_array(shuffle_mgr.current_arrangement)
	validate_callback.call(p)
	repeat_animating = false

## Check if repeat_animating has been stuck for too long and reset if so.
func check_repeat_timeout() -> void:
	if repeat_animating and Time.get_ticks_msec() - _repeat_anim_start_ms > _REPEAT_ANIM_TIMEOUT_MS:
		repeat_animating = false

## Animate a crystal along a quadratic Bezier arc using Tween.
func _animate_arc(crystal: CrystalNode, from: Vector2,
		control: Vector2, to: Vector2, duration: float, delay: float) -> void:
	var tw: Tween = _scene.create_tween()
	if delay > 0: tw.tween_interval(delay)
	tw.tween_method(_arc_interpolate.bind(crystal, from, control, to), 0.0, 1.0, duration)
	tw.tween_callback(_arc_snap.bind(crystal, to))

## Bezier arc interpolation step (called by tween_method).
func _arc_interpolate(t: float, crystal: CrystalNode, from: Vector2,
		control: Vector2, to: Vector2) -> void:
	var et: float = 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
	var omt: float = 1.0 - et
	crystal.position = omt * omt * from + 2.0 * omt * et * control + et * et * to

## Snap crystal to final position after arc animation.
func _arc_snap(crystal: CrystalNode, to: Vector2) -> void:
	crystal.position = to
