extends State

var reload_anim = "RR/re"
var _exited: bool = false
var _pump_cooldown_timer: float = 0.2

func _enter() -> void:
	_exited = false
	stop_moving()
	owner.is_aimming = false
	owner.aim_blocked_until_release = true
	owner.aim_bone_on(false)
	
	# Transition camera out of aim mode
	var cam = owner.get_node_or_null("Camera")
	if cam and cam.has_method("exit_aim"):
		cam.exit_aim()
	
	_pump_cooldown_timer = 0.2

	# If already fully charged on entry, just leave immediately
	if not owner.gun_controller or owner.gun_controller.current_gun.is_super_active:
		finished.emit("Idle")
		return

	reloading()

func _exit() -> void:
	_exited = true
	if is_instance_valid(owner):
		owner.aim_blocked_until_release = false
		if owner.anim and is_instance_valid(owner.anim):
			if owner.anim.animation_finished.is_connected(anim_done):
				owner.anim.animation_finished.disconnect(anim_done)
			owner.anim.set("parameters/Main/Reload/Reload/TimeScale/scale", 1.0)
			owner.anim.set("parameters/Main/Reload/Reload 2/TimeScale/scale", 1.0)
		if owner.reload_timer and is_instance_valid(owner.reload_timer):
			if owner.reload_timer.timeout.is_connected(reload_timeout):
				owner.reload_timer.timeout.disconnect(reload_timeout)

func _update(_delta: float) -> void:
	if owner.HP <= 0:
		finished.emit("Die")
		return
	if _pump_cooldown_timer > 0.0:
		_pump_cooldown_timer -= _delta
		
	# QoL: Aim cancels reload immediately
	if Input.is_action_pressed("aim"):
		owner.is_aimming = true
		finished.emit("Aim")
		return

func _state_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("Reload"):
		if _pump_cooldown_timer <= 0.0:
			var gun = owner.gun_controller.current_gun
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

	# Immediately transition between the two identical reload animations to reset it on tap
	var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
	if sub_pb:
		var current = sub_pb.get_current_node()
		if current == "Reload":
			sub_pb.travel("Reload 2")
		else:
			sub_pb.travel("Reload")

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
