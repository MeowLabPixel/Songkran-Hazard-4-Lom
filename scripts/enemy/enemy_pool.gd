extends Node

## High-performance object pool for enemies.
## Prevents runtime instantiate/queue_free hitches by pre-allocating and recycling instances.

static var instance = null

# Pool mapping: scene_path (String) -> Array[Node3D] (free available instances)
var _free_instances: Dictionary = {}
# Active mapping: instance (Node3D) -> scene_path (String)
var _active_instances: Dictionary = {}
# Storage node for parked instances
var _storage: Node3D = null

static var _last_spawn_frame: int = -1

static func can_spawn_this_frame() -> bool:
	return Engine.get_process_frames() != _last_spawn_frame

static func register_spawn_frame() -> void:
	_last_spawn_frame = Engine.get_process_frames()

func _enter_tree() -> void:
	instance = self
	if not _storage:
		_storage = Node3D.new()
		_storage.name = "PoolStorage"
		_storage.position = Vector3(0, -1000, 0)
		add_child(_storage)

func _exit_tree() -> void:
	if instance == self:
		instance = null
	clear_pools()

static func get_singleton():
	if not instance:
		var tree = Engine.get_main_loop() as SceneTree
		if tree and tree.root:
			var pool = tree.root.get_node_or_null("EnemyPool")
			if pool:
				instance = pool
			else:
				var script_res = load("res://scripts/enemy/enemy_pool.gd") as GDScript
				if script_res:
					var new_pool = script_res.new()
					new_pool.name = "EnemyPool"
					tree.root.call_deferred("add_child", new_pool)
					instance = new_pool
	return instance

static func is_pooled(enemy: Node3D) -> bool:
	var pool = get_singleton()
	if not pool or not is_instance_valid(enemy):
		return false
	return pool._active_instances.has(enemy)

static func prewarm(scene: PackedScene, count: int, parent_container: Node = null) -> void:
	var pool = get_singleton()
	if not pool or not scene:
		return
	var key = scene.resource_path
	if not pool._free_instances.has(key):
		pool._free_instances[key] = []
		
	var target_parent = parent_container if parent_container else pool._storage
	for i in range(count):
		var enemy = scene.instantiate() as Node3D
		if enemy:
			enemy.visible = false
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
			target_parent.add_child(enemy)
			EnemyRegistry.unregister_enemy(enemy)
			enemy.global_position = Vector3(0, -1000, 0)
			pool._free_instances[key].append(enemy)

static func acquire(scene: PackedScene, xform: Transform3D, parent_node: Node = null) -> Node3D:
	var pool = get_singleton()
	if not pool or not scene:
		return null
		
	var start_usec = Time.get_ticks_usec()
	var key = scene.resource_path
	var enemy: Node3D = null
	
	if pool._free_instances.has(key):
		while not pool._free_instances[key].is_empty():
			var candidate = pool._free_instances[key].pop_back()
			if is_instance_valid(candidate):
				enemy = candidate
				break

	if not enemy:
		# Pool empty, dynamically instantiate fallback
		enemy = scene.instantiate() as Node3D
		var target_parent = parent_node if parent_node else (pool.get_tree().current_scene if pool.get_tree() else null)
		if target_parent and enemy.get_parent() != target_parent:
			target_parent.add_child(enemy)

	if not enemy:
		return null

	var tree = pool.get_tree()
	var desired_parent = parent_node if parent_node else (tree.current_scene if tree else null)
	if desired_parent and enemy.get_parent() != desired_parent:
		enemy.reparent(desired_parent)

	enemy.global_transform = xform
	enemy.visible = true
	enemy.process_mode = Node.PROCESS_MODE_INHERIT

	pool._active_instances[enemy] = key
	
	# Reset state on the enemy
	if enemy.has_method("reset_for_spawn"):
		enemy.reset_for_spawn()
		
	return enemy

static func release(enemy: Node3D) -> void:
	var pool = get_singleton()
	if not pool or not is_instance_valid(enemy):
		return
		
	var key = pool._active_instances.get(enemy, "")
	if key.is_empty():
		# Not a tracked pooled instance, safely free
		enemy.queue_free()
		return
		
	pool._active_instances.erase(enemy)
	
	# Deactivate and park
	if enemy.has_method("deactivate_for_pool"):
		enemy.deactivate_for_pool()
		
	enemy.visible = false
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	
	if pool._storage and is_instance_valid(pool._storage) and enemy.get_parent() != pool._storage:
		enemy.reparent(pool._storage)
	enemy.global_position = Vector3(0, -1000, 0)
	
	if not pool._free_instances.has(key):
		pool._free_instances[key] = []
	pool._free_instances[key].append(enemy)

func _get_total_free_count() -> int:
	var total = 0
	for key in _free_instances:
		total += _free_instances[key].size()
	return total

static func clear_all() -> void:
	var pool = get_singleton()
	if pool:
		pool.clear_pools()

func clear_pools() -> void:
	for enemy in _active_instances.keys():
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active_instances.clear()
	
	for key in _free_instances:
		for enemy in _free_instances[key]:
			if is_instance_valid(enemy):
				enemy.queue_free()
	_free_instances.clear()
