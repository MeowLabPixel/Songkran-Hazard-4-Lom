extends State

@export var post_grab_delay: float = 1.35

var half = false
var fail_anim = "Grab/Fail"
var win_anim ="Grab/Win"
var mini_done = false
var is_exiting = false
var is_grab: bool = false
var last_anim: String
var _camera_state: int = 0

func _process(_delta: float) -> void:
	if is_exiting and last_anim == fail_anim:
		if owner and owner.anim:
			var pb = owner.anim.get("parameters/Grab/playback")
			if pb:
				var current_node = String(pb.get_current_node())
				if current_node == "Fail" and _camera_state == 0:
					_camera_state = 1
					var cam = owner.get_node_or_null("Camera")
					if cam and cam.has_method("set_action_offset_y"):
						# Smoothly lower the camera by 1.2 meters over 0.5 seconds
						cam.set_action_offset_y(-1.2, 0.5)
				elif current_node == "Getup" and _camera_state == 1:
					_camera_state = 2
					var cam = owner.get_node_or_null("Camera")
					if cam and cam.has_method("set_action_offset_y"):
						# Smoothly raise the camera back to normal over 1.0 seconds
						cam.set_action_offset_y(0.0, 1.0)


func _enter() -> void:
	print(name)
	stop_moving()
	owner.aim_bone_on(false)

	# Block all other enemies from attacking while player is grabbed
	get_tree().call_group("enemies", "set", "attack_blocked", true)

	owner.anim.get("parameters/playback").travel("Grab")
	owner.hitboxF.monitoring = false
	owner.hitboxB.monitoring = false
	is_exiting = false
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(_grab_fallback)

func _grab_fallback() -> void:
	print("Idle from Fallback.")
	if last_anim == win_anim:
		finished.emit("Idle")

func _exit() -> void:

	owner.start_qte = false
	owner.qte_bar.value = 0
	is_exiting = false
	mini_done = false
	owner.is_grab = false
	_camera_state = 0

	# Unblock enemy attacks after grab is over
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(get_tree()):
			get_tree().call_group("enemies", "set", "attack_blocked", false)
	)
	
	var cam = owner.get_node_or_null("Camera")
	if cam and cam.has_method("set_action_offset_y"):
		cam.set_action_offset_y(0.0, 0.5) # Failsafe reset
	
	owner.hitboxF.monitoring = true
	owner.hitboxB.monitoring = true
	# Disconnect animation callback to avoid duplicate connections
	if owner.anim and owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.disconnect(anim_done)

func resolve_grab(success: bool) -> void:

	owner.is_grab = true
	is_exiting = true
	

	if success:
		# Player LOST QTE (grab success)
		owner.anim.get("parameters/Grab/playback").travel("Fail")
		last_anim = fail_anim
	else:
		# Player ESCAPED
		owner.anim.get("parameters/Grab/playback").travel("Win")
		last_anim = win_anim

	if not owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.connect(anim_done)

func anim_done(_namee: String):
	owner.is_grab = false
	print("[Grab] anim_done received: ", _namee)
	if post_grab_delay > 0.0:
		await get_tree().create_timer(post_grab_delay).timeout
	finished.emit("Idle")

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)


func on_grabbed(success: bool) -> void:
	is_grab = success
