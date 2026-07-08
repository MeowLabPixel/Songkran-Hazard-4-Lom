extends State

var reload_anim = "RR/re"
var _exited: bool = false
var _pump_cooldown_timer: float = 0.2
var qte_hud = null

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

# ---- QTE HUD Callbacks ----

func _on_qte_hit() -> void:
	if _exited:
		return
		
	var gun = owner.gun_controller.current_gun
	if gun:
		# Add 25% of max air (25.0)
		gun.air = clampf(gun.air + 25.0, 0.0, gun.max_air)
		# Play standard pump SFX on hit
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
	
	# Transition AnimationTree sub-state to End to exit Reload state
	var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
	if sub_pb:
		sub_pb.travel("End")
	
	# Transition back to Idle
	finished.emit("Idle")

func _on_reload_cancelled() -> void:
	if _exited:
		return
	qte_hud = null
	
	# Transition AnimationTree out of Reload
	var sub_pb = owner.anim.get("parameters/Main/Reload/playback")
	if sub_pb:
		sub_pb.travel("End")
		
	finished.emit("Idle")
