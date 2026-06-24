class_name StateGetUp
extends EnemyState

@export var getup_duration: float = 1.5

var _timer: float     = 0.0
var stun_type: String = "head"

func enter() -> void:
	_timer = 0.0
	if enemy:
		enemy.velocity = Vector3.ZERO
		enemy.move_and_slide()
	print("[StateGetUp] Getting up. Zone: %s" % stun_type)
	var anim = enemy.anim_set.get_up_anim(stun_type)
	_play_anim(anim, "hit/hit_takedown")
	if enemy and enemy.anim_player and enemy.anim_player.has_animation(anim):
		var anim_len = enemy.anim_player.get_animation(anim).length
		var speed: float = 1.0
		if enemy.anim_tree:
			var speed_val = enemy.anim_tree.get("parameters/hit/hit_takedown/" + anim + "/TimeScale/scale")
			if typeof(speed_val) in [TYPE_FLOAT, TYPE_INT] and float(speed_val) > 0.0:
				speed = float(speed_val)
		getup_duration = anim_len / speed
	else:
		getup_duration = 1.5

	if enemy:
		enemy.set_meta("getup_elapsed_time", 0.0)
		enemy.set_meta("getup_duration", getup_duration)

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	_timer += delta
	if enemy and enemy.has_meta("getup_elapsed_time"):
		var elapsed = enemy.get_meta("getup_elapsed_time") + delta
		enemy.set_meta("getup_elapsed_time", elapsed)

	if _timer >= 0.5:
		var hunt = state_machine._states.get("StateHunt")
		if hunt:
			var remain = max(getup_duration - 0.5, 0.5)
			hunt.trigger_getup_block(remain)
		state_machine.transition_to("StateHunt")

func handle_hit(hit_data: Dictionary) -> String:
	if enemy and enemy.has_meta("getup_elapsed_time") and enemy.has_meta("getup_duration"):
		var elapsed = enemy.get_meta("getup_elapsed_time")
		var duration = enemy.get_meta("getup_duration")
		if elapsed >= (duration / 2.0):
			var zone: String = hit_data.get("hit_zone", "body")
			match zone:
				"head", "foot", "left_foot", "right_foot":
					return "StateTakedownable"
				_:
					return "StateStun"
	return ""
