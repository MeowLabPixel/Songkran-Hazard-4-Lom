class_name InteractionPointHUD
extends Control

## InteractionPointHUD
## AAA-style, clean, semi-transparent warm-white/yellow circular interaction points
## for the Merchant (during the quest to find him) and Takedownable Zombies.
##
## Features:
## 1. Distant state: minimalist circular pip with soft core and subtle breathing pulse.
## 2. In-range state: smoothly expands into an action badge displaying the key prompt (F or E) inside.
## 3. Off-screen navigation: for the Merchant quest, clamps to screen borders with a clean directional pointer.
## 4. Ultra-performance: zero external textures; 100% procedural 2D vector drawing via _draw().

# Visual Theme (Warm White / AAA Pale Yellow)
const COLOR_WARM_WHITE = Color(1.0, 0.97, 0.88, 0.85)
const COLOR_ACCENT_YELLOW = Color(0.987, 0.831, 0.13, 0.95)
const COLOR_SHADOW = Color(0.0, 0.06, 0.22, 0.75)
const COLOR_INNER_BG = Color(0.04, 0.08, 0.22, 0.82)
const COLOR_TAKEDOWN_CYAN = Color(0.4, 0.95, 0.85, 0.95)

# Dimensions
const DISTANT_RING_RADIUS: float = 8.5
const DISTANT_CORE_RADIUS: float = 3.2
const IN_RANGE_RADIUS: float = 16.0
const SCREEN_EDGE_PADDING: float = 48.0

# Fonts
var font_bold: Font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")

# Internal State Cache
var _pulse_time: float = 0.0
var _merchant_in_range_t: float = 0.0
var _merchant_alpha: float = 0.0
var _enemy_states: Dictionary = {} # enemy_id -> { "alpha": float, "in_range_t": float }

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Ensure it renders above background elements but below modal dialogs
	z_index = 5

func _process(delta: float) -> void:
	_pulse_time += delta * 2.8
	
	# Determine if HUD should be active
	var gm = get_tree().root.get_node_or_null("GameManager") if get_tree() and get_tree().root else null
	if gm and "show_gameplay_ui" in gm and not gm.show_gameplay_ui:
		visible = false
		return
	
	visible = true
	queue_redraw()

func _draw() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if not cam:
		return
		
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if get_tree() else null
	var gm = get_tree().root.get_node_or_null("GameManager") if get_tree() and get_tree().root else null
	var delta: float = get_process_delta_time()
	var vp_rect: Rect2 = get_viewport_rect()

	# 1. Render Merchant Interaction Point (Active during quest to meet merchant)
	_draw_merchant_point(cam, player, gm, vp_rect, delta)

	# 2. Render Takedownable Zombie Interaction Points
	_draw_takedown_points(cam, player, delta)

