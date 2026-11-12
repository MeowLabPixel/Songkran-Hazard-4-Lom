class_name WarmupService
extends Node

## Warmup service that runs behind the loading screen.
## Prewarms enemy pools, item pools, and forces GPU pipeline compilation for gameplay shaders.

const ENEMY_SCENE_PATHS: Array[String] = [
	"res://scenes/enemy/BalloonZom.tscn",
	"res://scenes/enemy/FMeleeZom.tscn",
	"res://scenes/enemy/GunZom.tscn",
	"res://scenes/enemy/MMeleeZom.tscn"
]

const POWDER_PREP_PATH: String = "res://Jomp_Folder/VFX_Water/VFX2/powder_attack_prep.tscn"
const TAKEDOWN_SHADER_PATH: String = "res://shaders/takedown_aura.gdshader"

static func warmup_all(world_scene: Node) -> void:
	if not world_scene:
		return
	var start_ms = Time.get_ticks_msec()
	print("[WarmupService] Starting warmup sequence...")

	# 1. Prewarm Enemy Pools (3 instances of each enemy type)
	for scene_path in ENEMY_SCENE_PATHS:
		if ResourceLoader.exists(scene_path):
			var packed = load(scene_path) as PackedScene
			if packed:
				EnemyPool.prewarm(packed, 3)

	# 2. Prewarm ItemPickup Pool (15 coins, 5 bottles)
	var pickup_scene = load("res://scenes/items/item_pickup.tscn") as PackedScene
	if pickup_scene:
		for i in range(15):
			var p = pickup_scene.instantiate() as ItemPickup
			if p:
				p.visible = false
				p.set_physics_process(false)
				world_scene.add_child(p)
				p._despawn()

	# 3. Compile Shaders by instantiating prep particle & aura material for 1 frame
	var temp_holder = Node3D.new()
	temp_holder.name = "WarmupShaderTemp"
	temp_holder.position = Vector3(0, -900, 0)
	world_scene.add_child(temp_holder)

	if ResourceLoader.exists(POWDER_PREP_PATH):
		var prep_packed = load(POWDER_PREP_PATH) as PackedScene
		if prep_packed:
			var prep_inst = prep_packed.instantiate()
			temp_holder.add_child(prep_inst)

	if ResourceLoader.exists(TAKEDOWN_SHADER_PATH):
		var shader = load(TAKEDOWN_SHADER_PATH) as Shader
		if shader:
			var mat = ShaderMaterial.new()
			mat.shader = shader
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = SphereMesh.new()
			mesh_inst.material_override = mat
			temp_holder.add_child(mesh_inst)

	# Clean up shader compiler temp node on next frame
	var tree = world_scene.get_tree()
	if tree:
		tree.create_timer(0.05).timeout.connect(func():
			if is_instance_valid(temp_holder):
				temp_holder.queue_free()
		)

	var elapsed = Time.get_ticks_msec() - start_ms
	print("[WarmupService] Warmup sequence completed in %d ms." % elapsed)
