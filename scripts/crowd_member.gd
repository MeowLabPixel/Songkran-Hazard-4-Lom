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
		if is_inside_tree() and is_node_ready():
			_apply_audio_state()
@export var enable_animation_sounds: bool = true:
	set(val):
		enable_animation_sounds = val
		if is_inside_tree() and is_node_ready():
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
var is_row_active: bool = false
var editor_performance_mode: bool = false
var member_index: int = 0
var anim_step_interval: int = 1
var _anim_accumulated_delta: float = 0.0
var cached_meshes: Array[MeshInstance3D] = []
var cached_rids: Array[RID] = []

var is_occluded: bool = false
var last_shadow_allowed: int = -1
var _is_setup_done: bool = false
var _nodes_resolved: bool = false

# Hitbox Dynamic LOD State
enum HitboxMode { OFF, CHEST, FULL }
var _current_hitbox_mode: HitboxMode = HitboxMode.OFF
var _cached_hitbox_areas: Array[Area3D] = []
var _cached_hitbox_entries: Array[Dictionary] = []
var _cached_chest_area: Area3D = null
var _cached_chest_entry: Dictionary = {}
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
var _pop_in_tween: Tween = null
var is_popping_out: bool = false

func play_balloon_pop_in(delay: float = 0.0, duration: float = 0.45) -> void:
	if _pop_in_tween and _pop_in_tween.is_valid():
		_pop_in_tween.kill()

	is_popping_out = false
	visible = true
	# Start squashed flat against the ground like a deflated balloon
	scale = Vector3(0.2, 0.02, 0.2)

	_pop_in_tween = create_tween()
	if delay > 0.0:
		_pop_in_tween.tween_interval(delay)

	var t_stretch = duration * 0.65
	var t_bounce = duration * 0.35

	# Phase 1: Rapid inflation stretch upward
	_pop_in_tween.tween_property(self, "scale", Vector3(0.85, 1.25, 0.85), t_stretch)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Phase 2: Elastic overshoot and settle into rest size
	_pop_in_tween.tween_property(self, "scale", Vector3.ONE, t_bounce)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func play_balloon_pop_out(delay: float = 0.0, duration: float = 0.45, on_complete: Callable = Callable()) -> void:
	if _pop_in_tween and _pop_in_tween.is_valid():
		_pop_in_tween.kill()

	is_popping_out = true
	visible = true

	_pop_in_tween = create_tween()
	if delay > 0.0:
		_pop_in_tween.tween_interval(delay)

	var t_anticipate = duration * 0.25
	var t_squash = duration * 0.55
	var t_sink = duration * 0.20

	# Phase 1: Brief anticipatory stretch upward before deflating
	_pop_in_tween.tween_property(self, "scale", Vector3(0.85, 1.25, 0.85), t_anticipate)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Phase 2: Rapid balloon deflation squashing flat into the ground as a wide pancake
	_pop_in_tween.tween_property(self, "scale", Vector3(1.35, 0.03, 1.35), t_squash)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Phase 3: Sink flat into zero on the ground
	_pop_in_tween.tween_property(self, "scale", Vector3.ZERO, t_sink)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_pop_in_tween.tween_callback(func():
		visible = false
		scale = Vector3.ONE
		is_popping_out = false
		if on_complete.is_valid():
			on_complete.call()
	)

