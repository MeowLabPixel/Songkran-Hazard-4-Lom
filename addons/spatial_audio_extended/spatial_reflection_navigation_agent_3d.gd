@tool
@icon("images/spatial_reflection_navigation_agent_3d.svg")
extends Node3D
class_name SpatialReflectionNavigationAgent3D

## `SpatialReflectionNavigationAgent3D` is a 3D path-routing helper for
## corner-aware audio reflection. It computes a collision-avoiding path from
## this node's origin to the active camera, then drives a proxied
## `AudioStreamPlayer3D` along that route. This node is HIGHLY EXPERIMENTAL!
##
## Highlights:
## - Reachable-space graph building for tight corridors and room interiors.
## - Greedy A* path solve over a cached sparse graph.
## - Spring-arm style listener-distance protection for proxy motion.
## - Reflection-volume modulation hook into `SpatialAudioPlayer3D`.
## - Debug overlays for bounds, route, graph, and proxy position.
##
## Usage:
## - Place this node at a sound source origin.
## - Enable `move_audio_player` and parent a `SpatialAudioPlayer3D` under it
##   (or assign `audio_player_node`) to drive reflected proxy playback.
## - Leave `target_override` empty to use the active camera automatically.
## - Use Debug exports to validate graph coverage and final routed path.
##
## Performance notes:
## - Prefer `use_reachable_scan` for tight indoor spaces.
## - Tune `scan_max_cells`, `scan_max_cell_extent`, and `update_interval` first.
## - Keep debug drawing disabled in runtime builds.
##
## The node itself does not need to move; it can run as a stationary router.

## Emitted whenever a path is found or refreshed.
signal path_updated(path_world: PackedVector3Array, direct_path: bool)
## Emitted when pathing fails while direct line is blocked.
signal path_failed(origin_world: Vector3, target_world: Vector3)
## Emitted each frame after proxy position is updated.
signal audio_proxy_position_updated(proxy_world: Vector3)
## Emitted after graph rebuild completes. Argument is point count.
signal graph_rebuilt(point_count: int)

enum OriginMode {
	NODE_POSITION, ## Use the world position of the resolved node as the origin.
	NODE_WITH_LOCAL_OFFSET, ## Apply a local-space offset to the resolved node position.
	FIXED_WORLD_POSITION, ## Always use the same world position, unaffected by parent movement.
}

enum DistanceMode {
	EUCLIDEAN, ## Straight-line distance (fastest, best for general use).
	MANHATTAN, ## Axis-aligned distance (fast for grid-like layouts, less accurate in open 3D).
}

enum ScanNeighborMode {
	AXIS_6, ## 6-connected neighbors along cardinal axes (fastest, best for open areas).
	DIAGONAL_18, ## 18-connected neighbors including diagonals (moderate cost, better for mixed spaces).
	FULL_26, ## 26-connected neighbors including diagonals and vertical (highest cost, best for tight 3D spaces).
}

enum NavigationProfile {
	CUSTOM, ## Keep your manual values for all properties.
	OPEN_AREAS, ## Optimized for open spaces with few obstacles.
	HALLWAYS, ## Optimized for narrow corridors and tight spaces.
}

var _NAV_PROFILE_CUSTOM_ONLY_PROPERTIES := PackedStringArray([
	"skip_recompute_when_static",
	"recompute_origin_threshold",
	"recompute_target_threshold",
	"static_recompute_interval",
	"navigation_radius",
	"sample_point_count",
	"sample_seed",
	"max_connection_distance",
	"graph_neighbor_limit",
	"dynamic_connection_limit",
	"dynamic_candidate_multiplier",
	"clearance_radius",
	"edge_clearance_checks",
	"graph_recenter_distance",
	"use_reachable_scan",
	"scan_cell_size",
	"scan_neighbor_mode",
	"scan_max_cells",
	"scan_max_cell_extent",
	"scan_cell_inset",
	"heuristic_weight",
	"distance_mode",
	"use_unit_cost",
	"unit_cost",
	"reuse_last_path_when_valid",
	"reuse_origin_tolerance",
	"reuse_target_tolerance",
	"reuse_max_detour_ratio",
	"smooth_path_with_visibility",
	"collision_mask",
	"collide_with_areas",
	"collide_with_bodies",
	"ignore_listener_body",
	"excluded_collision_nodes",
])

@export_group("Navigation")
## High-level tuning preset for graph generation.
## `CUSTOM` keeps your manual values; `OPEN_AREAS` and `HALLWAYS` apply tuned defaults.
@export var navigation_profile: NavigationProfile = NavigationProfile.CUSTOM:
	set(value):
		navigation_profile = value
		_apply_navigation_profile_preset()
		notify_property_list_changed()
## Recompute interval for the path query.
@export_range(0.01, 2.0, 0.01, "suffix:s") var update_interval: float = 0.15
## Skip full path solve when origin and listener moved less than configured thresholds.
@export var skip_recompute_when_static: bool = true:
	set(value):
		skip_recompute_when_static = value
		notify_property_list_changed()
## Movement threshold for origin required to trigger a full recompute.
@export_range(0.0, 5.0, 0.01, "suffix:m") var recompute_origin_threshold: float = 0.05
## Movement threshold for listener required to trigger a full recompute.
@export_range(0.0, 5.0, 0.01, "suffix:m") var recompute_target_threshold: float = 0.08
## Forced full solve interval while static skipping is active (0 disables periodic full solves).
@export_range(0.0, 5.0, 0.01, "suffix:s") var static_recompute_interval: float = 0.75
## Spherical bounds radius used for airborne sample points around the graph anchor.
@export_range(0.5, 512.0, 0.1, "suffix:m") var navigation_radius: float = 18.0:
	set(value):
		navigation_radius = maxf(value, 0.5)
		_mark_graph_dirty()
## Number of random points generated inside the sphere.
@export_range(8, 512, 1) var sample_point_count: int = 96:
	set(value):
		sample_point_count = maxi(value, 8)
		_samples_dirty = true
		_mark_graph_dirty()
## Deterministic random seed for stable sample layout.
@export var sample_seed: int = 1337:
	set(value):
		sample_seed = value
		_samples_dirty = true
		_mark_graph_dirty()
## Maximum edge length allowed between graph waypoints.
@export_range(0.5, 128.0, 0.1, "suffix:m") var max_connection_distance: float = 8.0:
	set(value):
		max_connection_distance = maxf(value, 0.5)
		_mark_graph_dirty()
## Max connected neighbors per waypoint in the cached graph.
@export_range(2, 32, 1) var graph_neighbor_limit: int = 10:
	set(value):
		graph_neighbor_limit = maxi(value, 2)
		_mark_graph_dirty()
## Max visible graph links from dynamic start/goal to graph.
@export_range(1, 32, 1) var dynamic_connection_limit: int = 6
## Number of best dynamic-link candidates kept before visibility tests.
## Higher values are more robust but increase physics query cost.
@export_range(1, 12, 1) var dynamic_candidate_multiplier: int = 4
## Collision clearance radius around sampled points and edge checkpoints.
@export_range(0.01, 5.0, 0.01, "suffix:m") var clearance_radius: float = 0.35:
	set(value):
		clearance_radius = maxf(value, 0.01)
		_clearance_shape.radius = clearance_radius
		_mark_graph_dirty()
## Number of interior checkpoints used to validate each graph edge.
@export_range(0, 8, 1) var edge_clearance_checks: int = 1:
	set(value):
		edge_clearance_checks = maxi(value, 0)
		_mark_graph_dirty()
## Rebuild the cached graph when anchor moves more than this distance.
@export_range(0.1, 64.0, 0.1, "suffix:m") var graph_recenter_distance: float = 2.0
## Build graph using collision-reachable flood scan from origin (better for tight spaces).
@export var use_reachable_scan: bool = true:
	set(value):
		use_reachable_scan = value
		_mark_graph_dirty()
		notify_property_list_changed()
## Grid cell size for reachable scan.
@export_range(0.2, 8.0, 0.1, "suffix:m") var scan_cell_size: float = 1.0:
	set(value):
		scan_cell_size = maxf(value, 0.2)
		_mark_graph_dirty()
## Neighbor connectivity for reachable scan.
@export var scan_neighbor_mode: ScanNeighborMode = ScanNeighborMode.AXIS_6:
	set(value):
		scan_neighbor_mode = value
		_mark_graph_dirty()
## Hard cap on scanned cells for reachable graph build.
@export_range(64, 32768, 1) var scan_max_cells: int = 4096:
	set(value):
		scan_max_cells = maxi(value, 64)
		_mark_graph_dirty()
## Maximum absolute grid extent from the start cell (0 = unlimited).
## Useful to cap scan cost in dense or complex scenes.
@export_range(0, 512, 1) var scan_max_cell_extent: int = 0:
	set(value):
		scan_max_cell_extent = maxi(value, 0)
		_mark_graph_dirty()
