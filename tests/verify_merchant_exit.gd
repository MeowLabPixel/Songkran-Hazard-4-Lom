extends SceneTree

func _init() -> void:
	var out: Array[String] = []
	out.append("\n================== RUNNING VERIFICATION TEST ==================")
	var total_tests = 0
	var passed_tests = 0

	# -------------------------------------------------------------
	# Test 1: Default properties
	# -------------------------------------------------------------
	total_tests += 1
	var MerchantScript = load("res://scripts/merchant/merchant.gd")
	var merchant = MerchantScript.new()
	
	if merchant.shop_exit_distance == 2.0 and not merchant.has_shopped_or_talked and not merchant._shop_exit_triggered:
		out.append("[PASS] Test 1: Merchant default exit distance is 2.0m and flags are initialized false.")
		passed_tests += 1
	else:
		out.append("[FAIL] Test 1: Merchant default values incorrect! distance=%s, has_shopped=%s" % [merchant.shop_exit_distance, merchant.has_shopped_or_talked])

	# -------------------------------------------------------------
	# Test 2: Exit logic with mock player
	# -------------------------------------------------------------
	var player = Node3D.new()
	player.name = "MockPlayer"
	player.add_to_group("player")
	
	root.add_child(merchant)
	root.add_child(player)

	merchant.global_position = Vector3.ZERO
	player.global_position = Vector3(1.0, 0, 0) # 1 meter away

	# Scenario A: Walk away BEFORE shopping/talking
	player.global_position = Vector3(3.0, 0, 0)
	merchant._check_player_shop_physical_exit()
	total_tests += 1
	if not merchant._shop_exit_triggered:
		out.append("[PASS] Test 2A: Moving away before shopping does NOT trigger exit.")
		passed_tests += 1
	else:
		out.append("[FAIL] Test 2A: Exit triggered prematurely before shopping!")

	# Scenario B: Player enters shop and interacts/shops
	player.global_position = Vector3(1.0, 0, 0)
	merchant.has_shopped_or_talked = true
	merchant.is_in_interaction = true
	merchant._check_player_shop_physical_exit()
	total_tests += 1
	if not merchant._shop_exit_triggered:
		out.append("[PASS] Test 2B: While menu is open / talking, exit does NOT trigger.")
		passed_tests += 1
	else:
		out.append("[FAIL] Test 2B: Exit triggered while player was talking/shopping!")

	# Scenario C: Player closes menu, but remains standing in the shop (< 2.0m away)
	merchant.is_in_interaction = false
	player.global_position = Vector3(1.2, 0, 0) # 1.2m away
	merchant._check_player_shop_physical_exit()
	total_tests += 1
	if not merchant._shop_exit_triggered:
		out.append("[PASS] Test 2C: Closing menu while standing at counter (1.2m < 2.0m) does NOT trigger exit.")
		passed_tests += 1
	else:
		out.append("[FAIL] Test 2C: Exit triggered while player was still at the shop counter!")

	# Scenario D: Player walks >= 2.0m away
	var exit_signal_received = false
	merchant.shop_exited.connect(func(): exit_signal_received = true)
	player.global_position = Vector3(2.1, 0, 0) # 2.1m away
	merchant._check_player_shop_physical_exit()
	total_tests += 1
	if merchant._shop_exit_triggered and exit_signal_received:
		out.append("[PASS] Test 2D: Walking 2.1m (>= 2.0m) triggers shop exit and emits shop_exited signal.")
		passed_tests += 1
	else:
		out.append("[FAIL] Test 2D: Shop exit did not trigger at 2.1m! triggered=%s, signal=%s" % [merchant._shop_exit_triggered, exit_signal_received])

	# -------------------------------------------------------------
	# Test 3: Spawner wait_for_shop_exit guard
	# -------------------------------------------------------------
	var SpawnerScript = load("res://scripts/enemy/enemy_spawner.gd")
	var spawner = SpawnerScript.new()
	spawner.wait_for_shop_exit = true
	spawner.trigger_type = spawner.TriggerType.AFTER_SHOP_EXIT
	root.add_child(spawner)

	total_tests += 1
	if not spawner.get("_shop_has_exited"):
		out.append("[PASS] Test 3A: Spawner initially has _shop_has_exited = false.")
		passed_tests += 1
	else:
		out.append("[FAIL] Test 3A: Spawner _shop_has_exited is unexpectedly true!")

	# Check spawning conditions
	spawner.is_spawning = false
	spawner._check_spawning_conditions()
	total_tests += 1
	if not spawner.is_spawning:
		out.append("[PASS] Test 3B: Spawner does not spawn before shop exit.")
		passed_tests += 1
	else:
		out.append("[FAIL] Test 3B: Spawner spawned before shop exit!")

	# Simulate signal received
	spawner._on_merchant_shop_exited()
	total_tests += 1
	if spawner.get("_shop_has_exited"):
		out.append("[PASS] Test 3C: Spawner marks _shop_has_exited = true on shop exit signal.")
		passed_tests += 1
	else:
		out.append("[FAIL] Test 3C: Spawner did not record shop exit!")

	out.append("================================================================")
	out.append("RESULTS: %d / %d tests passed." % [passed_tests, total_tests])
	out.append("================================================================\n")

	var fa = FileAccess.open("res://tests/test_results.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(out))
		fa.close()

	merchant.queue_free()
	player.queue_free()
	spawner.queue_free()

	quit(0 if passed_tests == total_tests else 1)
