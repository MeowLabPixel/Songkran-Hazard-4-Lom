@tool
class_name ScreenspaceGodray
extends MeshInstance3D

## Optional explicit reference to the scene's DirectionalLight3D.
## If null or invalid, the script automatically searches the active scene for the main world DirectionalLight3D.
@export var light_source: DirectionalLight3D

## Invert the direction vector if your scene's directional light orientation requires it.
@export var invert_direction: bool = false

@export_group("Directional Visibility")
## Minimum baseline intensity of godrays when facing away from the sun (0.0 = completely disappears, 1.0 = equal brightness from all angles).
@export_range(0.0, 1.0, 0.05) var min_facing_intensity: float = 0.35

## How smoothly rays transition from facing the sun to facing away (1.0 = linear, <1.0 = broader, >1.0 = sharper).
@export_range(0.1, 2.0, 0.05) var facing_falloff_power: float = 1.0

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	if not Engine.is_editor_hint():
		_auto_detect_light()

func _process(_delta: float) -> void:
	if not is_inside_tree():
		return

	# If current light_source is invalid or inside a SubViewport (e.g. HUD portrait), clear and re-detect
	if not is_instance_valid(light_source) or not _is_valid_world_light(light_source):
		_auto_detect_light()

	if not is_instance_valid(light_source) or not light_source.is_inside_tree():
		set_instance_shader_parameter("sun_facing", 0.0)
		return

	var vp: Viewport = get_viewport()
	if not vp:
		return

	var cam: Camera3D = vp.get_camera_3d()
	if not cam:
		cam = get_parent() as Camera3D
	if not cam or not cam.is_inside_tree():
		set_instance_shader_parameter("sun_facing", 0.0)
		return

	# Vector pointing from ground towards the sun in the sky (+basis.z)
	var sun_dir: Vector3 = light_source.global_transform.basis.z.normalized()
	if invert_direction:
		sun_dir = -sun_dir

	var cam_forward: Vector3 = -cam.global_transform.basis.z
	var dot_val: float = cam_forward.dot(sun_dir)

	var vp_size: Vector2 = vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var sun_world_pos: Vector3 = cam.global_position + sun_dir * 1000.0
	var is_behind: bool = cam.is_position_behind(sun_world_pos)
	var screen_px: Vector2 = cam.unproject_position(sun_world_pos)
	var screen_uv: Vector2 = screen_px / vp_size

	if is_behind:
		# When facing away from the sun, the sun is overhead and behind us.
		# Anchor the ray origin above the top of the screen (negative Y)
		# and flip horizontal azimuth so rays stream forward/downward over our head.
		screen_uv.y = -absf(screen_uv.y - 0.5) * 0.5 - 0.1
		screen_uv.x = 1.0 - screen_uv.x

	# Clamp to prevent extreme stretching when very far off-screen
	screen_uv.x = clampf(screen_uv.x, -1.0, 2.0)
	screen_uv.y = clampf(screen_uv.y, -1.0, 2.0)

	# Calculate smooth multidirectional facing curve:
	# dot_val ranges from +1.0 (looking directly at sun) to -1.0 (looking completely away).
	# normalized_facing maps [-1.0, 1.0] to [0.0, 1.0].
	var normalized_facing: float = clampf((dot_val + 1.0) * 0.5, 0.0, 1.0)
	if facing_falloff_power != 1.0:
		normalized_facing = pow(normalized_facing, facing_falloff_power)

	var facing: float = lerpf(min_facing_intensity, 1.0, normalized_facing)

	set_instance_shader_parameter("light_screen_pos", screen_uv)
	set_instance_shader_parameter("sun_facing", facing)

func _auto_detect_light() -> void:
	if not is_inside_tree():
		return

	# 1. Search for nodes in group "sun_light"
	var lights: Array[Node] = get_tree().get_nodes_in_group("sun_light")
	for node: Node in lights:
		if _is_valid_world_light(node):
			light_source = node as DirectionalLight3D
			return

	# 2. Search root / current scene for any valid DirectionalLight3D
	var scene_root: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	if scene_root:
		var found: DirectionalLight3D = _find_first_directional_light(scene_root)
		if found:
			light_source = found

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

func _find_first_directional_light(node: Node) -> DirectionalLight3D:
	if _is_valid_world_light(node):
		return node as DirectionalLight3D
	for child: Node in node.get_children():
		var found: DirectionalLight3D = _find_first_directional_light(child)
		if found:
			return found
	return null
