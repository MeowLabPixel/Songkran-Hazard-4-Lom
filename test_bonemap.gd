extends SceneTree
func _init():
	var profile = SkeletonProfileHumanoid.new()
	var map = BoneMap.new()
	map.profile = profile
	map.set_skeleton_bone_name("Hips", "ORG-pelvis")
	ResourceSaver.save(map, "test_bonemap.tres")
	quit()