# -----------------------------------------------------------------------------
# Merchant Interaction Point & Compass
# -----------------------------------------------------------------------------
func _draw_merchant_point(cam: Camera3D, player: Node3D, gm: Node, vp_rect: Rect2, delta: float) -> void:
	var is_quest_active: bool = false
	if gm and "game_phase" in gm:
		# GamePhase: 0 = FIRST_WAVE, 1 = MEET_MERCHANT, 2 = FINAL_WAVE
		is_quest_active = (int(gm.game_phase) == 1)

	var merchant: Node3D = get_tree().get_first_node_in_group("merchant") as Node3D if get_tree() else null
	if not is_quest_active or not merchant or not is_instance_valid(merchant):
		_merchant_alpha = move_toward(_merchant_alpha, 0.0, delta * 4.0)
		return

	# If currently inside shop menu or dialogue, smoothly fade out
	var is_in_shop: bool = false
	if "is_in_interaction" in merchant and merchant.is_in_interaction:
		is_in_shop = true
	if player and "is_in_shop" in player and player.is_in_shop:
		is_in_shop = true

	var target_alpha: float = 0.0 if is_in_shop else 1.0
	_merchant_alpha = move_toward(_merchant_alpha, target_alpha, delta * 3.5)
	if _merchant_alpha <= 0.001:
		return

	# 1. Authoritative check: Player is in interactable range if and only if
	# the merchant interaction system confirms player is facing the counter and in range.
	var is_in_interact_range: bool = false
	if player and "nearby_merchant" in player and is_instance_valid(player.nearby_merchant):
		if player.nearby_merchant == merchant and ("is_in_shop" not in player or not player.is_in_shop):
			is_in_interact_range = true
	elif "is_player_in_range" in merchant and merchant.is_player_in_range:
		if not is_in_shop:
			is_in_interact_range = true

	# Smoothly transition in-range state
	var target_in_range: float = 1.0 if is_in_interact_range else 0.0
	_merchant_in_range_t = move_toward(_merchant_in_range_t, target_in_range, delta * 7.0)

	# 3D world target position: directly above the counter interaction point where the player interacts
	var interact_pos: Vector3 = merchant.global_position + Vector3(0.0, 1.0, 0.85)
	if merchant.has_method("_get_interaction_point"):
		interact_pos = merchant._get_interaction_point()
	elif merchant.has_node("ShopTriggerArea"):
		interact_pos = merchant.get_node("ShopTriggerArea").global_position

	var player_pos: Vector3 = player.global_position if player else cam.global_position
	var dist_to_player: float = player_pos.distance_to(interact_pos)

	var world_target: Vector3 = interact_pos + Vector3(0.0, 0.45, 0.0)
	var is_behind: bool = cam.is_position_behind(world_target)
	var screen_pos: Vector2 = cam.unproject_position(world_target)

	var center: Vector2 = vp_rect.size * 0.5
	var margin: float = SCREEN_EDGE_PADDING
	var min_x = margin
	var max_x = vp_rect.size.x - margin
	var min_y = margin
	var max_y = vp_rect.size.y - margin

	var is_off_screen: bool = is_behind or screen_pos.x < min_x or screen_pos.x > max_x or screen_pos.y < min_y or screen_pos.y > max_y

	if is_off_screen:
		# Off-screen edge clamping with directional pointer
		var dir_from_center: Vector2
		if is_behind:
			dir_from_center = (center - screen_pos)
			if dir_from_center.length_squared() < 0.001:
				dir_from_center = Vector2.DOWN
			else:
				dir_from_center = dir_from_center.normalized()
		else:
			dir_from_center = (screen_pos - center).normalized()

		var edge_pos = _intersect_rect(center, dir_from_center, min_x, min_y, max_x, max_y)
		var angle = dir_from_center.angle()
		_draw_edge_pip(edge_pos, angle, _merchant_alpha, dist_to_player)
	else:
		# On-screen 3D-projected interaction point
		_draw_interactive_circle(screen_pos, _merchant_in_range_t, _merchant_alpha, "F", dist_to_player, false)

