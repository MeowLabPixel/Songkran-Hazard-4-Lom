class_name VFXPowder
extends Node3D

@export var auto_free_delay: float = 2.0
@onready var player_only_vfx: Node3D = get_node_or_null("Player_only_vfx")
@onready var enemies_only_vfx: Node3D = get_node_or_null("Enemies_only_vfx")

const POWDER_SCENE_PATH = "res://Jomp_Folder/VFX_Water/VFX2/vfx_powder.tscn"
static var _cached_scene: PackedScene = null

static func _get_scene() -> PackedScene:
	if not _cached_scene:
		_cached_scene = load(POWDER_SCENE_PATH)
	return _cached_scene

static func spawn(tree: SceneTree, pos: Vector3, normal: Vector3 = Vector3.UP, is_player: bool = false, custom_scale: Vector3 = Vector3.ONE, is_crit: bool = false) -> VFXPowder:
	if not tree or not tree.current_scene:
		return null
	var scene = _get_scene()
	if not scene:
		return null
	var instance = scene.instantiate() as VFXPowder
	if not instance:
		return null
	tree.current_scene.add_child(instance)
	instance.global_position = pos
	if normal.length_squared() > 0.01:
		var up = Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		instance.look_at(instance.global_position + normal, up)
	instance.scale = custom_scale
	instance.play(is_player, is_crit)
	return instance

func play(is_player: bool = false, is_crit: bool = false) -> void:
	if not is_inside_tree():
		return

	# Handle Player_only_vfx
	if is_instance_valid(player_only_vfx):
		player_only_vfx.visible = is_player
		if not is_player:
			for p in player_only_vfx.find_children("*", "GPUParticles3D", true, false):
				if p is GPUParticles3D:
					p.emitting = false

	# Handle Enemies_only_vfx
	if is_instance_valid(enemies_only_vfx):
		enemies_only_vfx.visible = not is_player
		if is_player:
			for p in enemies_only_vfx.find_children("*", "GPUParticles3D", true, false):
				if p is GPUParticles3D:
					p.emitting = false

	var crit_node = find_child("HitCore_Crit", true, false)
	var norm_node = find_child("HitCore_Normal", true, false)

	# Trigger all appropriate particles
	for child in find_children("*", "GPUParticles3D", true, false):
		if child is GPUParticles3D:
			if not is_player and is_instance_valid(player_only_vfx) and (child == player_only_vfx or player_only_vfx.is_ancestor_of(child)):
				continue
			if is_player and is_instance_valid(enemies_only_vfx) and (child == enemies_only_vfx or enemies_only_vfx.is_ancestor_of(child)):
				continue

			# Crit vs Normal filtering
			if is_player:
				if is_crit:
					if child == norm_node or child.name == "HitCore_Normal":
						child.emitting = false
						if "visible" in child:
							child.visible = false
						continue
				else:
					if child == crit_node or child.name == "HitCore_Crit" or (crit_node and crit_node.is_ancestor_of(child)):
						child.emitting = false
						if "visible" in child:
							child.visible = false
						continue
			else:
				if child == crit_node or child.name == "HitCore_Crit" or (crit_node and crit_node.is_ancestor_of(child)):
					child.emitting = false
					if "visible" in child:
						child.visible = false
					continue

			if "visible" in child:
				child.visible = true
			child.restart()
			child.emitting = true

	var anim_player = get_node_or_null("AnimationPlayer")
	if not anim_player:
		for child in get_children():
			if child is AnimationPlayer:
				anim_player = child
				break
	if anim_player and anim_player is AnimationPlayer and anim_player.get_animation_list().size() > 0:
		anim_player.play(anim_player.get_animation_list()[0])

	var tree = get_tree()
	if tree:
		tree.create_timer(auto_free_delay).timeout.connect(func():
			if is_instance_valid(self):
				queue_free()
		)
