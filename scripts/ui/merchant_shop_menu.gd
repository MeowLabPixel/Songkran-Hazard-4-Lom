class_name MerchantShopMenu
extends CanvasLayer

## Merchant Shop Menu
## Provides an energetic, tactile Songkran Hazard shop interface for interacting with the Water Merchant.
## Matches the visual mockups:
## 1. Slanted scrolling green checker ribbons & circular options menu (Buy, Tune, Sell) with yellow slice beam.
## 2. 2D Cosine Water shader background for deep ambiance.
## 3. Left 3D viewport featuring the absorption water shader and realistic water buoyancy bobbing for weapons.
## 4. Right-side coral-red BUY card with item slots, coin balance, and controls guide.
## 5. Foreground confirm popup with "Confirm" and "Cancle" buttons.
## 6. Enter & exit dual-door green checkerboard curtain transitions.

signal shop_opened
signal shop_closed
signal weapon_purchased(weapon_name: String, cost: int)
signal weapon_equipped(weapon_name: String)

enum ShopState {
	CLOSED,
	OPTIONS,
	BUY,
	CONFIRM
}

@export_group("Pricing & Economy")
@export var shotgun_cost: int = 50
@export var auto_equip_on_purchase: bool = true
@export var shop_items: Array[ShopItemData] = []

@export_group("Shop Bucket Layout - Selection Menu")
@export var options_bucket_window_size: Vector2 = Vector2(580, 580)
@export var options_bucket_offset: Vector2 = Vector2(0, 0)
@export var options_bucket_3d_scale: float = 1.0
@export var options_camera_fov: float = 65.0

@export_group("Shop Bucket Layout - Buy Menu")
@export var buy_bucket_window_size: Vector2 = Vector2(520, 520)
@export var buy_bucket_position: Vector2 = Vector2(40, -260)
@export var buy_bucket_3d_scale: float = 1.0
@export var buy_camera_fov: float = 65.0
@export var bucket_item_target_center: Vector3 = Vector3(-0.003, 0.505, -0.025)

@export_group("Shop Bucket Edge Cropping")
@export var enable_circular_crop: bool = false
@export var crop_corner_radius: int = 260

@export_group("State Roots")
@export var state_options: Control
@export var state_buy: Control
@export var state_confirm: Control

@export_group("Curtains & Transitions")
@export var curtain_overlay: Control
@export var curtain_left: TextureRect
@export var curtain_right: TextureRect

@export_group("Ribbons & Backgrounds")
@export var top_ribbon: TextureRect
@export var bottom_ribbon: TextureRect
@export var ribbon_bar_height: float = 36.0
@export var ribbon_transition_duration: float = 0.35
@export var background_water: ColorRect
@export var beam: CanvasItem

@export_group("Options Controls")
@export var btn_buy: Button
@export var btn_tune: Button
@export var btn_sell: Button
@export var desc_label: Label

@export_group("Buy Menu Controls")
@export var coins_label: Label
@export var shotgun_row_btn: Button
@export var shotgun_row_status: Label
@export var shotgun_pivot: Node3D
@export var status_label: Label

@export_group("Confirm Dialog Controls")
@export var confirm_prompt_label: Label
@export var confirm_cost_label: Label
@export var btn_confirm: Button
@export var btn_cancle: Button
@export var confirm_shotgun_pivot: Node3D
@export var confirm_weapon_spin_speed: float = 1.2
@export var confirm_weapon_bob_speed: float = 2.0
@export var confirm_weapon_bob_height: float = 0.025
@export var confirm_weapon_target_size: float = 1.15

# Fonts
var font_dog_bold: Font = preload("res://scenes/font/iannnnn-DOG-Bold.ttf")
var font_dog_reg: Font = preload("res://scenes/font/iannnnn-DOG-Regular.ttf")
var font_vcd_bold: Font = preload("res://scenes/font/iannnnnVCD 2007 Bold.ttf")

# Songkran Hazard Palette
const COLOR_DEEP_NAVY = Color(0.098, 0.086, 0.455, 1.0) # #191674 Comic Navy
const COLOR_SHADOW_NAVY = Color(0.0, 0.087, 0.316, 1.0) # #001651 Drop Shadow
const COLOR_BORDER_YELLOW = Color(0.987, 0.831, 0.13, 1.0) # Accent Yellow #FCE321
const COLOR_MINT_GREEN = Color(0.3, 0.95, 0.65, 1.0) # Confirm Green #4DF2A6
const COLOR_CORAL_RED = Color(0.95, 0.35, 0.38, 1.0) # Buy Card / Cancel Red #FF5757
const COLOR_WATER_BLUE = Color(0.353, 0.761, 1.0, 1.0) # Water Cyan

# State & Internals
var current_state: int = ShopState.CLOSED
var _player: CharacterBody3D = null
var _merchant: Node3D = null
var _is_open: bool = false
var _status_timer: float = 0.0
var _select_vo_timer: float = 0.0
var _buoyancy_time: float = 0.0
var _base_gun_pos: Vector3 = Vector3(0.0, 0.0, 0.0)
var _base_gun_rot: Vector3 = Vector3(0.0, 0.0, 0.0)
enum BeamState { IDLE, ENTERING, FOLLOWING, EXITING }

var _curtain_tween: Tween = null
var _is_transitioning: bool = false
var _active_hovered_btn: Button = null
var _beam_pool: Array[Dictionary] = []
var _current_voice_player: Node = null

# Option Buttons Buoyancy Baselines
var _buy_base_pos_ratio: Vector2 = Vector2(-0.4, 0.0)
var _buy_base_rot: float = -0.26529
var _tune_base_pos_ratio: Vector2 = Vector2(0.49, 0.0)
var _tune_base_rot: float = 0.132645
var _sell_base_pos_ratio: Vector2 = Vector2(-0.23, 0.0)
var _sell_base_rot: float = -0.26529
var _opt_buoyancy_time: float = 0.0

# Ribbon Transition Baselines
var _top_ribbon_base_pos: Vector2 = Vector2.ZERO
var _top_ribbon_base_rot: float = 0.0
var _bottom_ribbon_base_pos: Vector2 = Vector2.ZERO
var _bottom_ribbon_base_rot: float = 0.0
var _ribbon_tween: Tween = null

# Shared Shop Bucket & Dynamic Item List State
var _bucket_frame: PanelContainer = null
var _bucket_viewport: SubViewport = null
var _shop_inventories: Node3D = null
var _active_bucket_gun: Node3D = null
var _active_gun_base_pos: Vector3 = Vector3.ZERO
var _active_gun_base_rot: Vector3 = Vector3.ZERO
var _gun_sink_offset: float = 0.0
var _gun_sink_tilt: float = 0.0
var _gun_float_tween: Tween = null
var _confirm_menu_tween: Tween = null
var _gun_base_transforms: Dictionary = {}
var _spawned_item_models: Dictionary = {}
var _selected_item_index: int = 0
var _item_list_vbox: VBoxContainer = null
var _item_row_nodes: Array[Dictionary] = []
var _purchased_custom_items: Dictionary = {}
var _equipped_custom_item_index: int = -1

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_ensure_default_shop_items()
	_bind_nodes()
	_rebuild_shop_item_rows()
	_set_shop_viewports_active(false)
	_init_beam_pool()
	_setup_button_events()
	_apply_visual_styling()

	if btn_buy and btn_buy.get("offset_transform_position_ratio") != null:
		_buy_base_pos_ratio = btn_buy.get("offset_transform_position_ratio")
		_buy_base_rot = btn_buy.get("offset_transform_rotation")
	if btn_tune and btn_tune.get("offset_transform_position_ratio") != null:
		_tune_base_pos_ratio = btn_tune.get("offset_transform_position_ratio")
		_tune_base_rot = btn_tune.get("offset_transform_rotation")
	if btn_sell and btn_sell.get("offset_transform_position_ratio") != null:
		_sell_base_pos_ratio = btn_sell.get("offset_transform_position_ratio")
		_sell_base_rot = btn_sell.get("offset_transform_rotation")

	if shotgun_pivot:
		_base_gun_pos = shotgun_pivot.position
		_base_gun_rot = shotgun_pivot.rotation

	if top_ribbon:
		_top_ribbon_base_pos = top_ribbon.position
		_top_ribbon_base_rot = top_ribbon.rotation
	if bottom_ribbon:
		_bottom_ribbon_base_pos = bottom_ribbon.position
		_bottom_ribbon_base_rot = bottom_ribbon.rotation

