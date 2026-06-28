extends State

var reload_anim = "RR/re"
var _exited: bool = false

func _enter() -> void:
	print(name)
	_exited = false
	stop_moving()
	owner.aim_bone_on(false)



	# If already fully charged on entry, just leave immediately
	if not owner.gun_controller or owner.gun_controller.current_gun.is_super_ready:
		finished.emit("Aim" if owner.is_aimming else "Idle")
		return

	reloading()

func _exit() -> void:
	_exited = true
	if owner.anim and owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.disconnect(anim_done)
	if owner.reload_timer and owner.reload_timer.timeout.is_connected(reload_timeout):
		owner.reload_timer.timeout.disconnect(reload_timeout)

func _update(_delta: float) -> void:
	if owner.HP <= 0:
		finished.emit("Die")

func _state_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("Reload"):
		# Only allow pumping again if not yet full
		if not owner.gun_controller.current_gun.is_super_ready:
			reloading()
		else:
			# Already full, exit back to wherever they came from
			finished.emit("Aim" if owner.is_aimming else "Idle")

func reloading() -> void:
	if not owner.gun_controller:
		finished.emit("Aim" if owner.is_aimming else "Idle")
		return

	var gun = owner.gun_controller.current_gun
	gun.pump_air()

	owner.anim.get(owner.anim_playback).travel("Reload")

	# Slow animation on final pump
	var scale = 0.5 if gun.is_super_ready else 1.0
	owner.anim.set("parameters/Main/Reload/BlendTree/TimeScale/scale", scale)

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
	print("[Reload] anim_done: ", namee)
	if namee == reload_anim:
		owner.anim.set("parameters/Main/Reload/BlendTree/TimeScale/scale", 1.0)
		# If fully charged, timer will fire the exit — don't double-emit
		if owner.gun_controller.current_gun.is_super_ready:
			# Timer is already running from the last pump, let it finish
			pass
		else:
			# Mid-pump animation finished, wait for next player input
			pass

func reload_timeout() -> void:
	if _exited:
		return
	finished.emit("Aim" if owner.is_aimming else "Idle")



func stop_moving() -> void:
	owner.set_velocity_from_motion(Vector3.ZERO)
