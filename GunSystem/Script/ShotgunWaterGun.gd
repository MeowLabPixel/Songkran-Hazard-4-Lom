extends Gun
class_name ShotgunWaterGun

@export var outer_pellet_count: int = 8
@export var center_pellet_damage: float = 3.75
@export var outer_pellet_damage: float = 0.65
@export var center_pellet_head_multiplier: float = 1.6
@export var center_pellet_body_multiplier: float = 1.0
@export var outer_pellet_head_multiplier: float = 1.2
@export var outer_pellet_body_multiplier: float = 1.0
@export var vertical_spread_multiplier: float = 0.25
@export var takedown_range_multiplier: float = 1.35
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

func get_effective_takedown_range(player: Node) -> float:
	# Base takedown attack hit radius: 1.8m (1.5m arc + 0.3m capsule radius)
	var base_radius = 1.8
	if is_instance_valid(player):
		var td_hitbox = player.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/PlayerTakedownHitBox/TakedownHitbox")
		if td_hitbox:
			base_radius = 1.8
	return base_radius * takedown_range_multiplier

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
		var burst_count = outer_pellet_count

		# First burst: accurate center stream + surrounding burst
		fire_pellet(0.0, center_pellet_damage * 1.2, true)
		for i in range(burst_count):
			fire_pellet(-1.0, outer_pellet_damage * 1.2, false)

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
		fire_pellet(0.0, center_pellet_damage * 1.2, true)
		for i in range(burst_count):
			fire_pellet(-1.0, outer_pellet_damage * 1.2, false)

		current_spread = old_spread
		is_super_active = false
		air = maxf(0.0, air - super_shot_air_cost)
		on_super_end()
	else:
		# Normal shot: 1 pinpoint accurate high-damage center pellet + outer spread pellets
		fire_pellet(0.0, center_pellet_damage, true)
		for i in range(outer_pellet_count):
			fire_pellet(-1.0, outer_pellet_damage, false)