# -----------------------------------------------------------------------------
# Takedownable Zombie Points
# -----------------------------------------------------------------------------
func _draw_takedown_points(cam: Camera3D, player: Node3D, delta: float) -> void:
	if not get_tree():
		return

	var enemies = get_tree().get_nodes_in_group("enemies")
	var player_pos: Vector3 = player.global_position if player else cam.global_position
	var current_frame_ids: Dictionary = {}

	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if "is_defeated" in enemy and enemy.is_defeated:
			continue
		if not enemy.has_method("is_takedownable") or not enemy.is_takedownable():
			continue

		var iid = enemy.get_instance_id()
		current_frame_ids[iid] = true

		if not _enemy_states.has(iid):
			_enemy_states[iid] = { "alpha": 0.0, "in_range_t": 0.0 }
		var state: Dictionary = _enemy_states[iid]

		var enemy_pos = enemy.global_position
		var dist_to_player = player_pos.distance_to(enemy_pos)
		if dist_to_player > 25.0:
			state["alpha"] = move_toward(state["alpha"], 0.0, delta * 5.0)
			continue

		# Authoritative check: Player can execute takedown on this enemy if and only if
		# player.is_near_stunt is true (forward stun detector physically overlapping) and this enemy is in near_enemy_list
		var is_in_range: bool = false
		if player and "is_near_stunt" in player and player.is_near_stunt:
			var near_list: Array = player.near_enemy_list if ("near_enemy_list" in player and player.near_enemy_list != null) else []
			if near_list.has(enemy):
				is_in_range = true

		var target_in_range: float = 1.0 if is_in_range else 0.0
		state["in_range_t"] = move_toward(state["in_range_t"], target_in_range, delta * 7.0)
		state["alpha"] = move_toward(state["alpha"], 1.0, delta * 5.0)

		if state["alpha"] <= 0.001:
			continue

		# 3D world target: follow the animated head bone DEF-spine.006 so the pip moves with the stagger/kneel animation
		var world_target: Vector3 = enemy_pos + Vector3(0.0, 1.7, 0.0)
		if enemy.has_method("get_head_position"):
			var head_p: Vector3 = enemy.get_head_position()
			if head_p.distance_squared_to(enemy_pos) > 0.05:
				world_target = head_p + Vector3(0.0, 0.28, 0.0)

		var dist_to_target: float = player_pos.distance_to(world_target)

		if cam.is_position_behind(world_target):
			continue

		var screen_pos: Vector2 = cam.unproject_position(world_target)
		var vp_rect: Rect2 = get_viewport_rect()
		if not vp_rect.has_point(screen_pos):
			continue

		_draw_interactive_circle(screen_pos, state["in_range_t"], state["alpha"], "E", dist_to_target, true)

	# Clean up removed or recovered enemy states
	var to_erase: Array = []
	for iid in _enemy_states.keys():
		if not current_frame_ids.has(iid):
			var state: Dictionary = _enemy_states[iid]
			state["alpha"] = move_toward(state["alpha"], 0.0, delta * 6.0)
			if state["alpha"] <= 0.001:
				to_erase.append(iid)
	for iid in to_erase:
		_enemy_states.erase(iid)

