## SwapManager — Handles drag-and-drop crystal swaps, arrangement tracking,
## visual swap animations, reset, and repeat key application.
##
## Responsibilities:
## - Crystal drag-and-drop callbacks
## - Perform visual swap (animate crystals, update arrangement)
## - Reset arrangement to shuffled start
## - Apply arrangement to crystal positions
## - Repeat key animation (3-phase: lift, arc, land)

class_name SwapManager
extends RefCounted


# --- Dependencies (set by LevelScene) ---
var crystals: Dictionary = {}           # crystal_id -> CrystalNode
var edges: Array[EdgeRenderer] = []
var feedback_fx: FeedbackFX = null
var hud_layer: CanvasLayer = null
var shuffle_mgr: ShuffleManager = null
var level_data: Dictionary = {}
var agent_mode: bool = false

# --- Swap tracking ---
var swap_count: int = 0

# --- Repeat Key State ---
var active_repeat_key_index: int = -1
var repeat_animating: bool = false

# --- Signals (forwarded from LevelScene) ---
## Reference to the LevelScene for create_tween(), signal emission, etc.
var _scene: Node2D = null


## Initialize with references to scene objects.
func setup(scene: Node2D, p_crystals: Dictionary, p_edges: Array[EdgeRenderer],
		p_feedback_fx: FeedbackFX, p_hud_layer: CanvasLayer,
		p_shuffle_mgr: ShuffleManager, p_level_data: Dictionary,
		p_agent_mode: bool) -> void:
	_scene = scene
	crystals = p_crystals
	edges = p_edges
	feedback_fx = p_feedback_fx
	hud_layer = p_hud_layer
	shuffle_mgr = p_shuffle_mgr
	level_data = p_level_data
	agent_mode = p_agent_mode
	swap_count = 0
	active_repeat_key_index = -1
	repeat_animating = false


## Reset state for a new level.
func clear() -> void:
	swap_count = 0
	active_repeat_key_index = -1
	repeat_animating = false


## Perform a visual swap between two crystals.
## Updates positions, arrangement tracking, emits particles.
## Returns the resulting Permutation.
func perform_swap(crystal_a: CrystalNode, crystal_b: CrystalNode) -> Permutation:
	var pos_a = crystal_a.get_home_position()
	var pos_b = crystal_b.get_home_position()

	# Animate crystals swapping positions (instant in agent mode)
	var swap_duration := 0.0 if agent_mode else 0.35
	crystal_a.animate_to_position(pos_b, swap_duration)
	crystal_b.animate_to_position(pos_a, swap_duration)

	# Update home positions
	crystal_a.set_home_position(pos_b)
	crystal_b.set_home_position(pos_a)

	# Swap in tracking array
	shuffle_mgr.swap_in_arrangement(crystal_a.crystal_id, crystal_b.crystal_id)

	# Build Permutation object from current arrangement
	var perm := Permutation.from_array(shuffle_mgr.current_arrangement)

	# Swap feedback particles
	feedback_fx.play_swap_feedback(crystal_a, crystal_b)

	# Track swap count
	swap_count += 1

	return perm


## Reset all crystals to the shuffled starting arrangement.
func reset_arrangement() -> void:
	if shuffle_mgr.initial_arrangement.is_empty():
		return

	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var viewport_size = _scene.get_viewport_rect().size
	var pos_map := ShuffleManager.build_positions_map(nodes_data, viewport_size)

	# Restore each crystal to its shuffled start position
	for i in range(shuffle_mgr.initial_arrangement.size()):
		var crystal_id: int = shuffle_mgr.initial_arrangement[i]
		var slot_id: int = shuffle_mgr.identity_arrangement[i]
		if crystal_id in crystals and slot_id in pos_map:
			var pos: Vector2 = pos_map[slot_id]
			var reset_duration := 0.0 if agent_mode else 0.3
			crystals[crystal_id].animate_to_position(pos, reset_duration)
			crystals[crystal_id].set_home_position(pos)

	# Reset tracking to initial shuffled arrangement
	shuffle_mgr.reset_to_initial()


