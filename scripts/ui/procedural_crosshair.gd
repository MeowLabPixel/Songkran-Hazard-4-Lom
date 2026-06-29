extends Control

@export_group("Reticle Settings")
@export var min_reticle_radius: float = 10.0
@export var max_reticle_radius: float = 45.0
@export var reticle_line_length: float = 12.0
@export var reticle_line_thickness: float = 2.0
@export var reticle_outline_thickness: float = 4.0
@export var center_dot_radius: float = 2.0
@export var center_dot_outline: float = 3.5
@export var default_color: Color = Color(1.0, 1.0, 1.0, 0.75)
@export var focused_color: Color = Color(1.0, 0.8, 0.1, 0.95)

@export_group("Air Gauge Settings")
@export var gauge_on_left: bool = true
@export var gauge_offset_radius: float = 20.0 # visual_r + gauge_offset_radius (Makes the arc UI bigger)
@export var gauge_thickness: float = 3.0
@export var gauge_outline_thickness: float = 5.0
@export var gauge_cyan_color: Color = Color(0.2, 0.8, 1.0, 0.85)
@export var gauge_orange_color: Color = Color(1.0, 0.6, 0.0, 0.85)
@export var gauge_red_color: Color = Color(1.0, 0.2, 0.2, 0.95)

@export_group("Smoothness Settings")
@export var shrink_speed: float = 15.0
@export var expand_speed: float = 8.0

var player: Node = null

# Dynamic visual state
var visual_r: float = 45.0
var was_visible: bool = false

func _ready() -> void:
	print("ProceduralCrosshair: _ready called")
	scale = Vector2.ONE
	visual_r = max_reticle_radius

func get_player() -> Node:
	if player and is_instance_valid(player):
		return player
		
	# 1. Try walking up parent chain to find the Player node
	var node = self
	while node:
		if node.has_method("get_damage_multiplier") or node.name == "Player":
			player = node
			print("ProceduralCrosshair: found player via parent chain walk: ", player)
			return player
		node = node.get_parent()
		
	# 2. Group fallback
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		print("ProceduralCrosshair: found player via group fallback: ", player)
		return player
		
	print("ProceduralCrosshair: player node not found!")
	return null

func _process(delta: float) -> void:
	if visible:
		if not was_visible:
			print("ProceduralCrosshair: became visible, visual_r initialized to ", max_reticle_radius)
			# Snap to raw unfocused size and reset scale when aiming starts
			visual_r = max_reticle_radius
			scale = Vector2.ONE
			was_visible = true
			
		var p = get_player()
		if p:
			var focus_prog: float = p.get("focus_progress") if "focus_progress" in p else 0.0
			var target_r = lerp(max_reticle_radius, min_reticle_radius, focus_prog)
			
			# Gradually lerp the visual radius smoothly
			var lerp_speed = shrink_speed if target_r < visual_r else expand_speed
			visual_r = lerpf(visual_r, target_r, delta * lerp_speed)
			
		queue_redraw()
	else:
		if was_visible:
			print("ProceduralCrosshair: became hidden")
		was_visible = false

func _draw() -> void:
	var p = get_player()
	if p == null:
		return

	var focus_prog: float = p.get("focus_progress") if "focus_progress" in p else 0.0
	
	# Determine color based on focus progress
	var line_color = default_color
	if focus_prog >= 1.0:
		line_color = focused_color
		
	var center = size / 2.0
	
	# Draw reticle lines
	# Top
	draw_reticle_line(center + Vector2(0, -visual_r - reticle_line_length), center + Vector2(0, -visual_r), line_color)
	# Bottom
	draw_reticle_line(center + Vector2(0, visual_r), center + Vector2(0, visual_r + reticle_line_length), line_color)
	# Left
	draw_reticle_line(center + Vector2(-visual_r - reticle_line_length, 0), center + Vector2(-visual_r, 0), line_color)
	# Right
	draw_reticle_line(center + Vector2(visual_r, 0), center + Vector2(visual_r + reticle_line_length, 0), line_color)
	
	# Draw center dot
	draw_circle(center, center_dot_outline, Color(0, 0, 0, 0.8))
	draw_circle(center, center_dot_radius, line_color)
	
	# Draw Zelda-style 1/4 circular air gauge outline (Scales dynamically with visual_r!)
	var current_gauge_radius = visual_r + gauge_offset_radius
	
	var air_pct = 1.0
	if p.gun_controller and p.gun_controller.current_gun:
		var gun = p.gun_controller.current_gun
		air_pct = gun.air / gun.max_air
		
	# Calculate start and end angles for 1/4 circle (90 degrees)
	var bg_start_angle = 3.0 * PI / 4.0 if gauge_on_left else -PI / 4.0
	var bg_end_angle = 5.0 * PI / 4.0 if gauge_on_left else PI / 4.0
	var arc_length = PI / 2.0
	
	var fg_start_angle = bg_start_angle
	var fg_end_angle = fg_start_angle + (air_pct * arc_length)
	
	var gauge_color = gauge_cyan_color
	if air_pct < 0.3:
		gauge_color = gauge_red_color
	elif air_pct < 0.5:
		gauge_color = gauge_orange_color
		
	# Background 1/4 arc outline
	draw_arc(center, current_gauge_radius, bg_start_angle, bg_end_angle, 32, Color(0, 0, 0, 0.3), gauge_outline_thickness, true)
	draw_arc(center, current_gauge_radius, bg_start_angle, bg_end_angle, 32, Color(0.2, 0.2, 0.2, 0.6), gauge_thickness, true)
	
	# Foreground 1/4 arc fill
	draw_arc(center, current_gauge_radius, fg_start_angle, fg_end_angle, 32, Color(0, 0, 0, 0.6), gauge_outline_thickness, true)
	draw_arc(center, current_gauge_radius, fg_start_angle, fg_end_angle, 32, gauge_color, gauge_thickness, true)

func draw_reticle_line(from: Vector2, to: Vector2, color: Color) -> void:
	# Draw thick outline
	draw_line(from, to, Color(0, 0, 0, 0.8), reticle_outline_thickness)
	# Draw main inner core
	draw_line(from, to, color, reticle_line_thickness)