func _process(delta: float) -> void:
	if not _is_open:
		return

	# Status message expiration
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0 and status_label:
			status_label.text = ""

	if _select_vo_timer > 0.0:
		_select_vo_timer -= delta

	# Option buttons water buoyancy
	if current_state == ShopState.OPTIONS:
		_opt_buoyancy_time += delta
		if btn_buy and is_instance_valid(btn_buy):
			btn_buy.set("offset_transform_position_ratio", Vector2(_buy_base_pos_ratio.x, _buy_base_pos_ratio.y + sin(_opt_buoyancy_time * 2.1) * 0.035))
			btn_buy.set("offset_transform_rotation", _buy_base_rot + sin(_opt_buoyancy_time * 1.7) * 0.025)
		if btn_tune and is_instance_valid(btn_tune):
			btn_tune.set("offset_transform_position_ratio", Vector2(_tune_base_pos_ratio.x, _tune_base_pos_ratio.y + sin(_opt_buoyancy_time * 2.4 + 1.8) * 0.035))
			btn_tune.set("offset_transform_rotation", _tune_base_rot + cos(_opt_buoyancy_time * 1.9 + 1.2) * 0.025)
		if btn_sell and is_instance_valid(btn_sell):
			btn_sell.set("offset_transform_position_ratio", Vector2(_sell_base_pos_ratio.x, _sell_base_pos_ratio.y + sin(_opt_buoyancy_time * 1.9 + 3.5) * 0.035))
			btn_sell.set("offset_transform_rotation", _sell_base_rot + sin(_opt_buoyancy_time * 2.2 + 2.5) * 0.025)

		# Keep each active/exiting beam tracking its target button's visual center while following or exiting
		for slot in _beam_pool:
			if (slot["state"] == BeamState.FOLLOWING or slot["state"] == BeamState.EXITING) and slot["target_btn"] and is_instance_valid(slot["target_btn"]):
				var b_node: Polygon2D = slot["node"]
				if b_node and is_instance_valid(b_node):
					var parent_control = b_node.get_parent() as Control
					if parent_control:
						b_node.position = _get_button_target_pos(slot["target_btn"], parent_control)

	# 3D Water Buoyancy bobbing + sinking-to-floating physics for active weapon inside bucket
	_buoyancy_time += delta
	if _active_bucket_gun and is_instance_valid(_active_bucket_gun) and _active_bucket_gun.visible:
		_active_bucket_gun.position = Vector3(
			_active_gun_base_pos.x,
			_active_gun_base_pos.y + _gun_sink_offset + sin(_buoyancy_time * 2.6) * 0.018,
			_active_gun_base_pos.z
		)
		_active_bucket_gun.rotation = Vector3(
			_active_gun_base_rot.x + _gun_sink_tilt + cos(_buoyancy_time * 2.1) * 0.03,
			_active_gun_base_rot.y,
			_active_gun_base_rot.z + sin(_buoyancy_time * 1.8) * 0.035
		)
	elif shotgun_pivot and is_instance_valid(shotgun_pivot):
		shotgun_pivot.position.y = _base_gun_pos.y + sin(_buoyancy_time * 2.6) * 0.018
		shotgun_pivot.rotation.z = _base_gun_rot.z + sin(_buoyancy_time * 1.8) * 0.035
		shotgun_pivot.rotation.x = _base_gun_rot.x + cos(_buoyancy_time * 2.1) * 0.03

	if current_state == ShopState.CONFIRM and state_confirm and state_confirm.visible and confirm_shotgun_pivot and is_instance_valid(confirm_shotgun_pivot) and confirm_shotgun_pivot.visible:
		confirm_shotgun_pivot.rotation.y = wrapf(confirm_shotgun_pivot.rotation.y + delta * confirm_weapon_spin_speed, 0.0, TAU)
		confirm_shotgun_pivot.position.y = sin(_buoyancy_time * confirm_weapon_bob_speed) * confirm_weapon_bob_height

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or _is_transitioning:
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				match current_state:
					ShopState.CONFIRM:
						_switch_state(ShopState.BUY)
					ShopState.BUY:
						_play_corner_curtain_transition(func():
							_switch_state(ShopState.OPTIONS)
						)
					ShopState.OPTIONS:
						close_shop()
			KEY_Q:
				get_viewport().set_input_as_handled()
				match current_state:
					ShopState.CONFIRM:
						_switch_state(ShopState.BUY)
					ShopState.BUY:
						_play_corner_curtain_transition(func():
							_switch_state(ShopState.OPTIONS)
						)
					ShopState.OPTIONS:
						close_shop()
			KEY_E:
				get_viewport().set_input_as_handled()
				match current_state:
					ShopState.OPTIONS:
						_on_buy_option_selected()
					ShopState.BUY:
						_on_item_row_clicked(_selected_item_index)
					ShopState.CONFIRM:
						_on_confirm_buy_pressed()
			KEY_ENTER:
				if current_state == ShopState.CONFIRM:
					get_viewport().set_input_as_handled()
					_on_confirm_buy_pressed()

func open_shop(player: CharacterBody3D, merchant: Node3D = null) -> void:
	if _is_open:
		return

	_player = player
	_merchant = merchant
	_is_open = true
	_is_transitioning = true

	_bind_nodes()
	_set_shop_viewports_active(true)

	# Play greeting voiceline immediately when player presses E to enter shop
	play_voice("Enter_Shop")

	# Connect to ItemManager coin changes
	if typeof(ItemManager) != TYPE_NIL and ItemManager.has_signal("coins_changed"):
		if not ItemManager.coins_changed.is_connected(_on_coins_changed):
			ItemManager.coins_changed.connect(_on_coins_changed)

	# Suspend player controls & reveal cursor
	if _player:
		_player.set("is_in_shop", true)
		if _player.has_method("cancel_aim"):
			_player.cancel_aim()
		var crosshair = _player.get("cross_hair")
		if crosshair and is_instance_valid(crosshair):
			crosshair.visible = false

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Keep UI hidden while camera lerps into ShopCamera so the swoop into the bucket is visible
	visible = false

	var on_cam_arrived = func():
		visible = true
		_animate_ribbons(false, true)
		_switch_state(ShopState.OPTIONS)
		_play_curtain_open(func():
			_is_transitioning = false
		)

	# Direct Merchant gaze onto customer & trigger camera lerp
	if _merchant and _merchant.has_method("enter_interaction"):
		_merchant.enter_interaction(_player, on_cam_arrived)
	else:
		on_cam_arrived.call()

	shop_opened.emit()
	print("[MerchantShop] Shop Menu opened. Customer: %s" % (player.name if player else "Unknown"))

func close_shop() -> void:
	if not _is_open or _is_transitioning:
		return

	_is_transitioning = true
	_reset_all_beams()
	play_voice("Exit_Shop")
	_play_sfx("Hover_Ui")

	# Close curtains, then hide UI, trigger camera lerp back to player, and restore controls
	_play_curtain_close(func():
		_is_open = false
		current_state = ShopState.CLOSED
		visible = false
		_set_shop_viewports_active(false)

		# Disconnect ItemManager listener
		if typeof(ItemManager) != TYPE_NIL and ItemManager.has_signal("coins_changed"):
			if ItemManager.coins_changed.is_connected(_on_coins_changed):
				ItemManager.coins_changed.disconnect(_on_coins_changed)

		var on_cam_exited = func():
			_is_transitioning = false
			# Restore player control & capture cursor
			if _player:
				_player.set("is_in_shop", false)

			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			_player = null
			_merchant = null
			shop_closed.emit()
			print("[MerchantShop] Shop Menu closed. Controls restored.")

		# Release Merchant gaze & trigger camera lerp back to player
		if _merchant and _merchant.has_method("exit_interaction"):
			_merchant.exit_interaction(on_cam_exited)
		else:
			on_cam_exited.call()
	)

func is_shop_open() -> bool:
	return _is_open

# -------------------------------------------------------------------------
# State Machine
# -------------------------------------------------------------------------
func _switch_state(new_state: int) -> void:
	var prev_state: int = current_state
	current_state = new_state
	_refresh_ui()

	if new_state != ShopState.OPTIONS:
		_reset_all_beams()

	match new_state:
		ShopState.OPTIONS:
			if _confirm_menu_tween and _confirm_menu_tween.is_valid():
				_confirm_menu_tween.kill()
			_set_screens_visible(true, false, false)
			_update_bucket_frame_layout(true)
			_hide_all_bucket_guns()
			_animate_ribbons(false)
			_on_option_hovered("BUY")
		ShopState.BUY:
			_update_bucket_frame_layout(false)
			_animate_ribbons(true)
			_try_play_select_voice()
			if prev_state == ShopState.CONFIRM and state_confirm and state_confirm.visible:
				if state_options:
					state_options.visible = false
				if state_buy:
					state_buy.visible = true
					var buy_card = state_buy.get_node_or_null("RightBuyCard") as Control
					if buy_card:
						buy_card.visible = true
				_play_confirm_menu_pop_out()
			else:
				if _confirm_menu_tween and _confirm_menu_tween.is_valid():
					_confirm_menu_tween.kill()
				_set_screens_visible(false, true, false)
				var entering_from_options: bool = (prev_state != ShopState.CONFIRM)
				_show_bucket_gun_for_item(_selected_item_index, true, 0.12 if entering_from_options else 0.0)
		ShopState.CONFIRM:
			if _confirm_menu_tween and _confirm_menu_tween.is_valid():
				_confirm_menu_tween.kill()
			# Keep Confirm Menu hidden until the bucket gun finishes popping up and disappears
			_set_screens_visible(false, true, false)
			_update_bucket_frame_layout(false)
			_animate_ribbons(true)
			_update_confirm_dialog()
			_play_gun_pickup_from_bucket_anim()

func _set_screens_visible(opt: bool, buy_screen: bool, confirm_screen: bool) -> void:
	if state_options:
		state_options.visible = opt
	if state_buy:
		state_buy.visible = buy_screen
		var buy_card = state_buy.get_node_or_null("RightBuyCard") as Control
		if buy_card:
			buy_card.visible = buy_screen
	if state_confirm:
		state_confirm.visible = confirm_screen
	if not confirm_screen and confirm_shotgun_pivot and is_instance_valid(confirm_shotgun_pivot):
		confirm_shotgun_pivot.visible = false
	if _bucket_frame and is_instance_valid(_bucket_frame):
		_bucket_frame.visible = (opt or buy_screen or confirm_screen)

# -------------------------------------------------------------------------
# Options Menu Handlers
# -------------------------------------------------------------------------
func _on_option_hovered(opt_name: String) -> void:
	_play_sfx("Hover_Ui")
	var target_btn: Button = null

	match opt_name:
		"BUY":
			target_btn = btn_buy
			if desc_label:
				desc_label.text = "Buy water gun and drying item!"
		"TUNE":
			target_btn = btn_tune
			if desc_label:
				desc_label.text = "(Under Construction)"
		"SELL":
			target_btn = btn_sell
			if desc_label:
				desc_label.text = "(Coming Soon)"

	# Shoot beam from random off-screen corner behind the hovered button
	_shoot_beam_to_button(target_btn)

