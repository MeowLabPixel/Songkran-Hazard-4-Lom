@tool
## PlayerStatHUD — Visual HUD for player stats.
## Renders: player HP ring with 3D portrait, water/air bars,
## follower HP ring with 3D portrait, kill count, and timer.
## Designed to be fully tinker-ready with real nodes in the Godot Editor.
extends CanvasLayer

# ═══════════════════════════════════════════════════════════════════════════
#                         COMPONENT NODE REFERENCES
#  Can be wired in the Inspector or automatically resolved by scene hierarchy.
# ═══════════════════════════════════════════════════════════════════════════

@export_group("Component Nodes")
@export var hud_root: Control
@export var bottom_right_cluster: Control
@export var water_bar: HudResourceBar
@export var air_bar: HudResourceBar
@export var debuff_label: Label

@export_group("Player Portrait")
@export var player_portrait: HudHPRing
@export var player_svc: SubViewportContainer
@export var player_viewport: SubViewport
@export var player_camera: Camera3D

@export_group("Follower Portrait")
@export var follower_portrait: HudHPRing
@export var follower_svc: SubViewportContainer
@export var follower_viewport: SubViewport
@export var follower_camera: Camera3D

@export_group("Counters")
@export var kill_rect: TextureRect
@export var kill_label: Label
@export var time_rect: TextureRect
@export var time_label: Label

# ═══════════════════════════════════════════════════════════════════════════
#                         CAMERA SETTINGS
# ═══════════════════════════════════════════════════════════════════════════

@export_group("Player Portrait 3D View")
@export var player_cam_pos := Vector3(0.0, 1.56, -0.65):
	set(v):
		player_cam_pos = v
		_on_camera_setting_changed()

@export var player_cam_look := Vector3(0.0, 1.565, 0.0):
	set(v):
		player_cam_look = v
		_on_camera_setting_changed()

@export var player_cam_size := 0.415:
	set(v):
		player_cam_size = v
		_on_camera_setting_changed()

@export_group("Follower Portrait 3D View")
@export var follower_cam_pos := Vector3(0.005, 1.385, -0.65):
	set(v):
		follower_cam_pos = v
		_on_camera_setting_changed()

@export var follower_cam_look := Vector3(0.0, 1.45, 0.0):
	set(v):
		follower_cam_look = v
		_on_camera_setting_changed()

@export var follower_cam_size := 0.415:
	set(v):
		follower_cam_size = v
		_on_camera_setting_changed()

@export_group("Portrait Face Centering & Head Tracking")
@export var camera_track_head: bool = false:
	set(v):
		camera_track_head = v
		_on_camera_setting_changed()

@export var player_face_offset: Vector3 = Vector3(0.0, 0.11, 0.0):
	set(v):
		player_face_offset = v
		_on_camera_setting_changed()

@export var follower_face_offset: Vector3 = Vector3(0.0, 0.04, 0.0):
	set(v):
		follower_face_offset = v
		_on_camera_setting_changed()

@export var cam_distance: float = 0.65:
	set(v):
		cam_distance = v
		_on_camera_setting_changed()

@export_range(0.0, 1.0, 0.05) var action_head_look_influence: float = 0.5:
	set(v):
		action_head_look_influence = v

@export var head_look_lerp_speed: float = 6.0:
	set(v):
		head_look_lerp_speed = v

@export_group("Portrait Animation")
@export var player_idle_speed_scale: float = 0.75
@export var follower_idle_speed_scale: float = 1.0

# ═══════════════════════════════════════════════════════════════════════════
#                           COLOUR PALETTE
# ═══════════════════════════════════════════════════════════════════════════

const C_AIR_NORMAL := Color("b2ebf2")
const C_AIR_SUPER_READY := Color(1.0, 0.9, 0.1)
const C_AIR_SUPER_ACTIVE := Color(1.0, 0.2, 0.2)

# ═══════════════════════════════════════════════════════════════════════════
#                        INTERNAL STATE
# ═══════════════════════════════════════════════════════════════════════════

var _player: Node = null
var _follower: Node = null
var _gun_controller: Node = null
var _main_player_fc: Node = null       # PlayerFaceController on the real model
var _main_follower_fc: Node = null     # AnchaleeFaceController on the real model

var _player_portrait_setup: bool = false
var _follower_portrait_setup: bool = false

# Unique portrait material references for face syncing
var _p_eye_mat: StandardMaterial3D = null
var _p_mouth_mat: StandardMaterial3D = null
var _p_eye_idx: int = 2
var _p_mouth_idx: int = 3

var _f_eye_mat: StandardMaterial3D = null
var _f_mouth_mat: StandardMaterial3D = null
var _f_eye_idx: int = 0
var _f_mouth_idx: int = 1

# Player head rotation mimic & camera tracking references
var _p_src_skel: Skeleton3D = null
var _p_dst_skel: Skeleton3D = null
var _p_head_idx: int = -1
var _p_anim_player: AnimationPlayer = null
var _p_head_rest_rot: Quaternion = Quaternion.IDENTITY
var _current_head_look_influence: float = 1.0

# Follower head rotation mimic & camera tracking references
var _f_src_skel: Skeleton3D = null
var _f_dst_skel: Skeleton3D = null
var _f_head_idx: int = -1
var _f_head_rest_rot: Quaternion = Quaternion.IDENTITY
var _f_anim_player: AnimationPlayer = null

var _last_debuff_text: String = ""
var _default_air_color: Color = Color("b2ebf2")
var _font_sub: Font = null
var _font_body: Font = null
var _mask_shader: Shader = null