## Move crystals to match current_arrangement (used by submit_permutation).
func apply_arrangement_to_crystals() -> void:
	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var viewport_size = _scene.get_viewport_rect().size
	var positions_map := ShuffleManager.build_positions_map(nodes_data, viewport_size)

	for i in range(shuffle_mgr.current_arrangement.size()):
		var crystal_id = shuffle_mgr.current_arrangement[i]
		if crystal_id in crystals and i in positions_map:
			var target_pos = positions_map[i]
			var duration := 0.0 if agent_mode else 0.35
			crystals[crystal_id].animate_to_position(target_pos, duration)
			crystals[crystal_id].set_home_position(target_pos)


## Set the active repeat key when a new symmetry is discovered.
func set_active_repeat_key_latest(key_ring: KeyRing) -> void:
	if key_ring and key_ring.count() > 0:
		active_repeat_key_index = key_ring.count() - 1
		_update_repeat_button_text(key_ring)


## Apply a repeat key by index. Handles both instant (agent) and animated modes.
## validate_callback: Callable that takes (Permutation) for post-apply validation.
func apply_repeat_key(key_index: int, key_ring: KeyRing,
		rebase_inverse: Permutation, validate_callback: Callable) -> void:
	if key_ring == null or key_index < 0 or key_index >= key_ring.count():
		return

	# Get the rebased automorphism for this key
	var raw_perm: Permutation = key_ring.get_key(key_index)
	var auto_perm: Permutation = raw_perm
	if rebase_inverse != null:
		auto_perm = raw_perm.compose(rebase_inverse)

	var n := shuffle_mgr.current_arrangement.size()
	if n == 0:
		return

	# If identity automorphism — just flash, don't move
	if auto_perm.is_identity():
		for crystal in crystals.values():
			if crystal is CrystalNode:
				crystal.play_glow()
		return

	# Compute new arrangement via left composition
	var new_arrangement: Array[int] = []
	new_arrangement.resize(n)
	for i in range(n):
		new_arrangement[i] = shuffle_mgr.current_arrangement[auto_perm.apply(i)]

	# Build positions map
	var graph_data = level_data.get("graph", {})
	var nodes_data = graph_data.get("nodes", [])
	var viewport_size = _scene.get_viewport_rect().size
	var positions_map := ShuffleManager.build_positions_map(nodes_data, viewport_size)

	# Compute graph center for arc control points
	var graph_center := Vector2.ZERO
	for pos in positions_map.values():
		graph_center += pos
	if positions_map.size() > 0:
		graph_center /= float(positions_map.size())

	if agent_mode:
		# Instant mode: no animation
		shuffle_mgr.current_arrangement = new_arrangement
		apply_arrangement_to_crystals()
		var perm := Permutation.from_array(shuffle_mgr.current_arrangement)
		validate_callback.call(perm)
		return

	# Animated mode — fully Tween-based, no await/coroutines
	repeat_animating = true

	# Phase 1: PREPARATION (0.2 sec) — lift crystals slightly
	var prep_tween = _scene.create_tween().set_parallel(true)
	for crystal in crystals.values():
		if crystal is CrystalNode:
			prep_tween.tween_property(crystal, "scale", Vector2(1.08, 1.08), 0.2).set_ease(Tween.EASE_OUT)

	# Chain to Phase 2
	var chain := _scene.create_tween()
	chain.tween_interval(0.22)
	chain.tween_callback(_repeat_phase2.bind(n, auto_perm, positions_map, graph_center,
		new_arrangement, validate_callback))


