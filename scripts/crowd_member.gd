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
@export var balloon_throw_anim_name: String = "Balloone Zombie/Balloone Zombie equip and throw"
@export var balloon_throw_release_time: float = 1.8
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

# Row & Optimization State
var crowd_manager: Node = null
var crowd_row: int = 0
var is_row_active: bool = true
var editor_performance_mode: bool = false
var member_index: int = 0
var _anim_accumulated_delta: float = 0.0
var cached_meshes: Array[MeshInstance3D] = []
var cached_rids: Array[RID] = []

# Hitbox Dynamic LOD State
enum HitboxMode { OFF, CHEST, FULL }
var _current_hitbox_mode: HitboxMode = HitboxMode.OFF
var _cached_hitbox_areas: Array[Area3D] = []
var _cached_chest_area: Area3D = null
var _full_hitbox_timer: float = 0.0
const FULL_HITBOX_HOLD_DURATION: float = 0.75

# Internal references
var skeleton: Skeleton3D = null
var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null
var npc_gun: Node3D = null
var gun_spawn_point: Node3D = null
var attached_balloon: Node3D = null
var hit_reaction_modifier: EnemyHitReactionModifier = null
var hitboxes: Node3D = null
var _turn_tween: Tween = null

func set_row_active(active: bool) -> void:
	if is_row_active == active:
		return
	is_row_active = active
	if not active:
		if anim_player:
			anim_player.pause()
			anim_player.active = false
		set_hitbox_mode(HitboxMode.OFF)
	else:
		if anim_player:
			anim_player.active = true
			if anim_player.current_animation != "" and anim_player.has_animation(anim_player.current_animation):
				if not anim_player.is_playing():
					anim_player.play(anim_player.current_animation)
			else:
				resume_base_loop()
		set_hitbox_mode(HitboxMode.CHEST)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_row_active or not anim_player or not anim_player.active:
		return

	# If performing an action (shooting, throwing balloon, hit reaction) or front row: step every frame
	if is_performing_action or _current_hitbox_mode == HitboxMode.FULL or crowd_row == 0:
		if _anim_accumulated_delta > 0.0:
			anim_player.advance(_anim_accumulated_delta + delta)
			_anim_accumulated_delta = 0.0
		else:
			anim_player.advance(delta)
		return

	_anim_accumulated_delta += delta
	var frame_idx: int = Engine.get_process_frames()
	var should_step: bool = false

	if crowd_row == 1: # MIDDLE ROW: step every 2nd frame, staggered across members
		should_step = ((frame_idx + member_index) % 2 == 0)
	elif crowd_row == 2: # BACK ROW: step every 3rd frame, staggered across members
		should_step = ((frame_idx + member_index) % 3 == 0)
	else:
		should_step = true

	if should_step:
		anim_player.advance(_anim_accumulated_delta)
		_anim_accumulated_delta = 0.0

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _current_hitbox_mode == HitboxMode.FULL:
		_full_hitbox_timer -= delta
		if _full_hitbox_timer <= 0.0:
			set_hitbox_mode(HitboxMode.CHEST if is_row_active else HitboxMode.OFF)

func request_full_hitboxes() -> void:
	_full_hitbox_timer = FULL_HITBOX_HOLD_DURATION
	if _current_hitbox_mode != HitboxMode.FULL:
		set_hitbox_mode(HitboxMode.FULL)

func ensure_chest_hitbox_active() -> void:
	if _current_hitbox_mode == HitboxMode.OFF:
		set_hitbox_mode(HitboxMode.CHEST)
	elif _current_hitbox_mode == HitboxMode.CHEST and is_instance_valid(_cached_chest_area):
		var hz = _cached_chest_area.get_node_or_null("HitboxZone") as HitboxZone
		if hz:
			hz.sync_now()

func set_hitbox_mode(mode: HitboxMode) -> void:
	_current_hitbox_mode = mode
	match mode:
		HitboxMode.OFF:
			for area in _cached_hitbox_areas:
				_set_area_active(area, false)
		HitboxMode.CHEST:
			for area in _cached_hitbox_areas:
				if area == _cached_chest_area:
					_set_area_active(area, true)
				else:
					_set_area_active(area, false)
		HitboxMode.FULL:
			for area in _cached_hitbox_areas:
				_set_area_active(area, true)