func _init_beam_pool() -> void:
	if not beam or not is_instance_valid(beam):
		return

	_beam_pool.clear()
	var parent_control = beam.get_parent() as Control
	if not parent_control:
		return

	var beams: Array[Polygon2D] = []
	beams.append(beam as Polygon2D)

	# Check if Beam2 exists in CenterWindow
	var beam2 = parent_control.get_node_or_null("Beam2") as Polygon2D
	if not beam2:
		beam2 = (beam as Polygon2D).duplicate() as Polygon2D
		beam2.name = "Beam2"
		parent_control.add_child(beam2)
		parent_control.move_child(beam2, beam.get_index() + 1)
	beams.append(beam2)

	# Check if Beam3 exists in CenterWindow
	var beam3 = parent_control.get_node_or_null("Beam3") as Polygon2D
	if not beam3:
		beam3 = (beam as Polygon2D).duplicate() as Polygon2D
		beam3.name = "Beam3"
		parent_control.add_child(beam3)
		parent_control.move_child(beam3, beam2.get_index() + 1)
	beams.append(beam3)

	for b in beams:
		b.visible = false
		b.scale = Vector2(1.0, 0.001)
		b.modulate.a = 0.0
		_beam_pool.append({
			"node": b,
			"target_btn": null,
			"tween": null,
			"state": BeamState.IDLE
		})

func _reset_all_beams() -> void:
	_active_hovered_btn = null
	for slot in _beam_pool:
		if slot["tween"] and slot["tween"].is_valid():
			slot["tween"].kill()
		if slot["node"] and is_instance_valid(slot["node"]):
			slot["node"].visible = false
			slot["node"].rotation_degrees = 0.0
			slot["node"].scale = Vector2(1.0, 0.001)
			slot["node"].modulate.a = 0.0
		slot["state"] = BeamState.IDLE
		slot["target_btn"] = null

func _get_button_target_pos(btn: Button, parent: Control) -> Vector2:
	if not btn or not is_instance_valid(btn):
		return Vector2.ZERO
	var local_center: Vector2 = btn.size * 0.5
	var global_center: Vector2 = btn.get_global_transform() * local_center

	# When offset_transform is visual-only, it is not baked into get_global_transform(),
	# so we apply translation + rotation/scale around its pivot manually.
	if btn.get("offset_transform_enabled") == true and btn.get("offset_transform_visual_only") == true:
		var ratio: Vector2 = btn.get("offset_transform_position_ratio") if btn.get("offset_transform_position_ratio") != null else Vector2.ZERO
		var pos_px: Vector2 = btn.get("offset_transform_position") if btn.get("offset_transform_position") != null else Vector2.ZERO
		var rot: float = btn.get("offset_transform_rotation") if btn.get("offset_transform_rotation") != null else 0.0
		var scl: Vector2 = btn.get("offset_transform_scale") if btn.get("offset_transform_scale") != null else Vector2.ONE
		if scl == Vector2.ZERO:
			scl = Vector2.ONE
		var pivot_ratio: Vector2 = btn.get("offset_transform_pivot_ratio") if btn.get("offset_transform_pivot_ratio") != null else Vector2(0.5, 0.5)
		var pivot_px: Vector2 = btn.get("offset_transform_pivot") if btn.get("offset_transform_pivot") != null else Vector2.ZERO
		var pivot: Vector2 = pivot_px + pivot_ratio * btn.size
		var local_vis: Vector2 = pos_px + ratio * btn.size + pivot + ((local_center - pivot) * scl).rotated(rot)
		global_center = btn.get_global_transform() * local_vis

	return _control_to_local(parent, global_center)

func _get_beam_transformed_bounds(b_node: Polygon2D) -> Rect2:
	if not b_node:
		return Rect2(-500.0, -500.0, 1000.0, 1000.0)
	var poly = b_node.polygon
	var offset = b_node.offset
	if poly.is_empty():
		return Rect2(-500.0, -500.0, 1000.0, 1000.0)
	var transform_2d = Transform2D(b_node.rotation, Vector2.ZERO)
	var first_p = transform_2d * ((poly[0] + offset) * Vector2(b_node.scale.x, 1.0))
	var min_pt = first_p
	var max_pt = first_p
	for pt in poly:
		var p = transform_2d * ((pt + offset) * Vector2(b_node.scale.x, 1.0))
		min_pt.x = min(min_pt.x, p.x)
		min_pt.y = min(min_pt.y, p.y)
		max_pt.x = max(max_pt.x, p.x)
		max_pt.y = max(max_pt.y, p.y)
	return Rect2(min_pt, max_pt - min_pt)

func _control_to_local(control: Control, global_pt: Vector2) -> Vector2:
	if not control:
		return global_pt
	return control.get_global_transform().affine_inverse() * global_pt