func set_row_active(active: bool) -> void:
	if is_row_active == active and is_processing() == active:
		return
	is_row_active = active
	set_process(active)
	if not active:
		set_physics_process(false)
		if anim_player:
			anim_player.pause()
			anim_player.active = false
		set_hitbox_mode(HitboxMode.OFF)
		if hit_reaction_modifier:
			hit_reaction_modifier.active = false
		if _turn_tween and _turn_tween.is_valid():
			_turn_tween.kill()
			is_performing_action = false
	else:
		if anim_player:
			if not Engine.is_editor_hint():
				anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
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

	# If performing an action (shooting, throwing balloon, hit reaction): step full 60 FPS
	if is_performing_action:
		if _anim_accumulated_delta > 0.0:
			anim_player.advance(_anim_accumulated_delta + delta)
			_anim_accumulated_delta = 0.0
		else:
			anim_player.advance(delta)
		return

	if anim_step_interval <= 1:
		if _anim_accumulated_delta > 0.0:
			anim_player.advance(_anim_accumulated_delta + delta)
			_anim_accumulated_delta = 0.0
		else:
			anim_player.advance(delta)
		return

	_anim_accumulated_delta += delta
	var frame_idx: int = Engine.get_process_frames()
	var should_step: bool = false

	if anim_step_interval == 2: # Medium range: step every 2nd frame (30 FPS), staggered across members
		should_step = ((frame_idx + member_index) % 2 == 0)
	elif anim_step_interval == 3: # Step every 3rd frame (20 FPS)
		should_step = ((frame_idx + member_index) % 3 == 0)
	elif anim_step_interval >= 4: # Far range: step every 4th frame (15 FPS), staggered across members
		should_step = ((frame_idx + member_index) % 4 == 0)
	else:
		should_step = true

	if should_step:
		anim_player.advance(_anim_accumulated_delta)
		_anim_accumulated_delta = 0.0

func _physics_process(_delta: float) -> void:
	# Crowd members never need physics ticking
	set_physics_process(false)

func request_full_hitboxes() -> void:
	# No-op for crowd members: unified full-body hitbox already covers head, body, and legs
	ensure_chest_hitbox_active()

func ensure_chest_hitbox_active() -> void:
	if _current_hitbox_mode == HitboxMode.OFF:
		set_hitbox_mode(HitboxMode.CHEST)

func set_hitbox_mode(mode: HitboxMode) -> void:
	if _current_hitbox_mode == mode:
		return
	_current_hitbox_mode = mode
	set_physics_process(false)
	match mode:
		HitboxMode.OFF:
			for entry in _cached_hitbox_entries:
				_set_entry_active(entry, false, false)
		HitboxMode.CHEST, HitboxMode.FULL:
			for entry in _cached_hitbox_entries:
				var is_unified = (entry.get("area") == _cached_chest_area)
				_set_entry_active(entry, is_unified, false)

func _set_entry_active(entry: Dictionary, active_collision: bool, _active_sync: bool) -> void:
	var area: Area3D = entry.get("area")
	if not is_instance_valid(area):
		return
	area.monitoring = false
	area.monitorable = active_collision
	var shape: CollisionShape3D = entry.get("shape")
	if is_instance_valid(shape):
		shape.set_deferred("disabled", not active_collision)
	var hz: HitboxZone = entry.get("zone")
	if is_instance_valid(hz):
		hz.set_physics_process(false)

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
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
	if not _is_setup_done:
		_resolve_nodes()
		_optimize_skeleton_bones()
		_setup_hit_reactions()
		_setup_hitboxes()

func _resolve_nodes() -> void:
	if _nodes_resolved:
		return
	_nodes_resolved = true

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
		if not Engine.is_editor_hint():
			anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

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

	# Prune 15 unused BoneAttachment3D nodes at runtime to eliminate 300 bone matrix calculations per crowd scene
	if skeleton and not Engine.is_editor_hint():
		for child in skeleton.get_children():
			if child is BoneAttachment3D and child.name != "HitboxAttachRightHand":
				child.queue_free()

	# Disable CharacterBody3D capsule collision at runtime (InvisibleWall handles boundary collision)
	var col = find_child("CollisionShape3D", false, false) as CollisionShape3D
	if col and not Engine.is_editor_hint():
		col.disabled = true

func _optimize_skeleton_bones() -> void:
	# In Godot 4, disabling skeleton bones breaks MeshInstance3D Skin bindings and triggers thousands of C++ engine errors per frame.
	return

