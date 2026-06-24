## Manages transitions between EnemyStates.
## Lives as a child node on the enemy. States are its children.
class_name EnemyStateMachine
extends Node

## Emitted whenever the active state changes.
signal state_changed(old_state: String, new_state: String)

## The state that is currently active.
var current_state: EnemyState = null

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
			
	current_state = _states[starting_state_name]
	current_state.enter()

## Transition to a new state by name. Safe to call from within a state.
func transition_to(new_state_name: String) -> void:
	if not _states.has(new_state_name):
		push_error("EnemyStateMachine: unknown state '%s'" % new_state_name)
		return
	if current_state != null and current_state.name == new_state_name:
		return  # Already in this state, no-op.

	var old_name: String = current_state.name as String if current_state else ""
	if current_state:
		current_state.exit()
	current_state = _states[new_state_name]
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
			if _states.has("StateHitPush"):
				_states["StateHitPush"].push_direction = hit_data.get("hit_direction", Vector3.ZERO)
				transition_to("StateHitPush")
				return
	elif hit_type == "takedown_splash":
		if not current_state.name in ["StateKnockdown", "StateGetUp", "StateDefeated"]:
			if _states.has("StateKnockdown"):
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
		transition_to(next)

## Returns the name of the current state, or "" if uninitialised.
func get_current_state_name() -> String:
	return current_state.name as String if current_state else ""
