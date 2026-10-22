@tool
class_name CrowdMember
extends CharacterBody3D

signal enemy_hit(hit_data: Dictionary)

@export_group("Toggles")
@export var enable_dance_animation: bool = true
@export var enable_water_gun: bool = true
@export var enable_hit_reaction: bool = true
@export var enable_hit_animation: bool = false
@export var enable_hit_from_player: bool = true
@export var enable_hit_from_crowd: bool = true

@export_group("Audio")
@export var enable_audio: bool = true:
	set(val):
		enable_audio = val
		_apply_audio_state()
@export var enable_animation_sounds: bool = true:
	set(val):
		enable_animation_sounds = val
		_apply_audio_state()

@export_group("Animation")
@export_range(0.1, 3.0, 0.05) var dance_animation_speed: float = 1.0
@export_range(0.1, 3.0, 0.05) var range_animation_speed: float = 1.0
@export var cross_fade_time: float = 0.25
@export var turn_duration: float = 0.4
@export var reload_anim_name: String = "Range Zombie  ReloadLoop"
@export var shot_anim_name: String = "Range Zombie  shot"
@export var shot_fire_time: float = 3.44
@export var dance_anim_names: Array[String] = [
	"Dance Animation Male/Dance 1",
	"Dance Animation Male/Dance 2",
	"Dance Animation Male/Dance Blue",
	"Dance Animation Male/Dance orange"
]

@export_group("Hit Reaction Spring Settings")
@export var hit_reaction_multiplier: float = 1.0
@export var head_reaction_stiffness: float = 300.0
@export var head_reaction_damping: float = 18.0
@export var head_reaction_force: float = -20.0
@export var body_reaction_stiffness: float = 240.0
@export var body_reaction_damping: float = 16.0
@export var body_reaction_force: float = -14.0
@export var arms_reaction_stiffness: float = 220.0
@export var arms_reaction_damping: float = 16.0
@export var arms_reaction_force: float = -14.0
@export var legs_reaction_stiffness: float = 240.0
@export var legs_reaction_damping: float = 18.0
@export var legs_reaction_force: float = -10.0

var is_armed: bool = false
var is_performing_action: bool = false
var current_dance_anim: String = ""

# Internal references
var skeleton: Skeleton3D = null
var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null
var npc_gun: Node3D = null
var gun_spawn_point: Node3D = null
var hit_reaction_modifier: EnemyHitReactionModifier = null
var hitboxes: Node3D = null
var _turn_tween: Tween = null

func _ready() -> void:
	_resolve_nodes()
	if Engine.is_editor_hint():
		return
	_setup_hit_reactions()
	_setup_hitboxes()

func _resolve_nodes() -> void:
	if not skeleton:
		skeleton = find_child("GeneralSkeleton", true, false) as Skeleton3D
		if not skeleton:
			for child in find_children("*", "Skeleton3D", true, false):
				skeleton = child as Skeleton3D
				break

	if not anim_player:
		anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		anim_player.speed_scale = range_animation_speed if is_armed else dance_animation_speed

	if not anim_tree:
		anim_tree = find_child("AnimationTree", true, false) as AnimationTree
	if anim_tree:
		# Disable AnimationTree so we control AnimationPlayer directly via script
		anim_tree.active = false

	if not npc_gun:
		npc_gun = find_child("NPCGun", true, false) as Node3D
		if not npc_gun:
			npc_gun = find_child("NPC_Gun", true, false) as Node3D
	if npc_gun and not gun_spawn_point:
		if npc_gun.has_method("get_spawn_point"):
			gun_spawn_point = npc_gun.get_spawn_point()
		else:
			gun_spawn_point = npc_gun.find_child("GunSpawnPoint", true, false) as Node3D

	if not hitboxes:
		hitboxes = find_child("Hitboxes", true, false) as Node3D

