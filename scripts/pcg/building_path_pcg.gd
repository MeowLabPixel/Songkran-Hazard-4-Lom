@tool
class_name BuildingPathPCG
extends Path3D

## Procedural Content Generation (PCG) tool for placing modular shop house buildings along a Path3D.
## Designed for Silom Road level design in Songkran: Hazard 4 Lom.

enum SpacingMode {
	COLLISION_BOUNDS, ## Uses exact collision shapes (min_x, max_x) to place buildings flush wall-to-wall
	MODULAR_SLOTS,    ## Uses modular slot grid (standard = 1 building, wide/corner = 2 buildings)
	FIXED_SPACING,    ## Enforces fixed interval spacing
}

enum GateMode {
	RANDOM_CHANCE,   ## Randomly closes front iron gates based on gate_closed_chance
	ALL_CLOSED,      ## All buildings have front iron gates closed
	ALL_OPEN,        ## All buildings have front iron gates open
	ORIGINAL_DEFAULT ## Keeps the original scene gate state
}

const DEFAULT_POOL_PATHS: Array[String] = [
	"res://map/Store_Building/4_storey_v_1_Big_balcony.tscn",
	"res://map/Store_Building/4_storey_v_2_Small_Balcony.tscn",
	"res://map/Store_Building/4_storey_v_3_Small_Balcony.tscn",
	"res://map/Store_Building/4_storey_v_4_Small_Balcony.tscn",
	"res://map/Store_Building/4_storey_v_5_non_balcony.tscn",
	"res://map/Store_Building/4_storey_v_6_Big_balcony.tscn",
	"res://map/Store_Building/4_storey_v_7_Big_balcony.tscn",
	"res://map/Store_Building/4_storey_v_8_Big_balcony.tscn.tscn",
	"res://map/Store_Building/4_storey_v_9_small_balcony.tscn",
	"res://map/Store_Building/4_storey_v_10_mixed.tscn",
	"res://map/Store_Building/4_storey_v_11_mixed.tscn",
	"res://map/Store_Building/4_storey_wide.tscn",
	"res://map/Store_Building/4_storey_wide_2.tscn",
	"res://map/Store_Building/4_storey_wide_3.tscn",
	"res://map/Store_Building/3_storey_1.tscn",
	"res://map/Store_Building/3_storey_v_2.tscn",
	"res://map/Store_Building/3_storey_v_3.tscn",
	"res://map/Store_Building/3_storey_v_4.tscn",
	"res://map/Store_Building/3_storey_v_5.tscn",
	"res://map/Store_Building/3_storey_v_6.tscn",
]

const DEFAULT_CORNER_LEFT_PATH: String = "res://map/Store_Building/4_storey_wide_conner_building_Left.tscn"
const DEFAULT_CORNER_RIGHT_PATH: String = "res://map/Store_Building/4_storey_wide_conner_building_right.tscn"
const PCG_BUILDING_INSTANCE_SCRIPT = preload("res://scripts/pcg/pcg_building_instance.gd")

const KNOWN_SCENE_WIDTHS: Dictionary = {
	"3_storey_1": 4.8,
	"3_storey_v_2": 4.8,
	"3_storey_v_3": 4.8,
	"3_storey_v_4": 4.8,
	"3_storey_v_5": 4.8,
	"3_storey_v_6": 4.8,
	"4_storey_v_1_Big_balcony": 4.8,
	"4_storey_v_2_Small_Balcony": 4.8,
	"4_storey_v_3_Small_Balcony": 4.8,
	"4_storey_v_4_Small_Balcony": 4.8,
	"4_storey_v_5_non_balcony": 4.8,
	"4_storey_v_6_Big_balcony": 4.8,
	"4_storey_v_7_Big_balcony": 4.8,
	"4_storey_v_8_Big_balcony": 4.8,
	"4_storey_v_9_small_balcony": 4.8,
	"4_storey_v_10_mixed": 4.8,
	"4_storey_v_11_mixed": 4.8,
	"4_storey_wide": 9.6,
	"4_storey_wide_2": 9.6,
	"4_storey_wide_3": 9.6,
	"4_storey_wide_conner_building_right": 9.6,
	"4_storey_wide_conner_building_Left": 9.6,
}