# ═══════════════════════════════════════════════════════════════════════════
#                            LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_bind_or_build_nodes()

	if Engine.is_editor_hint():
		_setup_editor_portraits()
		return

	add_to_group("player_ui")

	_font_sub  = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
	_font_body = preload("res://scenes/font/iannnnnVCD 2007 Bold.ttf")
	_mask_shader = preload("res://shaders/circle_mask.gdshader")

	# Hide legacy child labels from old UI.gd (e.g. $HP, $Water, $Air if in player.tscn)
	for child in get_children():
		if child is Control and child != hud_root:
			var cname := child.name.to_lower()
			if cname in ["hp", "water", "air", "shockwavedrawer"]:
				child.visible = false

	_find_references()
	_try_setup_portraits()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if player_viewport == null:
			_bind_or_build_nodes()
		if player_viewport and not player_viewport.has_node("EditorPreviewHead"):
			_setup_editor_portraits()
		_ensure_editor_preview_skeletons()
		_sync_editor_cameras()
		return

	_refresh_references()
	_try_setup_portraits()

	# ── Visibility ──
	var should_show := true
	if get_tree().root.has_node("GameManager"):
		should_show = GameManager.show_player_stat_ui and GameManager.show_gameplay_ui
	if _player and "HP" in _player and _player.HP <= 0:
		should_show = false

	if hud_root:
		hud_root.visible = should_show
	if not should_show:
		return

	_update_player_hp()
	_update_bars()
	_update_follower()
	_update_debuff()
	_update_counters()
	_sync_faces()
	_sync_player_head_rotation(delta)
	_update_portrait_cameras()

# ═══════════════════════════════════════════════════════════════════════════
#                    NODE BINDING & FALLBACK CREATION
# ═══════════════════════════════════════════════════════════════════════════

func _bind_or_build_nodes() -> void:
	# 0. Hide any editor preview background (e.g. $bg)
	for child in get_children():
		if child is Control and child.name == "bg":
			child.visible = false

	# 1. Try to find the root control from existing scene nodes
	if hud_root == null:
		hud_root = get_node_or_null("HUDRoot") as Control

	# 2. If hud_root is not directly attached (e.g. attached to Player Stat in player.tscn),
	#    dynamically instantiate the user's customized player_stat_hud.tscn!
	if hud_root == null:
		var scene_res := load("res://scenes/player/player_stat_hud.tscn") as PackedScene
		if scene_res:
			var inst := scene_res.instantiate()
			# Hide preview bg on instantiated scene if present
			if inst.has_node("bg"):
				inst.get_node("bg").visible = false
			var inst_hud_root := inst.get_node_or_null("HUDRoot") as Control
			if inst_hud_root:
				inst_hud_root.owner = null
				inst.remove_child(inst_hud_root)
				add_child(inst_hud_root)
				hud_root = inst_hud_root

			# Copy all customized inspector properties from player_stat_hud.tscn
			if inst is CanvasLayer:
				player_cam_pos = inst.player_cam_pos
				player_cam_look = inst.player_cam_look
				player_cam_size = inst.player_cam_size
				follower_cam_pos = inst.follower_cam_pos
				follower_cam_look = inst.follower_cam_look
				follower_cam_size = inst.follower_cam_size
				camera_track_head = inst.camera_track_head
				player_face_offset = inst.player_face_offset
				follower_face_offset = inst.follower_face_offset
				cam_distance = inst.cam_distance
				if "action_head_look_influence" in inst:
					action_head_look_influence = inst.action_head_look_influence
				if "head_look_lerp_speed" in inst:
					head_look_lerp_speed = inst.head_look_lerp_speed
				if "player_idle_speed_scale" in inst:
					player_idle_speed_scale = inst.player_idle_speed_scale
				if "follower_idle_speed_scale" in inst:
					follower_idle_speed_scale = inst.follower_idle_speed_scale

			inst.queue_free()

	if hud_root != null:
		# Auto-wire missing node paths by expected standard names
		if bottom_right_cluster == null:
			bottom_right_cluster = hud_root.get_node_or_null("BottomRightCluster") as Control
		if water_bar == null and bottom_right_cluster:
			water_bar = bottom_right_cluster.get_node_or_null("ResourceBars/WaterBar") as HudResourceBar
		if air_bar == null and bottom_right_cluster:
			air_bar = bottom_right_cluster.get_node_or_null("ResourceBars/AirBar") as HudResourceBar
		if debuff_label == null and bottom_right_cluster:
			debuff_label = bottom_right_cluster.get_node_or_null("ResourceBars/DebuffLabel") as Label
		if player_portrait == null and bottom_right_cluster:
			player_portrait = bottom_right_cluster.get_node_or_null("PlayerPortrait") as HudHPRing
		if player_svc == null and player_portrait:
			player_svc = player_portrait.get_node_or_null("PortraitSVC") as SubViewportContainer
		if player_viewport == null and player_svc:
			player_viewport = player_svc.get_node_or_null("PortraitViewport") as SubViewport
		if player_camera == null and player_viewport:
			player_camera = player_viewport.get_node_or_null("PortraitCamera") as Camera3D
		if follower_portrait == null and bottom_right_cluster:
			follower_portrait = bottom_right_cluster.get_node_or_null("FollowerPortrait") as HudHPRing
		if follower_svc == null and follower_portrait:
			follower_svc = follower_portrait.get_node_or_null("FollowerPortraitSVC") as SubViewportContainer
		if follower_viewport == null and follower_svc:
			follower_viewport = follower_svc.get_node_or_null("FollowerPortraitViewport") as SubViewport
		if follower_camera == null and follower_viewport:
			follower_camera = follower_viewport.get_node_or_null("FollowerPortraitCamera") as Camera3D
		if kill_rect == null:
			kill_rect = hud_root.get_node_or_null("KillCountHUD") as TextureRect
		if kill_label == null and kill_rect:
			kill_label = kill_rect.get_node_or_null("KillLabel") as Label
		if time_rect == null:
			time_rect = hud_root.get_node_or_null("TimeLimitHUD") as TextureRect
		if time_label == null and time_rect:
			time_label = time_rect.get_node_or_null("TimeLabel") as Label

		# Cache user's customized air bar color
		if air_bar:
			_default_air_color = air_bar.fill_color
	else:
		# Fallback: build nodes programmatically if player_stat_hud.tscn fails to load
		_build_fallback_hud()


