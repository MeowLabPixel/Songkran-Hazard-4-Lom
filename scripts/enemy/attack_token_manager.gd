## AttackTokenManager: global coordinator for coordinating enemy attacks and grabs.
## Prevents the player from being overwhelmed by limiting concurrent attacks/grabs.
extends Node

const MAX_ATTACK_TOKENS: int = 2
const MAX_GRAB_TOKENS: int = 1

# Tracks the enemies currently holding tokens
var _assigned_tokens: Array[EnemyBase] = []
var _active_grabbers: Array[EnemyBase] = []

# Staggered attack settings
var last_attack_start_time: float = 0.0
const ATTACK_STAGGER_DELAY: float = 0.5 # seconds

## Checks if a zombie is allowed to transition to its attack state.
## Enforces a stagger delay so that zombies don't attack simultaneously.
func request_attack_transition(enemy: EnemyBase) -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_attack_start_time < ATTACK_STAGGER_DELAY:
		return false
		
	last_attack_start_time = current_time
	print("[AttackTokenManager] Granted attack transition to: ", enemy.name)
	return true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(_delta: float) -> void:
	_update_token_assignments()

## Checks if an enemy currently has an attack token.
func has_token(enemy: EnemyBase) -> bool:
	return _assigned_tokens.has(enemy)

func _clear_all_tokens() -> void:
	for enemy in _assigned_tokens:
		if is_instance_valid(enemy):
			_reset_enemy_tree(enemy)
	_assigned_tokens.clear()
	_active_grabbers.clear()

func _reset_enemy_tree(enemy: EnemyBase) -> void:
	var tree = enemy.anim_tree
	if tree and tree.active:
		if "parameters/Walk Zombie/Transition/transition_request" in tree:
			tree.set("parameters/Walk Zombie/Transition/transition_request", "default")

func _update_token_assignments() -> void:
	# 1. Find player
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_clear_all_tokens()
		return
	var player = players[0] as Node3D
	
	# Check if the player is currently in a hit reaction, grab, or busy state
	var player_in_busy_state = false
	if player.has_method("is_invulnerable") and player.is_invulnerable():
		player_in_busy_state = true
		
	if player_in_busy_state:
		# Revoke all attack tokens immediately so zombies can't attack during player hit/grab states
		for enemy in _assigned_tokens:
			if is_instance_valid(enemy):
				_reset_enemy_tree(enemy)
		_assigned_tokens.clear()
		
		# Keep active grabber but clean up any invalid ones
		_active_grabbers = _active_grabbers.filter(_is_grabber_active)
		return
	
	# 2. Get all enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	# 3. Categorize enemies
	var active_attackers: Array[EnemyBase] = []
	var candidates: Array[EnemyBase] = []
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_defeated:
			continue
			
		var sm = enemy.state_machine
		if not sm or not sm.current_state:
			continue
			
		if sm.current_state.name == "StateAttack":
			active_attackers.append(enemy)
		elif sm.current_state.name == "StateHunt" and not enemy.attack_blocked:
			# Verify the enemy is not currently on attack cooldown
			var hunt = sm._states.get("StateHunt")
			var can_attack = true
			if hunt and "last_attack_time" in enemy:
				can_attack = (Time.get_ticks_msec() / 1000.0) - enemy.last_attack_time >= hunt.attack_cooldown
			if can_attack:
				candidates.append(enemy)
			
	# 4. Determine new token assignments
	var new_assignments: Array[EnemyBase] = []
	
	# Active attackers have absolute priority and lock their tokens
	for attacker in active_attackers:
		new_assignments.append(attacker)
		
	var remaining_slots = MAX_ATTACK_TOKENS - new_assignments.size()
	
	# 5. Assign remaining tokens to candidates based on distance
	if remaining_slots > 0 and not candidates.is_empty():
		var candidate_data = []
		for enemy in candidates:
			var dist = enemy.global_position.distance_to(player.global_position)
			
			var hunt = enemy.state_machine._states.get("StateHunt")
			if not hunt:
				continue
				
			# Candidates must be within Attack Prep Range (default 3m)
			var prep_range = hunt.attack_prep_range if "attack_prep_range" in hunt else 3.0
			if dist > prep_range:
				continue
				
			# Sticky distance advantage: subtract 0.3m if they already hold a token
			var sort_dist = dist
			if _assigned_tokens.has(enemy):
				sort_dist -= 0.3
				
			candidate_data.append({
				"enemy": enemy,
				"sort_dist": sort_dist
			})
			
		candidate_data.sort_custom(func(a, b): return a.sort_dist < b.sort_dist)
		
		var count = min(remaining_slots, candidate_data.size())
		for i in range(count):
			new_assignments.append(candidate_data[i].enemy)
			
	# 6. Handle token releases/revocations
	for old_enemy in _assigned_tokens:
		if is_instance_valid(old_enemy) and not new_assignments.has(old_enemy):
			# This enemy lost its token this frame
			_reset_enemy_tree(old_enemy)
			print("[AttackTokenManager] Revoked token from: ", old_enemy.name)
			
	# 7. Print newly gained tokens for debug logging
	for new_enemy in new_assignments:
		if not _assigned_tokens.has(new_enemy):
			print("[AttackTokenManager] Granted token to: ", new_enemy.name)
			
	_assigned_tokens = new_assignments
	
	# Prune grabbers
	_active_grabbers = _active_grabbers.filter(_is_grabber_active)

