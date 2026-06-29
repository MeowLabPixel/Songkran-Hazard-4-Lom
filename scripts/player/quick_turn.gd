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
	if owner.anim.get(owner.anim_playback).get_current_node() != "QT":
		owner.anim.get(owner.anim_playback).travel("QT")
	quick_turn()
	owner.aim_bone_on(false)
	if not owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.connect(anim_done)


func _exit() -> void:
	_exited = true
	
	owner.is_quick_turn = false
	owner.quick_turn_cooldown = owner.quick_turn_cooldown_duration # Use the exported inspector variable!
	
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
	
	var tween:= create_tween() as Tween
	# Add inertia/smoothing effect to the turn
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(owner,"rotation:y",traget_y_rotation,owner.quick_turn_speed)
	# Do NOT set is_quick_turn = false here, or the player can spam the button before the state finishes!
	tween.finished.connect(func(): 
		owner.camera.camera_rotation.x += PI
		owner.camera.target_camera_rotation.x += PI
	)

	# Safety fallback: if animation/anim_done doesn't fire, ensure we exit quick turn
	var fallback_time: float = owner.quick_turn_speed + 0.2
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
		#one shot anim

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
	print("[QuickTurn] anim_done fired: ", namee)  # remove after debugging
	if not _exited and namee == QT_anim:
		finished.emit("Idle")

func _qt_fallback_timeout() -> void:
	if not _exited:
		owner.is_quick_turn = false
		finished.emit("Idle")

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)