func _build_fallback_hud() -> void:
	hud_root = Control.new()
	hud_root.name = "HUDRoot"
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)

	bottom_right_cluster = Control.new()
	bottom_right_cluster.name = "BottomRightCluster"
	bottom_right_cluster.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	bottom_right_cluster.anchor_left = 1.0
	bottom_right_cluster.anchor_top = 1.0
	bottom_right_cluster.anchor_right = 1.0
	bottom_right_cluster.anchor_bottom = 1.0
	bottom_right_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bottom_right_cluster)

	# Player Portrait
	player_portrait = HudHPRing.new()
	player_portrait.name = "PlayerPortrait"
	player_portrait.position = Vector2(-24.0 - 112.0, -24.0 - 112.0)
	player_portrait.size = Vector2(112.0, 112.0)
	player_portrait.ring_width = 7.0
	player_portrait.border_width = 2.0
	player_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_right_cluster.add_child(player_portrait)

	# Follower Portrait
	follower_portrait = HudHPRing.new()
	follower_portrait.name = "FollowerPortrait"
	follower_portrait.position = player_portrait.position + Vector2(40.0, -70.0)
	follower_portrait.size = Vector2(56.0, 56.0)
	follower_portrait.ring_width = 4.0
	follower_portrait.border_width = 1.5
	follower_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	follower_portrait.visible = false
	bottom_right_cluster.add_child(follower_portrait)

	# Resource Bars
	var res_bars := Control.new()
	res_bars.name = "ResourceBars"
	res_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_right_cluster.add_child(res_bars)

	var bar_right := player_portrait.position.x - 8.0
	var bar_left := bar_right - 200.0
	var bar_cy := player_portrait.position.y + 56.0

	water_bar = HudResourceBar.new()
	water_bar.name = "WaterBar"
	water_bar.position = Vector2(bar_left, bar_cy - 30.0 - 2.0)
	water_bar.size = Vector2(200.0, 30.0)
	water_bar.fill_color = Color("4fc3f7")
	water_bar.label_font = _font_sub
	water_bar.label_font_size = 18
	water_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res_bars.add_child(water_bar)

	air_bar = HudResourceBar.new()
	air_bar.name = "AirBar"
	air_bar.position = Vector2(bar_left, bar_cy + 2.0)
	air_bar.size = Vector2(200.0, 20.0)
	air_bar.fill_color = C_AIR_NORMAL
	air_bar.label_font = _font_sub
	air_bar.label_font_size = 14
	air_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res_bars.add_child(air_bar)

	debuff_label = Label.new()
	debuff_label.name = "DebuffLabel"
	debuff_label.position = Vector2(bar_left, air_bar.position.y + 22.0)
	debuff_label.size = Vector2(200.0, 18.0)
	debuff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	debuff_label.add_theme_font_override("font", _font_body)
	debuff_label.add_theme_font_size_override("font_size", 12)
	debuff_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debuff_label.add_theme_constant_override("outline_size", 4)
	res_bars.add_child(debuff_label)

	# Kill count & time limit
	_build_fallback_counters()

	# SubViewports
	_build_fallback_portrait_viewports()


func _build_fallback_counters() -> void:
	kill_rect = TextureRect.new()
	kill_rect.name = "KillCountHUD"
	var kill_tex := preload("res://scenes/Kill_Count_Ui.png")
	kill_rect.texture = kill_tex
	kill_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kill_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var target_h := 160.0
	var kill_size := kill_tex.get_size() * (target_h / kill_tex.get_size().y)
	kill_rect.size = kill_size
	kill_rect.anchors_preset = Control.PRESET_TOP_RIGHT
	kill_rect.anchor_left = 1.0
	kill_rect.anchor_top = 0.0
	kill_rect.anchor_right = 1.0
	kill_rect.anchor_bottom = 0.0
	kill_rect.offset_left = -kill_size.x - 60
	kill_rect.offset_top = 24
	kill_rect.offset_right = -60
	kill_rect.offset_bottom = 24 + kill_size.y
	kill_rect.pivot_offset = kill_size * 0.5
	hud_root.add_child(kill_rect)

	kill_label = Label.new()
	kill_label.name = "KillLabel"
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kill_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	kill_label.add_theme_font_size_override("font_size", 18)
	kill_label.add_theme_font_override("font", _font_sub)
	kill_label.add_theme_color_override("font_outline_color", Color.BLACK)
	kill_label.add_theme_constant_override("outline_size", 4)
	kill_rect.add_child(kill_label)

	time_rect = TextureRect.new()
	time_rect.name = "TimeLimitHUD"
	var time_tex := preload("res://scenes/General_Wide_UI_Box.png")
	time_rect.texture = time_tex
	time_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	time_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var time_size := time_tex.get_size() * (target_h / time_tex.get_size().y) * 0.3
	time_rect.size = time_size
	time_rect.anchors_preset = Control.PRESET_TOP_RIGHT
	time_rect.anchor_left = 1.0
	time_rect.anchor_top = 0.0
	time_rect.anchor_right = 1.0
	time_rect.anchor_bottom = 0.0
	time_rect.offset_right = -kill_size.x - 72
	time_rect.offset_left = -kill_size.x - 72 - time_size.x
	time_rect.offset_top = 64
	time_rect.offset_bottom = 64 + time_size.y
	time_rect.pivot_offset = time_size * 0.5
	hud_root.add_child(time_rect)

	time_label = Label.new()
	time_label.name = "TimeLabel"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	time_label.add_theme_font_size_override("font_size", 18)
	time_label.add_theme_font_override("font", _font_sub)
	time_label.add_theme_color_override("font_outline_color", Color.BLACK)
	time_label.add_theme_constant_override("outline_size", 4)
	time_rect.add_child(time_label)


