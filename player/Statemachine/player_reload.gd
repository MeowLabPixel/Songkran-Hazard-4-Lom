extends State

var reload_anim = "RR/re"
var _exited: bool = false
var _pump_cooldown_timer: float = 0.2
var qte_hud = null
var _time_in_state: float = 0.0
var _is_superpump_active: bool = false

@export_group("QTE Customization")
@export var block_movement_during_qte: bool = true
@export var block_aiming_during_qte: bool = true
@export var can_cancel_qte_via_aim: bool = false
@export var can_cancel_qte_via_movement: bool = false
@export var qte_duration: float = 2.0
@export var qte_prompt_count_override: int = 0 # If 0, uses start_air-based dynamic count (1 to 4)
@export var qte_target_zone_size: float = 0.0 # If 0.0, uses default difficulty-scaled size
@export var qte_show_progress_bar: bool = false
@export var superpump_hold_duration: float = 0.6
@export var fail_ends_reload: bool = true

@export_group("Shotgun Reload Customization")
@export var shotgun_hold_duration: float = 0.7
@export var shotgun_qte_window: float = 0.2
@export var shotgun_normal_air_gain: float = 30.0
@export var shotgun_qte_air_gain: float = 40.0

func _is_pistol(gun) -> bool:
	return gun != null and (gun.gun_name == "Water pistol" or (owner.gun_controller and owner.gun_controller.current_gun_index == 0))

func _is_shotgun(gun) -> bool:
	return gun != null and (gun.gun_name == "Water shotgun" or (owner.gun_controller and owner.gun_controller.current_gun_index == 1))
 
func _enter() -> void:
	_exited = false
	_time_in_state = 0.0
	stop_moving()
	owner.is_aimming = false
	owner.aim_bone_on(false)
	

	# Transition camera into aim mode (reload uses the same camera as aim, without showing crosshair)
	var cam = owner.get_node_or_null("Camera")
	if cam and cam.has_method("enter_aim"):
		cam.enter_aim(false)
	
	_pump_cooldown_timer = 0.2

	# If no gun controller or gun, leave immediately
	if not owner.gun_controller or not owner.gun_controller.current_gun:
		finished.emit("Idle")
		return

	var gun = owner.gun_controller.current_gun
	if gun.is_super_active:
		finished.emit("Idle")
		return
	if _is_pistol(gun):
		# Start QTE reload hud for pistol using pre-existing UI node
		var hud_node = get_tree().get_first_node_in_group("reload_qte_hud") as ReloadQteHud
		if hud_node:
			qte_hud = hud_node
			
			# Assign custom inspector settings dynamically
			qte_hud.duration = qte_duration
			qte_hud.prompt_count_override = qte_prompt_count_override
			qte_hud.prompt_size_override = qte_target_zone_size
			qte_hud.show_progress_bar = qte_show_progress_bar
			qte_hud.superpump_required_hold = superpump_hold_duration
			qte_hud.fail_ends_reload = fail_ends_reload
			
			if not qte_hud.qte_hit.is_connected(_on_qte_hit):
				qte_hud.qte_hit.connect(_on_qte_hit)
			if not qte_hud.finished.is_connected(_on_reload_finished):
				qte_hud.finished.connect(_on_reload_finished)
			if not qte_hud.cancelled.is_connected(_on_reload_cancelled):
				qte_hud.cancelled.connect(_on_reload_cancelled)
			if qte_hud.has_signal("superpump_started") and not qte_hud.superpump_started.is_connected(_on_superpump_started):
				qte_hud.superpump_started.connect(_on_superpump_started)
			if qte_hud.has_signal("superpump_completed") and not qte_hud.superpump_completed.is_connected(_on_superpump_completed):
				qte_hud.superpump_completed.connect(_on_superpump_completed)
				
			qte_hud.start(gun.air, gun.max_air)
		
		# Travel to main Reload state with smooth crossfade
		var main_pb = owner.anim.get(owner.anim_playback)
		if main_pb:
			main_pb.travel("Reload")
		
		# Set Reload timescale to half speed
		owner.anim.set("parameters/Main/Reload/Reload/TimeScale/scale", 0.5)
		
		# Travel to SuperPump or Reload in sub-state machine based on air
		var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
		if sub_pb:
			if gun.air >= gun.max_air:
				_is_superpump_active = true
				if sub_pb.get_current_node() == "End" or sub_pb.get_current_node() == "":
					sub_pb.start("SuperPump")
				else:
					sub_pb.travel("SuperPump")
				var superpump_pb = owner.anim.get("parameters/Main/Reload/SuperPump/playback")
				if superpump_pb:
					superpump_pb.start("SuperPumpStart")
			else:
				_is_superpump_active = false
				if sub_pb.get_current_node() == "End" or sub_pb.get_current_node() == "":
					sub_pb.start("Reload")
				else:
					sub_pb.travel("Reload")
	elif _is_shotgun(gun):
		# Start Hold-Release QTE reload hud for shotgun
		var hud_node = get_tree().get_first_node_in_group("reload_qte_hud") as ReloadQteHud
		if hud_node:
			qte_hud = hud_node
			qte_hud.shotgun_hold_duration = shotgun_hold_duration
			qte_hud.shotgun_qte_window = shotgun_qte_window
			qte_hud.shotgun_normal_air_gain = shotgun_normal_air_gain
			qte_hud.shotgun_qte_air_gain = shotgun_qte_air_gain
			qte_hud.superpump_required_hold = superpump_hold_duration
			qte_hud.show_progress_bar = qte_show_progress_bar
			
			if not qte_hud.qte_hit.is_connected(_on_qte_hit):
				qte_hud.qte_hit.connect(_on_qte_hit)
			if not qte_hud.finished.is_connected(_on_reload_finished):
				qte_hud.finished.connect(_on_reload_finished)
			if not qte_hud.cancelled.is_connected(_on_reload_cancelled):
				qte_hud.cancelled.connect(_on_reload_cancelled)
			if qte_hud.has_signal("superpump_started") and not qte_hud.superpump_started.is_connected(_on_superpump_started):
				qte_hud.superpump_started.connect(_on_superpump_started)
			if qte_hud.has_signal("superpump_completed") and not qte_hud.superpump_completed.is_connected(_on_superpump_completed):
				qte_hud.superpump_completed.connect(_on_superpump_completed)
				
			qte_hud.start_shotgun(gun.air, gun.max_air)
		
		# Travel to main Reload state with smooth crossfade
		var main_pb = owner.anim.get(owner.anim_playback)
		if main_pb:
			main_pb.travel("Reload")
		
		owner.anim.set("parameters/Main/Reload/Reload_Shotgun/TimeScale/scale", 1.0)
		owner.anim.set("parameters/Main/Reload/SuperPump_Shotgun/TimeScale/scale", 0.8)
		
		_is_superpump_active = (gun.air >= gun.max_air)
		var target_shotgun_reload = "SuperPump_Shotgun" if _is_superpump_active else "Reload_Shotgun"
		var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
		if sub_pb:
			sub_pb.start(target_shotgun_reload)
		
		if owner.anim:
			owner.anim.advance(0.0)
			if sub_pb:
				sub_pb.start(target_shotgun_reload)
	else:
		reloading()

