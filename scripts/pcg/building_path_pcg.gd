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

enum RenderMode {
	SCENE_INSTANCES,     ## Regular individual scene instances (standard node workflow)
	MULTIMESH,           ## Batched rendering using MultiMeshInstance3D for visual meshes (massive draw-call reduction, collisions & iron gates preserved)
	BATCH_COMBINED_MESH, ## 1 combined mesh + 1 trimesh collision per building (optimal for runtime: 2 draw calls/bldg, full culling, front gates interactive)
	BATCH_WHOLE_PATH,    ## 1 single combined mesh + 1 trimesh for the ENTIRE road (optimal for editor: 1 node, zero scene-tree lag, max editor FPS)
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

class BatchTemplate:
	var mesh: ArrayMesh
	var shape: ConcavePolygonShape3D
	var front_gates: Array[Dictionary] = [] # Array of { "node": Node3D, "transform": Transform3D }

# Static cache for batched building templates (shared across all PCG paths)
static var _batch_cache: Dictionary = {}

# Cache for calculated collision boundaries per scene resource path
var _collision_bounds_cache: Dictionary = {}

# ==================== ACTIONS ====================
@export_group("Generator Actions")
## Click to generate buildings along the path
@export var generate_buildings: bool = false:
	set(val):
		if val and is_inside_tree() and is_node_ready():
			generate()

## Click to clear all generated buildings
@export var clear_buildings: bool = false:
	set(val):
		if val and is_inside_tree():
			clear()

## Automatically re-generates when curve points change
@export var auto_update_on_curve_change: bool = false:
	set(val):
		if auto_update_on_curve_change == val:
			return
		auto_update_on_curve_change = val
		if Engine.is_editor_hint():
			set_process(val)

## Click to make this path's Curve3D unique (prevents sharing curves when duplicating nodes)
@export var make_curve_unique: bool = false:
	set(val):
		if val and is_inside_tree():
			_make_curve_unique()

# ==================== ORIENTATION & FLIP ====================
@export_group("Orientation & Flip")
## Toggle to rotate each mesh by Y 180° (flip front to back).
## This will also automatically swap the corner building mesh (Left <-> Right).
@export var flip_front_to_back: bool = false:
	set(val):
		if flip_front_to_back == val:
			return
		flip_front_to_back = val
		if _has_generated_buildings():
			generate()

## Extra rotation around local Y in degrees (useful for fine-tuning)
@export var extra_rotation_degrees: float = 0.0:
	set(val):
		if is_equal_approx(extra_rotation_degrees, val):
			return
		extra_rotation_degrees = val
		if _has_generated_buildings():
			generate()

## Lateral offset from the path line (positive moves to one side, negative to the other)
@export var lateral_offset: float = 0.0:
	set(val):
		if is_equal_approx(lateral_offset, val):
			return
		lateral_offset = val
		if _has_generated_buildings():
			generate()

## Height offset relative to path points
@export var height_offset: float = 0.0:
	set(val):
		if is_equal_approx(height_offset, val):
			return
		height_offset = val
		if _has_generated_buildings():
			generate()

## Distance to skip from start of the path
@export var offset_start: float = 0.0:
	set(val):
		if is_equal_approx(offset_start, val):
			return
		offset_start = val
		if _has_generated_buildings():
			generate()

## Distance to skip from end of the path
@export var offset_end: float = 0.0:
	set(val):
		if is_equal_approx(offset_end, val):
			return
		offset_end = val
		if _has_generated_buildings():
			generate()

# ==================== CORNER BUILDINGS ====================
@export_group("Corner Buildings")
## Places a corner building at the end of the path
@export var use_corner_at_end: bool = true:
	set(val):
		if use_corner_at_end == val:
			return
		use_corner_at_end = val
		if _has_generated_buildings():
			generate()

## Places a corner building at the start of the path
@export var use_corner_at_start: bool = false:
	set(val):
		if use_corner_at_start == val:
			return
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
		if spacing_mode == val:
			return
		spacing_mode = val
		if _has_generated_buildings():
			generate()

## Standard building unit width (used for modular slot calculations, default 4.8m)
@export var base_building_unit_width: float = 4.8:
	set(val):
		if is_equal_approx(base_building_unit_width, val):
			return
		base_building_unit_width = maxf(val, 0.5)
		if _has_generated_buildings():
			generate()

## Gap between adjacent buildings. Set to 0.0 for completely flush, wall-to-wall contact.
@export var building_gap: float = 0.0:
	set(val):
		if is_equal_approx(building_gap, val):
			return
		building_gap = val
		if _has_generated_buildings():
			generate()

## Fixed distance used when spacing_mode is set to FIXED_SPACING
@export var fixed_spacing: float = 4.8:
	set(val):
		if is_equal_approx(fixed_spacing, val):
			return
		fixed_spacing = maxf(val, 0.5)
		if _has_generated_buildings():
			generate()

# ==================== RANDOMIZATION & LIMITS ====================
@export_group("Randomization & Limits")
## Maximum building count (0 = unlimited / fill entire path).
## Note: Wide and corner buildings count as 2 buildings!
@export var max_buildings: int = 0:
	set(val):
		if max_buildings == val:
			return
		max_buildings = maxi(val, 0)
		if _has_generated_buildings():
			generate()

## Deterministic seed for building placement variety
@export var seed_number: int = 12345:
	set(val):
		if seed_number == val:
			return
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
		if avoid_adjacent_duplicates == val:
			return
		avoid_adjacent_duplicates = val
		if _has_generated_buildings():
			generate()

# ==================== IRON GATE CONTROLS ====================
@export_group("Iron Gate Controls (Doors Closed/Open)")
## How front iron gates are assigned during generation
@export var gate_mode: GateMode = GateMode.RANDOM_CHANCE:
	set(val):
		if gate_mode == val:
			return
		gate_mode = val
		if is_inside_tree() and is_node_ready():
			_apply_gate_settings_to_existing()

## Probability of a front iron gate being closed (solid/visible)
@export_range(0.0, 1.0) var gate_closed_chance: float = 0.5:
	set(val):
		if is_equal_approx(gate_closed_chance, val):
			return
		gate_closed_chance = val
		if gate_mode == GateMode.RANDOM_CHANCE and is_inside_tree() and is_node_ready():
			_apply_gate_settings_to_existing()

## Only affect front shop doors, leaving rear / back gates intact
@export var toggle_front_gates_only: bool = true:
	set(val):
		if toggle_front_gates_only == val:
			return
		toggle_front_gates_only = val
		if is_inside_tree() and is_node_ready():
			_apply_gate_settings_to_existing()

## Click to re-roll gates without rebuilding the buildings
@export var reroll_gates: bool = false:
	set(val):
		if val and is_inside_tree() and is_node_ready():
			_apply_gate_settings_to_existing()

## Click to set all front gates to CLOSED (solid)
@export var set_all_gates_closed: bool = false:
	set(val):
		if val:
			gate_mode = GateMode.ALL_CLOSED
			if is_inside_tree() and is_node_ready():
				_apply_gate_settings_to_existing()

## Click to set all front gates to OPEN (accessible)
@export var set_all_gates_open: bool = false:
	set(val):
		if val:
			gate_mode = GateMode.ALL_OPEN
			if is_inside_tree() and is_node_ready():
				_apply_gate_settings_to_existing()

# ==================== BUILDING POOL ====================
@export_group("Building Pool")
## Pool of middle shop house buildings to randomly choose from.
## If left empty, all 20 modular shop houses will be loaded automatically.
@export var building_pool: Array[PackedScene] = []

# ==================== PERFORMANCE / RENDERING ====================
@export_group("Performance & Rendering")
## Mode used while editing in the Godot Editor viewport.
## Default: BATCH_WHOLE_PATH (gives maximum editor responsiveness & zero node clutter).
@export var editor_render_mode: RenderMode = RenderMode.BATCH_WHOLE_PATH:
	set(val):
		if editor_render_mode == val:
			return
		editor_render_mode = val
		if Engine.is_editor_hint() and _has_generated_buildings():
			generate()

## Mode used when the game is running (runtime).
## Default: BATCH_COMBINED_MESH (gives full frustum culling, occlusion culling, and per-building dither fade).
@export var runtime_render_mode: RenderMode = RenderMode.BATCH_COMBINED_MESH:
	set(val):
		if runtime_render_mode == val:
			return
		runtime_render_mode = val
		if not Engine.is_editor_hint() and is_inside_tree() and _has_generated_buildings():
			generate()

## Non-exported compatibility property for script access and legacy scene loading.
## Note: Does NOT overwrite runtime_render_mode so that loading scenes doesn't clobber runtime settings!
var render_mode: RenderMode:
	get:
		return get_effective_render_mode()
	set(val):
		editor_render_mode = val
		if Engine.is_editor_hint() and _has_generated_buildings():
			generate()

## Sets both editor and runtime render modes simultaneously
func set_both_render_modes(mode: RenderMode) -> void:
	editor_render_mode = mode
	runtime_render_mode = mode
	if _has_generated_buildings():
		generate()

# ==================== BATCHING OPTIONS ====================
@export_group("Batching Options")
## When batching, preserves the FRONT iron gate as a dynamic interactive node so it can open/close.
## The BACK gate is permanently baked into the combined mesh to save draw calls.
@export var batch_preserve_front_gate: bool = true:
	set(val):
		if batch_preserve_front_gate == val:
			return
		batch_preserve_front_gate = val
		_clear_batch_cache()
		if (get_effective_render_mode() == RenderMode.BATCH_COMBINED_MESH or get_effective_render_mode() == RenderMode.BATCH_WHOLE_PATH) and _has_generated_buildings():
			generate()

## Click to clear cached building templates (useful after editing a building .tscn file)
@export var clear_batch_cache: bool = false:
	set(val):
		if val:
			_clear_batch_cache()

## Click to immediately switch editor mode to BATCH_COMBINED_MESH (per-building) and re-generate
@export var batch_buildings_now: bool = false:
	set(val):
		if val and is_inside_tree() and is_node_ready():
			editor_render_mode = RenderMode.BATCH_COMBINED_MESH
			generate()

## Click to immediately switch editor mode to BATCH_WHOLE_PATH (1 mesh for whole road) and re-generate
@export var batch_whole_path_now: bool = false:
	set(val):
		if val and is_inside_tree() and is_node_ready():
			editor_render_mode = RenderMode.BATCH_WHOLE_PATH
			generate()

# ==================== OCCLUSION CULLING ====================
@export_group("Occlusion Culling")
## Automatically generates lightweight 2-triangle QuadOccluder3D party walls and back walls for each building.
## Culls occluded geometry behind and beside buildings with zero door clipping and maximum performance!
@export var generate_occluders: bool = true:
	set(val):
		if generate_occluders == val:
			return
		generate_occluders = val
		if _has_generated_buildings():
			generate()

## Generates rear back wall occluder (culls background city, buildings, and props behind Silom Road)
@export var occlude_back_wall: bool = true:
	set(val):
		if occlude_back_wall == val:
			return
		occlude_back_wall = val
		if _has_generated_buildings():
			generate()

## Generates side party wall occluders between adjacent buildings (culls down-the-street geometry).
## False by default to eliminate acute-angle self-culling during fast 180° camera turns; BackWallOccluder handles 100% of street background culling.
@export var occlude_party_walls: bool = false:
	set(val):
		if occlude_party_walls == val:
			return
		occlude_party_walls = val
		if _has_generated_buildings():
			generate()

## Inset from side and back walls in meters (prevents seam clipping and z-fighting between adjacent buildings)
@export var occluder_wall_inset: float = 0.05:
	set(val):
		if is_equal_approx(occluder_wall_inset, val):
			return
		occluder_wall_inset = maxf(val, 0.0)
		if _has_generated_buildings():
			generate()

## Distance in meters the rear back wall occluder is moved forward into the building interior (default 0.35m = 35cm).
@export var occluder_back_inset: float = 0.35:
	set(val):
		if is_equal_approx(occluder_back_inset, val):
			return
		occluder_back_inset = maxf(val, 0.0)
		if _has_generated_buildings():
			generate()

## Distance in meters the side party wall occluders are moved inward into the building interior (default 0.25m = 25cm).
@export var occluder_side_inset: float = 0.25:
	set(val):
		if is_equal_approx(occluder_side_inset, val):
			return
		occluder_side_inset = maxf(val, 0.0)
		if _has_generated_buildings():
			generate()

## Inset from front facade in meters (ensures side occluders do not clip front doors, balconies, or sidewalks)
@export var occluder_front_inset: float = 0.5:
	set(val):
		if is_equal_approx(occluder_front_inset, val):
			return
		occluder_front_inset = maxf(val, 0.0)
		if _has_generated_buildings():
			generate()

## Extra margin in meters added to each mesh's bounding box for culling tests (default 3.5m).
## Prevents popping during fast 180° camera turns by expanding bounds tested by occlusion and frustum culling.
@export var extra_cull_margin: float = 3.5:
	set(val):
		if is_equal_approx(extra_cull_margin, val):
			return
		extra_cull_margin = maxf(val, 0.0)
		if is_inside_tree() and is_node_ready():
			_apply_cull_margin_to_existing()

## Scale multiplier for occluder wall dimensions (default 0.85 = 15% reduction).
## Keeps both back wall and side party wall occluders safely inside the building core without poking out.
@export_range(0.5, 1.0, 0.01) var occluder_size_scale: float = 0.85:
	set(val):
		if is_equal_approx(occluder_size_scale, val):
			return
		occluder_size_scale = clampf(val, 0.1, 1.0)
		if _has_generated_buildings():
			generate()

## Automatically deactivates occluders for buildings that are close to the player or camera.
## Completely prevents near-plane clipping and screen-blanking when walking inside or near buildings.
@export var disable_near_camera_occluders: bool = true:
	set(val):
		if disable_near_camera_occluders == val:
			return
		disable_near_camera_occluders = val
		if not val:
			_restore_all_occluders()

## Distance in meters from the camera or player within which a building's occluders are temporarily deactivated (default 10.0m).
@export var near_occluder_disable_distance: float = 10.0:
	set(val):
		if is_equal_approx(near_occluder_disable_distance, val):
			return
		near_occluder_disable_distance = maxf(val, 1.0)

# ==================== DISTANCE DITHER FADE ====================
@export_group("Distance Dither Fade")
## Enables triple-AAA GPU screen-space dither fading at distance (VISIBILITY_RANGE_FADE_SELF).
## Distant buildings smoothly dissolve into view along the street curve without popping!
@export var enable_distance_fade: bool = true:
	set(val):
		if enable_distance_fade == val:
			return
		enable_distance_fade = val
		if is_inside_tree() and is_node_ready():
			_apply_fade_settings_to_existing()

## Maximum render distance in meters. Beyond this distance, the building is completely dissolved and culled from rendering.
@export var fade_max_distance: float = 200.0:
	set(val):
		if is_equal_approx(fade_max_distance, val):
			return
		fade_max_distance = maxf(val, 5.0)
		if is_inside_tree() and is_node_ready():
			_apply_fade_settings_to_existing()

## Distance margin in meters over which the GPU dither fade occurs.
## For example, if max is 120m and margin is 25m, the building begins dissolving at 95m and is fully culled at 120m.
@export var fade_transition_margin: float = 25.0:
	set(val):
		if is_equal_approx(fade_transition_margin, val):
			return
		fade_transition_margin = maxf(val, 0.0)
		if is_inside_tree() and is_node_ready():
			_apply_fade_settings_to_existing()

## Screen-space fade mode (VISIBILITY_RANGE_FADE_SELF enables AAA sub-pixel dithering in Forward+).
@export var fade_mode: GeometryInstance3D.VisibilityRangeFadeMode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF:
	set(val):
		if fade_mode == val:
			return
		fade_mode = val
		if is_inside_tree() and is_node_ready():
			_apply_fade_settings_to_existing()

# ==================== BAKE ACTION ====================
@export_group("Bake to Scene")
## When false, generated buildings are runtime procedural children (not serialized into .tscn file, preventing editor freezing and 100MB scene bloat).
## Set to true only if you explicitly want to save individual generated building nodes into the scene file.
@export var persist_to_scene: bool = false

## Converts generated buildings to regular scene nodes, detaching them from PCG
@export var bake_to_scene: bool = false:
	set(val):
		if val:
			bake()


var _connected_curve: Curve3D = null
var _needs_regenerate: bool = false
var _near_occluder_check_timer: float = 0.0

## Returns active render mode based on whether running in Editor or Runtime
func get_effective_render_mode() -> RenderMode:
	if Engine.is_editor_hint():
		return editor_render_mode
	return runtime_render_mode

## Detects the render mode currently present inside the GeneratedBuildings container
func _get_container_render_mode(container: Node3D) -> int:
	if not container or container.get_child_count() == 0:
		return -1
	if container.has_node("CombinedPathMesh"):
		return RenderMode.BATCH_WHOLE_PATH
	if container.has_node("MultiMeshes"):
		return RenderMode.MULTIMESH
	for child in container.get_children():
		if child is Node3D and child.has_node("CombinedMesh"):
			return RenderMode.BATCH_COMBINED_MESH
	return RenderMode.SCENE_INSTANCES

func _ready() -> void:
	_init_default_scenes_if_needed()
	if Engine.is_editor_hint():
		_ensure_curve_connected()
		set_process(auto_update_on_curve_change)
		var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
		if container and _has_generated_buildings():
			var curr_mode: int = _get_container_render_mode(container)
			if curr_mode != editor_render_mode and auto_update_on_curve_change:
				generate()
	else:
		set_process(disable_near_camera_occluders and generate_occluders)
		var needs_gen: bool = not _has_generated_buildings()
		if not needs_gen:
			var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
			if container:
				var curr_mode: int = _get_container_render_mode(container)
				if curr_mode != runtime_render_mode:
					needs_gen = true
		if needs_gen:
			generate()

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_ensure_curve_connected()
		set_process(auto_update_on_curve_change)
	else:
		set_process(disable_near_camera_occluders and generate_occluders)

func _exit_tree() -> void:
	_disconnect_curve()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_ensure_curve_connected()
		if _needs_regenerate:
			_needs_regenerate = false
			if auto_update_on_curve_change and is_inside_tree():
				generate()
		return