func _set_area_active(area: Area3D, active: bool) -> void:
	if not is_instance_valid(area):
		return
	area.monitorable = active
	for col in area.find_children("*", "CollisionShape3D", true, false):
		var shape = col as CollisionShape3D
		if shape:
			shape.set_deferred("disabled", not active)
	var hz = area.get_node_or_null("HitboxZone") as HitboxZone
	if hz:
		hz.set_physics_process(active)
		if active:
			hz.sync_now()

func _ready() -> void:
	_resolve_nodes()
	if Engine.is_editor_hint():
		if has_meta("is_crowd_preview") or (get_parent() and "preview_in_editor" in get_parent()):
			if hitboxes and is_instance_valid(hitboxes):
				hitboxes.queue_free()
				hitboxes = null
			var col = find_child("CollisionShape3D", false, false) as CollisionShape3D
			if col:
				col.disabled = true
			if skeleton:
				for child in skeleton.get_children():
					if child is BoneAttachment3D and child.name != "HitboxAttachRightHand":
						child.queue_free()
			if attached_balloon and is_instance_valid(attached_balloon):
				attached_balloon.queue_free()
				attached_balloon = null
		return
	_optimize_skeleton_bones()
	_setup_hit_reactions()
	_setup_hitboxes()

func _resolve_nodes() -> void:
	if not is_instance_valid(skeleton):
		skeleton = find_child("GeneralSkeleton", true, false) as Skeleton3D
		if not skeleton:
			for child in find_children("*", "Skeleton3D", true, false):
				skeleton = child as Skeleton3D
				break

	if not is_instance_valid(anim_player):
		anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		anim_player.speed_scale = range_animation_speed if is_armed else dance_animation_speed

	if not is_instance_valid(anim_tree):
		anim_tree = find_child("AnimationTree", true, false) as AnimationTree
	if anim_tree:
		# Disable AnimationTree so we control AnimationPlayer directly via script
		anim_tree.active = false

	if not is_instance_valid(npc_gun):
		npc_gun = find_child("NPCGun", true, false) as Node3D
		if not npc_gun:
			npc_gun = find_child("NPC_Gun", true, false) as Node3D
	if is_instance_valid(npc_gun) and not is_instance_valid(gun_spawn_point):
		if npc_gun.has_method("get_spawn_point"):
			gun_spawn_point = npc_gun.get_spawn_point()
		else:
			gun_spawn_point = npc_gun.find_child("GunSpawnPoint", true, false) as Node3D

	if not is_instance_valid(hitboxes):
		hitboxes = find_child("Hitboxes", true, false) as Node3D

	if not is_instance_valid(attached_balloon):
		attached_balloon = find_child("WaterBalloon", true, false) as Node3D
	if is_instance_valid(attached_balloon):
		# Hand-held balloon is strictly a visual prop before launch; remove its GPUParticles3D
		# children to eliminate hundreds of idle particle systems from GPU memory.
		for child in attached_balloon.find_children("*", "GPUParticles3D", true, false):
			child.queue_free()
		_set_attached_balloon_visible(false)

	# Cache meshes and collision RIDs once to avoid thousands of find_children() calls during gameplay
	cached_meshes.clear()
	for node in find_children("*", "MeshInstance3D", true, false):
		if not is_instance_valid(node):
			continue
		if is_instance_valid(npc_gun) and (node == npc_gun or npc_gun.is_ancestor_of(node)):
			continue
		if is_instance_valid(attached_balloon) and (node == attached_balloon or attached_balloon.is_ancestor_of(node)):
			continue
		if node is MeshInstance3D:
			cached_meshes.append(node)

	cached_rids.clear()
	if self is CollisionObject3D:
		cached_rids.append(get_rid())
	for node in find_children("*", "CollisionObject3D", true, false):
		if is_instance_valid(node) and (node is CollisionObject3D):
			cached_rids.append(node.get_rid())

