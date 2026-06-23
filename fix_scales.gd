@tool
extends EditorScript

func _run() -> void:
	print("--- Forcing Uniform Scale on Hitboxes ---")
	
	var scenes = ["res://scenes/enemy/MMeleeZom.tscn", "res://scenes/enemy/FMeleeZom.tscn"]
	
	for scene_path in scenes:
		if not ResourceLoader.exists(scene_path):
			continue
			
		var packed_scene := load(scene_path) as PackedScene
		if not packed_scene:
			continue
			
		var root = packed_scene.instantiate()
		
		var nodes = [root]
		var count = 0
		while nodes.size() > 0:
			var curr = nodes.pop_back()
			
			if curr is CollisionShape3D or curr is Area3D:
				var t = curr.transform
				var b = t.basis
				# If scale is not perfectly 1, 1, 1
				var s = b.get_scale()
				if abs(s.x - 1.0) > 0.0001 or abs(s.y - 1.0) > 0.0001 or abs(s.z - 1.0) > 0.0001:
					b = b.orthonormalized()
					curr.transform.basis = b
					print("Fixed scale on ", curr.name, " (was ", s, ")")
					count += 1
					
			nodes.append_array(curr.get_children())

		if count > 0:
			var packer = PackedScene.new()
			packer.pack(root)
			var err = ResourceSaver.save(packer, scene_path)
			if err == OK:
				print("Successfully fixed ", count, " nodes in ", scene_path)
			else:
				print("Failed to save ", scene_path, ": ", err)
		else:
			print("No non-uniform scales found in ", scene_path)
			
		root.free()