func _shoot_beam_to_button(target_btn: Button) -> void:
	if not target_btn or not is_instance_valid(target_btn):
		return
	if _beam_pool.is_empty():
		return

	_active_hovered_btn = target_btn

	# If a beam is already following or entering this button, keep it
	for slot in _beam_pool:
		if slot["target_btn"] == target_btn and (slot["state"] == BeamState.FOLLOWING or slot["state"] == BeamState.ENTERING):
			return

	# Transition ANY other active beam (FOLLOWING or still ENTERING) to EXITING immediately
	for slot in _beam_pool:
		if slot["target_btn"] != target_btn and (slot["state"] == BeamState.FOLLOWING or slot["state"] == BeamState.ENTERING):
			_start_beam_pop_out(slot)

	# Find available beam: prefer IDLE, fallback to oldest EXITING
	var chosen_slot: Dictionary = {}
	for slot in _beam_pool:
		if slot["state"] == BeamState.IDLE:
			chosen_slot = slot
			break

	if chosen_slot.is_empty():
		for slot in _beam_pool:
			if slot["state"] == BeamState.EXITING:
				chosen_slot = slot
				break

	if chosen_slot.is_empty():
		chosen_slot = _beam_pool[0]

	# Kill any running tween on the chosen slot
	if chosen_slot["tween"] and chosen_slot["tween"].is_valid():
		chosen_slot["tween"].kill()

	chosen_slot["target_btn"] = target_btn
	chosen_slot["state"] = BeamState.ENTERING

	var b_node: Polygon2D = chosen_slot["node"]
	b_node.visible = true

	var parent_control = b_node.get_parent() as Control
	var target_pos = _get_button_target_pos(target_btn, parent_control)

	# Dynamic random flip: 50% chance for ANY button (BUY, TUNE, SELL), rotation stays 0.0
	var is_flipped: bool = (randf() < 0.5)
	b_node.scale.x = -1.0 if is_flipped else 1.0
	b_node.rotation_degrees = 0.0

	# Calculate dynamic spawn bounds relative to pivot so no edge enters the 1280x720 screen
	var bounds = _get_beam_transformed_bounds(b_node)
	var min_x = bounds.position.x
	var max_x = bounds.position.x + bounds.size.x
	var min_y = bounds.position.y
	var max_y = bounds.position.y + bounds.size.y

	var margin = 100.0
	var scr_w = 1280.0
	var scr_h = 720.0

	var left_x = randf_range(-margin - max_x - 300.0, -margin - max_x)
	var right_x = randf_range(scr_w + margin - min_x, scr_w + margin - min_x + 300.0)

	var top_y = randf_range(-margin - max_y - 250.0, -margin - max_y)
	var bottom_y = randf_range(scr_h + margin - min_y, scr_h + margin - min_y + 250.0)
	var mid_y = randf_range(150.0, 550.0)

	var left_corners = [
		Vector2(left_x, top_y),
		Vector2(left_x, bottom_y),
		Vector2(left_x, mid_y)
	]
	var right_corners = [
		Vector2(right_x, top_y),
		Vector2(right_x, bottom_y),
		Vector2(right_x, mid_y)
	]
	var all_corners = left_corners + right_corners
	var global_spawn: Vector2 = all_corners[randi() % all_corners.size()]
	var spawn_pos: Vector2 = _control_to_local(parent_control, global_spawn)

	b_node.position = spawn_pos
	b_node.scale.y = 0.001
	b_node.modulate.a = 0.2

	var tw = create_tween().set_parallel(true)
	chosen_slot["tween"] = tw
	tw.tween_property(b_node, "position", target_pos, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(b_node, "scale:y", 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b_node, "modulate:a", 1.0, 0.08)
	tw.chain().tween_callback(func():
		if chosen_slot["state"] == BeamState.ENTERING:
			chosen_slot["state"] = BeamState.FOLLOWING
	)

func _start_beam_pop_out(slot: Dictionary) -> void:
	if slot.is_empty() or not slot["node"] or not is_instance_valid(slot["node"]):
		return
	var b_node: Polygon2D = slot["node"]
	if not b_node.visible:
		slot["state"] = BeamState.IDLE
		slot["target_btn"] = null
		return

	if slot["tween"] and slot["tween"].is_valid():
		slot["tween"].kill()

	slot["state"] = BeamState.EXITING

	var tw = create_tween().set_parallel(true)
	slot["tween"] = tw
	# Y-scale reverse pop-out: TRANS_BACK with EASE_IN overshoots scale.y up to ~1.15 before snapping down to 0.001
	tw.tween_property(b_node, "scale:y", 0.001, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(b_node, "modulate:a", 0.0, 0.10)
	tw.chain().tween_callback(func():
		b_node.visible = false
		b_node.rotation_degrees = 0.0
		b_node.scale = Vector2(1.0, 0.001)
		slot["state"] = BeamState.IDLE
		slot["target_btn"] = null
	)

func _on_option_unhovered(btn: Button) -> void:
	if _active_hovered_btn == btn:
		call_deferred("_check_unhover_despawn", btn)

func _check_unhover_despawn(btn: Button) -> void:
	if _active_hovered_btn == btn and current_state == ShopState.OPTIONS:
		_active_hovered_btn = null
		for slot in _beam_pool:
			if slot["target_btn"] == btn and (slot["state"] == BeamState.FOLLOWING or slot["state"] == BeamState.ENTERING):
				_start_beam_pop_out(slot)

func _on_buy_option_selected() -> void:
	if _is_transitioning:
		return
	_play_sfx("Hover_Ui")
	_play_corner_curtain_transition(func():
		_switch_state(ShopState.BUY)
	)

func _on_tune_option_selected() -> void:
	_play_sfx("Hover_Ui")
	_set_status("Tuning is currently under construction!", COLOR_BORDER_YELLOW)

func _on_sell_option_selected() -> void:
	_play_sfx("Hover_Ui")
	_set_status("Selling will be available soon!", COLOR_BORDER_YELLOW)

# -------------------------------------------------------------------------
# Buy Menu Handlers (Dynamic Shop Item List)
# -------------------------------------------------------------------------
func _ensure_default_shop_items() -> void:
	if not shop_items.is_empty():
		return

	var item_shotgun := ShopItemData.new()
	item_shotgun.item_name = "Water Splash Gun"
	item_shotgun.item_stats = "Heavy spread blast | High soak capacity"
	item_shotgun.price = shotgun_cost
	item_shotgun.gun_index = 1
	item_shotgun.model_scene = load("res://GunSystem/Scene/WaterGun/shotgun.tscn") as PackedScene
	item_shotgun.bucket_position = Vector3(0.0, 0.507422, -0.02)
	item_shotgun.bucket_rotation_degrees = Vector3(-84.8, 94.0, -4.0)
	item_shotgun.bucket_scale = Vector3(0.455, 0.455, 0.455)
	shop_items.append(item_shotgun)

	var item_sniper := ShopItemData.new()
	item_sniper.item_name = "Pressure Sniper Rifle"
	item_sniper.item_stats = "Long-range precision jet | High pressure"
	item_sniper.price = 80
	item_sniper.gun_index = 2
	item_sniper.model_scene = load("res://GunSystem/Scene/WaterGun/sniper.tscn") as PackedScene
	item_sniper.bucket_position = Vector3(0.0, 0.485, -0.02)
	item_sniper.bucket_rotation_degrees = Vector3(-86.5, -119.0, 0.0)
	item_sniper.bucket_scale = Vector3(0.45, 0.45, 0.45)
	shop_items.append(item_sniper)

func _get_shop_item(index: int) -> ShopItemData:
	_ensure_default_shop_items()
	if index >= 0 and index < shop_items.size():
		return shop_items[index]
	if not shop_items.is_empty():
		return shop_items[0]
	return null

func _is_item_unlocked(index: int, item: ShopItemData) -> bool:
	if not item:
		return false
	if _player:
		var gc: GunController = _player.get("gun_controller") as GunController
		if gc and item.gun_index >= 0 and item.gun_index < gc.unlocked_guns.size():
			return gc.unlocked_guns[item.gun_index]
	return _purchased_custom_items.get(index, false) == true

func _is_item_equipped(index: int, item: ShopItemData) -> bool:
	if not _is_item_unlocked(index, item):
		return false
	if _player and item:
		var gc: GunController = _player.get("gun_controller") as GunController
		if gc and item.gun_index >= 0 and item.gun_index < gc.unlocked_guns.size():
			return gc.current_gun_index == item.gun_index
	return _equipped_custom_item_index == index

func _on_item_row_hovered(index: int) -> void:
	_play_sfx("Hover_Ui")
	if _selected_item_index != index:
		_selected_item_index = index
		_refresh_ui()
		if current_state == ShopState.BUY:
			_show_bucket_gun_for_item(_selected_item_index, true, 0.0)

func _on_item_row_clicked(index: int) -> void:
	var switched_item: bool = (_selected_item_index != index)
	_selected_item_index = index
	if switched_item and current_state == ShopState.BUY:
		_show_bucket_gun_for_item(_selected_item_index, true, 0.0)
	_refresh_ui()

	var item: ShopItemData = _get_shop_item(index)
	if not item:
		return

	var is_unlocked: bool = _is_item_unlocked(index, item)
	var is_equipped: bool = _is_item_equipped(index, item)

	if is_equipped:
		_set_status("%s IS ALREADY EQUIPPED!" % item.item_name.to_upper(), COLOR_MINT_GREEN)
		_play_sfx("Hover_Ui")
		return
	elif is_unlocked:
		if _player:
			var gc: GunController = _player.get("gun_controller") as GunController
			if gc and item.gun_index >= 0 and item.gun_index < gc.unlocked_guns.size():
				gc.switch_gun(item.gun_index)
				_player.set("curr_gun_index", item.gun_index)
			else:
				_equipped_custom_item_index = index
		else:
			_equipped_custom_item_index = index
		weapon_equipped.emit(item.item_name)
		_play_sfx("Superpump_Duration_End")
		_set_status("%s EQUIPPED!" % item.item_name.to_upper(), COLOR_MINT_GREEN)
		_refresh_ui()
		return

	# If locked, open Confirm Buy Screen for this item
	_try_play_select_voice(true)
	_switch_state(ShopState.CONFIRM)

func _on_shotgun_row_clicked() -> void:
	_on_item_row_clicked(_selected_item_index)

# -------------------------------------------------------------------------
# Confirm Buy Screen Handlers
# -------------------------------------------------------------------------
func _update_confirm_dialog() -> void:
	var item: ShopItemData = _get_shop_item(_selected_item_index)
	var item_title: String = item.item_name if item else "Water Splash Gun"
	var item_price: int = item.price if item else shotgun_cost

	var coins = ItemManager.get_coins() if typeof(ItemManager) != TYPE_NIL else 0
	if confirm_prompt_label:
		confirm_prompt_label.text = "Buy %s?" % item_title
	if confirm_cost_label:
		var remaining = coins - item_price
		confirm_cost_label.text = "Price: %d Coins  |  Remaining After: %d Coins" % [item_price, remaining]

	_update_confirm_preview_model(item)

func _update_confirm_preview_model(item: ShopItemData) -> void:
	if not confirm_shotgun_pivot or not is_instance_valid(confirm_shotgun_pivot):
		return
	if not item or not item.model_scene:
		return

	# Immediately remove old preview children before freeing so they don't linger
	for child in confirm_shotgun_pivot.get_children():
		confirm_shotgun_pivot.remove_child(child)
		child.queue_free()

	var model_inst = item.model_scene.instantiate() as Node3D
	if model_inst:
		# Weapon scene roots (shotgun.tscn, sniper.tscn) have visible = false by default; make visible for preview
		model_inst.visible = true
		model_inst.set_process(false)
		model_inst.set_physics_process(false)
		model_inst.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		confirm_shotgun_pivot.add_child(model_inst)

		# Auto-fit scale if visual dimension exceeds target size so long weapons never clip
		var local_aabb: AABB = _get_combined_mesh_aabb(model_inst)
		var max_dim: float = maxf(local_aabb.size.x, maxf(local_aabb.size.y, local_aabb.size.z))
		if max_dim > confirm_weapon_target_size and max_dim > 0.001:
			var scale_factor: float = confirm_weapon_target_size / max_dim
			model_inst.scale = Vector3.ONE * scale_factor

		# Offset model position (accounting for basis rotation & scale) so its visual center sits at Vector3.ZERO
		model_inst.position = _get_aabb_centered_position(model_inst, Vector3.ZERO)

		# Always reset pivot rotation & position on entry, and keep hidden until bucket gun disappears
		confirm_shotgun_pivot.rotation = Vector3.ZERO
		confirm_shotgun_pivot.position = Vector3.ZERO
		confirm_shotgun_pivot.visible = false

func _on_confirm_buy_pressed() -> void:
	var item: ShopItemData = _get_shop_item(_selected_item_index)
	if not item:
		_switch_state(ShopState.BUY)
		return

	var item_price: int = item.price
	var current_coins = ItemManager.get_coins() if typeof(ItemManager) != TYPE_NIL else 0
	if current_coins < item_price:
		_set_status("NOT ENOUGH COINS! NEED %d (HAVE %d)" % [item_price, current_coins], Color(1.0, 0.4, 0.4))
		_play_sfx("zombie_melee_hit")
		play_voice("Buy_Fail")
		_switch_state(ShopState.BUY)
		return

	# Deduct coins
	if typeof(ItemManager) != TYPE_NIL:
		var spent = ItemManager.spend_coins(item_price)
		if not spent:
			_set_status("Purchase failed: Transaction rejected.", Color(1.0, 0.4, 0.4))
			_switch_state(ShopState.BUY)
			return

	# Unlock weapon in GunController (or custom item registry)
	var gc: GunController = _player.get("gun_controller") as GunController if _player else null
	if gc and item.gun_index >= 0 and item.gun_index < gc.unlocked_guns.size():
		gc.unlock_gun(item.gun_index)
		if auto_equip_on_purchase:
			gc.switch_gun(item.gun_index)
			_player.set("curr_gun_index", item.gun_index)
	else:
		_purchased_custom_items[_selected_item_index] = true
		if auto_equip_on_purchase:
			_equipped_custom_item_index = _selected_item_index

	_play_sfx("Superpump_Ready_FullAir")
	play_voice("Buy_Success")
	_set_status("PURCHASED %s FOR %d COINS!" % [item.item_name.to_upper(), item_price], COLOR_BORDER_YELLOW)
	weapon_purchased.emit(item.item_name, item_price)

	# Return to Buy menu with status updated
	_switch_state(ShopState.BUY)

func _on_cancle_pressed() -> void:
	_play_sfx("Hover_Ui")
	_switch_state(ShopState.BUY)

# -------------------------------------------------------------------------
# Curtain Animations
# -------------------------------------------------------------------------
func _play_curtain_open(callback: Callable = Callable()) -> void:
	if not curtain_overlay or not curtain_left or not curtain_right:
		if callback.is_valid():
			callback.call()
		return

	curtain_overlay.visible = true
	var vp_size = get_viewport().get_visible_rect().size
	var half_w = vp_size.x * 0.5

	curtain_left.size = Vector2(half_w, vp_size.y)
	curtain_right.size = Vector2(half_w, vp_size.y)
	curtain_left.position = Vector2(0.0, 0.0)
	curtain_right.position = Vector2(half_w, 0.0)

	if _curtain_tween and _curtain_tween.is_valid():
		_curtain_tween.kill()

	_curtain_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_curtain_tween.tween_property(curtain_left, "position:x", -half_w, 0.4)
	_curtain_tween.tween_property(curtain_right, "position:x", vp_size.x, 0.4)

	_curtain_tween.chain().tween_callback(func():
		curtain_overlay.visible = false
		if callback.is_valid():
			callback.call()
	)

func _play_curtain_close(callback: Callable = Callable()) -> void:
	if not curtain_overlay or not curtain_left or not curtain_right:
		if callback.is_valid():
			callback.call()
		return

	curtain_overlay.visible = true
	var vp_size = get_viewport().get_visible_rect().size
	var half_w = vp_size.x * 0.5

	curtain_left.size = Vector2(half_w, vp_size.y)
	curtain_right.size = Vector2(half_w, vp_size.y)
	curtain_left.position = Vector2(-half_w, 0.0)
	curtain_right.position = Vector2(vp_size.x, 0.0)

	if _curtain_tween and _curtain_tween.is_valid():
		_curtain_tween.kill()

	_curtain_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_curtain_tween.tween_property(curtain_left, "position:x", 0.0, 0.35)
	_curtain_tween.tween_property(curtain_right, "position:x", half_w, 0.35)

	_curtain_tween.chain().tween_callback(func():
		if callback.is_valid():
			callback.call()
	)

func _play_corner_curtain_transition(on_covered: Callable, on_finished: Callable = Callable()) -> void:
	if not curtain_overlay or not curtain_left or not curtain_right:
		if on_covered.is_valid():
			on_covered.call()
		if on_finished.is_valid():
			on_finished.call()
		return

	if _curtain_tween and _curtain_tween.is_valid():
		_curtain_tween.kill()

	_is_transitioning = true
	curtain_overlay.visible = true

	var vp_size = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280.0, 720.0)
	var center = vp_size * 0.5

	# Screen diagonal angle connecting bottom-left (0, H) to top-right (W, 0)
	var theta = atan2(-vp_size.y, vp_size.x)
	var dir_seam = Vector2(cos(theta), sin(theta))
	var dir_norm = Vector2(-sin(theta), cos(theta)) # Points toward bottom-right

	# Generous dimensions so rotated curtains cover all corners
	var length = 2400.0
	var depth = 1400.0
	var travel_dist = 900.0

	curtain_left.rotation = theta
	curtain_right.rotation = theta
	curtain_left.pivot_offset = Vector2.ZERO
	curtain_right.pivot_offset = Vector2.ZERO
	curtain_left.size = Vector2(length, depth)
	curtain_right.size = Vector2(length, depth)

	# Closed positions meeting flush along the diagonal seam line through center
	var tl_closed = center - (length * 0.5) * dir_seam - depth * dir_norm
	var br_closed = center - (length * 0.5) * dir_seam

	# Open positions off-screen top-left and bottom-right
	var tl_open = tl_closed - travel_dist * dir_norm
	var br_open = br_closed + travel_dist * dir_norm

	curtain_left.position = tl_open
	curtain_right.position = br_open

	_curtain_tween = create_tween().set_trans(Tween.TRANS_CUBIC)

	# 1. Close: slide along perpendicular normal until diagonal edges meet at center seam
	_curtain_tween.set_parallel(true).set_ease(Tween.EASE_OUT)
	_curtain_tween.tween_property(curtain_left, "position", tl_closed, 0.28)
	_curtain_tween.tween_property(curtain_right, "position", br_closed, 0.28)

	# 2. Midpoint callback behind closed diagonal seam
	_curtain_tween.chain().tween_callback(func():
		if on_covered.is_valid():
			on_covered.call()
	)

	# 3. Open: retract back diagonally to top-left and bottom-right
	_curtain_tween.chain().set_parallel(true).set_ease(Tween.EASE_IN_OUT)
	_curtain_tween.tween_property(curtain_left, "position", tl_open, 0.28)
	_curtain_tween.tween_property(curtain_right, "position", br_open, 0.28)

	# 4. Cleanup & restore standard upright split for normal shop open/close
	_curtain_tween.chain().tween_callback(func():
		curtain_overlay.visible = false
		_is_transitioning = false

		curtain_left.rotation = 0.0
		curtain_right.rotation = 0.0
		var half_w = vp_size.x * 0.5
		curtain_left.size = Vector2(half_w, vp_size.y)
		curtain_right.size = Vector2(half_w, vp_size.y)
		curtain_left.position = Vector2(0.0, 0.0)
		curtain_right.position = Vector2(half_w, 0.0)

		if on_finished.is_valid():
			on_finished.call()
	)

# -------------------------------------------------------------------------
# Ribbon Transitions (Slanted Options <-> Horizontal Movie Bars)
# -------------------------------------------------------------------------
func _animate_ribbons(to_movie_bars: bool, immediate: bool = false) -> void:
	if not top_ribbon or not bottom_ribbon:
		return

	if _ribbon_tween and _ribbon_tween.is_valid():
		_ribbon_tween.kill()

	var vp_size = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280.0, 720.0)

	var target_top_pos: Vector2
	var target_top_rot: float
	var target_bot_pos: Vector2
	var target_bot_rot: float

	if to_movie_bars:
		# Horizontal movie letterbox bars framing the screen top & bottom
		target_top_rot = 0.0
		target_top_pos = Vector2((vp_size.x - top_ribbon.size.x) * 0.5, ribbon_bar_height - top_ribbon.size.y)

		target_bot_rot = 0.0
		target_bot_pos = Vector2((vp_size.x - bottom_ribbon.size.x) * 0.5, vp_size.y - ribbon_bar_height)
	else:
		# Return to original slanted Options Menu transforms
		target_top_rot = _top_ribbon_base_rot
		target_top_pos = _top_ribbon_base_pos

		target_bot_rot = _bottom_ribbon_base_rot
		target_bot_pos = _bottom_ribbon_base_pos

	if immediate:
		top_ribbon.position = target_top_pos
		top_ribbon.rotation = target_top_rot
		bottom_ribbon.position = target_bot_pos
		bottom_ribbon.rotation = target_bot_rot
		return

	_ribbon_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ribbon_tween.tween_property(top_ribbon, "position", target_top_pos, ribbon_transition_duration)
	_ribbon_tween.tween_property(top_ribbon, "rotation", target_top_rot, ribbon_transition_duration)
	_ribbon_tween.tween_property(bottom_ribbon, "position", target_bot_pos, ribbon_transition_duration)
	_ribbon_tween.tween_property(bottom_ribbon, "rotation", target_bot_rot, ribbon_transition_duration)

