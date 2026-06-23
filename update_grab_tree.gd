@tool
extends EditorScript

func _run() -> void:
	print("--- UPDATING GRAB STATE MACHINE ---")
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
			var root_sm = tree.tree_root as AnimationNodeStateMachine
			if root_sm.has_node("attack"):
				var attack_sm = root_sm.get_node("attack") as AnimationNodeStateMachine
				if attack_sm and attack_sm.has_node("grab"):
					var grab_sm = attack_sm.get_node("grab") as AnimationNodeStateMachine
					if grab_sm:
						# Rename the old node to the new name "Zombie Grab Loop"
						if grab_sm.has_node("Zombie Grab success_"):
							grab_sm.rename_node("Zombie Grab success_", "Zombie Grab Loop")
							print("Successfully updated grab node to 'Zombie Grab Loop' in ", scene_path)
							
							# Save scene
							var packer = PackedScene.new()
							packer.pack(root)
							ResourceSaver.save(packer, scene_path)
						else:
							print("Could not find old node 'Zombie Grab success_' in ", scene_path)
		root.free()
