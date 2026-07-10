extends CanvasLayer

@export var water: Label
@export var air: Label
@export var player: Player 
@onready var hp: Label = $HP

var debuff_label: Label
var last_debuff_text: String = ""

# Follower HP label
var follower_hp_label: Label

# Kill Count HUD elements
var kill_rect: TextureRect
var kill_label: Label

# Time Limit HUD elements
var time_rect: TextureRect
var time_label: Label

func _ready() -> void:
	add_to_group("player_ui")
	
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]

	# Preload fonts
	var subheader_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
	var body_font = preload("res://scenes/font/iannnnnVCD 2007 Bold.ttf")
			
	# Dynamically instantiate and style the debuff label next to the Air resource label
	debuff_label = Label.new()
	debuff_label.text = ""
	debuff_label.add_theme_font_size_override("font_size", 24)
	debuff_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3)) # Red color for debuff
	debuff_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debuff_label.add_theme_constant_override("outline_size", 6)
	debuff_label.add_theme_font_override("font", body_font)
	
	# Position to the left of the Air label (which is bottom-right anchored)
	debuff_label.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	debuff_label.anchor_left = 1.0
	debuff_label.anchor_top = 1.0
	debuff_label.anchor_right = 1.0
	debuff_label.anchor_bottom = 1.0
	
	# Air offset is: left = -205, top = -85, right = -42, bottom = -28
	# We place debuff_label left of it: left = -420, top = -85, right = -215, bottom = -28
	debuff_label.offset_left = -420
	debuff_label.offset_top = -85
	debuff_label.offset_right = -215
	debuff_label.offset_bottom = -28
	debuff_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	debuff_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	add_child(debuff_label)

	# Shift Player HP label up to prevent overlapping
	hp.offset_top = -240
	hp.offset_bottom = -183
	hp.add_theme_font_override("font", subheader_font)

	# Dynamically instantiate Follower HP label
	follower_hp_label = Label.new()
	follower_hp_label.name = "FollowerHP"
	follower_hp_label.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	follower_hp_label.anchor_left = 1.0
	follower_hp_label.anchor_top = 1.0
	follower_hp_label.anchor_right = 1.0
	follower_hp_label.anchor_bottom = 1.0
	follower_hp_label.offset_left = -205.0
	follower_hp_label.offset_top = -185.0
	follower_hp_label.offset_right = -42.0
	follower_hp_label.offset_bottom = -128.0
	follower_hp_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	follower_hp_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	follower_hp_label.add_theme_font_size_override("font_size", 41)
	follower_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	follower_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	follower_hp_label.add_theme_constant_override("outline_size", 8)
	follower_hp_label.add_theme_font_override("font", subheader_font)
	follower_hp_label.visible = false
	add_child(follower_hp_label)

	# Apply fonts to other exported labels
	if water:
		water.add_theme_font_override("font", subheader_font)
	if air:
		air.add_theme_font_override("font", subheader_font)

	# Dynamically create Kill Count HUD Rect
	kill_rect = TextureRect.new()
	kill_rect.name = "KillCountHUD"
	var kill_tex = preload("res://scenes/Kill_Count_Ui.png")
	kill_rect.texture = kill_tex
	kill_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	var kill_size = kill_tex.get_size()
	kill_rect.size = kill_size
	
	# Position at top right
	kill_rect.anchors_preset = Control.PRESET_TOP_RIGHT
	kill_rect.anchor_left = 1.0
	kill_rect.anchor_top = 0.0
	kill_rect.anchor_right = 1.0
	kill_rect.anchor_bottom = 0.0
	kill_rect.offset_left = -kill_size.x - 30
	kill_rect.offset_top = 30
	kill_rect.offset_right = -30
	kill_rect.offset_bottom = 30 + kill_size.y
	kill_rect.pivot_offset = kill_size / 2.0
	add_child(kill_rect)

	# Create Kill Count Label
	kill_label = Label.new()
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kill_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	kill_label.add_theme_font_size_override("font_size", 24)
	kill_label.add_theme_font_override("font", subheader_font)
	kill_label.add_theme_color_override("font_outline_color", Color.BLACK)
	kill_label.add_theme_constant_override("outline_size", 6)
	kill_rect.add_child(kill_label)

	# Dynamically create Time Limit HUD Rect
	time_rect = TextureRect.new()
	time_rect.name = "TimeLimitHUD"
	var time_tex = preload("res://scenes/General_Wide_UI_Box.png")
	time_rect.texture = time_tex
	time_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	var time_size = time_tex.get_size()
	time_rect.size = time_size
	
	# Position at top center
	time_rect.anchors_preset = Control.PRESET_CENTER_TOP
	time_rect.anchor_left = 0.5
	time_rect.anchor_top = 0.0
	time_rect.anchor_right = 0.5
	time_rect.anchor_bottom = 0.0
	time_rect.offset_left = -time_size.x / 2.0
	time_rect.offset_top = 30
	time_rect.offset_right = time_size.x / 2.0
	time_rect.offset_bottom = 30 + time_size.y
	time_rect.pivot_offset = time_size / 2.0
	add_child(time_rect)

	# Create Time Limit Label
	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	time_label.add_theme_font_size_override("font_size", 24)
	time_label.add_theme_font_override("font", subheader_font)
	time_label.add_theme_color_override("font_outline_color", Color.BLACK)
	time_label.add_theme_constant_override("outline_size", 6)
	time_rect.add_child(time_label)

	if not player: return
	
	update_display()
	_update_hp_display()