# -------------------------------------------------------------------------
# Audio & Status Helpers
# -------------------------------------------------------------------------
func play_voice(event_name: String) -> void:
	if _merchant and _merchant.has_method("play_merchant_voice"):
		_current_voice_player = _merchant.play_merchant_voice(event_name)
	elif typeof(SoundManager) != TYPE_NIL:
		if _current_voice_player and is_instance_valid(_current_voice_player):
			if _current_voice_player.has_method("stop"):
				_current_voice_player.stop()
			_current_voice_player.queue_free()
			_current_voice_player = null
		if SoundManager.has_method("play_2d"):
			_current_voice_player = SoundManager.play_2d(event_name)

func _try_play_select_voice(force: bool = false) -> void:
	if force or _select_vo_timer <= 0.0:
		_select_vo_timer = 4.0
		play_voice("Buy_Menu_Select")

func _play_sfx(event_name: String) -> void:
	if typeof(SoundManager) != TYPE_NIL and SoundManager.has_method("play_2d"):
		SoundManager.play_2d(event_name)

func _set_status(msg: String, color: Color) -> void:
	if status_label:
		status_label.text = msg
		status_label.add_theme_color_override("font_color", color)
		_status_timer = 3.5

func _on_coins_changed(_new_total: int) -> void:
	_refresh_ui()

