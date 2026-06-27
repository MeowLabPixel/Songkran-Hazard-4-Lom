class_name StateAttack
extends EnemyState

@export var grab_chance: float      = 0.25
@export var grab_damage: int        = 30
@export var attack_damage: int      = 30

@export_group("Attack Windows")
@export var attack1_swing_start_frac: float = 0.5
@export var attack1_swing_end_frac: float   = 0.75
@export var attack2_swing_start_frac: float = 0.5
@export var attack2_swing_end_frac: float   = 0.75
@export var grab_start_frac: float  = 0.5
@export var grab_end_frac: float    = 0.9
@export var qte_duration: float     = 2.5
@export var qte_shakes_needed: int  = 5
@export_group("Attack Movement")
@export var attack_forward_speed: float = 10.0
@export var attack_tracking_speed: float = 4.0
@export var attack_min_speed: float = 0.0
@export var recovery_friction: float = 0.0
@export var recovery_tracking_speed: float = 0.0

@export_group("Grab Movement")
@export var grab_hold_distance: float = 0.5
@export var grab_forward_speed: float = 4.0
@export var grab_tracking_speed: float = 3.5
@export var grab_min_speed: float = 2.0
@export var grab_recovery_friction: float = 0.0
@export var grab_recovery_tracking_speed: float = 0.0
enum Phase { ATTACK, GRAB_REACHING, GRAB_HOLDING, GRAB_RESOLVING, DONE }
enum SwingPhase { WINDUP, SWING, RECOVERY }

var _phase: Phase                = Phase.DONE
var _swing_phase: SwingPhase     = SwingPhase.WINDUP
var _current_attack_is_1: bool   = false
var _timer: float                = 0.0
var _anim_duration: float        = 1.85
var _damage_dealt: bool          = false
var _hitboxes_active: bool       = false
var _grab_made_contact: bool     = false
var _go_knockdown_after_anim     = false
var _qte_hud                     = null
var _hand_left:  Area3D          = null
var _hand_right: Area3D          = null
var _grab_hitbox: Area3D         = null
var _attack_index: int           = 0

func enter() -> void:
	_timer             = 0.0
	_damage_dealt      = false
	_hitboxes_active   = false
	_grab_made_contact = false
	_qte_hud           = null
	_swing_phase       = SwingPhase.WINDUP

	var nav_agent = enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if nav_agent:
		nav_agent.avoidance_enabled = false

	_cache_hand_hitboxes()
	_set_active_hitboxes(false)

	var attack_to_run: String = ""
	if enemy and "selected_attack_type" in enemy:
		attack_to_run = enemy.selected_attack_type
		# Consume the selection
		enemy.selected_attack_type = ""

	var token_manager = enemy.get_node("/root/AttackTokenManager")
	var player := _get_player()
	if player and player.is_grab:
		_start_attack_with_index(0)
	elif attack_to_run == "attack_grab":
		if token_manager.request_grab_token(enemy):
			_start_grab_reach()
		else:
			# Fallback if grab token denied
			_start_attack_with_index(0)
	elif attack_to_run == "attack_1":
		_start_attack_with_index(0)
	elif attack_to_run == "attack_2":
		_start_attack_with_index(1)
	else:
		# Fallback if no pre-selected attack is set
		if enemy and "guaranteed_grab_next_attack" in enemy and enemy.guaranteed_grab_next_attack:
			enemy.guaranteed_grab_next_attack = false
			if token_manager.request_grab_token(enemy):
				_start_grab_reach()
			else:
				_start_attack_with_index(0)
		elif randf() < grab_chance:
			if token_manager.request_grab_token(enemy):
				_start_grab_reach()
			else:
				_start_attack_with_index(0)
		else:
			_start_attack_with_index(randi() % 2)

func exit() -> void:
	var nav_agent = enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if nav_agent:
		nav_agent.avoidance_enabled = true
		
	_set_active_hitboxes(false)
	_dismiss_qte()
	# Disconnect hand signals
	for hand in [_hand_left, _hand_right, _grab_hitbox]:
		if hand and hand.area_entered.is_connected(_on_hand_area_entered):
			hand.area_entered.disconnect(_on_hand_area_entered)
			
	# Release the attack/grab tokens
	if enemy:
		var token_manager = enemy.get_node("/root/AttackTokenManager")
		token_manager.release_token(enemy)