func _process(_delta: float) -> void:
	if not player:
		if owner is Player:
			player = owner as Player
		else:
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0:
				player = players[0]
		if not player:
			return
			
	if player.HP <= 0:
		self.visible = false
		
	update_display()
	_update_debuff_display()
	_update_hp_display()
	_update_hud_counters()

func _update_hp_display() -> void:
	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language

	hp.text = ("HP: " if lang == "en" else "HP ผู้เล่น: ") + str(player.HP)

	# Update Follower HP
	var follower = get_tree().get_first_node_in_group("Anchalee")
	if follower and is_instance_valid(follower) and not follower.is_dead:
		follower_hp_label.visible = true
		if lang == "th":
			follower_hp_label.text = "HP ผู้ช่วย: " + str(follower.health)
		else:
			follower_hp_label.text = "Follower HP: " + str(follower.health)
	else:
		follower_hp_label.visible = false

func _update_hud_counters() -> void:
	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language
		
	# Update Kill Count Box
	var kills = GameManager.kill_count
	var limit = GameManager.KILL_LIMIT
	if lang == "th":
		kill_label.text = "กำจัด: %d / %d" % [kills, limit]
	else:
		kill_label.text = "Kills: %d / %d" % [kills, limit]

	# Update Time Limit UI
	var time_elapsed = GameManager.survival_time_elapsed
	var limit_time = GameManager.SURVIVAL_LIMIT
	var time_left = max(0.0, limit_time - time_elapsed)
	var minutes = int(time_left) / 60
	var seconds = int(time_left) % 60
	var time_str = "%02d:%02d" % [minutes, seconds]
	
	if lang == "th":
		time_label.text = "เวลาที่เหลือ: " + time_str
	else:
		time_label.text = "TIME LEFT: " + time_str

