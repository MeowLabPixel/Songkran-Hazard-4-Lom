extends State

func _enter() -> void:
	print(name)
	stop_moving()
	owner.cancel_aim()
	owner.anim.get("parameters/playback").travel("Die")
	SoundManager.play_3d("leon_dead", owner)
	if owner.has_method("force_die"):
		owner.force_die()

	# Trigger cinematic overhead pull-back death camera
	var cam = owner.camera if "camera" in owner else owner.get_node_or_null("Camera")
	if cam and cam.has_method("start_death_camera"):
		cam.start_death_camera()

	# If outcome wasn't already set to DEFEAT_ANCHALEE, set it to DEFEAT_PLAYER
	if get_tree().root.has_node("GameManager"):
		var gm = get_tree().root.get_node("GameManager")
		if gm.game_outcome != gm.Outcome.DEFEAT_ANCHALEE:
			gm.game_outcome = gm.Outcome.DEFEAT_PLAYER

	# Disable all enemy attacks and force them back to hunt/idle
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.attack_blocked = true
			if enemy.state_machine:
				if enemy.state_machine.current_state and enemy.state_machine.current_state.name == "StateAttack":
					enemy.state_machine.transition_to("StateHunt")

	# Notify follower (Anchalee) to enter infinite ducking state
	for anchalee in get_tree().get_nodes_in_group("Anchalee"):
		if is_instance_valid(anchalee) and anchalee.has_method("on_player_died"):
			anchalee.on_player_died()

	# If die screen is disabled for footage capture, do not fade to black or switch scene
	if get_tree().root.has_node("GameManager"):
		var gm = get_tree().root.get_node("GameManager")
		if not (gm.show_die_screen and gm.show_gameplay_ui):
			return

	# Allow overhead crane pull-back shot to play (~2.8s), then fade to black over 1.2s (total ~4.0s)
	var timer = get_tree().create_timer(2.8)
	timer.timeout.connect(func():
		var canvas_layer = CanvasLayer.new()
		canvas_layer.layer = 99
		var color_rect = ColorRect.new()
		color_rect.color = Color(0.02, 0.02, 0.03, 1.0)
		color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		color_rect.modulate.a = 0.0
		canvas_layer.add_child(color_rect)
		owner.add_child(canvas_layer)
		
		var tween = owner.create_tween()
		tween.tween_property(color_rect, "modulate:a", 1.0, 1.2)
		tween.finished.connect(func():
			if get_tree().root.has_node("GameManager"):
				var gm = get_tree().root.get_node("GameManager")
				if gm.game_outcome == gm.Outcome.DEFEAT_ANCHALEE:
					get_tree().change_scene_to_file("res://scenes/result_screen_defeat_anchalee.tscn")
				else:
					get_tree().change_scene_to_file("res://scenes/result_screen_defeat_player.tscn")
			else:
				# Fallback if GameManager is not found
				get_tree().change_scene_to_file("res://scenes/result_screen_defeat_player.tscn")
		)
	)

func _exit() -> void:
	pass

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)