func _exit() -> void:
	_exited = true
	var was_superpump = false
	if is_instance_valid(qte_hud):
		_disconnect_qte_signals()
		qte_hud.cancel()
		qte_hud = null
	else:
		var hud = get_tree().get_first_node_in_group("reload_qte_hud") if get_tree() else null
		if is_instance_valid(hud) and hud.visible:
			hud.cancel()
	if is_instance_valid(owner):
		owner.superpump_cooldown = 0.0
		if owner.anim and is_instance_valid(owner.anim):
			if owner.anim.animation_finished.is_connected(anim_done):
				owner.anim.animation_finished.disconnect(anim_done)
			owner.anim.set("parameters/Main/Reload/Reload/TimeScale/scale", 1.0)
			owner.anim.set("parameters/Main/Reload/Reload 2/TimeScale/scale", 1.0)
			owner.anim.set("parameters/Main/Reload/Reload_Quick/TimeScale/scale", 1.5)
			
		# Transition camera out of aim mode if we are not aiming
		if not owner.is_aimming:
			var cam = owner.get_node_or_null("Camera")
			if cam and cam.has_method("exit_aim"):
				cam.exit_aim()
				
		if owner.reload_timer and is_instance_valid(owner.reload_timer):
			if owner.reload_timer.timeout.is_connected(reload_timeout):
				owner.reload_timer.timeout.disconnect(reload_timeout)

