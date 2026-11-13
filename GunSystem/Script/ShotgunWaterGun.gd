extends Gun
class_name ShotgunWaterGun

@export var outer_pellet_count: int = 12
@export var center_pellet_damage: float = 3.75
@export var outer_pellet_damage: float = 0.43
@export var center_pellet_head_multiplier: float = 1.6
@export var center_pellet_body_multiplier: float = 1.0
@export var outer_pellet_head_multiplier: float = 1.2
@export var outer_pellet_body_multiplier: float = 1.0
@export var vertical_spread_multiplier: float = 0.25
@export var normal_knockdown_range: float = 2.0
@export var special_knockdown_min_pellets: int = 4
@export var special_knockdown_max_range: float = 0.0
@export var falloff_start_dist: float = 2.25
@export var falloff_end_dist: float = 14.0
@export var min_falloff_multiplier: float = 0.25
@export var super_shot_air_cost: float = 60.0

func _ready():
	gun_name = "Water shotgun"
	damage = outer_pellet_damage
	shoot_interval = 0.54
	water_consumption = 5.0
	air_consumption = 30.0
	aim_exit_lock_duration = 0.27
	min_spread = 9.75
	max_spread = 13.0
	current_spread = 13.0
	recoil_pitch = 3.2
	recoil_yaw = 0.8
	camera_fov_kick = 2.8
	camera_shake = 0.08
	mesh_kick_z = 0.18
	mesh_kick_pitch = 0.24
	shoulder_kick_z = 0.16
	shoulder_kick_pitch = 0.20
	crosshair_shot_kick = 81.0

func get_effective_takedown_range(_player: Node) -> float:
	return normal_knockdown_range

func play_shoot_sound(shoot_pos: Vector3) -> void:
	var pitch = randf_range(0.95, 1.05) if (SoundManager and SoundManager.enable_pitch_randomization) else 1.0
	if is_super_active:
		SoundManager.play_3d("Region_Shotgun_SuperShot", shoot_pos, 0.0, -1.0, pitch)
		SoundManager.play_3d("watergun_pistol_Superpump_Shoot_Add", shoot_pos, 0.0, -1.0, pitch)
	else:
		SoundManager.play_3d("watergun_pistol_shoot", shoot_pos, 0.0, -1.0, pitch)

func get_aim_exit_lock_duration() -> float:
	if is_super_active:
		return aim_exit_lock_duration + 0.18
	return aim_exit_lock_duration

func fire_projectiles():
	if is_super_active:
		# Super Shot: 2 bursts with tighter spread, high damage
		var old_spread: float = current_spread
		current_spread = min_spread * 0.6

		# First burst: accurate center stream + surrounding burst
		_fire_shotgun_blast(1.2)

		# Wait
		var tree := get_tree()
		if tree:
			await tree.create_timer(0.18).timeout
		else:
			return
		current_spread = min_spread * 0.6

		# Trigger second burst feedback (arm kick, shoulder kick, camera shake & recoil, reticle kick, sound, character anim)
		var shoot_pos = spawn_point.global_position if spawn_point else global_position
		apply_shot_feedback(shoot_pos)
		trigger_player_shoot_animation()

		# Second burst: accurate center stream + surrounding burst
		_fire_shotgun_blast(1.2)

		current_spread = old_spread
		is_super_active = false
		air = maxf(0.0, air - super_shot_air_cost)
		on_super_end()
	else:
		# Normal shot: 1 pinpoint accurate high-damage center pellet + outer spread pellets
		_fire_shotgun_blast(1.0)

func _fire_shotgun_blast(damage_mult: float = 1.0) -> void:
	var casts: Array[Dictionary] = []
	casts.append({
		"data": _cast_pellet_ray(0.0),
		"damage": center_pellet_damage * damage_mult,
		"is_center": true
	})
	for i in range(outer_pellet_count):
		casts.append({
			"data": _cast_pellet_ray(-1.0),
			"damage": outer_pellet_damage * damage_mult,
			"is_center": false
		})

	var pellet_counts: Dictionary = {}
	for entry in casts:
		var res: Dictionary = entry["data"].get("result", {})
		if not res.is_empty():
			var target = _get_raycast_target(res)
			if target:
				pellet_counts[target] = pellet_counts.get(target, 0) + 1

	for entry in casts:
		var data: Dictionary = entry["data"]
		if data.is_empty():
			continue
		var res: Dictionary = data.get("result", {})
		var count: int = 1
		if not res.is_empty():
			var target = _get_raycast_target(res)
			if target:
				count = pellet_counts.get(target, 1)
		_resolve_pellet_hit(data, entry["damage"], entry["is_center"], count)
