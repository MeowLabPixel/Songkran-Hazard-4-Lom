class_name StateTakedownable
extends EnemyState

@export var takedown_window: float = 2.0
@export var head_hit_move_speed: float = 1.5

var _act2_timer: float = 0.0
var _act1_timer: float = 0.0
var _in_act1: bool     = false
var _act1_velocity: Vector3 = Vector3.ZERO
var stun_type: String  = "head"
var takedown_triggered: bool = false

func enter() -> void:
	_act2_timer = 0.0
	takedown_triggered = false
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	print("[StateTakedownable] TAKEDOWN-able! Type: %s" % stun_type)
	_start_act1()

func _start_act1() -> void:
	_in_act1 = true
	_act1_timer = 0.0
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
				
	_force_anim(anim, "hit/hit_takedown")

func exit() -> void:
	if stun_type == "head":
		enemy.next_idle_offset = 6.5
	stun_type = "head"
	takedown_triggered = false
	_in_act1 = false
	if enemy and enemy.anim_tree:
		enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_far", false)
		enemy.anim_tree.set("parameters/hit/hit_takedown/conditions/hit_close", false)

func physics_update(delta: float) -> void:
	if takedown_triggered:
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
		_act2_timer += delta
		if _act2_timer >= takedown_window:
			var hunt = state_machine._states.get("StateHunt")
			if hunt:
				hunt.trigger_stun_recovery = true
			state_machine.transition_to("StateHunt")

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
	takedown_triggered = true