func _start_attack_with_index(index: int) -> void:
	_phase = Phase.ATTACK
	for hand in [_hand_left, _hand_right]:
		if hand and hand is AttackHitbox:
			hand.attack_type = "attack"
	var anim: String = enemy.anim_set.attack_1 if index == 0 else enemy.anim_set.attack_2
	_current_attack_is_1 = (index == 0)
	_force_anim(anim, "attack")
	_anim_duration = _anim_length(anim, "attack")
	print("[StateAttack] Attack (index %d): %s (%.2fs)" % [index, anim, _anim_duration])

func physics_update(delta: float) -> void:
	_timer += delta
	match _phase:
		Phase.ATTACK:         _tick_attack()
		Phase.GRAB_REACHING:  _tick_grab_reach()
		Phase.GRAB_HOLDING:   _tick_grab_holding(delta)
		Phase.GRAB_RESOLVING: _tick_grab_resolving()
		Phase.DONE:           pass

func handle_hit(hit_data: Dictionary) -> String:
	var zone: String = hit_data.get("hit_zone", "body")
	match zone:
		"head", "foot", "left_foot", "right_foot":
			# If shot in the leg during the actual attack swing lunge OR the grab reach lunge
			var is_lunge = (_phase == Phase.ATTACK and _swing_phase == SwingPhase.SWING) or (_phase == Phase.GRAB_REACHING)
			if is_lunge and zone in ["foot", "left_foot", "right_foot"]:
				var knockdown = state_machine._states.get("StateKnockdown")
				if knockdown:
					knockdown.knockdown_mode = "SWING_SHOT"
					knockdown.stun_type = "head" # The user animation is "HIT head act 3..."
				return "StateKnockdown"
			return "StateTakedownable"
		_:
			return "StateStun"

# ── Attack ────────────────────────────────────────────────────────────────

func _start_attack() -> void:
	_phase = Phase.ATTACK
	for hand in [_hand_left, _hand_right]:
		if hand and hand is AttackHitbox:
			hand.attack_type = "attack"
	var anim: String = enemy.anim_set.get_attack_anim(_attack_index)
	_current_attack_is_1 = (anim == enemy.anim_set.attack_1)
	_attack_index += 1
	_force_anim(anim, "attack")
	_anim_duration = _anim_length(anim, "attack")
	print("[StateAttack] Attack: %s (%.2fs)" % [anim, _anim_duration])

@export var early_exit_fraction: float = 0.85

func _tick_attack() -> void:
	# Fallback for BlendTree filtering out Method Tracks
	var frac: float = _timer / max(_anim_duration, 0.01)
	
	var cur_start = attack1_swing_start_frac if _current_attack_is_1 else attack2_swing_start_frac
	var cur_end   = attack1_swing_end_frac if _current_attack_is_1 else attack2_swing_end_frac
	var should_open: bool = frac >= cur_start and frac <= cur_end
	
	if should_open and _swing_phase == SwingPhase.WINDUP:
		open_hitboxes()
	elif not should_open and _swing_phase == SwingPhase.SWING:
		close_hitboxes()
	
	_apply_movement_and_rotation()
		
	if _timer > 0.1 and enemy and enemy.anim_tree:
		var pb = enemy.anim_tree.get("parameters/attack/playback")
		if pb and pb.get_current_node() == "End":
			_finish()


# ── Grab ──────────────────────────────────────────────────────────────────

func _start_grab_reach() -> void:
	_phase = Phase.GRAB_REACHING
	if _grab_hitbox and _grab_hitbox is AttackHitbox:
		_grab_hitbox.attack_type = "grab"
	var anim = enemy.anim_set.grab_reach
	_force_anim(anim, "attack/grab")
	_anim_duration = _anim_length(anim, "attack/grab")
	print("[StateAttack] Grab: reaching (%.2fs)" % _anim_duration)