func _update(_delta: float) -> void:
	if owner.HP <= 0:
		finished.emit("Die")
		return
		
	_time_in_state += _delta
	if _pump_cooldown_timer > 0.0:
		_pump_cooldown_timer -= _delta
		
	var current_gun = owner.gun_controller.current_gun if owner.gun_controller else null
	if _is_shotgun(current_gun) and owner.anim:
		var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
		if sub_pb:
			var target_node = "SuperPump_Shotgun" if _is_superpump_active else "Reload_Shotgun"
			var cur_node = String(sub_pb.get_current_node())
			if cur_node != target_node and cur_node != "End":
				sub_pb.start(target_node)
		
	# QoL: Aim cancels reload (unless blocked by setting and within 0.3s guard)
	if Input.is_action_just_pressed("aim"):
		var is_active_qte = is_instance_valid(qte_hud) and (qte_hud.mode == "qte" or qte_hud.mode == "shotgun_qte")
		if is_active_qte:
			if can_cancel_qte_via_aim and _time_in_state >= 0.3:
				owner.is_aimming = true
				finished.emit("Aim")
				return
		else:
			owner.is_aimming = true
			finished.emit("Aim")
			return
			
	# QoL: Movement cancels reload (if enabled and within 0.3s guard)
	var up = Input.is_action_pressed("ui_up")
	var down = Input.is_action_pressed("ui_down")
	var left = Input.is_action_pressed("ui_left")
	var right = Input.is_action_pressed("ui_right")
	
	var just_up = Input.is_action_just_pressed("ui_up")
	var just_down = Input.is_action_just_pressed("ui_down")
	var just_left = Input.is_action_just_pressed("ui_left")
	var just_right = Input.is_action_just_pressed("ui_right")
	var has_new_movement_input = just_up or just_down or just_left or just_right
	
	if has_new_movement_input:
		var is_active_qte = is_instance_valid(qte_hud) and (qte_hud.mode == "qte" or qte_hud.mode == "shotgun_qte")
		if is_active_qte and can_cancel_qte_via_movement and _time_in_state >= 0.3:
			finished.emit("Run")
			return
			
	# Gradually fill gun air for water pistol and shotgun based on HUD progress
	if is_instance_valid(qte_hud) and (qte_hud.mode == "qte" or qte_hud.mode == "shotgun_qte"):
		var gun = owner.gun_controller.current_gun
		if gun:
			if qte_hud.mode == "qte":
				gun.air = clampf(qte_hud.start_air + (qte_hud.max_air - qte_hud.start_air) * qte_hud.reload_progress, 0.0, gun.max_air)
			elif qte_hud.mode == "shotgun_qte":
				if qte_hud.resolved:
					gun.air = qte_hud.resolved_air
				else:
					gun.air = clampf(qte_hud.start_air + qte_hud.shotgun_normal_air_gain * qte_hud.reload_progress, 0.0, gun.max_air)
			
		# If movement is allowed, process movement input and apply velocity
		if not block_movement_during_qte:
			var input_dir = Vector2.ZERO
			
			var horizontal = 0.0
			if right: horizontal += 1.0
			if left: horizontal -= 1.0
			var vertical = 0.0
			if down: vertical += 1.0
			if up: vertical -= 1.0
			
			input_dir = Vector2(horizontal, vertical)
			if input_dir.length_squared() > 0.0:
				input_dir = input_dir.normalized()
				
			var direction = owner.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
			var target_speed = 5.0 # Walk speed
			
			var current_vel = owner.velocity
			current_vel.x = move_toward(current_vel.x, direction.x * target_speed, 1000.0 * _delta)
			current_vel.z = move_toward(current_vel.z, direction.z * target_speed, 1000.0 * _delta)
			owner.velocity = current_vel

func _state_input(_event: InputEvent) -> void:
	var gun = owner.gun_controller.current_gun
	if _is_shotgun(gun):
		if is_instance_valid(qte_hud) and qte_hud.resolved and Input.is_action_just_pressed("Reload"):
			gun.air = qte_hud.resolved_air
			if not (gun.is_super_active and gun.air >= gun.max_air):
				get_viewport().set_input_as_handled()
				_enter()
		return
	if _is_pistol(gun):
		# Let the QTE HUD handle input for the pistol
		return
		
	if Input.is_action_just_pressed("Reload"):
		if _pump_cooldown_timer <= 0.0:
			# Only allow pumping again if not in super active mode yet
			if not gun.is_super_active:
				reloading()
				_pump_cooldown_timer = 0.2
			else:
				# Already super active, exit back
				_evaluate_queued_exit()

func reloading() -> void:
	if not owner.gun_controller:
		_evaluate_queued_exit()
		return

	var gun = owner.gun_controller.current_gun
	gun.pump_air()

	# Travel to main Reload state first
	owner.anim.get(owner.anim_playback).travel("Reload")

	# Immediately restart the reload animation to reset it on tap
	var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
	if sub_pb:
		sub_pb.start("Reload")

	# Slow animation on final pump (when super active is triggered)
	var scale = 1.0 if gun.is_super_active else 1.5
	owner.anim.set("parameters/Main/Reload/Reload/TimeScale/scale", scale)
	owner.anim.set("parameters/Main/Reload/Reload 2/TimeScale/scale", scale)

	# Connect anim_done once
	if not owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.connect(anim_done)

	# Restart the fallback timer each pump
	if owner.reload_timer.timeout.is_connected(reload_timeout):
		owner.reload_timer.timeout.disconnect(reload_timeout)
	owner.reload_timer.timeout.connect(reload_timeout)
	owner.reload_timer.start()

