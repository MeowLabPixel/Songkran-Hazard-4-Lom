extends Motion

var is_stopping: bool = false
var last_input_dir: Vector2 = Vector2.ZERO
var stop_timer: float = 0.0
var _linger_anim_speed: float = 1.0
var blend_reversal_timer: float = 0.0
const BLEND_REVERSAL_DURATION: float = 0.40

func _enter() -> void:
	if owner.HP <= 0 or ("pending_die_after_hit" in owner and owner.pending_die_after_hit):
		finished.emit("Die")
		return
	is_stopping = false
	stop_timer = 0.0
	blend_reversal_timer = 0.0
	print(name)
	owner.aim_bone_on(true)
	
	if Input.is_action_pressed("aim") and not owner.aim_blocked_until_release and owner.can_aim():
		owner.is_aimming = true
		finished.emit("Aim")
		return
		
	set_gun_anim()
	owner.anim.get(owner.anim_playback).travel("Run")
	owner.anim.set("parameters/Main/Run/Pis/TimeScale/scale", 1.0)
	owner.anim.set("parameters/Main/Run/Shot/TimeScale/scale", 1.0)
	
	set_direction()
	if direction != Vector3.ZERO:
		last_input_dir = input_dir
		var init_blend = Vector2(input_dir.x, -input_dir.y)
		var cur_blend_pis = owner.anim.get("parameters/Main/Run/Pis/BlendSpace2D/blend_position") as Vector2
		if cur_blend_pis == null or cur_blend_pis.length_squared() < 0.01:
			owner.anim.set("parameters/Main/Run/Pis/BlendSpace2D/blend_position", init_blend * 0.3)
			owner.anim.set("parameters/Main/Run/Shot/BlendSpace2D/blend_position", init_blend * 0.3)

func _update(_delta:float) -> void:
	if owner.HP <= 0 or ("pending_die_after_hit" in owner and owner.pending_die_after_hit):
		finished.emit("Die")
		return
	if not Input.is_action_pressed("aim"):
		owner.aim_blocked_until_release = false

	if owner.is_aimming and not owner.aim_blocked_until_release and owner.can_aim():
		finished.emit("Aim")
		return
		
	set_direction()
	
	if direction != Vector3.ZERO:
		is_stopping = false
		last_input_dir = input_dir
		
		var current_speed = owner.walk_speed
		var current_anim_speed = owner.walk_anim_speed
		
		if input_dir.y > 0.0:
			current_speed = owner.walk_Back_speed
			current_anim_speed = owner.walk_back_anim_speed
		elif input_dir.y == 0.0 and input_dir.x != 0.0:
			current_speed = owner.walk_Back_speed
			current_anim_speed = owner.walk_side_anim_speed
			
		_linger_anim_speed = current_anim_speed
		owner.anim.set("parameters/Main/Run/Pis/TimeScale/scale", current_anim_speed)
		owner.anim.set("parameters/Main/Run/Shot/TimeScale/scale", current_anim_speed)
			
		calculate_velocity(current_speed, direction, _delta)
		
		# Velocity-Driven BlendSpace2D blending (1-to-1 sync with physical character momentum)
		var player_basis = owner.global_transform.basis
		var local_vel = player_basis.inverse() * velocity
		var ref_speed_z = maxf(owner.walk_speed if local_vel.z < 0.0 else owner.walk_Back_speed, 0.1)
		var ref_speed_x = maxf(owner.walk_Back_speed, 0.1)
		var target_blend = Vector2(
			clampf(local_vel.x / ref_speed_x, -1.0, 1.0),
			clampf(-local_vel.z / ref_speed_z, -1.0, 1.0)
		)
		
		var current_blend_pis = owner.anim.get("parameters/Main/Run/Pis/BlendSpace2D/blend_position") as Vector2
		var current_blend_shot = owner.anim.get("parameters/Main/Run/Shot/BlendSpace2D/blend_position") as Vector2
		
		# Detect 180° direction reversal (target opposes current blend position)
		if target_blend.length_squared() > 0.1 and current_blend_pis.length_squared() > 0.1:
			var dot = target_blend.normalized().dot(current_blend_pis.normalized())
			if dot < -0.3 and blend_reversal_timer <= 0.0:
				blend_reversal_timer = BLEND_REVERSAL_DURATION

		var blend_lerp_speed = 12.0
		if blend_reversal_timer > 0.0:
			blend_reversal_timer -= _delta
			var elapsed_t = clampf((BLEND_REVERSAL_DURATION - blend_reversal_timer) / BLEND_REVERSAL_DURATION, 0.0, 1.0)
			# Gradually accelerate lerp speed from 3.0 (slow plant) -> 18.0 (fast whip into new direction)
			blend_lerp_speed = lerpf(3.0, 18.0, elapsed_t * elapsed_t)

		var new_blend_pis = current_blend_pis.lerp(target_blend, _delta * blend_lerp_speed)
		var new_blend_shot = current_blend_shot.lerp(target_blend, _delta * blend_lerp_speed)
		
		owner.anim.set("parameters/Main/Run/Pis/BlendSpace2D/blend_position", new_blend_pis)
		owner.anim.set("parameters/Main/Run/Shot/BlendSpace2D/blend_position", new_blend_shot)
	else:
		if not is_stopping:
			is_stopping = true
			stop_timer = 0.22 # Stopping step duration in seconds
			
		stop_timer -= _delta
		if stop_timer <= 0.0:
			finished.emit("Idle")
			return
			
		# Smooth AAA-style physical velocity deceleration (footstep inertia)
		velocity.x = lerpf(velocity.x, 0.0, _delta * 9.0)
		velocity.z = lerpf(velocity.z, 0.0, _delta * 9.0)
		velocity_updated.emit(velocity)
		
		# Smooth animation deceleration
		var decay_speed = lerpf(0.0, _linger_anim_speed, clamp(stop_timer / 0.22, 0.0, 1.0))
		owner.anim.set("parameters/Main/Run/Pis/TimeScale/scale", decay_speed)
		owner.anim.set("parameters/Main/Run/Shot/TimeScale/scale", decay_speed)
		
		# Lock blend position so it doesn't snap to idle during the stop (using smooth lerp)
		var target_blend = Vector2(last_input_dir.x, -last_input_dir.y)
		var current_blend_pis = owner.anim.get("parameters/Main/Run/Pis/BlendSpace2D/blend_position") as Vector2
		var current_blend_shot = owner.anim.get("parameters/Main/Run/Shot/BlendSpace2D/blend_position") as Vector2
		
		var new_blend_pis = current_blend_pis.lerp(target_blend, _delta * 10.0)
		var new_blend_shot = current_blend_shot.lerp(target_blend, _delta * 10.0)
		
		owner.anim.set("parameters/Main/Run/Pis/BlendSpace2D/blend_position", new_blend_pis)
		owner.anim.set("parameters/Main/Run/Shot/BlendSpace2D/blend_position", new_blend_shot)
	if owner.HP <= 0:
			finished.emit("Die")

		
