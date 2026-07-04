extends State

@export var post_grab_delay: float = 1.35

@export_group("Camera Adjustments")
@export var qte_lose_cam_offset: float = -1.2
@export var qte_lose_cam_pitch: float = -10.0
@export var qte_lose_cam_spring_offset: float = 2.0
@export var qte_lose_cam_duration_down: float = 0.5
@export var qte_lose_cam_duration_up: float = 1.0

@export var qte_win_cam_offset: float = 1.2
@export var qte_win_cam_pitch: float = 10.0
@export var qte_win_cam_spring_offset: float = 2.0
@export var qte_win_cam_duration_up: float = 0.5
@export var qte_win_cam_duration_down: float = 1.0

var half = false
var fail_anim = "Grab/Fail"
var win_anim ="Grab/Win"
var mini_done = false
var is_exiting = false
var is_grab: bool = false
var last_anim: String
var _camera_state: int = 0
var _transition_emitted: bool = false

func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	if not is_exiting:
		# Failsafe: Prevent the AnimationTree from automatically transitioning to Win or Fail
		# if the player hasn't actually won or failed the QTE yet.
		if owner and owner.anim:
			var pb = owner.anim.get("parameters/Grab/playback")
			if pb:
				var current_node = String(pb.get_current_node())
				if current_node in ["Win", "Fail", "Getup", "End"]:
					print("[PlayerGrab] Prevented premature transition to: ", current_node)
					pb.start("Grab")
		return

	if is_exiting:
		if last_anim == fail_anim:
			if owner and owner.anim:
				var pb = owner.anim.get("parameters/Grab/playback")
				if pb:
					var current_node = String(pb.get_current_node())
					if current_node == "Fail" and _camera_state == 0:
						_camera_state = 1
						var cam = owner.get_node_or_null("Camera")
						if cam:
							if cam.has_method("set_action_offset_y"):
								cam.set_action_offset_y(qte_lose_cam_offset, qte_lose_cam_duration_down)
							if cam.has_method("set_action_pitch"):
								cam.set_action_pitch(qte_lose_cam_pitch, qte_lose_cam_duration_down)
							if cam.has_method("set_action_spring_length"):
								cam.set_action_spring_length(qte_lose_cam_spring_offset, qte_lose_cam_duration_down)
					elif current_node == "Getup" and _camera_state == 1:
						_camera_state = 2
						var cam = owner.get_node_or_null("Camera")
						if cam:
							if cam.has_method("set_action_offset_y"):
								cam.set_action_offset_y(0.0, qte_lose_cam_duration_up)
							if cam.has_method("set_action_pitch"):
								cam.set_action_pitch(0.0, qte_lose_cam_duration_up)
							if cam.has_method("set_action_spring_length"):
								cam.set_action_spring_length(0.0, qte_lose_cam_duration_up)
		elif last_anim == win_anim:
			if owner and owner.anim:
				var pb = owner.anim.get("parameters/Grab/playback")
				if pb:
					var current_node = String(pb.get_current_node())
					if current_node == "Win" and _camera_state == 0:
						_camera_state = 1
						var cam = owner.get_node_or_null("Camera")
						if cam:
							if cam.has_method("set_action_offset_y"):
								cam.set_action_offset_y(qte_win_cam_offset, qte_win_cam_duration_up)
							if cam.has_method("set_action_pitch"):
								cam.set_action_pitch(qte_win_cam_pitch, qte_win_cam_duration_up)
							if cam.has_method("set_action_spring_length"):
								cam.set_action_spring_length(qte_win_cam_spring_offset, qte_win_cam_duration_up)
					elif current_node != "Win" and _camera_state == 1:
						_camera_state = 2
						var cam = owner.get_node_or_null("Camera")
						if cam:
							if cam.has_method("set_action_offset_y"):
								cam.set_action_offset_y(0.0, qte_win_cam_duration_down)
							if cam.has_method("set_action_pitch"):
								cam.set_action_pitch(0.0, qte_win_cam_duration_down)
							if cam.has_method("set_action_spring_length"):
								cam.set_action_spring_length(0.0, qte_win_cam_duration_down)
		# Detect when the final animation has finished (node reaches "End")
		if not _transition_emitted:
			if owner and owner.anim:
				var pb_check = owner.anim.get("parameters/Grab/playback")
				if pb_check:
					var node_now = String(pb_check.get_current_node())
					if node_now == "End":
						_transition_emitted = true
						owner.is_grab = false
						print("[PlayerGrab] Final animation done, transitioning to Idle")
						finished.emit("Idle")


