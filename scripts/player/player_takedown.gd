extends State
#temp can do when idle,run,sprint
var anim_name = "TD/Take down anim"

var splash_area: Area3D = null
var _hit_primary: bool = false
var _hit_enemies: Array[Node] = []

func _enter() -> void:
	print(name)
	_hit_primary = false
	_hit_enemies.clear()
	
	# Play Rookie Lee attack grunt (low chance for heavy attack grunt)
	if randf() < 0.15:
		SoundManager.play_3d("vo_leon_attack", owner)
	else:
		SoundManager.play_3d("vo_leon_quickattack", owner)
		
	# Play Rookie Lee takedown sound and Region_PlayerTakedownAttackStart
	SoundManager.play_3d("leon_takedown", owner)
	SoundManager.play_3d("Region_PlayerTakedownAttackStart", owner)
		
	owner.stun_detect.monitorable = true
	owner.aim_bone_on(false)
	stop_moving()
	owner.anim.get(owner.anim_playback).travel("Takedown")
	if not owner.anim.animation_finished.is_connected(anim_done):
		owner.anim.animation_finished.connect(anim_done)
	owner.hitboxF.monitoring = false
	owner.hitboxB.monitoring = false
	
	# Reference the pre-configured takedown hitbox in the scene
	splash_area = owner.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/PlayerTakedownHitBox/TakedownHitbox")
	if splash_area:
		splash_area.monitoring = true
		if not splash_area.area_entered.is_connected(_on_splash_area_entered):
			splash_area.area_entered.connect(_on_splash_area_entered)
	else:
		push_warning("[PlayerTakedown] TakedownHitbox not found at path Re4Lom Base Rig/rig/Skeleton3D/PlayerTakedownHitBox/TakedownHitbox")
		
func _update(_delta: float) -> void:
	_check_overlapping_splash()

func _exit() -> void:
	# Removed the safety fallback: enemies will now ONLY be knocked down if the physical TakedownHitbox actually collided with them!
	if is_instance_valid(owner):
		if owner.stun_detect:
			owner.stun_detect.monitorable = false
		if owner.anim and is_instance_valid(owner.anim) and owner.anim.animation_finished.is_connected(anim_done):
			owner.anim.animation_finished.disconnect(anim_done)
	
	if is_instance_valid(splash_area):
		if splash_area.area_entered.is_connected(_on_splash_area_entered):
			splash_area.area_entered.disconnect(_on_splash_area_entered)
	splash_area = null

func anim_done(namee: String):
	if namee == anim_name:
		finished.emit("Idle")
		owner.hitboxF.monitoring = true
		owner.hitboxB.monitoring = true

func stop_moving():
	var dire = Vector3.ZERO
	owner.set_velocity_from_motion(dire)

func _check_overlapping_splash() -> void:
	if not is_instance_valid(splash_area):
		return
	for a in splash_area.get_overlapping_areas():
		_process_splash_hit(a)

func _on_splash_area_entered(area: Area3D) -> void:
	_process_splash_hit(area)

func _process_splash_hit(area: Area3D) -> void:
	var enemy = _find_enemy_from_area(area)
	if enemy and not enemy.is_defeated:
		if enemy == owner.takedown_target:
			if not _hit_primary:
				if enemy.has_method("trigger_takedown"):
					enemy.trigger_takedown()
				else:
					var sm = enemy.get_node_or_null("EnemyStateMachine")
					if sm:
						var td = sm.get_node_or_null("StateTakedownable")
						if td:
							td.trigger_takedown()
				
				var hit_dir = (enemy.global_position - owner.global_position).normalized()
				hit_dir.y = 0.0
				hit_dir = hit_dir.normalized()
				if enemy.has_method("take_hit"):
					enemy.take_hit({
						"damage": 1.33,
						"hit_zone": "body",
						"hit_type": "takedown",
						"hit_direction": hit_dir,
						"source": owner
					})
				_hit_primary = true
			return
			
		if enemy in _hit_enemies:
			return
		_hit_enemies.append(enemy)
		
		var zone_name := "body"
		var hitbox_zone = area.get_node_or_null("HitboxZone")
		if not hitbox_zone:
			for child in area.get_children():
				if child is HitboxZone:
					hitbox_zone = child
					break
		if hitbox_zone:
			zone_name = hitbox_zone.zone_name
			
		var hit_dir = (enemy.global_position - owner.global_position).normalized()
		hit_dir.y = 0.0
		hit_dir = hit_dir.normalized()
		
		enemy.take_hit({
			"damage": 1.33,
			"hit_zone": zone_name,
			"hit_type": "takedown_splash",
			"hit_direction": hit_dir,
			"source": owner
		})

func _find_enemy_from_area(area: Area3D) -> Node:
	var node = area
	while node:
		if node is EnemyBase:
			return node
		node = node.get_parent()
	return null
