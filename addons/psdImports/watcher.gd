@tool
extends EditorPlugin

var filesystem: EditorFileSystem


enum ScanMode {
	OPEN_SCENE_ONLY = 0,
	ALL_SCENES = 1,
	DISABLED = 2
}

func _enter_tree():
	filesystem = EditorInterface.get_resource_filesystem()
	filesystem.resources_reimported.connect(_on_resources_reimported)
	
	if _is_debug_enabled():
		var mode = _get_scan_mode()
		match mode:
			ScanMode.OPEN_SCENE_ONLY:
				print("PSD Watcher enabled - Open scene only (FAST)")
			ScanMode.ALL_SCENES:
				print("PSD Watcher enabled - Full project scan (SLOW)")
			ScanMode.DISABLED:
				print("PSD Watcher enabled - Scanning disabled")

func _exit_tree():
	if filesystem:
		filesystem.resources_reimported.disconnect(_on_resources_reimported)
	if _is_debug_enabled():
		print("PSD Watcher disabled")

func _on_resources_reimported(resources: PackedStringArray):
	var scan_mode = _get_scan_mode()
	if scan_mode == ScanMode.DISABLED:
		return
	
	for resource_path in resources:
		if resource_path.ends_with(".psd"):
			if _is_debug_enabled():
				print("========================================")
				print("PSD reimported: ", resource_path)
			_update_all_project_references(resource_path)
			if _is_debug_enabled():
				print("========================================")

