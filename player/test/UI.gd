extends CanvasLayer

@export var water: Label
@export var air: Label
@export var player: Player 
@export var debuff_font_size: int = 32
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

# Takedown Shockwave elements
var shockwave_drawer: Control
var active_shockwaves: Array = []

func _ready() -> void:
	add_to_group("player_ui")
	
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]

	# Setup full-screen shockwave drawing canvas
	shockwave_drawer = Control.new()
	shockwave_drawer.name = "ShockwaveDrawer"
	shockwave_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	shockwave_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shockwave_drawer.draw.connect(_draw_shockwaves)
	add_child(shockwave_drawer)

	# Preload fonts
	var subheader_font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
	var body_font = preload("res://scenes/font/iannnnnVCD 2007 Bold.ttf")
			
	# Dynamically instantiate and style the debuff label next to the Air resource label
	debuff_label = Label.new()
	debuff_label.text = ""
	debuff_label.add_theme_font_size_override("font_size", round(debuff_font_size * 0.8))
	debuff_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3)) # Red color for debuff
	debuff_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debuff_label.add_theme_constant_override("outline_size", 5)
	debuff_label.add_theme_font_override("font", body_font)
	
	# Position to the left of the Air label (which is bottom-right anchored)
	debuff_label.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	debuff_label.anchor_left = 1.0
	debuff_label.anchor_top = 1.0
	debuff_label.anchor_right = 1.0
	debuff_label.anchor_bottom = 1.0
	
	# Air offset is: left = -205, top = -85, right = -42, bottom = -28
	# We place debuff_label left of it: left = -420, top = -85, right = -215, bottom = -28
	debuff_label.offset_left = -420 * 0.8
	debuff_label.offset_top = -85 * 0.8
	debuff_label.offset_right = -215 * 0.8
	debuff_label.offset_bottom = -28 * 0.8
	debuff_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	debuff_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	add_child(debuff_label)

	# Shift Player HP label up to prevent overlapping
	hp.offset_left = -205.0 * 0.8
	hp.offset_right = -42.0 * 0.8
	hp.offset_top = -240 * 0.8
	hp.offset_bottom = -183 * 0.8
	hp.add_theme_font_override("font", subheader_font)
	hp.add_theme_font_size_override("font_size", 33)
	hp.add_theme_constant_override("outline_size", 6)

	# Dynamically instantiate Follower HP label
	follower_hp_label = Label.new()
	follower_hp_label.name = "FollowerHP"
	follower_hp_label.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	follower_hp_label.anchor_left = 1.0
	follower_hp_label.anchor_top = 1.0
	follower_hp_label.anchor_right = 1.0
	follower_hp_label.anchor_bottom = 1.0
	follower_hp_label.offset_left = -205.0 * 0.8
	follower_hp_label.offset_top = -185.0 * 0.8
	follower_hp_label.offset_right = -42.0 * 0.8
	follower_hp_label.offset_bottom = -128.0 * 0.8
	follower_hp_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	follower_hp_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	follower_hp_label.add_theme_font_size_override("font_size", 33)
	follower_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	follower_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	follower_hp_label.add_theme_constant_override("outline_size", 6)
	follower_hp_label.add_theme_font_override("font", subheader_font)
	follower_hp_label.visible = false
	add_child(follower_hp_label)

	# Apply fonts to other exported labels
	if water:
		water.add_theme_font_override("font", subheader_font)
		water.add_theme_font_size_override("font_size", 33)
		water.add_theme_constant_override("outline_size", 6)
		water.offset_left = -205.0 * 0.8
		water.offset_right = -42.0 * 0.8
		water.offset_top = -133.0 * 0.8
		water.offset_bottom = -76.0 * 0.8
	if air:
		air.add_theme_font_override("font", subheader_font)
		air.add_theme_font_size_override("font_size", 33)
		air.add_theme_constant_override("outline_size", 6)
		air.offset_left = -205.0 * 0.8
		air.offset_right = -42.0 * 0.8
		air.offset_top = -85.0 * 0.8
		air.offset_bottom = -28.0 * 0.8

	# Dynamically create Kill Count HUD Rect
	kill_rect = TextureRect.new()
	kill_rect.name = "KillCountHUD"
	var kill_tex = preload("res://scenes/Kill_Count_Ui.png")
	kill_rect.texture = kill_tex
	kill_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kill_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var target_height = 160.0
	var kill_size = kill_tex.get_size() * (target_height / kill_tex.get_size().y)
	kill_rect.size = kill_size
	
	# Position at top right
	kill_rect.anchors_preset = Control.PRESET_TOP_RIGHT
	kill_rect.anchor_left = 1.0
	kill_rect.anchor_top = 0.0
	kill_rect.anchor_right = 1.0
	kill_rect.anchor_bottom = 0.0
	kill_rect.offset_left = -kill_size.x - 60
	kill_rect.offset_top = 24
	kill_rect.offset_right = -60
	kill_rect.offset_bottom = 24 + kill_size.y
	kill_rect.pivot_offset = kill_size / 2.0
	add_child(kill_rect)

	# Create Kill Count Label (larger text)
	kill_label = Label.new()
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kill_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	kill_label.add_theme_font_size_override("font_size", 18)
	kill_label.add_theme_font_override("font", subheader_font)
	kill_label.add_theme_color_override("font_outline_color", Color.BLACK)
	kill_label.add_theme_constant_override("outline_size", 4)
	kill_rect.add_child(kill_label)

	# Dynamically create Time Limit HUD Rect (aligned beside kill count)
	time_rect = TextureRect.new()
	time_rect.name = "TimeLimitHUD"
	var time_tex = preload("res://scenes/General_Wide_UI_Box.png")
	time_rect.texture = time_tex
	time_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	time_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var time_size = time_tex.get_size() * (target_height / time_tex.get_size().y) * 0.3
	time_rect.size = time_size
	
	# Position beside Kill Count HUD box (with a 15px gap)
	time_rect.anchors_preset = Control.PRESET_TOP_RIGHT
	time_rect.anchor_left = 1.0
	time_rect.anchor_top = 0.0
	time_rect.anchor_right = 1.0
	time_rect.anchor_bottom = 0.0
	time_rect.offset_right = -kill_size.x - 72
	time_rect.offset_left = -kill_size.x - 72 - time_size.x
	time_rect.offset_top = 64
	time_rect.offset_bottom = 64 + time_size.y
	time_rect.pivot_offset = time_size / 2.0
	add_child(time_rect)

	# Create Time Limit Label (larger text)
	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	time_label.add_theme_font_size_override("font_size", 18)
	time_label.add_theme_font_override("font", subheader_font)
	time_label.add_theme_color_override("font_outline_color", Color.BLACK)
	time_label.add_theme_constant_override("outline_size", 4)
	time_rect.add_child(time_label)

	if not player: return
	
	update_display()
	_update_hp_display()

