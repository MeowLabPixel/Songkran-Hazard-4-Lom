extends Motion

func _enter() -> void:
	if owner.gun_controller:
		owner.gun_controller.next_gun()
		owner.curr_gun_index = owner.gun_controller.current_gun_index
	else:
		owner.change_gun()
	#play gunswap anim

func anim_done(_namee: String):
	pass

func _update(_delta:float) -> void:
	set_direction()
	calculate_velocity(SPEED,direction,_delta)


#switch to 1 shot in run/sprint/idle add func here too
