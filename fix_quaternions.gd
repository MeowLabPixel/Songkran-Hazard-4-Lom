@tool
extends EditorScript

func _run() -> void:
	print("--- FIXING CORRUPT MIXAMO QUATERNIONS ---")
	var scenes = ["res://scenes/enemy/MMeleeZom.tscn", "res://scenes/enemy/FMeleeZom.tscn"]
	
	for scene_path in scenes:
		if not ResourceLoader.exists(scene_path):
			continue
		
		var packed := load(scene_path) as PackedScene
		if not packed: continue
		var root = packed.instantiate()
		
		# Find AnimationPlayer
		var anim_player: AnimationPlayer = null
		var nodes = [root]
		while nodes.size() > 0:
			var curr = nodes.pop_back()
			if curr is AnimationPlayer:
				anim_player = curr
				break
			nodes.append_array(curr.get_children())
			
		if anim_player:
			var libs = anim_player.get_animation_library_list()
			for lib_name in libs:
				var lib = anim_player.get_animation_library(lib_name)
				var anim_names = lib.get_animation_list()
				for anim_n in anim_names:
					var anim = lib.get_animation(anim_n)
					var fixed = 0
					for t in range(anim.get_track_count()):
						if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
							for k in range(anim.track_get_key_count(t)):
								var q = anim.track_get_key_value(t, k)
								if q is Quaternion:
									if not q.is_normalized():
										anim.track_set_key_value(t, k, q.normalized())
										fixed += 1
					if fixed > 0:
						print("Fixed ", fixed, " broken quaternions in: ", anim_n)
						
		# Save scene
		var packer = PackedScene.new()
		packer.pack(root)
		ResourceSaver.save(packer, scene_path)
		print("Successfully sanitized animations for: ", scene_path)
		root.free()
