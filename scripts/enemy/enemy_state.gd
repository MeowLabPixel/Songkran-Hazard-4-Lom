## Base class for all Enemy AI states.
## Each state extends this and overrides the relevant methods.
class_name EnemyState
extends Node

# Reference back to the enemy that owns this state machine.
# Set by EnemyStateMachine on ready.
var enemy: EnemyBase = null  # CharacterBody3D — untyped to avoid circular dependency
var state_machine = null  # EnemyStateMachine — untyped to avoid circular dependency

## Called when this state becomes active.
func enter() -> void:
	pass

## Called when this state is exited.
func exit() -> void:
	pass

## Called every physics frame while this state is active.
func physics_update(_delta: float) -> void:
	pass

## Called every frame while this state is active.
func update(_delta: float) -> void:
	pass

## Called when the enemy takes a hit.
## hit_data: Dictionary with keys: damage, hit_zone (String: "body","head","foot")
## Return the name (String) of the state to transition to, or "" to stay in current state.
func handle_hit(_hit_data: Dictionary) -> String:
	return ""

## Returns true if the state currently blocks the enemy from moving.
func is_movement_blocked() -> bool:
	return false

## Plays an animation, skipping only if it is actively mid-play right now.
## Uses is_playing() + current_animation so a finished one-shot can replay.
func _play_anim(anim_name: String, sub_machine: String = "") -> void:
	if not enemy: return
	
	var tree = enemy.get_node_or_null("AnimationTree") as AnimationTree
	if not tree:
		tree = enemy.get_node_or_null("ZombieModel/AnimationTree") as AnimationTree
		
	if tree and tree.active and tree.get("parameters/playback") != null:
		var root_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if root_playback:
			if sub_machine != "":
				var folders = sub_machine.split("/")
				root_playback.travel(folders[0])
				if folders.size() > 1:
					var intermediate = tree.get("parameters/" + folders[0] + "/playback") as AnimationNodeStateMachinePlayback
					if intermediate: intermediate.travel(folders[1])
				
				var sub_path = "parameters/" + sub_machine + "/playback"
				var sub_playback = tree.get(sub_path) as AnimationNodeStateMachinePlayback
				if sub_playback:
					sub_playback.travel(anim_name)
				else:
					push_warning("[EnemyState] _play_anim: sub_playback not found at " + sub_path)
			else:
				root_playback.travel(anim_name)
				
			if anim_name == enemy.anim_set.idle and enemy.next_idle_offset >= 0.0:
				var offset = enemy.next_idle_offset
				enemy.next_idle_offset = -1.0
				enemy.get_tree().process_frame.connect(func():
					if is_instance_valid(enemy) and is_instance_valid(enemy.anim_tree):
						enemy.anim_tree.advance(offset)
				, CONNECT_ONE_SHOT)
			return
			
	if not enemy.anim_player:
		push_warning("[EnemyState] _play_anim: no anim_player on %s" % enemy.name)
		return
	var ap: AnimationPlayer = enemy.anim_player
	if ap.is_playing() and ap.current_animation == anim_name:
		return
	if not ap.has_animation(anim_name):
		push_warning("[EnemyState] _play_anim: animation '%s' not found on %s" % [anim_name, enemy.name])
		return
	ap.play(anim_name)

func _force_anim(anim_name: String, sub_machine: String = "", custom_speed: float = 1.0) -> void:
	_force_anim_ext(anim_name, sub_machine, custom_speed, false)

func _force_anim_instant(anim_name: String, sub_machine: String = "", custom_speed: float = 1.0) -> void:
	_force_anim_ext(anim_name, sub_machine, custom_speed, true)

func _force_anim_ext(anim_name: String, sub_machine: String = "", custom_speed: float = 1.0, start_instant: bool = false) -> void:
	if not enemy: return
	
	var tree = enemy.get_node_or_null("AnimationTree") as AnimationTree
	if not tree:
		tree = enemy.get_node_or_null("ZombieModel/AnimationTree") as AnimationTree
		
	if tree and tree.active and tree.get("parameters/playback") != null:
		var root_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if root_playback:
			if sub_machine != "":
				var folders = sub_machine.split("/")
				if start_instant:
					root_playback.start(folders[0])
				else:
					root_playback.travel(folders[0])
				if folders.size() > 1:
					var intermediate = tree.get("parameters/" + folders[0] + "/playback") as AnimationNodeStateMachinePlayback
					if intermediate:
						if start_instant:
							intermediate.start(folders[1])
						else:
							intermediate.travel(folders[1])
				
				var sub_path = "parameters/" + sub_machine + "/playback"
				var sub_playback = tree.get(sub_path) as AnimationNodeStateMachinePlayback
				if sub_playback:
					if start_instant:
						sub_playback.start(anim_name)
					else:
						sub_playback.travel(anim_name)
				else:
					# The sub-state machine was just started and its playback parameter
					# is not yet active in the AnimationTree. Wait one frame and retry.
					var tree_ref = enemy.get_tree()
					if tree_ref:
						tree_ref.process_frame.connect(func():
							if is_instance_valid(enemy) and is_instance_valid(tree):
								var p = tree.get(sub_path) as AnimationNodeStateMachinePlayback
								if p:
									if start_instant:
										p.start(anim_name)
									else:
										p.travel(anim_name)
								else:
									push_warning("[EnemyState] _force_anim: sub_playback still not found after 1 frame at " + sub_path)
						, CONNECT_ONE_SHOT)
			else:
				if start_instant:
					root_playback.start(anim_name)
				else:
					root_playback.travel(anim_name)
				
			if anim_name == enemy.anim_set.idle and enemy.next_idle_offset >= 0.0:
				var offset = enemy.next_idle_offset
				enemy.next_idle_offset = -1.0
				enemy.get_tree().process_frame.connect(func():
					if is_instance_valid(enemy) and is_instance_valid(enemy.anim_tree):
						enemy.anim_tree.advance(offset)
				, CONNECT_ONE_SHOT)
			return
			
	if not enemy.anim_player:
		push_warning("[EnemyState] _force_anim: no anim_player on %s" % enemy.name)
		return
	if not enemy.anim_player.has_animation(anim_name):
		push_warning("[EnemyState] _force_anim: animation '%s' not found on %s" % [anim_name, enemy.name])
		return
	enemy.anim_player.play(anim_name, -1.0, custom_speed)