# -------------------------------------------------------------------------
# UI Refresh & Binding
# -------------------------------------------------------------------------
func _refresh_ui() -> void:
	_bind_nodes()
	_ensure_default_shop_items()
	if _item_row_nodes.size() != shop_items.size():
		_rebuild_shop_item_rows()

	var coins = ItemManager.get_coins() if typeof(ItemManager) != TYPE_NIL else 0
	if coins_label:
		coins_label.text = "🪙 %d" % coins

	for i in range(_item_row_nodes.size()):
		var row_info: Dictionary = _item_row_nodes[i]
		var item: ShopItemData = _get_shop_item(i)
		if not item:
			continue

		var name_lbl: Label = row_info.get("name_label") as Label
		var stats_lbl: Label = row_info.get("stats_label") as Label
		var badge_lbl: Label = row_info.get("badge_label") as Label
		var row_panel: PanelContainer = row_info.get("panel") as PanelContainer

		if name_lbl:
			name_lbl.text = item.item_name
			var is_sel: bool = (i == _selected_item_index)
			name_lbl.add_theme_color_override("font_color", COLOR_BORDER_YELLOW if is_sel else Color.WHITE)
		if stats_lbl:
			stats_lbl.text = item.item_stats

		if row_panel and is_instance_valid(row_panel):
			row_panel.modulate = Color(1.08, 1.08, 1.08, 1.0) if (i == _selected_item_index) else Color(0.92, 0.92, 0.96, 0.95)

		if badge_lbl:
			var is_unlocked: bool = _is_item_unlocked(i, item)
			var is_equipped: bool = _is_item_equipped(i, item)
			if is_equipped:
				badge_lbl.text = "✓ EQUIPPED"
				badge_lbl.add_theme_color_override("font_color", COLOR_MINT_GREEN)
			elif is_unlocked:
				badge_lbl.text = "EQUIP"
				badge_lbl.add_theme_color_override("font_color", COLOR_WATER_BLUE)
			else:
				badge_lbl.text = "🪙 %d" % item.price
				if coins >= item.price:
					badge_lbl.add_theme_color_override("font_color", COLOR_BORDER_YELLOW)
				else:
					badge_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))

func _rebuild_shop_item_rows() -> void:
	if not _item_list_vbox or not is_instance_valid(_item_list_vbox):
		return

	_ensure_default_shop_items()

	var template_row: PanelContainer = _item_list_vbox.get_node_or_null("ShotgunRow") as PanelContainer
	if not template_row:
		for child in _item_list_vbox.get_children():
			if child is PanelContainer:
				template_row = child
				break
	if not template_row:
		return

	var base_row_copy: PanelContainer = template_row.duplicate() as PanelContainer

	for child in _item_list_vbox.get_children():
		_item_list_vbox.remove_child(child)
		child.queue_free()

	_item_row_nodes.clear()

	for i in range(shop_items.size()):
		var item: ShopItemData = shop_items[i]
		var row: PanelContainer = base_row_copy.duplicate() as PanelContainer
		row.name = "ShopItemRow_%d" % i
		row.visible = true
		_item_list_vbox.add_child(row)

		var name_lbl := row.get_node_or_null("Margin/HBox/ItemInfoVBox/ItemName") as Label
		var stats_lbl := row.get_node_or_null("Margin/HBox/ItemInfoVBox/ItemStats") as Label
		var badge_lbl := row.get_node_or_null("Margin/HBox/StatusBadge/BadgeLabel") as Label
		var row_btn := row.get_node_or_null("RowButton") as Button

		if name_lbl and item:
			name_lbl.text = item.item_name
		if stats_lbl and item:
			stats_lbl.text = item.item_stats
		if badge_lbl and item:
			badge_lbl.text = "🪙 %d" % item.price

		if row_btn:
			var idx: int = i
			row_btn.pressed.connect(func(): _on_item_row_clicked(idx))
			row_btn.mouse_entered.connect(func(): _on_item_row_hovered(idx))

		if i == 0:
			shotgun_row_btn = row_btn
			shotgun_row_status = badge_lbl

		_item_row_nodes.append({
			"panel": row,
			"name_label": name_lbl,
			"stats_label": stats_lbl,
			"badge_label": badge_lbl,
			"button": row_btn
		})

	base_row_copy.free()

func _isolate_viewport_3d(vp: SubViewport) -> void:
	if not vp:
		return
	vp.own_world_3d = true
	vp.transparent_bg = true
	# Ensure the viewport has its own isolated World3D instance so lights/cameras never affect the main game
	if get_viewport() and vp.find_world_3d() == get_viewport().find_world_3d():
		vp.world_3d = World3D.new()

func _set_shop_viewports_active(active: bool) -> void:
	var buy_svc_vp = _bucket_viewport
	if not buy_svc_vp:
		buy_svc_vp = get_node_or_null("LeftCircularFrame/TurntableSVC/TurntableViewport") as SubViewport
	if not buy_svc_vp:
		buy_svc_vp = get_node_or_null("StateRoot_BuyMenu/LeftCircularFrame/TurntableSVC/TurntableViewport") as SubViewport
	if buy_svc_vp:
		buy_svc_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		var dir_light = buy_svc_vp.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
		if dir_light:
			dir_light.visible = active

	var confirm_svc_vp = get_node_or_null("StateRoot_Confirm/ConfirmCard/Margin/ConfirmVBox/WeaponPreviewFrame/TurntableSVC/TurntableViewport") as SubViewport
	if confirm_svc_vp:
		confirm_svc_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		var cam = confirm_svc_vp.find_child("Camera3D", true, false) as Camera3D
		if cam:
			cam.current = true
		var dir_light = confirm_svc_vp.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
		if dir_light:
			dir_light.visible = active

func _bind_nodes() -> void:
	if not state_options:
		state_options = get_node_or_null("StateRoot_Options") as Control
	if not state_buy:
		state_buy = get_node_or_null("StateRoot_BuyMenu") as Control
	if not state_confirm:
		state_confirm = get_node_or_null("StateRoot_Confirm") as Control

	# Ensure CenterWindow has an empty panel background so the centered 3D Shop Bucket replaces it
	var center_win = get_node_or_null("StateRoot_Options/CenterWindow") as PanelContainer
	if center_win:
		center_win.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	# Bind and promote LeftCircularFrame to root so the Shop Bucket is shared between OPTIONS (center) and BUY (left)
	if not _bucket_frame or not is_instance_valid(_bucket_frame):
		_bucket_frame = get_node_or_null("LeftCircularFrame") as PanelContainer
		if not _bucket_frame:
			_bucket_frame = get_node_or_null("StateRoot_BuyMenu/LeftCircularFrame") as PanelContainer
	if _bucket_frame and is_instance_valid(_bucket_frame):
		_bucket_frame.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		_bucket_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bucket_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var svc = _bucket_frame.get_node_or_null("TurntableSVC") as SubViewportContainer
		if svc:
			svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _bucket_frame.get_parent() != self:
			if _bucket_frame.get_parent():
				_bucket_frame.get_parent().remove_child(_bucket_frame)
			add_child(_bucket_frame)
			if state_options:
				move_child(_bucket_frame, state_options.get_index())

	if not curtain_overlay:
		curtain_overlay = get_node_or_null("CurtainOverlay") as Control
	if not curtain_left:
		curtain_left = get_node_or_null("CurtainOverlay/CurtainLeft") as TextureRect
	if not curtain_right:
		curtain_right = get_node_or_null("CurtainOverlay/CurtainRight") as TextureRect

	if not top_ribbon:
		top_ribbon = get_node_or_null("TopRibbon") as TextureRect
	if not bottom_ribbon:
		bottom_ribbon = get_node_or_null("BottomRibbon") as TextureRect
	if not background_water:
		background_water = get_node_or_null("BackgroundWater") as ColorRect
	if not beam:
		beam = get_node_or_null("StateRoot_Options/CenterWindow/Beam") as CanvasItem
		if not beam:
			beam = get_node_or_null("StateRoot_Options/CenterWindow/YellowBeam") as CanvasItem

	if not btn_buy:
		btn_buy = get_node_or_null("StateRoot_Options/CenterWindow/OptionsVBox/Btn_Buy") as Button
	if not btn_tune:
		btn_tune = get_node_or_null("StateRoot_Options/CenterWindow/OptionsVBox/Btn_Tune") as Button
	if not btn_sell:
		btn_sell = get_node_or_null("StateRoot_Options/CenterWindow/OptionsVBox/Btn_Sell") as Button
	if not desc_label:
		desc_label = get_node_or_null("StateRoot_Options/DescriptionCard/Margin/DescLabel") as Label

	if not coins_label:
		coins_label = get_node_or_null("StateRoot_BuyMenu/RightBuyCard/Margin/ContentVBox/HeaderHBox/CoinBadge/Margin/CoinLabel") as Label
	if not _item_list_vbox:
		_item_list_vbox = get_node_or_null("StateRoot_BuyMenu/RightBuyCard/Margin/ContentVBox/ItemListVBox") as VBoxContainer

	if _bucket_frame and not _bucket_viewport:
		_bucket_viewport = _bucket_frame.get_node_or_null("TurntableSVC/TurntableViewport") as SubViewport
	if _bucket_viewport:
		_isolate_viewport_3d(_bucket_viewport)
		_setup_shop_bucket_viewport(_bucket_viewport)

	var confirm_svc_vp = get_node_or_null("StateRoot_Confirm/ConfirmCard/Margin/ConfirmVBox/WeaponPreviewFrame/TurntableSVC/TurntableViewport") as SubViewport
	if confirm_svc_vp:
		_isolate_viewport_3d(confirm_svc_vp)

	if not _shop_inventories and _bucket_viewport:
		_shop_inventories = _bucket_viewport.find_child("Shop Inventories", true, false) as Node3D
	if not shotgun_pivot and _bucket_viewport:
		shotgun_pivot = _shop_inventories
		if not shotgun_pivot:
			shotgun_pivot = _bucket_viewport.get_node_or_null("ShotgunPivot") as Node3D

	if shotgun_pivot and _base_gun_pos == Vector3.ZERO:
		_base_gun_pos = shotgun_pivot.position
		_base_gun_rot = shotgun_pivot.rotation

	if not status_label:
		status_label = get_node_or_null("StateRoot_BuyMenu/RightBuyCard/Margin/ContentVBox/StatusLabel") as Label

	if not confirm_prompt_label:
		confirm_prompt_label = get_node_or_null("StateRoot_Confirm/ConfirmCard/Margin/ConfirmVBox/PromptTitle") as Label
	if not confirm_cost_label:
		confirm_cost_label = get_node_or_null("StateRoot_Confirm/ConfirmCard/Margin/ConfirmVBox/CostSubtitle") as Label
	if not btn_confirm:
		btn_confirm = get_node_or_null("StateRoot_Confirm/ConfirmCard/Margin/ConfirmVBox/ButtonHBox/ConfirmButton") as Button
	if not btn_cancle:
		btn_cancle = get_node_or_null("StateRoot_Confirm/ConfirmCard/Margin/ConfirmVBox/ButtonHBox/CancleButton") as Button
	if not confirm_shotgun_pivot:
		confirm_shotgun_pivot = get_node_or_null("StateRoot_Confirm/ConfirmCard/Margin/ConfirmVBox/WeaponPreviewFrame/TurntableSVC/TurntableViewport/ShotgunPivot") as Node3D