func _build_fallback_portrait_viewports() -> void:
	# Player SubViewport
	var p_margin := player_portrait.ring_width + player_portrait.border_width + 1.0
	var p_inner := player_portrait.size.x - p_margin * 2.0

	player_svc = SubViewportContainer.new()
	player_svc.name = "PortraitSVC"
	player_svc.stretch = true
	player_svc.position = Vector2(p_margin, p_margin)
	player_svc.size = Vector2(p_inner, p_inner)
	player_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p_mat := ShaderMaterial.new()
	p_mat.shader = _mask_shader
	player_svc.material = p_mat

	player_viewport = SubViewport.new()
	player_viewport.name = "PortraitViewport"
	player_viewport.size = Vector2i(int(p_inner) * 2, int(p_inner) * 2)
	player_viewport.transparent_bg = true
	player_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	player_viewport.own_world_3d = true
	player_viewport.msaa_3d = Viewport.MSAA_2X
	player_svc.add_child(player_viewport)

	player_camera = Camera3D.new()
	player_camera.name = "PortraitCamera"
	player_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	player_camera.size = player_cam_size
	player_camera.near = 0.01
	player_camera.far = 10.0
	player_camera.position = player_cam_pos
	player_camera.look_at(player_cam_look)
	player_viewport.add_child(player_camera)

	_add_portrait_lighting(player_viewport)
	player_portrait.add_child(player_svc)

	# Follower SubViewport
	var f_margin := follower_portrait.ring_width + follower_portrait.border_width + 1.0
	var f_inner := follower_portrait.size.x - f_margin * 2.0

	follower_svc = SubViewportContainer.new()
	follower_svc.name = "FollowerPortraitSVC"
	follower_svc.stretch = true
	follower_svc.position = Vector2(f_margin, f_margin)
	follower_svc.size = Vector2(f_inner, f_inner)
	follower_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f_mat := ShaderMaterial.new()
	f_mat.shader = _mask_shader
	follower_svc.material = f_mat

	follower_viewport = SubViewport.new()
	follower_viewport.name = "FollowerPortraitViewport"
	follower_viewport.size = Vector2i(int(f_inner) * 2, int(f_inner) * 2)
	follower_viewport.transparent_bg = true
	follower_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	follower_viewport.own_world_3d = true
	follower_viewport.msaa_3d = Viewport.MSAA_2X
	follower_svc.add_child(follower_viewport)

	follower_camera = Camera3D.new()
	follower_camera.name = "FollowerPortraitCamera"
	follower_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	follower_camera.size = follower_cam_size
	follower_camera.near = 0.01
	follower_camera.far = 10.0
	follower_camera.position = follower_cam_pos
	follower_camera.look_at(follower_cam_look)
	follower_viewport.add_child(follower_camera)

	_add_portrait_lighting(follower_viewport)
	follower_portrait.add_child(follower_svc)


func _add_portrait_lighting(vp: SubViewport) -> void:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-25.0, 30.0, 0.0)
	key.light_energy = 1.3
	key.shadow_enabled = false
	vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-10.0, -45.0, 0.0)
	fill.light_energy = 0.4
	fill.shadow_enabled = false
	vp.add_child(fill)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_energy = 0.7
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)

# ═══════════════════════════════════════════════════════════════════════════
#                        REFERENCE LOOKUP
# ═══════════════════════════════════════════════════════════════════════════

func _find_references() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		if "gun_controller" in _player:
			_gun_controller = _player.gun_controller
		if "face_controller" in _player:
			_main_player_fc = _player.face_controller
	_follower = get_tree().get_first_node_in_group("Anchalee")
	if _follower and "face_controller" in _follower:
		_main_follower_fc = _follower.face_controller


func _refresh_references() -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_gun_controller = _player.gun_controller if "gun_controller" in _player else null
			_main_player_fc = _player.face_controller if "face_controller" in _player else null
	if not _follower or not is_instance_valid(_follower):
		_follower = get_tree().get_first_node_in_group("Anchalee")
		if _follower and "face_controller" in _follower:
			_main_follower_fc = _follower.face_controller

# ═══════════════════════════════════════════════════════════════════════════
#                       3D PORTRAIT HEAD CLONING
# ═══════════════════════════════════════════════════════════════════════════

func _try_setup_portraits() -> void:
	if not _player_portrait_setup and _player and is_instance_valid(_player):
		if _setup_single_portrait(_player, player_viewport, player_camera, player_cam_pos, player_cam_look, player_cam_size, true):
			_player_portrait_setup = true

	if not _follower_portrait_setup and _follower and is_instance_valid(_follower):
		if _setup_single_portrait(_follower, follower_viewport, follower_camera, follower_cam_pos, follower_cam_look, follower_cam_size, false):
			_follower_portrait_setup = true


func _setup_portraits() -> void:
	_try_setup_portraits()


