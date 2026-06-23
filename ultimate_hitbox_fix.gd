@tool
extends EditorScript

func _run() -> void:
	print("--- EXECUTING ULTIMATE HITBOX FIX ---")
	
	var scenes = ["res://scenes/enemy/MMeleeZom.tscn", "res://scenes/enemy/FMeleeZom.tscn"]
	
	for scene_path in scenes:
		if not ResourceLoader.exists(scene_path):
			continue
			
		var packed_scene := load(scene_path) as PackedScene
		if not packed_scene:
			continue
			
		var root = packed_scene.instantiate()
		
		# 1. SCRUB ALL BAKED SCALES
		var nodes = [root]
		while nodes.size() > 0:
			var curr = nodes.pop_back()
			if curr is CollisionShape3D or curr is Area3D or curr is RemoteTransform3D:
				var t = curr.transform
				var b = t.basis
				var s = b.get_scale()
				if abs(s.x - 1.0) > 0.0001 or abs(s.y - 1.0) > 0.0001 or abs(s.z - 1.0) > 0.0001:
					curr.transform.basis = b.orthonormalized()
					print("Scrubbed baked scale on: ", curr.name)
			nodes.append_array(curr.get_children())

		# 2. SEPARATE HITBOXES FROM BONES
		var skeleton: Skeleton3D = null
		nodes = [root]
		while nodes.size() > 0:
			var curr = nodes.pop_back()
			if curr is Skeleton3D:
				skeleton = curr
				break
			nodes.append_array(curr.get_children())
			
		if skeleton:
			var hitboxes_root = root.get_node_or_null("Hitboxes")
			if not hitboxes_root:
				hitboxes_root = Node3D.new()
				hitboxes_root.name = "Hitboxes"
				root.add_child(hitboxes_root)
				hitboxes_root.owner = root
				
			for child in skeleton.get_children():
				if child is BoneAttachment3D:
					var hitbox: Area3D = null
					for c in child.get_children():
						if c is Area3D:
							hitbox = c
							break
					
					if hitbox:
						print("Decoupling: ", hitbox.name)
						var local_trans = hitbox.transform
						local_trans.basis = local_trans.basis.orthonormalized() # Scrub scale
						
						child.remove_child(hitbox)
						hitboxes_root.add_child(hitbox)
						hitbox.owner = root
						hitbox.transform = Transform3D.IDENTITY
						
						var remote = RemoteTransform3D.new()
						remote.name = "Remote" + hitbox.name
						remote.transform = local_trans
						remote.update_scale = false
						child.add_child(remote)
						remote.owner = root
						remote.remote_path = remote.get_path_to(hitbox)
						
						for hc in hitbox.get_children():
							hc.owner = root

		# Save
		var packer = PackedScene.new()
		packer.pack(root)
		var err = ResourceSaver.save(packer, scene_path)
		if err == OK:
			print("SUCCESSFULLY CLEANED AND FIXED: ", scene_path)
		else:
			print("Failed to save: ", err)
			
		root.free()