func _update_bucket_frame_layout(in_options: bool) -> void:
	if not _bucket_frame or not is_instance_valid(_bucket_frame):
		return

	# Handle Edge Cropping
	if enable_circular_crop:
		_bucket_frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 1)
		sb.set_corner_radius_all(crop_corner_radius)
		_bucket_frame.add_theme_stylebox_override("panel", sb)
	else:
		_bucket_frame.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		_bucket_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var bucket_cam = _bucket_viewport.find_child("ShopCamera", true, false) as Camera3D if _bucket_viewport else null
	var bucket_root = _bucket_viewport.find_child("Blue Bucket", true, false) as Node3D if _bucket_viewport else null

	if in_options:
		# Center of the screen behind BUY / TUNE / SELL options and yellow slice beams
		_bucket_frame.anchor_left = 0.5
		_bucket_frame.anchor_top = 0.5
		_bucket_frame.anchor_right = 0.5
		_bucket_frame.anchor_bottom = 0.5
		var half_sz = options_bucket_window_size * 0.5
		_bucket_frame.offset_left = -half_sz.x + options_bucket_offset.x
		_bucket_frame.offset_top = -half_sz.y + options_bucket_offset.y
		_bucket_frame.offset_right = half_sz.x + options_bucket_offset.x
		_bucket_frame.offset_bottom = half_sz.y + options_bucket_offset.y
		if _bucket_viewport:
			_bucket_viewport.size = Vector2i(options_bucket_window_size)
		if bucket_cam:
			bucket_cam.fov = options_camera_fov
		if bucket_root:
			bucket_root.scale = Vector3.ONE * options_bucket_3d_scale
	else:
		# Left preview slot in Buy Menu next to RightBuyCard
		_bucket_frame.anchor_left = 0.0
		_bucket_frame.anchor_top = 0.5
		_bucket_frame.anchor_right = 0.0
		_bucket_frame.anchor_bottom = 0.5
		_bucket_frame.offset_left = buy_bucket_position.x
		_bucket_frame.offset_top = buy_bucket_position.y
		_bucket_frame.offset_right = buy_bucket_position.x + buy_bucket_window_size.x
		_bucket_frame.offset_bottom = buy_bucket_position.y + buy_bucket_window_size.y
		if _bucket_viewport:
			_bucket_viewport.size = Vector2i(buy_bucket_window_size)
		if bucket_cam:
			bucket_cam.fov = buy_camera_fov
		if bucket_root:
			bucket_root.scale = Vector3.ONE * buy_bucket_3d_scale

func _hide_all_bucket_guns() -> void:
	if _gun_float_tween and _gun_float_tween.is_valid():
		_gun_float_tween.kill()
	_active_bucket_gun = null
	if not _shop_inventories or not is_instance_valid(_shop_inventories):
		return
	for child in _shop_inventories.get_children():
		if child is Node3D:
			child.visible = false

func _resolve_bucket_gun_for_item(item_index: int) -> Node3D:
	if not _shop_inventories or not is_instance_valid(_shop_inventories):
		return null

	var item: ShopItemData = _get_shop_item(item_index)
	if not item:
		return null

	# 1. Check cached node if still valid and matching the current model_scene
	if _spawned_item_models.has(item_index):
		var cached: Node3D = _spawned_item_models[item_index] as Node3D
		if cached and is_instance_valid(cached):
			var expected_path: String = item.model_scene.resource_path if item.model_scene else ""
			if expected_path.is_empty() or cached.scene_file_path == expected_path or cached.get_meta("model_path", "") == expected_path:
				return cached

	# 2. Check existing pre-placed children in Shop Inventories (e.g., "Shotgun", "Sniper")
	var target_scene_path: String = item.model_scene.resource_path if item.model_scene else ""
	for child in _shop_inventories.get_children():
		if child is Node3D:
			if not target_scene_path.is_empty() and child.scene_file_path == target_scene_path:
				_spawned_item_models[item_index] = child
				return child

	# 3. Dynamically instantiate the assigned model_scene into Shop Inventories
	if item.model_scene:
		var inst := item.model_scene.instantiate() as Node3D
		if inst:
			inst.name = "DynamicShopModel_%d" % item_index
			inst.set_meta("model_path", target_scene_path)
			inst.position = item.bucket_position
			inst.rotation_degrees = item.bucket_rotation_degrees
			inst.scale = item.bucket_scale
			_shop_inventories.add_child(inst)
			_gun_base_transforms[inst.get_instance_id()] = {
				"pos": inst.position,
				"rot": inst.rotation
			}
			_spawned_item_models[item_index] = inst
			return inst

	return null

func _get_node_transform_relative_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var tf: Transform3D = Transform3D.IDENTITY
	var curr: Node = node
	while curr and curr != ancestor and curr is Node3D:
		tf = (curr as Node3D).transform * tf
		curr = curr.get_parent()
	return tf

func _transform_aabb(tf: Transform3D, aabb: AABB) -> AABB:
	var pos: Vector3 = tf * aabb.position
	var x: Vector3 = tf.basis.x * aabb.size.x
	var y: Vector3 = tf.basis.y * aabb.size.y
	var z: Vector3 = tf.basis.z * aabb.size.z
	var min_p: Vector3 = pos
	var max_p: Vector3 = pos
	var corners: Array[Vector3] = [
		pos + x,
		pos + y,
		pos + z,
		pos + x + y,
		pos + x + z,
		pos + y + z,
		pos + x + y + z
	]
	for corner in corners:
		min_p = min_p.min(corner)
		max_p = max_p.max(corner)
	return AABB(min_p, max_p - min_p)

func _get_combined_mesh_aabb(root_node: Node3D) -> AABB:
	var combined: AABB = AABB(Vector3.ZERO, Vector3.ZERO)
	var has_mesh: bool = false
	var stack: Array[Node] = [root_node]

	while not stack.is_empty():
		var curr = stack.pop_back()
		if curr is MeshInstance3D and curr.mesh:
			var mesh_aabb: AABB = curr.mesh.get_aabb()
			if mesh_aabb.size != Vector3.ZERO:
				var tf_rel: Transform3D = _get_node_transform_relative_to(curr, root_node)
				var tf_aabb: AABB = _transform_aabb(tf_rel, mesh_aabb)
				if not has_mesh:
					combined = tf_aabb
					has_mesh = true
				else:
					combined = combined.merge(tf_aabb)
		for child in curr.get_children():
			stack.push_back(child)

	return combined

func _get_aabb_centered_position(gun_node: Node3D, target_center: Vector3) -> Vector3:
	var aabb: AABB = _get_combined_mesh_aabb(gun_node)
	if aabb.size == Vector3.ZERO:
		return target_center
	var visual_offset: Vector3 = gun_node.transform.basis * aabb.get_center()
	return target_center - visual_offset

func _show_bucket_gun_for_item(item_index: int, play_sink_float: bool = true, delay_sec: float = 0.0) -> void:
	if not _shop_inventories or not is_instance_valid(_shop_inventories):
		return

	var gun_node: Node3D = _resolve_bucket_gun_for_item(item_index)
	for child in _shop_inventories.get_children():
		if child is Node3D:
			child.visible = (child == gun_node)

	_active_bucket_gun = gun_node
	if not _active_bucket_gun:
		return

	var iid: int = _active_bucket_gun.get_instance_id()
	if not _gun_base_transforms.has(iid):
		_gun_base_transforms[iid] = {
			"rot": _active_bucket_gun.rotation
		}

	var base_tf: Dictionary = _gun_base_transforms[iid]
	_active_gun_base_rot = base_tf["rot"]
	_active_gun_base_pos = _get_aabb_centered_position(_active_bucket_gun, bucket_item_target_center)
	_active_bucket_gun.position = _active_gun_base_pos
	_active_bucket_gun.rotation = _active_gun_base_rot

	if play_sink_float:
		_play_gun_sink_to_float_anim(delay_sec)
	else:
		if _gun_float_tween and _gun_float_tween.is_valid():
			_gun_float_tween.kill()
		_gun_sink_offset = 0.0
		_gun_sink_tilt = 0.0
		_active_bucket_gun.position = _active_gun_base_pos
		_active_bucket_gun.rotation = _active_gun_base_rot

