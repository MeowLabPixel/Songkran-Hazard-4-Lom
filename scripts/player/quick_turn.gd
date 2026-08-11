extends State

var anim_node = "parameters/Main/QT/"
var QT_anim = "QT/Base"
var _exited: bool = false

func _enter() -> void:
	print(name)
	_exited = false
	
	# Completely disable input processing for the player and camera during QuickTurn
	owner.set_process_input(false)
	owner.set_process_unhandled_input(false)
	if owner.camera:
		owner.camera.set_process_input(false)
		owner.camera.set_process_unhandled_input(false)
		owner.camera.exit_aim() # Force the camera and player out of the aiming state!
		
	stop_moving()
	set_gun_anim()
	if owner.anim:
		owner.anim.set("parameters/Main/QT/Pis/TimeScale/scale", 1.5)
		owner.anim.set("parameters/Main/QT/Shot/TimeScale/scale", 1.5)
		# Force-reset QT Blend2 to 0.0 so the sidestep layer starts clean
		owner.anim.set("parameters/Main/QT/Pis/Blend2/blend_amount", 0.0)
		owner.anim.set("parameters/Main/QT/Shot/Blend2/blend_amount", 0.0)
	# Reset idle turn state so the 180° tween rotation doesn't activate sidestepping
	owner._is_turning = false
	owner._is_returning_to_neutral = false
	owner._turn_direction = 0.0
	owner._peak_blend = 0.0
	SoundManager.play_3d("leon_quickturn", owner)
	if owner.anim.get(owner.anim_playback).get_current_node() != "QT":
		owner.anim.get(owner.anim_playback).travel("QT")
	quick_turn()
	owner.aim_bone_on(false)
	if not owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.connect(anim_done)


func _exit() -> void:
	_exited = true
	
	# Force camera rotation to match the player's exact orientation
	# to prevent any visual snaps when is_quick_turn becomes false!
	if owner.camera:
		owner.camera.camera_rotation.x = -owner.rotation.y
		owner.camera.target_camera_rotation.x = -owner.rotation.y
		
	owner.is_quick_turn = false
	owner.quick_turn_cooldown = owner.quick_turn_cooldown_duration # Use the exported inspector variable!
	
	# Cleanly reset movement velocity and BlendSpace2D positions on exit to guarantee smooth foot blending
	Motion.velocity = Vector3.ZERO
	if owner.anim:
		owner.anim.set("parameters/Main/Run/Pis/BlendSpace2D/blend_position", Vector2.ZERO)
		owner.anim.set("parameters/Main/Run/Shot/BlendSpace2D/blend_position", Vector2.ZERO)
		owner.anim.set("parameters/Main/Run/Pis/TimeScale/scale", 1.0)
		owner.anim.set("parameters/Main/Run/Shot/TimeScale/scale", 1.0)
	
	# Re-enable input processing
	owner.set_process_input(true)
	owner.set_process_unhandled_input(true)
	if owner.camera:
		owner.camera.set_process_input(true)
		owner.camera.set_process_unhandled_input(true)
		
	# Clean up animation callback to avoid duplicate connections
	if owner.anim and owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.disconnect(anim_done)

func _update(_delta:float) -> void:
	# Force horizontal velocity to 0 every frame so WASD input physically cannot move the player
	owner.velocity.x = 0.0
	owner.velocity.z = 0.0
	if not owner.is_on_floor():
		owner.velocity.y -= 9.8 * _delta
		
	if owner.HP <= 0:
		finished.emit("Die")
	
func quick_turn():
	owner.is_quick_turn =true
	var traget_y_rotation = owner.rotation.y + -PI
	
	# Smoothly zoom out the camera slightly during the quick turn to make it feel cinematic and less abrupt
	if owner.camera:
		owner.camera.set_action_spring_length(0.8, owner.quick_turn_speed * 0.5)
		var zoom_back_tween = create_tween()
		zoom_back_tween.tween_interval(owner.quick_turn_speed * 0.5)
		zoom_back_tween.tween_callback(func():
			if owner.camera:
				owner.camera.set_action_spring_length(0.0, owner.quick_turn_speed * 0.5)
		)
	
	var tween:= create_tween() as Tween
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Tween the player character's rotation
	tween.tween_property(owner,"rotation:y",traget_y_rotation,owner.quick_turn_speed)
	
	# Tween the camera's internal rotation to match the transition smoothly in parallel
	if owner.camera:
		var target_cam = Vector2(owner.camera.camera_rotation.x + PI, owner.camera.camera_rotation.y)
		var target_target_cam = Vector2(owner.camera.target_camera_rotation.x + PI, owner.camera.target_camera_rotation.y)
		tween.tween_property(owner.camera, "camera_rotation", target_cam, owner.quick_turn_speed)
		tween.tween_property(owner.camera, "target_camera_rotation", target_target_cam, owner.quick_turn_speed)

	# Safety fallback: if animation/anim_done doesn't fire, ensure we exit quick turn
	var fallback_time: float = owner.quick_turn_speed + 0.6
	var timer := get_tree().create_timer(fallback_time)
	timer.timeout.connect(_qt_fallback_timeout)
	
func _state_input(event: InputEvent) -> void:
	if Input.is_action_pressed("Gun1"):
		switch_gun(0)
	if Input.is_action_pressed("Gun2"):
		switch_gun(1)
	if Input.is_action_pressed("Gun3"):
		switch_gun(2)

func switch_gun(num:int):
	if owner.gun_controller:
		owner.gun_controller.switch_gun(num)
		set_gun_anim()

func set_gun_anim():
	if not owner.gun_controller or not owner.gun_controller.current_gun:
		return
	if owner.gun_controller.current_gun.get_gun_name() == "Water pistol":
		owner.anim.set(anim_node + "conditions/pis",true)
		owner.anim.set(anim_node + "conditions/shot",false)
		if owner.anim.get(anim_node + "playback").get_current_node() != "Pis":
			owner.anim.get(anim_node + "playback").travel("Pis")
	elif owner.gun_controller.current_gun.get_gun_name() == "Water shotgun" or owner.gun_controller.current_gun.get_gun_name() == "Water sniper":
		owner.anim.set(anim_node + "conditions/pis",false)
		owner.anim.set(anim_node + "conditions/shot",true)
		if owner.anim.get(anim_node + "playback").get_current_node() != "Shot":
			owner.anim.get(anim_node + "playback").travel("Shot")

func anim_done(namee: String):
	print("[QuickTurn] anim_done fired: ", namee)
	var is_qt_anim = (
		namee == "QT/Base" or 
		namee == "Pis" or 
		namee == "Shot" or 
		namee == "QT/Pis" or 
		namee == "QT/Shot" or 
		namee.ends_with("Pis") or 
		namee.ends_with("Shot")
	)
	if not _exited and is_qt_anim:
		var next_state = "Run" if Motion.input_dir != Vector2.ZERO else "Idle"
		finished.emit(next_state)

func _qt_fallback_timeout() -> void:
	if not _exited:
		if owner.camera:
			owner.camera.camera_rotation.x = -owner.rotation.y
			owner.camera.target_camera_rotation.x = -owner.rotation.y
		owner.is_quick_turn = false
		var next_state = "Run" if Motion.input_dir != Vector2.ZERO else "Idle"
		finished.emit(next_state)

func stop_moving():
	Motion.velocity = Vector3.ZERO
	owner.set_velocity_from_motion(Vector3.ZERO)
