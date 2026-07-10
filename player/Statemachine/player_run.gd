extends Motion

var is_stopping: bool = false
var last_input_dir: Vector2 = Vector2.ZERO
var stop_timer: float = 0.0
var _linger_anim_speed: float = 1.0

func _enter() -> void:
	is_stopping = false
	stop_timer = 0.0
	print(name)
	owner.aim_bone_on(true)
	set_gun_anim()
	owner.anim.get(owner.anim_playback).travel("Run")	
	#gun_anim()



func _update(_delta:float) -> void:
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
		elif input_dir.x != 0.0:
			current_speed = owner.walk_Back_speed
			current_anim_speed = owner.walk_side_anim_speed
			
		_linger_anim_speed = current_anim_speed
			
		calculate_velocity(current_speed, direction, _delta)
		
		owner.anim.set("parameters/Main/Run/Pis/TimeScale/scale", current_anim_speed)
		owner.anim.set("parameters/Main/Run/Shot/TimeScale/scale", current_anim_speed)
		
		var target_blend = Vector2(input_dir.x, -input_dir.y)
		var current_blend_pis = owner.anim.get("parameters/Main/Run/Pis/BlendSpace2D/blend_position") as Vector2
		var current_blend_shot = owner.anim.get("parameters/Main/Run/Shot/BlendSpace2D/blend_position") as Vector2
		
		var new_blend_pis = current_blend_pis.lerp(target_blend, _delta * 10.0)
		var new_blend_shot = current_blend_shot.lerp(target_blend, _delta * 10.0)
		
		owner.anim.set("parameters/Main/Run/Pis/BlendSpace2D/blend_position", new_blend_pis)
		owner.anim.set("parameters/Main/Run/Shot/BlendSpace2D/blend_position", new_blend_shot)
	else:
		if not is_stopping:
			is_stopping = true
			stop_timer = 0.15 # Stopping step duration in seconds
			
		stop_timer -= _delta
		if stop_timer <= 0.0:
			finished.emit("Idle")
			return
			
		# Smooth physical deceleration
		velocity.x = lerpf(velocity.x, 0.0, _delta * 20.0)
		velocity.z = lerpf(velocity.z, 0.0, _delta * 20.0)
		velocity_updated.emit(velocity)
		
		# Smooth animation deceleration
		var decay_speed = lerpf(0.0, _linger_anim_speed, stop_timer / 0.15)
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
