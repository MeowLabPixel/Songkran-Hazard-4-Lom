@tool
extends McpTestSuite

func suite_name() -> String:
	return "merchant_wave2_exit"

func test_merchant_shop_exit_distance_default() -> void:
	var script = ResourceLoader.load("res://scripts/merchant/merchant.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	var merchant = script.new()
	track(merchant)
	
	assert_true(merchant.get("shop_exit_distance") == 2.0, "shop_exit_distance should default to 2.0m")
	assert_false(merchant.get("has_shopped_or_talked"), "has_shopped_or_talked should initially be false")
	assert_false(merchant.get("_shop_exit_triggered"), "_shop_exit_triggered should initially be false")

func test_merchant_exit_logic_flow() -> void:
	var script = ResourceLoader.load("res://scripts/merchant/merchant.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	var merchant = script.new()
	track(merchant)
	
	# Create a mock player node in "player" group
	var player = Node3D.new()
	player.name = "TestPlayer"
	player.add_to_group("player")
	track(player)
	
	# Add to tree so get_nodes_in_group and global_position work
	var tree = (Engine.get_main_loop() as SceneTree)
	tree.root.add_child(merchant)
	tree.root.add_child(player)
	
	# Position merchant at origin, player at 1 meter away
	merchant.global_position = Vector3(0, 0, 0)
	player.global_position = Vector3(1.0, 0, 0)
	
	# 1. Before talking: even if moving away, exit should not trigger
	player.global_position = Vector3(3.0, 0, 0)
	merchant._check_player_shop_physical_exit()
	assert_false(merchant._shop_exit_triggered, "Should not trigger exit if player never talked/shopped")
	
	# 2. Player approaches and opens menu
	player.global_position = Vector3(1.0, 0, 0)
	merchant.has_shopped_or_talked = true
	merchant.is_in_interaction = true
	merchant._check_player_shop_physical_exit()
	assert_false(merchant._shop_exit_triggered, "Should not trigger exit while in interaction / menu is open")
	
	# 3. Player closes menu but stays within 2.0m (e.g. 1.2m)
	merchant.is_in_interaction = false
	player.global_position = Vector3(1.2, 0, 0)
	merchant._check_player_shop_physical_exit()
	assert_false(merchant._shop_exit_triggered, "Should not trigger exit while player is within 2.0m (1.2m)")
	
	# 4. Player walks away past 2.0m (e.g. 2.1m)
	var signal_emitted = false
	merchant.shop_exited.connect(func(): signal_emitted = true)
	player.global_position = Vector3(2.1, 0, 0)
	merchant._check_player_shop_physical_exit()
	
	assert_true(merchant._shop_exit_triggered, "Should trigger exit once player is >= 2.0m away")
	assert_true(signal_emitted, "shop_exited signal must be emitted")
	
	# Cleanup tree children
	tree.root.remove_child(merchant)
	tree.root.remove_child(player)

func test_spawner_wait_for_shop_exit_guard() -> void:
	var spawner_script = ResourceLoader.load("res://scripts/enemy/enemy_spawner.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	var spawner = spawner_script.new()
	track(spawner)
	
	spawner.wait_for_shop_exit = true
	spawner.trigger_type = spawner.TriggerType.AFTER_SHOP_EXIT
	
	# Initially _shop_has_exited is false
	assert_false(spawner.get("_shop_has_exited"), "Spawner _shop_has_exited should initially be false")
	
	# Call check spawning conditions - should NOT spawn if shop has not exited
	spawner.is_spawning = false
	spawner._check_spawning_conditions()
	assert_false(spawner.is_spawning, "Spawner must not start spawning before shop exit")
	
	# Simulate shop exit signal received
	spawner._on_merchant_shop_exited()
	assert_true(spawner.get("_shop_has_exited"), "Spawner _shop_has_exited should be true after receiving signal")
