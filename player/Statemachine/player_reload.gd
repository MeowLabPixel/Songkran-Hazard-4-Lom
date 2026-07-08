extends State

var reload_anim = "RR/re"
var _exited: bool = false
var _pump_cooldown_timer: float = 0.2
var qte_hud = null

@export var block_movement_during_qte: bool = true
@export var block_aiming_during_qte: bool = true

func _enter() -> void:
	_exited = false
	stop_moving()
	owner.is_aimming = false
	owner.aim_blocked_until_release = true
	owner.aim_bone_on(false)
	

	# Transition camera into aim mode (reload uses the same camera as aim, without showing crosshair)
	var cam = owner.get_node_or_null("Camera")
	if cam and cam.has_method("enter_aim"):
		cam.enter_aim(false)
	
	_pump_cooldown_timer = 0.2

	# If already fully charged on entry, just leave immediately
	if not owner.gun_controller or owner.gun_controller.current_gun.is_super_active:
		finished.emit("Idle")
		return

	var gun = owner.gun_controller.current_gun
	if gun and (gun.gun_name == "Water pistol" or owner.gun_controller.current_gun_index == 0):
		# Start QTE reload hud for pistol
		qte_hud = load("res://scripts/ui/reload_qte_hud.gd").new(gun.air, gun.max_air)
		qte_hud.qte_hit.connect(_on_qte_hit)
		qte_hud.finished.connect(_on_reload_finished)
		qte_hud.cancelled.connect(_on_reload_cancelled)
		owner.add_child(qte_hud)
		
		# Travel to main Reload state first
		owner.anim.get(owner.anim_playback).travel("Reload")
		
		# Set Reload timescale to half speed
		owner.anim.set("parameters/Main/Reload/Reload/TimeScale/scale", 0.5)
		
		# Travel to SuperPump or Reload in sub-state machine based on air
		var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
		if sub_pb:
			if gun.air >= gun.max_air:
				sub_pb.travel("SuperPump")
			else:
				sub_pb.travel("Reload")
	else:
		reloading()

func _exit() -> void:
	_exited = true
	if is_instance_valid(qte_hud):
		qte_hud.cancel()
		qte_hud = null
	if is_instance_valid(owner):
		owner.aim_blocked_until_release = false
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
		
	if _pump_cooldown_timer > 0.0:
		_pump_cooldown_timer -= _delta
		
	# QoL: Aim cancels reload (unless blocked by setting)
	if Input.is_action_pressed("aim"):
		var is_pistol_qte = is_instance_valid(qte_hud) and qte_hud.mode == "qte"
		var should_block_aim = is_pistol_qte and block_aiming_during_qte
		
		if not should_block_aim:
			owner.is_aimming = true
			finished.emit("Aim")
			return
			
	# Gradually fill gun air for water pistol based on HUD progress
	if is_instance_valid(qte_hud) and qte_hud.mode == "qte":
		var gun = owner.gun_controller.current_gun
		if gun:
			gun.air = clampf(qte_hud.start_air + (qte_hud.max_air - qte_hud.start_air) * qte_hud.reload_progress, 0.0, gun.max_air)
			
		# If movement is allowed, process movement input and apply velocity
		if not block_movement_during_qte:
			var input_dir = Vector2.ZERO
			var up = Input.is_action_pressed("ui_up")
			var down = Input.is_action_pressed("ui_down")
			var left = Input.is_action_pressed("ui_left")
			var right = Input.is_action_pressed("ui_right")
			
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
	if gun and (gun.gun_name == "Water pistol" or owner.gun_controller.current_gun_index == 0):
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
				finished.emit("Idle")

func reloading() -> void:
	if not owner.gun_controller:
		finished.emit("Aim" if owner.is_aimming else "Idle")
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
	finished.emit("Idle")

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
		
	# Travel to Reload_Quick in animation tree
	var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
	if sub_pb:
		sub_pb.travel("Reload_Quick")

func _on_reload_finished(final_air: float, super_activated: bool) -> void:
	if _exited:
		return
		
	var gun = owner.gun_controller.current_gun
	if gun:
		gun.air = final_air
		if super_activated:
			gun.is_super_ready = false
			gun.is_super_active = true
			gun.super_timer = 5.0 # Super pump lasts for 5.0 sec
			SoundManager.play_2d("watergun_pistol_reload_Superpump")
			
	# Cleanup HUD reference
	qte_hud = null
	
	# Transition back to Idle immediately
	finished.emit("Idle")

func _on_reload_cancelled() -> void:
	if _exited:
		return
	qte_hud = null
	
	finished.emit("Idle")