# Cache for calculated collision boundaries per scene resource path
var _collision_bounds_cache: Dictionary = {}

# ==================== ACTIONS ====================
@export_group("Generator Actions")
## Click to generate buildings along the path
@export var generate_buildings: bool = false:
	set(val):
		if val:
			generate()

## Click to clear all generated buildings
@export var clear_buildings: bool = false:
	set(val):
		if val:
			clear()

## Automatically re-generates when curve points change
@export var auto_update_on_curve_change: bool = false

## Click to make this path's Curve3D unique (prevents sharing curves when duplicating nodes)
@export var make_curve_unique: bool = false:
	set(val):
		if val:
			_make_curve_unique()

# ==================== ORIENTATION & FLIP ====================
@export_group("Orientation & Flip")
## Toggle to rotate each mesh by Y 180° (flip front to back).
## This will also automatically swap the corner building mesh (Left <-> Right).
@export var flip_front_to_back: bool = false:
	set(val):
		flip_front_to_back = val
		if _has_generated_buildings():
			generate()

## Extra rotation around local Y in degrees (useful for fine-tuning)
@export var extra_rotation_degrees: float = 0.0:
	set(val):
		extra_rotation_degrees = val
		if _has_generated_buildings():
			generate()

## Lateral offset from the path line (positive moves to one side, negative to the other)
@export var lateral_offset: float = 0.0:
	set(val):
		lateral_offset = val
		if _has_generated_buildings():
			generate()

## Height offset relative to path points
@export var height_offset: float = 0.0:
	set(val):
		height_offset = val
		if _has_generated_buildings():
			generate()

## Distance to skip from start of the path
@export var offset_start: float = 0.0:
	set(val):
		offset_start = val
		if _has_generated_buildings():
			generate()

## Distance to skip from end of the path
@export var offset_end: float = 0.0:
	set(val):
		offset_end = val
		if _has_generated_buildings():
			generate()

# ==================== CORNER BUILDINGS ====================
@export_group("Corner Buildings")
## Places a corner building at the end of the path
@export var use_corner_at_end: bool = true:
	set(val):
		use_corner_at_end = val
		if _has_generated_buildings():
			generate()

## Places a corner building at the start of the path
@export var use_corner_at_start: bool = false:
	set(val):
		use_corner_at_start = val
		if _has_generated_buildings():
			generate()

## End corner building when flip_front_to_back is false
@export var corner_end_scene: PackedScene

## End corner building when flip_front_to_back is true (swapped)
@export var corner_end_scene_flipped: PackedScene

## Start corner building when flip_front_to_back is false
@export var corner_start_scene: PackedScene

## Start corner building when flip_front_to_back is true (swapped)
@export var corner_start_scene_flipped: PackedScene

# ==================== SPACING & COLLISION ====================
@export_group("Spacing & Collision")
## Spacing mode:
## COLLISION_BOUNDS: Snaps buildings flush wall-to-wall using their actual CollisionShape3D bounds.
## MODULAR_SLOTS: Uses standard modular units (Standard = 1 building, Wide/Corner = 2 buildings).
## FIXED_SPACING: Uses a fixed distance interval.
@export var spacing_mode: SpacingMode = SpacingMode.COLLISION_BOUNDS:
	set(val):
		spacing_mode = val
		if _has_generated_buildings():
			generate()

## Standard building unit width (used for modular slot calculations, default 4.8m)
@export var base_building_unit_width: float = 4.8:
	set(val):
		base_building_unit_width = maxf(val, 0.5)
		if _has_generated_buildings():
			generate()

