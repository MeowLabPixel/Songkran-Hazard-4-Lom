extends Motion

var _is_first_time: bool = true

func _enter() -> void:
	owner.aim_bone_on(true)
	if Input.is_action_pressed("aim") and not owner.aim_blocked_until_release and owner.can_aim():
		owner.is_aimming = true
		finished.emit("Aim")
		return
	elif not Input.is_action_pressed("aim"):
		owner.aim_blocked_until_release = false
		
	if owner.is_aimming and owner.can_aim():
		finished.emit("Aim")
	print(name)
	
	var pb = owner.anim.get(owner.anim_playback)
	if pb:
		if _is_first_time:
			_is_first_time = false
			pb.start("Idle")
		else:
			pb.travel("Idle")
	
	set_gun_anim()



func _update(_delta:float) -> void:
	if not Input.is_action_pressed("aim"):
		owner.aim_blocked_until_release = false
		
	set_direction()
	calculate_velocity(SPEED,direction,_delta)
	if owner.HP <= 0:
		finished.emit("Die")
	if direction != Vector3.ZERO:
		finished.emit("Run")

func _state_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quick_turn") and not owner.is_quick_turn and owner.quick_turn_cooldown <= 0.0:
		finished.emit("Quick_turn")
	if Input.is_action_pressed("aim") and not owner.aim_blocked_until_release and owner.can_aim():
		finished.emit("Aim")
	if Input.is_action_just_pressed("Reload") :
		finished.emit("Reload")
	if Input.is_action_pressed("Gun1"):
		switch_gun(0)
	if Input.is_action_pressed("Gun2"):
		switch_gun(1)
	if Input.is_action_pressed("Gun3"):
		switch_gun(2)
	if Input.is_action_pressed("Takedown") and owner.is_near_stunt:
		# Trigger any nearby enemy takedownable state, then transition
		if owner.attempt_takedown():
			finished.emit("Takedown")



func switch_gun(num:int):
	if owner.gun_controller:
		owner.gun_controller.switch_gun(num)
		set_gun_anim()
		#one shot anim
	
func set_gun_anim():
	if not owner.gun_controller or not owner.gun_controller.current_gun:
		return
	var gun_name = owner.gun_controller.current_gun.get_gun_name()
	if gun_name == "Water pistol":
		owner.anim.set("parameters/Main/Idle/conditions/pis", true)
		owner.anim.set("parameters/Main/Idle/conditions/shot", false)
		owner.anim.set("parameters/Main/Idle/conditions/rifle", false)
		var pb = owner.anim.get("parameters/Main/Idle/playback")
		if pb and pb.get_current_node() != "Pis":
			pb.travel("Pis")
	elif gun_name == "Water shotgun":
		owner.anim.set("parameters/Main/Idle/conditions/pis", false)
		owner.anim.set("parameters/Main/Idle/conditions/shot", true)
		owner.anim.set("parameters/Main/Idle/conditions/rifle", false)
		var pb = owner.anim.get("parameters/Main/Idle/playback")
		if pb and pb.get_current_node() != "Shot":
			pb.travel("Shot")
	elif gun_name == "Water sniper":
		owner.anim.set("parameters/Main/Idle/conditions/pis", false)
		owner.anim.set("parameters/Main/Idle/conditions/shot", false)
		owner.anim.set("parameters/Main/Idle/conditions/rifle", true)
		var pb = owner.anim.get("parameters/Main/Idle/playback")
		if pb and pb.get_current_node() != "Rifle":
			pb.travel("Rifle")
	print(owner.anim.get("parameters/Main/Idle/playback").get_current_node())