func _setup_single_portrait(character: Node, sv: SubViewport, cam: Camera3D,
		cam_pos: Vector3, cam_look: Vector3, cam_sz: float, is_player: bool) -> bool:
	if not character or not is_instance_valid(character) or not sv:
		return false

	# Configure camera unconditionally with orthogonal framing facing the head
	if cam:
		cam.current = true
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.position = cam_pos
		cam.look_at(cam_look, Vector3.UP)
		cam.size = cam_sz

	# Find model root on the character
	var model_root: Node = _find_model_root(character, is_player)
	if not model_root:
		return false

	# Clear any previous model copies (including editor preview dummy)
	for child in sv.get_children():
		if child != cam and not (child is DirectionalLight3D or child is WorldEnvironment):
			child.queue_free()

	# Duplicate model into the isolated viewport
	var model_copy: Node = model_root.duplicate()
	model_copy.position = Vector3.ZERO
	_cleanup_portrait_model(model_copy)
	sv.add_child(model_copy)
	# Assign owner so scene-unique-name paths like %OriginalSkeleton resolve in the AnimationPlayer
	_assign_owners(model_copy)

	# Hide everything except head, hair, and collar/neck
	var head_mesh: MeshInstance3D = _hide_non_head_meshes(model_copy)
	if not head_mesh:
		return false

	# Create unique material instances to capture live face UV offsets
	if is_player:
		_p_eye_mat = _make_unique_material(head_mesh, _p_eye_idx)
		_p_mouth_mat = _make_unique_material(head_mesh, _p_mouth_idx)
		_p_src_skel = _find_skeleton(model_root)
		_p_dst_skel = _find_skeleton(model_copy)
		if _p_dst_skel:
			_p_head_idx = _p_dst_skel.find_bone("DEF-spine.006")
			if _p_head_idx == -1:
				for b in range(_p_dst_skel.get_bone_count()):
					if "head" in _p_dst_skel.get_bone_name(b).to_lower():
						_p_head_idx = b
						break
			if _p_head_idx != -1:
				_p_head_rest_rot = _p_dst_skel.get_bone_rest(_p_head_idx).basis.get_rotation_quaternion()
		_p_anim_player = _find_anim_player(model_copy)
		if _p_anim_player:
			_p_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	else:
		_f_eye_mat = _make_unique_material(head_mesh, _f_eye_idx)
		_f_mouth_mat = _make_unique_material(head_mesh, _f_mouth_idx)
		_f_src_skel = _find_skeleton(model_root)
		_f_dst_skel = _find_skeleton(model_copy)
		if _f_dst_skel:
			_f_head_idx = _f_dst_skel.find_bone("DEF-spine.006")
			if _f_head_idx == -1:
				for b in range(_f_dst_skel.get_bone_count()):
					if "head" in _f_dst_skel.get_bone_name(b).to_lower():
						_f_head_idx = b
						break
			if _f_head_idx != -1:
				_f_head_rest_rot = _f_dst_skel.get_bone_rest(_f_head_idx).basis.get_rotation_quaternion()
		_f_anim_player = _find_anim_player(model_copy)
		if _f_anim_player:
			_f_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	# Start dedicated looping idle animation
	_start_portrait_idle_animation(model_copy, is_player)
	_update_portrait_cameras()

	return true


func _setup_editor_portraits() -> void:
	if not Engine.is_editor_hint():
		return

	# Setup player preview head if not present
	if player_viewport and not player_viewport.has_node("EditorPreviewHead"):
		var p_scene := load("res://scenes/player/player.tscn") as PackedScene
		if p_scene:
			var p_inst := p_scene.instantiate()
			var p_model := _find_model_root(p_inst, true)
			if p_model:
				var copy := p_model.duplicate()
				copy.name = "EditorPreviewHead"
				copy.position = Vector3.ZERO
				_cleanup_portrait_model(copy)
				_hide_non_head_meshes(copy)
				player_viewport.add_child(copy)
				_assign_owners(copy)
				_start_portrait_idle_animation(copy, true)
			p_inst.queue_free()

	# Setup follower preview head if not present
	if follower_viewport and not follower_viewport.has_node("EditorPreviewHead"):
		var f_scene := load("res://scenes/anchalee/Anchalee.tscn") as PackedScene
		if f_scene:
			var f_inst := f_scene.instantiate()
			var f_model := _find_model_root(f_inst, false)
			if f_model:
				var copy := f_model.duplicate()
				copy.name = "EditorPreviewHead"
				copy.position = Vector3.ZERO
				_cleanup_portrait_model(copy)
				_hide_non_head_meshes(copy)
				follower_viewport.add_child(copy)
				_assign_owners(copy)
				_start_portrait_idle_animation(copy, false)
			f_inst.queue_free()

	_ensure_editor_preview_skeletons()
	_sync_editor_cameras()


func _ensure_editor_preview_skeletons() -> void:
	if not Engine.is_editor_hint():
		return

	_find_references()

	if player_viewport:
		var p_prev := player_viewport.get_node_or_null("EditorPreviewHead")
		if not p_prev and not player_viewport.has_node("EditorPreviewHead"):
			_setup_editor_portraits()
			p_prev = player_viewport.get_node_or_null("EditorPreviewHead")
		if p_prev and (not _p_dst_skel or not is_instance_valid(_p_dst_skel)):
			_p_dst_skel = _find_skeleton(p_prev)
			if _p_dst_skel:
				_p_head_idx = _p_dst_skel.find_bone("DEF-spine.006")
				if _p_head_idx == -1:
					for b in range(_p_dst_skel.get_bone_count()):
						if "head" in _p_dst_skel.get_bone_name(b).to_lower():
							_p_head_idx = b
							break
				if _p_head_idx != -1:
					_p_head_rest_rot = _p_dst_skel.get_bone_rest(_p_head_idx).basis.get_rotation_quaternion()
		if p_prev and (not _p_anim_player or not is_instance_valid(_p_anim_player)):
			_p_anim_player = _find_anim_player(p_prev)
			if _p_anim_player:
				_p_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				_start_portrait_idle_animation(p_prev, true)

	if follower_viewport:
		var f_prev := follower_viewport.get_node_or_null("EditorPreviewHead")
		if not f_prev and not follower_viewport.has_node("EditorPreviewHead"):
			_setup_editor_portraits()
			f_prev = follower_viewport.get_node_or_null("EditorPreviewHead")
		if f_prev and (not _f_dst_skel or not is_instance_valid(_f_dst_skel)):
			_f_dst_skel = _find_skeleton(f_prev)
			if _f_dst_skel:
				_f_head_idx = _f_dst_skel.find_bone("DEF-spine.006")
				if _f_head_idx == -1:
					for b in range(_f_dst_skel.get_bone_count()):
						if "head" in _f_dst_skel.get_bone_name(b).to_lower():
							_f_head_idx = b
							break
				if _f_head_idx != -1:
					_f_head_rest_rot = _f_dst_skel.get_bone_rest(_f_head_idx).basis.get_rotation_quaternion()
		if f_prev and (not _f_anim_player or not is_instance_valid(_f_anim_player)):
			_f_anim_player = _find_anim_player(f_prev)
			if _f_anim_player:
				_f_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				_start_portrait_idle_animation(f_prev, false)


