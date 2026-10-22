@tool
class_name NPCGun
extends Node3D

@export_group("VFX Scenes")
@export var shot_vfx_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterLine.tscn")
@export var muzzle_vfx_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterMuzzle.tscn")
@export var hit_vfx_scene: PackedScene = preload("res://Jomp_Folder/VFX_Water/VFX2/vfx_water_splatter.tscn")

@export_group("VFX Customization")
@export var muzzle_scale: Vector3 = Vector3(0.2, 0.2, 0.2)
@export var muzzle_offset: Vector3 = Vector3.ZERO
@export var impact_scale: Vector3 = Vector3(0.4, 0.4, 0.4)
@export var impact_offset: Vector3 = Vector3.ZERO
@export var muzzle_animation_name: String = "Muzzle"
@export var impact_animation_name: String = "Muzzle"

func get_spawn_point() -> Node3D:
	var sp: Node3D = find_child("GunSpawnPoint", true, false) as Node3D
	return sp if sp else self