func _optimize_skeleton_bones() -> void:
	if not skeleton or Engine.is_editor_hint():
		return
	var bone_count = skeleton.get_bone_count()
	if bone_count <= 40:
		return

	var keep_bones: Dictionary = {}
	for b in range(bone_count):
		var b_name = skeleton.get_bone_name(b)
		if b_name.begins_with("DEF-") or b_name in ["root", "Root", "torso", "chest", "Hips"]:
			var curr = b
			while curr != -1 and not keep_bones.has(curr):
				keep_bones[curr] = true
				curr = skeleton.get_bone_parent(curr)

	for child in skeleton.get_children():
		if child is BoneAttachment3D and child.bone_idx >= 0:
			var curr = child.bone_idx
			while curr != -1 and not keep_bones.has(curr):
				keep_bones[curr] = true
				curr = skeleton.get_bone_parent(curr)

	for b in range(bone_count):
		if not keep_bones.has(b):
			skeleton.set_bone_enabled(b, false)

func _set_attached_balloon_visible(is_vis: bool) -> void:
	if not attached_balloon or not is_instance_valid(attached_balloon):
		return
	attached_balloon.visible = is_vis
	for child in attached_balloon.find_children("*", "GPUParticles3D", true, false):
		var p = child as GPUParticles3D
		if p:
			p.emitting = false

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

	# Crowd members are purely decorative until hit, so keep modifier dormant by default
	hit_reaction_modifier.active = false

func _setup_hitboxes() -> void:
	if Engine.is_editor_hint():
		return
	_cached_hitbox_areas.clear()
	_cached_chest_area = null
	for node in find_children("*", "HitboxZone", true, false):
		var hz = node as HitboxZone
		if hz:
			hz.set("_target_entity", self)
			var parent_area = hz.get_parent() as Area3D
			if parent_area:
				parent_area.add_to_group("crowd_hitbox")
				if not _cached_hitbox_areas.has(parent_area):
					_cached_hitbox_areas.append(parent_area)
				if parent_area.name == "HitboxChest" or parent_area.name == "HitboxBody":
					_cached_chest_area = parent_area
	if _cached_chest_area == null and not _cached_hitbox_areas.is_empty():
		_cached_chest_area = _cached_hitbox_areas[0]

	set_hitbox_mode(HitboxMode.CHEST if is_row_active else HitboxMode.OFF)

func setup_member(armed: bool, material: Material, config: Dictionary = {}) -> void:
	_resolve_nodes()
	if not Engine.is_editor_hint():
		_setup_hit_reactions()
		_setup_hitboxes()

	for k in config:
		if k in self:
			set(k, config[k])

	is_armed = armed and enable_water_gun
	if is_armed:
		if is_instance_valid(npc_gun):
			npc_gun.visible = true
		if attached_balloon and is_instance_valid(attached_balloon):
			attached_balloon.queue_free()
			attached_balloon = null
	else:
		if npc_gun and is_instance_valid(npc_gun):
			npc_gun.queue_free()
			npc_gun = null
			gun_spawn_point = null

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
	for mesh_inst in cached_meshes:
		if not is_instance_valid(mesh_inst):
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

func _get_armed_anim() -> String:
	if not anim_player:
		return ""
	var candidates: Array[String] = [
		reload_anim_name,
		"Range Zombie  ReloadLoop",
		"Range Zombie reload Loop",
		"Range Zombie Idle ",
		"Zombie Idle"
	]
	for c in candidates:
		if c != "" and anim_player.has_animation(c):
			return c
	var dances = get_available_dance_animations()
	if not dances.is_empty():
		return dances[0]
	return ""

func _get_dance_anim() -> String:
	if not anim_player:
		return ""
	if current_dance_anim != "" and anim_player.has_animation(current_dance_anim):
		return current_dance_anim
	var dances = get_available_dance_animations()
	if not dances.is_empty():
		current_dance_anim = dances.pick_random()
		return current_dance_anim
	if anim_player.has_animation("Zombie Idle"):
		current_dance_anim = "Zombie Idle"
		return current_dance_anim
	return ""