## Gap between adjacent buildings. Set to 0.0 for completely flush, wall-to-wall contact.
@export var building_gap: float = 0.0:
	set(val):
		building_gap = val
		if _has_generated_buildings():
			generate()

## Fixed distance used when spacing_mode is set to FIXED_SPACING
@export var fixed_spacing: float = 4.8:
	set(val):
		fixed_spacing = maxf(val, 0.5)
		if _has_generated_buildings():
			generate()

# ==================== RANDOMIZATION & LIMITS ====================
@export_group("Randomization & Limits")
## Maximum building count (0 = unlimited / fill entire path).
## Note: Wide and corner buildings count as 2 buildings!
@export var max_buildings: int = 0:
	set(val):
		max_buildings = maxi(val, 0)
		if _has_generated_buildings():
			generate()

## Deterministic seed for building placement variety
@export var seed_number: int = 12345:
	set(val):
		seed_number = val
		if _has_generated_buildings():
			generate()

## Click to randomize the seed
@export var reroll_seed: bool = false:
	set(val):
		if val:
			seed_number = randi() % 100000
			generate()

## Prevents the exact same building variant from placing side-by-side
@export var avoid_adjacent_duplicates: bool = true:
	set(val):
		avoid_adjacent_duplicates = val
		if _has_generated_buildings():
			generate()

# ==================== IRON GATE CONTROLS ====================
@export_group("Iron Gate Controls (Doors Closed/Open)")
## How front iron gates are assigned during generation
@export var gate_mode: GateMode = GateMode.RANDOM_CHANCE:
	set(val):
		gate_mode = val
		_apply_gate_settings_to_existing()

## Probability of a front iron gate being closed (solid/visible)
@export_range(0.0, 1.0) var gate_closed_chance: float = 0.5:
	set(val):
		gate_closed_chance = val
		if gate_mode == GateMode.RANDOM_CHANCE:
			_apply_gate_settings_to_existing()

## Only affect front shop doors, leaving rear / back gates intact
@export var toggle_front_gates_only: bool = true:
	set(val):
		toggle_front_gates_only = val
		_apply_gate_settings_to_existing()

## Click to re-roll gates without rebuilding the buildings
@export var reroll_gates: bool = false:
	set(val):
		if val:
			_apply_gate_settings_to_existing()

## Click to set all front gates to CLOSED (solid)
@export var set_all_gates_closed: bool = false:
	set(val):
		if val:
			gate_mode = GateMode.ALL_CLOSED
			_apply_gate_settings_to_existing()

## Click to set all front gates to OPEN (accessible)
@export var set_all_gates_open: bool = false:
	set(val):
		if val:
			gate_mode = GateMode.ALL_OPEN
			_apply_gate_settings_to_existing()

# ==================== BUILDING POOL ====================
@export_group("Building Pool")
## Pool of middle shop house buildings to randomly choose from.
## If left empty, all 20 modular shop houses will be loaded automatically.
@export var building_pool: Array[PackedScene] = []

# ==================== BAKE ACTION ====================
@export_group("Bake to Scene")
## Converts generated buildings to regular scene nodes, detaching them from PCG
@export var bake_to_scene: bool = false:
	set(val):
		if val:
			bake()


var _connected_curve: Curve3D = null
var _needs_regenerate: bool = false

func _ready() -> void:
	_init_default_scenes_if_needed()
	_ensure_curve_connected()

func _enter_tree() -> void:
	_ensure_curve_connected()

func _exit_tree() -> void:
	_disconnect_curve()

func _process(_delta: float) -> void:
	_ensure_curve_connected()
	if _needs_regenerate:
		_needs_regenerate = false
		if auto_update_on_curve_change and is_inside_tree():
			generate()

func _make_curve_unique() -> void:
	if curve:
		_disconnect_curve()
		curve = curve.duplicate()
		_ensure_curve_connected()
		print("BuildingPathPCG: Made curve unique for ", name)
		if auto_update_on_curve_change and is_inside_tree():
			generate()

