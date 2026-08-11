extends Motion

var D

func _enter() -> void:
	print(name)
	owner.aim_bone_on(true)
	owner.anim.get(owner.anim_playback).travel("Run")	
	
	var camera_node = owner.get_node_or_null("Camera")
	if camera_node and camera_node.has_method("enter_sprint"):
		camera_node.enter_sprint()


func _update(_delta:float) -> void:
	if owner.is_aimming:
		finished.emit("Aim")
		return
		
	set_direction()
	if input_dir.y >= -0.1:
		finished.emit("Run")
		return
	calculate_velocity(owner.run_speed,direction,_delta)
	
	# Velocity-Driven BlendSpace2D blending (1-to-1 sync with physical character momentum)
	var player_basis = owner.global_transform.basis
	var local_vel = player_basis.inverse() * velocity
	var ref_speed_z = maxf(owner.run_speed if local_vel.z < 0.0 else owner.walk_Back_speed, 0.1)
	var ref_speed_x = maxf(owner.walk_Back_speed, 0.1)
	var target_blend = Vector2(
		clampf(local_vel.x / ref_speed_x, -1.0, 1.0),
		clampf(-local_vel.z / ref_speed_z, -1.0, 1.0)
	)
	
	var current_blend_pis = owner.anim.get("parameters/Main/Run/Pis/BlendSpace2D/blend_position") as Vector2
	var current_blend_shot = owner.anim.get("parameters/Main/Run/Shot/BlendSpace2D/blend_position") as Vector2
	
	var new_blend_pis = current_blend_pis.lerp(target_blend, _delta * 12.0)
	var new_blend_shot = current_blend_shot.lerp(target_blend, _delta * 12.0)
	
	owner.anim.set("parameters/Main/Run/Pis/BlendSpace2D/blend_position", new_blend_pis)
	owner.anim.set("parameters/Main/Run/Shot/BlendSpace2D/blend_position", new_blend_shot)
	#owner.anim.get("parameters/Main/Run/Pis/BlendSpace2D/blend_position").set(direction)
	D=_delta
	if direction == Vector3.ZERO:
		finished.emit("Run")
	if owner.HP <= 0:
		finished.emit("Die")
		
func _exit() -> void:
	var camera_node = owner.get_node_or_null("Camera")
	if camera_node and camera_node.has_method("exit_sprint"):
		camera_node.exit_sprint()
	
	
func _state_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("quick_turn") and not owner.is_quick_turn and owner.quick_turn_cooldown <= 0.0:
		finished.emit("Quick_turn")
	if Input.is_action_just_released("sprint"):
		finished.emit("Run")
	if Input.is_action_pressed("Reload") :
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
	if Input.is_action_pressed("aim") :
		finished.emit("Aim")





func switch_gun(num:int):
	if owner.gun_controller:
		owner.gun_controller.switch_gun(num)
		set_gun_anim()
		#one shot anim

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