## Extra margin from voxel center toward free space to reduce wall hugging.
@export_range(0.0, 0.45, 0.01) var scan_cell_inset: float = 0.08:
	set(value):
		scan_cell_inset = clampf(value, 0.0, 0.45)
		_mark_graph_dirty()
## Heuristic weight (w) used in Greedy A* estimated cost.
@export_range(0.1, 5.0, 0.05) var heuristic_weight: float = 1.0
## Distance function for movement and heuristic.
@export var distance_mode: DistanceMode = DistanceMode.EUCLIDEAN
## If true, every edge has the same movement cost.
@export var use_unit_cost: bool = false:
	set(value):
		use_unit_cost = value
		notify_property_list_changed()
## Unit cost used when use_unit_cost is true.
@export_range(0.01, 50.0, 0.01) var unit_cost: float = 1.0
## Reuse previous solved around-corner path until it becomes invalid.
@export var reuse_last_path_when_valid: bool = true:
	set(value):
		reuse_last_path_when_valid = value
		notify_property_list_changed()
## Maximum movement of the origin before cached path reuse is rejected.
@export_range(0.0, 16.0, 0.05, "suffix:m") var reuse_origin_tolerance: float = 0.60
## Maximum movement of the target before cached path reuse is rejected.
@export_range(0.0, 16.0, 0.05, "suffix:m") var reuse_target_tolerance: float = 0.90
## Reject cached path if too long compared to direct distance.
@export_range(1.0, 6.0, 0.05) var reuse_max_detour_ratio: float = 2.0
## If true, run visibility-based line-of-sight smoothing on solved paths.
@export var smooth_path_with_visibility: bool = true
## Physics layers considered as blockers.
@export_flags_3d_physics var collision_mask: int = 1
## If true, include Area3D nodes as blockers.
@export var collide_with_areas: bool = false
## If true, include PhysicsBody3D nodes as blockers.
@export var collide_with_bodies: bool = true
## Ignore the active camera's collision parent/body in path queries.
@export var ignore_listener_body: bool = true
## Extra nodes to exclude from collision checks (node + collision descendants).
@export var excluded_collision_nodes: Array[Node3D] = []:
	set(value):
		excluded_collision_nodes = value
		_exclusions_dirty = true

@export_group("Origin")
## Where the path starts from.
@export var origin_mode: OriginMode = OriginMode.NODE_WITH_LOCAL_OFFSET
## Origin node override when using NODE_* origin modes.
@export var origin_override: Node3D = null
## Local-space offset applied after resolving origin node.
@export var origin_local_offset: Vector3 = Vector3.ZERO
## Fixed world start position (unaffected by parent movement).
@export var fixed_world_origin: Vector3 = Vector3.ZERO
## Capture the current resolved node origin into fixed_world_origin on ready.
@export var capture_fixed_origin_on_ready: bool = false

@export_group("Target")
## Manual target override. If null, active camera is used.
@export var target_override: Node3D = null

@export_group("Audio Proxy")
## If enabled, this agent moves an audio player proxy along the computed path.
@export var move_audio_player: bool = false:
	set(value):
		move_audio_player = value
		notify_property_list_changed()
## Explicit audio player node to move.
@export var audio_player_node: Node3D = null:
	set(value):
		audio_player_node = value
		_resolve_audio_proxy_ref()
		update_configuration_warnings()
## If true and audio_player_node is empty, auto-find first AudioStreamPlayer3D child.
@export var auto_find_audio_player_child: bool = true:
	set(value):
		auto_find_audio_player_child = value
		_resolve_audio_proxy_ref()
		update_configuration_warnings()
		notify_property_list_changed()
## If true, only move to a waypoint when the direct line is blocked.
@export var proxy_only_when_blocked: bool = true
## Path index used for the proxy (1 = first waypoint after origin).
@export_range(1, 64, 1) var proxy_waypoint_index: int = 2
## Smooths proxy movement (0 = snap instantly).
@export_range(1.0, 60.0, 0.1) var audio_proxy_lerp_speed: float = 30
## Lerp speed while backing away from a too-close listener.
@export_range(0.0, 40.0, 0.1) var audio_proxy_backoff_lerp_speed: float = 4.0
## Vertical offset added to the proxy target position.
@export_range(-5.0, 5.0, 0.01, "suffix:m") var audio_proxy_height_offset: float = 0.0
## Return the moved audio node to origin when proxy movement is disabled.
@export var restore_audio_to_origin_when_disabled: bool = true
## While reflected, temporarily force inner_radius to 0 when proxy is outside source inner zone.
@export var proxy_force_inner_radius_outside_source_zone: bool = true
## Keep reflected proxy from getting too close to listener by backing up on the path.
@export var enable_proxy_listener_backoff: bool = true:
	set(value):
		enable_proxy_listener_backoff = value
		notify_property_list_changed()
## Enter backoff when listener is nearer than this to the reflected proxy.
@export_range(0.1, 20.0, 0.05, "suffix:m") var proxy_min_listener_distance: float = 1.6
## Exit backoff only when listener distance exceeds this threshold.
@export_range(0.1, 20.0, 0.05, "suffix:m") var proxy_backoff_release_distance: float = 2.2
## Distance from listener along the solved path where proxy retreats to.
@export_range(0.1, 50.0, 0.05, "suffix:m") var proxy_backoff_path_distance: float = 2.8
## Enables spring-arm style minimum distance control along the solved path.
@export var proxy_spring_arm_enabled: bool = true:
	set(value):
		proxy_spring_arm_enabled = value
		notify_property_list_changed()
## Minimum allowed listener distance for the reflected proxy.
@export_range(0.1, 20.0, 0.05, "suffix:m") var proxy_spring_min_distance: float = 1.5
## Extra retreat amount when listener breaches the minimum distance.
@export_range(0.0, 4.0, 0.05) var proxy_spring_push_strength: float = 1.0
## Spring response speed while pushing away from listener.
@export_range(0.1, 40.0, 0.1) var proxy_spring_push_speed: float = 10.0
## Spring response speed while relaxing back toward the base proxy target.
@export_range(0.1, 40.0, 0.1) var proxy_spring_return_speed: float = 6.0

@export_group("Reflection Audio")
## Apply additional reflection loudness loss based on proxy distance from source origin.
@export var apply_reflection_volume_loss: bool = true:
	set(value):
		apply_reflection_volume_loss = value
		notify_property_list_changed()
## Added loss per meter from origin to proxy.
@export_range(0.0, 6.0, 0.01, "suffix:dB/m") var reflection_loss_db_per_meter: float = 0.45
## Non-linear exponent for reflection loss distance.
@export_range(0.2, 3.0, 0.05) var reflection_loss_power: float = 1.0
## Max additional loss from reflection routing.
@export_range(0.0, 80.0, 0.1, "suffix:dB") var reflection_max_loss_db: float = 20.0
## Hold occlusion open briefly while proxy transitions to reflected position.
@export var proxy_occlusion_transition_smoothing: bool = true:
	set(value):
		proxy_occlusion_transition_smoothing = value
		notify_property_list_changed()
## Hold duration used when returning from reflected proxy back to direct mode.
@export_range(0.0, 1.0, 0.01, "suffix:s") var proxy_occlusion_hold_seconds: float = 0.18
## Extend hold while returning movement is still larger than this threshold.
@export_range(0.0, 10.0, 0.01, "suffix:m") var proxy_occlusion_hold_move_threshold: float = 0.25

@export_group("Debug")
## When false, full runtime behavior is disabled in editor.
## Selected-node preview for bounds/path still runs for inspection.
@export var preview_pathing_in_editor: bool = false:
	set(value):
		var was_enabled := preview_pathing_in_editor
		preview_pathing_in_editor = value
		if Engine.is_editor_hint() and was_enabled and not preview_pathing_in_editor:
			_reset_audio_proxy_to_origin()
		notify_property_list_changed()
## Draws the navigation sphere centered at the resolved origin.
@export var debug_draw_bounds: bool = false
## Draws the currently solved path polyline.
@export var debug_draw_path: bool = false:
	set(value):
		debug_draw_path = value
		notify_property_list_changed()
## Draws direct origin->listener line in blocked color when path is invalid.
@export var debug_draw_direct_line_when_blocked: bool = false
## Draws a cross marker for each cached graph waypoint.
@export var debug_draw_graph_points: bool = false
## Draws graph connectivity lines between waypoints.
@export var debug_draw_graph_edges: bool = false
## Draws a marker sphere where the proxy audio node currently sits.
@export var debug_draw_audio_proxy: bool = false:
	set(value):
		debug_draw_audio_proxy = value
		notify_property_list_changed()
