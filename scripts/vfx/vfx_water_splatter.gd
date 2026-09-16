class_name VFXWaterSplatter
extends Node3D

@export var auto_free_delay: float = 3.0
@onready var bubble_small: GPUParticles3D = get_node_or_null("Bubble_Small")

const SPLATTER_SCENE_PATH = "res://Jomp_Folder/VFX_Water/VFX2/vfx_water_splatter.tscn"
static var _cached_scene: PackedScene = null

static func _get_scene() -> PackedScene:
	if not _cached_scene:
		_cached_scene = load(SPLATTER_SCENE_PATH)
	return _cached_scene

static func spawn(tree: SceneTree, pos: Vector3, normal: Vector3 = Vector3.UP, is_player: bool = false, custom_scale: Vector3 = Vector3.ONE, is_crit: bool = false, is_weakpoint: bool = false) -> VFXWaterSplatter:
	if not tree or not tree.current_scene:
		return null
	var scene = _get_scene()
	if not scene:
		return null
	var instance = scene.instantiate() as VFXWaterSplatter
	if not instance:
		return null
	tree.current_scene.add_child(instance)
	instance.global_position = pos
	if normal.length_squared() > 0.01:
		var up = Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		instance.look_at(instance.global_position + normal, up)
	instance.scale = custom_scale
	instance.play(is_player, is_crit, is_weakpoint)
	return instance

func adjust_for_surface(custom_normal: Vector3 = Vector3.ZERO) -> void:
	if not bubble_small or not is_instance_valid(bubble_small):
		bubble_small = get_node_or_null("Bubble_Small")
	if not bubble_small or not bubble_small.process_material:
		return

	var normal: Vector3
	if custom_normal.length_squared() > 0.01:
		normal = custom_normal.normalized()
	else:
		normal = -global_transform.basis.z.normalized()

	# Detect ground / floor hits (surface normal pointing largely upwards)
	var is_ground: bool = normal.y > 0.6

	var mat = bubble_small.process_material.duplicate() as ParticleProcessMaterial
	if not mat:
		return

	if is_ground:
		# Ground / floor splash: splash upward and radially in all 360-degree angles
		mat.direction = Vector3(0, 0, -1)
		mat.spread = 70.0
		mat.flatness = 0.0
		mat.emission_shape_offset = Vector3(0, 0, -0.05)
		mat.initial_velocity_min = 4.5
		mat.initial_velocity_max = 6.0
	else:
		# Wall / Zombie / vertical splash: keep original upward spray along surface
		mat.direction = Vector3(0, 10, -1)
		mat.spread = 15.0
		mat.flatness = 0.36
		mat.emission_shape_offset = Vector3(0, 0, -0.3)
		mat.initial_velocity_min = 5.0
		mat.initial_velocity_max = 6.0

	bubble_small.process_material = mat

func play(is_player: bool = false, is_crit: bool = false, is_weakpoint: bool = false) -> void:
	if not is_inside_tree():
		return

	# Adjust Bubble_Small particle material based on surface orientation
	adjust_for_surface()

	var crit_node = find_child("HitCore_Crit", true, false)
	var wind_node = find_child("Wind", true, false)
	var norm_nodes: Array = []
	for n_name in ["HitCore_Normal", "HitCore", "Hitsub"]:
		var found = find_child(n_name, true, false)
		if found:
			norm_nodes.append(found)

	# Collect any sub_emitter targets so they aren't directly emitted
	var sub_emitters: Array = []
	for p in find_children("*", "GPUParticles3D", true, false):
		if p is GPUParticles3D and p.sub_emitter != ^"":
			var target = p.get_node_or_null(p.sub_emitter)
			if target:
				sub_emitters.append(target)

	# Trigger all appropriate particles
	for child in find_children("*", "GPUParticles3D", true, false):
		if child is GPUParticles3D:
			if sub_emitters.has(child):
				continue

			# Crit vs Normal filtering
			if is_crit and norm_nodes.has(child):
				child.emitting = false
				if "visible" in child:
					child.visible = false
				continue
			elif not is_crit and (child == crit_node or (crit_node and crit_node.is_ancestor_of(child))):
				child.emitting = false
				if "visible" in child:
					child.visible = false
				continue
			elif child == wind_node or (wind_node and wind_node.is_ancestor_of(child)):
				if is_weakpoint:
					if "visible" in child:
						child.visible = true
					child.restart()
					child.emitting = true
				else:
					child.emitting = false
					if "visible" in child:
						child.visible = false
				continue

			if "visible" in child:
				child.visible = true
			child.restart()
			child.emitting = true

	# Trigger AnimationPlayers
	for ap in find_children("*", "AnimationPlayer", true, false):
		if ap is AnimationPlayer:
			if ap.has_animation("Muzzle"):
				ap.play("Muzzle")
			elif ap.get_animation_list().size() > 0:
				ap.play(ap.get_animation_list()[0])

	var tree = get_tree()
	if tree:
		tree.create_timer(auto_free_delay).timeout.connect(func():
			if is_instance_valid(self):
				queue_free()
		)