func anim_done(namee: String) -> void:
	if _exited:
		return
	if namee == reload_anim:
		owner.anim.set("parameters/Main/Reload/Reload/TimeScale/scale", 1.0)
		owner.anim.set("parameters/Main/Reload/Reload 2/TimeScale/scale", 1.0)

func reload_timeout() -> void:
	if _exited:
		return
	_evaluate_queued_exit()

func stop_moving() -> void:
	owner.set_velocity_from_motion(Vector3.ZERO)

# ---- QTE HUD Callbacks ----

func _on_qte_hit() -> void:
	if _exited:
		return
		
	var gun = owner.gun_controller.current_gun
	if gun:
		# Play standard pump SFX on hit (air is refilled gradually in _update)
		SoundManager.play_2d("watergun_pistol_reload")
		
	if _is_shotgun(gun):
		return
		
	# Travel to Reload_Quick in animation tree (pistol only)
	var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
	if sub_pb:
		sub_pb.travel("Reload_Quick")

func _on_superpump_started() -> void:
	if _exited:
		return
	_is_superpump_active = true
	var gun = owner.gun_controller.current_gun if owner.gun_controller else null
	var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
	if _is_shotgun(gun):
		if sub_pb:
			if sub_pb.get_current_node() == "End" or sub_pb.get_current_node() == "":
				sub_pb.start("SuperPump_Shotgun")
			else:
				sub_pb.travel("SuperPump_Shotgun")
		return
	if sub_pb:
		if sub_pb.get_current_node() == "End" or sub_pb.get_current_node() == "":
			sub_pb.start("SuperPump")
		else:
			sub_pb.travel("SuperPump")
	var superpump_pb = owner.anim.get("parameters/Main/Reload/SuperPump/playback")
	if superpump_pb:
		superpump_pb.start("SuperPumpStart")

func _on_superpump_completed() -> void:
	if _exited:
		return
	var gun = owner.gun_controller.current_gun if owner.gun_controller else null
	if gun:
		if _is_shotgun(gun):
			gun.air = gun.max_air
			gun.is_super_ready = false
			gun.is_super_active = true
			gun.super_timer = 30.0
		else:
			gun.air = 120.0
			gun.is_super_ready = false
			gun.is_super_active = true
			gun.super_timer = 5.0
	if is_instance_valid(owner) and is_instance_valid(owner.anim):
		if _is_shotgun(gun):
			var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
			if sub_pb and sub_pb.get_current_node() != "SuperPump_Shotgun":
				sub_pb.start("SuperPump_Shotgun")
			return
		var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
		if sub_pb and sub_pb.get_current_node() != "SuperPump":
			sub_pb.travel("SuperPump")
		var superpump_pb = owner.anim.get("parameters/Main/Reload/SuperPump/playback")
		if superpump_pb:
			if superpump_pb.get_current_node() == "SuperPumpStart":
				superpump_pb.travel("SuperPumpEnd")
			else:
				superpump_pb.start("SuperPumpEnd")

func _on_reload_finished(final_air: float, super_activated: bool) -> void:
	if _exited:
		return
		
	var gun = owner.gun_controller.current_gun
	if gun:
		if _is_shotgun(gun) and super_activated:
			gun.air = gun.max_air
			gun.is_super_ready = false
			gun.is_super_active = true
			gun.super_timer = 30.0
		else:
			gun.air = final_air
			if super_activated:
				gun.is_super_ready = false
				gun.is_super_active = true
				if gun.super_timer <= 0.0:
					gun.super_timer = 5.0
			
	# Cleanup HUD reference
	_disconnect_qte_signals()
	qte_hud = null
	
	# Transition back using queued exit check
	_evaluate_queued_exit()

func _on_reload_cancelled() -> void:
	if _exited:
		return
	_disconnect_qte_signals()
	qte_hud = null
	
	_evaluate_queued_exit()

func _disconnect_qte_signals() -> void:
	if is_instance_valid(qte_hud):
		if qte_hud.qte_hit.is_connected(_on_qte_hit):
			qte_hud.qte_hit.disconnect(_on_qte_hit)
		if qte_hud.finished.is_connected(_on_reload_finished):
			qte_hud.finished.disconnect(_on_reload_finished)
		if qte_hud.cancelled.is_connected(_on_reload_cancelled):
			qte_hud.cancelled.disconnect(_on_reload_cancelled)
		if qte_hud.has_signal("superpump_started") and qte_hud.superpump_started.is_connected(_on_superpump_started):
			qte_hud.superpump_started.disconnect(_on_superpump_started)
		if qte_hud.has_signal("superpump_completed") and qte_hud.superpump_completed.is_connected(_on_superpump_completed):
			qte_hud.superpump_completed.disconnect(_on_superpump_completed)

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
