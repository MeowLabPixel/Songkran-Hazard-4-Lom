class_name StateTakedownable
extends EnemyState

@export var takedown_window: float = 2.0
@export var head_stun_duration: float = 2.0
@export var foot_stun_duration: float = 3.0
@export var head_hit_move_speed: float = 2.0

@export_group("Takedown Anticipation Settings")
@export var enable_takedown_anticipation: bool = true                     ## Enable hit-stop, mesh pop, and squash & stretch in Act 2
@export_range(0.05, 0.5, 0.01) var anticipation_duration: float = 0.2      ## Duration of hit-stop anticipation in Act 2 (seconds)
@export_range(1.1, 1.6, 0.05) var mesh_pop_scale: float = 1.30             ## Frame-1 Mesh Pop scale multiplier
@export_range(1.0, 1.8, 0.05) var squash_stretch_factor: float = 1.30      ## Cartoony squash & stretch scale factor
@export_range(0.02, 0.15, 0.01) var micro_shake_amplitude: float = 0.8    ## Micro-shake displacement (meters)
@export_range(10.0, 40.0, 1.0) var micro_shake_frequency: float = 60.0     ## Micro-shake vibration frequency (Hz)



var _act2_timer: float = 0.0
var _act1_timer: float = 0.0
var _in_act1: bool     = false
var _act1_velocity: Vector3 = Vector3.ZERO
var stun_type: String  = "head"
var takedown_triggered: bool = false
var _in_anticipation_phase: bool = false
var _anticipation_timer: float = 0.0


func enter() -> void:
	_act2_timer = 0.0
	takedown_triggered = false
	_in_anticipation_phase = false
	_anticipation_timer = 0.0
	takedown_window = get_stun_duration()
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	print("[StateTakedownable] TAKEDOWN-able! Type: %s (Duration: %.1fs)" % [stun_type, takedown_window])
	_start_act1()

func _start_act1() -> void:
	_in_act1 = true
	_act1_timer = 0.0
	_act2_timer = 0.0
	takedown_triggered = false
	_in_anticipation_phase = false
	_anticipation_timer = 0.0
	takedown_window = get_stun_duration()
	_act1_velocity = Vector3.ZERO
	var anim = enemy.anim_set.hit_reaction(stun_type)
	
	if stun_type == "head":
		var players = enemy.get_tree().get_nodes_in_group("player")
		var player = players[0] if players.size() > 0 else null
		if player:
			var to_player = player.global_position - enemy.global_position
			to_player.y = 0.0
			var dist = to_player.length()
			var move_dir = to_player.normalized() if dist > 0.01 else -enemy.global_transform.basis.z
			
			if dist > 2.0:
				if enemy and enemy.anim_tree:
					enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_far", true)
					enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_close", false)
				_act1_velocity = move_dir * head_hit_move_speed # Move forward
			else:
				if enemy and enemy.anim_tree:
					enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_far", false)
					enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_close", true)
				_act1_velocity = -move_dir * head_hit_move_speed # Move backward
	else:
		# If it's a leg hit during get-up, we need the hit_getup condition to be true
		if enemy and enemy.anim_tree:
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_getup", true)
		
		# Play leg slip/stumble sound
		SoundManager.play_3d("zombie_hit_leg_act_1_slipping", enemy, 0.0, -1.0, enemy.custom_pitch_scale)
				
	_force_anim_instant(anim, "hit/hit_takedown")

func exit() -> void:
	if stun_type == "head":
		enemy.next_idle_offset = 6.5
	stun_type = "head"
	takedown_triggered = false
	_in_act1 = false
	_in_anticipation_phase = false
	_anticipation_timer = 0.0
	if enemy:
		if enemy.anim_tree:
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_far", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_close", false)
		enemy.reset_getup_conditions()

