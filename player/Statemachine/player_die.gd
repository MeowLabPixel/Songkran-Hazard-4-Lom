extends State

func _enter() -> void:
	print(name)
	stop_moving()
	owner.aim_bone_on(false)
	owner.anim.get("parameters/playback").travel("Die")
	owner.die.visible = true
	owner.die_anim.play("in")
	if owner.has_method("force_die"):
		owner.force_die()

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)