func _play_gun_sink_to_float_anim(delay_sec: float = 0.0) -> void:
	if not _active_bucket_gun or not is_instance_valid(_active_bucket_gun):
		return

	if _gun_float_tween and _gun_float_tween.is_valid():
		_gun_float_tween.kill()

	# Start submerged deep beneath the water surface so absorption conceals it, then rise to floating position
	_gun_sink_offset = -0.38
	_gun_sink_tilt = 0.35
	_active_bucket_gun.position = Vector3(
		_active_gun_base_pos.x,
		_active_gun_base_pos.y + _gun_sink_offset,
		_active_gun_base_pos.z
	)
	_active_bucket_gun.rotation = Vector3(
		_active_gun_base_rot.x + _gun_sink_tilt,
		_active_gun_base_rot.y,
		_active_gun_base_rot.z
	)

	_gun_float_tween = create_tween()
	if delay_sec > 0.0:
		_gun_float_tween.tween_interval(delay_sec)
	_gun_float_tween.set_parallel(true)
	_gun_float_tween.tween_property(self, "_gun_sink_offset", 0.0, 0.72).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_gun_float_tween.tween_property(self, "_gun_sink_tilt", 0.0, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_gun_pickup_from_bucket_anim() -> void:
	if not _active_bucket_gun or not is_instance_valid(_active_bucket_gun):
		_reveal_confirm_preview_gun()
		return

	if _gun_float_tween and _gun_float_tween.is_valid():
		_gun_float_tween.kill()

	var target_gun: Node3D = _active_bucket_gun
	target_gun.visible = true

	# Quickly pop the gun slightly upward and hide it, then in the exact same frame reveal the Confirm gun
	_gun_float_tween = create_tween()
	_gun_float_tween.set_parallel(true)
	_gun_float_tween.tween_property(self, "_gun_sink_offset", 0.18, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_gun_float_tween.tween_property(self, "_gun_sink_tilt", -0.22, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_gun_float_tween.chain().tween_callback(func():
		if target_gun and is_instance_valid(target_gun):
			target_gun.visible = false
		if current_state == ShopState.CONFIRM:
			_reveal_confirm_preview_gun()
	)

func _reveal_confirm_preview_gun() -> void:
	if _confirm_menu_tween and _confirm_menu_tween.is_valid():
		_confirm_menu_tween.kill()

	if state_confirm:
		state_confirm.visible = true
		state_confirm.modulate.a = 1.0
		var confirm_card := state_confirm.get_node_or_null("ConfirmCard") as Control
		if confirm_card:
			confirm_card.pivot_offset = confirm_card.size * 0.5
			confirm_card.scale = Vector2.ONE

	if not confirm_shotgun_pivot or not is_instance_valid(confirm_shotgun_pivot):
		return

	confirm_shotgun_pivot.rotation = Vector3.ZERO
	confirm_shotgun_pivot.position = Vector3.ZERO
	confirm_shotgun_pivot.visible = true
	confirm_shotgun_pivot.scale = Vector3.ONE * 0.01
	_confirm_menu_tween = create_tween()
	_confirm_menu_tween.tween_property(confirm_shotgun_pivot, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _play_confirm_menu_pop_out() -> void:
	if _confirm_menu_tween and _confirm_menu_tween.is_valid():
		_confirm_menu_tween.kill()

	var confirm_card: Control = state_confirm.get_node_or_null("ConfirmCard") as Control if state_confirm else null
	if confirm_card:
		confirm_card.pivot_offset = confirm_card.size * 0.5
		confirm_card.scale = Vector2.ONE

	_confirm_menu_tween = create_tween()
	_confirm_menu_tween.set_parallel(true)
	if confirm_card:
		_confirm_menu_tween.tween_property(confirm_card, "scale", Vector2(0.75, 0.75), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if confirm_shotgun_pivot and is_instance_valid(confirm_shotgun_pivot):
		_confirm_menu_tween.tween_property(confirm_shotgun_pivot, "scale", Vector3.ONE * 0.01, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if state_confirm:
		_confirm_menu_tween.tween_property(state_confirm, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_confirm_menu_tween.chain().tween_callback(func():
		if state_confirm:
			state_confirm.visible = false
			state_confirm.modulate.a = 1.0
		if confirm_card:
			confirm_card.scale = Vector2.ONE
		if confirm_shotgun_pivot and is_instance_valid(confirm_shotgun_pivot):
			confirm_shotgun_pivot.visible = false
			confirm_shotgun_pivot.scale = Vector3.ONE
		if current_state == ShopState.BUY:
			_show_bucket_gun_for_item(_selected_item_index, true, 0.0)
	)

func _setup_button_events() -> void:
	if btn_buy and not btn_buy.pressed.is_connected(_on_buy_option_selected):
		btn_buy.pressed.connect(_on_buy_option_selected)
		btn_buy.mouse_entered.connect(func(): _on_option_hovered("BUY"))
		btn_buy.mouse_exited.connect(func(): _on_option_unhovered(btn_buy))
	if btn_tune and not btn_tune.pressed.is_connected(_on_tune_option_selected):
		btn_tune.pressed.connect(_on_tune_option_selected)
		btn_tune.mouse_entered.connect(func(): _on_option_hovered("TUNE"))
		btn_tune.mouse_exited.connect(func(): _on_option_unhovered(btn_tune))
	if btn_sell and not btn_sell.pressed.is_connected(_on_sell_option_selected):
		btn_sell.pressed.connect(_on_sell_option_selected)
		btn_sell.mouse_entered.connect(func(): _on_option_hovered("SELL"))
		btn_sell.mouse_exited.connect(func(): _on_option_unhovered(btn_sell))

	if btn_confirm and not btn_confirm.pressed.is_connected(_on_confirm_buy_pressed):
		btn_confirm.pressed.connect(_on_confirm_buy_pressed)
		btn_confirm.mouse_entered.connect(func(): _play_sfx("Hover_Ui"))
	if btn_cancle and not btn_cancle.pressed.is_connected(_on_cancle_pressed):
		btn_cancle.pressed.connect(_on_cancle_pressed)
		btn_cancle.mouse_entered.connect(func(): _play_sfx("Hover_Ui"))

func _apply_visual_styling() -> void:
	# Keep user's custom styling on option buttons (BUY, TUNE, SELL), only style confirm dialog buttons
	_style_comic_button(btn_confirm, COLOR_MINT_GREEN, COLOR_DEEP_NAVY, 24)
	_style_comic_button(btn_cancle, COLOR_CORAL_RED, Color.WHITE, 24)

func _style_comic_button(btn: Button, bg_col: Color, text_col: Color, fsize: int) -> void:
	if not btn:
		return
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 24
	sb.corner_radius_bottom_right = 12
	sb.corner_radius_bottom_left = 24
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = COLOR_DEEP_NAVY
	sb.shadow_color = COLOR_SHADOW_NAVY
	sb.shadow_offset = Vector2(4, 5)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("disabled", sb)

	var sb_hover = sb.duplicate()
	sb_hover.bg_color = bg_col.lightened(0.2)
	sb_hover.border_color = Color.WHITE
	sb_hover.shadow_offset = Vector2(5, 6)
	btn.add_theme_stylebox_override("hover", sb_hover)

	var sb_pressed = sb.duplicate()
	sb_pressed.bg_color = bg_col.darkened(0.15)
	sb_pressed.shadow_offset = Vector2(2, 2)
	btn.add_theme_stylebox_override("pressed", sb_pressed)

	btn.add_theme_font_override("font", font_dog_bold)
	btn.add_theme_font_size_override("font_size", fsize)
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_outline_color", COLOR_DEEP_NAVY)
	btn.add_theme_constant_override("outline_size", 6)

func _setup_shop_bucket_viewport(vp: SubViewport) -> void:
	if not vp:
		return

	# Fallback auto-instantiation if old nodes are still in scene
	var bucket = vp.find_child("Blue Bucket", true, false)
	if not bucket:
		bucket = vp.find_child("Shop Bucket", true, false)
	if not bucket:
		var bucket_scene = load("res://scenes/Merchant/Shop_Bucket.tscn") as PackedScene
		if bucket_scene:
			# Remove old placeholder nodes if present
			var old_cam = vp.get_node_or_null("Camera3D")
			if old_cam:
				old_cam.queue_free()
			var old_water = vp.get_node_or_null("WaterSurface")
			if old_water:
				old_water.queue_free()
			var old_pivot = vp.get_node_or_null("ShotgunPivot")
			if old_pivot:
				old_pivot.queue_free()

			bucket = bucket_scene.instantiate()
			vp.add_child(bucket)

	# Cache Shop Inventories and hide guns initially until entering Buy Menu
	var inv = vp.find_child("Shop Inventories", true, false) as Node3D
	if inv:
		_shop_inventories = inv
		for child in inv.get_children():
			if child is Node3D:
				var iid: int = child.get_instance_id()
				if not _gun_base_transforms.has(iid):
					var init_pos: Vector3 = child.position
					init_pos.x = 0.0
					init_pos.z = -0.02
					child.position = init_pos
					_gun_base_transforms[iid] = {
						"pos": init_pos,
						"rot": child.rotation
					}
				if current_state != ShopState.BUY and current_state != ShopState.CONFIRM:
					child.visible = false

	# Ensure Water Mesh has the absorption water shader material applied
	var water_mesh = vp.find_child("Water Mesh", true, false) as MeshInstance3D
	if water_mesh and not water_mesh.material_override:
		var water_mat = load("res://shaders/bucket_water_material.tres") as Material
		if water_mat:
			water_mesh.material_override = water_mat

	# Ensure viewport has transparent background
	vp.transparent_bg = true

	# Ensure camera inside bucket is active with transparent background
	var bucket_cam = vp.find_child("ShopCamera", true, false) as Camera3D
	if bucket_cam:
		bucket_cam.current = true
		var env = bucket_cam.environment
		if not env:
			env = Environment.new()
			bucket_cam.environment = env
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.8, 0.9, 1.0, 1.0)
		env.ambient_light_energy = 1.0

	# Ensure lighting in isolated SubViewport
	var dir_light = vp.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
	if not dir_light:
		dir_light = DirectionalLight3D.new()
		dir_light.name = "DirectionalLight3D"
		dir_light.transform = Transform3D(
			Basis(
				Vector3(0.866025, -0.353553, 0.353553),
				Vector3(0.0, 0.707107, 0.707107),
				Vector3(-0.5, -0.612372, 0.612372)
			),
			Vector3(1.5, 2.5, 2.0)
		)
		dir_light.light_color = Color(1.0, 0.98, 0.9, 1.0)
		dir_light.light_energy = 1.5
		vp.add_child(dir_light)
	dir_light.visible = _is_open