	if disable_near_camera_occluders and generate_occluders:
		_near_occluder_check_timer += delta
		if _near_occluder_check_timer >= 0.05:
			_near_occluder_check_timer = 0.0
			_update_near_occluders()

func _make_curve_unique() -> void:
	if curve:
		_disconnect_curve()
		curve = curve.duplicate()
		_ensure_curve_connected()
		print("BuildingPathPCG: Made curve unique for ", name)
		if auto_update_on_curve_change and is_inside_tree():
			generate()

func _ensure_curve_connected() -> void:
	if not Engine.is_editor_hint():
		return
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
	if not Engine.is_editor_hint():
		return
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

## Calculates exact local collision and spatial bounds for a building scene
func _get_collision_bounds(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {
			"min_x": -2.4, "max_x": 2.4, "width": 4.8, "is_wide": false,
			"min_y": 0.0, "max_y": 12.4, "height": 12.4,
			"min_z": -3.5, "max_z": 2.97, "depth": 6.47
		}
	
	var scene_path: String = scene.resource_path
	if _collision_bounds_cache.has(scene_path):
		return _collision_bounds_cache[scene_path]

	var file_name: String = scene_path.get_file().get_basename().to_lower()
	var name_says_wide: bool = file_name.contains("wide") or file_name.contains("conner") or file_name.contains("corner")

	var inst: Node3D = scene.instantiate() as Node3D
	if not inst:
		var w: float = 9.6 if name_says_wide else 4.8
		return {
			"min_x": -w * 0.5, "max_x": w * 0.5, "width": w, "is_wide": name_says_wide,
			"min_y": 0.0, "max_y": 12.4, "height": 12.4,
			"min_z": -9.9 if name_says_wide else -3.5, "max_z": 2.97, "depth": 12.87 if name_says_wide else 6.47
		}

	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

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
			for c in [
				Vector3(-s.x, -s.y, -s.z), Vector3(s.x, -s.y, -s.z),
				Vector3(-s.x, s.y, -s.z), Vector3(s.x, s.y, -s.z),
				Vector3(-s.x, -s.y, s.z), Vector3(s.x, -s.y, s.z),
				Vector3(-s.x, s.y, s.z), Vector3(s.x, s.y, s.z)
			]:
				var pt: Vector3 = xform * (c * 0.5)
				min_x = minf(min_x, pt.x)
				max_x = maxf(max_x, pt.x)
				min_y = minf(min_y, pt.y)
				max_y = maxf(max_y, pt.y)
				min_z = minf(min_z, pt.z)
				max_z = maxf(max_z, pt.z)
		elif shape is ConvexPolygonShape3D:
			for pt in (shape as ConvexPolygonShape3D).points:
				var gpt: Vector3 = xform * pt
				min_x = minf(min_x, gpt.x)
				max_x = maxf(max_x, gpt.x)
				min_y = minf(min_y, gpt.y)
				max_y = maxf(max_y, gpt.y)
				min_z = minf(min_z, gpt.z)
				max_z = maxf(max_z, gpt.z)
		elif shape is ConcavePolygonShape3D:
			for pt in (shape as ConcavePolygonShape3D).get_faces():
				var gpt: Vector3 = xform * pt
				min_x = minf(min_x, gpt.x)
				max_x = maxf(max_x, gpt.x)
				min_y = minf(min_y, gpt.y)
				max_y = maxf(max_y, gpt.y)
				min_z = minf(min_z, gpt.z)
				max_z = maxf(max_z, gpt.z)

	# If collision shapes don't provide valid Y or Z bounds, check MeshInstance3Ds as fallback
	if is_inf(min_y) or is_inf(max_y) or is_inf(min_z) or is_inf(max_z):
		var meshes: Array[Node] = inst.find_children("*", "MeshInstance3D", true, false)
		for mi in meshes:
			if not (mi is MeshInstance3D) or mi.mesh == null:
				continue
			var aabb: AABB = mi.mesh.get_aabb()
			var xform: Transform3D = mi.transform
			var p: Node = mi.get_parent()
			while p and p != inst:
				if p is Node3D:
					xform = (p as Node3D).transform * xform
				p = p.get_parent()
			for i in range(8):
				var corner: Vector3 = aabb.position + Vector3(
					aabb.size.x if (i & 1) else 0.0,
					aabb.size.y if (i & 2) else 0.0,
					aabb.size.z if (i & 4) else 0.0
				)
				var pt: Vector3 = xform * corner
				min_x = minf(min_x, pt.x)
				max_x = maxf(max_x, pt.x)
				min_y = minf(min_y, pt.y)
				max_y = maxf(max_y, pt.y)
				min_z = minf(min_z, pt.z)
				max_z = maxf(max_z, pt.z)

	inst.free()

	if is_inf(min_x) or is_inf(max_x) or min_x >= max_x:
		var fallback_w: float = 9.6 if name_says_wide else 4.8
		min_x = -fallback_w * 0.5
		max_x = fallback_w * 0.5

	var is_3_storey: bool = file_name.contains("3_storey")
	if is_inf(min_y) or is_inf(max_y) or min_y >= max_y:
		min_y = 0.0
		max_y = 9.3 if is_3_storey else 12.4

	if is_inf(min_z) or is_inf(max_z) or min_z >= max_z:
		min_z = -9.9 if name_says_wide else -3.5
		max_z = 2.97

	var width: float = max_x - min_x
	var is_wide: bool = name_says_wide or width > 6.0
	var res: Dictionary = {
		"min_x": min_x,
		"max_x": max_x,
		"width": width,
		"is_wide": is_wide,
		"min_y": min_y,
		"max_y": max_y,
		"height": max_y - min_y,
		"min_z": min_z,
		"max_z": max_z,
		"depth": max_z - min_z
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
		if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			container.owner = get_tree().edited_scene_root
	return container

func _has_generated_buildings() -> bool:
	if not is_inside_tree() or not is_node_ready():
		return false
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
	if not is_inside_tree() or not is_node_ready():
		return
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

	var placements: Array[Dictionary] = []
	var placed_count: int = 0

	# 1. Start corner building
	if use_corner_at_start and start_corner_scene_active:
		if cursor + start_w <= max_dist:
			var place_d: float = _calculate_placement_distance(cursor, start_bounds)
			placements.append({
				"scene": start_corner_scene_active,
				"distance": place_d,
				"prefix": "StartCorner",
				"index": placed_count
			})
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
		placements.append({
			"scene": scene_to_place,
			"distance": place_d,
			"prefix": "Building",
			"index": placed_count
		})
		cursor += b_width + building_gap
		placed_count += b_slots # Wide counts as 2, standard counts as 1

	# 3. End corner building (Rule 1)
	if use_corner_at_end and end_corner_scene_active:
		if (max_buildings == 0) or (placed_count + 2 <= max_buildings):
			var place_d: float = _calculate_placement_distance(cursor, end_bounds)
			placements.append({
				"scene": end_corner_scene_active,
				"distance": place_d,
				"prefix": "EndCorner",
				"index": placed_count
			})

	# 4. Spawn based on effective render mode
	var eff_mode: RenderMode = get_effective_render_mode()
	if eff_mode == RenderMode.BATCH_WHOLE_PATH:
		_generate_whole_path_batch(container, placements, rng)
	else:
		for item in placements:
			_spawn_building_auto(container, item["scene"], item["distance"], rng, item["prefix"])

		# MultiMesh batching optimization (draw-call reduction)
		if eff_mode == RenderMode.MULTIMESH:
			_apply_multimesh_batching(container)

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

## Clears cached building batch templates (shared across paths)
func _clear_batch_cache() -> void:
	for key in _batch_cache:
		var tmpl: BatchTemplate = _batch_cache[key]
		if tmpl and tmpl.front_gates:
			for entry in tmpl.front_gates:
				if entry and entry.has("node") and is_instance_valid(entry["node"]):
					(entry["node"] as Node3D).queue_free()
	_batch_cache.clear()
	print("BuildingPathPCG: Batch template cache cleared.")

## Gets or generates an optimized single-mesh template for a given building scene
func _get_or_build_template(scene: PackedScene) -> BatchTemplate:
	if scene == null:
		return null
	
	var path: String = scene.resource_path
	var cache_key: String = "%s_pfg_%s" % [path, str(batch_preserve_front_gate)]
	if _batch_cache.has(cache_key):
		return _batch_cache[cache_key]
	
	var inst: Node3D = scene.instantiate() as Node3D
	if not inst:
		return null
	
	var template: BatchTemplate = BatchTemplate.new()
	
	# 1. Identify and extract front gates if preserving them
	var front_gate_roots: Array[Node] = []
	if batch_preserve_front_gate:
		var all_nodes: Array[Node] = inst.find_children("*", "", true, false)
		for node in all_nodes:
			if PCG_BUILDING_INSTANCE_SCRIPT.is_front_gate(node):
				var is_sub_gate: bool = false
				for fg in front_gate_roots:
					if fg.is_ancestor_of(node):
						is_sub_gate = true
						break
				if not is_sub_gate:
					front_gate_roots.append(node)
		
		for fg_root in front_gate_roots:
			var gate_xform: Transform3D = (fg_root as Node3D).transform
			var p: Node = fg_root.get_parent()
			while p and p != inst:
				if p is Node3D:
					gate_xform = (p as Node3D).transform * gate_xform
				p = p.get_parent()
			
			var copy: Node3D = fg_root.duplicate() as Node3D
			template.front_gates.append({
				"node": copy,
				"transform": gate_xform
			})
	
	# 2. Gather visible meshes (excluding preserved front gates; back gates are baked)
	var material_buckets: Dictionary = {}
	var mesh_nodes: Array[Node] = inst.find_children("*", "MeshInstance3D", true, false)
	
	for m_node in mesh_nodes:
		var mi: MeshInstance3D = m_node as MeshInstance3D
		if not mi or mi.mesh == null:
			continue
		
		if not _is_visible_in_hierarchy(mi, inst):
			continue
		
		var is_front_gate_mesh: bool = false
		for fg in front_gate_roots:
			if fg == mi or fg.is_ancestor_of(mi):
				is_front_gate_mesh = true
				break
		if is_front_gate_mesh:
			continue
		
		# Relative transform to inst
		var rel_xform: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p and p != inst:
			if p is Node3D:
				rel_xform = (p as Node3D).transform * rel_xform
			p = p.get_parent()
		
		var basis: Basis = rel_xform.basis
		var is_flipped: bool = basis.determinant() < 0.0
		# Correct normal matrix: inverse-transpose of basis (prevents normal distortion from non-uniform scale)
		var normal_mat: Basis = basis.inverse().transposed()
		
		var m: Mesh = mi.mesh
		var surf_count: int = m.get_surface_count()
		for s in range(surf_count):
			var mat: Material = mi.get_active_material(s)
			var mat_key: Variant = mat if mat != null else "default_mat"
			if not material_buckets.has(mat_key):
				material_buckets[mat_key] = {
					"material": mat,
					"vertices": PackedVector3Array(),
					"normals": PackedVector3Array(),
					"tangents": PackedFloat32Array(),
					"uvs": PackedVector2Array(),
					"uv2s": PackedVector2Array(),
					"colors": PackedColorArray(),
					"indices": PackedInt32Array()
				}
			
			var bucket: Dictionary = material_buckets[mat_key]
			var arrays: Array = m.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			
			# Vertices
			var in_verts = arrays[Mesh.ARRAY_VERTEX]
			if in_verts == null or not (in_verts is PackedVector3Array):
				continue
			var vert_count: int = in_verts.size()
			if vert_count == 0:
				continue
			
			var vertex_offset: int = bucket["vertices"].size()
			var out_v: PackedVector3Array = bucket["vertices"]
			for v in in_verts:
				out_v.append(rel_xform * v)
			
			# Normals
			var in_normals = arrays[Mesh.ARRAY_NORMAL]
			if in_normals != null and (in_normals is PackedVector3Array) and in_normals.size() == vert_count:
				var out_n: PackedVector3Array = bucket["normals"]
				for n in in_normals:
					out_n.append((normal_mat * n).normalized())
			
			# Tangents
			var in_tangents = arrays[Mesh.ARRAY_TANGENT]
			if in_tangents != null and (in_tangents is PackedFloat32Array) and in_tangents.size() == vert_count * 4:
				var out_t: PackedFloat32Array = bucket["tangents"]
				for i in range(vert_count):
					var idx: int = i * 4
					var t: Vector3 = Vector3(in_tangents[idx], in_tangents[idx + 1], in_tangents[idx + 2])
					var w: float = in_tangents[idx + 3]
					var trans_t: Vector3 = (normal_mat * t).normalized()
					if is_flipped:
						w = -w
					out_t.append(trans_t.x)
					out_t.append(trans_t.y)
					out_t.append(trans_t.z)
					out_t.append(w)
			
			# UVs
			var in_uvs = arrays[Mesh.ARRAY_TEX_UV]
			if in_uvs != null and (in_uvs is PackedVector2Array) and in_uvs.size() == vert_count:
				bucket["uvs"].append_array(in_uvs)
			
			# UV2s
			var in_uv2s = arrays[Mesh.ARRAY_TEX_UV2]
			if in_uv2s != null and (in_uv2s is PackedVector2Array) and in_uv2s.size() == vert_count:
				bucket["uv2s"].append_array(in_uv2s)
			
			# Colors
			var in_colors = arrays[Mesh.ARRAY_COLOR]
			if in_colors != null and (in_colors is PackedColorArray) and in_colors.size() == vert_count:
				bucket["colors"].append_array(in_colors)
			
			# Indices (handles winding flip for negative determinant)
			var in_indices = arrays[Mesh.ARRAY_INDEX]
			var out_idx: PackedInt32Array = bucket["indices"]
			if in_indices != null and (in_indices is PackedInt32Array) and in_indices.size() > 0:
				if is_flipped:
					for i in range(0, in_indices.size(), 3):
						out_idx.append(in_indices[i] + vertex_offset)
						out_idx.append(in_indices[i + 2] + vertex_offset)
						out_idx.append(in_indices[i + 1] + vertex_offset)
				else:
					for idx in in_indices:
						out_idx.append(idx + vertex_offset)
			else:
				if is_flipped:
					for i in range(0, vert_count, 3):
						out_idx.append(vertex_offset + i)
						out_idx.append(vertex_offset + i + 2)
						out_idx.append(vertex_offset + i + 1)
				else:
					for i in range(vert_count):
						out_idx.append(vertex_offset + i)
	
	# 3. Create combined ArrayMesh
	var combined_mesh: ArrayMesh = ArrayMesh.new()
	for mat_key in material_buckets:
		var bucket: Dictionary = material_buckets[mat_key]
		var b_verts: PackedVector3Array = bucket["vertices"]
		if b_verts.is_empty():
			continue
		
		var surf_arrays: Array = []
		surf_arrays.resize(Mesh.ARRAY_MAX)
		surf_arrays[Mesh.ARRAY_VERTEX] = b_verts
		if not bucket["normals"].is_empty():
			surf_arrays[Mesh.ARRAY_NORMAL] = bucket["normals"]
		if not bucket["tangents"].is_empty():
			surf_arrays[Mesh.ARRAY_TANGENT] = bucket["tangents"]
		if not bucket["uvs"].is_empty():
			surf_arrays[Mesh.ARRAY_TEX_UV] = bucket["uvs"]
		if not bucket["uv2s"].is_empty():
			surf_arrays[Mesh.ARRAY_TEX_UV2] = bucket["uv2s"]
		if not bucket["colors"].is_empty():
			surf_arrays[Mesh.ARRAY_COLOR] = bucket["colors"]
		if not bucket["indices"].is_empty():
			surf_arrays[Mesh.ARRAY_INDEX] = bucket["indices"]
		
		var s_idx: int = combined_mesh.get_surface_count()
		combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf_arrays)
		if bucket["material"] != null:
			combined_mesh.surface_set_material(s_idx, bucket["material"])
	
	template.mesh = combined_mesh
	
	# 4. Generate Trimesh Shape
	if combined_mesh.get_surface_count() > 0:
		template.shape = combined_mesh.create_trimesh_shape()
	
	inst.free()
	
	_batch_cache[cache_key] = template
	print("BuildingPathPCG [Batch]: Built template for %s (%d surfaces, %d front gates)" % [
		path.get_file(), combined_mesh.get_surface_count(), template.front_gates.size()
	])
	return template

## Spawns building using appropriate mode
func _spawn_building_auto(container: Node3D, scene: PackedScene, d: float, rng: RandomNumberGenerator, prefix: String) -> Node3D:
	var eff_mode: RenderMode = get_effective_render_mode()
	if eff_mode == RenderMode.BATCH_COMBINED_MESH:
		return _spawn_batched_building(container, scene, d, rng, prefix)
	return _spawn_building(container, scene, d, rng, prefix)

## Spawns an ultra-lightweight batched building (1 combined mesh + 1 trimesh collision + optional front gate)
func _spawn_batched_building(container: Node3D, scene: PackedScene, d: float, rng: RandomNumberGenerator, prefix: String) -> Node3D:
	var template: BatchTemplate = _get_or_build_template(scene)
	if not template or not template.mesh:
		return null
	
	var building_node: Node3D = Node3D.new()
	var count: int = container.get_child_count()
	building_node.name = "%s_%02d_%s" % [prefix, count, scene.resource_path.get_file().get_basename()]
	
	var t: Transform3D = _compute_transform_at_distance(d)
	building_node.transform = t
	
	container.add_child(building_node)
	if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		building_node.owner = get_tree().edited_scene_root
	
	# Attach PCGBuildingInstance component for gate control
	building_node.set_script(PCG_BUILDING_INSTANCE_SCRIPT)
	var building_ctrl: PCGBuildingInstance = building_node as PCGBuildingInstance
	
	# 1. Combined visual MeshInstance3D
	var combined_mi: MeshInstance3D = MeshInstance3D.new()
	combined_mi.name = "CombinedMesh"
	combined_mi.mesh = template.mesh
	combined_mi.extra_cull_margin = extra_cull_margin
	if enable_distance_fade:
		combined_mi.visibility_range_end = fade_max_distance
		combined_mi.visibility_range_end_margin = fade_transition_margin
		combined_mi.visibility_range_fade_mode = fade_mode
	building_node.add_child(combined_mi)
	if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		combined_mi.owner = get_tree().edited_scene_root
	
	# 2. StaticBody3D with Trimesh Collision
	if template.shape:
		var sb: StaticBody3D = StaticBody3D.new()
		sb.name = "StaticBody3D"
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.name = "CombinedCollisionShape"
		cs.shape = template.shape
		sb.add_child(cs)
		building_node.add_child(sb)
		if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			sb.owner = get_tree().edited_scene_root
			cs.owner = get_tree().edited_scene_root
	
	# 3. Preserved Front Gate(s)
	if batch_preserve_front_gate and not template.front_gates.is_empty():
		for entry in template.front_gates:
			var gate_orig: Node3D = entry["node"] as Node3D
			if is_instance_valid(gate_orig):
				var gate_copy: Node3D = gate_orig.duplicate() as Node3D
				building_node.add_child(gate_copy)
				gate_copy.transform = entry["transform"]
				if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
					_safe_set_owner_recursive(gate_copy, get_tree().edited_scene_root)
	
	# Apply distance dither fade & extra cull margin across all visual meshes (CombinedMesh + Front Gates)
	_apply_distance_fade_to_building(building_node)
	
	# 4. Apply gate open/closed settings
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
		building_ctrl._update_gates()
	
	# 5. Occlusion Culling (QuadOccluders)
	if generate_occluders:
		_generate_building_occluders(building_node, scene, prefix)
	
	return building_node

## Generates the entire path as 1 single combined mesh + 1 trimesh collision (optimal for editor responsiveness)
func _generate_whole_path_batch(container: Node3D, placements: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	if placements.is_empty():
		return

	var path_material_buckets: Dictionary = {}
	var front_gates_container: Node3D = null
	if batch_preserve_front_gate:
		front_gates_container = Node3D.new()
		front_gates_container.name = "FrontGates"
		container.add_child(front_gates_container)
		if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			front_gates_container.owner = get_tree().edited_scene_root

	var occluders_container: Node3D = null
	if generate_occluders:
		occluders_container = Node3D.new()
		occluders_container.name = "Occluders"
		container.add_child(occluders_container)
		if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			occluders_container.owner = get_tree().edited_scene_root

	for item in placements:
		var scene: PackedScene = item["scene"]
		var d: float = item["distance"]
		var idx: int = item["index"]
		var prefix: String = item["prefix"]
		var T: Transform3D = _compute_transform_at_distance(d)

		var template: BatchTemplate = _get_or_build_template(scene)
		if not template or not template.mesh:
			continue

		var basis: Basis = T.basis
		var is_flipped: bool = basis.determinant() < 0.0
		var normal_mat: Basis = basis.inverse().transposed()

		# 1. Accumulate pre-merged variant surfaces into path buckets
		var m: ArrayMesh = template.mesh
		for s in range(m.get_surface_count()):
			var mat: Material = m.surface_get_material(s)
			var mat_key: Variant = mat if mat != null else "default_mat"
			if not path_material_buckets.has(mat_key):
				path_material_buckets[mat_key] = {
					"material": mat,
					"vertices": PackedVector3Array(),
					"normals": PackedVector3Array(),
					"tangents": PackedFloat32Array(),
					"uvs": PackedVector2Array(),
					"uv2s": PackedVector2Array(),
					"colors": PackedColorArray(),
					"indices": PackedInt32Array()
				}

			var bucket: Dictionary = path_material_buckets[mat_key]
			var arrays: Array = m.surface_get_arrays(s)
			if arrays.is_empty():
				continue

			var in_verts = arrays[Mesh.ARRAY_VERTEX]
			if in_verts == null or not (in_verts is PackedVector3Array):
				continue
			var vert_count: int = in_verts.size()
			if vert_count == 0:
				continue

			var vertex_offset: int = bucket["vertices"].size()
			var out_v: PackedVector3Array = bucket["vertices"]
			for v in in_verts:
				out_v.append(T * v)

			var in_normals = arrays[Mesh.ARRAY_NORMAL]
			if in_normals != null and (in_normals is PackedVector3Array) and in_normals.size() == vert_count:
				var out_n: PackedVector3Array = bucket["normals"]
				for n in in_normals:
					out_n.append((normal_mat * n).normalized())

			var in_tangents = arrays[Mesh.ARRAY_TANGENT]
			if in_tangents != null and (in_tangents is PackedFloat32Array) and in_tangents.size() == vert_count * 4:
				var out_t: PackedFloat32Array = bucket["tangents"]
				for i in range(vert_count):
					var t_idx: int = i * 4
					var t_vec: Vector3 = Vector3(in_tangents[t_idx], in_tangents[t_idx + 1], in_tangents[t_idx + 2])
					var w: float = in_tangents[t_idx + 3]
					var trans_t: Vector3 = (normal_mat * t_vec).normalized()
					if is_flipped:
						w = -w
					out_t.append(trans_t.x)
					out_t.append(trans_t.y)
					out_t.append(trans_t.z)
					out_t.append(w)

			var in_uvs = arrays[Mesh.ARRAY_TEX_UV]
			if in_uvs != null and (in_uvs is PackedVector2Array) and in_uvs.size() == vert_count:
				bucket["uvs"].append_array(in_uvs)

			var in_uv2s = arrays[Mesh.ARRAY_TEX_UV2]
			if in_uv2s != null and (in_uv2s is PackedVector2Array) and in_uv2s.size() == vert_count:
				bucket["uv2s"].append_array(in_uv2s)

			var in_colors = arrays[Mesh.ARRAY_COLOR]
			if in_colors != null and (in_colors is PackedColorArray) and in_colors.size() == vert_count:
				bucket["colors"].append_array(in_colors)

			var in_indices = arrays[Mesh.ARRAY_INDEX]
			var out_idx: PackedInt32Array = bucket["indices"]
			if in_indices != null and (in_indices is PackedInt32Array) and in_indices.size() > 0:
				if is_flipped:
					for i in range(0, in_indices.size(), 3):
						out_idx.append(in_indices[i] + vertex_offset)
						out_idx.append(in_indices[i + 2] + vertex_offset)
						out_idx.append(in_indices[i + 1] + vertex_offset)
				else:
					for index_val in in_indices:
						out_idx.append(index_val + vertex_offset)
			else:
				if is_flipped:
					for i in range(0, vert_count, 3):
						out_idx.append(vertex_offset + i)
						out_idx.append(vertex_offset + i + 2)
						out_idx.append(vertex_offset + i + 1)
				else:
					for i in range(vert_count):
						out_idx.append(vertex_offset + i)

		# 2. Preserved Front Gate(s)
		if batch_preserve_front_gate and front_gates_container and not template.front_gates.is_empty():
			var gate_ctrl: Node3D = Node3D.new()
			gate_ctrl.name = "GateCtrl_%02d_%s" % [idx, scene.resource_path.get_file().get_basename()]
			gate_ctrl.transform = T
			gate_ctrl.set_script(PCG_BUILDING_INSTANCE_SCRIPT)
			front_gates_container.add_child(gate_ctrl)
			if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
				gate_ctrl.owner = get_tree().edited_scene_root

			for g_entry in template.front_gates:
				var gate_orig: Node3D = g_entry["node"] as Node3D
				if is_instance_valid(gate_orig):
					var gate_copy: Node3D = gate_orig.duplicate() as Node3D
					gate_ctrl.add_child(gate_copy)
					gate_copy.transform = g_entry["transform"]
					if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
						_safe_set_owner_recursive(gate_copy, get_tree().edited_scene_root)

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
			
			var ctrl_inst = gate_ctrl as PCGBuildingInstance
			if ctrl_inst:
				ctrl_inst.front_iron_gate_closed = is_closed
				ctrl_inst._update_gates()
			_apply_distance_fade_to_building(gate_ctrl)

		# 3. Procedural Occluders
		if generate_occluders and occluders_container:
			var dummy_bldg: Node3D = Node3D.new()
			dummy_bldg.transform = T
			_generate_building_occluders(dummy_bldg, scene, prefix)
			var occ_node: Node = dummy_bldg.get_node_or_null("Occluders")
			if occ_node:
				dummy_bldg.remove_child(occ_node)
				occluders_container.add_child(occ_node)
				occ_node.transform = T
				if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
					_safe_set_owner_recursive(occ_node, get_tree().edited_scene_root)
			dummy_bldg.free()

	# 4. Commit to 1 single CombinedPathMesh
	var combined_path_mesh: ArrayMesh = ArrayMesh.new()
	for mat_key in path_material_buckets:
		var bucket: Dictionary = path_material_buckets[mat_key]
		var b_verts: PackedVector3Array = bucket["vertices"]
		if b_verts.is_empty():
			continue

		var surf_arrays: Array = []
		surf_arrays.resize(Mesh.ARRAY_MAX)
		surf_arrays[Mesh.ARRAY_VERTEX] = b_verts
		if not bucket["normals"].is_empty():
			surf_arrays[Mesh.ARRAY_NORMAL] = bucket["normals"]
		if not bucket["tangents"].is_empty():
			surf_arrays[Mesh.ARRAY_TANGENT] = bucket["tangents"]
		if not bucket["uvs"].is_empty():
			surf_arrays[Mesh.ARRAY_TEX_UV] = bucket["uvs"]
		if not bucket["uv2s"].is_empty():
			surf_arrays[Mesh.ARRAY_TEX_UV2] = bucket["uv2s"]
		if not bucket["colors"].is_empty():
			surf_arrays[Mesh.ARRAY_COLOR] = bucket["colors"]
		if not bucket["indices"].is_empty():
			surf_arrays[Mesh.ARRAY_INDEX] = bucket["indices"]

		var s_idx: int = combined_path_mesh.get_surface_count()
		combined_path_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf_arrays)
		if bucket["material"] != null:
			combined_path_mesh.surface_set_material(s_idx, bucket["material"])

	var path_mi: MeshInstance3D = MeshInstance3D.new()
	path_mi.name = "CombinedPathMesh"
	path_mi.mesh = combined_path_mesh
	path_mi.extra_cull_margin = extra_cull_margin
	if enable_distance_fade:
		path_mi.visibility_range_end = fade_max_distance
		path_mi.visibility_range_end_margin = fade_transition_margin
		path_mi.visibility_range_fade_mode = fade_mode
	container.add_child(path_mi)
	if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		path_mi.owner = get_tree().edited_scene_root

	# 5. Generate 1 path-wide Trimesh collision
	if combined_path_mesh.get_surface_count() > 0:
		var trimesh_shape: ConcavePolygonShape3D = combined_path_mesh.create_trimesh_shape()
		var sb: StaticBody3D = StaticBody3D.new()
		sb.name = "StaticBody3D"
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.name = "CombinedPathCollision"
		cs.shape = trimesh_shape
		sb.add_child(cs)
		container.add_child(sb)
		if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			sb.owner = get_tree().edited_scene_root
			cs.owner = get_tree().edited_scene_root

	print("BuildingPathPCG [WholePath]: Merged %d buildings into 1 mesh (%d surfaces) for %s" % [
		placements.size(), combined_path_mesh.get_surface_count(), name
	])

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
	if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
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

	# Procedural Occlusion Culling (lightweight QuadOccluder3D walls)
	if generate_occluders:
		_generate_building_occluders(instance, scene, prefix)

	# Triple-AAA GPU screen-space distance dither fade
	_apply_distance_fade_to_building(instance)

	return instance

## Generates lightweight 2-triangle QuadOccluder3D walls for a building instance
func _generate_building_occluders(instance: Node3D, scene: PackedScene, prefix: String) -> void:
	var b_info: Dictionary = _get_collision_bounds(scene)
	var min_x: float = b_info.get("min_x", -2.4)
	var max_x: float = b_info.get("max_x", 2.4)
	var width: float = b_info.get("width", 4.8)
	var min_y: float = b_info.get("min_y", 0.0)
	var max_y: float = b_info.get("max_y", 12.4)
	var height: float = b_info.get("height", 12.4)
	var min_z: float = b_info.get("min_z", -3.5)
	var max_z: float = b_info.get("max_z", 2.97)

	var occ_group: Node3D = Node3D.new()
	occ_group.name = "Occluders"
	instance.add_child(occ_group)

	var scene_name: String = scene.resource_path.get_file().get_basename().to_lower()
	var is_left_corner: bool = scene_name.contains("conner_building_left") or scene_name.contains("corner_building_left")
	var is_right_corner: bool = scene_name.contains("conner_building_right") or scene_name.contains("corner_building_right")

	# 1. Back Wall Occluder (culls background city / buildings behind the street)
	if occlude_back_wall:
		var back_w: float = maxf((width * occluder_size_scale) - (occluder_side_inset * 2.0), 0.1)
		var back_h: float = maxf(height - (occluder_wall_inset * 2.0), 0.1)
		var back_pos: Vector3 = Vector3(
			(min_x + max_x) * 0.5,
			(min_y + max_y) * 0.5,
			min_z + occluder_back_inset
		)
		_create_quad_occluder(occ_group, "BackWallOccluder", Vector2(back_w, back_h), back_pos, 0.0)

	# 2. Side Party Wall Occluders (culls down-the-street geometry)
	if occlude_party_walls:
		var z_start: float = min_z + occluder_back_inset
		var z_end: float = max_z - occluder_front_inset
		var eff_depth: float = maxf((z_end - z_start) * occluder_size_scale, 0.5)
		var party_h: float = maxf(height - (occluder_wall_inset * 2.0), 0.1)
		var party_z: float = (z_start + z_end) * 0.5
		var party_y: float = (min_y + max_y) * 0.5

		# Left Wall: skip if left corner building (outer side faces open side street)
		if not is_left_corner:
			var left_pos: Vector3 = Vector3(min_x + occluder_side_inset, party_y, party_z)
			_create_quad_occluder(occ_group, "LeftPartyWallOccluder", Vector2(eff_depth, party_h), left_pos, 90.0)

		# Right Wall: skip if right corner building (outer side faces open side street)
		if not is_right_corner:
			var right_pos: Vector3 = Vector3(max_x - occluder_side_inset, party_y, party_z)
			_create_quad_occluder(occ_group, "RightPartyWallOccluder", Vector2(eff_depth, party_h), right_pos, 90.0)

## Helper to create and attach a QuadOccluder3D
func _create_quad_occluder(parent: Node3D, node_name: String, quad_size: Vector2, local_pos: Vector3, local_rot_y_deg: float) -> OccluderInstance3D:
	var occ_inst: OccluderInstance3D = OccluderInstance3D.new()
	occ_inst.name = node_name

	var quad: QuadOccluder3D = QuadOccluder3D.new()
	quad.size = quad_size
	occ_inst.occluder = quad

	occ_inst.position = local_pos
	if not is_zero_approx(local_rot_y_deg):
		occ_inst.rotation_degrees = Vector3(0.0, local_rot_y_deg, 0.0)

	parent.add_child(occ_inst)

	return occ_inst

## Dynamically deactivates occluders when camera or player is near or inside a building
func _update_near_occluders() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container or container.get_child_count() == 0:
		return

	# 1. Resolve active camera position
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	var cam_pos: Vector3 = cam.global_position if cam else Vector3(INF, INF, INF)
	var has_cam: bool = cam != null

	# 2. Resolve active player position if available
	var player_pos: Vector3 = Vector3(INF, INF, INF)
	var has_player: bool = false
	if get_tree():
		var player_node: Node = get_tree().get_first_node_in_group("player")
		if player_node and player_node is Node3D:
			player_pos = (player_node as Node3D).global_position
			has_player = true

	if not has_cam and not has_player:
		return

	var threshold_sq: float = near_occluder_disable_distance * near_occluder_disable_distance

	for child in container.get_children():
		if child.name == "MultiMeshes" or not (child is Node3D):
			continue
		
		var b_node: Node3D = child as Node3D
		var occ_group: Node = child if child.name == "Occluders" else b_node.get_node_or_null("Occluders")
		if not occ_group:
			continue

		for occ in occ_group.get_children():
			if not (occ is OccluderInstance3D):
				continue
			var occ_inst: OccluderInstance3D = occ as OccluderInstance3D
			var occ_pos: Vector3 = occ_inst.global_position

			var dist_sq: float = INF
			if has_cam:
				dist_sq = minf(dist_sq, cam_pos.distance_squared_to(occ_pos))
			if has_player:
				dist_sq = minf(dist_sq, player_pos.distance_squared_to(occ_pos))

			var should_be_active: bool = dist_sq >= threshold_sq
			if occ_inst.visible != should_be_active:
				occ_inst.visible = should_be_active

## Restores all occluders to active when proximity deactivation is turned off
func _restore_all_occluders() -> void:
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container:
		return
	for child in container.get_children():
		if child.name == "MultiMeshes" or not (child is Node3D):
			continue
		var occ_group: Node = child if child.name == "Occluders" else (child as Node3D).get_node_or_null("Occluders")
		if occ_group:
			for occ in occ_group.get_children():
				if occ is OccluderInstance3D:
					(occ as OccluderInstance3D).visible = true

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
	if not is_inside_tree() or not is_node_ready():
		return
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container:
		return
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_number + 999
	
	var controllers: Array[Node] = []
	for child in container.get_children():
		if child.name == "MultiMeshes":
			continue
		if child.name == "FrontGates":
			for fg in child.get_children():
				if fg.get_script() == PCG_BUILDING_INSTANCE_SCRIPT or fg is PCGBuildingInstance:
					controllers.append(fg)
				elif fg.has_node("PCGBuildingInstance"):
					controllers.append(fg.get_node("PCGBuildingInstance"))
			continue
		
		if child.get_script() == PCG_BUILDING_INSTANCE_SCRIPT or child is PCGBuildingInstance:
			controllers.append(child)
		elif child.has_node("PCGBuildingInstance"):
			controllers.append(child.get_node("PCGBuildingInstance"))
	
	for ctrl in controllers:
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
		
		var b_ctrl = ctrl as PCGBuildingInstance
		if b_ctrl:
			b_ctrl.front_iron_gate_closed = is_closed
			if not toggle_front_gates_only:
				b_ctrl.back_iron_gate_closed = is_closed

## Applies distance dither fade settings to all MeshInstance3Ds within a building
func _apply_distance_fade_to_building(node: Node3D) -> void:
	var dist: float = fade_max_distance if enable_distance_fade else 0.0
	var margin: float = fade_transition_margin if enable_distance_fade else 0.0
	var mode: GeometryInstance3D.VisibilityRangeFadeMode = fade_mode if enable_distance_fade else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	if node is MeshInstance3D:
		var self_mi: MeshInstance3D = node as MeshInstance3D
		self_mi.visibility_range_end = dist
		self_mi.visibility_range_end_margin = margin
		self_mi.visibility_range_fade_mode = mode
		self_mi.extra_cull_margin = extra_cull_margin

	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi:
			mi.visibility_range_end = dist
			mi.visibility_range_end_margin = margin
			mi.visibility_range_fade_mode = mode
			mi.extra_cull_margin = extra_cull_margin

## Re-applies extra cull margin to all currently spawned buildings and MultiMeshes
func _apply_cull_margin_to_existing() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container:
		return

	for child in container.get_children():
		if child.name == "MultiMeshes":
			for mm in child.get_children():
				if mm is MultiMeshInstance3D:
					(mm as MultiMeshInstance3D).extra_cull_margin = extra_cull_margin
			continue

		if child is Node3D:
			if child is MeshInstance3D:
				(child as MeshInstance3D).extra_cull_margin = extra_cull_margin
			var meshes: Array[Node] = (child as Node3D).find_children("*", "MeshInstance3D", true, false)
			for m in meshes:
				var mi: MeshInstance3D = m as MeshInstance3D
				if mi:
					mi.extra_cull_margin = extra_cull_margin

## Re-applies distance dither fade settings to all currently spawned buildings and MultiMeshes
func _apply_fade_settings_to_existing() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container:
		return

	var dist: float = fade_max_distance if enable_distance_fade else 0.0
	var margin: float = fade_transition_margin if enable_distance_fade else 0.0
	var mode: GeometryInstance3D.VisibilityRangeFadeMode = fade_mode if enable_distance_fade else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	for child in container.get_children():
		if child.name == "MultiMeshes":
			for mm in child.get_children():
				if mm is MultiMeshInstance3D:
					var mmi: MultiMeshInstance3D = mm as MultiMeshInstance3D
					mmi.visibility_range_end = dist
					mmi.visibility_range_end_margin = margin
					mmi.visibility_range_fade_mode = mode
			continue

		if child is Node3D:
			_apply_distance_fade_to_building(child as Node3D)

## Bakes the generated buildings into independent scene nodes and removes the PCG connection
func bake() -> void:
	var container: Node3D = get_node_or_null("GeneratedBuildings") as Node3D
	if not container or container.get_child_count() == 0:
		push_warning("BuildingPathPCG: No buildings to bake.")
		return
	
	container.name = "Baked_Buildings_" + str(randi() % 1000)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		var root = get_tree().edited_scene_root
		_safe_set_owner_recursive(container, root)
	print("BuildingPathPCG: Successfully baked buildings to node: ", container.name)

## Safely sets owner on node and its children, respecting nested instanced sub-scenes
func _safe_set_owner_recursive(node: Node, root: Node) -> void:
	if node != root and node.owner == null:
		node.owner = root
	for child in node.get_children():
		if not child.scene_file_path.is_empty():
			if child.owner == null:
				child.owner = root
		else:
			_safe_set_owner_recursive(child, root)

## Batches non-gate MeshInstance3Ds across all generated buildings into MultiMeshInstance3Ds.
## Physics collisions and interactive IronGate doors remain fully intact and operational!
func _apply_multimesh_batching(container: Node3D) -> void:
	var mm_container: Node3D = Node3D.new()
	mm_container.name = "MultiMeshes"
	container.add_child(mm_container)
	if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		mm_container.owner = get_tree().edited_scene_root

	# Dictionary of batches:
	# key_id -> { "mesh": Mesh, "material": Material, "transforms": Array[Transform3D] }
	var batches: Dictionary = {}
	var total_batched: int = 0

	for child in container.get_children():
		if child == mm_container or not (child is Node3D):
			continue
		var building_node: Node3D = child as Node3D
		
		var mesh_instances: Array[Node] = building_node.find_children("*", "MeshInstance3D", true, false)
		for node in mesh_instances:
			var mi: MeshInstance3D = node as MeshInstance3D
			if not mi or mi.mesh == null:
				continue
			
			# Skip hidden meshes or meshes under hidden parent branches (preserves deliberate scene editor hiding)
			if not _is_visible_in_hierarchy(mi, building_node):
				continue

			# Preserve iron gate door meshes as standalone MeshInstance3D nodes for visibility/open/close controls
			if _is_part_of_gate(mi, building_node):
				continue
			
			var mesh_res: Mesh = mi.mesh
			var mat: Material = mi.get_active_material(0)
			
			var m_id: String = mesh_res.resource_path if not mesh_res.resource_path.is_empty() else (mesh_res.resource_name if not mesh_res.resource_name.is_empty() else str(mesh_res.get_instance_id()))
			var mat_id: String = mat.resource_path if (mat and not mat.resource_path.is_empty()) else str(mat.get_instance_id() if mat != null else 0)
			var key: String = "%s_%s" % [m_id, mat_id]
			if not batches.has(key):
				batches[key] = {
					"mesh": mesh_res,
					"material": mat,
					"transforms": []
				}
			
			# Calculate exact transform relative to container
			var rel_xform: Transform3D = mi.transform
			var p: Node = mi.get_parent()
			while p and p != building_node:
				if p is Node3D:
					rel_xform = (p as Node3D).transform * rel_xform
				p = p.get_parent()
			
			var final_xform: Transform3D = building_node.transform * rel_xform
			batches[key]["transforms"].append(final_xform)
			total_batched += 1

			# Remove visual mesh from the individual MeshInstance3D to prevent duplicate draw calls.
			# Its physics children (StaticBody3D / CollisionShape3D) remain completely intact!
			mi.mesh = null

	# Create a MultiMeshInstance3D for each unique (mesh, material) batch
	for key in batches:
		var entry: Dictionary = batches[key]
		var mesh_res: Mesh = entry["mesh"]
		var mat: Material = entry["material"]
		var xforms: Array = entry["transforms"]
		if xforms.is_empty():
			continue

		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		var m_name: String = mesh_res.resource_name if mesh_res.resource_name != "" else str(mesh_res.get_instance_id())
		mmi.name = "MMI_%s" % m_name

		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.use_custom_data = false
		mm.mesh = mesh_res
		mm.instance_count = xforms.size()

		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])

		mmi.multimesh = mm
		if mat != null:
			mmi.material_override = mat

		mmi.extra_cull_margin = extra_cull_margin

		if enable_distance_fade:
			mmi.visibility_range_end = fade_max_distance
			mmi.visibility_range_end_margin = fade_transition_margin
			mmi.visibility_range_fade_mode = fade_mode

		mm_container.add_child(mmi)
		if persist_to_scene and Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			mmi.owner = get_tree().edited_scene_root

	print("BuildingPathPCG [MultiMesh]: Batched %d mesh instances into %d MultiMeshInstance3D draw calls." % [total_batched, batches.size()])

## Checks whether a node or any of its ancestors within a building is an IronGate node
func _is_part_of_gate(node: Node, building_root: Node) -> bool:
	var curr: Node = node
	while curr and curr != building_root:
		if PCG_BUILDING_INSTANCE_SCRIPT.is_gate_node(curr):
			return true
		curr = curr.get_parent()
	return false

## Checks whether a node and all of its ancestors up to building_root are visible
func _is_visible_in_hierarchy(node: Node, building_root: Node) -> bool:
	var curr: Node = node
	while curr and curr != building_root:
		if curr is Node3D and not (curr as Node3D).visible:
			return false
		curr = curr.get_parent()
	if building_root is Node3D and not (building_root as Node3D).visible:
		return false
	return true
