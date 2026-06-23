@tool
extends EditorScript

func _run() -> void:
	print("--- Generating Deeply Nested Animation Tree (With Precise Spacing) ---")
	
	var scene_path := "res://scenes/enemy/MMeleeZom.tscn"
	var packed_scene := load(scene_path) as PackedScene
	if not packed_scene:
		print("Failed to load scene")
		return
		
	var root = packed_scene.instantiate()
	var anim_tree: AnimationTree = null
	var nodes_to_check = [root]
	while nodes_to_check.size() > 0:
		var current = nodes_to_check.pop_back()
		if current is AnimationTree:
			anim_tree = current
			break
		nodes_to_check.append_array(current.get_children())
	
	if not anim_tree:
		print("AnimationTree node not found!")
		root.free()
		return
		
	var anim_set = root.get("anim_set")
	if not anim_set:
		print("ZombieAnimSet not found on root!")
		root.free()
		return
		
	var root_sm = AnimationNodeStateMachine.new()
	
	var add_anim_node = func(sm: AnimationNodeStateMachine, anim_name: String, pos: Vector2):
		if not anim_name or anim_name.is_empty(): return
		if sm.has_node(anim_name): return
		var anim_node = AnimationNodeAnimation.new()
		anim_node.animation = anim_name
		sm.add_node(anim_name, anim_node, pos)
		sm.set_node_position(anim_name, pos)
		
	var add_transition = func(sm: AnimationNodeStateMachine, from: String, to: String, crossfade: float = 0.0, auto: bool = false):
		if not from or not to or from.is_empty() or to.is_empty(): return
		if not sm.has_node(from) or not sm.has_node(to): return
		var tr = AnimationNodeStateMachineTransition.new()
		tr.xfade_time = crossfade
		if auto:
			tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		sm.add_transition(from, to, tr)

	# --- 1. MAIN ---
	var sm_main = AnimationNodeStateMachine.new()
	sm_main.set_node_position("Start", Vector2(0, 150))
	add_anim_node.call(sm_main, anim_set.idle, Vector2(300, 50))
	add_anim_node.call(sm_main, anim_set.walk_anim, Vector2(300, 250))
	add_transition.call(sm_main, anim_set.idle, anim_set.walk_anim, 0.3)
	add_transition.call(sm_main, anim_set.walk_anim, anim_set.idle, 0.3)
	add_transition.call(sm_main, "Start", anim_set.idle, 0.0, true)
	root_sm.add_node("main", sm_main, Vector2(300, 150))
	root_sm.set_node_position("main", Vector2(300, 150))
	
	# --- 2. GRAB (NESTED IN ATTACK) ---
	var sm_grab = AnimationNodeStateMachine.new()
	sm_grab.set_node_position("Start", Vector2(0, 150))
	sm_grab.set_node_position("End", Vector2(1200, 150))
	add_anim_node.call(sm_grab, anim_set.grab_reach, Vector2(300, 50))
	add_anim_node.call(sm_grab, anim_set.grab_hold, Vector2(600, 50))
	add_anim_node.call(sm_grab, anim_set.grab_success, Vector2(900, -50))
	add_anim_node.call(sm_grab, anim_set.grab_fail, Vector2(900, 150))
	add_transition.call(sm_grab, anim_set.grab_reach, anim_set.grab_hold, 0.1, true)
	add_transition.call(sm_grab, "Start", anim_set.grab_reach, 0.0)
	add_transition.call(sm_grab, "Start", anim_set.grab_hold, 0.0)
	add_transition.call(sm_grab, "Start", anim_set.grab_success, 0.0)
	add_transition.call(sm_grab, "Start", anim_set.grab_fail, 0.0)
	add_transition.call(sm_grab, anim_set.grab_hold, "End", 0.1, true)
	add_transition.call(sm_grab, anim_set.grab_success, "End", 0.1, true)
	add_transition.call(sm_grab, anim_set.grab_fail, "End", 0.1, true)
	
	# --- 3. ATTACK ---
	var sm_attack = AnimationNodeStateMachine.new()
	sm_attack.set_node_position("Start", Vector2(0, 150))
	sm_attack.set_node_position("End", Vector2(700, 150))
	add_anim_node.call(sm_attack, anim_set.attack_1, Vector2(300, 50))
	add_anim_node.call(sm_attack, anim_set.attack_2, Vector2(300, 150))
	sm_attack.add_node("grab", sm_grab, Vector2(300, 250))
	sm_attack.set_node_position("grab", Vector2(300, 250))
	add_transition.call(sm_attack, "Start", anim_set.attack_1, 0.0)
	add_transition.call(sm_attack, "Start", anim_set.attack_2, 0.0)
	add_transition.call(sm_attack, "Start", "grab", 0.0)
	# Connect to End
	add_transition.call(sm_attack, anim_set.attack_1, "End", 0.1, true)
	add_transition.call(sm_attack, anim_set.attack_2, "End", 0.1, true)
	add_transition.call(sm_attack, "grab", "End", 0.1, true)
	root_sm.add_node("attack", sm_attack, Vector2(700, 0))
	root_sm.set_node_position("attack", Vector2(700, 0))

	# --- 4. HIT STUN (NESTED IN HIT) ---
	var sm_stun = AnimationNodeStateMachine.new()
	sm_stun.set_node_position("Start", Vector2(0, 150))
	sm_stun.set_node_position("End", Vector2(700, 150))
	add_anim_node.call(sm_stun, anim_set.hit_body, Vector2(300, -50))
	add_anim_node.call(sm_stun, anim_set.hit_left_arm, Vector2(300, 100))
	add_anim_node.call(sm_stun, anim_set.hit_right_arm, Vector2(300, 250))
	add_transition.call(sm_stun, "Start", anim_set.hit_body, 0.0)
	add_transition.call(sm_stun, "Start", anim_set.hit_left_arm, 0.0)
	add_transition.call(sm_stun, "Start", anim_set.hit_right_arm, 0.0)
	add_transition.call(sm_stun, anim_set.hit_body, "End", 0.1, true)
	add_transition.call(sm_stun, anim_set.hit_left_arm, "End", 0.1, true)
	add_transition.call(sm_stun, anim_set.hit_right_arm, "End", 0.1, true)

	# --- 5. HIT TAKEDOWN (NESTED IN HIT) ---
	var sm_takedown = AnimationNodeStateMachine.new()
	sm_takedown.set_node_position("Start", Vector2(0, 200))
	sm_takedown.set_node_position("End", Vector2(1500, 200))
	var head = [anim_set.hit_head_act1, anim_set.hit_head_act2, anim_set.hit_head_act3, anim_set.hit_head_act4, anim_set.hit_head_act5]
	var lleg = [anim_set.hit_lleg_act1, anim_set.hit_lleg_act2, anim_set.hit_lleg_act3, anim_set.hit_lleg_act4, anim_set.hit_lleg_act5]
	var rleg = [anim_set.hit_rleg_act1, anim_set.hit_rleg_act2, anim_set.hit_rleg_act3, anim_set.hit_rleg_act4, anim_set.hit_rleg_act5]
	
	var y = 0
	for chain in [head, lleg, rleg]:
		var x = 300
		for act in chain:
			add_anim_node.call(sm_takedown, act, Vector2(x, y))
			x += 250
		for act in chain:
			add_transition.call(sm_takedown, "Start", act, 0.0)
		# Auto transitions Act 1 -> 2, Act 3 -> 4
		add_transition.call(sm_takedown, chain[0], chain[1], 0.1, true)
		add_transition.call(sm_takedown, chain[2], chain[3], 0.1, true)
		# End transition for Act 5
		add_transition.call(sm_takedown, chain[4], "End", 0.1, true)
		y += 150
		
	# --- 6. HIT ---
	var sm_hit = AnimationNodeStateMachine.new()
	sm_hit.set_node_position("Start", Vector2(0, 150))
	sm_hit.set_node_position("End", Vector2(700, 150))
	sm_hit.add_node("hit_stun", sm_stun, Vector2(300, 50))
	sm_hit.set_node_position("hit_stun", Vector2(300, 50))
	sm_hit.add_node("hit_takedown", sm_takedown, Vector2(300, 250))
	sm_hit.set_node_position("hit_takedown", Vector2(300, 250))
	add_transition.call(sm_hit, "Start", "hit_stun", 0.0)
	add_transition.call(sm_hit, "Start", "hit_takedown", 0.0)
	add_transition.call(sm_hit, "hit_stun", "End", 0.1, true)
	add_transition.call(sm_hit, "hit_takedown", "End", 0.1, true)
	root_sm.add_node("hit", sm_hit, Vector2(700, 300))
	root_sm.set_node_position("hit", Vector2(700, 300))
	
	# --- 7. DEFEATED ---
	var sm_defeated = AnimationNodeStateMachine.new()
	sm_defeated.set_node_position("Start", Vector2(0, 100))
	add_anim_node.call(sm_defeated, anim_set.dead, Vector2(300, 100))
	add_anim_node.call(sm_defeated, anim_set.dead_walk, Vector2(600, 100))
	add_transition.call(sm_defeated, "Start", anim_set.dead, 0.0)
	add_transition.call(sm_defeated, anim_set.dead, anim_set.dead_walk, 0.2, true)
	root_sm.add_node("defeated", sm_defeated, Vector2(400, -100))
	root_sm.set_node_position("defeated", Vector2(400, -100))

	# --- ROOT TRANSITIONS ---
	root_sm.set_node_position("Start", Vector2(0, 150))
	add_transition.call(root_sm, "Start", "main", 0.0, true)
	
	# main connects to everything
	for to in ["attack", "hit", "defeated"]:
		add_transition.call(root_sm, "main", to, 0.1)
		
	# attacks / hits connect back to main
	for from in ["attack", "hit"]:
		add_transition.call(root_sm, from, "main", 0.3)
		add_transition.call(root_sm, from, "defeated", 0.1)
		
	# hits can interrupt attacks
	add_transition.call(root_sm, "attack", "hit", 0.1)

	anim_tree.tree_root = root_sm
	
	# Re-pack and save
	var packer = PackedScene.new()
	packer.pack(root)
	var err = ResourceSaver.save(packer, scene_path)
	if err == OK:
		print("Successfully generated and saved PERFECTLY SPACED Nested AnimationTree to " + scene_path)
	else:
		print("Failed to save scene: ", err)
		
	root.free()
