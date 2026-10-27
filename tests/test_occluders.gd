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
					assert_true(quad.size.x <= 8.2, "BackWallOccluder width must be reduced by 15% (<= 8.2m even for wide buildings)")
			elif o.name == "LeftPartyWallOccluder" or o.name == "RightPartyWallOccluder":
				var party_quad = (o as OccluderInstance3D).occluder as QuadOccluder3D
				if party_quad != null:
					assert_true(party_quad.size.x > 0.0 and party_quad.size.y > 0.0, "PartyWallOccluder size must be positive")
		assert_true(has_back, "Building %s must have a BackWallOccluder" % b.name)
		checked_buildings += 1
	
	assert_true(checked_buildings > 0, "At least one building should be verified")

func test_near_occluder_deactivation() -> void:
	var script = ResourceLoader.load("res://scripts/pcg/building_path_pcg.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	var pcg = script.new()
	track(pcg)
	
	var c = Curve3D.new()
	c.add_point(Vector3(0, 0, 0))
	c.add_point(Vector3(0, 0, 50))
	pcg.curve = c
	pcg.generate_occluders = true
	pcg.disable_near_camera_occluders = true
	pcg.near_occluder_disable_distance = 10.0
	
	pcg.generate()
	
	var container = pcg.get_node_or_null("GeneratedBuildings")
	assert_true(container != null, "GeneratedBuildings container must exist")
	if container == null:
		return
	
	var buildings = container.get_children()
	assert_true(not buildings.is_empty(), "Buildings should exist")
	
	var first_building = buildings[0] as Node3D
	var occ_group = first_building.get_node_or_null("Occluders")
	assert_true(occ_group != null, "First building must have Occluders group")
	
	var first_occ = occ_group.get_node_or_null("BackWallOccluder") as OccluderInstance3D
	assert_true(first_occ != null, "BackWallOccluder must exist")
	assert_true(first_occ.visible, "Occluder should start active")
	
	# Test restore all
	pcg._restore_all_occluders()
	assert_true(first_occ.visible, "Occluder must be visible after restore_all")

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
				assert_eq(mi.extra_cull_margin, 3.5, "MeshInstance3D must have default extra_cull_margin set to 3.5")
				checked_meshes += 1
	
	assert_true(checked_meshes > 0, "At least one MeshInstance3D should be verified")
	
	# Test live update without regeneration
	pcg.fade_max_distance = 85.0
	pcg.fade_transition_margin = 15.0
	pcg.extra_cull_margin = 5.0
	for b in buildings:
		if not (b is Node3D):
			continue
		var meshes = (b as Node3D).find_children("*", "MeshInstance3D", true, false)
		for m in meshes:
			var mi = m as MeshInstance3D
			if mi:
				assert_eq(mi.visibility_range_end, 85.0, "Live update must adjust visibility_range_end")
				assert_eq(mi.visibility_range_end_margin, 15.0, "Live update must adjust visibility_range_end_margin")
				assert_eq(mi.extra_cull_margin, 5.0, "Live update must adjust extra_cull_margin")

