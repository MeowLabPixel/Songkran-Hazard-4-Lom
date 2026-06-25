## Base class for all Anchalee AI states.
## Mirrors the EnemyState pattern — same lifecycle hooks, same untyped refs.
class_name AnchaleeState
extends Node

# Set by AnchaleeStateMachine on ready.
var Anchalee = null   # CharacterBody3D — untyped to avoid circular dependency
var state_machine = null  # AnchaleeStateMachine — untyped

func enter() -> void:
	pass

func exit() -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func update(_delta: float) -> void:
	pass

## Plays an animation only if it isn't already playing. No-ops if no AnimationPlayer.
func _play_anim(anim_name: String) -> void:
	if not Anchalee or not Anchalee.anim_player:
		return
	if Anchalee.anim_player.current_animation != anim_name:
		Anchalee.anim_player.play(anim_name)
