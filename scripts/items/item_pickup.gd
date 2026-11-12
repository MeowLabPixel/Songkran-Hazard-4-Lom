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

@export_group("Highlight Ray")
## If false, hides the highlight ray entirely.
@export var show_highlight_ray: bool = true
## If true, tints the ray beam color dynamically based on the item type (coin, bottle, etc.).
@export var ray_tint_by_type: bool = true
## Ray height when generated procedurally.
@export var ray_height: float = 0.75
## Ray bottom radius when generated procedurally.
@export var ray_radius: float = 0.12
## Opacity multiplier for the ray (0.0 = completely transparent, 1.0 = fully opaque).
@export var ray_opacity: float = 0.4

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

const ITEM_PICKUP_SCENE = preload("res://scenes/items/item_pickup.tscn")
const BOTTLE_SCENE = preload("res://DropItem/Bottle.fbx")
const RAY_SHADER = preload("res://shaders/zelda_highlight_rays.gdshader")
const RAY_NOISE = preload("res://shaders/highlight_ray_noise.tres")

static var _pool: Array[ItemPickup] = []
static var _cached_meshes: Dictionary = {}
static var _cached_materials: Dictionary = {}
static var _cached_ray_mesh: CylinderMesh = null
static var _cached_ray_materials: Dictionary = {}

var _is_pooled: bool = false
var _bottle_instance: Node3D = null
var _ray_instance: MeshInstance3D = null

func _ready() -> void:
	add_to_group("object")
	_bob_offset = randf() * TAU
	_apply_mesh()

func _physics_process(delta: float) -> void:
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		_despawn()
		return
	# Bob.
	var bob_y = BOB_HEIGHT * sin(_lifetime_timer * BOB_SPEED + _bob_offset)
	_mesh_instance.position.y = bob_y
	if _bottle_instance and _bottle_instance.visible:
		_bottle_instance.position.y = bob_y
		_bottle_instance.rotation.y += SPIN_SPEED * delta
	else:
		_mesh_instance.rotation.y += SPIN_SPEED * delta

func _despawn() -> void:
	if not visible:
		return
	visible = false
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if not _pool.has(self):
		_pool.append(self)

func reset_for_drop(p_type: String, p_val: int, p_override: Mesh = null) -> void:
	item_type = p_type
	value = p_val
	mesh_override = p_override
	_lifetime_timer = 0.0
	_bob_offset = randf() * TAU
	visible = true
	set_physics_process(true)
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	_apply_mesh()

## Build and assign a mesh + material onto the MeshInstance3D.
func _apply_mesh() -> void:
	if not _mesh_instance:
		return
	_apply_ray()
	if item_type == "bottle":
		if not _bottle_instance:
			_bottle_instance = BOTTLE_SCENE.instantiate()
			_bottle_instance.name = "Bottle"
			_bottle_instance.scale = Vector3(0.4, 0.4, 0.4) # Make the bottle smaller (QoL)
			add_child(_bottle_instance)
		_mesh_instance.visible = false
		_bottle_instance.visible = true
		return
		
	if _bottle_instance:
		_bottle_instance.visible = false
	_mesh_instance.visible = true
	
	if mesh_override:
		_mesh_instance.mesh = mesh_override
		return
	var shape: String = ITEM_SHAPES.get(item_type, "sphere")
	_mesh_instance.mesh = _get_shared_mesh(shape)
	_mesh_instance.material_override = _get_shared_material(item_type)

func _apply_ray() -> void:
	if not _ray_instance:
		_ray_instance = get_node_or_null("RayMesh") as MeshInstance3D
		if not _ray_instance:
			_ray_instance = MeshInstance3D.new()
			_ray_instance.name = "RayMesh"
			add_child(_ray_instance)
			_ray_instance.mesh = _get_shared_ray_mesh(ray_height, ray_radius)
			_ray_instance.position = Vector3(0, ray_height * 0.5, 0)
			_ray_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			if not _ray_instance.mesh:
				_ray_instance.mesh = _get_shared_ray_mesh(ray_height, ray_radius)
				_ray_instance.position = Vector3(0, ray_height * 0.5, 0)

	if not show_highlight_ray:
		_ray_instance.visible = false
		return

	# If the user assigned a material in the scene, respect its settings!
	if _ray_instance.material_override is ShaderMaterial:
		if ray_tint_by_type:
			var mat: ShaderMaterial = _ray_instance.material_override.duplicate() as ShaderMaterial
			var base_col: Color = _type_color()
			base_col.a = ray_opacity
			mat.set_shader_parameter("beam_color", base_col)
			_ray_instance.material_override = mat
	else:
		_ray_instance.material_override = _get_shared_ray_material(item_type, ray_opacity)

	_ray_instance.visible = true

