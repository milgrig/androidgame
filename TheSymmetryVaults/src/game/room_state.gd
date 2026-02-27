class_name RoomState
extends RefCounted
## RoomState — Maps the group structure as "rooms" for the room-map metaphor.
##
## Each valid crystal arrangement = a room. Number of rooms = group order.
## Room 0 (Home) = identity permutation.
##
## RoomState does NOT replace KeyRing. KeyRing tracks discovery order;
## RoomState tracks the algebraic structure (fixed indices from JSON).
##
## Usage:
##   var rs = RoomState.new()
##   rs.setup(level_data, rebase_inverse)
##   rs.discover_room(0)  # Home is always discovered
##   var dest = rs.apply_key(2)  # move from current_room via key 2

# --- Data fields ---

## Total number of rooms (= group order)
var group_order: int = 0

## All automorphisms, index 0 = identity. Rebased if rebase_inverse != null.
var all_perms: Array = []  # Array[Permutation]

## Display names from JSON (same indexing as all_perms)
var perm_names: Array = []  # Array[String]

## Sym IDs from JSON (same indexing as all_perms), e.g. "e", "r1", "s01"
var perm_ids: Array = []  # Array[String]

## Cayley table: cayley_table[a][b] = index of compose(perm_a, perm_b)
var cayley_table: Array = []  # Array[Array[int]]

## Which rooms have been discovered by the player
var discovered: Array = []  # Array[bool]

## Index of the room the player is currently in
var current_room: int = 0

## Unique color for each room (Room 0 = gold)
var colors: Array = []  # Array[Color]

## History of transitions: {from: int, to: int, key: int, time: float}
var transition_history: Array = []  # Array[Dictionary]


# --- Setup ---

## Initialize from level_data JSON and optional rebase_inverse.
## Reads symmetries.automorphisms, places identity at index 0,
## builds Cayley table, generates colors.
func setup(level_data: Dictionary, rebase_inverse: Permutation = null) -> void:
	var sym_data: Dictionary = level_data.get("symmetries", {})
	var autos: Array = sym_data.get("automorphisms", [])
	if autos.is_empty():
		push_warning("RoomState.setup: no automorphisms in level data")
		return

	# Parse all permutations from JSON
	var raw_perms: Array = []   # Array[Permutation]
	var raw_names: Array = []   # Array[String]
	var raw_ids: Array = []     # Array[String]

	for auto in autos:
		var mapping: Array = auto.get("mapping", [])
		var perm: Permutation = Permutation.from_array(mapping)
		# Apply rebase if provided: rebased = perm compose rebase_inverse
		if rebase_inverse != null:
			perm = perm.compose(rebase_inverse)
		raw_perms.append(perm)
		raw_names.append(auto.get("name", ""))
		raw_ids.append(auto.get("id", ""))

	# Find identity and move it to index 0
	var identity_idx: int = -1
	for i in range(raw_perms.size()):
		if raw_perms[i].is_identity():
			identity_idx = i
			break

	if identity_idx == -1:
		# If no identity found after rebasing, find the one closest to identity
		# (shouldn't happen with correct data)
		push_warning("RoomState.setup: no identity found among automorphisms")
		identity_idx = 0

	# Reorder: identity first, rest follow
	all_perms.clear()
	perm_names.clear()
	perm_ids.clear()

	all_perms.append(raw_perms[identity_idx])
	perm_names.append(raw_names[identity_idx])
	perm_ids.append(raw_ids[identity_idx])

	for i in range(raw_perms.size()):
		if i != identity_idx:
			all_perms.append(raw_perms[i])
			perm_names.append(raw_names[i])
			perm_ids.append(raw_ids[i])

	group_order = all_perms.size()

	# Build Cayley table
	_build_cayley_table()

	# Initialize discovery state
	discovered.clear()
	discovered.resize(group_order)
	for i in range(group_order):
		discovered[i] = false
	discovered[0] = true  # Home is always discovered

	current_room = 0

	# Generate colors
	colors = generate_colors(group_order)

	# Clear history
	transition_history.clear()


## Build the Cayley table from all_perms.
## cayley_table[a][b] = index of the permutation a*b in standard math convention:
## (a*b)(x) = a(b(x)), i.e. apply b first, then a.
## Since Permutation.compose does "self then other" (result[i] = other.apply(self.apply(i))),
## we compute b.compose(a) to get the math convention a*b.
func _build_cayley_table() -> void:
	cayley_table.clear()
	for a in range(group_order):
		var row: Array = []
		row.resize(group_order)
		for b in range(group_order):
			var product: Permutation = all_perms[b].compose(all_perms[a])
			var idx: int = _find_perm_index(product)
			if idx == -1:
				push_warning("RoomState: Cayley table — product not found for [%d][%d]" % [a, b])
				idx = 0  # Fallback to identity
			row[b] = idx
		cayley_table.append(row)


## Find the index of a permutation in all_perms. Returns -1 if not found.
func _find_perm_index(perm: Permutation) -> int:
	for i in range(all_perms.size()):
		if all_perms[i].equals(perm):
			return i
	return -1


# --- Room discovery ---