func _is_grabber_active(e: Node) -> bool:
	if not is_instance_valid(e) or e.is_defeated:
		return false
	var sm = e.state_machine
	if not sm or not sm.current_state or sm.current_state.name != "StateAttack":
		return false
	var attack_state = sm.current_state
	if "_phase" in attack_state:
		# Phase.ATTACK = 0, Phase.DONE = 4. We only keep if GRAB_REACHING (1), GRAB_HOLDING (2), or GRAB_RESOLVING (3)
		var phase = attack_state._phase
		if phase == 0 or phase == 4:
			return false
	return true

## Requests a grab token specifically (1 concurrent grab max).
func request_grab_token(enemy: EnemyBase) -> bool:
	_active_grabbers = _active_grabbers.filter(_is_grabber_active)
	
	if not is_instance_valid(enemy) or enemy.is_defeated:
		return false
		
	# Check if player is invulnerable/busy before granting a new grab token
	var players = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var player = players[0]
		if player.has_method("is_invulnerable") and player.is_invulnerable():
			# Allow the current active grabber to keep its token
			if _active_grabbers.has(enemy):
				return true
			print("[AttackTokenManager] Denied grab token to: ", enemy.name, " because player is busy/invulnerable")
			return false
		
	if _active_grabbers.has(enemy):
		return true
		
	if _active_grabbers.size() < MAX_GRAB_TOKENS:
		_active_grabbers.append(enemy)
		print("[AttackTokenManager] Granted grab token to: ", enemy.name, " | Active grabbers count: ", _active_grabbers.size())
		return true
		
	print("[AttackTokenManager] Denied grab token to: ", enemy.name)
	for g in _active_grabbers:
		if is_instance_valid(g):
			var state_name = "null"
			var phase_val = "null"
			var sm = g.state_machine
			if sm and sm.current_state:
				state_name = sm.current_state.name
				var cur_state = sm.current_state
				if "_phase" in cur_state:
					phase_val = str(cur_state._phase)
			print("  Active grabber: ", g.name, " | State: ", state_name, " | Phase: ", phase_val)
	return false

## Explicit release helper
func release_token(enemy: EnemyBase) -> void:
	if _assigned_tokens.has(enemy):
		_assigned_tokens.erase(enemy)
		_reset_enemy_tree(enemy)
		print("[AttackTokenManager] Explicitly released attack token from: ", enemy.name)
		
	if _active_grabbers.has(enemy):
		_active_grabbers.erase(enemy)
		print("[AttackTokenManager] Explicitly released grab token from: ", enemy.name, " | Active grabbers count: ", _active_grabbers.size())
