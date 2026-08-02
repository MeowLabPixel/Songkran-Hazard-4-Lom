extends Gun
class_name ShotgunWaterGun

@export var pellet_count: int = 5

func _ready():
	gun_name = "Water shotgun"
	recoil_pitch = 3.2
	recoil_yaw = 0.8
	camera_fov_kick = 2.8
	camera_shake = 0.08
	mesh_kick_z = 0.18
	mesh_kick_pitch = 0.24
	shoulder_kick_z = 0.16
	shoulder_kick_pitch = 0.20

func play_shoot_sound(shoot_pos: Vector3) -> void:
	var pitch = randf_range(0.95, 1.05) if (SoundManager and SoundManager.enable_pitch_randomization) else 1.0
	if is_super_active:
		SoundManager.play_3d("Region_Shotgun_SuperShot", shoot_pos, 0.0, -1.0, pitch)
		SoundManager.play_3d("watergun_pistol_Superpump_Shoot_Add", shoot_pos, 0.0, -1.0, pitch)
	else:
		SoundManager.play_3d("watergun_pistol_shoot", shoot_pos, 0.0, -1.0, pitch)

func fire_projectiles():
	if is_super_active:
		# Super Shot
		var old_spread: float = current_spread
		current_spread = min_spread * 0.5 

		# First burst
		for i in range(pellet_count * 2):
			fire_pellet()

		# Wait
		var tree := get_tree()
		if tree:
			await tree.create_timer(0.2).timeout
		else:
			return
		current_spread = min_spread * 0.5

		# Second burst
		for i in range(pellet_count * 2):
			fire_pellet()

		current_spread = old_spread
		is_super_active = false
		on_super_end()
	else:
		# Normal shot
		for i in range(pellet_count):
			fire_pellet()
