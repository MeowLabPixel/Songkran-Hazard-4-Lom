@tool
class_name OutlineCompositorEffect
extends CompositorEffect

@export_group("Recompile / Debug")
@export var recompile: bool = false:
	set(v):
		if v:
			_cleanup_gpu_resources()
			cached_push_size = 0
			notify_property_list_changed()

@export_group("Outline Color")
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.431)

@export_group("Edge Thresholds")
@export_range(0.001, 2.0, 0.01) var depth_threshold: float = 0.5
@export_range(0.0, 2.0, 0.05) var normal_threshold: float = 1.5
@export_range(0.0, 1.0, 0.05) var normal_smoothing: float = 1.0

@export_group("Thickness & Distance")
@export_range(0.1, 5.0, 0.1) var max_thickness: float = 1.3
@export_range(0.1, 5.0, 0.1) var min_thickness: float = 0.5
@export_range(1.0, 200.0, 1.0) var max_distance: float = 75.0
@export_range(0.1, 20.0, 0.5) var min_distance: float = 2.0

@export_group("Grazing Prevention")
@export_range(0.1, 10.0, 0.5) var grazing_fresnel_power: float = 5.0
@export_range(0.1, 5.0, 0.1) var grazing_angle_mask_power: float = 1.0
@export_range(0.0, 100.0, 5.0) var grazing_angle_modulation_factor: float = 50.0

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var default_sampler: RID
var dummy_normal_texture: RID
var cached_push_size: int = 0

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	needs_normal_roughness = true

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
	if dummy_normal_texture.is_valid():
		rd.free_rid(dummy_normal_texture)
		dummy_normal_texture = RID()
	cached_push_size = 0

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

	if not dummy_normal_texture.is_valid():
		var tf := RDTextureFormat.new()
		tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		tf.width = 1
		tf.height = 1
		tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		var view := RDTextureView.new()
		var byte_data := PackedByteArray([128, 128, 255, 255]) # Flat normal (0, 0, 1)
		dummy_normal_texture = rd.texture_create(tf, view, [byte_data])

	if not shader.is_valid():
		var shader_file: RDShaderFile = ResourceLoader.load("res://shaders/compositor/outline.glsl", "", ResourceLoader.CACHE_MODE_REPLACE) as RDShaderFile
		if not shader_file:
			push_error("OutlineCompositorEffect: Failed to load res://shaders/compositor/outline.glsl")
			return false
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		if not spirv:
			push_error("OutlineCompositorEffect: Failed to get SPIRV from outline.glsl")
			return false
		shader = rd.shader_create_from_spirv(spirv)
		if not shader.is_valid():
			push_error("OutlineCompositorEffect: Failed to compile compute shader")
			return false

	if not pipeline.is_valid() and shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
		if not pipeline.is_valid():
			push_error("OutlineCompositorEffect: Failed to create compute pipeline")
			return false

	return true

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
	if not enabled or p_effect_callback_type != effect_callback_type:
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

	# Inverse projection coefficients
	var proj: Projection = render_scene_data.get_cam_projection()
	var inv_proj: Projection = proj.inverse()

	# Push constants (std430, 112 bytes = 28 floats)
	var push_data := PackedFloat32Array([
		outline_color.r, outline_color.g, outline_color.b, outline_color.a,
		depth_threshold, normal_threshold, normal_smoothing, 1.0,
		min_distance, max_distance, min_thickness, max_thickness,
		float(size.x), float(size.y), 1.0 / float(size.x), 1.0 / float(size.y),
		inv_proj.z.z, inv_proj.w.z, inv_proj.z.w, inv_proj.w.w,
		inv_proj.x.x, inv_proj.y.y, 0.0, 0.0,
		grazing_fresnel_power, grazing_angle_mask_power, grazing_angle_modulation_factor, 0.0
	])
	var push_bytes: PackedByteArray = push_data.to_byte_array()

	# Auto-rebuild pipeline if push constant byte size changed or pipeline is invalid
	if cached_push_size != push_bytes.size() or not pipeline.is_valid():
		_cleanup_gpu_resources()
		if not _ensure_pipeline():
			return
		cached_push_size = push_bytes.size()

	var view_count: int = render_scene_buffers.get_view_count()
	for view in range(view_count):
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		var depth_texture: RID = render_scene_buffers.get_depth_layer(view)
		if not color_image.is_valid() or not depth_texture.is_valid():
			continue

		var normal_texture: RID = dummy_normal_texture
		var has_normals: float = 0.0
		if render_scene_buffers.has_texture("forward_clustered", "normal_roughness"):
			normal_texture = render_scene_buffers.get_texture("forward_clustered", "normal_roughness")
			has_normals = 1.0
		elif render_scene_buffers.has_texture("render_buffers", "normal_roughness"):
			normal_texture = render_scene_buffers.get_texture("render_buffers", "normal_roughness")
			has_normals = 1.0

		# Update has_normals in push constant if needed
		if has_normals < 0.5:
			push_data[7] = 0.0
			push_bytes = push_data.to_byte_array()

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

		var uniform_normal := RDUniform.new()
		uniform_normal.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_normal.binding = 2
		uniform_normal.add_id(default_sampler)
		uniform_normal.add_id(normal_texture)

		var uniform_set: RID = UniformSetCacheRD.get_cache(shader, 0, [uniform_color, uniform_depth, uniform_normal])
		if not uniform_set.is_valid():
			continue

		# Dispatch 8x8 workgroups
		var x_groups: int = int(ceil(float(size.x) / 8.0))
		var y_groups: int = int(ceil(float(size.y) / 8.0))

		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