func spawn_kill_projectile(zombie_3d_pos: Vector3) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	if camera.is_position_behind(zombie_3d_pos):
		return
		
	var screen_pos = camera.unproject_position(zombie_3d_pos)
	
	# Create a floating +1 label
	var proj = Label.new()
	proj.text = "+1"
	proj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	proj.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Style the +1 label
	proj.add_theme_font_size_override("font_size", 38)
	proj.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5)) # Bright green
	proj.add_theme_color_override("font_outline_color", Color.BLACK)
	proj.add_theme_constant_override("outline_size", 8)
	proj.add_theme_font_override("font", preload("res://scenes/font/iannnnn-DOG-Bold.ttf"))
	
	add_child(proj)
	proj.global_position = screen_pos - Vector2(25, 20)
	proj.scale = Vector2.ZERO
	
	# Target position: center of the kill HUD box
	var target_pos = kill_rect.global_position + kill_rect.size / 2.0 - Vector2(25, 20)
	
	# Tween: pop in, fly to target, fade out
	var tween = create_tween().set_parallel(true)
	tween.tween_property(proj, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	var fly_tween = create_tween()
	fly_tween.tween_interval(0.25)
	fly_tween.tween_property(proj, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	fly_tween.finished.connect(func():
		proj.queue_free()
		# Bounce the kill box!
		var bounce_tween = create_tween()
		bounce_tween.tween_property(kill_rect, "scale", Vector2(1.2, 1.2), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bounce_tween.tween_property(kill_rect, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	)

func update_display() -> void:
	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language

	if player.gun_controller:
		var current_w = player.gun_controller.current_water
		var max_w = player.gun_controller.max_water
		var current_air = 0.0
		var is_super = false
		
		if player.gun_controller.current_gun:
			current_air = player.gun_controller.current_gun.air
			is_super = player.gun_controller.current_gun.is_super_active
		
		if water:
			var water_label_prefix = "Water: " if lang == "en" else "น้ำ: "
			water.text = water_label_prefix + str(int(current_w)) + "/" + str(int(max_w))
		
		if air:
			var air_label_prefix = "Air: " if lang == "en" else "ลม: "
			air.text = air_label_prefix + str(int(current_air))
			if is_super:
				air.add_theme_color_override("font_color", Color.RED)
			elif player.gun_controller.current_gun and player.gun_controller.current_gun.is_super_ready:
				air.add_theme_color_override("font_color", Color.YELLOW)
			else:
				air.add_theme_color_override("font_color", Color.WHITE)
	else:
		if water:
			var ammo_label_prefix = "Ammo: " if lang == "en" else "กระสุน: "
			water.text = ammo_label_prefix + str(player.curr_gun.ammo)
		if air:
			var air_label_prefix = "Air: " if lang == "en" else "ลม: "
			air.text = air_label_prefix + "N/A"

func _update_debuff_display() -> void:
	if not player or not player.gun_controller or not player.gun_controller.current_gun:
		if debuff_label:
			debuff_label.text = ""
		return
		
	var gun = player.gun_controller.current_gun
	var air_pct = gun.air / gun.max_air
	var new_debuff_text = ""
	var label_color = Color(1.0, 0.3, 0.3)
	
	var lang = "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language

	if air_pct <= 0.3:
		new_debuff_text = "-15% dmg" if lang == "en" else "-15% พลังโจมตี"
		label_color = Color(1.0, 0.3, 0.3) # Red for high debuff
	elif air_pct < 0.5:
		new_debuff_text = "-10% dmg" if lang == "en" else "-10% พลังโจมตี"
		label_color = Color(1.0, 0.6, 0.0) # Orange for low debuff
	else:
		new_debuff_text = "+50% focus spd" if lang == "en" else "+50% ความเร็วโฟกัส"
		label_color = Color(0.2, 0.9, 0.5) # Bright green for buff
		
	if new_debuff_text != last_debuff_text:
		last_debuff_text = new_debuff_text
		debuff_label.text = new_debuff_text
		debuff_label.add_theme_color_override("font_color", label_color)
		
		if new_debuff_text != "":
			# Pop animation!
			debuff_label.pivot_offset = debuff_label.get_minimum_size() / 2.0
			debuff_label.scale = Vector2.ZERO
			debuff_label.modulate.a = 0.0
			
			var tween = create_tween().set_parallel(true)
			tween.tween_property(debuff_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(debuff_label, "modulate:a", 1.0, 0.15)
		else:
			# Fade out
			var tween = create_tween()
			tween.tween_property(debuff_label, "modulate:a", 0.0, 0.2)
