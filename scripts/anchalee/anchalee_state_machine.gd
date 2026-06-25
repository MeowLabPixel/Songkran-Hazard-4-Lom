## Manages transitions between AnchaleeStates.
## Direct mirror of EnemyStateMachine — states are child nodes.
class_name AnchaleeStateMachine
extends Node

signal state_changed(old_state: String, new_state: String)

var current_state: AnchaleeState = null
var _states: Dictionary = {}

var Anchalee: AnchaleeBase
var state_machine: AnchaleeStateMachine

func enter() -> void: pass
func exit() -> void: pass
func physics_update(delta: float) -> void: pass
func update(delta: float) -> void: pass

func _ready() -> void:
	var Anchalee_node = get_parent()
	for child in get_children():
		if child is AnchaleeState:
			child.Anchalee = Anchalee_node
			child.state_machine = self
			_states[child.name] = child

func initialize(starting_state_name: String) -> void:
	if not _states.has(starting_state_name):
		push_error("AnchaleeStateMachine: unknown starting state '%s'" % starting_state_name)
		return
	current_state = _states[starting_state_name]
	current_state.enter()

func transition_to(new_state_name: String) -> void:
	if not _states.has(new_state_name):
		push_error("AnchaleeStateMachine: unknown state '%s'" % new_state_name)
		return
	if current_state != null and current_state.name == new_state_name:
		return
	var old_name: String = current_state.name as String if current_state else ""
	if current_state:
		current_state.exit()
	current_state = _states[new_state_name]
	current_state.enter()
	state_changed.emit(old_name, new_state_name)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func get_current_state_name() -> String:
	return current_state.name as String if current_state else ""