func _sync_editor_cameras() -> void:
	_ensure_editor_preview_skeletons()
	_apply_camera_settings()


func _find_model_root(character: Node, is_player: bool) -> Node:
	if is_player:
		var root := character.get_node_or_null("Re4Lom Base Rig")
		if root:
			return root
	else:
		var root := character.get_node_or_null("AnchaleeModel")
		if root:
			return root

	for child in character.get_children():
		if child is Node3D and child.find_child("Skeleton3D", true, false):
			return child
	return null


func _cleanup_portrait_model(model: Node) -> void:
	var to_remove: Array[Node] = []
	for node in _get_all_descendants(model):
		var nname := node.name
		if (node is AnimationTree
				or node is Area3D or node is CollisionShape3D
				or node is CollisionPolygon3D or node is RayCast3D
				or node is NavigationAgent3D or node is AudioStreamPlayer3D
				or node is GPUParticles3D or node is BoneAttachment3D
				or node.is_class("LookAtModifier3D")
				or nname.begins_with("SpineLeanModifier")):
			to_remove.append(node)
		elif node.get_script() and not (node is MeshInstance3D or node is Skeleton3D or node is Node3D or node is AnimationPlayer):
			to_remove.append(node)

	for node in to_remove:
		if is_instance_valid(node) and node.get_parent():
			node.get_parent().remove_child(node)
			node.queue_free()


func _hide_non_head_meshes(model: Node) -> MeshInstance3D:
	var head: MeshInstance3D = null
	for node in _get_all_descendants(model):
		if node is MeshInstance3D:
			var n := node.name.to_lower()
			if "head" in n or "face" in n:
				node.visible = true
				if head == null:
					head = node as MeshInstance3D
			elif "hair" in n:
				node.visible = true
			elif "neck" in n or "suit" in n or "cloth" in n or "top" in n:
				node.visible = true
			else:
				node.visible = false
	return head


func _make_unique_material(head: MeshInstance3D, surface_idx: int) -> StandardMaterial3D:
	if surface_idx >= head.mesh.get_surface_count():
		return null
	var active := head.get_active_material(surface_idx)
	if active and active is StandardMaterial3D:
		var mat := active.duplicate() as StandardMaterial3D
		head.set_surface_override_material(surface_idx, mat)
		return mat
	return null

# ═══════════════════════════════════════════════════════════════════════════
#                          UPDATE LOOP
# ═══════════════════════════════════════════════════════════════════════════

func _update_player_hp() -> void:
	if not _player or not player_portrait:
		return
	player_portrait.max_value = float(_player.MaxHP) if "MaxHP" in _player else 150.0
	player_portrait.current_value = float(_player.HP) if "HP" in _player else 0.0


func _update_bars() -> void:
	if not _player:
		return

	# ── Water ──
	if _gun_controller and water_bar:
		var cw: float = _gun_controller.current_water
		var mw: float = _gun_controller.max_water
		water_bar.max_value = mw
		water_bar.current_value = cw
		water_bar.label_text = str(int(cw))

	# ── Air ──
	if _gun_controller and _gun_controller.current_gun and air_bar:
		var gun = _gun_controller.current_gun
		var air_val: float = gun.air
		var max_air: float = gun.max_air
		air_bar.max_value = max_air
		air_bar.current_value = air_val
		var pct := int((air_val / max_air) * 100.0) if max_air > 0.0 else 0
		air_bar.label_text = str(pct) + "%"

		if gun.is_super_active:
			air_bar.fill_color = C_AIR_SUPER_ACTIVE
		elif gun.is_super_ready:
			air_bar.fill_color = C_AIR_SUPER_READY
		else:
			air_bar.fill_color = _default_air_color


func _update_follower() -> void:
	if not follower_portrait:
		return

	if _follower and is_instance_valid(_follower) and not _follower.is_dead:
		follower_portrait.visible = true
		follower_portrait.max_value = float(_follower.max_health)
		follower_portrait.current_value = float(_follower.health)
	else:
		follower_portrait.visible = false


func _update_debuff() -> void:
	if not debuff_label or not _gun_controller:
		return
	if not _gun_controller.current_gun:
		debuff_label.text = ""
		return

	var gun = _gun_controller.current_gun
	var air_pct: float = gun.air / gun.max_air if gun.max_air > 0.0 else 0.0

	var lang := "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language

	var new_text := ""
	var color := Color.WHITE

	if air_pct <= 0.3:
		new_text = "-15% dmg" if lang == "en" else "-15% พลังโจมตี"
		color = Color(1.0, 0.3, 0.3)
	elif air_pct < 0.5:
		new_text = "-10% dmg" if lang == "en" else "-10% พลังโจมตี"
		color = Color(1.0, 0.6, 0.0)
	else:
		new_text = "+50% focus spd" if lang == "en" else "+50% ความเร็วโฟกัส"
		color = Color(0.2, 0.9, 0.5)

	if new_text != _last_debuff_text:
		_last_debuff_text = new_text
		debuff_label.text = new_text
		debuff_label.add_theme_color_override("font_color", color)

		if new_text != "":
			debuff_label.pivot_offset = debuff_label.get_minimum_size() * 0.5
			debuff_label.scale = Vector2.ZERO
			debuff_label.modulate.a = 0.0
			var tw := create_tween().set_parallel(true)
			tw.tween_property(debuff_label, "scale", Vector2.ONE, 0.25) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(debuff_label, "modulate:a", 1.0, 0.15)
		else:
			var tw := create_tween()
			tw.tween_property(debuff_label, "modulate:a", 0.0, 0.2)


