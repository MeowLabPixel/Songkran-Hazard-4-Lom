class_name AnchaleeStateDie
extends AnchaleeState

func enter() -> void:
	print("[Anchalee] Die")
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()
	
	_set_immune(true)
	
	if Anchalee.has_node("AnchaleeModel/AnimationTree"):
		var tree = Anchalee.get_node("AnchaleeModel/AnimationTree")
		var pb = tree.get("parameters/playback")
		if pb: pb.travel("Die")
		
	# Trigger Game Over via Player's Camera nodes
	var player = Anchalee.get_player()
	if player:
		# player.die is usually standard, but let's navigate the specific tree
		var die_screen = player.get_node_or_null("Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/Die")
		var die_anim = player.get_node_or_null("Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D/Die/AnimationPlayer")
		
		if die_screen:
			die_screen.visible = true
		if die_anim:
			die_anim.play("in")

func physics_update(delta: float) -> void:
	Anchalee.velocity = Vector3.ZERO
	Anchalee.move_and_slide()

func _set_immune(is_immune: bool) -> void:
	var hurtbox = Anchalee.get_node_or_null("HurtBox")
	if hurtbox and hurtbox is Area3D:
		hurtbox.set_deferred("monitorable", not is_immune)
		hurtbox.set_deferred("monitoring", not is_immune)
	Anchalee.set_collision_layer_value(2, not is_immune)
