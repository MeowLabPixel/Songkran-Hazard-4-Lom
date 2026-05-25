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

func switch_gun(index: int) -> void:
	if index < 0 or index >= guns.size():
		return

	current_gun_index = index
	current_gun = guns[index]

	for i in range(guns.size()):
		if guns[i]:
			guns[i].visible = i == current_gun_index

func next_gun() -> void:
	var next_index := current_gun_index + 1
	if next_index >= guns.size():
		next_index = 0

	switch_gun(next_index)

func get_current_gun() -> Gun:
	return current_gun