## Color used for navigation bounds.
@export var debug_bounds_color: Color = Color(0.12, 0.65, 1.0, 0.65)
## Color used for solved path lines.
@export var debug_path_color: Color = Color(0.2, 1.0, 0.25, 0.95)
## Color used for blocked direct-path debug line.
@export var debug_blocked_color: Color = Color(1.0, 0.25, 0.2, 0.95)
## Color used for graph points and edges.
@export var debug_graph_color: Color = Color(1.0, 0.9, 0.2, 0.50)
## Color used for proxy marker sphere/cross.
@export var debug_audio_proxy_color: Color = Color(1.0, 0.25, 0.9, 0.95)
## Radius of the proxy debug sphere marker.
@export_range(0.02, 2.0, 0.01, "suffix:m") var debug_audio_proxy_radius: float = 0.20

var _time_accum: float = 0.0
var _time_since_last_full_recompute: float = 0.0
var _samples_dirty: bool = true
var _graph_dirty: bool = true
var _sample_offsets: Array[Vector3] = []
var _clearance_shape := SphereShape3D.new()

var _graph_anchor_world: Vector3 = Vector3.ZERO
var _graph_grid_origin: Vector3 = Vector3.ZERO
var _graph_points_world: Array[Vector3] = []
var _graph_edges: Array[PackedInt32Array] = []
var _graph_edge_count: int = 0
var _cached_internal_waypoints: PackedVector3Array = PackedVector3Array()
var _cached_origin_world: Vector3 = Vector3.ZERO
var _cached_target_world: Vector3 = Vector3.ZERO
var _cached_path_length: float = 0.0
var _current_path_length: float = 0.0

var _current_path_world: PackedVector3Array = PackedVector3Array()
var _has_valid_path: bool = false
var _is_direct_path: bool = false
var _last_origin_world: Vector3 = Vector3.ZERO
var _last_target_world: Vector3 = Vector3.ZERO
var _last_solve_origin_world: Vector3 = Vector3.ZERO
var _last_solve_target_world: Vector3 = Vector3.ZERO
var _has_last_solve_state: bool = false

var _debug_mesh: ImmediateMesh = null
var _debug_instance: MeshInstance3D = null
var _debug_was_drawing: bool = false

var _audio_proxy_ref: Node3D = null
var _proxy_world_current: Vector3 = Vector3.ZERO
var _proxy_world_target: Vector3 = Vector3.ZERO
var _proxy_ready: bool = false
var _proxy_in_backoff: bool = false
var _last_reflection_volume_offset_db: float = INF
var _spring_arm_distance_from_end: float = 0.0
var _spring_arm_ready: bool = false
var _was_reflected_proxy_active: bool = false
var _proxy_audio_has_inner_radius: bool = false
var _proxy_saved_inner_radius: float = -1.0
var _proxy_inner_radius_forced: bool = false

var _ray_query := PhysicsRayQueryParameters3D.new()
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _segment_visibility_cache: Dictionary = {}
var _point_free_cache: Dictionary = {}
var _exclusions_dirty: bool = true
var _cached_base_exclusions: Array[RID] = []


