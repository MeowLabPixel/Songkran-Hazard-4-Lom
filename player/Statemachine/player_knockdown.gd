extends State

var exit_anim_name = "Knockdown/out"
var start_anim_name = "Knockdown/down"

func _enter() -> void:
	print(name)
	stop_moving()
	owner.cancel_aim()
	owner.anim.get(owner.anim_playback).travel("Knockdown")
	owner.hitboxF.monitoring = false
	owner.hitboxB.monitoring = false
	if not owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.connect(anim_done)
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(_knockdown_fallback)

func _exit() -> void:
	owner.hitboxF.monitoring = true
	owner.hitboxB.monitoring = true
	if owner.anim and owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.disconnect(anim_done)
	owner.aim_blocked_until_release = false

func _knockdown_fallback() -> void:
	print("Idle from Fallback.")
	anim_done(exit_anim_name)

func anim_done(_namee: String):
	if _namee == exit_anim_name:
		finished.emit("Idle")

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)