func start_idle_loop() -> void:
	if not anim_player:
		return

	var target_anim: String = ""
	var speed: float = dance_animation_speed

	if is_armed:
		target_anim = _get_armed_anim()
		speed = range_animation_speed
	elif enable_dance_animation:
		target_anim = _get_dance_anim()
		speed = dance_animation_speed

	if target_anim != "" and anim_player.has_animation(target_anim):
		current_dance_anim = target_anim
		anim_player.speed_scale = speed
		if not Engine.is_editor_hint():
			anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim_player.play(target_anim, cross_fade_time)
		var anim_res = anim_player.get_animation(target_anim)
		if anim_res and anim_res.length > 0.0:
			if Engine.is_editor_hint() and editor_performance_mode:
				anim_player.seek(anim_res.length * 0.5, true)
				anim_player.pause()
				anim_player.active = false
			else:
				anim_player.seek(randf_range(0.0, anim_res.length), true)

func apply_editor_performance_mode(enabled: bool) -> void:
	if not Engine.is_editor_hint():
		return
	editor_performance_mode = enabled
	if not anim_player:
		return
	if enabled:
		var cur_anim = anim_player.current_animation
		if cur_anim == "" and current_dance_anim != "":
			cur_anim = current_dance_anim
		if cur_anim != "" and anim_player.has_animation(cur_anim):
			var anim_res = anim_player.get_animation(cur_anim)
			if anim_res and anim_res.length > 0.0:
				anim_player.seek(anim_res.length * 0.5, true)
		anim_player.pause()
		anim_player.active = false
	else:
		anim_player.active = true
		anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		anim_player.speed_scale = range_animation_speed if is_armed else dance_animation_speed
		resume_base_loop()

func resume_base_loop() -> void:
	if not anim_player:
		return
	if not Engine.is_editor_hint():
		anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if is_armed:
		var target_anim = _get_armed_anim()
		if target_anim != "" and anim_player.has_animation(target_anim):
			current_dance_anim = target_anim
			anim_player.speed_scale = range_animation_speed
			anim_player.play(target_anim, cross_fade_time)
	else:
		if enable_dance_animation:
			var target_anim = _get_dance_anim()
			if target_anim != "" and anim_player.has_animation(target_anim):
				anim_player.speed_scale = dance_animation_speed
				anim_player.play(target_anim, cross_fade_time)

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
	if not is_row_active or is_performing_action or not anim_player or not is_armed:
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
	if not is_row_active or is_performing_action or is_armed:
		return
	is_performing_action = true

	# Smoothly rotate toward target
	_rotate_smoothly_toward(target_pos)

	_set_attached_balloon_visible(true)

	var target_anim = balloon_throw_anim_name
	if not anim_player or not anim_player.has_animation(target_anim):
		if anim_player:
			for cand in ["Balloone Zombie/Balloone Zombie equip and throw", "Balloone Zombie equip and throw", "Balloone Zombie/Balloone Zombie throw", "Balloone Zombie throw"]:
				if anim_player.has_animation(cand):
					target_anim = cand
					break

	if anim_player and anim_player.has_animation(target_anim):
		anim_player.speed_scale = 1.0
		anim_player.play(target_anim, cross_fade_time)
		var anim_len = anim_player.get_animation(target_anim).length
		var release_time = clamp(balloon_throw_release_time, 0.05, anim_len)

		get_tree().create_timer(release_time).timeout.connect(func():
			if is_instance_valid(self):
				_set_attached_balloon_visible(false)
				var spawn_pos = attached_balloon.global_position if attached_balloon else (global_position + Vector3(0, 1.4, 0))
				if on_balloon_release.is_valid():
					on_balloon_release.call(self, spawn_pos, target_pos)
		)

		get_tree().create_timer(anim_len).timeout.connect(func():
			if is_instance_valid(self):
				is_performing_action = false
				resume_base_loop()
		)
	else:
		var spawn_pos = attached_balloon.global_position if attached_balloon else (global_position + Vector3(0, 1.4, 0))
		_set_attached_balloon_visible(false)
		if on_balloon_release.is_valid():
			on_balloon_release.call(self, spawn_pos, target_pos)
		is_performing_action = false
		resume_base_loop()

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

	# Hit reactions only work when all crowd rows are present
	var mgr = crowd_manager if crowd_manager else get_parent()
	if mgr and mgr.has_method("are_all_rows_present"):
		if not mgr.are_all_rows_present():
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

	request_full_hitboxes()

	if hit_reaction_modifier:
		hit_reaction_modifier.active = true

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