func _ensure_curve_connected() -> void:
	if curve != _connected_curve:
		_disconnect_curve()
		_connected_curve = curve
		if _connected_curve:
			if not _connected_curve.changed.is_connected(_on_curve_changed):
				_connected_curve.changed.connect(_on_curve_changed)

func _disconnect_curve() -> void:
	if _connected_curve:
		if _connected_curve.changed.is_connected(_on_curve_changed):
			_connected_curve.changed.disconnect(_on_curve_changed)
		_connected_curve = null

func _on_curve_changed() -> void:
	if auto_update_on_curve_change:
		_needs_regenerate = true

func _init_default_scenes_if_needed() -> void:
	if corner_end_scene == null and ResourceLoader.exists(DEFAULT_CORNER_LEFT_PATH):
		corner_end_scene = load(DEFAULT_CORNER_LEFT_PATH) as PackedScene
	
	if corner_end_scene_flipped == null and ResourceLoader.exists(DEFAULT_CORNER_RIGHT_PATH):
		corner_end_scene_flipped = load(DEFAULT_CORNER_RIGHT_PATH) as PackedScene
	
	if corner_start_scene == null and ResourceLoader.exists(DEFAULT_CORNER_RIGHT_PATH):
		corner_start_scene = load(DEFAULT_CORNER_RIGHT_PATH) as PackedScene
	
	if corner_start_scene_flipped == null and ResourceLoader.exists(DEFAULT_CORNER_LEFT_PATH):
		corner_start_scene_flipped = load(DEFAULT_CORNER_LEFT_PATH) as PackedScene

	if building_pool.is_empty():
		for path in DEFAULT_POOL_PATHS:
			if ResourceLoader.exists(path):
				var scene: PackedScene = load(path) as PackedScene
				if scene:
					building_pool.append(scene)

func _get_active_end_corner_scene() -> PackedScene:
	_init_default_scenes_if_needed()
	return corner_end_scene_flipped if flip_front_to_back else corner_end_scene

func _get_active_start_corner_scene() -> PackedScene:
	_init_default_scenes_if_needed()
	return corner_start_scene_flipped if flip_front_to_back else corner_start_scene