# -----------------------------------------------------------------------------
# Drawing Helpers: Procedural AAA Point & Prompt
# -----------------------------------------------------------------------------
func _draw_interactive_circle(pos: Vector2, in_range_t: float, alpha: float, prompt_key: String, dist_meters: float, is_takedown: bool) -> void:
	var pulse: float = sin(_pulse_time) * 0.5 + 0.5 # 0.0 to 1.0
	var subtle_breathing: float = lerpf(0.96, 1.04, pulse)

	# Radius interpolates smoothly between distant pip and prompt badge
	var current_radius: float = lerpf(DISTANT_RING_RADIUS * subtle_breathing, IN_RANGE_RADIUS, in_range_t)
	var final_alpha: float = alpha * lerpf(0.75, 1.0, in_range_t)

	var ring_color: Color = COLOR_TAKEDOWN_CYAN if is_takedown else COLOR_ACCENT_YELLOW
	var white_color: Color = COLOR_WARM_WHITE
	ring_color.a *= final_alpha
	white_color.a *= final_alpha

	var shadow_col: Color = COLOR_SHADOW
	shadow_col.a *= final_alpha

	# 1. Soft contrast shadow behind the ring
	draw_arc(pos + Vector2(0, 1.5), current_radius + 1.0, 0, TAU, 32, shadow_col, 3.2, true)

	if in_range_t > 0.05:
		# 2. In-range state: Translucent dark inner backing
		var bg_col: Color = COLOR_INNER_BG
		bg_col.a *= in_range_t * final_alpha
		draw_circle(pos, current_radius, bg_col)

		# Outer glowing ring
		var border_w: float = lerpf(1.8, 2.4, in_range_t)
		draw_arc(pos, current_radius, 0, TAU, 36, ring_color, border_w, true)

		# Action Prompt Button Keycap Letter (e.g. "F" or "E")
		var font_size: int = 16
		var char_str: String = prompt_key
		var str_size: Vector2 = font_bold.get_string_size(char_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos: Vector2 = pos + Vector2(-str_size.x * 0.5, str_size.y * 0.35)

		# Text drop shadow
		var text_shadow_col = Color(0, 0, 0, in_range_t * final_alpha * 0.9)
		draw_string(font_bold, text_pos + Vector2(1, 1), char_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_shadow_col)
		# Crisp foreground letter
		var letter_col: Color = Color.WHITE
		letter_col.a = in_range_t * final_alpha
		draw_string(font_bold, text_pos, char_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, letter_col)
	else:
		# 3. Distant state: Minimalist circular ring + solid inner core dot
		# Outer fine ring
		draw_arc(pos, current_radius, 0, TAU, 28, ring_color, 1.8, true)
		# Inner soft core dot
		draw_circle(pos, DISTANT_CORE_RADIUS, white_color)

# -----------------------------------------------------------------------------
# Off-Screen Edge Pip & Compass Chevron
# -----------------------------------------------------------------------------
func _draw_edge_pip(pos: Vector2, angle: float, alpha: float, dist_meters: float) -> void:
	var pulse: float = sin(_pulse_time * 1.2) * 0.5 + 0.5
	var pip_radius: float = DISTANT_RING_RADIUS * lerpf(0.95, 1.05, pulse)

	var ring_col: Color = COLOR_ACCENT_YELLOW
	ring_col.a *= alpha * 0.9
	var core_col: Color = COLOR_WARM_WHITE
	core_col.a *= alpha * 0.95
	var shadow_col: Color = COLOR_SHADOW
	shadow_col.a *= alpha

	# Contrast shadow
	draw_circle(pos + Vector2(0, 1.5), pip_radius + 2.0, shadow_col)
	# Translucent background
	var bg_col: Color = COLOR_INNER_BG
	bg_col.a *= alpha * 0.8
	draw_circle(pos, pip_radius, bg_col)
	# Outer ring
	draw_arc(pos, pip_radius, 0, TAU, 24, ring_col, 2.0, true)
	# Inner dot
	draw_circle(pos, DISTANT_CORE_RADIUS, core_col)

	# Directional Chevron Arrow pointing off-screen toward target
	var chevron_dist: float = pip_radius + 9.0
	var forward: Vector2 = Vector2.from_angle(angle)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var tip: Vector2 = pos + forward * (chevron_dist + 4.0)
	var left_wing: Vector2 = pos + forward * (chevron_dist - 3.0) + right * 5.0
	var right_wing: Vector2 = pos + forward * (chevron_dist - 3.0) - right * 5.0

	var pts: PackedVector2Array = [tip, left_wing, pos + forward * (chevron_dist - 1.0), right_wing]
	draw_colored_polygon(pts, ring_col)

	# Optional clean distance readout next to edge marker
	if dist_meters > 3.0:
		var dist_str = "%dm" % int(dist_meters)
		var font_size = 13
		var str_sz = font_bold.get_string_size(dist_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var offset_dir = -forward
		var text_center = pos + offset_dir * (pip_radius + 12.0)
		var text_pos = text_center + Vector2(-str_sz.x * 0.5, str_sz.y * 0.35)
		draw_string(font_bold, text_pos + Vector2(1, 1), dist_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, shadow_col)
		draw_string(font_bold, text_pos, dist_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, core_col)

# -----------------------------------------------------------------------------
# Ray-AABB Screen Edge Intersection
# -----------------------------------------------------------------------------
func _intersect_rect(origin: Vector2, dir: Vector2, min_x: float, min_y: float, max_x: float, max_y: float) -> Vector2:
	var t_min: float = 0.0
	var t_max: float = 1e6

	if abs(dir.x) > 0.0001:
		var tx1 = (min_x - origin.x) / dir.x
		var tx2 = (max_x - origin.x) / dir.x
		var t_enter = minf(tx1, tx2)
		var t_exit = maxf(tx1, tx2)
		if t_enter > t_min: t_min = t_enter
		if t_exit < t_max: t_max = t_exit

	if abs(dir.y) > 0.0001:
		var ty1 = (min_y - origin.y) / dir.y
		var ty2 = (max_y - origin.y) / dir.y
		var t_enter = minf(ty1, ty2)
		var t_exit = maxf(ty1, ty2)
		if t_enter > t_min: t_min = t_enter
		if t_exit < t_max: t_max = t_exit

	var t = t_max if t_max > 0.0 else t_min
	return origin + dir * t
