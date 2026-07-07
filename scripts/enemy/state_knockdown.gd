class_name StateKnockdown
extends EnemyState

enum Phase { NONE, ACT3, ACT4, ACT5, DONE }

@export var knockdown_duration: float = 2.0
@export var slip_forward_speed: float = 2.0
@export var act3_push_speed: float = 2.0
@export var act3_push_min_speed: float = 1.5
@export var special_l_push_speed: float = 2.0
@export var special_r_push_speed: float = 2.0
@export var swing_shot_push_speed: float = 2.0
@export var splash_push_radius: float = 1.0
@export var splash_push_damage: int = 0

var knockdown_mode: String = "NORMAL" # "NORMAL", "SPECIAL_LEG_SHOT", "SPECIAL_FOOT_HEAD", etc.
var stun_type: String  = "head"
var skip_act3: bool    = false
var knockdown_type: String = "head"

var special_side: String = "L"
var start_offset_override: float = 0.0
var push_direction: Vector3 = Vector3.ZERO

var _phase: Phase = Phase.NONE
var _timer: float = 0.0
var _anim_duration: float = 0.0
var _pushed_enemies: Array[Node] = []
var _act3_timer: float = 0.0
var _travelled_to_getup_end: bool = false

func enter() -> void:
	_timer = 0.0
	_phase = Phase.ACT3
	_pushed_enemies.clear()
	_act3_timer = 0.0
	_travelled_to_getup_end = false
	if enemy:
		enemy.reset_getup_conditions()
		if enemy.has_method("trigger_impact_sway"):
			enemy.trigger_impact_sway(true)
	
	# Determine push direction and align enemy rotation
	var is_special = knockdown_mode in ["SPECIAL_LEG_SHOT", "SPECIAL_FOOT_HEAD", "SPECIAL_HEAD_FOOT", "SWING_SHOT"]
	var players = enemy.get_tree().get_nodes_in_group("player") if enemy else []
	var player = players[0] if players.size() > 0 else null
	if enemy and player and not is_special:
		var to_enemy = enemy.global_position - player.global_position
		to_enemy.y = 0.0
		if to_enemy.length() > 0.01:
			push_direction = to_enemy.normalized()
			
			# Rotate the enemy to face the player along the Y axis
			var to_player = player.global_position - enemy.global_position
			to_player.y = 0.0
			if to_player.length() > 0.01:
				var target_y = atan2(-to_player.x, -to_player.z)
				enemy.rotation.y = target_y
		else:
			push_direction = enemy.global_transform.basis.z
	elif enemy:
		push_direction = enemy.global_transform.basis.z
	else:
		push_direction = Vector3.ZERO
		
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	print("[StateKnockdown] Knocked down. Mode: %s Zone: %s skip_act3=%s special_side=%s" % [knockdown_mode, stun_type, skip_act3, special_side])
	
	# Trigger Act 3 takedown/knockdown sounds
	if not skip_act3 and enemy:
		if knockdown_mode == "NORMAL":
			# Normal player-triggered takedown sequence
			SoundManager.play_3d("Region_ZombieGetHitTakedown_Part1", enemy, 0.0, -1.0, enemy.custom_pitch_scale)
		else:
			# Non-normal knockdown (stumble, leg shot, swing shot)
			if stun_type == "head":
				SoundManager.play_3d("zombie_hit_head_act_3_takedown", enemy, 0.0, -1.0, enemy.custom_pitch_scale)
			else:
				SoundManager.play_3d("zombie_hit_leg_act_3_takedown", enemy, 0.0, -1.0, enemy.custom_pitch_scale)
				
	if skip_act3:
		_start_act4()
		return
		
	var start_offset: float = 0.0
	
	if knockdown_mode == "SPECIAL_LEG_SHOT":
		knockdown_type = stun_type
		start_offset = start_offset_override
		if enemy and enemy.anim_tree:
			if special_side == "L":
				enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_L", true)
				enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special", true) # fallback/compatibility
				enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_2", false)
				enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_R", false)
			else:
				enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_R", true)
				enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special", false)
				enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_2", false)
				enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_L", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Swing_shot", false)
	elif knockdown_mode == "SPECIAL_FOOT_HEAD":
		knockdown_type = stun_type
		start_offset = 1.25
		if enemy and enemy.anim_tree:
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special", true)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_2", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_L", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_R", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Swing_shot", false)
	elif knockdown_mode == "SPECIAL_HEAD_FOOT":
		knockdown_type = stun_type
		start_offset = 0.0 # Standard start
		if enemy and enemy.anim_tree:
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_2", true)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_L", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_R", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Swing_shot", false)
	elif knockdown_mode == "SWING_SHOT":
		knockdown_type = stun_type
		start_offset = 0.0
		if enemy and enemy.anim_tree:
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_2", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_L", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_R", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Swing_shot", true)
	else:
		# Normal
		if enemy and enemy.anim_tree:
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_2", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_L", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_R", false)
			enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Swing_shot", false)
			
		if stun_type == "head":
			knockdown_type = "head"
			start_offset = 0.0
		else:
			knockdown_type = stun_type
			start_offset = 0.0
			
	if knockdown_mode == "SWING_SHOT":
		_force_anim_instant("HIT head act 3-take down Special for Attack Swing Leg Shot", "hit/hit_takedown")
	elif knockdown_mode == "SPECIAL_LEG_SHOT":
		if special_side == "L":
			_force_anim_instant("HIT head act 3-take down Special_L", "hit/hit_takedown")
		else:
			_force_anim_instant("HIT RightLeg act 3-take down Special_R", "hit/hit_takedown")
	elif knockdown_mode == "SPECIAL_HEAD_FOOT":
		_force_anim_instant("HIT head act 3-take down Special for leg", "hit/hit_takedown")
	else:
		# Travel directly to the Act 3 animation state node so it transitions immediately
		var act3_state = _get_act3_state_node_name()
		_force_anim_instant(act3_state, "hit/hit_takedown")
	
	if start_offset > 0.0 and enemy and enemy.anim_tree:
		enemy.anim_tree.advance(start_offset)
		
