extends State

@export var post_grab_delay: float = 1.35

@export_group("QTE Pushback")
@export var player_push_speed: float = 4.0
@export var player_push_decay: float = 4.0
@export var enemy_push_radius: float = 1.5

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
var _pushed_enemies: Array[Node] = []
var _time_in_grab: float = 0.0
var _push_velocity: float = 0.0
var _current_grabber: Node = null
var max_grab_duration: float = 8.0
var _grab_loop_player: AudioStreamPlayer3D = null


func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	# Tick the grab timer
	_time_in_grab += _delta
	if _time_in_grab >= max_grab_duration:
		print("[PlayerGrab] Stuck grab fallback triggered. Forcing transition via queued exit.")
		_evaluate_queued_exit()
		return



	if not is_exiting:
		# Guard the ROOT playback during QTE loop only.
		# The root may auto-advance away from "Grab"; force it back
		# so the sub-playback stays alive. We DON'T guard during
		# is_exiting because we WANT End->Main to happen naturally.
		if owner and owner.anim:
			var root_pb = owner.anim.get("parameters/playback")
			if root_pb:
				var root_node = String(root_pb.get_current_node())
				if root_node != "Grab":
					print("[PlayerGrab] Root playback left 'Grab' (was: ", root_node, "). Forcing back during QTE loop.")
					root_pb.travel("Grab")

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
		_push_nearby_enemies()
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
		# Detect when the grab animation path completes naturally
		# (Root leaves "Grab" -> entered "Main" = all animations finished)
		if not _transition_emitted:
			var root_pb = owner.anim.get("parameters/playback")
			if root_pb:
				var root_node = String(root_pb.get_current_node())
				if root_node != "Grab":
					_transition_emitted = true
					owner.is_grab = false
					print("[PlayerGrab] Grab animation path completed (root reached: ", root_node, ")")
					if last_anim == win_anim:
						SoundManager.play_3d("vo_leon_grab_winend", owner)
						var followers = owner.get_tree().get_nodes_in_group("Anchalee")
						if followers.size() > 0:
							var follower = followers[0]
							if is_instance_valid(follower):
								var health = follower.get("health")
								if health != null and health > 0:
									SoundManager.play_3d("vo_anchalee_after_gethit", follower)
					_evaluate_queued_exit()

func _evaluate_queued_exit() -> void:
	var is_aim = Input.is_action_pressed("aim")
	if is_aim and is_instance_valid(owner) and owner.has_method("can_aim") and owner.can_aim():
		owner.aim_blocked_until_release = false
		finished.emit("Aim")
		return
	var is_move = Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_down") or Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right") or (typeof(Motion) != TYPE_NIL and Motion.input_dir != Vector2.ZERO)
	if is_move:
		finished.emit("Run")
	else:
		finished.emit("Idle")


func _enter() -> void:
	set_process(true)
	print(name)
	stop_moving()
	owner.cancel_aim()
	owner.is_stunned = true
	owner.is_grab = true
	
	_grab_loop_player = SoundManager.play_3d("grab_sucess_loop", owner)
	
	# Play Anchalee worried voiceline 1.0 second after player gets grabbed
	var timer = owner.get_tree().create_timer(1.0)
	timer.timeout.connect(func():
		if is_instance_valid(owner) and owner.is_grab:
			var followers = owner.get_tree().get_nodes_in_group("Anchalee")
			if followers.size() > 0:
				var follower = followers[0]
				if is_instance_valid(follower):
					var health = follower.get("health")
					if health != null and health > 0:
						SoundManager.play_3d("vo_anchalee_player_gethit", follower)
	)
	
	# Clear Motion's static vars so held movement keys can't carry velocity into/out of grab
	Motion.input_dir = Vector2.ZERO
	Motion.direction = Vector3.ZERO
	Motion.velocity = Vector3.ZERO

	# Block all other enemies from attacking while player is grabbed
	get_tree().call_group("enemies", "set", "attack_blocked", true)
	
	# Disable all zombie attack/grab hitboxes
	_set_all_enemy_hitboxes(false)

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
	
	# Reset the grab timer and calculate max duration dynamically
	_time_in_grab = 0.0
	var qte_len = 1.5
	_current_grabber = owner._last_grabber
	if is_instance_valid(_current_grabber):
		var sm = _current_grabber.get_node_or_null("EnemyStateMachine")
		if sm and sm.has_node("StateAttack"):
			var sa = sm.get_node("StateAttack")
			if "qte_duration" in sa:
				qte_len = sa.qte_duration
	max_grab_duration = qte_len + 5.0 # QTE duration + 5.0 seconds for win/fail/getup animation paths
	print("[PlayerGrab] Grab started. Max grab duration: ", max_grab_duration)
	_push_surrounding_enemies_on_grab_enter()