func _update_counters() -> void:
	var lang := "en"
	if get_tree().root.has_node("GameManager"):
		lang = GameManager.selected_language

	if kill_label:
		var kills: int = GameManager.kill_count
		var limit: int = GameManager.kill_limit
		kill_label.text = ("กำจัด: %d/%d" if lang == "th" else "Kills: %d/%d") % [kills, limit]

	if time_label:
		var elapsed: float = GameManager.survival_time_elapsed
		var limit_t: float = GameManager.SURVIVAL_LIMIT
		var left := maxf(0.0, limit_t - elapsed)
		var mins := int(left) / 60
		var secs := int(left) % 60
		var time_str := "%02d:%02d" % [mins, secs]
		time_label.text = ("เวลา: " if lang == "th" else "TIME: ") + time_str


func _sync_faces() -> void:
	# ── Player ──
	if _main_player_fc and _main_player_fc.head_mesh:
		var main_head: MeshInstance3D = _main_player_fc.head_mesh
		_copy_uv(main_head, _p_eye_idx, _p_eye_mat)
		_copy_uv(main_head, _p_mouth_idx, _p_mouth_mat)

	# ── Follower ──
	if _main_follower_fc and "head_mesh" in _main_follower_fc and _main_follower_fc.head_mesh:
		var main_head: MeshInstance3D = _main_follower_fc.head_mesh
		_copy_uv(main_head, _f_eye_idx, _f_eye_mat)
		_copy_uv(main_head, _f_mouth_idx, _f_mouth_mat)


func _copy_uv(src_mesh: MeshInstance3D, surface_idx: int, dst_mat: StandardMaterial3D) -> void:
	if not dst_mat or not src_mesh:
		return
	var src_mat := src_mesh.get_active_material(surface_idx) as StandardMaterial3D
	if src_mat:
		dst_mat.uv1_offset = src_mat.uv1_offset
		dst_mat.uv1_scale = src_mat.uv1_scale


# ═══════════════════════════════════════════════════════════════════════════
#             ISOLATED PORTRAIT IDLE ANIMATION & HEAD ROTATION MIMIC
# ═══════════════════════════════════════════════════════════════════════════

func _start_portrait_idle_animation(model: Node, is_player: bool) -> void:
	if not model or not is_instance_valid(model):
		return

	var anim_player := _find_anim_player(model)
	if not anim_player:
		return

	var target_anim := ""
	if is_player:
		# Prefer Leon's pistol idle animation
		target_anim = "Gun_idle/pis_idle"
		if not anim_player.has_animation(target_anim):
			for a in anim_player.get_animation_list():
				var a_low := a.to_lower()
				if "idle" in a_low:
					target_anim = a
					break
	else:
		# Prefer Anchalee's IDLE animation
		target_anim = "IDLE "
		if not anim_player.has_animation(target_anim):
			for a in anim_player.get_animation_list():
				var a_low := a.to_lower()
				if "idle" in a_low:
					target_anim = a
					break

	if target_anim != "" and anim_player.has_animation(target_anim):
		var anim := anim_player.get_animation(target_anim)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
		anim_player.play(target_anim)


func _sync_player_head_rotation(delta: float) -> void:
	# 1. Advance portrait idle animations manually (SubViewport does not auto-tick AnimationPlayers)
	if _p_anim_player and is_instance_valid(_p_anim_player):
		if not _p_anim_player.is_playing():
			_start_portrait_idle_animation(_p_anim_player.get_parent(), true)
		_p_anim_player.advance(delta * player_idle_speed_scale)

	if _f_anim_player and is_instance_valid(_f_anim_player):
		if not _f_anim_player.is_playing():
			_start_portrait_idle_animation(_f_anim_player.get_parent(), false)
		_f_anim_player.advance(delta * follower_idle_speed_scale)

	# 2. Mimic the player's real-time head look rotation (from HeadLookAt / glance)
	# Zero bone position translation is applied — the body and camera remain 100% stationary
	if _p_src_skel and _p_dst_skel and is_instance_valid(_p_src_skel) and is_instance_valid(_p_dst_skel) and _p_head_idx != -1:
		if _p_head_rest_rot == Quaternion.IDENTITY:
			_p_head_rest_rot = _p_dst_skel.get_bone_rest(_p_head_idx).basis.get_rotation_quaternion()

		var head_rot := _p_src_skel.get_bone_pose_rotation(_p_head_idx)

		# Reduce head look-at influence by 50% when takedown or grab success (player win QTE) are active
		var is_action := _is_player_takedown_active() or _is_player_grab_success_active()
		var target_influence: float = action_head_look_influence if is_action else 1.0

		_current_head_look_influence = move_toward(_current_head_look_influence, target_influence, head_look_lerp_speed * delta)

		var final_rot := _p_head_rest_rot.slerp(head_rot, _current_head_look_influence)
		_p_dst_skel.set_bone_pose_rotation(_p_head_idx, final_rot)

	# 3. Mimic the follower's real-time head look rotation (from LookAtModifier3D / glance)
	# Zero bone position translation is applied — the body and camera remain 100% stationary
	if _f_src_skel and _f_dst_skel and is_instance_valid(_f_src_skel) and is_instance_valid(_f_dst_skel) and _f_head_idx != -1:
		if _f_head_rest_rot == Quaternion.IDENTITY:
			_f_head_rest_rot = _f_dst_skel.get_bone_rest(_f_head_idx).basis.get_rotation_quaternion()

		var f_head_rot := _f_src_skel.get_bone_pose_rotation(_f_head_idx)
		_f_dst_skel.set_bone_pose_rotation(_f_head_idx, f_head_rot)


func _is_player_takedown_active() -> bool:
	if not _player or not is_instance_valid(_player):
		return false
	var sm = _player.get_node_or_null("Statemachine")
	if sm and sm.get("current_state"):
		if sm.current_state.name == "Takedown":
			return true
	if "anim" in _player and _player.anim:
		var root_pb = _player.anim.get("parameters/playback")
		if root_pb:
			var curr := String(root_pb.get_current_node())
			if curr in ["Takedown", "TD"]:
				return true
	return false