func physics_update(delta: float) -> void:
	if takedown_triggered:
		if _in_anticipation_phase:
			_anticipation_timer += delta
			if enemy:
				enemy.velocity = Vector3.ZERO
				enemy.move_and_slide()
			if _anticipation_timer >= anticipation_duration:
				_in_anticipation_phase = false
				var knockdown = state_machine._states.get("StateKnockdown")
				if knockdown:
					knockdown.knockdown_mode = "NORMAL"
					knockdown.stun_type = stun_type
				state_machine.transition_to("StateKnockdown")
			return
		else:
			var knockdown = state_machine._states.get("StateKnockdown")
			if knockdown:
				knockdown.knockdown_mode = "NORMAL"
				knockdown.stun_type = stun_type
			state_machine.transition_to("StateKnockdown")
			return

		
	var current_node = ""
	if enemy and enemy.anim_tree:
		var pb = enemy.anim_tree.get("parameters/hit/hit_takedown/playback")
		if pb:
			var node = pb.get_current_node()
			if node != null: current_node = String(node)
			
	var loop_anim = enemy.anim_set.stun_idle(stun_type)
		
	if _in_act1:
		# Apply act1 velocity
		if enemy and stun_type == "head":
			enemy.velocity = _act1_velocity
			enemy.move_and_slide()
			
			# Face the player while moving
			if _act1_velocity.length() > 0.01:
				var players = enemy.get_tree().get_nodes_in_group("player")
				if players.size() > 0:
					var to_player = players[0].global_position - enemy.global_position
					to_player.y = 0.0
					if to_player.length() > 0.01:
						var target_y = atan2(-to_player.x, -to_player.z)
						enemy.rotation.y = lerp_angle(enemy.rotation.y, target_y, 10.0 * delta)
						
		_act1_timer += delta
		# Wait for the AnimationTree to automatically transition to Act 2
		# We wait 0.1s to ensure the tree has processed the travel() call and isn't 
		# returning a stale state from a previous takedown.
		# Added a 1.2s timeout fallback so the zombie doesn't slide forever if the animation tree stalls.
		var animation_finished = (current_node == loop_anim and _act1_timer > 0.1)
		if animation_finished or _act1_timer >= 1.2:
			_in_act1 = false
			_act2_timer = 0.0
			if enemy:
				enemy.velocity = Vector3.ZERO
				enemy.move_and_slide()
	else:
		if enemy and enemy.anim_tree:
			if "parameters/hit/Getup_End/conditions/act2_skip" in enemy.anim_tree:
				enemy.anim_tree.set("parameters/hit/Getup_End/conditions/act2_skip", true)
		_act2_timer += delta

		var is_exiting_act2 = (current_node == "End" or "act 3" in current_node.to_lower() or "act3" in current_node.to_lower())
		if get_elapsed_time() >= get_stun_duration() or is_exiting_act2:
			var hunt = state_machine._states.get("StateHunt")
			if hunt:
				hunt.trigger_stun_recovery = true
			state_machine.transition_to("StateHunt")

func get_stun_duration() -> float:
	if stun_type == "head":
		return head_stun_duration
	return foot_stun_duration

func get_elapsed_time() -> float:
	return _act1_timer + _act2_timer

func is_takedown_window_active() -> bool:
	if takedown_triggered:
		return false
	if get_elapsed_time() >= get_stun_duration():
		return false
	if enemy and enemy.anim_tree:
		var pb = enemy.anim_tree.get("parameters/hit/hit_takedown/playback")
		if pb:
			var node = String(pb.get_current_node())
			if node == "End" or "act 3" in node.to_lower() or "act3" in node.to_lower() or "special" in node.to_lower():
				return false
	return true

func handle_hit(hit_data: Dictionary) -> String:
	var zone = hit_data.get("hit_zone", "body")
	
	if stun_type == "head":
		match zone:
			"head":
				stun_type = zone
				_act2_timer = 0.0
				_start_act1()
				return ""
			"left_foot", "right_foot", "foot":
				var knockdown = state_machine._states.get("StateKnockdown")
				if knockdown:
					knockdown.knockdown_mode = "SPECIAL_LEG_SHOT"
					# Head to Foot: start_offset is 0.0 (standing to falling)
					knockdown.start_offset_override = 0.0
					if zone == "right_foot":
						knockdown.special_side = "R"
						knockdown.stun_type = "right_foot"
					else:
						knockdown.special_side = "L"
						knockdown.stun_type = "left_foot"
				state_machine.transition_to("StateKnockdown")
				return ""
			_:
				return "StateStun"
	else: # currently in foot stun (left_foot, right_foot, foot)
		var first_foot_was_right: bool = (stun_type == "right_foot")
		# Any shot after that triggers the zombie falldown!
		var knockdown = state_machine._states.get("StateKnockdown")
		if knockdown:
			knockdown.knockdown_mode = "SPECIAL_LEG_SHOT"
			# Foot to Anything: start_offset is 1.25 (already on ground slipping)
			knockdown.start_offset_override = 1.25
			if first_foot_was_right:
				knockdown.special_side = "R"
				knockdown.stun_type = "right_foot"
			else:
				knockdown.special_side = "L"
				knockdown.stun_type = "left_foot"
		state_machine.transition_to("StateKnockdown")
		return ""


func trigger_takedown() -> void:
	if _in_anticipation_phase:
		return
		
	takedown_triggered = true
	var knockdown = state_machine._states.get("StateKnockdown")
	if knockdown:
		knockdown.knockdown_mode = "NORMAL"
		knockdown.stun_type = stun_type


	if enable_takedown_anticipation and enemy:
		_in_anticipation_phase = true
		_anticipation_timer = 0.0
		SoundManager.play_3d("ZombieGetHitTakedown", enemy, 0.0, -1.0, enemy.custom_pitch_scale)
		var hit_dir = -enemy.global_transform.basis.z
		var players = enemy.get_tree().get_nodes_in_group("player") if (enemy and enemy.get_tree()) else []
		if players.size() > 0:
			var to_enemy = enemy.global_position - players[0].global_position
			to_enemy.y = 0.0
			if to_enemy.length() > 0.01:
				hit_dir = to_enemy.normalized()

		if enemy.has_method("trigger_act2_anticipation_juice"):
			enemy.trigger_act2_anticipation_juice(hit_dir, anticipation_duration, mesh_pop_scale, squash_stretch_factor, micro_shake_amplitude, micro_shake_frequency)

	else:
		state_machine.transition_to("StateKnockdown")