## Calculates exact local collision bounds for a building scene
func _get_collision_bounds(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {"min_x": -2.4, "max_x": 2.4, "width": 4.8, "is_wide": false}
	
	var scene_path: String = scene.resource_path
	if _collision_bounds_cache.has(scene_path):
		return _collision_bounds_cache[scene_path]

	var file_name: String = scene_path.get_file().get_basename().to_lower()
	var name_says_wide: bool = file_name.contains("wide") or file_name.contains("conner") or file_name.contains("corner")

	var inst: Node3D = scene.instantiate() as Node3D
	if not inst:
		var w: float = 9.6 if name_says_wide else 4.8
		return {"min_x": -w * 0.5, "max_x": w * 0.5, "width": w, "is_wide": name_says_wide}

	var min_x: float = INF
	var max_x: float = -INF

	var col_shapes: Array[Node] = inst.find_children("*", "CollisionShape3D", true, false)
	for col in col_shapes:
		if not (col is CollisionShape3D):
			continue
		var cs: CollisionShape3D = col as CollisionShape3D
		var shape: Shape3D = cs.shape
		if not shape:
			continue

		# Accumulate transform relative to scene root
		var xform: Transform3D = cs.transform
		var p: Node = cs.get_parent()
		while p and p != inst:
			if p is Node3D:
				xform = (p as Node3D).transform * xform
			p = p.get_parent()

		if shape is BoxShape3D:
			var s: Vector3 = (shape as BoxShape3D).size
			for c in [Vector3(-s.x, -s.y, -s.z), Vector3(s.x, s.y, s.z)]:
				var pt: Vector3 = xform * (c * 0.5)
				min_x = minf(min_x, pt.x)
				max_x = maxf(max_x, pt.x)
		elif shape is ConvexPolygonShape3D:
			for pt in (shape as ConvexPolygonShape3D).points:
				var gpt: Vector3 = xform * pt
				min_x = minf(min_x, gpt.x)
				max_x = maxf(max_x, gpt.x)
		elif shape is ConcavePolygonShape3D:
			for pt in (shape as ConcavePolygonShape3D).get_faces():
				var gpt: Vector3 = xform * pt
				min_x = minf(min_x, gpt.x)
				max_x = maxf(max_x, gpt.x)

	inst.free()

	if is_inf(min_x) or is_inf(max_x) or min_x >= max_x:
		var fallback_w: float = 9.6 if name_says_wide else 4.8
		min_x = -fallback_w * 0.5
		max_x = fallback_w * 0.5

	var width: float = max_x - min_x
	var is_wide: bool = name_says_wide or width > 6.0
	var res: Dictionary = {
		"min_x": min_x,
		"max_x": max_x,
		"width": width,
		"is_wide": is_wide
	}
	_collision_bounds_cache[scene_path] = res
	return res

## Returns how many building slots this building occupies (Wide / Corner = 2, Standard = 1)
func get_building_slot_count(scene: PackedScene) -> int:
	var b: Dictionary = _get_collision_bounds(scene)
	return 2 if b["is_wide"] else 1

func _get_or_create_container() -> Node3D:
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container:
		container = Node3D.new()
		container.name = "GeneratedBuildings"
		add_child(container)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			container.owner = get_tree().edited_scene_root
	return container

func _has_generated_buildings() -> bool:
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	return container != null and container.get_child_count() > 0

## Clears all generated buildings
func clear() -> void:
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if container:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

## Main PCG generation algorithm
func generate() -> void:
	if curve == null:
		push_warning("BuildingPathPCG: Path3D has no Curve3D assigned.")
		return
	
	var total_len: float = curve.get_baked_length()
	if total_len <= 1.0:
		push_warning("BuildingPathPCG: Curve length is too short.")
		return

	_init_default_scenes_if_needed()
	
	var active_pool: Array[PackedScene] = []
	for s in building_pool:
		if s != null:
			active_pool.append(s)
	
	if active_pool.is_empty():
		push_warning("BuildingPathPCG: Building pool is empty.")
		return

	clear()
	var container: Node3D = _get_or_create_container()

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_number

	var end_corner_scene_active: PackedScene = _get_active_end_corner_scene() if use_corner_at_end else null
	var start_corner_scene_active: PackedScene = _get_active_start_corner_scene() if use_corner_at_start else null

	var end_bounds: Dictionary = _get_collision_bounds(end_corner_scene_active) if end_corner_scene_active else {}
	var end_w: float = end_bounds.get("width", 9.6) if end_corner_scene_active else 0.0

	var start_bounds: Dictionary = _get_collision_bounds(start_corner_scene_active) if start_corner_scene_active else {}
	var start_w: float = start_bounds.get("width", 9.6) if start_corner_scene_active else 0.0

	var cursor: float = offset_start
	var max_dist: float = total_len - offset_end
	var reserved_for_end: float = (end_w + building_gap) if use_corner_at_end else 0.0

	var placed_count: int = 0

	# 1. Start corner building
	if use_corner_at_start and start_corner_scene_active:
		if cursor + start_w <= max_dist:
			var place_d: float = _calculate_placement_distance(cursor, start_bounds)
			_spawn_building(container, start_corner_scene_active, place_d, rng, "StartCorner")
			cursor += start_w + building_gap
			placed_count += 2 # Corner building counts as 2 buildings

	# 2. Middle modular shop houses
	var last_scene_idx: int = -1
	while cursor + 2.0 <= (max_dist - reserved_for_end):
		if max_buildings > 0 and placed_count >= max_buildings:
			break

		# Pick random building from pool
		var idx: int = rng.randi() % active_pool.size()
		if avoid_adjacent_duplicates and active_pool.size() > 1 and idx == last_scene_idx:
			idx = (idx + 1 + (rng.randi() % (active_pool.size() - 1))) % active_pool.size()
		last_scene_idx = idx

		var scene_to_place: PackedScene = active_pool[idx]
		var b_info: Dictionary = _get_collision_bounds(scene_to_place)
		var b_slots: int = 2 if b_info["is_wide"] else 1
		
		# Determine effective width
		var b_width: float = 0.0
		match spacing_mode:
			SpacingMode.COLLISION_BOUNDS:
				b_width = b_info["width"]
			SpacingMode.MODULAR_SLOTS:
				b_width = b_slots * base_building_unit_width
			SpacingMode.FIXED_SPACING:
				b_width = fixed_spacing

		# Check if max_buildings limit would be exceeded
		if max_buildings > 0 and (placed_count + b_slots) > max_buildings:
			break

		# Check if fitting before reserved end space
		if cursor + b_width > (max_dist - reserved_for_end + 0.1):
			break

		var place_d: float = _calculate_placement_distance(cursor, b_info)
		_spawn_building(container, scene_to_place, place_d, rng, "Building")
		cursor += b_width + building_gap
		placed_count += b_slots # Wide counts as 2, standard counts as 1

	# 3. End corner building (Rule 1)
	if use_corner_at_end and end_corner_scene_active:
		if (max_buildings == 0) or (placed_count + 2 <= max_buildings):
			var place_d: float = _calculate_placement_distance(cursor, end_bounds)
			_spawn_building(container, end_corner_scene_active, place_d, rng, "EndCorner")

## Calculates origin position so building's collision boundary starts precisely at cursor
func _calculate_placement_distance(cursor_pos: float, bounds: Dictionary) -> float:
	var col_min_x: float = bounds.get("min_x", -2.4)
	var col_max_x: float = bounds.get("max_x", 2.4)
	var col_width: float = bounds.get("width", 4.8)

	match spacing_mode:
		SpacingMode.COLLISION_BOUNDS:
			if flip_front_to_back:
				# Rotated 180° around local Y: local X is inverted along curve direction
				return cursor_pos + col_max_x
			else:
				# Normal: leading edge is min_x relative to origin
				return cursor_pos - col_min_x
		
		SpacingMode.MODULAR_SLOTS, SpacingMode.FIXED_SPACING:
			var slot_w: float = (2.0 if bounds.get("is_wide", false) else 1.0) * base_building_unit_width
			if spacing_mode == SpacingMode.FIXED_SPACING:
				slot_w = fixed_spacing
			return cursor_pos + (slot_w * 0.5)
	
	return cursor_pos + (col_width * 0.5)

## Spawns a single building at curve distance d
func _spawn_building(container: Node3D, scene: PackedScene, d: float, rng: RandomNumberGenerator, prefix: String) -> Node3D:
	var instance: Node3D = scene.instantiate() as Node3D
	if not instance:
		return null

	var count: int = container.get_child_count()
	instance.name = "%s_%02d_%s" % [prefix, count, scene.resource_path.get_file().get_basename()]

	# Calculate transform along curve
	var t: Transform3D = _compute_transform_at_distance(d)
	instance.transform = t

	container.add_child(instance)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		instance.owner = get_tree().edited_scene_root

	# Attach or configure PCGBuildingInstance component for gate control
	var building_ctrl: Node = null
	if instance.get_script() == null:
		instance.set_script(PCG_BUILDING_INSTANCE_SCRIPT)
		building_ctrl = instance
	elif instance.get_script() == PCG_BUILDING_INSTANCE_SCRIPT:
		building_ctrl = instance
	else:
		building_ctrl = PCG_BUILDING_INSTANCE_SCRIPT.new()
		building_ctrl.name = "PCGBuildingInstance"
		instance.add_child(building_ctrl)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			building_ctrl.owner = get_tree().edited_scene_root

	# Apply Iron Gate setting
	if building_ctrl:
		var is_closed: bool = true
		match gate_mode:
			GateMode.RANDOM_CHANCE:
				is_closed = rng.randf() < gate_closed_chance
			GateMode.ALL_CLOSED:
				is_closed = true
			GateMode.ALL_OPEN:
				is_closed = false
			GateMode.ORIGINAL_DEFAULT:
				is_closed = true
		
		building_ctrl.front_iron_gate_closed = is_closed
		if not toggle_front_gates_only:
			building_ctrl.back_iron_gate_closed = is_closed

	return instance

## Calculates the position and right-handed orientation Basis at curve distance d
func _compute_transform_at_distance(d: float) -> Transform3D:
	var total_len: float = curve.get_baked_length()
	var clamped_d: float = clampf(d, 0.0, total_len)
	var pos: Vector3 = curve.sample_baked(clamped_d)

	var delta: float = 0.2
	var next_d: float = minf(clamped_d + delta, total_len)
	var prev_d: float = maxf(clamped_d - delta, 0.0)
	var pos_next: Vector3 = curve.sample_baked(next_d)
	var pos_prev: Vector3 = curve.sample_baked(prev_d)
	var tangent: Vector3 = (pos_next - pos_prev).normalized()

	if tangent.is_zero_approx():
		tangent = Vector3(-1, 0, 0)

	# Right-handed coordinate basis:
	# Local X is along the road tangent
	# Local Y is UP
	# Local Z is facade front (facing perpendicular to the path)
	var basis_x: Vector3 = tangent
	var basis_y: Vector3 = Vector3.UP
	var basis_z: Vector3 = basis_x.cross(basis_y).normalized()
	basis_x = basis_y.cross(basis_z).normalized()

	var b: Basis = Basis(basis_x, basis_y, basis_z)

	# Rule 2: Flip front to back (rotate 180° around local Y)
	if flip_front_to_back:
		b = b.rotated(Vector3.UP, PI)

	# User fine-tune rotation
	if not is_zero_approx(extra_rotation_degrees):
		b = b.rotated(Vector3.UP, deg_to_rad(extra_rotation_degrees))

	# Apply lateral offset along facade normal and height offset
	var offset_pos: Vector3 = pos + (b.z * lateral_offset) + (Vector3.UP * height_offset)

	return Transform3D(b, offset_pos)

## Re-applies gate settings to currently existing buildings without regenerating positions
func _apply_gate_settings_to_existing() -> void:
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container:
		return
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_number + 999
	
	for child in container.get_children():
		var ctrl: Node = null
		if child.get_script() == PCG_BUILDING_INSTANCE_SCRIPT:
			ctrl = child
		elif child.has_node("PCGBuildingInstance"):
			ctrl = child.get_node("PCGBuildingInstance")
		
		if ctrl:
			var is_closed: bool = true
			match gate_mode:
				GateMode.RANDOM_CHANCE:
					is_closed = rng.randf() < gate_closed_chance
				GateMode.ALL_CLOSED:
					is_closed = true
				GateMode.ALL_OPEN:
					is_closed = false
				GateMode.ORIGINAL_DEFAULT:
					is_closed = true
			
			ctrl.front_iron_gate_closed = is_closed
			if not toggle_front_gates_only:
				ctrl.back_iron_gate_closed = is_closed

## Bakes the generated buildings into independent scene nodes and removes the PCG connection
func bake() -> void:
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container or container.get_child_count() == 0:
		push_warning("BuildingPathPCG: No buildings to bake.")
		return
	
	container.name = "Baked_Buildings_" + str(randi() % 1000)
	print("BuildingPathPCG: Successfully baked buildings to node: ", container.name)
