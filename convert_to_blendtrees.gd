@tool
extends EditorScript

func _run() -> void:
	print("--- CONVERTING ANIMATION NODES TO BLEND TREES ---")
	var scenes = ["res://scenes/enemy/MMeleeZom.tscn", "res://scenes/enemy/FMeleeZom.tscn"]
	
	for scene_path in scenes:
		if not ResourceLoader.exists(scene_path):
			continue
		
		var packed := load(scene_path) as PackedScene
		if not packed: continue
		var root = packed.instantiate()
		
		var tree: AnimationTree = null
		var nodes = [root]
		while nodes.size() > 0:
			var curr = nodes.pop_back()
			if curr is AnimationTree:
				tree = curr
				break
			nodes.append_array(curr.get_children())
			
		if tree and tree.tree_root and tree.tree_root is AnimationNodeStateMachine:
			_convert_sm(tree.tree_root)
			
			var packer = PackedScene.new()
			packer.pack(root)
			ResourceSaver.save(packer, scene_path)
			print("Successfully converted nodes in ", scene_path)
		root.free()

func _convert_sm(sm: AnimationNodeStateMachine) -> void:
	var states_to_convert = []
	for prop in sm.get_property_list():
		if prop.name.begins_with("states/") and prop.name.ends_with("/node"):
			var state_name = prop.name.replace("states/", "").replace("/node", "")
			var node = sm.get_node(state_name)
			
			if node is AnimationNodeStateMachine:
				_convert_sm(node) # Recursively convert nested state machines
			elif node is AnimationNodeAnimation:
				# It's a raw animation node! We should convert it!
				states_to_convert.append({"name": state_name, "node": node})
				
	for data in states_to_convert:
		var state_name = data.name
		var anim_node = data.node
		var pos = sm.get_node_position(state_name)
		
		# Create the new BlendTree
		var bt = AnimationNodeBlendTree.new()
		
		# Re-create the AnimationNodeAnimation
		var new_anim = AnimationNodeAnimation.new()
		new_anim.animation = anim_node.animation
		
		# Create TimeScale
		var ts = AnimationNodeTimeScale.new()
		
		# Add to BlendTree
		bt.add_node("Animation", new_anim, Vector2(0, 100))
		bt.add_node("TimeScale", ts, Vector2(300, 100))
		
		# Connect them
		bt.connect_node("TimeScale", 0, "Animation")
		bt.connect_node("output", 0, "TimeScale")
		
		# Replace the node in the state machine
		sm.replace_node(state_name, bt)
		sm.set_node_position(state_name, pos)
		print("Converted: ", state_name)