func _process(delta: float) -> void:
	if not player:
		if owner is Player:
			player = owner as Player
		if not player:
			return
	var should_show_stat_ui = true
	if get_tree().root.has_node("GameManager"):
		should_show_stat_ui = GameManager.show_player_stat_ui and GameManager.show_gameplay_ui
	
	if not should_show_stat_ui or player.HP <= 0:
		self.visible = false
	else:
		self.visible = true
		
	# Update active takedown shockwaves
	if active_shockwaves.size() > 0:
		var i = active_shockwaves.size() - 1
		while i >= 0:
			var sw = active_shockwaves[i]
			sw.radius += delta * 300.0  # Expand the shockwave ring
			sw.alpha -= delta * 2.8     # Fade out the ring
			if sw.alpha <= 0.0:
				active_shockwaves.remove_at(i)
			i -= 1
		if is_instance_valid(shockwave_drawer):
			shockwave_drawer.queue_redraw()
		
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
	var limit = GameManager.kill_limit
	if lang == "th":
		kill_label.text = "กำจัด: %d/%d" % [kills, limit]
	else:
		kill_label.text = "Kills: %d/%d" % [kills, limit]

	# Update Time Limit UI
	var time_elapsed = GameManager.survival_time_elapsed
	var limit_time = GameManager.SURVIVAL_LIMIT
	var time_left = max(0.0, limit_time - time_elapsed)
	var minutes = int(time_left) / 60
	var seconds = int(time_left) % 60
	var time_str = "%02d:%02d" % [minutes, seconds]
	
	if lang == "th":
		time_label.text = "เวลา: " + time_str
	else:
		time_label.text = "TIME: " + time_str

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
	
	# Style the +1 label (25% bigger: 28 * 1.25 = 35)
	proj.add_theme_font_size_override("font_size", 35)
	proj.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5)) # Bright green
	proj.add_theme_color_override("font_outline_color", Color.BLACK)
	proj.add_theme_constant_override("outline_size", 6)
	proj.add_theme_font_override("font", preload("res://scenes/font/iannnnn-DOG-Bold.ttf"))
	
	add_child(proj)
	proj.global_position = screen_pos - Vector2(22, 18)
	proj.scale = Vector2.ZERO
	
	# Target position: center of the kill HUD box
	var target_pos = kill_rect.global_position + kill_rect.size / 2.0 - Vector2(22, 18)
	
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

func spawn_takedown_shockwave(zombie_3d_pos: Vector3, custom_scale: float = 1.0) -> void:
	active_shockwaves.append({
		"pos_3d": zombie_3d_pos,
		"radius": 15.0 * custom_scale,
		"alpha": 1.0,
		"color": Color(1.0, 0.8, 0.1) # Yellow
	})
	if active_shockwaves.size() > 8:
		active_shockwaves.remove_at(0)
	if is_instance_valid(shockwave_drawer):
		shockwave_drawer.queue_redraw()


func spawn_defeat_shockwave(zombie_3d_pos: Vector3) -> void:
	active_shockwaves.append({
		"pos_3d": zombie_3d_pos,
		"radius": 15.0,
		"alpha": 1.0,
		"color": Color(0.2, 0.85, 0.3) # Green
	})
	if active_shockwaves.size() > 8:
		active_shockwaves.remove_at(0)
	if is_instance_valid(shockwave_drawer):
		shockwave_drawer.queue_redraw()

func _draw_shockwaves() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
		
	for sw in active_shockwaves:
		if camera.is_position_behind(sw.pos_3d):
			continue
		var screen_pos = camera.unproject_position(sw.pos_3d)
		
		# Draw a single thick black shadow outline underneath
		shockwave_drawer.draw_arc(screen_pos, sw.radius, 0.0, 2.0 * PI, 24, Color(0, 0, 0, sw.alpha * 0.5), 6.0, true)
		
		# Draw the expanding circle/shockwave on top
		var base_color = sw.get("color", Color(1.0, 0.8, 0.1))
		var ring_color = Color(base_color.r, base_color.g, base_color.b, sw.alpha * 0.95)
		shockwave_drawer.draw_arc(screen_pos, sw.radius, 0.0, 2.0 * PI, 24, ring_color, 4.0, true)
