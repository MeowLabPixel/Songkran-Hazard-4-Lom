extends CanvasLayer

@export var water: Label
@export var air: Label
@export var player: Player 
@onready var hp: Label = $HP

var debuff_label: Label
var last_debuff_text: String = ""

func _ready() -> void:
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
			
	# Dynamically instantiate and style the debuff label next to the Air resource label
	debuff_label = Label.new()
	debuff_label.text = ""
	debuff_label.add_theme_font_size_override("font_size", 24)
	debuff_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3)) # Red color for debuff
	debuff_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debuff_label.add_theme_constant_override("outline_size", 6)
	
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

	if not player: return
	
	update_display()
	hp.text = "HP: " + str(player.HP)

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
			
	if player.HP <=0:
		self.visible = false
	update_display()
	_update_debuff_display()
	hp.text = "HP: " + str(player.HP)

func update_display() -> void:
	if player.gun_controller:
		var current_w = player.gun_controller.current_water
		var max_w = player.gun_controller.max_water
		var current_air = 0.0
		var is_super = false
		
		if player.gun_controller.current_gun:
			current_air = player.gun_controller.current_gun.air
			is_super = player.gun_controller.current_gun.is_super_active
		
		if water:
			water.text = "Water: " + str(int(current_w)) + "/" + str(int(max_w))
		
		if air:
			air.text = "Air: " + str(int(current_air))
			if is_super:
				air.add_theme_color_override("font_color", Color.RED)
			elif player.gun_controller.current_gun and player.gun_controller.current_gun.is_super_ready:
				air.add_theme_color_override("font_color", Color.YELLOW)
			else:
				air.add_theme_color_override("font_color", Color.WHITE)
	else:
		if water:
			water.text = "Ammo: " + str(player.curr_gun.ammo)
		if air:
			air.text = "Air: N/A"

func _update_debuff_display() -> void:
	if not player or not player.gun_controller or not player.gun_controller.current_gun:
		if debuff_label:
			debuff_label.text = ""
		return
		
	var gun = player.gun_controller.current_gun
	var air_pct = gun.air / gun.max_air
	var new_debuff_text = ""
	var label_color = Color(1.0, 0.3, 0.3)
	
	if air_pct <= 0.3:
		new_debuff_text = "-15% dmg"
		label_color = Color(1.0, 0.3, 0.3) # Red for high debuff
	elif air_pct < 0.5:
		new_debuff_text = "-10% dmg"
		label_color = Color(1.0, 0.6, 0.0) # Orange for low debuff
	else:
		new_debuff_text = "+50% focus spd"
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