func _state_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quick_turn") and not owner.is_quick_turn and owner.quick_turn_cooldown <= 0.0:
		finished.emit("Quick_turn")
	if Input.is_action_pressed("sprint") and input_dir.y < -0.1:
		finished.emit("Sprint")
	if Input.is_action_just_pressed("Reload") :
		var gun = owner.gun_controller.current_gun
		var is_pistol = gun and (gun.gun_name == "Water pistol" or owner.gun_controller.current_gun_index == 0)
		var is_superpump_attempt = is_pistol and gun.air >= gun.max_air
		if not (is_superpump_attempt and owner.superpump_cooldown > 0.0):
			get_viewport().set_input_as_handled()
			finished.emit("Reload")
	if Input.is_action_pressed("Gun1"):
		switch_gun(0)
	if Input.is_action_pressed("Gun2"):
		switch_gun(1)
	if Input.is_action_pressed("Gun3"):
		switch_gun(2)
	if Input.is_action_pressed("Takedown") and owner.is_near_stunt:
		if owner.attempt_takedown():
			finished.emit("Takedown")
	if Input.is_action_pressed("aim") and not owner.aim_blocked_until_release and owner.can_aim():
		finished.emit("Aim")



func switch_gun(num:int):
	if owner.gun_controller:
		owner.gun_controller.switch_gun(num)
		set_gun_anim()
		#one shot anim

func set_gun_anim():
	if not owner.gun_controller or not owner.gun_controller.current_gun:
		return
	if owner.gun_controller.current_gun.get_gun_name() == "Water pistol":
		owner.anim.set("parameters/Main/Run/conditions/pis",true)
		owner.anim.set("parameters/Main/Run/conditions/shot",false)
		if owner.anim.get("parameters/Main/Run/playback").get_current_node() != "Pis":
			owner.anim.get("parameters/Main/Run/playback").travel("Pis")
	elif owner.gun_controller.current_gun.get_gun_name() == "Water shotgun" or owner.gun_controller.current_gun.get_gun_name() == "Water sniper":
		owner.anim.set("parameters/Main/Run/conditions/pis",false)
		owner.anim.set("parameters/Main/Run/conditions/shot",true)
		if owner.anim.get("parameters/Main/Run/playback").get_current_node() != "Shot":
			owner.anim.get("parameters/Main/Run/playback").travel("Shot")
