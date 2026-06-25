extends CanvasLayer

@export var water: Label
@export var air: Label
@export var player: Player 
@onready var hp: Label = $HP

func _ready() -> void:
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
			
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
		# Fallback to old system if gun_controller is missing
		if water:
			water.text = "Ammo: " + str(player.curr_gun.ammo)
		if air:
			air.text = "Air: N/A"
