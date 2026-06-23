@tool
extends EditorScript

func _run() -> void:
	print("--- Fixing Non-Uniform Scale for Hitboxes ---")
	
	var scenes = ["res://scenes/enemy/MMeleeZom.tscn", "res://scenes/enemy/FMeleeZom.tscn"]
	
	for scene_path in scenes:
		if not ResourceLoader.exists(scene_path):
			continue
			
		var packed_scene := load(scene_path) as PackedScene
		if not packed_scene:
			continue
			
		var root = packed_scene.instantiate()
		
		# Find the skeleton
		var skeleton: Skeleton3D = null
		var nodes = [root]
		while nodes.size() > 0:
			var curr = nodes.pop_back()
			if curr is Skeleton3D:
				skeleton = curr
				break
			nodes.append_array(curr.get_children())
			
		if not skeleton:
			print("No skeleton found in ", scene_path)
			root.free()
			continue
			
		# Find or create Hitboxes root
		var hitboxes_root = root.get_node_or_null("Hitboxes")
		if not hitboxes_root:
			hitboxes_root = Node3D.new()
			hitboxes_root.name = "Hitboxes"
			root.add_child(hitboxes_root)
			hitboxes_root.owner = root
		
		# Find all BoneAttachment3D
		for child in skeleton.get_children():
			if child is BoneAttachment3D:
				# Find the Area3D hitbox inside it
				var hitbox: Area3D = null
				for c in child.get_children():
					if c is Area3D:
						hitbox = c
						break
				
				if hitbox:
					print("Fixing: ", hitbox.name)
					# 1. Store the local transform of the hitbox
					var local_trans = hitbox.transform
					
					# 2. Reparent the hitbox to the root 'Hitboxes' node
					child.remove_child(hitbox)
					hitboxes_root.add_child(hitbox)
					hitbox.owner = root
					
					# 3. Create a RemoteTransform3D in the BoneAttachment3D
					var remote = RemoteTransform3D.new()
					remote.name = "Remote" + hitbox.name
					remote.transform = local_trans # Keep the local offset!
					remote.update_scale = false # FIXES THE NON-UNIFORM SCALE ERROR
					child.add_child(remote)
					remote.owner = root
					
					# 4. Point it to the hitbox
					remote.remote_path = remote.get_path_to(hitbox)
					
					# 5. Fix ownership of hitbox children (CollisionShape3D, HitboxZone)
					for hc in hitbox.get_children():
						hc.owner = root

		# Repack and save
		var packer = PackedScene.new()
		packer.pack(root)
		var err = ResourceSaver.save(packer, scene_path)
		if err == OK:
			print("Successfully fixed hitboxes for ", scene_path)
		else:
			print("Failed to save ", scene_path, ": ", err)
			
		root.free()