func _enter() -> void:
	set_process(true)
	print(name)
	stop_moving()
	owner.aim_bone_on(false)
	owner.is_stunned = true
	owner.is_grab = true
	
	# Clear Motion's static vars so held movement keys can't carry velocity into/out of grab
	Motion.input_dir = Vector2.ZERO
	Motion.direction = Vector3.ZERO
	Motion.velocity = Vector3.ZERO

	# Block all other enemies from attacking while player is grabbed
	get_tree().call_group("enemies", "set", "attack_blocked", true)

	# Disable physical collision with enemies so rotating the player doesn't cause Godot's physics to push them across the floor
	owner.set_collision_mask_value(3, false)
	owner.set_collision_layer_value(2, false)

	owner.anim.get("parameters/playback").travel("Grab")
	owner.hitboxF.monitoring = false
	owner.hitboxB.monitoring = false
	owner.hitboxF.monitorable = false
	owner.hitboxB.monitorable = false
	is_exiting = false
	_transition_emitted = false
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(_grab_fallback)

func _grab_fallback() -> void:
	print("[PlayerGrab] Stuck grab fallback triggered. Forcing transition to Idle.")
	finished.emit("Idle")

func _exit() -> void:
	set_process(false)
	owner.start_qte = false
	owner.qte_bar.value = 0
	
	# If the grab state was aborted prematurely (e.g., zombie died), we must force the AnimationTree to End
	if not is_exiting:
		var sub_pb = owner.anim.get("parameters/Grab/playback")
		if sub_pb:
			sub_pb.travel("End")
			
	is_exiting = false
	mini_done = false
	owner.is_grab = false
	owner.is_stunned = false
	_camera_state = 0
	_transition_emitted = false

	# Unblock enemy attacks after grab is over
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(get_tree()):
			get_tree().call_group("enemies", "set", "attack_blocked", false)
	)
	
	var cam = owner.get_node_or_null("Camera")
	if cam:
		if cam.has_method("set_action_offset_y"):
			cam.set_action_offset_y(0.0, 0.5) # Failsafe reset
		if cam.has_method("set_action_pitch"):
			cam.set_action_pitch(0.0, 0.5) # Failsafe reset
		if cam.has_method("set_action_spring_length"):
			cam.set_action_spring_length(0.0, 0.5) # Failsafe reset
	
	owner.hitboxF.monitoring = true
	owner.hitboxB.monitoring = true
	owner.hitboxF.monitorable = true
	owner.hitboxB.monitorable = true
	
	# Re-enable physical collision with enemies
	owner.set_collision_mask_value(3, true)
	owner.set_collision_layer_value(2, true)
	


func resolve_grab(success: bool) -> void:
	var sm = get_parent()
	if sm and "current_state" in sm and sm.current_state != self:
		print("[PlayerGrab] resolve_grab ignored because player is not in Grab state. Current state: ", sm.current_state.name if sm.current_state else "null")
		return

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



func _update(_delta: float) -> void:
	# Continuously force velocity to zero so held movement keys can't push the player
	Motion.input_dir = Vector2.ZERO
	Motion.direction = Vector3.ZERO
	Motion.velocity = Vector3.ZERO
	owner.velocity.x = 0.0
	owner.velocity.z = 0.0

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)


func on_grabbed(success: bool) -> void:
	is_grab = success