## Phase 2 of repeat animation: crystal movement along arcs.
func _repeat_phase2(n: int, active_perm: Permutation, positions_map: Dictionary,
		graph_center: Vector2, new_arrangement: Array[int],
		validate_callback: Callable) -> void:
	var max_delay := 0.0

	for i in range(n):
		var source_pos_index: int = active_perm.apply(i)
		if source_pos_index == i:
			continue
		if source_pos_index >= n:
			continue

		var crystal_id: int = shuffle_mgr.current_arrangement[source_pos_index]
		if crystal_id not in crystals:
			continue
		if i not in positions_map:
			continue

		var crystal: CrystalNode = crystals[crystal_id]
		var from_pos: Vector2 = crystal.position
		var to_pos: Vector2 = positions_map[i]

		# Calculate Bezier arc control point
		var midpoint: Vector2 = (from_pos + to_pos) / 2.0
		var to_center: Vector2 = graph_center - midpoint
		var arc_offset: float = 40.0
		if to_center.length() > 0:
			var control_point: Vector2 = midpoint + to_center.normalized() * arc_offset
			_animate_crystal_arc_tween(crystal, from_pos, control_point, to_pos, 0.5, max_delay)
		else:
			var straight_tween := _scene.create_tween()
			if max_delay > 0:
				straight_tween.tween_interval(max_delay)
			straight_tween.tween_property(crystal, "position", to_pos, 0.5)\
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

		max_delay += 0.03

	# Chain to Phase 3
	var wait_tween := _scene.create_tween()
	wait_tween.tween_interval(0.5 + max_delay + 0.05)
	wait_tween.tween_callback(_repeat_phase3.bind(n, new_arrangement, positions_map,
		validate_callback))


## Phase 3 of repeat animation: landing bounce + state update.
func _repeat_phase3(n: int, new_arrangement: Array[int], positions_map: Dictionary,
		validate_callback: Callable) -> void:
	# Update state
	shuffle_mgr.current_arrangement = new_arrangement

	# Update home positions
	for i in range(n):
		var crystal_id: int = shuffle_mgr.current_arrangement[i]
		if crystal_id in crystals and i in positions_map:
			crystals[crystal_id].set_home_position(positions_map[i])

	# Bounce effect
	for crystal in crystals.values():
		if crystal is CrystalNode:
			var bounce := _scene.create_tween()
			bounce.tween_property(crystal, "scale", Vector2(0.95, 0.95), 0.1).set_ease(Tween.EASE_IN)
			bounce.tween_property(crystal, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_OUT)
			feedback_fx._spawn_burst(crystal.position, crystal._glow_color, 3)

	# Chain to finish
	var finish_tween := _scene.create_tween()
	finish_tween.tween_interval(0.25)
	finish_tween.tween_callback(_repeat_finish.bind(validate_callback))


## Final phase: validate + re-enable.
func _repeat_finish(validate_callback: Callable) -> void:
	var perm := Permutation.from_array(shuffle_mgr.current_arrangement)
	validate_callback.call(perm)
	repeat_animating = false


## Animate a crystal along a quadratic Bezier arc using Tween.
func _animate_crystal_arc_tween(crystal: CrystalNode, from: Vector2,
		control: Vector2, to: Vector2, duration: float, delay: float) -> Tween:
	var tween := _scene.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_method(_bezier_step.bind(crystal, from, control, to), 0.0, 1.0, duration)
	tween.tween_callback(_snap_crystal_pos.bind(crystal, to))
	return tween


## Bezier interpolation step.
func _bezier_step(t: float, crystal: CrystalNode, from: Vector2,
		control: Vector2, to: Vector2) -> void:
	var eased_t: float
	if t < 0.5:
		eased_t = 2.0 * t * t
	else:
		eased_t = 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
	var one_minus_t := 1.0 - eased_t
	crystal.position = one_minus_t * one_minus_t * from + 2.0 * one_minus_t * eased_t * control + eased_t * eased_t * to


## Snap crystal to final position.
func _snap_crystal_pos(crystal: CrystalNode, pos: Vector2) -> void:
	crystal.position = pos


## Update the REPEAT button text to show active key name.
func _update_repeat_button_text(key_ring: KeyRing) -> void:
	var repeat_btn = hud_layer.get_node_or_null("RepeatButton") if hud_layer else null
	if repeat_btn == null:
		return

	if active_repeat_key_index < 0 or key_ring == null or active_repeat_key_index >= key_ring.count():
		repeat_btn.text = "ПОВТОРИТЬ"
		return

	# Use LevelScene's _get_key_display_name via callback (set externally)
	repeat_btn.text = "ПОВТОРИТЬ"