func _setup_hit_reactions() -> void:
	if Engine.is_editor_hint() or not enable_hit_reaction or not skeleton:
		return

	hit_reaction_modifier = skeleton.get_node_or_null("EnemyHitReactionModifier") as EnemyHitReactionModifier
	if not hit_reaction_modifier:
		hit_reaction_modifier = EnemyHitReactionModifier.new()
		hit_reaction_modifier.name = "EnemyHitReactionModifier"
		hit_reaction_modifier.enemy = self
		hit_reaction_modifier.reaction_multiplier = hit_reaction_multiplier
		
		hit_reaction_modifier.head_stiffness = head_reaction_stiffness
		hit_reaction_modifier.head_damping = head_reaction_damping
		hit_reaction_modifier.head_force = head_reaction_force
		
		hit_reaction_modifier.body_stiffness = body_reaction_stiffness
		hit_reaction_modifier.body_damping = body_reaction_damping
		hit_reaction_modifier.body_force = body_reaction_force
		
		hit_reaction_modifier.arms_stiffness = arms_reaction_stiffness
		hit_reaction_modifier.arms_damping = arms_reaction_damping
		hit_reaction_modifier.arms_force = arms_reaction_force
		
		hit_reaction_modifier.legs_stiffness = legs_reaction_stiffness
		hit_reaction_modifier.legs_damping = legs_reaction_damping
		hit_reaction_modifier.legs_force = legs_reaction_force
		
		skeleton.add_child(hit_reaction_modifier)
	else:
		hit_reaction_modifier.enemy = self
		hit_reaction_modifier.reaction_multiplier = hit_reaction_multiplier

func _setup_hitboxes() -> void:
	if Engine.is_editor_hint():
		return
	for node in find_children("*", "HitboxZone", true, false):
		var hz = node as HitboxZone
		if hz:
			hz.set("_target_entity", self)
			var parent_area = hz.get_parent() as Area3D
			if parent_area:
				parent_area.add_to_group("crowd_hitbox")

func setup_member(armed: bool, material: Material, config: Dictionary = {}) -> void:
	_resolve_nodes()
	if not Engine.is_editor_hint():
		_setup_hit_reactions()
		_setup_hitboxes()

	for k in config:
		if k in self:
			set(k, config[k])

	is_armed = armed and enable_water_gun
	if npc_gun:
		npc_gun.visible = is_armed

	if material:
		set_crowd_material(material)

	start_idle_loop()
	_apply_audio_state()

func _apply_audio_state() -> void:
	var should_play: bool = enable_audio and enable_animation_sounds
	for child in find_children("*", "AudioStreamPlayer", true, false):
		if child is AudioStreamPlayer:
			child.volume_db = 0.0 if should_play else -80.0
			if not should_play:
				child.stop()
	for child in find_children("*", "AudioStreamPlayer3D", true, false):
		if child is AudioStreamPlayer3D:
			child.volume_db = 0.0 if should_play else -80.0
			if not should_play:
				child.stop()

	if anim_player:
		for anim_name in anim_player.get_animation_list():
			var anim = anim_player.get_animation(anim_name)
			if anim:
				for t in range(anim.get_track_count()):
					if anim.track_get_type(t) == Animation.TYPE_AUDIO:
						anim.track_set_enabled(t, should_play)

func play_footstep() -> void:
	if not (enable_audio and enable_animation_sounds):
		return
	if SoundManager:
		SoundManager.play_3d("zombie_footstep", self, 0.0, -1.0, 1.0)

func play_sound(event_name: String = "") -> void:
	if not (enable_audio and enable_animation_sounds) or event_name == "":
		return
	if SoundManager:
		SoundManager.play_3d(event_name, self, 0.0, -1.0, 1.0)

func set_crowd_material(mat: Material) -> void:
	if not mat:
		return
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_inst = node as MeshInstance3D
		if npc_gun and (mesh_inst == npc_gun or npc_gun.is_ancestor_of(mesh_inst)):
			continue
		mesh_inst.material_override = null
		var count = mesh_inst.get_surface_override_material_count()
		if count > 0:
			for s in range(count):
				mesh_inst.set_surface_override_material(s, mat)
		elif mesh_inst.mesh:
			for s in range(mesh_inst.mesh.get_surface_count()):
				mesh_inst.set_surface_override_material(s, mat)

func get_available_dance_animations() -> Array[String]:
	var list: Array[String] = []
	if not anim_player:
		return list
	var all_anims = anim_player.get_animation_list()
	for d in dance_anim_names:
		if anim_player.has_animation(d):
			list.append(d)
	if list.is_empty():
		for anim in all_anims:
			if "dance" in anim.to_lower():
				list.append(anim)
	return list