func _update_all_project_references(psd_path: String):
	var new_img = ResourceLoader.load(psd_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not new_img or not new_img is Image:
		push_error("Failed to load updated PSD image")
		return
	
	var scan_mode = _get_scan_mode()
	
	if scan_mode == ScanMode.OPEN_SCENE_ONLY:
		var count = _update_open_scene(psd_path, new_img)
		if _is_debug_enabled() and count > 0:
			print("✓ Updated %d nodes in open scene" % count)
		return
	
	if _is_debug_enabled():
		print("Scanning entire project for references to this PSD...")
	
	var open_scene_count = _update_open_scene(psd_path, new_img)
	if _is_debug_enabled():
		print("Updated %d nodes in open scene" % open_scene_count)
	
	var scenes_updated = 0
	var total_nodes_updated = 0
	
	if scan_mode == ScanMode.ALL_SCENES:
		var scene_files = _find_all_scene_files()
		if _is_debug_enabled():
			print("Found %d scene files to scan" % scene_files.size())
		
		for scene_path in scene_files:
			var current_scene = EditorInterface.get_edited_scene_root()
			if current_scene and current_scene.scene_file_path == scene_path:
				continue
			
			var result = _update_scene_file(scene_path, psd_path, new_img)
			if result > 0:
				scenes_updated += 1
				total_nodes_updated += result
	
	var materials_updated = 0
	if _should_scan_materials():
		var material_files = _find_all_material_files()
		if _is_debug_enabled():
			print("Found %d material files to scan" % material_files.size())
		
		for material_path in material_files:
			if _update_material_file(material_path, psd_path, new_img):
				materials_updated += 1
	
	if _is_debug_enabled():
		print("─────────────────────────────────────")
		print("✓ Summary:")
		print("  Open scene: %d nodes updated" % open_scene_count)
		if scan_mode == ScanMode.ALL_SCENES:
			print("  Closed scenes: %d scenes, %d nodes updated" % [scenes_updated, total_nodes_updated])
		if _should_scan_materials():
			print("  Materials: %d updated" % materials_updated)
		print("─────────────────────────────────────")

func _update_open_scene(psd_path: String, new_img: Image) -> int:
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene:
		return 0
	
	if _is_debug_enabled():
		print("Scanning all nodes in scene '%s'..." % edited_scene.name)
	
	var count = _update_nodes_recursive(edited_scene, psd_path, new_img)
	
	if count > 0:
		EditorInterface.mark_scene_as_unsaved()
	
	if _is_debug_enabled():
		print("Total nodes updated: %d" % count)
	
	return count

func _find_all_scene_files() -> Array:
	var scenes = []
	_scan_directory_for_extension("res://", ".tscn", scenes)
	return scenes

func _find_all_material_files() -> Array:
	var materials = []
	_scan_directory_for_extension("res://", ".tres", materials)
	return materials

func _scan_directory_for_extension(path: String, extension: String, results: Array):
	var dir = DirAccess.open(path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path + "/" + file_name if path != "res://" else path + file_name
		
		if dir.current_is_dir():
			if file_name != "." and file_name != ".." and file_name != ".godot" and file_name != ".import":
				_scan_directory_for_extension(full_path, extension, results)
		elif file_name.ends_with(extension):
			results.append(full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _update_scene_file(scene_path: String, psd_path: String, new_img: Image) -> int:
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		return 0
	
	var scene_root = packed_scene.instantiate()
	if not scene_root:
		return 0
	
	var count = _update_nodes_recursive(scene_root, psd_path, new_img)
	
	if count > 0:
		if _is_debug_enabled():
			print("  Updating scene: %s (%d nodes)" % [scene_path, count])
		var new_packed_scene = PackedScene.new()
		new_packed_scene.pack(scene_root)
		ResourceSaver.save(new_packed_scene, scene_path)
	
	scene_root.queue_free()
	return count

func _update_material_file(material_path: String, psd_path: String, new_img: Image) -> bool:
	var material = load(material_path)
	if not material:
		return false
	
	var updated = false
	
	if material is StandardMaterial3D:
		updated = _update_standard_material_3d(material, psd_path, new_img)
	elif material is ShaderMaterial:
		updated = _update_shader_material(material, psd_path, new_img)
	elif material is CanvasItemMaterial:
		pass
	
	if updated:
		if _is_debug_enabled():
			print("  Updating material: %s" % material_path)
		ResourceSaver.save(material, material_path)
	
	return updated

func _update_standard_material_3d(material: StandardMaterial3D, psd_path: String, new_img: Image) -> bool:
	var updated = false
	var new_texture = ImageTexture.create_from_image(new_img)
	
	var texture_properties = [
		"albedo_texture",
		"emission_texture",
		"metallic_texture",
		"roughness_texture",
		"normal_texture",
		"ao_texture",
		"height_texture",
		"refraction_texture",
		"detail_albedo",
		"detail_normal"
	]
	
	for prop in texture_properties:
		var texture = material.get(prop)
		if texture and _should_update_texture(material, prop, psd_path):
			material.set(prop, new_texture)
			updated = true
	
	return updated

func _update_shader_material(material: ShaderMaterial, psd_path: String, new_img: Image) -> bool:
	var updated = false
	var shader = material.shader
	if not shader:
		return false
	
	var new_texture = ImageTexture.create_from_image(new_img)
	
	var params = material.get_property_list()
	for param in params:
		if param.type == TYPE_OBJECT and param.hint == PROPERTY_HINT_RESOURCE_TYPE:
			var param_name = param.name
			if param_name.begins_with("shader_parameter/"):
				var actual_param = param_name.substr("shader_parameter/".length())
				var value = material.get_shader_parameter(actual_param)
				
				if value is Texture2D and _should_update_texture(material, param_name, psd_path):
					material.set_shader_parameter(actual_param, new_texture)
					updated = true
	
	return updated

func _should_update_texture(resource: Resource, property: String, psd_path: String) -> bool:
	var meta_key = "psd_source_" + property
	if resource.has_meta(meta_key):
		return resource.get_meta(meta_key) == psd_path
	
	var texture = resource.get(property)
	if texture:
		if texture.resource_path == psd_path:
			resource.set_meta(meta_key, psd_path)
			return true
		
		if texture is ImageTexture:
			var img = texture.get_image()
			if img and img.has_meta("psd_source") and img.get_meta("psd_source") == psd_path:
				resource.set_meta(meta_key, psd_path)
				return true
	
	return false

func _update_nodes_recursive(node: Node, psd_path: String, new_img: Image) -> int:
	var count = 0
	var new_texture = ImageTexture.create_from_image(new_img)
	
	if _is_debug_enabled():
		print("Scanning node: %s (type: %s)" % [node.name, node.get_class()])
	
	var texture_property = ""
	
	if node is TextureRect:
		texture_property = "texture"
	elif node is Sprite2D or node is Sprite3D:
		texture_property = "texture"
	elif node is AnimatedSprite2D or node is AnimatedSprite3D:
		if _update_animated_sprite(node, psd_path, new_texture):
			count += 1
	elif node is TextureButton:
		for prop in ["texture_normal", "texture_pressed", "texture_hover", "texture_disabled", "texture_focused"]:
			if _update_node_texture_property(node, prop, psd_path, new_texture):
				count += 1
	elif node is TextureProgressBar:
		for prop in ["texture_under", "texture_over", "texture_progress"]:
			if _update_node_texture_property(node, prop, psd_path, new_texture):
				count += 1
	elif node is NinePatchRect:
		texture_property = "texture"
	elif node is Polygon2D:
		texture_property = "texture"
	elif node is Line2D:
		texture_property = "texture"
	elif node is CPUParticles2D:
		texture_property = "texture"
	elif node is CPUParticles3D:
		texture_property = "texture"
	elif node is GPUParticles2D:
		if node.process_material:
			if _update_particle_material(node.process_material, psd_path, new_img):
				count += 1
	elif node is GPUParticles3D:
		texture_property = "texture"
		if node.process_material:
			if _update_particle_material(node.process_material, psd_path, new_img):
				count += 1
	elif node is Decal:
		for prop in ["texture_albedo", "texture_normal", "texture_orm", "texture_emission"]:
			if _update_node_texture_property(node, prop, psd_path, new_texture):
				count += 1
	elif node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if mat:
				if mat is StandardMaterial3D:
					if _update_standard_material_3d(mat, psd_path, new_img):
						count += 1
				elif mat is ShaderMaterial:
					if _update_shader_material(mat, psd_path, new_img):
						count += 1
	elif node is CSGMesh3D:
		if node.material:
			if node.material is StandardMaterial3D:
				if _update_standard_material_3d(node.material, psd_path, new_img):
					count += 1
	
	if texture_property != "":
		if _update_node_texture_property(node, texture_property, psd_path, new_texture):
			count += 1
	
	for child in node.get_children():
		count += _update_nodes_recursive(child, psd_path, new_img)
	
	if _is_debug_enabled() and count > 0:
		print("  Node '%s' updated %d textures" % [node.name, count])
	
	return count

func _update_node_texture_property(node: Node, property: String, psd_path: String, new_texture: ImageTexture) -> bool:
	var texture = node.get(property)
	if not texture:
		return false
	
	var texture_path = texture.resource_path
	
	if _is_debug_enabled():
		print("  Checking node '%s' property '%s'" % [node.name, property])
		print("    Current texture path: '%s'" % texture_path)
		print("    Looking for psd path: '%s'" % psd_path)
	
	var meta_key = "psd_source_" + property
	if node.has_meta(meta_key):
		if _is_debug_enabled():
			print("    Node already has tag: ", node.get_meta(meta_key))
		if node.get_meta(meta_key) == psd_path:
			node.set(property, new_texture)
			if _is_debug_enabled():
				print("    ✓ Updated from existing tag")
			return true
		return false 
	
	if texture_path == psd_path:
		node.set_meta(meta_key, psd_path)
		node.set(property, new_texture)
		if _is_debug_enabled():
			print("    ✓ Auto-tagged and updated (direct path match)")
		return true
	
	if texture is ImageTexture:
		var img = texture.get_image()
		if img:
			if _is_debug_enabled():
				print("    Image exists, checking metadata...")
				var meta_list = img.get_meta_list()
				print("    Image metadata keys: ", meta_list)
			
			if img.has_meta("psd_source"):
				var source_path = img.get_meta("psd_source")
				if _is_debug_enabled():
					print("    Image has psd_source metadata: ", source_path)
				if source_path == psd_path:
					node.set_meta(meta_key, psd_path)
					node.set(property, new_texture)
					if _is_debug_enabled():
						print("    ✓ Auto-tagged and updated (metadata match)")
					return true
	
	if texture_path.begins_with("res://") and texture_path.contains("::"):
		if _is_debug_enabled():
			print("    Embedded texture detected")
		
		var has_other_source_tag = false
		var all_possible_source_tags = ["kra_source_" + property, "png_source_" + property, "jpg_source_" + property]
		for tag in all_possible_source_tags:
			if node.has_meta(tag):
				has_other_source_tag = true
				if _is_debug_enabled():
					print("    Node already has source tag from another importer: %s = %s" % [tag, node.get_meta(tag)])
				break
		
		if has_other_source_tag:
			return false
		
		var import_path = psd_path + ".import"
		
		if FileAccess.file_exists(import_path):
			var config = ConfigFile.new()
			if config.load(import_path) == OK:
				var imported_resource_path = config.get_value("remap", "path", "")
				
				if imported_resource_path != "":
					var imported_img = ResourceLoader.load(imported_resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
					
					if imported_img and imported_img is Image and texture is ImageTexture:
						var current_img = texture.get_image()
						if current_img:
							if imported_img.get_width() == current_img.get_width() and imported_img.get_height() == current_img.get_height():
								node.set_meta(meta_key, psd_path)
								node.set(property, new_texture)
								if _is_debug_enabled():
									print("    ✓ Auto-tagged and updated (dimension match: %dx%d, no conflicting tags)" % [current_img.get_width(), current_img.get_height()])
								return true
							elif _is_debug_enabled():
								print("    Dimensions don't match: psd=%dx%d vs current=%dx%d" % [
									imported_img.get_width(), imported_img.get_height(),
									current_img.get_width(), current_img.get_height()
								])
	
	return false

func _update_particle_material(material: Material, psd_path: String, new_img: Image) -> bool:
	# ParticleProcessMaterial doesn't have texture properties
	# But custom ShaderMaterial might
	if material is ShaderMaterial:
		return _update_shader_material(material, psd_path, new_img)
	return false

func _update_animated_sprite(node: Node, psd_path: String, new_texture: ImageTexture) -> bool:
	var sprite_frames = node.sprite_frames
	if not sprite_frames:
		return false
	
	var updated = false
	var animations = sprite_frames.get_animation_names()
	
	for anim_name in animations:
		var frame_count = sprite_frames.get_frame_count(anim_name)
		for i in range(frame_count):
			var frame_texture = sprite_frames.get_frame_texture(anim_name, i)
			if frame_texture:
				var meta_key = "psd_source_frame_%s_%d" % [anim_name, i]
				
				if sprite_frames.has_meta(meta_key):
					if sprite_frames.get_meta(meta_key) == psd_path:
						sprite_frames.set_frame(anim_name, i, new_texture)
						updated = true
						if _is_debug_enabled():
							print("    ✓ Updated frame %d in animation '%s'" % [i, anim_name])
				elif frame_texture.resource_path == psd_path:
					sprite_frames.set_meta(meta_key, psd_path)
					sprite_frames.set_frame(anim_name, i, new_texture)
					updated = true
					if _is_debug_enabled():
						print("    ✓ Auto-tagged and updated frame %d in animation '%s'" % [i, anim_name])
				elif frame_texture is ImageTexture:
					var img = frame_texture.get_image()
					if img and img.has_meta("psd_source") and img.get_meta("psd_source") == psd_path:
						sprite_frames.set_meta(meta_key, psd_path)
						sprite_frames.set_frame(anim_name, i, new_texture)
						updated = true
						if _is_debug_enabled():
							print("    ✓ Auto-tagged and updated frame %d in animation '%s' (metadata match)" % [i, anim_name])
	
	return updated


func _get_scan_mode() -> int:
	return ProjectSettings.get_setting("psd_importer/scan_mode", 0)

func _should_scan_materials() -> bool:
	return ProjectSettings.get_setting("psd_importer/scan_materials", false)

func _is_debug_enabled() -> bool:
	return ProjectSettings.get_setting("psd_importer/debug_prints", false)
