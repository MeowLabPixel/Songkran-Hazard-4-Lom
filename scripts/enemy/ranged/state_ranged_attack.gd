## STATE: RangedAttack
## Used by both the Water Gun zombie and the Balloon zombie.
class_name StateRangedAttack
extends EnemyState

enum AttackType { WATER_GUN, BALLOON }

@export var attack_type: AttackType = AttackType.WATER_GUN
@export var attack_damage: int = 4
@export var attack_range: float = 8.0
@export var release_frac: float = 0.5
@export var post_attack_delay: float = 0.5

# Balloon-only settings
@export var balloon_scene: PackedScene
@export var balloon_arc_height: float = 3.0
@export var balloon_travel_time: float = 1.2
@export var balloon_splash_radius: float = 3.0
@export var balloon_spawn_point: Node3D

# Water gun settings
@export var water_stream_scene: PackedScene
@export var gun_spawn_point: Node3D
@export var gun_model: Node3D

var _timer: float = 0.0
var _anim_duration: float = 1.5
var _damage_dealt: bool = false
var _anim_done: bool = false

func enter() -> void:
	if enemy and enemy.anim_player:
		print("[StateRangedAttack] Available animations:")
		for a in enemy.anim_player.get_animation_list():
			print("  '", a, "'")
			
	_timer        = 0.0
	_damage_dealt = false
	_anim_done    = false

	# Show/hide gun model based on type
	if gun_model:
		gun_model.visible = attack_type == AttackType.WATER_GUN

	var anim := _pick_anim()
	_force_anim(anim)

	if enemy and enemy.anim_player and enemy.anim_player.has_animation(anim):
		_anim_duration = enemy.anim_player.get_animation(anim).length
	else:
		_anim_duration = 1.5
		push_warning("[StateRangedAttack] Animation '%s' not found — using fallback duration" % anim)

	print("[StateRangedAttack] %s attack (%.2fs)" % [AttackType.keys()[attack_type], _anim_duration])

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	_timer += delta

	if not _damage_dealt and _timer >= _anim_duration * release_frac:
		_damage_dealt = true
		_try_deal_damage()

	if not _anim_done and _timer >= _anim_duration:
		_anim_done = true
		_force_anim(_pick_idle_anim())

	if _anim_done and _timer >= _anim_duration + post_attack_delay:
		state_machine.transition_to("StateHunt")

func handle_hit(hit_data: Dictionary) -> String:
	var zone: String = hit_data.get("hit_zone", "body")
	match zone:
		"head", "left_foot", "right_foot", "foot":
			return "StateTakedownable"
		_:
			return "StateStun"

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _pick_anim() -> String:
	match attack_type:
		AttackType.BALLOON:
			return enemy.anim_set.balloon_throw
		_:
			return enemy.anim_set.range_shoot

func _pick_idle_anim() -> String:
	match attack_type:
		AttackType.BALLOON:
			return enemy.anim_set.balloon_idle
		_:
			return enemy.anim_set.range_idle

func _try_deal_damage() -> void:
	var player := _get_player()
	if not player:
		return
	match attack_type:
		AttackType.BALLOON:
			_throw_balloon(player)
		AttackType.WATER_GUN:
			_fire_water_gun(player)

func _fire_water_gun(player: Node3D) -> void:
	var dist: float = enemy.global_position.distance_to(player.global_position)
	if dist > attack_range:
		print("[StateRangedAttack] Shot missed — out of range (%.1f > %.1f)" % [dist, attack_range])
		return

	var from: Vector3 = gun_spawn_point.global_position if gun_spawn_point \
		else enemy.global_position + Vector3.UP * 1.5
	var to: Vector3 = player.global_position + Vector3.UP * 1.0

	var space = enemy.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas  = true
	query.exclude = [enemy.get_rid()]
	var result = space.intersect_ray(query)

	var end_pos: Vector3 = result.position if result else to

	if water_stream_scene:
		var stream: Node = water_stream_scene.instantiate()
		var tree := enemy.get_tree()
		if tree and tree.current_scene:
			tree.current_scene.add_child(stream)
			if stream.has_method("set_line"):
				stream.set_line(from, end_pos)
			tree.create_timer(0.5).timeout.connect(stream.queue_free)
		else:
			stream.queue_free()

	if result:
		var collider = result.collider
		# Hit the CharacterBody3D directly
		var hit_player: bool = collider.is_in_group("player")
		# Hit a player hitbox Area3D
		if not hit_player and collider is Area3D and collider.is_in_group("player_hitbox"):
			hit_player = true

		if hit_player:
			player.take_damage(attack_damage)
			print("[StateRangedAttack] Water gun hit player for %d (dist %.1f)" % [attack_damage, dist])
		else:
			print("[StateRangedAttack] Water gun blocked by: ", collider.name)
	else:
		print("[StateRangedAttack] Water gun missed — no collision")

func _throw_balloon(player: Node3D) -> void:
	if not balloon_scene:
		push_warning("[StateRangedAttack] No balloon_scene assigned")
		player.take_damage(attack_damage)
		return

	var tree := enemy.get_tree()
	if not tree or not tree.current_scene:
		return
	var balloon: Node3D = balloon_scene.instantiate()
	tree.current_scene.add_child(balloon)

	var spawn_pos: Vector3 = balloon_spawn_point.global_position if balloon_spawn_point \
		else enemy.global_position + Vector3.UP * 1.8
	balloon.global_position = spawn_pos

	if balloon.has_method("launch"):
		balloon.launch(player.global_position, attack_damage, balloon_splash_radius,
			balloon_arc_height, balloon_travel_time)
	else:
		push_warning("[StateRangedAttack] Balloon scene has no launch() method")

func _get_player() -> Node3D:
	var tree := enemy.get_tree()
	if not tree:
		return null
	var players: Array = tree.get_nodes_in_group("player")
	return players[0] as Node3D if players.size() > 0 else null
