extends Gun
class_name PistolWaterGun

func _ready():
	gun_name = "Water pistol"
	damage = 2.3
	shoot_interval = 0.27
	air_consumption = 10.0

func _process(delta):
	super._process(delta)
	
	if is_super_active:
		shoot_interval = 0.10
		damage = 1.5
	else:
		shoot_interval = 0.27
		damage = 2.3