func _push_surrounding_enemies_on_grab_enter() -> void:
	if not owner or not is_instance_valid(owner):
		return
	var player_pos = owner.global_position
	var grabber_pos = _current_grabber.global_position if is_instance_valid(_current_grabber) else player_pos

	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_defeated or enemy == _current_grabber:
			continue
		var dist_player = player_pos.distance_to(enemy.global_position)
		var dist_grabber = grabber_pos.distance_to(enemy.global_position)
		if dist_player <= 1.5 or dist_grabber <= 1.5:
			var push_dir = (enemy.global_position - player_pos)
			push_dir.y = 0.0
			if push_dir.length() < 0.1:
				push_dir = -owner.global_transform.basis.z
			push_dir = push_dir.normalized()
			
			if enemy.has_method("take_hit"):
				enemy.take_hit({
					"damage": 0.0,
					"hit_zone": "body",
					"hit_type": "push",
					"hit_direction": push_dir,
					"source": owner
				})
				print("[PlayerGrab] Pushed away nearby enemy: ", enemy.name, " on grab enter within 1.5m")

func _exit() -> void:
	set_process(false)
	
	# Stop looping grab sound if not already stopped
	if _grab_loop_player and is_instance_valid(_grab_loop_player):
		_grab_loop_player.stop()
		_grab_loop_player = null
		
	# If the grab state was aborted prematurely (e.g., zombie died), we must force the AnimationTree to End
	if not is_exiting:
		var sub_pb = owner.anim.get("parameters/Grab/playback")
		if sub_pb:
			sub_pb.travel("End")
			
	is_exiting = false
	last_anim = ""
	mini_done = false
	owner.is_grab = false
	owner.is_stunned = false
	_current_grabber = null
	_camera_state = 0
	_transition_emitted = false
	owner.aim_blocked_until_release = false

	# Unblock enemy attacks after grab is over
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(get_tree()):
			get_tree().call_group("enemies", "set", "attack_blocked", false)
	)
	
	# Re-enable all zombie attack/grab hitboxes
	_set_all_enemy_hitboxes(true)
	
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
	_pushed_enemies.clear()
	
	# Reset the fallback timer so Win/Fail + Getup animations get their full duration
	_time_in_grab = 0.0
	max_grab_duration = 5.0 # 5 seconds is plenty for win/fail/getup animation paths
	
	# Start decaying pushback for the player
	_push_velocity = player_push_speed
	

	# Stop looping grab sound when QTE is resolved
	if _grab_loop_player and is_instance_valid(_grab_loop_player):
		_grab_loop_player.stop()
		_grab_loop_player = null

	if success:
		# Player LOST QTE (grab success)
		owner.anim.get("parameters/Grab/playback").start("Fail")
		last_anim = fail_anim
		# Play QTE Fail sound!
		SoundManager.play_3d("leon_grab_fail", owner)
	else:
		# Player ESCAPED
		owner.anim.get("parameters/Grab/playback").start("Win")
		last_anim = win_anim
		# Play QTE Win/Success sound!
		SoundManager.play_3d("leon_grab_success", owner)



func _update(_delta: float) -> void:
	# Continuously force velocity to zero so held movement keys can't push the player
	Motion.input_dir = Vector2.ZERO
	Motion.direction = Vector3.ZERO
	Motion.velocity = Vector3.ZERO
	
	if is_exiting and _push_velocity > 0.0:
		# Decay the push speed toward zero (similar to zombie StateHitPush)
		_push_velocity = move_toward(_push_velocity, 0.0, player_push_decay * _delta)
		# Push backward relative to player's facing direction (+Z = backward in Godot)
		var push_dir = owner.global_transform.basis.z
		push_dir.y = 0.0
		push_dir = push_dir.normalized()
		owner.velocity.x = push_dir.x * _push_velocity
		owner.velocity.z = push_dir.z * _push_velocity
	else:
		owner.velocity.x = 0.0
		owner.velocity.z = 0.0

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)


func on_grabbed(success: bool) -> void:
	is_grab = success

func _push_nearby_enemies() -> void:
	if not owner or not owner.anim:
		return
		
	var pb = owner.anim.get("parameters/Grab/playback")
	if not pb:
		return
		
	var current_node = String(pb.get_current_node())
	# Only push during Win or Fail animations (not Getup or End)
	if current_node != "Win" and current_node != "Fail":
		return
		
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_defeated or enemy in _pushed_enemies or enemy == _current_grabber:
			continue
			
		var dist = owner.global_position.distance_to(enemy.global_position)
		print("[PlayerGrab debug] Checking enemy: ", enemy.name, " at dist: ", dist, " (limit: ", enemy_push_radius, ")")
		if dist <= enemy_push_radius:
			_pushed_enemies.append(enemy)
			var push_dir = (enemy.global_position - owner.global_position).normalized()
			push_dir.y = 0.0
			push_dir = push_dir.normalized()
			
			if enemy.has_method("take_hit"):
				print("[PlayerGrab debug] Calling take_hit on ", enemy.name, " with push direction: ", push_dir)
				enemy.take_hit({
					"damage": 0.0,
					"hit_zone": "body",
					"hit_type": "push",
					"hit_direction": push_dir,
					"source": owner
				})
				print("[PlayerGrab] Pushed back enemy: ", enemy.name, " during animation: ", current_node)

func _set_all_enemy_hitboxes(enabled: bool) -> void:
	var areas = get_tree().get_nodes_in_group("enemy_attack")
	for area in areas:
		if area is Area3D:
			area.monitoring = enabled
			area.monitorable = enabled
