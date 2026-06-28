extends State

@export var push_speed: float = 4.0
@export var push_duration: float = 0.5
@export var stun_duration: float = 1.0

@export_group("Camera Adjustments")
@export var hit_cam_offset: float = -1.5
@export var hit_cam_pitch: float = -15.0
@export var hit_cam_duration_down: float = 0.5
@export var hit_cam_duration_up: float = 0.5

var elapsed_time: float = 0.0
var direction: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var camera_raised: bool = false

func _enter() -> void:
	print(name)
	owner.aim_bone_on(false)
	stop_moving()
	
	# Mark the player as stunned (this makes them invulnerable)
	owner.is_stunned = true
	elapsed_time = 0.0
	camera_raised = false
	
	# Apply damage if not already done by take_damage
	if not owner.hit_damage_already_applied:
		if owner.Hit_info.bullet and owner.Hit_info.bullet.has_node("HitboxZone"):
			owner.lost_HP(owner.Hit_info.bullet.get_node("HitboxZone").base_damage)
		else:
			owner.lost_HP(5) # default fallback damage
			
	# Play the appropriate animation based on hitbox location
	var location = owner.Hit_info.location
	
	# Travel to Hit state in the root machine
	var root_playback = owner.anim.get("parameters/playback")
	if root_playback:
		root_playback.travel("Hit")
		
	# Travel to the specific hit animation in the Hit sub-machine
	var hit_playback = owner.anim.get("parameters/Hit/playback")
	if hit_playback:
		if location == "back":
			hit_playback.travel("Hit_Back")
		else:
			hit_playback.travel("Hit_Front")
		
	# Calculate push direction
	calculate_push_direction(location)
	
	# Start camera transition (lowering camera exactly like grab fail)
	var cam = owner.camera
	if cam:
		if cam.has_method("set_action_offset_y"):
			cam.set_action_offset_y(hit_cam_offset, hit_cam_duration_down)
		if cam.has_method("set_action_pitch"):
			cam.set_action_pitch(hit_cam_pitch, hit_cam_duration_down)

func _exit() -> void:
	owner.Hit_info.location = null
	owner.Hit_info.bullet = null
	owner.hit_damage_already_applied = false
	owner.is_stunned = false
	
	# Failsafe camera reset
	var cam = owner.camera
	if cam:
		if cam.has_method("set_action_offset_y"):
			cam.set_action_offset_y(0.0, 0.2)
		if cam.has_method("set_action_pitch"):
			cam.set_action_pitch(0.0, 0.2)

func _update(delta: float) -> void:
	elapsed_time += delta
	
	# Handle push velocity during push_duration
	if elapsed_time < push_duration:
		# Pushing the player
		velocity.x = direction.x * push_speed
		velocity.z = direction.z * push_speed
	else:
		# Stop push movement, decelerate to 0
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		
		# Raise camera back
		if not camera_raised:
			camera_raised = true
			var cam = owner.camera
			if cam:
				if cam.has_method("set_action_offset_y"):
					cam.set_action_offset_y(0.0, hit_cam_duration_up)
				if cam.has_method("set_action_pitch"):
					cam.set_action_pitch(0.0, hit_cam_duration_up)
		
	# Apply gravity if not on floor
	if not owner.is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
		
	owner.velocity = velocity
	
	# Transition back to Idle after stun_duration is reached
	if elapsed_time >= stun_duration:
		finished.emit("Idle")

func stop_moving() -> void:
	velocity = Vector3.ZERO
	owner.velocity = Vector3.ZERO

func calculate_push_direction(location: String) -> void:
	var input_dir = Vector2.ZERO
	if location == "front":
		# Hit from front: push player back (move backwards relative to player facing direction)
		input_dir = Vector2(0, 1)
	elif location == "back":
		# Hit from back: push player forward (move forwards relative to player facing direction)
		input_dir = Vector2(0, -1)
	else:
		# Default fallback: push player back
		input_dir = Vector2(0, 1)
		
	direction = owner.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	direction = direction.normalized()