func _ready() -> void:
	if Engine.is_editor_hint() and not preview_pathing_in_editor:
		# Keep processing enabled so selected-node preview debug can update.
		set_process(true)

	_clearance_shape.radius = clearance_radius
	_shape_query.shape = _clearance_shape
	_shape_query.collision_mask = collision_mask
	_shape_query.collide_with_areas = collide_with_areas
	_shape_query.collide_with_bodies = collide_with_bodies
	_ray_query.collision_mask = collision_mask
	_ray_query.collide_with_areas = collide_with_areas
	_ray_query.collide_with_bodies = collide_with_bodies
	_ray_query.hit_from_inside = true
	if capture_fixed_origin_on_ready:
		fixed_world_origin = _resolve_node_origin_world()

	_apply_navigation_profile_preset()
	_rebuild_samples_if_needed()
	_resolve_audio_proxy_ref()
	update_configuration_warnings()
	_recompute_path()
	if Engine.is_editor_hint() and not preview_pathing_in_editor:
		_reset_audio_proxy_to_origin()
	else:
		_update_audio_proxy(0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_exclusions_dirty = true
		update_configuration_warnings()


func _validate_property(property: Dictionary) -> void:
	var prop_name := str(property.get("name", ""))
	if navigation_profile != NavigationProfile.CUSTOM and _NAV_PROFILE_CUSTOM_ONLY_PROPERTIES.has(prop_name):
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if not skip_recompute_when_static and prop_name in [
		"recompute_origin_threshold",
		"recompute_target_threshold",
		"static_recompute_interval",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if not use_reachable_scan and prop_name in [
		"scan_cell_size",
		"scan_neighbor_mode",
		"scan_max_cells",
		"scan_max_cell_extent",
		"scan_cell_inset",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if not use_unit_cost and prop_name == "unit_cost":
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if not reuse_last_path_when_valid and prop_name in [
		"reuse_origin_tolerance",
		"reuse_target_tolerance",
		"reuse_max_detour_ratio",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if not move_audio_player and prop_name in [
		"audio_player_node",
		"auto_find_audio_player_child",
		"proxy_only_when_blocked",
		"proxy_waypoint_index",
		"audio_proxy_lerp_speed",
		"audio_proxy_backoff_lerp_speed",
		"audio_proxy_height_offset",
		"restore_audio_to_origin_when_disabled",
		"proxy_force_inner_radius_outside_source_zone",
		"enable_proxy_listener_backoff",
		"proxy_min_listener_distance",
		"proxy_backoff_release_distance",
		"proxy_backoff_path_distance",
		"proxy_spring_arm_enabled",
		"proxy_spring_min_distance",
		"proxy_spring_push_strength",
		"proxy_spring_push_speed",
		"proxy_spring_return_speed",
		"apply_reflection_volume_loss",
		"reflection_loss_db_per_meter",
		"reflection_loss_power",
		"reflection_max_loss_db",
		"proxy_occlusion_transition_smoothing",
		"proxy_occlusion_hold_seconds",
		"proxy_occlusion_hold_move_threshold",
		"debug_draw_audio_proxy",
		"debug_audio_proxy_color",
		"debug_audio_proxy_radius",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if move_audio_player and proxy_spring_arm_enabled and prop_name in [
		"enable_proxy_listener_backoff",
		"proxy_min_listener_distance",
		"proxy_backoff_release_distance",
		"proxy_backoff_path_distance",
		"audio_proxy_backoff_lerp_speed",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if move_audio_player and not proxy_spring_arm_enabled and not enable_proxy_listener_backoff and prop_name in [
		"proxy_min_listener_distance",
		"proxy_backoff_release_distance",
		"proxy_backoff_path_distance",
		"audio_proxy_backoff_lerp_speed",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if move_audio_player and not proxy_spring_arm_enabled and prop_name in [
		"proxy_spring_min_distance",
		"proxy_spring_push_strength",
		"proxy_spring_push_speed",
		"proxy_spring_return_speed",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if move_audio_player and not apply_reflection_volume_loss and prop_name in [
		"reflection_loss_db_per_meter",
		"reflection_loss_power",
		"reflection_max_loss_db",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if move_audio_player and not proxy_occlusion_transition_smoothing and prop_name in [
		"proxy_occlusion_hold_seconds",
		"proxy_occlusion_hold_move_threshold",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if not debug_draw_path and prop_name == "debug_draw_direct_line_when_blocked":
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR
		return

	if not debug_draw_audio_proxy and prop_name in [
		"debug_audio_proxy_color",
		"debug_audio_proxy_radius",
	]:
		property.usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) & ~PROPERTY_USAGE_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()

	var configured_audio := _get_configured_audio_player()
	var found_spatial := _find_first_spatial_audio_player_child(self)
	if configured_audio is SpatialAudioPlayer3D:
		found_spatial = configured_audio as SpatialAudioPlayer3D

	if found_spatial == null:
		warnings.push_back(
			"No SpatialAudioPlayer3D was found. Add one as a child or assign one in `audio_player_node` for reflected proxy playback."
		)

	if configured_audio != null and configured_audio is AudioStreamPlayer3D and not (configured_audio is SpatialAudioPlayer3D):
		warnings.push_back(
			"Detected AudioStreamPlayer3D `%s`. Proxy reflection integration requires SpatialAudioPlayer3D; regular AudioStreamPlayer3D will not behave correctly."
			% configured_audio.name
		)
	elif configured_audio != null and not (configured_audio is AudioStreamPlayer3D):
		warnings.push_back(
			"`audio_player_node` points to `%s`, which is not an AudioStreamPlayer3D. Assign SpatialAudioPlayer3D for reflected proxy playback."
			% configured_audio.name
		)

	return warnings


func _process(delta: float) -> void:
	var editor_preview := Engine.is_editor_hint() and not preview_pathing_in_editor
	var editor_selected := _is_editor_selected() if editor_preview else false
	if editor_preview:
		if editor_selected:
			_time_since_last_full_recompute += delta
			_time_accum += delta
			if _time_accum >= update_interval:
				_time_accum = 0.0
				_recompute_path()
		else:
			_time_accum = 0.0
		_draw_debug(editor_selected)
		return

	_time_since_last_full_recompute += delta
	_time_accum += delta
	if _time_accum >= update_interval:
		_time_accum = 0.0
		_recompute_path()
	_update_audio_proxy(delta)
	_draw_debug(false)


func get_current_path_world() -> PackedVector3Array:
	return _current_path_world


func has_valid_path() -> bool:
	return _has_valid_path


func is_direct_path() -> bool:
	return _is_direct_path


func get_path_length() -> float:
	return _current_path_length


func force_recompute() -> void:
	_recompute_path()


func set_fixed_origin_from_current() -> void:
	fixed_world_origin = _resolve_node_origin_world()


func _mark_graph_dirty() -> void:
	_graph_dirty = true


func _apply_navigation_profile_preset() -> void:
	match navigation_profile:
		NavigationProfile.CUSTOM:
			return
		NavigationProfile.OPEN_AREAS:
			use_reachable_scan = false
			sample_point_count = 128
			max_connection_distance = 11.0
			graph_neighbor_limit = 12
			dynamic_connection_limit = 8
			dynamic_candidate_multiplier = 3
			edge_clearance_checks = 0
			graph_recenter_distance = 3.5
			scan_max_cell_extent = 0
		NavigationProfile.HALLWAYS:
			use_reachable_scan = true
			scan_neighbor_mode = ScanNeighborMode.AXIS_6
			scan_cell_size = 0.9
			scan_max_cells = 4096
			scan_max_cell_extent = 28
			scan_cell_inset = 0.10
			max_connection_distance = 8.0
			graph_neighbor_limit = 10
			dynamic_connection_limit = 6
			dynamic_candidate_multiplier = 4
			edge_clearance_checks = 1
			graph_recenter_distance = 1.5

	_has_last_solve_state = false
	_mark_graph_dirty()

	if is_inside_tree() and (not Engine.is_editor_hint() or preview_pathing_in_editor):
		_recompute_path()


func _commit_solve_state(origin_world: Vector3, target_world: Vector3) -> void:
	_last_solve_origin_world = origin_world
	_last_solve_target_world = target_world
	_has_last_solve_state = true
	_time_since_last_full_recompute = 0.0


func _recompute_path() -> void:
	var world := get_world_3d()
	if world == null:
		return

	var target := _get_target_node()
	if target == null:
		_set_failed_path(Vector3.ZERO, Vector3.ZERO, false)
		return

	var origin_world := _resolve_origin_world()
	var target_world := target.global_position
	_last_origin_world = origin_world
	_last_target_world = target_world
	if skip_recompute_when_static and _has_last_solve_state and not _graph_dirty:
		var origin_delta := origin_world.distance_to(_last_solve_origin_world)
		var target_delta := target_world.distance_to(_last_solve_target_world)
		if origin_delta < recompute_origin_threshold and target_delta < recompute_target_threshold:
			if static_recompute_interval <= 0.0 or _time_since_last_full_recompute < static_recompute_interval:
				return

	var space := world.direct_space_state
	var exclusions := _build_exclusions(target)
	_segment_visibility_cache.clear()
	_point_free_cache.clear()

	if _get_first_blocking_hit(space, origin_world, target_world, exclusions).is_empty():
		_set_path(PackedVector3Array([origin_world, target_world]), true)
		_commit_solve_state(origin_world, target_world)
		return

	if reuse_last_path_when_valid:
		var reused := _try_reuse_cached_path(space, origin_world, target_world, exclusions)
		if reused.size() >= 2:
			_set_path(reused, false)
			_commit_solve_state(origin_world, target_world)
			return

	_rebuild_graph_if_needed(space, origin_world, exclusions)
	if _graph_points_world.is_empty():
		_set_failed_path(origin_world, target_world, true)
		_commit_solve_state(origin_world, target_world)
		return

	var start_links := _find_dynamic_links(space, origin_world, target_world, exclusions)
	var goal_links := _find_dynamic_links(space, target_world, origin_world, exclusions)
	if start_links.is_empty() or goal_links.is_empty():
		_set_failed_path(origin_world, target_world, true)
		_commit_solve_state(origin_world, target_world)
		return

	var graph_path := _find_path_greedy_a_star(origin_world, target_world, start_links, goal_links)
	if smooth_path_with_visibility and graph_path.size() > 2:
		graph_path = _smooth_path(space, graph_path, exclusions)
	if graph_path.size() >= 2:
		_set_path(graph_path, false)
	else:
		_set_failed_path(origin_world, target_world, true)
	_commit_solve_state(origin_world, target_world)


func _rebuild_graph_if_needed(
	space: PhysicsDirectSpaceState3D,
	anchor_world: Vector3,
	exclusions: Array[RID]
) -> void:
	var must_recenter := _graph_points_world.is_empty() \
		or _graph_anchor_world.distance_to(anchor_world) > graph_recenter_distance
	if not _graph_dirty and not must_recenter:
		return

	_rebuild_samples_if_needed()
	_graph_anchor_world = anchor_world
	_graph_grid_origin = anchor_world
	_graph_points_world.clear()
	_graph_edges.clear()
	_graph_edge_count = 0

	if use_reachable_scan:
		_build_graph_reachable_scan(space, exclusions)
	else:
		_build_graph_random_samples(space, exclusions)

	_graph_dirty = false
	graph_rebuilt.emit(_graph_points_world.size())


func _build_graph_random_samples(space: PhysicsDirectSpaceState3D, exclusions: Array[RID]) -> void:
	for offset in _sample_offsets:
		var p := _graph_anchor_world + offset
		if _is_point_free(space, p, exclusions):
			_graph_points_world.push_back(p)

	var count := _graph_points_world.size()
	_graph_edges.resize(count)
	for i in range(count):
		_graph_edges[i] = PackedInt32Array()

	for i in range(count):
		var candidates: Array = []
		var pi := _graph_points_world[i]
		var keep_count := maxi(graph_neighbor_limit * 2, graph_neighbor_limit + 2)
		var max_conn_sq := max_connection_distance * max_connection_distance
		for j in range(count):
			if i == j:
				continue
			var d_sq := pi.distance_squared_to(_graph_points_world[j])
			if d_sq <= max_conn_sq:
				_insert_sorted_limited_pair(candidates, d_sq, j, keep_count)

		var added := 0
		for c in candidates:
			if added >= graph_neighbor_limit:
				break
			var j: int = c[1]
			if _edge_exists(i, j):
				continue
			if _is_segment_clear(space, _graph_points_world[i], _graph_points_world[j], exclusions):
				_add_edge(i, j)
				added += 1


func _build_graph_reachable_scan(space: PhysicsDirectSpaceState3D, exclusions: Array[RID]) -> void:
	var neighbor_dirs := _get_scan_neighbor_offsets(scan_neighbor_mode)
	var queue: Array[Vector3i] = []
	var head := 0
	var index_of := {}
	var radius_sq := navigation_radius * navigation_radius
	var max_extent := scan_max_cell_extent

	var start_cell := Vector3i.ZERO
	var start_pos := _cell_to_world(start_cell, _graph_grid_origin, scan_cell_size)
	if not _is_point_free(space, start_pos, exclusions):
		return

	index_of[start_cell] = 0
	queue.push_back(start_cell)
	_graph_points_world.push_back(start_pos)
	_graph_edges.push_back(PackedInt32Array())

	while head < queue.size() and _graph_points_world.size() < scan_max_cells:
		var cell := queue[head]
		head += 1
		var cell_idx: int = index_of[cell]
		var cell_pos := _graph_points_world[cell_idx]

		for dir in neighbor_dirs:
			var next_cell := cell + dir
			if max_extent > 0:
				if abs(next_cell.x) > max_extent or abs(next_cell.y) > max_extent or abs(next_cell.z) > max_extent:
					continue
			var next_pos := _cell_to_world(next_cell, _graph_grid_origin, scan_cell_size)
			if next_pos.distance_squared_to(_graph_anchor_world) > radius_sq:
				continue

			var has_next := index_of.has(next_cell)
			if not has_next:
				if not _is_point_free(space, next_pos, exclusions):
					continue
				if not _is_segment_clear(space, cell_pos, next_pos, exclusions):
					continue
				index_of[next_cell] = _graph_points_world.size()
				queue.push_back(next_cell)
				_graph_points_world.push_back(next_pos)
				_graph_edges.push_back(PackedInt32Array())
				var new_idx: int = index_of[next_cell]
				if not _edge_exists(cell_idx, new_idx):
					_add_edge(cell_idx, new_idx)
				continue
			else:
				if not _is_segment_clear(space, cell_pos, next_pos, exclusions):
					continue

			var next_idx: int = index_of[next_cell]
			if cell_idx == next_idx:
				continue
			if _edge_exists(cell_idx, next_idx):
				continue
			if _graph_edges[cell_idx].size() >= graph_neighbor_limit:
				continue
			if _graph_edges[next_idx].size() >= graph_neighbor_limit:
				continue
			_add_edge(cell_idx, next_idx)


func _edge_exists(a: int, b: int) -> bool:
	for n in _graph_edges[a]:
		if n == b:
			return true
	return false


func _add_edge(a: int, b: int) -> void:
	var aa := _graph_edges[a]
	aa.push_back(b)
	_graph_edges[a] = aa
	var bb := _graph_edges[b]
	bb.push_back(a)
	_graph_edges[b] = bb
	_graph_edge_count += 1


func _find_dynamic_links(
	space: PhysicsDirectSpaceState3D,
	from_world: Vector3,
	toward_world: Vector3,
	exclusions: Array[RID]
) -> PackedInt32Array:
	var candidates: Array = []
	var keep_count := maxi(dynamic_connection_limit * maxi(dynamic_candidate_multiplier, 1), dynamic_connection_limit + 2)
	for i in range(_graph_points_world.size()):
		var p := _graph_points_world[i]
		var score := from_world.distance_squared_to(p) + p.distance_squared_to(toward_world) * 0.25
		_insert_sorted_limited_pair(candidates, score, i, keep_count)

	var out := PackedInt32Array()
	for c in candidates:
		if out.size() >= dynamic_connection_limit:
			break
		var idx: int = c[1]
		if _is_segment_clear(space, from_world, _graph_points_world[idx], exclusions):
			out.push_back(idx)
	return out


func _find_path_greedy_a_star(
	start_world: Vector3,
	goal_world: Vector3,
	start_links: PackedInt32Array,
	goal_links: PackedInt32Array
) -> PackedVector3Array:
	# Mirrors the repo's GreedyAStar flow:
	# frontier(min-heap by f), travel_cost, breadcrumb.
	var goal_set := {}
	for idx in goal_links:
		goal_set[idx] = true

	var frontier: Array = []
	_heap_push(frontier, [0.0, 0]) # [f_score, node_id]

	var travel_cost := {0: 0.0}
	var breadcrumb := {0: -1}

	while not frontier.is_empty():
		var best := _heap_pop(frontier)
		var best_f: float = best[0]
		var best_id: int = best[1]

		var current_g: float = travel_cost.get(best_id, INF)
		if current_g == INF:
			continue
		var expected_f := current_g + _estimate_cost(_id_to_point(best_id, start_world, goal_world), goal_world)
		if best_f > expected_f + 0.0001:
			continue

		if best_id == 1:
			break

		var neighbors := _neighbors_of(best_id, start_links, goal_set)
		for n in neighbors:
			var move_cost := _compute_move_cost(
				_id_to_point(best_id, start_world, goal_world),
				_id_to_point(n, start_world, goal_world)
			)
			var next_g := current_g + move_cost
			if next_g < travel_cost.get(n, INF):
				travel_cost[n] = next_g
				breadcrumb[n] = best_id
				var f := next_g + _estimate_cost(_id_to_point(n, start_world, goal_world), goal_world)
				_heap_push(frontier, [f, n])

	if not travel_cost.has(1):
		return PackedVector3Array()

	var id_path := PackedInt32Array([1])
	while id_path[id_path.size() - 1] != 0:
		id_path.push_back(breadcrumb[id_path[id_path.size() - 1]])
	id_path.reverse()

	var world_path := PackedVector3Array()
	for id in id_path:
		world_path.push_back(_id_to_point(id, start_world, goal_world))
	return world_path


func _neighbors_of(id: int, start_links: PackedInt32Array, goal_set: Dictionary) -> PackedInt32Array:
	if id == 1:
		return PackedInt32Array()
	if id == 0:
		var out := PackedInt32Array()
		for idx in start_links:
			out.push_back(idx + 2)
		return out

	var out := PackedInt32Array()
	var graph_idx := id - 2
	for n in _graph_edges[graph_idx]:
		out.push_back(n + 2)
	if goal_set.has(graph_idx):
		out.push_back(1)
	return out


func _id_to_point(id: int, start_world: Vector3, goal_world: Vector3) -> Vector3:
	if id == 0:
		return start_world
	if id == 1:
		return goal_world
	return _graph_points_world[id - 2]


func _try_reuse_cached_path(
	space: PhysicsDirectSpaceState3D,
	origin_world: Vector3,
	target_world: Vector3,
	exclusions: Array[RID]
) -> PackedVector3Array:
	if _cached_internal_waypoints.is_empty():
		return PackedVector3Array()
	if origin_world.distance_to(_cached_origin_world) > reuse_origin_tolerance:
		return PackedVector3Array()
	if target_world.distance_to(_cached_target_world) > reuse_target_tolerance:
		return PackedVector3Array()

	var candidate := PackedVector3Array([origin_world])
	for p in _cached_internal_waypoints:
		candidate.push_back(p)
	candidate.push_back(target_world)

	if _is_path_valid(space, candidate, exclusions):
		if smooth_path_with_visibility and candidate.size() > 2:
			candidate = _smooth_path(space, candidate, exclusions)
		var candidate_length := _path_length(candidate)
		var direct_distance := origin_world.distance_to(target_world)
		if _cached_path_length > 0.0 and candidate_length > _cached_path_length * 1.20:
			return PackedVector3Array()
		if candidate_length > direct_distance * reuse_max_detour_ratio:
			return PackedVector3Array()
		return candidate
	return PackedVector3Array()


func _is_path_valid(
	space: PhysicsDirectSpaceState3D,
	path_world: PackedVector3Array,
	exclusions: Array[RID]
) -> bool:
	if path_world.size() < 2:
		return false
	for i in range(path_world.size() - 1):
		if not _is_segment_clear(space, path_world[i], path_world[i + 1], exclusions):
			return false
	return true


func _smooth_path(
	space: PhysicsDirectSpaceState3D,
	path_world: PackedVector3Array,
	exclusions: Array[RID]
) -> PackedVector3Array:
	if path_world.size() <= 2:
		return path_world

	var smoothed := PackedVector3Array([path_world[0]])
	var anchor := 0
	while anchor < path_world.size() - 1:
		var furthest := path_world.size() - 1
		while furthest > anchor + 1:
			if _is_segment_clear(space, path_world[anchor], path_world[furthest], exclusions):
				break
			furthest -= 1
		smoothed.push_back(path_world[furthest])
		anchor = furthest
	return smoothed


func _path_length(path_world: PackedVector3Array) -> float:
	if path_world.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(path_world.size() - 1):
		total += path_world[i].distance_to(path_world[i + 1])
	return total


func _apply_proxy_spring_arm_target(delta: float, base_target_world: Vector3) -> Vector3:
	if _current_path_world.size() < 2:
		_spring_arm_ready = false
		return base_target_world

	var path_total := _current_path_length
	if path_total <= 0.001:
		_spring_arm_ready = false
		return base_target_world

	var listener_pos := _current_path_world[_current_path_world.size() - 1]
	var base_along := _distance_from_start_to_point_on_path(_current_path_world, base_target_world)
	var desired_from_end := clampf(path_total - base_along, 0.0, path_total)

	var probe := _proxy_world_current if _proxy_ready else base_target_world
	var current_to_listener := probe.distance_to(listener_pos)
	var min_dist := maxf(proxy_spring_min_distance, 0.0)
	if current_to_listener < min_dist:
		var breach := min_dist - current_to_listener
		desired_from_end = maxf(desired_from_end, min_dist + breach * proxy_spring_push_strength)

	if not _spring_arm_ready:
		_spring_arm_distance_from_end = desired_from_end
		_spring_arm_ready = true
	else:
		var speed := proxy_spring_push_speed if desired_from_end > _spring_arm_distance_from_end else proxy_spring_return_speed
		var t := clampf(delta * speed, 0.0, 1.0)
		_spring_arm_distance_from_end = lerpf(_spring_arm_distance_from_end, desired_from_end, t)

	_spring_arm_distance_from_end = clampf(_spring_arm_distance_from_end, 0.0, path_total)
	return _point_along_path_from_end(_current_path_world, _spring_arm_distance_from_end)


func _point_along_path_from_end(path_world: PackedVector3Array, distance_from_end: float) -> Vector3:
	if path_world.is_empty():
		return Vector3.ZERO
	if path_world.size() == 1:
		return path_world[0]

	var remain := maxf(distance_from_end, 0.0)
	for i in range(path_world.size() - 1, 0, -1):
		var seg_end := path_world[i]
		var seg_start := path_world[i - 1]
		var seg_len := seg_end.distance_to(seg_start)
		if seg_len <= 0.0001:
			continue
		if remain <= seg_len:
			var t := remain / seg_len
			return seg_end.lerp(seg_start, t)
		remain -= seg_len
	return path_world[0]


func _distance_from_start_to_point_on_path(path_world: PackedVector3Array, point_world: Vector3) -> float:
	if path_world.size() < 2:
		return 0.0

	var best_dist := INF
	var best_along := 0.0
	var accum := 0.0
	for i in range(path_world.size() - 1):
		var a := path_world[i]
		var b := path_world[i + 1]
		var ab := b - a
		var seg_len_sq := ab.length_squared()
		if seg_len_sq <= 0.000001:
			continue
		var t := clampf((point_world - a).dot(ab) / seg_len_sq, 0.0, 1.0)
		var proj := a + ab * t
		var d := proj.distance_to(point_world)
		var seg_len := sqrt(seg_len_sq)
		if d < best_dist:
			best_dist = d
			best_along = accum + seg_len * t
		accum += seg_len
	return best_along


func _update_reflection_audio_modulation(origin_world: Vector3, proxy_world: Vector3) -> void:
	if not apply_reflection_volume_loss:
		_apply_reflection_volume_offset_db(0.0)
		return
	if _is_direct_path or _current_path_world.size() < 2:
		_apply_reflection_volume_offset_db(0.0)
		return

	var route_dist := _distance_from_start_to_point_on_path(_current_path_world, proxy_world)
	var shaped_dist := pow(maxf(route_dist, 0.0), reflection_loss_power)
	var loss_db := minf(shaped_dist * reflection_loss_db_per_meter, reflection_max_loss_db)
	_apply_reflection_volume_offset_db(-loss_db)


func _apply_reflection_volume_offset_db(offset_db: float) -> void:
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref):
		return
	if abs(offset_db - _last_reflection_volume_offset_db) < 0.05:
		return
	_last_reflection_volume_offset_db = offset_db

	if _audio_proxy_ref.has_method("set_external_volume_db_offset"):
		_audio_proxy_ref.call("set_external_volume_db_offset", offset_db)


func _update_proxy_occlusion_transition_support(reflected_active: bool) -> void:
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref):
		_was_reflected_proxy_active = reflected_active
		return
	if not proxy_occlusion_transition_smoothing:
		if _audio_proxy_ref.has_method("clear_external_occlusion_hold"):
			_audio_proxy_ref.call("clear_external_occlusion_hold")
		_was_reflected_proxy_active = reflected_active
		return
	if not _audio_proxy_ref.has_method("set_external_occlusion_hold"):
		_was_reflected_proxy_active = reflected_active
		return

	# Never force occlusion open while reflected/behind walls.
	if reflected_active:
		if _audio_proxy_ref.has_method("clear_external_occlusion_hold"):
			_audio_proxy_ref.call("clear_external_occlusion_hold")
	elif _was_reflected_proxy_active:
		if proxy_occlusion_hold_seconds > 0.0:
			_audio_proxy_ref.call("set_external_occlusion_hold", proxy_occlusion_hold_seconds)

	if not reflected_active and _proxy_ready:
		if _proxy_world_current.distance_to(_proxy_world_target) > proxy_occlusion_hold_move_threshold:
			_audio_proxy_ref.call("set_external_occlusion_hold", proxy_occlusion_hold_seconds)

	_was_reflected_proxy_active = reflected_active


func _update_external_navigation_debug(reflected_active: bool, origin_world: Vector3, listener_world: Vector3) -> void:
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref):
		return
	var has_setter := _audio_proxy_ref.has_method("set_external_navigation_debug_data")
	var has_clear := _audio_proxy_ref.has_method("clear_external_navigation_debug_data")
	if not has_setter and not has_clear:
		return

	if not reflected_active:
		if has_clear:
			_audio_proxy_ref.call("clear_external_navigation_debug_data")
		elif has_setter:
			_audio_proxy_ref.call("set_external_navigation_debug_data", false, {})
		return

	var direct_distance := maxf(origin_world.distance_to(listener_world), 0.001)
	var detour_ratio := _current_path_length / direct_distance
	var info := {
		"agent_name": name,
		"profile": NavigationProfile.keys()[navigation_profile],
		"path_points": _current_path_world.size(),
		"path_length": _current_path_length,
		"direct_distance": direct_distance,
		"detour_ratio": detour_ratio,
		"graph_points": _graph_points_world.size(),
		"graph_edges": _graph_edge_count,
		"proxy_waypoint_index": proxy_waypoint_index,
		"proxy_backoff_active": _proxy_in_backoff,
		"spring_arm_active": proxy_spring_arm_enabled,
		"spring_arm_distance_from_end": _spring_arm_distance_from_end,
		"proxy_to_listener": _proxy_world_current.distance_to(listener_world),
		"proxy_to_origin": _proxy_world_current.distance_to(origin_world),
		"proxy_to_target": _proxy_world_current.distance_to(_proxy_world_target),
		"update_hz": 1.0 / update_interval if update_interval > 0.0 else 0.0,
	}
	if has_setter:
		_audio_proxy_ref.call("set_external_navigation_debug_data", true, info)


func _reset_audio_proxy_to_origin() -> void:
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref):
		_resolve_audio_proxy_ref()
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref):
		return

	var origin_world := _resolve_origin_world()
	var listener_world := _last_target_world
	if _has_valid_path and _current_path_world.size() > 0:
		listener_world = _current_path_world[_current_path_world.size() - 1]

	_audio_proxy_ref.global_position = origin_world
	_proxy_world_current = origin_world
	_proxy_world_target = origin_world
	_proxy_ready = true
	_proxy_in_backoff = false
	_spring_arm_ready = false
	_update_proxy_inner_radius_override(false, origin_world, origin_world)
	_update_proxy_occlusion_transition_support(false)
	_apply_reflection_volume_offset_db(0.0)
	_update_external_navigation_debug(false, origin_world, listener_world)


func _compute_move_cost(from_world: Vector3, to_world: Vector3) -> float:
	if use_unit_cost:
		return unit_cost
	return _distance(from_world, to_world)


func _estimate_cost(from_world: Vector3, to_world: Vector3) -> float:
	return heuristic_weight * _distance(from_world, to_world)


func _distance(a: Vector3, b: Vector3) -> float:
	match distance_mode:
		DistanceMode.MANHATTAN:
			var d := (a - b).abs()
			return d.x + d.y + d.z
		_:
			return a.distance_to(b)


func _heap_push(heap: Array, item: Array) -> void:
	heap.push_back(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[p][0] <= heap[i][0]:
			break
		var tmp = heap[p]
		heap[p] = heap[i]
		heap[i] = tmp
		i = p


func _heap_pop(heap: Array) -> Array:
	var top = heap[0]
	var last := heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			if l >= heap.size():
				break
			var m := l
			if r < heap.size() and heap[r][0] < heap[l][0]:
				m = r
			if heap[i][0] <= heap[m][0]:
				break
			var tmp = heap[i]
			heap[i] = heap[m]
			heap[m] = tmp
			i = m
	return top


func _update_audio_proxy(delta: float) -> void:
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref):
		_resolve_audio_proxy_ref()
	if _audio_proxy_ref == null:
		return

	var origin_world := _resolve_origin_world()
	var listener_world := _last_target_world
	if _has_valid_path and _current_path_world.size() > 0:
		listener_world = _current_path_world[_current_path_world.size() - 1]
	else:
		var target_node := _get_target_node()
		if target_node != null:
			listener_world = target_node.global_position
	if not move_audio_player:
		_proxy_in_backoff = false
		_spring_arm_ready = false
		_update_proxy_inner_radius_override(false, origin_world, origin_world)
		_update_proxy_occlusion_transition_support(false)
		_update_external_navigation_debug(false, origin_world, listener_world)
		if restore_audio_to_origin_when_disabled:
			_audio_proxy_ref.global_position = origin_world
			_proxy_world_current = origin_world
			_proxy_world_target = origin_world
			_proxy_ready = true
		_apply_reflection_volume_offset_db(0.0)
		return

	var reflected_active := _has_valid_path and not _is_direct_path
	var base_target := _get_proxy_target_world(origin_world)
	if reflected_active and proxy_spring_arm_enabled:
		base_target = _apply_proxy_spring_arm_target(delta, base_target)
	else:
		_spring_arm_ready = false

	_proxy_world_target = base_target + Vector3.UP * audio_proxy_height_offset
	if not _proxy_ready:
		_proxy_world_current = _proxy_world_target
		_proxy_ready = true
	var active_lerp_speed := audio_proxy_backoff_lerp_speed if _proxy_in_backoff else audio_proxy_lerp_speed
	if active_lerp_speed <= 0.0:
		_proxy_world_current = _proxy_world_target
	else:
		var w := clampf(delta * active_lerp_speed, 0.0, 1.0)
		_proxy_world_current = _proxy_world_current.lerp(_proxy_world_target, w)

	_audio_proxy_ref.global_position = _proxy_world_current
	_update_reflection_audio_modulation(origin_world, _proxy_world_current)
	_update_proxy_inner_radius_override(reflected_active, origin_world, _proxy_world_current)
	_update_proxy_occlusion_transition_support(reflected_active)
	_update_external_navigation_debug(reflected_active, origin_world, listener_world)
	audio_proxy_position_updated.emit(_proxy_world_current)


func _get_proxy_target_world(origin_world: Vector3) -> Vector3:
	if not _has_valid_path or _current_path_world.size() < 2:
		_proxy_in_backoff = false
		return origin_world
	if proxy_only_when_blocked and _is_direct_path:
		_proxy_in_backoff = false
		return origin_world
	var idx := mini(maxi(proxy_waypoint_index, 1), _current_path_world.size() - 1)
	var target_point := _current_path_world[idx]

	if proxy_spring_arm_enabled:
		_proxy_in_backoff = false
		return target_point

	if not enable_proxy_listener_backoff or _is_direct_path:
		_proxy_in_backoff = false
		return target_point

	var listener_pos := _current_path_world[_current_path_world.size() - 1]
	var proxy_check_pos := _proxy_world_current if _proxy_ready else target_point
	var dist_to_listener := proxy_check_pos.distance_to(listener_pos)
	var release_dist := maxf(proxy_backoff_release_distance, proxy_min_listener_distance)

	if _proxy_in_backoff:
		if dist_to_listener >= release_dist:
			_proxy_in_backoff = false
	else:
		if dist_to_listener < proxy_min_listener_distance:
			_proxy_in_backoff = true

	if _proxy_in_backoff:
		var backoff_dist := maxf(proxy_backoff_path_distance, proxy_min_listener_distance)
		target_point = _point_along_path_from_end(_current_path_world, backoff_dist)

	return target_point


func _resolve_audio_proxy_ref() -> void:
	if audio_player_node != null and is_instance_valid(audio_player_node):
		if _audio_proxy_ref != audio_player_node:
			if _audio_proxy_ref != null and is_instance_valid(_audio_proxy_ref) and _audio_proxy_ref.has_method("clear_external_navigation_debug_data"):
				_audio_proxy_ref.call("clear_external_navigation_debug_data")
			_restore_proxy_inner_radius_if_forced()
			_proxy_ready = false
			_last_reflection_volume_offset_db = INF
		_audio_proxy_ref = audio_player_node
		_refresh_proxy_inner_radius_capability()
		return

	if not auto_find_audio_player_child:
		return

	var found := _find_first_audio_player_child(self)
	if _audio_proxy_ref != found:
		if _audio_proxy_ref != null and is_instance_valid(_audio_proxy_ref) and _audio_proxy_ref.has_method("clear_external_navigation_debug_data"):
			_audio_proxy_ref.call("clear_external_navigation_debug_data")
		_restore_proxy_inner_radius_if_forced()
		_proxy_ready = false
		_last_reflection_volume_offset_db = INF
	_audio_proxy_ref = found
	_refresh_proxy_inner_radius_capability()


func _get_configured_audio_player() -> Node3D:
	if audio_player_node != null and is_instance_valid(audio_player_node):
		return audio_player_node
	if auto_find_audio_player_child:
		return _find_first_audio_player_child(self)
	return null


func _find_first_audio_player_child(node: Node) -> Node3D:
	for child in node.get_children():
		if child is AudioStreamPlayer3D:
			return child as Node3D
	for child in node.get_children():
		var found := _find_first_audio_player_child(child)
		if found != null:
			return found
	return null


func _find_first_spatial_audio_player_child(node: Node) -> SpatialAudioPlayer3D:
	for child in node.get_children():
		if child is SpatialAudioPlayer3D:
			return child as SpatialAudioPlayer3D
	for child in node.get_children():
		var found := _find_first_spatial_audio_player_child(child)
		if found != null:
			return found
	return null


func _refresh_proxy_inner_radius_capability() -> void:
	_proxy_audio_has_inner_radius = false
	_proxy_saved_inner_radius = -1.0
	_proxy_inner_radius_forced = false
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref):
		return
	for prop in _audio_proxy_ref.get_property_list():
		if str(prop.name) == "inner_radius":
			_proxy_audio_has_inner_radius = true
			var v = _audio_proxy_ref.get("inner_radius")
			if v is float:
				_proxy_saved_inner_radius = float(v)
			elif v is int:
				_proxy_saved_inner_radius = float(v)
			else:
				_proxy_saved_inner_radius = 0.0
			return


func _restore_proxy_inner_radius_if_forced() -> void:
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref):
		_proxy_inner_radius_forced = false
		return
	if _proxy_audio_has_inner_radius and _proxy_inner_radius_forced and _proxy_saved_inner_radius >= 0.0:
		_audio_proxy_ref.set("inner_radius", _proxy_saved_inner_radius)
	_proxy_inner_radius_forced = false


func _update_proxy_inner_radius_override(reflected_active: bool, origin_world: Vector3, proxy_world: Vector3) -> void:
	if not proxy_force_inner_radius_outside_source_zone:
		_restore_proxy_inner_radius_if_forced()
		return
	if not reflected_active:
		_restore_proxy_inner_radius_if_forced()
		if _audio_proxy_ref != null and is_instance_valid(_audio_proxy_ref) and _proxy_audio_has_inner_radius:
			var cur = _audio_proxy_ref.get("inner_radius")
			if cur is float:
				_proxy_saved_inner_radius = float(cur)
			elif cur is int:
				_proxy_saved_inner_radius = float(cur)
		return
	if _audio_proxy_ref == null or not is_instance_valid(_audio_proxy_ref) or not _proxy_audio_has_inner_radius:
		return

	if _proxy_saved_inner_radius < 0.0:
		var raw = _audio_proxy_ref.get("inner_radius")
		if raw is float:
			_proxy_saved_inner_radius = float(raw)
		elif raw is int:
			_proxy_saved_inner_radius = float(raw)
		else:
			_proxy_saved_inner_radius = 0.0

	var source_inner := maxf(_proxy_saved_inner_radius, 0.0)
	var outside_source_inner := origin_world.distance_to(proxy_world) > source_inner + 0.001
	if outside_source_inner:
		if not _proxy_inner_radius_forced:
			_audio_proxy_ref.set("inner_radius", 0.0)
			_proxy_inner_radius_forced = true
	else:
		_restore_proxy_inner_radius_if_forced()


func _set_path(path_world: PackedVector3Array, direct: bool) -> void:
	_current_path_world = path_world
	_has_valid_path = path_world.size() >= 2
	_is_direct_path = direct and _has_valid_path
	_current_path_length = _path_length(path_world)
	if _has_valid_path:
		_cached_origin_world = path_world[0]
		_cached_target_world = path_world[path_world.size() - 1]
		_cached_path_length = _current_path_length
		_cached_internal_waypoints = PackedVector3Array()
		if not _is_direct_path and path_world.size() > 2:
			for i in range(1, path_world.size() - 1):
				_cached_internal_waypoints.push_back(path_world[i])
	path_updated.emit(_current_path_world, _is_direct_path)


func _set_failed_path(origin_world: Vector3, target_world: Vector3, blocked: bool) -> void:
	_current_path_world = PackedVector3Array()
	_has_valid_path = false
	_is_direct_path = false
	_current_path_length = 0.0
	if blocked:
		path_failed.emit(origin_world, target_world)


func _rebuild_samples_if_needed() -> void:
	if not _samples_dirty:
		return

	_sample_offsets.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = sample_seed
	for _i in range(sample_point_count):
		_sample_offsets.push_back(_random_point_in_sphere(rng, navigation_radius))
	_samples_dirty = false


func _is_segment_clear(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	exclusions: Array[RID]
) -> bool:
	if from.is_equal_approx(to):
		return true

	var key := _segment_key(from, to)
	if _segment_visibility_cache.has(key):
		return _segment_visibility_cache[key]

	var visible := true
	var hit := _get_first_blocking_hit(space, from, to, exclusions)
	if not hit.is_empty():
		visible = false
	elif edge_clearance_checks > 0:
		for i in range(edge_clearance_checks):
			var t := float(i + 1) / float(edge_clearance_checks + 1)
			var p := from.lerp(to, t)
			if not _is_point_free(space, p, exclusions):
				visible = false
				break

	_segment_visibility_cache[key] = visible
	return visible


func _get_first_blocking_hit(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	exclusions: Array[RID]
) -> Dictionary:
	_ray_query.from = from
	_ray_query.to = to
	_ray_query.exclude = exclusions
	_ray_query.collision_mask = collision_mask
	_ray_query.collide_with_areas = collide_with_areas
	_ray_query.collide_with_bodies = collide_with_bodies
	_ray_query.hit_from_inside = true
	return space.intersect_ray(_ray_query)


func _is_point_free(
	space: PhysicsDirectSpaceState3D,
	point: Vector3,
	exclusions: Array[RID]
) -> bool:
	var key := _point_key(point)
	if _point_free_cache.has(key):
		return _point_free_cache[key]

	_shape_query.transform = Transform3D(Basis.IDENTITY, point)
	_shape_query.exclude = exclusions
	_shape_query.collision_mask = collision_mask
	_shape_query.collide_with_areas = collide_with_areas
	_shape_query.collide_with_bodies = collide_with_bodies
	var hits := space.intersect_shape(_shape_query, 1)
	var is_free := hits.is_empty()
	_point_free_cache[key] = is_free
	return is_free


func _point_key(point: Vector3) -> Vector3i:
	return Vector3i(
		roundi(point.x * 100.0),
		roundi(point.y * 100.0),
		roundi(point.z * 100.0)
	)


func _segment_key(a: Vector3, b: Vector3) -> String:
	var ka := _point_key(a)
	var kb := _point_key(b)
	if ka.x > kb.x or (ka.x == kb.x and (ka.y > kb.y or (ka.y == kb.y and ka.z > kb.z))):
		var swap := ka
		ka = kb
		kb = swap
	return "%d|%d|%d>%d|%d|%d" % [ka.x, ka.y, ka.z, kb.x, kb.y, kb.z]


func _insert_sorted_limited_pair(store: Array, score: float, idx: int, limit: int) -> void:
	var pair := [score, idx]
	var inserted := false
	for i in range(store.size()):
		if score < store[i][0]:
			store.insert(i, pair)
			inserted = true
			break
	if not inserted:
		if store.size() < limit:
			store.push_back(pair)
		else:
			return
	if store.size() > limit:
		store.resize(limit)


func _resolve_origin_world() -> Vector3:
	match origin_mode:
		OriginMode.NODE_POSITION:
			return _resolve_node_origin_world()
		OriginMode.NODE_WITH_LOCAL_OFFSET:
			var owner: Node3D = origin_override if origin_override != null else self
			return owner.to_global(origin_local_offset)
		OriginMode.FIXED_WORLD_POSITION:
			return fixed_world_origin
	return global_position


func _resolve_node_origin_world() -> Vector3:
	if origin_override != null:
		return origin_override.global_position
	return global_position


func _is_editor_selected() -> bool:
	if not Engine.is_editor_hint():
		return false
	var selection := EditorInterface.get_selection()
	return self in selection.get_selected_nodes()


func _get_target_node() -> Node3D:
	if target_override != null:
		return target_override
	if Engine.is_editor_hint():
		var vp := EditorInterface.get_editor_viewport_3d()
		if vp != null:
			return vp.get_camera_3d()
		return null
	return get_viewport().get_camera_3d()


func _build_exclusions(target: Node3D) -> Array[RID]:
	if _exclusions_dirty:
		_cached_base_exclusions.clear()
		var seen := {}
		_append_collision_rids_recursive(self, _cached_base_exclusions, seen)
		for node in excluded_collision_nodes:
			_append_collision_rids_recursive(node, _cached_base_exclusions, seen)
		_exclusions_dirty = false

	if not ignore_listener_body or target == null:
		return _cached_base_exclusions

	var out := _cached_base_exclusions.duplicate()
	var seen_merge := {}
	for rid in out:
		seen_merge[rid] = true
	var listener_root := _find_collision_ancestor(target)
	if listener_root != null:
		_append_collision_rids_recursive(listener_root, out, seen_merge)
	return out


func _append_collision_rids_recursive(node: Node, out: Array[RID], seen: Dictionary) -> void:
	if node == null:
		return
	if node is CollisionObject3D:
		var rid := (node as CollisionObject3D).get_rid()
		if not seen.has(rid):
			seen[rid] = true
			out.push_back(rid)
	for child in node.get_children():
		_append_collision_rids_recursive(child, out, seen)


func _find_collision_ancestor(node: Node) -> Node:
	var cur := node
	while cur != null:
		if cur is CollisionObject3D:
			return cur
		cur = cur.get_parent()
	return null


func _random_point_in_sphere(rng: RandomNumberGenerator, radius: float) -> Vector3:
	while true:
		var p := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		)
		if p.length_squared() <= 1.0:
			return p * radius
	return Vector3.ZERO


func _cell_to_world(cell: Vector3i, grid_origin: Vector3, cell_size: float) -> Vector3:
	var step := cell_size * (1.0 - scan_cell_inset)
	return grid_origin + Vector3(cell.x, cell.y, cell.z) * step


func _get_scan_neighbor_offsets(mode: ScanNeighborMode) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var n := Vector3i(x, y, z)
				if n == Vector3i.ZERO:
					continue
				var manhattan = abs(x) + abs(y) + abs(z)
				match mode:
					ScanNeighborMode.AXIS_6:
						if manhattan == 1:
							out.push_back(n)
					ScanNeighborMode.DIAGONAL_18:
						if manhattan <= 2:
							out.push_back(n)
					ScanNeighborMode.FULL_26:
						out.push_back(n)
	return out


func _ensure_debug_mesh() -> void:
	if _debug_mesh != null and _debug_instance != null:
		return
	_debug_mesh = ImmediateMesh.new()
	_debug_instance = MeshInstance3D.new()
	_debug_instance.name = "ReflectionNavDebug"
	_debug_instance.mesh = _debug_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_instance.material_override = mat
	add_child(_debug_instance)


func _draw_debug(editor_selected_preview: bool = false) -> void:
	var show_bounds := debug_draw_bounds or editor_selected_preview
	var show_path := debug_draw_path or editor_selected_preview
	var wants_any := show_bounds \
		or show_path \
		or debug_draw_graph_points \
		or debug_draw_graph_edges \
		or (debug_draw_audio_proxy and move_audio_player)
	if not wants_any:
		if _debug_mesh != null and _debug_was_drawing:
			_debug_mesh.clear_surfaces()
			_debug_was_drawing = false
		if _debug_instance != null:
			_debug_instance.visible = false
		return

	if _debug_mesh == null:
		_ensure_debug_mesh()
	if _debug_mesh == null:
		return

	if _debug_instance != null:
		_debug_instance.visible = true
	_debug_was_drawing = true

	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	if show_bounds:
		_draw_wireframe_sphere(_resolve_origin_world(), navigation_radius, debug_bounds_color, 48)

	if show_path:
		if _has_valid_path and _current_path_world.size() >= 2:
			_draw_polyline(_current_path_world, debug_path_color)
		elif debug_draw_direct_line_when_blocked:
			_draw_polyline(PackedVector3Array([_last_origin_world, _last_target_world]), debug_blocked_color)

	if debug_draw_graph_points:
		for p in _graph_points_world:
			_draw_cross(p, 0.06, debug_graph_color)

	if debug_draw_graph_edges:
		for i in range(_graph_points_world.size()):
			for j in _graph_edges[i]:
				if j <= i:
					continue
				_draw_segment(_graph_points_world[i], _graph_points_world[j], debug_graph_color)

	if debug_draw_audio_proxy and _audio_proxy_ref != null and move_audio_player:
		_draw_wireframe_sphere(_audio_proxy_ref.global_position, debug_audio_proxy_radius, debug_audio_proxy_color, 24)
		_draw_cross(_audio_proxy_ref.global_position, debug_audio_proxy_radius, debug_audio_proxy_color)

	_debug_mesh.surface_end()


func _draw_polyline(points_world: PackedVector3Array, color: Color) -> void:
	for i in range(points_world.size() - 1):
		_draw_segment(points_world[i], points_world[i + 1], color)


func _draw_segment(a_world: Vector3, b_world: Vector3, color: Color) -> void:
	var a := to_local(a_world)
	var b := to_local(b_world)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(a)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(b)


func _draw_cross(center_world: Vector3, size: float, color: Color) -> void:
	var c := to_local(center_world)
	var x0 := c + Vector3(-size, 0.0, 0.0)
	var x1 := c + Vector3(size, 0.0, 0.0)
	var y0 := c + Vector3(0.0, -size, 0.0)
	var y1 := c + Vector3(0.0, size, 0.0)
	var z0 := c + Vector3(0.0, 0.0, -size)
	var z1 := c + Vector3(0.0, 0.0, size)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(x0)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(x1)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(y0)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(y1)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(z0)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(z1)


func _draw_wireframe_sphere(center_world: Vector3, radius: float, color: Color, segments: int = 64) -> void:
	var c := to_local(center_world)
	for plane in range(3):
		for i in range(segments):
			var a0 := (float(i) / float(segments)) * TAU
			var a1 := (float(i + 1) / float(segments)) * TAU
			var p0: Vector3
			var p1: Vector3
			match plane:
				0:
					p0 = c + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
					p1 = c + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
				1:
					p0 = c + Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
					p1 = c + Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
				2:
					p0 = c + Vector3(0.0, cos(a0) * radius, sin(a0) * radius)
					p1 = c + Vector3(0.0, cos(a1) * radius, sin(a1) * radius)
			_debug_mesh.surface_set_color(color)
			_debug_mesh.surface_add_vertex(p0)
			_debug_mesh.surface_set_color(color)
			_debug_mesh.surface_add_vertex(p1)
