extends SceneTree

func _init():
	var scene = load("res://player/test/world.tscn")
	var root = scene.instantiate()
	var player = root.get_node("player")
	var anchalee = root.get_node("Anchalee(Follower)")
	print("Player Layer: ", player.collision_layer)
	print("Player Mask: ", player.collision_mask)
	print("Anchalee Layer: ", anchalee.collision_layer)
	print("Anchalee Mask: ", anchalee.collision_mask)
	for child in player.find_children("*", "CollisionObject3D"):
		print("Player child ", child.name, " Layer: ", child.collision_layer, " Mask: ", child.collision_mask)
	for child in anchalee.find_children("*", "CollisionObject3D"):
		print("Anchalee child ", child.name, " Layer: ", child.collision_layer, " Mask: ", child.collision_mask)
	quit()
