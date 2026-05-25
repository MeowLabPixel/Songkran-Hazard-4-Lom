extends Gun
class_name ShotgunWaterGun

@export var pellet_count: int = 5

func fire_projectiles():
	if is_super_active:
		# Super Shot
		var old_spread: float = current_spread
		current_spread = min_spread * 0.5 

		# First burst
		for i in range(pellet_count * 2):
			fire_pellet()

		# Wait
		await get_tree().create_timer(0.2).timeout
		current_spread = min_spread * 0.5

		# Second burst
		for i in range(pellet_count * 2):
			fire_pellet()

		current_spread = old_spread
		is_super_active = false
		on_super_end()
		print("Shotgun DOUBLE Super Blast! Super Ended.")
	else:
		# Normal shot
		for i in range(pellet_count):
			fire_pellet()
