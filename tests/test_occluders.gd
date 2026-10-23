@tool
extends McpTestSuite

func suite_name() -> String:
	return "pcg_occluders"

func test_occluder_generation() -> void:
	var script = ResourceLoader.load("res://scripts/pcg/building_path_pcg.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	var pcg = script.new()
	track(pcg)
	
	var c = Curve3D.new()
	c.add_point(Vector3(0, 0, 0))
	c.add_point(Vector3(0, 0, 50))
	pcg.curve = c
	pcg.generate_occluders = true
	pcg.occlude_back_wall = true
	pcg.occlude_party_walls = true
	
	# Run generate
	pcg.generate()
	
	var container = pcg.get_node_or_null("GeneratedBuildings")
	assert_true(container != null, "GeneratedBuildings container must exist")
	if container == null:
		return
	
	var buildings = container.get_children()
	assert_true(not buildings.is_empty(), "Buildings should be generated along the path")
	
	var checked_buildings: int = 0
	for b in buildings:
		if not (b is Node3D):
			continue
		var occ_group = b.get_node_or_null("Occluders")
		assert_true(occ_group != null, "Each building must have an Occluders node")
		if occ_group == null:
			continue
		
		var occs = occ_group.get_children()
		assert_true(occs.size() >= 1, "Each building must have at least 1 occluder")
		
		var has_back = false
		for o in occs:
			if o.name == "BackWallOccluder":
				has_back = true
				var quad = (o as OccluderInstance3D).occluder as QuadOccluder3D
				assert_true(quad != null, "BackWallOccluder must have a QuadOccluder3D")
				if quad != null:
					assert_true(quad.size.x > 0.0 and quad.size.y > 0.0, "QuadOccluder size must be positive")
		assert_true(has_back, "Building %s must have a BackWallOccluder" % b.name)
		checked_buildings += 1
	
	assert_true(checked_buildings > 0, "At least one building should be verified")

func test_distance_dither_fade() -> void:
	var script = ResourceLoader.load("res://scripts/pcg/building_path_pcg.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	var pcg = script.new()
	track(pcg)
	
	var c = Curve3D.new()
	c.add_point(Vector3(0, 0, 0))
	c.add_point(Vector3(0, 0, 50))
	pcg.curve = c
	pcg.enable_distance_fade = true
	pcg.fade_max_distance = 110.0
	pcg.fade_transition_margin = 20.0
	pcg.fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	
	pcg.generate()
	
	var container = pcg.get_node_or_null("GeneratedBuildings")
	assert_true(container != null, "GeneratedBuildings container must exist")
	if container == null:
		return
	
	var buildings = container.get_children()
	assert_true(not buildings.is_empty(), "Buildings should be generated along the path")
	
	var checked_meshes: int = 0
	for b in buildings:
		if not (b is Node3D):
			continue
		var meshes = (b as Node3D).find_children("*", "MeshInstance3D", true, false)
		for m in meshes:
			var mi = m as MeshInstance3D
			if mi:
				assert_eq(mi.visibility_range_end, 110.0, "MeshInstance3D must have visibility_range_end set")
				assert_eq(mi.visibility_range_end_margin, 20.0, "MeshInstance3D must have visibility_range_end_margin set")
				assert_eq(mi.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF, "Fade mode must be VISIBILITY_RANGE_FADE_SELF")
				checked_meshes += 1
	
	assert_true(checked_meshes > 0, "At least one MeshInstance3D should be verified")
	
	# Test live update without regeneration
	pcg.fade_max_distance = 85.0
	pcg.fade_transition_margin = 15.0
	for b in buildings:
		if not (b is Node3D):
			continue
		var meshes = (b as Node3D).find_children("*", "MeshInstance3D", true, false)
		for m in meshes:
			var mi = m as MeshInstance3D
			if mi:
				assert_eq(mi.visibility_range_end, 85.0, "Live update must adjust visibility_range_end")
				assert_eq(mi.visibility_range_end_margin, 15.0, "Live update must adjust visibility_range_end_margin")

