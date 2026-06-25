## Player — test controller.
## WASD movement on the XZ plane.
## Faces the mouse cursor position projected onto the ground plane.
## Belongs to the "player" group so Anchalee and pickups can identify it.
#class_name Player
extends CharacterBody3D

@export var move_speed: float = 5.0
@export var rotation_speed: float = 15.0
## Starting health for the player.
@export var max_health: int = 100

## Set by TestWorld each frame — world position of the mouse on the ground.
var aim_position: Vector3 = Vector3.ZERO

var current_health: int = max_health
## True while the enemy has successfully grabbed the player.
var is_grabbed: bool = false

const GRAVITY: float = -20.0

signal health_changed(current: int, maximum: int)

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	# Enable collision mask for Layer 3 (Enemies)
	set_collision_mask_value(3, true)

func _physics_process(delta: float) -> void:
	# Freeze all movement while grabbed.
	if is_grabbed:
		velocity = Vector3.ZERO
		return

	# ── Gravity ──────────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	# ── WASD input ────────────────────────────────────────────────────────────
	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back")  - Input.get_action_strength("move_forward")
	)

	if input_dir.length_squared() > 0.01:
		input_dir = input_dir.normalized()
		var move_dir := Vector3(input_dir.x, 0.0, input_dir.y)
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()

	# ── Face the mouse aim position ─────────────────────────────────────────────
	var to_aim: Vector3 = aim_position - global_position
	to_aim.y = 0.0
	if to_aim.length_squared() > 0.01:
		var target_basis: Basis = global_transform.looking_at(
				global_position + to_aim, Vector3.UP).basis
		global_transform.basis = global_transform.basis.slerp(
				target_basis.orthonormalized(),
				clampf(rotation_speed * delta, 0.0, 1.0))

# ─── Damage / Grab API ───────────────────────────────────────────────────

## Called by StateAttack when the enemy lands or misses a grab.
## success=true  → player is caught, freeze movement.
## success=false → player escaped, restore movement.
func on_grabbed(success: bool) -> void:
	is_grabbed = success
	if success:
		print("[Player] Grabbed! Cannot move.")
		# TODO: play LEON_GRAB_SUCCESS anim on the player model when one exists.
	else:
		print("[Player] Escaped the grab!")
		# TODO: play LEON_GRAB_FAIL anim on the player model when one exists.

## Called by StateAttack to deal hit damage to the player.
func take_damage(amount: int) -> void:
	current_health = clampi(current_health - amount, 0, max_health)
	print("[Player] Took %d damage — HP: %d/%d" % [amount, current_health, max_health])
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		print("[Player] Defeated!")
		# TODO: trigger player death state.
