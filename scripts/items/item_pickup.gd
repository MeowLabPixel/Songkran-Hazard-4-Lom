## ItemPickup — generic collectible dropped in the world.
## Spawn via ItemPickup.instantiate_drop() rather than directly.
## Any dropper (enemy, breakable prop, chest) uses the same scene.
class_name ItemPickup
extends Area3D

signal collected(item_type: String, value: int)

## What kind of item this is. "coin", "health", "ammo", etc.
@export var item_type: String = "coin"
## How much of the item is granted on collection.
@export var value: int = 1
## Seconds before this pickup disappears if not collected.
@export var lifetime: float = 30.0
## Optional: assign any Mesh resource here to override the procedural default.
@export var mesh_override: Mesh = null

## Default shape per item_type. Add entries as new types are introduced.
const ITEM_SHAPES: Dictionary = {
	"coin":   "sphere",
	"health": "box",
	"ammo":   "cylinder",
}

const BOB_HEIGHT: float = 0.15
const BOB_SPEED: float  = 2.0
const SPIN_SPEED: float = 1.8

var _lifetime_timer: float = 0.0
var _bob_offset: float = 0.0
@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D

static var _cached_scene: PackedScene = null
static var _cached_bottle_scene: PackedScene = null
var _bottle_instance: Node3D = null

func _ready() -> void:
	add_to_group("object")
	_bob_offset = randf() * TAU
	_apply_mesh()

func _physics_process(delta: float) -> void:
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		queue_free()
		return
	# Bob.
	var bob_y = BOB_HEIGHT * sin(_lifetime_timer * BOB_SPEED + _bob_offset)
	_mesh_instance.position.y = bob_y
	if _bottle_instance:
		_bottle_instance.position.y = bob_y
		_bottle_instance.rotation.y += SPIN_SPEED * delta
	else:
		_mesh_instance.rotation.y += SPIN_SPEED * delta

## Build and assign a mesh + material onto the MeshInstance3D.
func _apply_mesh() -> void:
	if not _mesh_instance:
		return
	if item_type == "bottle":
		if not _cached_bottle_scene:
			_cached_bottle_scene = load("res://DropItem/Bottle.fbx")
		if _cached_bottle_scene:
			_bottle_instance = _cached_bottle_scene.instantiate()
			_bottle_instance.name = "Bottle"
			_bottle_instance.scale = Vector3(0.4, 0.4, 0.4) # Make the bottle smaller (QoL)
			add_child(_bottle_instance)
			_mesh_instance.visible = false
			return
	if mesh_override:
		_mesh_instance.mesh = mesh_override
		return
	var shape: String = ITEM_SHAPES.get(item_type, "sphere")
	_mesh_instance.mesh = _build_mesh(shape)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _type_color()
	mat.metallic   = 0.6
	mat.roughness  = 0.3
	_mesh_instance.material_override = mat

func _build_mesh(shape: String) -> Mesh:
	match shape:
		"sphere":
			var m := SphereMesh.new()
			m.radius = 0.12
			m.height = 0.05
			return m
		"box":
			var m := BoxMesh.new()
			m.size = Vector3(0.18, 0.18, 0.18)
			return m
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius    = 0.08
			m.bottom_radius = 0.08
			m.height        = 0.22
			return m
		_:
			var m := SphereMesh.new()
			m.radius = 0.12
			m.height = 0.24
			return m

func _type_color() -> Color:
	match item_type:
		"coin":   return Color(1.0, 0.85, 0.1)
		"health": return Color(0.9, 0.15, 0.15)
		"ammo":   return Color(0.3, 0.7,  1.0)
		_:        return Color(0.8, 0.8,  0.8)

func _collect() -> void:
	collected.emit(item_type, value)
	if item_type == "bottle":
		var player = get_tree().get_first_node_in_group("player")
		if player:
			var gc = player.get("gun_controller")
			if gc:
				gc.current_water = min(gc.current_water + gc.max_water * 0.30, gc.max_water)
			if player.has_method("spawn_damage_popup"):
				player.spawn_damage_popup("+30% Water", Color(0.1, 0.7, 1.0))
	var mgr = get_node_or_null("/root/ItemManager")
	if mgr:
		mgr.add_item(item_type, value)
	queue_free()

## Static helper: spawn a pickup at a world position and add it to a parent.
## Usage: ItemPickup.instantiate_drop(get_tree().current_scene, position, "coin", 1)
static func instantiate_drop(
		parent: Node,
		world_position: Vector3,
		p_item_type: String,
		p_value: int,
		scatter_radius: float = 0.6,
		p_mesh_override: Mesh = null) -> void:
	if not _cached_scene:
		_cached_scene = load("res://scenes/items/item_pickup.tscn")
	if not _cached_scene:
		push_error("[ItemPickup] Could not load res://scenes/items/item_pickup.tscn")
		return
	var instance: ItemPickup = _cached_scene.instantiate()
	instance.item_type = p_item_type
	instance.value = p_value
	if p_mesh_override:
		instance.mesh_override = p_mesh_override
		
	# Coin drops scatter much closer to each other (QoL)
	var scatter_val = 0.2 if p_item_type == "coin" else scatter_radius
	var offset := Vector3(
		randf_range(-scatter_val, scatter_val),
		0.3,
		randf_range(-scatter_val, scatter_val))
	parent.add_child(instance)
	instance.global_position = world_position + offset