func _tick_grab_reach() -> void:
	# Fallback for BlendTree filtering out Method Tracks
	var frac: float = _timer / max(_anim_duration, 0.01)
	var should_open: bool = frac >= grab_start_frac and frac <= grab_end_frac
	
	if should_open and _swing_phase == SwingPhase.WINDUP:
		open_hitboxes()
	elif not should_open and _swing_phase == SwingPhase.SWING:
		close_hitboxes()
	
	_apply_movement_and_rotation()
		
	if _timer > 0.1 and enemy and enemy.anim_tree and not _grab_made_contact:
		var pb = enemy.anim_tree.get("parameters/attack/playback")
		if pb and pb.get_current_node() == "End":
			print("[StateAttack] Grab: whiffed")
			_finish()

func _start_grab_hold() -> void:
	_phase = Phase.GRAB_HOLDING
	_force_anim(enemy.anim_set.grab_hold, "attack/grab")
	var hud_script = load("res://scripts/ui/grab_qte_hud.gd")
	_qte_hud = hud_script.new(qte_duration, qte_shakes_needed)
	_qte_hud.escaped.connect(_on_qte_escaped)
	_qte_hud.caught.connect(_on_qte_caught)
	enemy.get_tree().root.add_child(_qte_hud)
	
	var player = _get_player()
	if player:
		var sm = player.get_node_or_null("Statemachine")
		if sm and sm.has_method("_change_state"):
			sm._change_state("Grab")
			
		# Force alignment
		var to_player = player.global_position - enemy.global_position
		to_player.y = 0.0
		var current_dist = to_player.length()
		if current_dist > 0.01:
			var dir_to_player = to_player / current_dist
			enemy.global_transform.basis = Basis.looking_at(dir_to_player, Vector3.UP)
			
			# Pull the zombie closer to the player to align the grab animations
			if current_dist > grab_hold_distance:
				enemy.global_position += dir_to_player * (current_dist - grab_hold_distance)
			
		var to_zombie = enemy.global_position - player.global_position
		to_zombie.y = 0.0
		# We don't instantly snap the player's rotation anymore.
		# Instead, we will smoothly pull the camera in _tick_grab_holding().

func _tick_grab_holding(delta: float) -> void:
	var player = _get_player()
	if player:
		var cam = player.get_node_or_null("Camera")
		if cam and "target_camera_rotation" in cam:
			var to_zombie = enemy.global_position - player.global_position
			to_zombie.y = 0.0
			if to_zombie.length_squared() > 0.01:
				var ideal_basis = Basis.looking_at(to_zombie.normalized(), Vector3.UP)
				# camera_rotation.x corresponds to -player.rotation.y
				var target_angle = -ideal_basis.get_euler().y
				# Smoothly pull the target rotation to face the zombie.
				# A high speed like 15.0 pulls it fast initially, but allows mouse wiggling.
				cam.target_camera_rotation.x = lerp_angle(cam.target_camera_rotation.x, target_angle, 15.0 * delta)

func _on_qte_escaped() -> void:
	print("[StateAttack] Grab: player ESCAPED (Zombie failed)")
	var player := _get_player()
	var sm = player.get_node_or_null("Statemachine")
	if sm:
		var grab_state = sm.get_node_or_null("Grab")
		if grab_state:
			grab_state.resolve_grab(false)
	_qte_hud = null
	
	if enemy.anim_tree:
		enemy.anim_tree.set("parameters/attack/grab/conditions/Fail", true)
		
	# Transition immediately to Knockdown!
	var knockdown = state_machine._states.get("StateKnockdown")
	if knockdown:
		knockdown.knockdown_mode = "SPECIAL_FOOT_HEAD"
		knockdown.stun_type = "head"
		knockdown.skip_act3 = false
	state_machine.transition_to("StateKnockdown")

func _on_qte_caught() -> void:
	print("[StateAttack] Grab: player CAUGHT (Zombie succeeds)")
	_go_knockdown_after_anim = false
	var player := _get_player()
	var sm = player.get_node_or_null("Statemachine")
	if sm:
		var grab_state = sm.get_node_or_null("Grab")
		if grab_state:
			grab_state.resolve_grab(true)
	_qte_hud = null
	_deal_damage(grab_damage, "grab")
	_phase = Phase.GRAB_RESOLVING
	
	if enemy.anim_tree:
		enemy.anim_tree.set("parameters/attack/grab/conditions/Success", true)
		
	var anim = enemy.anim_set.grab_success
	_force_anim(anim, "attack/grab")
	_anim_duration = _anim_length(anim, "attack/grab")
	_timer = 0.0

