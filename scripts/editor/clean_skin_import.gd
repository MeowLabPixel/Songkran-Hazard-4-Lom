@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	clean_node(scene, scene)
	return scene

func clean_node(node: Node, root: Node) -> void:
	if node is MeshInstance3D:
		var skeleton = node.get_node_or_null(node.skeleton) as Skeleton3D
		if skeleton and node.skin:
			var skin = node.skin
			var valid_binds = []
			
			# Filter out any binds that don't exist in the skeleton
			for i in range(skin.get_bind_count()):
				var bind_name = skin.get_bind_name(i)
				if skeleton.find_bone(bind_name) != -1:
					valid_binds.append({
						"name": bind_name,
						"pose": skin.get_bind_pose(i)
					})
			
			# If we found invalid binds, rebuild a clean skin resource
			if valid_binds.size() < skin.get_bind_count():
				var new_skin = Skin.new()
				for i in range(valid_binds.size()):
					new_skin.add_bind(i, valid_binds[i].pose)
					new_skin.set_bind_name(i, valid_binds[i].name)
				node.skin = new_skin
	
	for child in node.get_children():
		clean_node(child, root)