func _start_act4() -> void:
	_phase = Phase.ACT4
	_timer = 0.0
	var loop_anim: String = enemy.anim_set.takedown_idle(knockdown_type)
	_force_anim(loop_anim, "hit/hit_takedown")
	
	if enemy:
		# Play hit ground sound
		SoundManager.play_3d("Region_Zombie_Hitground_Sound", enemy, 0.0, -1.0, enemy.custom_pitch_scale)
		# If leg hit, play loop struggle
		if knockdown_type != "head":
			SoundManager.play_3d("zombie_hit_leg_act_2_loop", enemy, 0.0, -1.0, enemy.custom_pitch_scale)

func _start_act5() -> void:
	_phase = Phase.ACT5
	_timer = 0.0
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
		
		# Play getup reaction sound
		if knockdown_type == "head":
			SoundManager.play_3d("zombie_hit_head_act_5_getup", enemy, 0.0, -1.0, enemy.custom_pitch_scale)
		else:
			SoundManager.play_3d("zombie_hit_leg_act_5_getup", enemy, 0.0, -1.0, enemy.custom_pitch_scale)
			
	var getup_anim = enemy.anim_set.get_up_anim(knockdown_type)
	_force_anim(getup_anim, "hit/hit_takedown")
	
	# Reset travel flag at start of act 5
	_travelled_to_getup_end = false
	
	if enemy and enemy.anim_player and enemy.anim_player.has_animation(getup_anim):
		var anim_len = enemy.anim_player.get_animation(getup_anim).length
		var speed: float = 1.0
		if enemy.anim_tree:
			var speed_val = enemy.anim_tree.get("parameters/hit/hit_takedown/" + getup_anim + "/TimeScale/scale")
			if typeof(speed_val) in [TYPE_FLOAT, TYPE_INT] and float(speed_val) > 0.0:
				speed = float(speed_val)
		_anim_duration = anim_len / speed
	else:
		_anim_duration = 1.0

func exit() -> void:
	if enemy and enemy.anim_tree:
		enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special", false)
		enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_2", false)
		enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_L", false)
		enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Special_R", false)
		enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/Swing_shot", false)
		
	skip_act3 = false
	knockdown_mode = "NORMAL"
	_phase = Phase.DONE

