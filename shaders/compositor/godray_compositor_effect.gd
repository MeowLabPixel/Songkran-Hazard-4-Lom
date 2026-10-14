@tool
class_name GodrayCompositorEffect
extends CompositorEffect

@export_group("Recompile / Debug")
@export var recompile: bool = false:
	set(v):
		if v:
			_cleanup_gpu_resources()
			notify_property_list_changed()

@export_group("Ray Properties")
@export_range(4, 64, 1) var num_samples: int = 12
@export_range(0.05, 1.5, 0.01) var max_ray_length: float = 0.75
@export_range(0.0, 2.0, 0.01) var density: float = 0.75
@export_range(0.0, 0.2, 0.001) var weight: float = 0.03
@export_range(0.7, 1.0, 0.005) var decay: float = 0.94
@export_range(0.0, 2.0, 0.05) var exposure: float = 0.5
@export_range(0.0, 1.0, 0.05) var light_fade_start: float = 0.8
@export_range(0.0, 1.0, 0.05) var light_fade_end: float = 1.0
@export var ambient_color: Color = Color(1.167, 1.182, 0.725)

@export_group("Directional Visibility")
@export var light_group: StringName = &"sun_light"
@export var light_name: String = "DirectionalLight3D"
@export var invert_direction: bool = false
@export_range(0.0, 1.0, 0.05) var min_facing_intensity: float = 0.35
@export_range(0.1, 2.0, 0.05) var facing_falloff_power: float = 1.0

@export_group("Near Occlusion")
@export var enable_near_fade: bool = true
@export_range(0.0, 30.0, 0.1) var near_fade_start: float = 1.5
@export_range(0.1, 50.0, 0.1) var near_fade_end: float = 6.0
@export var enable_near_gradient: bool = true
@export_range(0.0, 1.0, 0.01) var near_gradient_bottom_alpha: float = 0.0
@export_range(0.0, 1.0, 0.05) var near_gradient_top_alpha: float = 1.0
@export_range(0.0, 1.0, 0.05) var near_gradient_bottom_y: float = 0.1
@export_range(0.0, 1.0, 0.05) var near_gradient_top_y: float = 0.8
@export_range(0.2, 4.0, 0.1) var near_gradient_curve: float = 1.0

@export_group("Distance Blur")
@export var enable_depth_blur: bool = true
@export_range(0.0, 50.0, 1.0) var blur_near_distance: float = 12.0
@export_range(1.0, 300.0, 5.0) var blur_far_distance: float = 70.0
@export_range(0.0, 0.05, 0.001) var max_blur_radius: float = 0.015

@export_group("Atmospheric Animation")
@export var enable_animation: bool = true
@export_range(0.0, 3.0, 0.05) var animation_speed: float = 0.6
@export_range(1.0, 20.0, 0.5) var animation_scale: float = 6.0
@export_range(0.0, 0.6, 0.02) var animation_intensity: float = 0.20
@export_range(0.0, 0.5, 0.01) var animation_blur_radius: float = 0.15

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var default_sampler: RID
var ubo: RID
var light_source: DirectionalLight3D = null
const UBO_SIZE: int = 176 # 11 vec4s = 44 floats = 176 bytes (std140)

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true

func _cleanup_gpu_resources() -> void:
	if not rd:
		return
	if pipeline.is_valid():
		rd.free_rid(pipeline)
		pipeline = RID()
	if shader.is_valid():
		rd.free_rid(shader)
		shader = RID()
	if default_sampler.is_valid():
		rd.free_rid(default_sampler)
		default_sampler = RID()
	if ubo.is_valid():
		rd.free_rid(ubo)
		ubo = RID()

