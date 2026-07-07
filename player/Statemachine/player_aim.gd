extends State
var anim_node = "parameters/Main/Aim/"
func _enter() -> void:
	stop_moving()
	owner.is_aimming = true
	#set_gun_anim()
	if owner.anim.get(owner.anim_playback).get_current_node() != "Aim":
		owner.anim.get(owner.anim_playback).travel("Aim")
	owner.cross_hair.visible = true
	owner.aim_bone_on(true)
	if owner.camera and owner.camera.has_method("enter_aim"):
		owner.camera.enter_aim()

	if not Input.is_action_pressed("aim") :
		owner.is_aimming = false
		finished.emit("Idle")

func _update(_delta:float) -> void:
	if owner.HP <= 0:
		finished.emit("Die")
		return
		
	# Automatic shooting during Super Pump (Pistol only)
	if Input.is_action_pressed("click"):
		if owner.gun_controller and owner.gun_controller.current_gun:
			var gun = owner.gun_controller.current_gun
			if gun is PistolWaterGun and gun.is_super_active:
				if gun.can_shoot():
					gun.shoot()
					owner.anim.set("parameters/Main/Aim/BlendTree/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
					owner.notify_shot_fired()
	
func _exit() -> void:
	#owner.is_aimming = false
	owner.cross_hair.visible = false
	


func _state_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quick_turn") and not owner.is_quick_turn and owner.quick_turn_cooldown <= 0.0:
		finished.emit("Quick_turn")
	if Input.is_action_just_released("aim") :
		owner.is_aimming = false
		finished.emit("Idle")
	if Input.is_action_pressed("Reload") :
		finished.emit("Reload")
	if Input.is_action_pressed("Gun1"):
		switch_gun(0)
	if Input.is_action_pressed("Gun2"):
		switch_gun(1)
	if Input.is_action_pressed("Gun3"):
		switch_gun(2)
	if Input.is_action_just_pressed("click"):
		if owner.gun_controller and owner.gun_controller.current_gun:
			var gun = owner.gun_controller.current_gun
			if not (gun is PistolWaterGun and gun.is_super_active):
				if gun.can_shoot():
					gun.shoot()
					owner.anim.set("parameters/Main/Aim/BlendTree/OneShot/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
					owner.notify_shot_fired()


func switch_gun(num:int):
	if owner.gun_controller:
		owner.gun_controller.switch_gun(num)
		#set_gun_anim()
		#one shot anim
		
#func set_gun_anim():
	#if owner.gun_controller.current_gun.get_gun_name() == "Water pistol":
		#owner.anim.set(anim_node + "conditions/pis",true)
		#owner.anim.set(anim_node + "conditions/shot",false)
		#if owner.anim.get(anim_node + "playback").get_current_node() != "Pis":
			#owner.anim.get(anim_node + "playback").travel("Pis")
	#elif owner.gun_controller.current_gun.get_gun_name() == "Water shotgun" or owner.gun_controller.current_gun.get_gun_name() == "Water sniper":
		#owner.anim.set(anim_node + "conditions/pis",false)
		#owner.anim.set(anim_node + "conditions/shot",true)
		#if owner.anim.get(anim_node + "playback").get_current_node() != "Shot":
			#owner.anim.get(anim_node + "playback").travel("Shot")

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)