func _tick_grab_resolving() -> void:
	if _timer > 0.1 and enemy and enemy.anim_tree:
		var pb = enemy.anim_tree.get("parameters/attack/playback")
		if pb and pb.get_current_node() == "End":
			if _go_knockdown_after_anim:
				var knockdown = state_machine._states.get("StateKnockdown")
				if knockdown:
					knockdown.skip_act3 = true
				state_machine.transition_to("StateKnockdown")
			else:
				_finish()

# ── Shared helpers ────────────────────────────────────────────────────────

func _finish() -> void:
	if enemy:
		var extra_time = 0.0
		# If the zombie just finished throwing the player to the ground from a grab,
		# the player takes a few seconds to play their Fail + Getup animations.
		# We add the hunt state's attack_cooldown to the time so it scales with inspector values.
		if _phase == Phase.GRAB_RESOLVING:
			var hunt = state_machine._states.get("StateHunt")
			if hunt and "attack_cooldown" in hunt:
				extra_time = hunt.attack_cooldown
		enemy.last_attack_time = (Time.get_ticks_msec() / 1000.0) + extra_time
		
	_phase = Phase.DONE
	_swing_phase = SwingPhase.RECOVERY
	
	_set_active_hitboxes(false)
	_dismiss_qte()
	
	var hunt = state_machine._states.get("StateHunt")
	if hunt:
		hunt.trigger_attack_recovery = true
		
	state_machine.transition_to("StateHunt")

# --- Manual Animation Event Hooks ---

func open_hitboxes() -> void:
	_hitboxes_active = true
	_swing_phase = SwingPhase.SWING
	_set_active_hitboxes(true)

func close_hitboxes() -> void:
	_hitboxes_active = false
	_swing_phase = SwingPhase.RECOVERY
	_set_active_hitboxes(false)

func _apply_movement_and_rotation() -> void:
	var player = _get_player()
	
	var is_grab = (_phase == Phase.GRAB_REACHING)
	var cur_tracking_speed = grab_tracking_speed if is_grab else attack_tracking_speed
	var cur_forward_speed = grab_forward_speed if is_grab else attack_forward_speed
	var cur_min_speed = grab_min_speed if is_grab else attack_min_speed
	var cur_recovery_tracking = grab_recovery_tracking_speed if is_grab else recovery_tracking_speed
	var cur_recovery_fric = grab_recovery_friction if is_grab else recovery_friction
	
	var target_vel := Vector3.ZERO
	var anim_frac: float = _timer / max(_anim_duration, 0.01)
	
	match _swing_phase:
		SwingPhase.WINDUP:
			if player:
				var to_target = (player.global_position - enemy.global_position)
				to_target.y = 0.0
				if to_target.length_squared() > 0.01:
					var move_dir = to_target.normalized()
					var current_y = enemy.rotation.y
					var target_y = atan2(-move_dir.x, -move_dir.z)
					enemy.rotation.y = lerp_angle(current_y, target_y, cur_tracking_speed * enemy.get_physics_process_delta_time())
			
			target_vel = -enemy.global_transform.basis.z * cur_min_speed
			
		SwingPhase.SWING:
			# No rotation, pure forward lunge
			target_vel = -enemy.global_transform.basis.z * cur_forward_speed
			
		SwingPhase.RECOVERY:
			if player:
				var to_target = (player.global_position - enemy.global_position)
				to_target.y = 0.0
				if to_target.length_squared() > 0.01:
					var move_dir = to_target.normalized()
					var current_y = enemy.rotation.y
					var target_y = atan2(-move_dir.x, -move_dir.z)
					enemy.rotation.y = lerp_angle(current_y, target_y, cur_recovery_tracking * enemy.get_physics_process_delta_time())
					
			target_vel = -enemy.global_transform.basis.z * cur_min_speed
			
	target_vel.y = 0.0
	enemy.velocity = target_vel
	enemy.move_and_slide()

