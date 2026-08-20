extends State
var anim_node = "parameters/Main/Aim/"
@export var default_aim_entry_duration: float = 0.17
@export var quick_shot_post_delay: float = 0.01
var shot_exit_lock_timer: float = 0.0
var _is_firing_shot: bool = false
var is_shot_queued: bool = false
var is_waiting_quick_shot_delay: bool = false
var quick_shot_delay_timer: float = 0.0
var aim_entry_timer: float = 0.15

func _enter() -> void:
	stop_moving()
	owner.is_aimming = true
	shot_exit_lock_timer = 0.0
	_is_firing_shot = false
	is_shot_queued = false
	is_waiting_quick_shot_delay = false
	quick_shot_delay_timer = 0.0
	aim_entry_timer = default_aim_entry_duration
	if "target_aim_speed_multiplier" in owner:
		owner.target_aim_speed_multiplier = 1.0
	if "aim_speed_multiplier" in owner:
		owner.aim_speed_multiplier = 1.0
	set_gun_aim_anim()
	if owner.anim and owner.anim_playback != "":
		var pb = owner.anim.get(owner.anim_playback)
		if pb and pb.has_method("travel"):
			pb.travel("Aim")
	owner.cross_hair.visible = true
	owner.aim_bone_on(true)
	if owner.camera and owner.camera.has_method("enter_aim"):
		owner.camera.enter_aim()

	# If shoot button was already pressed/held upon entering aim, queue the shot immediately
	if Input.is_action_pressed("click") or Input.is_action_just_pressed("click"):
		if owner.gun_controller and owner.gun_controller.current_gun:
			var gun = owner.gun_controller.current_gun
			if not (gun is PistolWaterGun and gun.is_super_active):
				is_shot_queued = true
				if owner.has_method("boost_aim_transition_fast"):
					owner.boost_aim_transition_fast()
				aim_entry_timer = min(aim_entry_timer, 0.15)
				set_gun_aim_anim()

	if not Input.is_action_pressed("aim") and not is_shot_queued and not is_waiting_quick_shot_delay:
		owner.is_aimming = false
		_evaluate_queued_exit()

func _update(_delta:float) -> void:
	if owner.HP <= 0:
		finished.emit("Die")
		return
		
	if is_shot_queued or is_waiting_quick_shot_delay or shot_exit_lock_timer > 0.0:
		owner.is_aimming = true
		
	if aim_entry_timer > 0.0:
		aim_entry_timer -= _delta
		
	if shot_exit_lock_timer > 0.0:
		shot_exit_lock_timer -= _delta
		
	# If shot was queued, wait out the accelerated aim entry duration and transition completion, then apply 0.025s post-delay
	if is_shot_queued:
		if not is_waiting_quick_shot_delay:
			if aim_entry_timer <= 0.0 and owner.is_aim_transition_complete():
				is_waiting_quick_shot_delay = true
				quick_shot_delay_timer = quick_shot_post_delay
		else:
			quick_shot_delay_timer -= _delta
			if quick_shot_delay_timer <= 0.0:
				is_shot_queued = false
				is_waiting_quick_shot_delay = false
				_trigger_shot()
	# Check for shooting input if not already queued
	if not is_shot_queued and not is_waiting_quick_shot_delay:
		if Input.is_action_just_pressed("click"):
			if owner.gun_controller and owner.gun_controller.current_gun:
				var gun = owner.gun_controller.current_gun
				if not (gun is PistolWaterGun and gun.is_super_active):
					if aim_entry_timer <= 0.0 and owner.is_aim_transition_complete():
						_trigger_shot()
					else:
						is_shot_queued = true
						if owner.has_method("boost_aim_transition_fast"):
							owner.boost_aim_transition_fast()
						aim_entry_timer = min(aim_entry_timer, 0.1)
						set_gun_aim_anim()
		elif Input.is_action_pressed("click"):
			if owner.gun_controller and owner.gun_controller.current_gun:
				var gun = owner.gun_controller.current_gun
				if gun is PistolWaterGun and gun.is_super_active:
					if aim_entry_timer <= 0.0 and owner.is_aim_transition_complete():
						_trigger_shot()
					else:
						is_shot_queued = true
						if owner.has_method("boost_aim_transition_fast"):
							owner.boost_aim_transition_fast()
						aim_entry_timer = min(aim_entry_timer, 0.1)
						set_gun_aim_anim()
				
	# If aim button was released, exit once shot animation is done and no shot is queued
	if not Input.is_action_pressed("aim") and shot_exit_lock_timer <= 0.0 and not is_shot_queued and not is_waiting_quick_shot_delay:
		owner.is_aimming = false
		_evaluate_queued_exit()
	
