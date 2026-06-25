## TestWorld — prototype controller.
## Player moves with WASD and faces the mouse.
## Left-click shoots (body hit), Shift+click = head, Ctrl+click = foot.
## E = takedown.
extends Node3D

@export var enemy_path: NodePath  = ^"Enemy"
@export var Anchalee_path: NodePath = ^"Anchalee"
@export var player_path: NodePath = ^"Player"
@export var camera_path: NodePath = ^"CamRig/Camera3D"

@onready var enemy:  CharacterBody3D = get_node(enemy_path)
@onready var Anchalee: CharacterBody3D = get_node(Anchalee_path)
@onready var player: CharacterBody3D = get_node(player_path)
@onready var camera: Camera3D        = get_node(camera_path)

const SHOOT_FLAG_DURATION: float = 0.4
var _shoot_flag_timer: float = 0.0

var _ground_plane := Plane(Vector3.UP, 0.0)

func _ready() -> void:
	print("[TestWorld] WASD = move | Mouse = aim | LMB = shoot (aim at body part) | E = takedown | Z = Anchalee wait/follow")

func _process(delta: float) -> void:
	_update_targets()
	_tick_shoot_flag(delta)
	_check_shoot()
	_check_takedown()
	_check_Anchalee_wait()

func _check_Anchalee_wait() -> void:
	if not Input.is_action_just_pressed("Anchalee_wait"):
		return
	if not Anchalee:
		return
	var sm = Anchalee.get_node_or_null("AnchaleeStateMachine")
	if not sm:
		return
	if sm.get_current_state_name() == "AnchaleeStateWait":
		print("[TestWorld] Anchalee: follow")
		sm.transition_to("AnchaleeStateFollow")
	else:
		print("[TestWorld] Anchalee: wait")
		sm.transition_to("AnchaleeStateWait")

## Project mouse onto the ground plane.
## Player position is the follow target for Anchalee/enemy.
## Mouse ground position is what the player faces and shoots toward.
func _update_targets() -> void:
	if not camera:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir    := camera.project_ray_normal(mouse_pos)
	var aim_hit: Variant = _ground_plane.intersects_ray(ray_origin, ray_dir)

	# Push aim position to player so it can face the cursor.
	if aim_hit and player:
		(player as Player).aim_position = aim_hit

	# Anchalee and enemy follow the player's actual world position.
	var follow_pos: Vector3 = player.global_position if player else Vector3.ZERO
	if enemy:
		enemy.set_meta("target_position", follow_pos)
	if Anchalee:
		Anchalee.set_meta("target_position", follow_pos)

func _tick_shoot_flag(delta: float) -> void:
	if _shoot_flag_timer > 0.0:
		_shoot_flag_timer -= delta
		if _shoot_flag_timer <= 0.0 and Anchalee:
			Anchalee.set_meta("player_shooting", false)

func _check_shoot() -> void:
	if not Input.is_action_just_pressed("shoot"):
		return
	if not enemy or not camera:
		return

	var mouse_pos  := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end    := ray_origin + camera.project_ray_normal(mouse_pos) * 100.0

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	# Layer 2 = enemy hitbox Areas only. Everything else (Anchalee ThreatArea,
	# ground, player, etc.) is invisible to this raycast.
	query.collision_mask    = 2
	query.collide_with_areas  = true
	query.collide_with_bodies = false
	if player:
		query.exclude = [player.get_rid()]
	var result := space.intersect_ray(query)

	if result.is_empty():
		return

	# Check the hit Area3D belongs to our enemy and has a HitboxZone.
	var hit_area: Area3D = result["collider"]
	var hitbox_zone: HitboxZone = hit_area.get_node_or_null("HitboxZone")
	if not hitbox_zone or hitbox_zone._enemy != enemy:
		return

	var hit_data := {"damage": hitbox_zone.base_damage, "hit_zone": hitbox_zone.zone_name}
	print("[TestWorld] Shot! zone=%s" % hitbox_zone.zone_name)
	enemy.take_hit(hit_data)
	if Anchalee:
		Anchalee.set_meta("player_shooting", true)
		_shoot_flag_timer = SHOOT_FLAG_DURATION

func _check_takedown() -> void:
	if not Input.is_action_just_pressed("takedown"):
		return
	if not enemy:
		return
	var sm = enemy.get_node_or_null("EnemyStateMachine")
	if not sm:
		return
	var td_state = sm.get_node_or_null("StateTakedownable")
	if td_state and sm.current_state == td_state:
		print("[TestWorld] TAKEDOWN!")
		td_state.trigger_takedown()
	else:
		print("[TestWorld] Enemy not in TAKEDOWNable state.")