func _cache_hand_hitboxes() -> void:
	for skel_base in ["ZombieModel/rig_001/Skeleton3D", "ZombieModel/rig/Skeleton3D", "ZombieModel/rig_002/Skeleton3D", "ZombieModel/rig/GeneralSkeleton", "ZombieModel/rig_002/GeneralSkeleton"]:
		var l := enemy.get_node_or_null("%s/HitboxAttachLeftHand/AttackHitbox" % skel_base)
		var r := enemy.get_node_or_null("%s/HitboxAttachRightHand/AttackHitbox" % skel_base)
		if l or r:
			_hand_left  = l
			_hand_right = r
			break
	if not _hand_left:
		push_warning("[StateAttack] AttackHitbox not found on left hand")
	if not _hand_right:
		push_warning("[StateAttack] AttackHitbox not found on right hand")
		
	_grab_hitbox = enemy.find_child("GrabHitbox", true, false)
	if not _grab_hitbox:
		push_warning("[StateAttack] GrabHitbox not found! Please attach a new AttackHitbox named 'GrabHitbox' to the chest bone.")
		
	for hand in [_hand_left, _hand_right, _grab_hitbox]:
		if not hand:
			continue
		hand.collision_layer = 16
		hand.collision_mask  = 8
		hand.monitorable     = true
		hand.monitoring      = false
		if not hand.is_in_group("enemy_attack"):
			hand.add_to_group("enemy_attack")
		# Connect signal instead of polling
		if not hand.area_entered.is_connected(_on_hand_area_entered):
			hand.area_entered.connect(_on_hand_area_entered)

func _on_hand_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player_hitbox"):
		return
	match _phase:
		Phase.ATTACK:
			if _hitboxes_active and not _damage_dealt:
				print("[StateAttack] Signal hit — player attacked!")
				_damage_dealt = true
				_deal_damage(attack_damage, "attack")
		Phase.GRAB_REACHING:
			if _hitboxes_active and not _grab_made_contact:
				var player := _get_player()
				if player and player.is_grab:
					print("[StateAttack] Grab blocked — player already grabbed")
					_finish()
					return
				print("[StateAttack] Signal hit — grab contact!")
				_grab_made_contact = true
				_set_active_hitboxes(false)
				_start_grab_hold()

func _set_active_hitboxes(enabled: bool) -> void:
	if not enabled:
		for hb in [_hand_left, _hand_right, _grab_hitbox]:
			if hb:
				hb.monitoring  = false
				hb.monitorable = false
		return
		
	if _phase == Phase.GRAB_REACHING:
		if _grab_hitbox:
			_grab_hitbox.monitoring  = true
			_grab_hitbox.monitorable = true
	else:
		if _hand_left:
			_hand_left.monitoring  = true
			_hand_left.monitorable = true
		if _hand_right:
			_hand_right.monitoring  = true
			_hand_right.monitorable = true

func _hand_touches_player() -> bool:
	for hitbox in [_hand_left, _hand_right]:
		if not (hitbox and hitbox.monitoring):
			continue
		for area in hitbox.get_overlapping_areas():
			if area.is_in_group("player_hitbox"):
				return true
	return false

func _deal_damage(amount: int, source: String) -> void:
	var player := _get_player()
	if player and player.has_method("take_damage"):
		player.take_damage(amount)
	print("[StateAttack] %s dealt %d damage" % [source, amount])

func _anim_length(anim_name: String, sub_machine: String = "") -> float:
	if enemy and enemy.anim_player and enemy.anim_player.has_animation(anim_name):
		var raw_length = enemy.anim_player.get_animation(anim_name).length
		var global_scale = max(enemy.anim_player.speed_scale, 0.01)
		
		var tree = enemy.get_node_or_null("AnimationTree")
		if not tree:
			tree = enemy.get_node_or_null("ZombieModel/AnimationTree")
			
		if tree:
			var scale_path = "parameters/"
			if sub_machine != "":
				scale_path += sub_machine + "/"
			scale_path += anim_name + "/TimeScale/scale"
			
			var local_scale = tree.get(scale_path)
			if local_scale != null and typeof(local_scale) in [TYPE_FLOAT, TYPE_INT]:
				global_scale *= max(float(local_scale), 0.01)
				
		return raw_length / global_scale
	return 1.5

func _get_player() -> Node3D:
	var players: Array = enemy.get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if players.size() > 0 else null

func _dismiss_qte() -> void:
	if _qte_hud and is_instance_valid(_qte_hud):
		_qte_hud.queue_free()
	_qte_hud = null
