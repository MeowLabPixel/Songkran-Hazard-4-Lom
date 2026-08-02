extends Control

@export_group("Reticle Settings")
@export var min_reticle_radius: float = 7.5
@export var max_reticle_radius: float = 33.75
@export var reticle_line_length: float = 9.0
@export var reticle_line_thickness: float = 2.0
@export var reticle_outline_thickness: float = 4.0
@export var center_dot_radius: float = 1.5
@export var center_dot_outline: float = 2.625
@export var default_color: Color = Color(1.0, 1.0, 1.0, 0.75)
@export var focused_color: Color = Color(1.0, 0.8, 0.1, 0.95)

@export_group("Air Gauge Settings")
@export var gauge_on_left: bool = true
@export var gauge_offset_radius: float = 15.0 # visual_r + gauge_offset_radius (Makes the arc UI bigger)
@export var gauge_thickness: float = 3.0
@export var gauge_outline_thickness: float = 5.0
@export var gauge_cyan_color: Color = Color(0.2, 0.8, 1.0, 0.85)
@export var gauge_orange_color: Color = Color(1.0, 0.6, 0.0, 0.85)
@export var gauge_red_color: Color = Color(1.0, 0.2, 0.2, 0.95)

@export_group("Smoothness Settings")
@export var shrink_speed: float = 15.0
@export var expand_speed: float = 8.0

@export_group("Procedural Sway & Recoil Settings")
@export var enable_crosshair_sway: bool = true
@export var enable_crosshair_recoil: bool = true
@export var crosshair_sway_amount: float = 2.5
@export var crosshair_sway_move_mult: float = 2.5
@export var crosshair_shot_kick_upward: float = 12.0
@export var crosshair_shot_recoil_duration: float = 0.5
@export var crosshair_shot_recoil_recovery_speed: float = 4.5

var player: Node = null

# Dynamic visual state
var visual_r: float = 33.75
var was_visible: bool = false
var pop_scale: float = 1.0
var was_fully_focused: bool = false

# Procedural Sway & Shot Recoil
var sway_offset: Vector2 = Vector2.ZERO
var target_mouse_sway: Vector2 = Vector2.ZERO
var crosshair_shot_offset: Vector2 = Vector2.ZERO
var shot_recoil_timer: float = 0.0
var mouse_still_timer: float = 0.0

func _ready() -> void:
	add_to_group("crosshair")
	scale = Vector2.ONE
	visual_r = max_reticle_radius
	pop_scale = 1.0
	was_fully_focused = false
	sway_offset = Vector2.ZERO
	target_mouse_sway = Vector2.ZERO
	crosshair_shot_offset = Vector2.ZERO
	shot_recoil_timer = 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.relative.length_squared() > 1.0:
			mouse_still_timer = 0.0

func trigger_shot_kick(amount: float = 9.0) -> void:
	var gm = get_tree().root.get_node_or_null("GameManager") if get_tree() and get_tree().root.has_node("GameManager") else null
	var is_recoil_enabled = enable_crosshair_recoil and (not gm or not ("enable_crosshair_recoil" in gm) or gm.enable_crosshair_recoil)
	
	if is_recoil_enabled:
		visual_r = minf(visual_r + amount, max_reticle_radius * 1.6)
		crosshair_shot_offset += Vector2(randf_range(-crosshair_shot_kick_upward * 0.5, crosshair_shot_kick_upward * 0.5), -crosshair_shot_kick_upward)
		shot_recoil_timer = crosshair_shot_recoil_duration

func get_player() -> Node:
	if player and is_instance_valid(player):
		return player
		
	# 1. Try walking up parent chain to find the Player node
	var node = self
	while node:
		if node.has_method("get_damage_multiplier") or node.name == "Player":
			player = node
			return player
		node = node.get_parent()
		
	# 2. Group fallback
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		return player
		
	return null

func _process(delta: float) -> void:
	if visible:
		if not was_visible:
			visual_r = max_reticle_radius
			scale = Vector2.ONE
			pop_scale = 1.0
			was_fully_focused = false
			was_visible = true
			sway_offset = Vector2.ZERO
			target_mouse_sway = Vector2.ZERO
			
		var p = get_player()
		if p:
			var focus_prog: float = p.get("focus_progress") if "focus_progress" in p else 0.0
			var target_r = lerp(max_reticle_radius, min_reticle_radius, focus_prog)
			
			var lerp_speed = shrink_speed if target_r < visual_r else expand_speed
			visual_r = lerpf(visual_r, target_r, delta * lerp_speed)
			
			# Trigger focus pop when progress hits 100%
			if focus_prog >= 1.0:
				if not was_fully_focused:
					pop_scale = 1.5
					was_fully_focused = true
			else:
				was_fully_focused = false
				
			# Smoothly bounce scale back to 1.0
			pop_scale = lerpf(pop_scale, 1.0, delta * 12.0)
			scale = Vector2(pop_scale, pop_scale)
			
			mouse_still_timer += delta
			var sway_fade = clampf((mouse_still_timer - 0.15) * 4.0, 0.0, 1.0)
			
			var breath_sway = Vector2.ZERO
			if enable_crosshair_sway and sway_fade > 0.0:
				var t = Time.get_ticks_msec() * 0.001
				var is_moving = ("velocity" in p) and (p.velocity.length() > 0.1)
				# Smoothly reduce sway by 50% at full focus
				var focus_mult = lerpf(1.0, 0.5, focus_prog)
				var sway_mult = crosshair_sway_amount * sway_fade * focus_mult
				if is_moving:
					sway_mult *= crosshair_sway_move_mult
				
				# Gamey figure-8 sway: two sine waves at slightly different speeds
				# creates a smooth Lissajous curve — reads clearly as breathing, not noise
				breath_sway = Vector2(
					sin(t * 1.1) * 4.0 * sway_mult,
					sin(t * 1.7) * 3.0 * sway_mult
				)
			
			target_mouse_sway = Vector2.ZERO
			
			if shot_recoil_timer > 0.0:
				shot_recoil_timer -= delta
				crosshair_shot_offset = crosshair_shot_offset.lerp(Vector2.ZERO, delta * crosshair_shot_recoil_recovery_speed)
				if shot_recoil_timer <= 0.0:
					crosshair_shot_offset = Vector2.ZERO
			else:
				crosshair_shot_offset = Vector2.ZERO
				
			var desired_sway = breath_sway + target_mouse_sway + crosshair_shot_offset
			sway_offset = sway_offset.lerp(desired_sway, delta * 14.0)
			
		queue_redraw()
	else:
		was_visible = false
		visual_r = max_reticle_radius
		scale = Vector2.ONE
		pop_scale = 1.0
		was_fully_focused = false
		sway_offset = Vector2.ZERO
		target_mouse_sway = Vector2.ZERO
		crosshair_shot_offset = Vector2.ZERO
		shot_recoil_timer = 0.0

func _draw() -> void:
	var p = get_player()
	if p == null:
		return

	var focus_prog: float = p.get("focus_progress") if "focus_progress" in p else 0.0
	
	# Determine color based on focus progress
	var line_color = default_color
	if focus_prog >= 1.0:
		line_color = focused_color
		
	var center = (size / 2.0) + sway_offset
	
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