func start_idle_loop() -> void:
	if not anim_player:
		return

	if is_armed:
		var target_anim = reload_anim_name
		if not anim_player.has_animation(target_anim):
			if anim_player.has_animation("Range Zombie  ReloadLoop"):
				target_anim = "Range Zombie  ReloadLoop"
			elif anim_player.has_animation("Range Zombie reload Loop"):
				target_anim = "Range Zombie reload Loop"
			elif anim_player.has_animation("Range Zombie Idle "):
				target_anim = "Range Zombie Idle "

		if anim_player.has_animation(target_anim):
			anim_player.speed_scale = range_animation_speed
			anim_player.play(target_anim, cross_fade_time)
			var anim_res = anim_player.get_animation(target_anim)
			if anim_res and anim_res.length > 0.0:
				anim_player.seek(randf_range(0.0, anim_res.length), true)
	else:
		if enable_dance_animation:
			var dances = get_available_dance_animations()
			if dances.size() > 0:
				current_dance_anim = dances.pick_random()
				anim_player.speed_scale = dance_animation_speed
				anim_player.play(current_dance_anim, cross_fade_time)
				var anim_res = anim_player.get_animation(current_dance_anim)
				if anim_res and anim_res.length > 0.0:
					anim_player.seek(randf_range(0.0, anim_res.length), true)

func resume_base_loop() -> void:
	if not anim_player:
		return
	if is_armed:
		var target_anim = reload_anim_name
		if not anim_player.has_animation(target_anim):
			if anim_player.has_animation("Range Zombie  ReloadLoop"):
				target_anim = "Range Zombie  ReloadLoop"
			elif anim_player.has_animation("Range Zombie reload Loop"):
				target_anim = "Range Zombie reload Loop"
			elif anim_player.has_animation("Range Zombie Idle "):
				target_anim = "Range Zombie Idle "
		if anim_player.has_animation(target_anim):
			anim_player.speed_scale = range_animation_speed
			anim_player.play(target_anim, cross_fade_time)
	else:
		if enable_dance_animation and current_dance_anim != "" and anim_player.has_animation(current_dance_anim):
			anim_player.speed_scale = dance_animation_speed
			anim_player.play(current_dance_anim, cross_fade_time)

