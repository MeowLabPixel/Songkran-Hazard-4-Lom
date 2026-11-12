extends Node

## Central registry for active enemies and combat state.
## Eliminates expensive tree-wide node_added hooks and per-frame get_nodes_in_group scans.

signal enemy_registered(enemy: Node3D)
signal enemy_unregistered(enemy: Node3D)
signal enemy_defeated(enemy: Node3D)
signal combat_state_changed(in_combat: bool)

static var instance = null

var _active_enemies: Array[Node3D] = []
var _combat_enemies: Dictionary = {} # Enemy -> bool
var _cached_player: Node3D = null

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null
	_active_enemies.clear()
	_combat_enemies.clear()
	_cached_player = null

static func get_singleton():
	if not instance:
		# Auto-create if not added to Autoloads yet
		var tree = Engine.get_main_loop() as SceneTree
		if tree and tree.root:
			var reg = tree.root.get_node_or_null("EnemyRegistry")
			if reg:
				instance = reg
			else:
				var script_res = load("res://scripts/enemy/enemy_registry.gd") as GDScript
				if script_res:
					var new_reg = script_res.new()
					new_reg.name = "EnemyRegistry"
					tree.root.call_deferred("add_child", new_reg)
					instance = new_reg
	return instance

static func register_enemy(enemy: Node3D) -> void:
	var reg = get_singleton()
	if not reg or not is_instance_valid(enemy):
		return
	if not enemy.is_inside_tree() or enemy.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	if enemy.get_parent() and enemy.get_parent().name == "PoolStorage":
		return
	if not reg._active_enemies.has(enemy):
		reg._active_enemies.append(enemy)
		reg.enemy_registered.emit(enemy)

static func unregister_enemy(enemy: Node3D) -> void:
	var reg = get_singleton()
	if not reg or not is_instance_valid(enemy):
		return
	reg._active_enemies.erase(enemy)
	if reg._combat_enemies.has(enemy):
		reg._combat_enemies.erase(enemy)
		_check_combat_music(reg)
	reg.enemy_unregistered.emit(enemy)

static func notify_enemy_defeated(enemy: Node3D) -> void:
	var reg = get_singleton()
	if not reg or not is_instance_valid(enemy):
		return
	if reg._active_enemies.has(enemy):
		reg._active_enemies.erase(enemy)
	if reg._combat_enemies.has(enemy):
		reg._combat_enemies.erase(enemy)
		_check_combat_music(reg)
	reg.enemy_defeated.emit(enemy)

static func set_in_combat(enemy: Node3D, in_combat: bool) -> void:
	var reg = get_singleton()
	if not reg or not is_instance_valid(enemy):
		return
	var was_in_combat = reg._combat_enemies.has(enemy)
	if in_combat and not was_in_combat:
		reg._combat_enemies[enemy] = true
		if reg._combat_enemies.size() == 1:
			reg.combat_state_changed.emit(true)
	elif not in_combat and was_in_combat:
		reg._combat_enemies.erase(enemy)
		_check_combat_music(reg)

static func _check_combat_music(reg) -> void:
	if reg._combat_enemies.is_empty():
		reg.combat_state_changed.emit(false)
		if SoundManager:
			SoundManager.play_music_non_combat()

static func get_active_count() -> int:
	var reg = get_singleton()
	if not reg:
		return 0
	for i in range(reg._active_enemies.size() - 1, -1, -1):
		var e = reg._active_enemies[i]
		if not is_instance_valid(e) or not e.is_inside_tree() or e.process_mode == Node.PROCESS_MODE_DISABLED or e.get("is_defeated") == true:
			reg._active_enemies.remove_at(i)
	return reg._active_enemies.size()

static func is_any_in_combat() -> bool:
	var reg = get_singleton()
	if not reg:
		return false
	return not reg._combat_enemies.is_empty()

static func is_in_combat(enemy: Node3D) -> bool:
	var reg = get_singleton()
	if not reg or not is_instance_valid(enemy):
		return false
	return reg._combat_enemies.has(enemy)

static func get_player() -> Node3D:
	var reg = get_singleton()
	if not reg:
		return null
	if is_instance_valid(reg._cached_player):
		return reg._cached_player
		
	var tree = Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var player = tree.get_first_node_in_group("player") as Node3D
	if not player and tree.current_scene:
		player = tree.current_scene.get_node_or_null("player") as Node3D
		if not player:
			player = tree.current_scene.get_node_or_null("Player") as Node3D
	reg._cached_player = player
	return player

static func get_active_enemies() -> Array[Node3D]:
	var reg = get_singleton()
	if not reg:
		return []
	return reg._active_enemies.duplicate()