func _exit() -> void:
	owner.is_aimming = false
	owner.cross_hair.visible = false
	aim_entry_timer = default_aim_entry_duration
	is_shot_queued = false
	is_waiting_quick_shot_delay = false
	quick_shot_delay_timer = 0.0
	if "target_aim_speed_multiplier" in owner:
		owner.target_aim_speed_multiplier = 1.0
	if "aim_speed_multiplier" in owner:
		owner.aim_speed_multiplier = 1.0
	if owner.camera and owner.camera.has_method("exit_aim"):
		owner.camera.exit_aim()
	


func _state_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quick_turn") and not owner.is_quick_turn and owner.quick_turn_cooldown <= 0.0:
		if shot_exit_lock_timer <= 0.0 and not is_shot_queued and not is_waiting_quick_shot_delay:
			finished.emit("Quick_turn")
	if Input.is_action_just_released("aim") :
		if shot_exit_lock_timer <= 0.0 and not is_shot_queued and not is_waiting_quick_shot_delay:
			owner.is_aimming = false
			_evaluate_queued_exit()
	if Input.is_action_just_pressed("Reload") :
		if shot_exit_lock_timer <= 0.0 and not is_shot_queued and not is_waiting_quick_shot_delay:
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
	if Input.is_action_just_pressed("click"):
		if owner.gun_controller and owner.gun_controller.current_gun:
			var gun = owner.gun_controller.current_gun
			if not (gun is PistolWaterGun and gun.is_super_active):
				if aim_entry_timer <= 0.0 and owner.is_aim_transition_complete():
					_trigger_shot()
				else:
					is_shot_queued = true
					if owner.has_method("boost_aim_transition_fast"):
						owner.boost_aim_transition_fast()
					aim_entry_timer = min(aim_entry_timer, 0.15)
					set_gun_aim_anim()

func _trigger_shot() -> void:
	if _is_firing_shot:
		return
	if not owner.gun_controller or not owner.gun_controller.current_gun:
		return
	var gun = owner.gun_controller.current_gun
	if not gun.can_shoot():
		return
		
	_is_firing_shot = true
	if "target_aim_speed_multiplier" in owner:
		owner.target_aim_speed_multiplier = 1.0
	if "aim_speed_multiplier" in owner:
		owner.aim_speed_multiplier = 1.0
	set_gun_aim_anim()
	
	# Trigger the shot recoil animation
	owner.anim.set("parameters/Main/Aim/BlendTree/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	owner.notify_shot_fired()
	
	# Fire the projectile, VFX, and sound
	gun.shoot()
	
	# Lock aim exit until 100% of the shot animation has finished
	var shot_dur = gun.shoot_interval if gun else 0.3
	shot_exit_lock_timer = shot_dur
	
	_is_firing_shot = false


func switch_gun(num:int):
	if owner.gun_controller:
		owner.gun_controller.switch_gun(num)
		set_gun_aim_anim()

func set_gun_aim_anim():
	if not owner.gun_controller or not owner.gun_controller.current_gun or not owner.anim:
		return
	var gun_name = owner.gun_controller.current_gun.get_gun_name()
	if gun_name == "Water pistol":
		owner.anim.set("parameters/Main/Aim/BlendTree/Transition/transition_request", "pis")
	elif gun_name == "Water shotgun":
		owner.anim.set("parameters/Main/Aim/BlendTree/Transition/transition_request", "shot")
	elif gun_name == "Water sniper":
		owner.anim.set("parameters/Main/Aim/BlendTree/Transition/transition_request", "rifle")

func _evaluate_queued_exit() -> void:
	var is_move = Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_down") or Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right") or (typeof(Motion) != TYPE_NIL and Motion.input_dir != Vector2.ZERO)
	if is_move:
		finished.emit("Run")
	else:
		finished.emit("Idle")

func stop_moving():
	Motion.velocity = Vector3.ZERO
	Motion.input_dir = Vector2.ZERO
	owner.set_velocity_from_motion(Vector3.ZERO)
