extends State

@export var push_speed: float = 4.0
@export var push_duration: float = 0.5

@export_group("Camera Adjustments")
@export var hit_cam_offset: float = -1.5
@export var hit_cam_pitch: float = -15.0
@export var hit_cam_spring_offset: float = 1.5
@export var hit_cam_duration_down: float = 0.5
@export var hit_cam_duration_up: float = 0.5

var elapsed_time: float = 0.0
var direction: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var camera_raised: bool = false
var _anim_finished: bool = false

func _enter() -> void:
	print(name)
	owner.cancel_aim()
	stop_moving()
	
	# Play Rookie Lee get hit voice line and physical hit sound
	SoundManager.play_3d("vo_leon_gethit", owner)
	SoundManager.play_3d("leon_hit", owner)
	SoundManager.play_3d("Region_PlayerGetHitMelee", owner)
	
	# Play Anchalee worried voiceline 1.0 second after player gets hit
	var timer = owner.get_tree().create_timer(1.0)
	timer.timeout.connect(func():
		var followers = owner.get_tree().get_nodes_in_group("Anchalee")
		if followers.size() > 0:
			var follower = followers[0]
			if is_instance_valid(follower):
				var health = follower.get("health")
				if health != null and health > 0:
					SoundManager.play_3d("vo_anchalee_player_gethit", follower)
	)
	
	# Muffle the music bus when player is hit
	SoundManager.set_bus_muffled("Music", true)
	
	# Mark the player as stunned (this makes them invulnerable)
	owner.is_stunned = true
	
	# Disable player bone hitbox areas so zombies can't detect overlap during flinch
	_set_player_hitbox_areas_monitoring(false)
	
	# Disable all zombie attack/grab hitboxes during hit state
	_set_all_enemy_hitboxes(false)
	
	elapsed_time = 0.0
	camera_raised = false
	_anim_finished = false
	
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
		if cam.has_method("set_action_spring_length"):
			cam.set_action_spring_length(hit_cam_spring_offset, hit_cam_duration_down)
	
	# Listen for animation end to transition immediately
	if not owner.anim.animation_finished.is_connected(_on_hit_anim_finished):
		owner.anim.animation_finished.connect(_on_hit_anim_finished)

func _on_hit_anim_finished(_anim_name: String) -> void:
	_anim_finished = true

func _exit() -> void:
	# Unmuffle the music bus when recovering
	SoundManager.set_bus_muffled("Music", false)
	
	owner.Hit_info.location = null
	owner.Hit_info.bullet = null
	owner.hit_damage_already_applied = false
	owner.is_stunned = false
	owner.aim_blocked_until_release = false
	
	# Re-enable player bone hitbox areas
	_set_player_hitbox_areas_monitoring(true)
	
	# Re-enable all zombie attack/grab hitboxes
	_set_all_enemy_hitboxes(true)
	
	# Disconnect animation callback
	if owner.anim and owner.anim.animation_finished.is_connected(_on_hit_anim_finished):
		owner.anim.animation_finished.disconnect(_on_hit_anim_finished)
	
	# Failsafe camera reset
	var cam = owner.camera
	if cam:
		if cam.has_method("set_action_offset_y"):
			cam.set_action_offset_y(0.0, 0.2)
		if cam.has_method("set_action_pitch"):
			cam.set_action_pitch(0.0, 0.2)
		if cam.has_method("set_action_spring_length"):
			cam.set_action_spring_length(0.0, 0.2)

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
				if cam.has_method("set_action_spring_length"):
					cam.set_action_spring_length(0.0, hit_cam_duration_up)
		
	# Apply gravity if not on floor
	if not owner.is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
		
	owner.velocity = velocity
	
	# Transition back to Idle when animation finishes
	if _anim_finished:
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

func _set_player_hitbox_areas_monitoring(enabled: bool) -> void:
	if not owner:
		return
	var nodes = owner.get_tree().get_nodes_in_group("player_hitbox")
	for area in nodes:
		if area is Area3D:
			# Modify both monitoring and monitorable so they neither scan nor are scanned
			area.set_deferred("monitoring", enabled)
			area.set_deferred("monitorable", enabled)

func _set_all_enemy_hitboxes(enabled: bool) -> void:
	if not owner or not owner.is_inside_tree():
		return
	var areas = owner.get_tree().get_nodes_in_group("enemy_attack")
	for area in areas:
		if area is Area3D:
			area.set_deferred("monitoring", enabled)
			area.set_deferred("monitorable", enabled)
