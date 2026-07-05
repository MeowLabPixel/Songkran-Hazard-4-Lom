extends Node3D
class_name GunController

@export var pistol_gun: Gun
@export var shotgun_gun: Gun
@export var sniper_gun: Gun
@export var camera: Camera3D

@export_group("Water Tank Settings")
@export var max_water: float = 100.0
@export var current_water: float = 100.0

var guns: Array[Gun] = []
var unlocked_guns: Array[bool] = [true, false, false] # Pistol unlocked by default, Shotgun/Sniper locked
var current_gun_index: int = 0
var current_gun: Gun

func _ready() -> void:
	guns = [pistol_gun, shotgun_gun, sniper_gun]
	for gun in guns:
		if gun:
			if camera:
				gun.camera = camera
			gun.water_tank = self
	switch_gun(0)

func unlock_gun(index: int) -> void:
	if index >= 0 and index < unlocked_guns.size():
		unlocked_guns[index] = true
		print("Gun unlocked at index: ", index)

func switch_gun(index: int) -> void:
	if index < 0 or index >= guns.size():
		return
	
	if not unlocked_guns[index]:
		print("Gun at index ", index, " is locked!")
		return

	current_gun_index = index
	current_gun = guns[index]

	for i in range(guns.size()):
		if guns[i]:
			guns[i].visible = i == current_gun_index

func next_gun() -> void:
	var next_index := (current_gun_index + 1) % guns.size()
	
	# Loop until we find an unlocked gun or we've checked all of them
	var checked_count = 0
	while not unlocked_guns[next_index] and checked_count < guns.size():
		next_index = (next_index + 1) % guns.size()
		checked_count += 1
		
	if unlocked_guns[next_index]:
		switch_gun(next_index)

func get_current_gun() -> Gun:
	return current_gun