func physics_update(delta: float) -> void:
	var current_node = ""
	if enemy and enemy.anim_tree:
		var pb = enemy.anim_tree.get("parameters/hit/hit_takedown/playback")
		if pb:
			var node = pb.get_current_node()
			if node != null: current_node = String(node)
			
	var act4_anim = enemy.anim_set.takedown_idle(knockdown_type)
	var act5_anim = enemy.anim_set.get_up_anim(knockdown_type)

	match _phase:
		Phase.ACT3:
			var is_flying_node = current_node in [
				"Hit Leg act 3-take down for head",
				"Hit Leg act 3 (Take_down)",
				"Hit RightLeg act 3 (Take_down)",
				"HIT head act 3-take down Special_L",
				"HIT head act 3-take down Special for Attack Swing Leg Shot",
				"HIT RightLeg act 3-take down Special_R"
			]
			if is_flying_node:
				_act3_timer += delta
				if enemy:
					var duration = _get_act3_anim_duration(current_node)
					var pct = _act3_timer / duration if duration > 0.0 else 0.0
					
					var base_speed = act3_push_speed
					var min_speed = act3_push_min_speed
					var dir = push_direction
					
					if "Special_L" in current_node:
						base_speed = special_l_push_speed
						if act3_push_speed > 0.0:
							min_speed = special_l_push_speed * (act3_push_min_speed / act3_push_speed)
					elif "Special_R" in current_node:
						base_speed = special_r_push_speed
						if act3_push_speed > 0.0:
							min_speed = special_r_push_speed * (act3_push_min_speed / act3_push_speed)
					elif "Attack Swing Leg Shot" in current_node:
						base_speed = swing_shot_push_speed
						if act3_push_speed > 0.0:
							min_speed = swing_shot_push_speed * (act3_push_min_speed / act3_push_speed)
						dir = -enemy.global_transform.basis.z
						
					var current_speed = base_speed
					if pct > 0.25:
						var t_factor = (pct - 0.25) / 0.75
						current_speed = min_speed * max(0.0, 1.0 - t_factor)
						
					enemy.velocity = dir * current_speed
					enemy.move_and_slide()
					
					# Detect and push other enemies
					var other_enemies = enemy.get_tree().get_nodes_in_group("enemies")
					for other in other_enemies:
						if other == enemy or other.is_defeated or other in _pushed_enemies:
							continue
						var dist = enemy.global_position.distance_to(other.global_position)
						if dist < splash_push_radius:
							_pushed_enemies.append(other)
							var push_dir = (other.global_position - enemy.global_position).normalized()
							push_dir.y = 0.0
							push_dir = push_dir.normalized()
							other.take_hit({
								"damage": splash_push_damage,
								"hit_type": "push",
								"hit_direction": push_dir,
								"source": enemy
							})
					
			# Wait for AnimationTree to automatically transition to Act 4
			# Since we queued travel() for Head, it will take the user's crossfade arrow to Head Act 4!
			if current_node == act4_anim:
				if enemy and enemy.is_takedown_defeat:
					enemy._trigger_defeat()
					return
				_phase = Phase.ACT4
				_timer = 0.0
				if enemy:
					enemy.velocity = Vector3.ZERO
					enemy.move_and_slide()
				
		Phase.ACT4:
			_timer += delta
			if _timer >= knockdown_duration:
				_start_act5()
				
		Phase.ACT5:
			_timer += delta
			if _timer >= 0.4 and not _travelled_to_getup_end:
				_travelled_to_getup_end = true
				if enemy and enemy.anim_tree:
					var act2_skip_val = enemy.anim_tree.get("parameters/hit/Getup_End/conditions/act2_skip")
					if act2_skip_val == false:
						var pb = enemy.anim_tree.get("parameters/hit/playback")
						if pb:
							pb.travel("Getup_End")
						var child_pb = enemy.anim_tree.get("parameters/hit/Getup_End/playback")
						if child_pb:
							var getup_anim = enemy.anim_set.get_up_anim(knockdown_type)
							child_pb.travel(getup_anim)

			if _timer >= 0.5:
				var hunt = state_machine._states.get("StateHunt")
				if hunt:
					var remain = max(_anim_duration - 0.5, 0.5)
					hunt.trigger_getup_block(remain)
				state_machine.transition_to("StateHunt")

func handle_hit(hit_data: Dictionary) -> String:
	if _phase == Phase.ACT5 and _timer >= 0.5:
		var zone: String = hit_data.get("hit_zone", "body")
		match zone:
			"head", "foot", "left_foot", "right_foot":
				return "StateTakedownable"
			_:
				return "StateStun"
	return ""

func _get_act3_anim_duration(node_name: String) -> float:
	if not enemy or not enemy.anim_player:
		return 1.0
	var anim_name = ""
	match node_name:
		"Hit Leg act 3-take down for head", "HIT head act 3-take down Special for Attack Swing Leg Shot":
			anim_name = "HIT head act 3-take down"
		"Hit Leg act 3 (Take_down)", "HIT head act 3-take down Special_L":
			anim_name = "Hit Leg act 3 (Take_down)"
		"Hit RightLeg act 3 (Take_down)", "HIT RightLeg act 3-take down Special_R":
			anim_name = "Hit RightLeg act 3 (Take_down)"
			
	if anim_name != "" and enemy.anim_player.has_animation(anim_name):
		var base_len = enemy.anim_player.get_animation(anim_name).length
		var timescale_path = "parameters/hit/hit_takedown/" + node_name + "/TimeScale/scale"
		var ts = enemy.anim_tree.get(timescale_path) if enemy.anim_tree else null
		if typeof(ts) in [TYPE_FLOAT, TYPE_INT] and float(ts) > 0.0:
			return base_len / float(ts)
		return base_len
	return 1.0

func _get_act3_state_node_name() -> String:
	match knockdown_type:
		"left_foot", "foot": return "Hit Leg act 3 (Take_down)"
		"right_foot":        return "Hit RightLeg act 3 (Take_down)"
		_:                   return "Hit Leg act 3-take down for head"

func is_playing_special_act3() -> bool:
	if _phase != Phase.ACT3:
		return false
	
	if knockdown_mode in ["SPECIAL_LEG_SHOT", "SWING_SHOT"]:
		return true
		
	var current_node = ""
	if enemy and enemy.anim_tree:
		var pb = enemy.anim_tree.get("parameters/hit/hit_takedown/playback")
		if pb:
			var node = pb.get_current_node()
			if node != null: current_node = String(node)
	return current_node in [
		"HIT head act 3-take down Special_L",
		"HIT head act 3-take down Special for Attack Swing Leg Shot",
		"HIT RightLeg act 3-take down Special_R"
	]