func _rotate_smoothly_toward(target_pos: Vector3, duration: float = -1.0) -> void:
	var dir = target_pos - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return

	var target_basis = Basis.looking_at(dir.normalized(), Vector3.UP)
	var target_yaw = target_basis.get_euler().y
	var current_yaw = rotation.y
	var diff = wrapf(target_yaw - current_yaw, -PI, PI)
	var t_duration = turn_duration if duration <= 0.0 else duration

	if _turn_tween and _turn_tween.is_valid():
		_turn_tween.kill()

	_turn_tween = create_tween()
	_turn_tween.tween_method(func(val: float):
		rotation.y = val
	, current_yaw, current_yaw + diff, t_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func shoot_at(target_pos: Vector3, on_projectile_release: Callable) -> void:
	if is_performing_action or not anim_player or not is_armed:
		return
	is_performing_action = true

	# Smoothly rotate toward target
	_rotate_smoothly_toward(target_pos)

	var target_anim = shot_anim_name
	if not anim_player.has_animation(target_anim):
		if anim_player.has_animation("Range Zombie shot"):
			target_anim = "Range Zombie shot"
		elif anim_player.has_animation("Range Zombie  shot"):
			target_anim = "Range Zombie  shot"

	if anim_player.has_animation(target_anim):
		var spd = max(range_animation_speed, 0.01)
		anim_player.speed_scale = spd
		anim_player.play(target_anim, cross_fade_time)
		var anim_len = anim_player.get_animation(target_anim).length / spd
		var fire_time = clamp(shot_fire_time / spd, 0.05, anim_len)

		get_tree().create_timer(fire_time).timeout.connect(func():
			if is_instance_valid(self):
				var muzzle_pos = gun_spawn_point.global_position if gun_spawn_point else (global_position + Vector3(0, 1.2, 0))
				if on_projectile_release.is_valid():
					on_projectile_release.call(self, muzzle_pos, target_pos)
		)

		get_tree().create_timer(anim_len).timeout.connect(func():
			if is_instance_valid(self):
				is_performing_action = false
				resume_base_loop()
		)
	else:
		var muzzle_pos = gun_spawn_point.global_position if gun_spawn_point else (global_position + Vector3(0, 1.2, 0))
		if on_projectile_release.is_valid():
			on_projectile_release.call(self, muzzle_pos, target_pos)
		is_performing_action = false
		resume_base_loop()

func throw_balloon_at(target_pos: Vector3, on_balloon_release: Callable) -> void:
	if is_performing_action:
		return
	is_performing_action = true

	# Smoothly rotate toward target
	_rotate_smoothly_toward(target_pos)

	var spawn_pos = global_position + Vector3(0, 1.4, 0)
	if on_balloon_release.is_valid():
		on_balloon_release.call(self, spawn_pos, target_pos)

	get_tree().create_timer(0.4).timeout.connect(func():
		if is_instance_valid(self):
			is_performing_action = false
			resume_base_loop()
	)

func get_hit_animation_for_zone(zone: String) -> String:
	match zone.to_lower():
		"head", "weakpoint":
			return "HIT head act 1 - when get hit"
		"left_arm", "hitboxupperleftarm", "hitboxleftarm", "hitboxlefthand":
			return "HIT Left arm"
		"right_arm", "hitboxupperrightarm", "hitboxrightarm", "hitboxrighthand":
			if anim_player and anim_player.has_animation("HIT Right Arm"):
				return "HIT Right Arm"
			return "HIT  Right Arm"
		"left_leg", "left_foot", "hitboxleftthigh", "hitboxleftshin", "hitboxleftfoot":
			return "Hit Leg act 1 Slipping"
		"right_leg", "right_foot", "hitboxrightthigh", "hitboxrightshin", "hitboxrightfoot":
			return "Hit RightLeg act 1 Slipping"
		_:
			return "HIT Body"

func take_hit(hit_data: Dictionary) -> void:
	if not enable_hit_reaction:
		return

	var is_from_crowd = hit_data.get("from_crowd", false)
	var is_from_player = false
	if not is_from_crowd:
		var source = hit_data.get("source")
		if source and (source.is_in_group("player") or source.is_in_group("player_projectile") or source.is_in_group("bullet") or source.is_in_group("player_attack")):
			is_from_player = true
		else:
			is_from_player = true

	if is_from_player and not enable_hit_from_player:
		return
	if is_from_crowd and not enable_hit_from_crowd:
		return

	var zone: String = hit_data.get("hit_zone", "body")
	var hit_dir: Vector3 = hit_data.get("hit_direction", Vector3.ZERO)

	if hit_dir == Vector3.ZERO:
		var hit_pos = hit_data.get("position", global_position)
		var source = hit_data.get("source")
		if source and is_instance_valid(source) and source is Node3D:
			hit_dir = (hit_pos - source.global_position).normalized()
		else:
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0 and is_instance_valid(players[0]):
				hit_dir = (hit_pos - players[0].global_position).normalized()
			else:
				hit_dir = -global_transform.basis.z

	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()
	hit_data["hit_direction"] = hit_dir

	# 1. Emit enemy_hit for procedural spring wiggles
	enemy_hit.emit(hit_data)

	# 2. Localized bone juice
	if hit_reaction_modifier and hit_reaction_modifier.has_method("trigger_bone_juice"):
		if zone in ["head", "left_foot", "left_leg", "right_foot", "right_leg"]:
			hit_reaction_modifier.trigger_bone_juice(zone, hit_dir, 0.35, 1.15, 1.175, 0.0, 30.0)

	# 3. Optional hit animation
	if enable_hit_animation and anim_player and not is_performing_action:
		var hit_anim = get_hit_animation_for_zone(zone)
		if anim_player.has_animation(hit_anim):
			is_performing_action = true
			anim_player.play(hit_anim, 0.1)
			var anim_len = anim_player.get_animation(hit_anim).length
			var return_delay = min(anim_len, 0.45)
			get_tree().create_timer(return_delay).timeout.connect(func():
				if is_instance_valid(self):
					is_performing_action = false
					resume_base_loop()
			)