## Mark a room as discovered. Returns true if it was newly discovered.
func discover_room(idx: int) -> bool:
	if idx < 0 or idx >= group_order:
		return false
	if discovered[idx]:
		return false
	discovered[idx] = true
	return true


## Check if a room is discovered.
func is_discovered(idx: int) -> bool:
	if idx < 0 or idx >= group_order:
		return false
	return discovered[idx]


## Count how many rooms have been discovered.
func discovered_count() -> int:
	var count: int = 0
	for d in discovered:
		if d:
			count += 1
	return count


# --- Navigation ---

## Apply a key from the current room. Updates current_room, records history.
## Returns the destination room index.
func apply_key(key_idx: int) -> int:
	if key_idx < 0 or key_idx >= group_order:
		push_warning("RoomState.apply_key: invalid key_idx %d" % key_idx)
		return current_room

	var dest: int = cayley_table[current_room][key_idx]
	transition_history.append({
		"from": current_room,
		"to": dest,
		"key": key_idx,
		"time": Time.get_ticks_msec() / 1000.0
	})
	current_room = dest
	return dest


## Pure lookup: where does key_idx take you from room `from_room`?
func get_destination(from_room: int, key_idx: int) -> int:
	if from_room < 0 or from_room >= group_order:
		return 0
	if key_idx < 0 or key_idx >= group_order:
		return from_room
	return cayley_table[from_room][key_idx]


## Find which room corresponds to a given permutation.
## If rebase_inverse is provided, applies it before matching.
## Returns -1 if not found.
func find_room_for_perm(perm: Permutation, rebase_inverse: Permutation = null) -> int:
	var check_perm: Permutation = perm
	if rebase_inverse != null:
		check_perm = perm.compose(rebase_inverse)
	return _find_perm_index(check_perm)


## Set current room directly (e.g. when clicking a node on the map).
func set_current_room(idx: int) -> void:
	if idx >= 0 and idx < group_order:
		current_room = idx


# --- Color generation ---

## Generate unique colors for n rooms.
## Room 0 = gold Color(0.788, 0.659, 0.298)
## Remaining rooms: hue spread with maximum separation.
## Port of generateColors() from redesign_map/rooms-keys.html.
static func generate_colors(n: int) -> Array:
	var result: Array = []  # Array[Color]
	if n <= 0:
		return result

	# Room 0: gold (#c9a84c)
	result.append(Color(0.788, 0.659, 0.298, 1.0))

	for i in range(1, n):
		# Hue spread: offset by 200 degrees for visual separation from gold
		var hue: float = fmod(float(i) * 360.0 / float(n - 1) + 200.0, 360.0) / 360.0
		var sat_base: float = 50.0 + float(i % 3) * 10.0  # 50%, 60%, or 70%
		var lit_base: float = 45.0 + float(i % 2) * 10.0   # 45% or 55%
		var sat: float = sat_base / 100.0
		var lit: float = lit_base / 100.0
		var color: Color = _hsl_to_color(hue, sat, lit)
		result.append(color)

	return result


## Convert HSL (all in 0..1 range) to Godot Color.
static func _hsl_to_color(h: float, s: float, l: float) -> Color:
	# Standard HSL to RGB conversion
	var a: float = s * minf(l, 1.0 - l)
	var r: float = _hsl_channel(0.0, h, a, l)
	var g: float = _hsl_channel(8.0, h, a, l)
	var b: float = _hsl_channel(4.0, h, a, l)
	return Color(r, g, b, 1.0)


## Helper for HSL channel calculation (matches JS hslToHex logic).
static func _hsl_channel(n_val: float, h: float, a: float, l: float) -> float:
	var k: float = fmod(n_val + h * 12.0, 12.0)
	return l - a * maxf(minf(minf(k - 3.0, 9.0 - k), 1.0), -1.0)


# --- Serialization ---

## Get serializable state for Agent Bridge / save system.
func get_state() -> Dictionary:
	var disc_indices: Array = []
	for i in range(group_order):
		if discovered[i]:
			disc_indices.append(i)
	return {
		"group_order": group_order,
		"current_room": current_room,
		"discovered": disc_indices,
		"discovered_count": discovered_count(),
		"total_rooms": group_order,
		"transition_count": transition_history.size(),
	}


## Get the display name for a room.
func get_room_name(idx: int) -> String:
	if idx == 0:
		return "Дом"
	if idx >= 0 and idx < perm_names.size() and perm_names[idx] != "":
		return perm_names[idx]
	return "Комната %d" % idx


## Get the sym_id for a room.
func get_room_sym_id(idx: int) -> String:
	if idx >= 0 and idx < perm_ids.size():
		return perm_ids[idx]
	return ""


## Get the permutation for a room.
func get_room_perm(idx: int) -> Permutation:
	if idx >= 0 and idx < all_perms.size():
		return all_perms[idx]
	return null


## Clear all state.
func clear() -> void:
	group_order = 0
	all_perms.clear()
	perm_names.clear()
	perm_ids.clear()
	cayley_table.clear()
	discovered.clear()
	colors.clear()
	current_room = 0
	transition_history.clear()