func _set_attached_balloon_visible(is_vis: bool) -> void:
	if not attached_balloon or not is_instance_valid(attached_balloon):
		return
	attached_balloon.visible = is_vis

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
	_cached_hitbox_entries.clear()
	_cached_chest_area = null
	_cached_chest_entry = {}
	for node in find_children("*", "HitboxZone", true, false):
		var hz = node as HitboxZone
		if hz:
			hz.set("_target_entity", self)
			var parent_area = hz.get_parent() as Area3D
			if parent_area:
				parent_area.add_to_group("crowd_hitbox")
				if not _cached_hitbox_areas.has(parent_area):
					_cached_hitbox_areas.append(parent_area)
					var col_shape: CollisionShape3D = null
					for col in parent_area.find_children("*", "CollisionShape3D", true, false):
						if col is CollisionShape3D:
							col_shape = col
							break
					var entry = { "area": parent_area, "shape": col_shape, "zone": hz }
					_cached_hitbox_entries.append(entry)
					if parent_area.name == "HitboxChest" or parent_area.name == "HitboxBody":
						_cached_chest_area = parent_area
						_cached_chest_entry = entry
	if _cached_chest_area == null and not _cached_hitbox_areas.is_empty():
		_cached_chest_area = _cached_hitbox_areas[0]
		_cached_chest_entry = _cached_hitbox_entries[0]

	# Configure _cached_chest_area as the unified full-body hitbox covering head to toe
	if is_instance_valid(_cached_chest_area):
		_cached_chest_area.top_level = false
		_cached_chest_area.position = Vector3(0.0, 0.9, 0.0)
		_cached_chest_area.rotation = Vector3.ZERO
		var shape_node = _cached_chest_entry.get("shape") as CollisionShape3D
		if is_instance_valid(shape_node):
			shape_node.position = Vector3.ZERO
			shape_node.rotation = Vector3.ZERO
			var full_capsule = CapsuleShape3D.new()
			full_capsule.radius = 0.32
			full_capsule.height = 1.75
			shape_node.shape = full_capsule

	# Free the 15 redundant limb Area3D nodes so only the unified HitboxChest remains in the scene tree
	for entry in _cached_hitbox_entries:
		var area = entry.get("area") as Area3D
		if is_instance_valid(area) and area != _cached_chest_area:
			area.queue_free()

	_cached_hitbox_areas.clear()
	_cached_hitbox_entries.clear()
	if is_instance_valid(_cached_chest_area):
		_cached_hitbox_areas.append(_cached_chest_area)
		_cached_hitbox_entries.append(_cached_chest_entry)

	# Ensure all hitboxes are cleanly disabled on initial spawn
	for entry in _cached_hitbox_entries:
		_set_entry_active(entry, false, false)
	_current_hitbox_mode = HitboxMode.OFF

	if is_row_active:
		set_hitbox_mode(HitboxMode.CHEST)

func setup_member(armed: bool, material: Material, config: Dictionary = {}) -> void:
	_is_setup_done = true
	for k in config:
		if k in self:
			set(k, config[k])

	_resolve_nodes()
	if not Engine.is_editor_hint():
		_optimize_skeleton_bones()
		_setup_hit_reactions()
		_setup_hitboxes()

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
	var hit_pos: Vector3 = hit_data.get("position", Vector3.ZERO)
	var source = hit_data.get("source")
	if hit_pos == Vector3.ZERO and source and is_instance_valid(source) and source is Node3D:
		hit_pos = source.global_position

	# Dynamic height-based zone classification for unified full-body hitbox:
	if hit_pos != Vector3.ZERO:
		var local_y: float = to_local(hit_pos).y
		if local_y >= 1.35:
			zone = "head"
		elif local_y <= 0.65:
			var local_x: float = to_local(hit_pos).x
			zone = "left_leg" if local_x < 0.0 else "right_leg"
		elif zone == "" or zone == "body" or zone == "chest":
			zone = "body"
		hit_data["hit_zone"] = zone

	var hit_dir: Vector3 = hit_data.get("hit_direction", Vector3.ZERO)

	if hit_dir == Vector3.ZERO:
		if hit_pos != Vector3.ZERO and source and is_instance_valid(source) and source is Node3D:
			hit_dir = (hit_pos - source.global_position).normalized()
		else:
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0 and is_instance_valid(players[0]):
				hit_dir = ((hit_pos if hit_pos != Vector3.ZERO else global_position) - players[0].global_position).normalized()
			else:
				hit_dir = -global_transform.basis.z

	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()
	hit_data["hit_direction"] = hit_dir

	if hit_reaction_modifier:
		hit_reaction_modifier.active = true
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(self) and hit_reaction_modifier and not is_performing_action:
				hit_reaction_modifier.active = false
		)

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
					if hit_reaction_modifier:
						hit_reaction_modifier.active = false
					resume_base_loop()
			)