static func _get_shared_ray_mesh(p_height: float = 0.75, p_radius: float = 0.12) -> CylinderMesh:
	if not _cached_ray_mesh:
		var cm := CylinderMesh.new()
		cm.top_radius = p_radius * 1.35
		cm.bottom_radius = p_radius
		cm.height = p_height
		cm.cap_top = false
		cm.cap_bottom = false
		_cached_ray_mesh = cm
	return _cached_ray_mesh

static func _get_shared_ray_material(p_type: String, p_opacity: float = 0.4) -> ShaderMaterial:
	if not _cached_ray_materials.has(p_type):
		var mat := ShaderMaterial.new()
		mat.shader = RAY_SHADER
		mat.set_shader_parameter("noise_texture", RAY_NOISE)
		var col: Color
		match p_type:
			"coin":
				col = Color(1.0, 0.85, 0.2, p_opacity)
			"bottle":
				col = Color(0.2, 0.8, 1.0, p_opacity)
			"health":
				col = Color(1.0, 0.2, 0.25, p_opacity)
			"ammo":
				col = Color(0.3, 0.75, 1.0, p_opacity)
			_:
				col = Color(0.9, 0.9, 0.9, p_opacity)
		mat.set_shader_parameter("beam_color", col)
		mat.set_shader_parameter("vertical_speed", 0.5)
		mat.set_shader_parameter("rotation_speed", 0.1)
		mat.set_shader_parameter("density", 12.0)
		mat.set_shader_parameter("ray_sharpness", 0.55)
		mat.set_shader_parameter("fade_towards_top", true)
		mat.set_shader_parameter("fade_power", 2.2)
		_cached_ray_materials[p_type] = mat
	return _cached_ray_materials[p_type]

static func _get_shared_mesh(shape: String) -> Mesh:
	if not _cached_meshes.has(shape):
		var m: Mesh
		match shape:
			"sphere":
				var sm := SphereMesh.new()
				sm.radius = 0.12
				sm.height = 0.05
				m = sm
			"box":
				var bm := BoxMesh.new()
				bm.size = Vector3(0.18, 0.18, 0.18)
				m = bm
			"cylinder":
				var cm := CylinderMesh.new()
				cm.top_radius = 0.08
				cm.bottom_radius = 0.08
				cm.height = 0.22
				m = cm
			_:
				var sm := SphereMesh.new()
				sm.radius = 0.12
				sm.height = 0.24
				m = sm
		_cached_meshes[shape] = m
	return _cached_meshes[shape]

static func _get_shared_material(p_type: String) -> StandardMaterial3D:
	if not _cached_materials.has(p_type):
		var mat := StandardMaterial3D.new()
		match p_type:
			"coin": mat.albedo_color = Color(1.0, 0.85, 0.1)
			"health": mat.albedo_color = Color(0.9, 0.15, 0.15)
			"ammo": mat.albedo_color = Color(0.3, 0.7, 1.0)
			_: mat.albedo_color = Color(0.8, 0.8, 0.8)
		mat.metallic = 0.6
		mat.roughness = 0.3
		_cached_materials[p_type] = mat
	return _cached_materials[p_type]

func _type_color() -> Color:
	match item_type:
		"coin":   return Color(1.0, 0.85, 0.1)
		"bottle": return Color(0.2, 0.8,  1.0)
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
	_despawn()

static func clear_pool() -> void:
	for item in _pool:
		if is_instance_valid(item):
			item.queue_free()
	_pool.clear()

## Static helper: spawn a pickup at a world position and add it to a parent.
## Usage: ItemPickup.instantiate_drop(get_tree().current_scene, position, "coin", 1)
static func instantiate_drop(
		parent: Node,
		world_position: Vector3,
		p_item_type: String,
		p_value: int,
		scatter_radius: float = 0.6,
		p_mesh_override: Mesh = null) -> void:
	var instance: ItemPickup = null
	while not _pool.is_empty():
		var candidate = _pool.pop_back()
		if is_instance_valid(candidate):
			instance = candidate
			break

	if instance:
		if is_instance_valid(parent) and instance.get_parent() != parent:
			instance.reparent(parent)
		instance.reset_for_drop(p_item_type, p_value, p_mesh_override)
	else:
		instance = ITEM_PICKUP_SCENE.instantiate()
		instance.item_type = p_item_type
		instance.value = p_value
		if p_mesh_override:
			instance.mesh_override = p_mesh_override
		if is_instance_valid(parent):
			parent.add_child(instance)
		
	# Coin drops scatter much closer to each other (QoL)
	var scatter_val = 0.2 if p_item_type == "coin" else scatter_radius
	var offset := Vector3(
		randf_range(-scatter_val, scatter_val),
		0.3,
		randf_range(-scatter_val, scatter_val))
	instance.global_position = world_position + offset
