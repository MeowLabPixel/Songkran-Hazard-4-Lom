## Manages transitions between EnemyStates.
## Lives as a child node on the enemy. States are its children.
class_name EnemyStateMachine
extends Node

## Emitted whenever the active state changes.
signal state_changed(old_state: String, new_state: String)

## The state that is currently active.
var current_state: EnemyState = null
var next_state_name: String = ""

## Internal map of state name → EnemyState node, built on ready.
var _states: Dictionary = {}

func _ready() -> void:
	# Grab the enemy (our parent) and wire every child state.
	var enemy_node = get_parent()
	for child in get_children():
		if child is EnemyState:
			child.enemy = enemy_node
			child.state_machine = self
			_states[child.name] = child

## Call this after _ready to boot into the initial state.
func initialize(starting_state_name: String) -> void:
	if not _states.has(starting_state_name):
		push_error("EnemyStateMachine: unknown starting state '%s'" % starting_state_name)
		return
		
	for state in _states.values():
		if state.has_method("initialize_state"):
			state.initialize_state()
			
	_update_collision_for_state(starting_state_name)
	current_state = _states[starting_state_name]
	current_state.enter()

## Transition to a new state by name. Safe to call from within a state.
func transition_to(new_state_name: String, force_reenter: bool = false) -> void:
	if not _states.has(new_state_name):
		push_error("EnemyStateMachine: unknown state '%s'" % new_state_name)
		return
	if not force_reenter and current_state != null and current_state.name == new_state_name:
		return  # Already in this state, no-op.

	var old_name: String = current_state.name as String if current_state else ""
	next_state_name = new_state_name
	if current_state:
		current_state.exit()
	next_state_name = ""
	current_state = _states[new_state_name]
	_update_collision_for_state(new_state_name)
	current_state.enter()
	state_changed.emit(old_name, new_state_name)

# --- Animation Event Hooks ---

func open_hitboxes() -> void:
	if current_state and current_state.has_method("open_hitboxes"):
		current_state.open_hitboxes()

func close_hitboxes() -> void:
	if current_state and current_state.has_method("close_hitboxes"):
		current_state.close_hitboxes()

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

## Convenience: forward a hit event to the current state.
## If the state returns a non-empty string, transition to that state.
func handle_hit(hit_data: Dictionary) -> void:
	if not current_state:
		return

	# Handle custom system hit types
	var hit_type = hit_data.get("hit_type", "")
	if hit_type == "push":
		if not current_state.name in ["StateKnockdown", "StateGetUp", "StateDefeated"]:
			if current_state.name == "StateTakedownable":
				var td = current_state as StateTakedownable
				var is_foot_stun = td and td.stun_type != "head"
				if is_foot_stun:
					if _states.has("StateKnockdown"):
						var knockdown = _states["StateKnockdown"]
						knockdown.knockdown_mode = "SPECIAL_LEG_SHOT"
						knockdown.start_offset_override = 1.25
						if td.stun_type == "right_foot":
							knockdown.special_side = "R"
							knockdown.stun_type = "right_foot"
						else:
							knockdown.special_side = "L"
							knockdown.stun_type = "left_foot"
						transition_to("StateKnockdown")
						return
				else:
					if _states.has("StateHitPush"):
						_states["StateHitPush"].push_direction = hit_data.get("hit_direction", Vector3.ZERO)
						transition_to("StateHitPush", true)
						return
			elif _states.has("StateHitPush"):
				_states["StateHitPush"].push_direction = hit_data.get("hit_direction", Vector3.ZERO)
				var force = (current_state.name == "StateHitPush")
				transition_to("StateHitPush", force)
				return
	elif hit_type in ["takedown", "takedown_splash"]:
		if not current_state.name in ["StateKnockdown", "StateGetUp", "StateDefeated"]:
			if current_state.name == "StateTakedownable":
				var td = current_state as StateTakedownable
				if td:
					td.trigger_takedown()
					return
			elif _states.has("StateTakedownable"):
				var td = _states["StateTakedownable"] as StateTakedownable
				if td:
					td.stun_type = hit_data.get("hit_zone", "head")
					transition_to("StateTakedownable")
					td.trigger_takedown()
					return
			elif _states.has("StateKnockdown"):
				_states["StateKnockdown"].knockdown_mode = "NORMAL"
				_states["StateKnockdown"].stun_type = hit_data.get("hit_zone", "head")
				transition_to("StateKnockdown")
				return


	var next := current_state.handle_hit(hit_data)
	if next != "":
		# Pre-load zone data into destination state before enter() runs.
		if next == "StateTakedownable" and _states.has("StateTakedownable"):
			_states["StateTakedownable"].stun_type = hit_data.get("hit_zone", "head")
		if next == "StateStun" and _states.has("StateStun"):
			_states["StateStun"].hit_zone = hit_data.get("hit_zone", "body")
		# Forward stun_type to Knockdown so it plays the right leg/head sequence.
		if next == "StateKnockdown" and _states.has("StateKnockdown"):
			var td = _states.get("StateTakedownable")
			if td:
				_states["StateKnockdown"].stun_type = td.stun_type
		# Force re-enter when transitioning from hit-reaction states so animations restart cleanly
		var force = current_state.name in ["StateHitPush", "StateStun"]
		transition_to(next, force)

## Returns the name of the current state, or "" if uninitialised.
func get_current_state_name() -> String:
	return current_state.name as String if current_state else ""

func _update_collision_for_state(state_name: String) -> void:
	var enemy_node = get_parent()
	if not enemy_node:
		return
		
	# Active states have collision with other enemies and enable navigation avoidance.
	# Floor/disabled states disable these to avoid creating invisible walls.
	var is_collidable = true
	if state_name in ["StateTakedownable", "StateKnockdown", "StateGetUp", "StateDefeated"]:
		is_collidable = false
		
	enemy_node.set_collision_layer_value(3, is_collidable)
	enemy_node.set_collision_mask_value(3, is_collidable)
	
	var nav_agent = enemy_node.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if nav_agent:
		nav_agent.avoidance_enabled = is_collidable