func _is_player_grab_success_active() -> bool:
	if not _player or not is_instance_valid(_player):
		return false
	var sm = _player.get_node_or_null("Statemachine")
	if sm and sm.get("current_state"):
		if sm.current_state.name == "Grab":
			var grab_state = sm.current_state
			if "last_anim" in grab_state and grab_state.last_anim == "Grab/Win":
				return true
	if "anim" in _player and _player.anim:
		var grab_pb = _player.anim.get("parameters/Grab/playback")
		if grab_pb and String(grab_pb.get_current_node()) == "Win":
			return true
	return false


func _sync_portrait_poses(_delta: float) -> void:
	pass


func _on_camera_setting_changed() -> void:
	if not is_inside_tree():
		return

	_find_references()

	if Engine.is_editor_hint():
		_ensure_editor_preview_skeletons()

	_apply_camera_settings()

	if player_viewport:
		player_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if follower_viewport:
		follower_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if player_svc:
		player_svc.queue_redraw()
	if follower_svc:
		follower_svc.queue_redraw()


func _apply_camera_settings() -> void:
	# ── Player Portrait Camera ──
	if player_camera:
		player_camera.current = true
		player_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		player_camera.size = player_cam_size
		if camera_track_head and _p_dst_skel and is_instance_valid(_p_dst_skel) and _p_head_idx != -1:
			var head_pose: Transform3D = _p_dst_skel.get_bone_global_pose(_p_head_idx)
			var head_pos: Vector3 = _p_dst_skel.global_transform * head_pose.origin
			var face_center: Vector3 = head_pos + player_face_offset
			player_camera.position = Vector3(face_center.x, face_center.y, face_center.z - cam_distance)
			player_camera.look_at(Vector3(face_center.x, face_center.y, face_center.z), Vector3.UP)
		else:
			player_camera.position = player_cam_pos
			player_camera.look_at(player_cam_look, Vector3.UP)

	# ── Follower Portrait Camera ──
	if follower_camera:
		follower_camera.current = true
		follower_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		follower_camera.size = follower_cam_size
		if camera_track_head and _f_dst_skel and is_instance_valid(_f_dst_skel) and _f_head_idx != -1:
			var head_pose: Transform3D = _f_dst_skel.get_bone_global_pose(_f_head_idx)
			var head_pos: Vector3 = _f_dst_skel.global_transform * head_pose.origin
			var face_center: Vector3 = head_pos + follower_face_offset
			follower_camera.position = Vector3(face_center.x, face_center.y, face_center.z - cam_distance)
			follower_camera.look_at(Vector3(face_center.x, face_center.y, face_center.z), Vector3.UP)
		else:
			follower_camera.position = follower_cam_pos
			follower_camera.look_at(follower_cam_look, Vector3.UP)


func _update_portrait_cameras() -> void:
	_apply_camera_settings()


func _find_skeleton(root: Node) -> Skeleton3D:
	if not root:
		return null
	var skels := _find_all_skeletons(root)
	for s in skels:
		if s.find_bone("DEF-spine.006") != -1:
			return s
		for b in range(s.get_bone_count()):
			if "head" in s.get_bone_name(b).to_lower():
				return s
	if skels.size() > 0:
		return skels[0]
	return null


func _find_anim_player(root: Node) -> AnimationPlayer:
	if not root:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in _get_all_descendants(root):
		if child is AnimationPlayer:
			return child as AnimationPlayer
	return null


func _find_all_skeletons(root: Node) -> Array[Skeleton3D]:
	var result: Array[Skeleton3D] = []
	if not root:
		return result
	if root is Skeleton3D:
		result.append(root as Skeleton3D)
	for child in _get_all_descendants(root):
		if child is Skeleton3D:
			result.append(child as Skeleton3D)
	return result

# ═══════════════════════════════════════════════════════════════════════════
#                BACKWARD-COMPATIBILITY HOOKS
# ═══════════════════════════════════════════════════════════════════════════

func spawn_kill_projectile(zombie_3d_pos: Vector3) -> void:
	if not kill_rect or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if not camera or camera.is_position_behind(zombie_3d_pos):
		return

	var screen_pos := camera.unproject_position(zombie_3d_pos)
	var proj := Label.new()
	proj.text = "+1"
	proj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	proj.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	proj.add_theme_font_size_override("font_size", 35)
	proj.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	proj.add_theme_color_override("font_outline_color", Color.BLACK)
	proj.add_theme_constant_override("outline_size", 6)
	if _font_sub:
		proj.add_theme_font_override("font", _font_sub)

	add_child(proj)
	proj.global_position = screen_pos - Vector2(22, 18)
	proj.scale = Vector2.ZERO

	var target_pos := kill_rect.global_position + kill_rect.size * 0.5 - Vector2(22, 18)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(proj, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var fly_tween := create_tween()
	fly_tween.tween_interval(0.25)
	fly_tween.tween_property(proj, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	fly_tween.finished.connect(func():
		proj.queue_free()
		if is_instance_valid(kill_rect):
			var bounce_tween := create_tween()
			bounce_tween.tween_property(kill_rect, "scale", Vector2(1.2, 1.2), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			bounce_tween.tween_property(kill_rect, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	)


func spawn_takedown_shockwave(_zombie_3d_pos: Vector3, _custom_scale: float = 1.0) -> void:
	pass


func spawn_defeat_shockwave(_zombie_3d_pos: Vector3) -> void:
	pass

# ═══════════════════════════════════════════════════════════════════════════
#                            HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _get_all_descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_descendants(child))
	return result


func _assign_owners(root: Node) -> void:
	## Assign `root` as the owner of every descendant so that
	## scene-unique-name references like %OriginalSkeleton resolve correctly
	## inside AnimationPlayer track paths after a duplicate() call.
	for node in _get_all_descendants(root):
		node.owner = root
