class_name StateKnockdown
extends EnemyState

enum Phase { NONE, ACT3, ACT4, ACT5, DONE }

@export var knockdown_duration: float = 2.0
@export var slip_forward_speed: float = 2.0

var knockdown_mode: String = "NORMAL" # "NORMAL", "SPECIAL_LEG_SHOT", "SPECIAL_FOOT_HEAD", etc.
var stun_type: String  = "head"
var skip_act3: bool    = false
var knockdown_type: String = "head"

var special_side: String = "L"
var start_offset_override: float = 0.0

var _phase: Phase = Phase.NONE
var _timer: float = 0.0
var _anim_duration: float = 0.0

func enter() -> void:
	_timer = 0.0
	_phase = Phase.ACT3
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	print("[StateKnockdown] Knocked down. Mode: %s Zone: %s skip_act3=%s special_side=%s" % [knockdown_mode, stun_type, skip_act3, special_side])
	
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
		_force_anim("HIT head act 3-take down Special for Attack Swing Leg Shot", "hit/hit_takedown")
	elif knockdown_mode == "SPECIAL_LEG_SHOT":
		if special_side == "L":
			_force_anim("HIT head act 3-take down Special_L", "hit/hit_takedown")
		else:
			_force_anim("HIT RightLeg act 3-take down Special_R", "hit/hit_takedown")
	elif knockdown_mode == "SPECIAL_HEAD_FOOT":
		_force_anim("HIT head act 3-take down Special for leg", "hit/hit_takedown")
	else:
		# Universally queue the travel to the correct Act 4 loop!
		# We travel to Act 4 so it smoothly transitions from Act 3 -> Act 4.
		var act4_anim = enemy.anim_set.takedown_idle(knockdown_type)
		_force_anim(act4_anim, "hit/hit_takedown")
	
	if start_offset > 0.0 and enemy and enemy.anim_tree:
		enemy.anim_tree.advance(start_offset)
		
func _start_act4() -> void:
	_phase = Phase.ACT4
	_timer = 0.0
	var loop_anim: String = enemy.anim_set.takedown_idle(knockdown_type)
	_force_anim(loop_anim, "hit/hit_takedown")

func _start_act5() -> void:
	_phase = Phase.ACT5
	_timer = 0.0
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	var getup_anim = enemy.anim_set.get_up_anim(knockdown_type)
	_force_anim(getup_anim, "hit/hit_takedown")
	
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
			if "Attack Swing Leg Shot" in current_node:
				if enemy:
					var forward_dir = -enemy.global_transform.basis.z
					enemy.velocity = forward_dir * slip_forward_speed
					enemy.move_and_slide()
					
			# Wait for AnimationTree to automatically transition to Act 4
			# Since we queued travel() for Head, it will take the user's crossfade arrow to Head Act 4!
			if current_node == act4_anim:
				_phase = Phase.ACT4
				_timer = 0.0
				
		Phase.ACT4:
			_timer += delta
			if _timer >= knockdown_duration:
				_start_act5()
				
		Phase.ACT5:
			_timer += delta
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