func _ensure_pipeline() -> bool:
	if not rd:
		rd = RenderingServer.get_rendering_device()
		if not rd:
			return false

	if not default_sampler.is_valid():
		var sampler_state := RDSamplerState.new()
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		default_sampler = rd.sampler_create(sampler_state)

	if not ubo.is_valid():
		var buffer_data := PackedByteArray()
		buffer_data.resize(UBO_SIZE)
		ubo = rd.uniform_buffer_create(UBO_SIZE, buffer_data)

	if not shader.is_valid():
		var shader_file: RDShaderFile = ResourceLoader.load("res://shaders/compositor/godray.glsl", "", ResourceLoader.CACHE_MODE_REPLACE) as RDShaderFile
		if not shader_file:
			push_error("GodrayCompositorEffect: Failed to load res://shaders/compositor/godray.glsl")
			return false
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		if not spirv:
			push_error("GodrayCompositorEffect: Failed to get SPIRV from godray.glsl")
			return false
		shader = rd.shader_create_from_spirv(spirv)
		if not shader.is_valid():
			push_error("GodrayCompositorEffect: Failed to compile compute shader")
			return false

	if not pipeline.is_valid() and shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
		if not pipeline.is_valid():
			push_error("GodrayCompositorEffect: Failed to create compute pipeline")
			return false

	return true

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
	if not enabled or p_effect_callback_type != effect_callback_type:
		return

	if not _ensure_pipeline():
		return

	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if not render_scene_buffers:
		return

	var render_scene_data: RenderSceneData = p_render_data.get_render_scene_data()
	if not render_scene_data:
		return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return

	# Auto-detect world light if needed
	if not is_instance_valid(light_source) or not _is_valid_world_light(light_source):
		_auto_detect_light()

	if not is_instance_valid(light_source) or not light_source.is_inside_tree():
		return

	# Vector pointing from ground towards the sun in the sky (+basis.z)
	var sun_dir: Vector3 = light_source.global_transform.basis.z.normalized()
	if invert_direction:
		sun_dir = -sun_dir

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var cam: Camera3D = null
	var vp_size: Vector2 = Vector2(size)
	if tree and tree.root:
		var vp: Viewport = tree.root.get_viewport()
		if vp:
			cam = vp.get_camera_3d()
			var rect_size: Vector2 = vp.get_visible_rect().size
			if rect_size.x > 0.0 and rect_size.y > 0.0:
				vp_size = rect_size

	if not cam and tree and tree.root:
		var cams: Array[Node] = tree.root.find_children("*", "Camera3D", true, false)
		for c: Node in cams:
			var c3d: Camera3D = c as Camera3D
			if c3d and c3d.current and c3d.is_inside_tree():
				cam = c3d
				break

	var screen_uv: Vector2 = Vector2(0.5, 0.5)
	var dot_val: float = 1.0
	var camera_yaw: float = 0.0

	if cam and cam.is_inside_tree():
		var sun_world_pos: Vector3 = cam.global_position + sun_dir * 1000.0
		var is_behind: bool = cam.is_position_behind(sun_world_pos)
		var screen_px: Vector2 = cam.unproject_position(sun_world_pos)
		screen_uv = screen_px / vp_size

		if is_behind:
			screen_uv.y = -absf(screen_uv.y - 0.5) * 0.5 - 0.1
			screen_uv.x = 1.0 - screen_uv.x

		screen_uv.x = clampf(screen_uv.x, -1.0, 2.0)
		screen_uv.y = clampf(screen_uv.y, -1.0, 2.0)

		var cam_forward: Vector3 = -cam.global_transform.basis.z
		dot_val = cam_forward.dot(sun_dir)
		camera_yaw = atan2(cam.global_transform.basis.x.z, cam.global_transform.basis.x.x)
	else:
		var cam_transform: Transform3D = render_scene_data.get_cam_transform()
		var cam_forward: Vector3 = -cam_transform.basis.z
		dot_val = cam_forward.dot(sun_dir)
		var is_behind: bool = dot_val < 0.0

		var proj: Projection = render_scene_data.get_cam_projection()
		var sun_world_pos: Vector3 = cam_transform.origin + sun_dir * 1000.0
		var sun_cam_space: Vector3 = cam_transform.affine_inverse() * sun_world_pos
		var clip: Vector4 = proj * Vector4(sun_cam_space.x, sun_cam_space.y, sun_cam_space.z, 1.0)
		var inv_w: float = 1.0 / maxf(absf(clip.w), 1e-5)
		screen_uv = Vector2((clip.x * inv_w + 1.0) * 0.5, (1.0 - clip.y * inv_w) * 0.5)

		if is_behind:
			screen_uv.y = -absf(screen_uv.y - 0.5) * 0.5 - 0.1
			screen_uv.x = 1.0 - screen_uv.x

		screen_uv.x = clampf(screen_uv.x, -1.0, 2.0)
		screen_uv.y = clampf(screen_uv.y, -1.0, 2.0)
		camera_yaw = atan2(cam_transform.basis.x.z, cam_transform.basis.x.x)

	var normalized_facing: float = clampf((dot_val + 1.0) * 0.5, 0.0, 1.0)
	if facing_falloff_power != 1.0:
		normalized_facing = pow(normalized_facing, facing_falloff_power)
	var facing: float = lerpf(min_facing_intensity, 1.0, normalized_facing)

	# EARLY OUT: Skip dispatch entirely if looking away
	if facing <= 0.001:
		return

	var proj_for_depth: Projection = render_scene_data.get_cam_projection()
	var inv_proj: Projection = proj_for_depth.inverse()
	var time_val: float = Time.get_ticks_msec() / 1000.0

	# Pack 44 floats (11 vec4s = 176 bytes) for UBO std140
	var ubo_floats := PackedFloat32Array([
		# 0. light_and_facing (vec4)
		screen_uv.x, screen_uv.y, facing, time_val,
		# 1. ray_params (vec4)
		float(num_samples), max_ray_length, density, weight,
		# 2. decay_and_exposure (vec4)
		decay, exposure, light_fade_start, light_fade_end,
		# 3. ambient_color (vec4)
		ambient_color.r, ambient_color.g, ambient_color.b, camera_yaw,
		# 4. near_fade_params (vec4)
		near_fade_start, near_fade_end, 1.0 if enable_near_fade else 0.0, 1.0 if enable_near_gradient else 0.0,
		# 5. near_gradient_alpha (vec4)
		near_gradient_bottom_alpha, near_gradient_top_alpha, near_gradient_bottom_y, near_gradient_top_y,
		# 6. near_gradient_curve (vec4)
		near_gradient_curve, 1.0 if enable_depth_blur else 0.0, blur_near_distance, blur_far_distance,
		# 7. depth_blur_and_anim (vec4)
		max_blur_radius, 1.0 if enable_animation else 0.0, animation_scale, animation_intensity,
		# 8. anim_blur_and_speed (vec4)
		animation_blur_radius, animation_speed, 0.0, 0.0,
		# 9. screen_size (vec4)
		float(size.x), float(size.y), 1.0 / float(size.x), 1.0 / float(size.y),
		# 10. inv_proj_zw (vec4)
		inv_proj.z.z, inv_proj.w.z, inv_proj.z.w, inv_proj.w.w
	])
	var ubo_bytes: PackedByteArray = ubo_floats.to_byte_array()
	rd.buffer_update(ubo, 0, ubo_bytes.size(), ubo_bytes)

	var view_count: int = render_scene_buffers.get_view_count()
	for view in range(view_count):
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		var depth_texture: RID = render_scene_buffers.get_depth_layer(view)
		if not color_image.is_valid() or not depth_texture.is_valid():
			continue

		# Uniform set (Set 0)
		var uniform_color := RDUniform.new()
		uniform_color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform_color.binding = 0
		uniform_color.add_id(color_image)

		var uniform_depth := RDUniform.new()
		uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_depth.binding = 1
		uniform_depth.add_id(default_sampler)
		uniform_depth.add_id(depth_texture)

		var uniform_ubo := RDUniform.new()
		uniform_ubo.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		uniform_ubo.binding = 2
		uniform_ubo.add_id(ubo)

		var uniform_set: RID = UniformSetCacheRD.get_cache(shader, 0, [uniform_color, uniform_depth, uniform_ubo])
		if not uniform_set.is_valid():
			continue

		var x_groups: int = int(ceil(float(size.x) / 8.0))
		var y_groups: int = int(ceil(float(size.y) / 8.0))

		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

func _auto_detect_light() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return

	# 1. Search for nodes in group
	if not light_group.is_empty():
		var lights: Array[Node] = tree.get_nodes_in_group(light_group)
		for node: Node in lights:
			if _is_valid_world_light(node):
				light_source = node as DirectionalLight3D
				return

	# 2. Search by explicit name if provided
	if not light_name.is_empty():
		var named_lights: Array[Node] = tree.root.find_children(light_name, "DirectionalLight3D", true, false)
		for node: Node in named_lights:
			if _is_valid_world_light(node):
				light_source = node as DirectionalLight3D
				return

	# 3. Search root tree for any DirectionalLight3D
	var all_lights: Array[Node] = tree.root.find_children("*", "DirectionalLight3D", true, false)
	for node: Node in all_lights:
		if _is_valid_world_light(node):
			light_source = node as DirectionalLight3D
			return

func _is_valid_world_light(node: Node) -> bool:
	if not (node is DirectionalLight3D):
		return false
	if not node.is_inside_tree() or not node.is_visible_in_tree():
		return false
	# Exclude lights that belong to a SubViewport (like 2D HUD character portraits)
	var p: Node = node.get_parent()
	while p:
		if p is SubViewport:
			return false
		p = p.get_parent()
	return true
