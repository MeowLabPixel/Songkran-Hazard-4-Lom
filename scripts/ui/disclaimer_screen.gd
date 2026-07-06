extends Control

var pages_th: Array[Texture2D] = [
	preload("res://scenes/1_Disclaimer.png"),
	preload("res://scenes/2_Controls.png"),
	preload("res://scenes/3_Reload.png"),
	preload("res://scenes/4_Weakpoints.png"),
	preload("res://scenes/5_Objective.png")
]

var pages_en: Array[Texture2D] = [
	preload("res://scenes/1_Disclaimer_ENG.png"),
	preload("res://scenes/2_Controls_ENG.png"),
	preload("res://scenes/3_Reload_ENG.png"),
	preload("res://scenes/4_Weakpoints_ENG.png"),
	preload("res://scenes/5_Objective_ENG.png")
]

var pages: Array[Texture2D] = []

@export var movement_pic_a: Texture2D
@export var movement_pic_b: Texture2D
@export var movement_pic_c: Texture2D

@onready var container: Control = $ContentContainer
@onready var texture_rect: TextureRect = $ContentContainer/VBox/TextureRect
@onready var prompt_label: Label = $ContentContainer/VBox/Prompt

var is_transitioning := false
var current_step := 0
var language_selected := false
var selected_lang := "en"
var lang_container: HBoxContainer
var move_selection_container: Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").reset_game()

	# Hide main content container initially
	container.hide()
	
	# Create language selection UI
	lang_container = HBoxContainer.new()
	lang_container.alignment = BoxContainer.ALIGNMENT_CENTER
	lang_container.add_theme_constant_override("separation", 50)
	
	var btn_th = Button.new()
	btn_th.text = "ภาษาไทย (THAI)"
	btn_th.add_theme_font_size_override("font_size", 48)
	btn_th.custom_minimum_size = Vector2(350, 120)
	btn_th.pressed.connect(func(): _select_language("th"))
	
	var btn_en = Button.new()
	btn_en.text = "ENGLISH"
	btn_en.add_theme_font_size_override("font_size", 48)
	btn_en.custom_minimum_size = Vector2(350, 120)
	btn_en.pressed.connect(func(): _select_language("en"))
	
	lang_container.add_child(btn_th)
	lang_container.add_child(btn_en)
	
	add_child(lang_container)
	lang_container.anchor_right = 1.0
	lang_container.anchor_bottom = 1.0
	
	# Set pivot to center so scaling is centered
	container.resized.connect(func():
		container.pivot_offset = container.size / 2.0
	)

func _select_language(lang: String) -> void:
	if lang == "th":
		pages = pages_th
		selected_lang = "th"
	else:
		pages = pages_en
		selected_lang = "en"
		
	language_selected = true
	lang_container.hide()
	_show_movement_selection()

func update_prompt() -> void:
	if prompt_label == null:
		return
	if current_step < pages.size() - 1:
		prompt_label.text = "[ Press E Next | Q for Back ]"
		prompt_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
	else:
		prompt_label.text = "[ Press E to START THE GAME | Q for Back ]"
		prompt_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1)) # Gold color for emphasis

func _unhandled_input(event: InputEvent) -> void:
	if not language_selected or is_transitioning:
		return
		
	var is_forward = event.is_action_pressed("takedown") or (
		event is InputEventKey and event.pressed and (
			event.keycode == KEY_E or 
			event.keycode == KEY_D or 
			event.keycode == KEY_RIGHT
		)
	)
	
	var is_backward = event is InputEventKey and event.pressed and (
		event.keycode == KEY_Q or 
		event.keycode == KEY_A or 
		event.keycode == KEY_LEFT
	)
	
	if is_forward:
		if current_step == pages.size() - 1:
			transition_to_game()
		else:
			transition_to_page(current_step + 1)
	elif is_backward:
		if current_step > 0:
			transition_to_page(current_step - 1)

func transition_to_page(next_page_index: int) -> void:
	is_transitioning = true
	
	# Start pop-out animation
	var tween = create_tween().set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(container, "modulate:a", 0.0, 0.2)
	
	tween.finished.connect(func():
		current_step = next_page_index
		if current_step >= 0 and current_step < pages.size():
			texture_rect.texture = pages[current_step]
		update_prompt()
		
		# Start pop-in animation
		var tween_in = create_tween().set_parallel(true)
		tween_in.tween_property(container, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween_in.tween_property(container, "modulate:a", 1.0, 0.3)
		
		tween_in.finished.connect(func():
			is_transitioning = false
		)
	)

func transition_to_game() -> void:
	is_transitioning = true
	
	# Start pop-out animation
	var tween = create_tween().set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(container, "modulate:a", 0.0, 0.3)
	
	tween.finished.connect(func():
		get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
	)

var movement_texts = {
	"title": {
		"en": "CHOOSE MOVEMENT CONTROL TYPE",
		"th": "เลือกรูปแบบการควบคุมการเคลื่อนไหว"
	},
	"type_a_title": {
		"en": "Type A: Hybrid Retro",
		"th": "แบบ A: ไฮบริดเรโทร"
	},
	"type_a_desc": {
		"en": "Classic 4-way direction movement.\nWhen a new input is pressed, it replaces the previous one. Great for retro precision.",
		"th": "การเคลื่อนที่ 4 ทิศทางแบบคลาสสิก\nกดปุ่มใหม่จะแทนที่ปุ่มเดิม เหมาะสำหรับความแม่นยำสูงแบบย้อนยุค"
	},
	"type_b_title": {
		"en": "Type B: Modern",
		"th": "แบบ B: สมัยใหม่"
	},
	"type_b_desc": {
		"en": "Modern 8-way directional movement.\nCombine forward/backward and left/right keys to move diagonally.",
		"th": "การเคลื่อนที่ 8 ทิศทางแบบร่วมสมัย\nสามารถกดปุ่มเดินหน้า/ถอยหลังพร้อมกับซ้าย/ขวาเพื่อเคลื่อนที่แนวทะแยงได้"
	},
	"type_c_title": {
		"en": "Type C: True Tank",
		"th": "แบบ C: แทงค์คลาสสิก"
	},
	"type_c_desc": {
		"en": "Classic Tank Control.\nW/S moves forward/back. A/D rotates the character/camera.\nMouse rotates character only when aiming/grabbed, otherwise free-look (L 20°, R 15°, Up 10°, Down 15°).",
		"th": "การควบคุมสไตล์รถถังคลาสสิก\nW/S เดินหน้า/ถอยหลัง A/D หมุนตัวและกล้อง\nเมาส์จะหมุนตัวเมื่อเล็งหรือถูกจับเท่านั้น นอกนั้นใช้มองรอบๆ (ซ้าย 20°, ขวา 15°, บน 10°, ล่าง 15°)"
	},
	"select_btn": {
		"en": "SELECT",
		"th": "เลือก"
	}
}

func _show_movement_selection() -> void:
	move_selection_container = Control.new()
	move_selection_container.name = "MovementSelectionUI"
	add_child(move_selection_container)
	move_selection_container.anchor_right = 1.0
	move_selection_container.anchor_bottom = 1.0
	
	# Background style
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07, 0.95)
	move_selection_container.add_child(bg)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 40)
	move_selection_container.add_child(vbox)
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_top = 50
	vbox.offset_bottom = -50
	
	# Title
	var title_lbl = Label.new()
	title_lbl.text = movement_texts["title"][selected_lang]
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 42)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)) # Golden text
	vbox.add_child(title_lbl)
	
	# Cards horizontal layout
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 60)
	vbox.add_child(hbox)
	
	# Create 3 cards
	_create_movement_card(hbox, "Type A", GameManager.MovementType.HYBRID_RETRO)
	_create_movement_card(hbox, "Type B", GameManager.MovementType.MODERN)
	_create_movement_card(hbox, "Type C", GameManager.MovementType.TANK)

func _create_movement_card(parent: Control, type_key: String, type_val: GameManager.MovementType) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 680)
	
	# Design a premium-looking panel
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	sb.corner_radius_top_left = 15
	sb.corner_radius_top_right = 15
	sb.corner_radius_bottom_left = 15
	sb.corner_radius_bottom_right = 15
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.25, 0.25, 0.3)
	card.add_theme_stylebox_override("panel", sb)
	
	parent.add_child(card)
	
	# Main layout inside the card
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	
	# Add some internal padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	
	card.add_child(margin)
	margin.add_child(vbox)
	
	# Variables based on type
	var title_lbl_key = ""
	var desc_key = ""
	var pic_tex: Texture2D = null
	
	match type_val:
		GameManager.MovementType.HYBRID_RETRO:
			title_lbl_key = "type_a_title"
			desc_key = "type_a_desc"
			pic_tex = movement_pic_a
		GameManager.MovementType.MODERN:
			title_lbl_key = "type_b_title"
			desc_key = "type_b_desc"
			pic_tex = movement_pic_b
		GameManager.MovementType.TANK:
			title_lbl_key = "type_c_title"
			desc_key = "type_c_desc"
			pic_tex = movement_pic_c
			
	var title_lbl = Label.new()
	title_lbl.text = movement_texts[title_lbl_key][selected_lang]
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 30)
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(title_lbl)
	
	# Image Area (clickable)
	var img_container = PanelContainer.new()
	img_container.custom_minimum_size = Vector2(380, 240)
	var img_sb = StyleBoxFlat.new()
	img_sb.bg_color = Color(0.08, 0.08, 0.1, 1)
	img_sb.corner_radius_top_left = 10
	img_sb.corner_radius_top_right = 10
	img_sb.corner_radius_bottom_left = 10
	img_sb.corner_radius_bottom_right = 10
	img_container.add_theme_stylebox_override("panel", img_sb)
	vbox.add_child(img_container)
	
	if pic_tex != null:
		var tex_rect = TextureRect.new()
		tex_rect.texture = pic_tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img_container.add_child(tex_rect)
	else:
		# Placeholder label/visual
		var placeholder = VBoxContainer.new()
		placeholder.alignment = BoxContainer.ALIGNMENT_CENTER
		var icon = Label.new()
		icon.text = "📷"
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 48)
		var label = Label.new()
		label.text = "[ IMAGE PLACEHOLDER ]\n(Click to select)"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		placeholder.add_child(icon)
		placeholder.add_child(label)
		img_container.add_child(placeholder)
		
	# Description
	var desc_lbl = Label.new()
	desc_lbl.text = movement_texts[desc_key][selected_lang]
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.custom_minimum_size = Vector2(360, 160)
	desc_lbl.add_theme_font_size_override("font_size", 18)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(desc_lbl)
	
	# Select Button
	var select_btn = Button.new()
	select_btn.text = movement_texts["select_btn"][selected_lang]
	select_btn.add_theme_font_size_override("font_size", 24)
	select_btn.custom_minimum_size = Vector2(250, 60)
	
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.18, 0.18, 0.24)
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_left = 8
	btn_normal.corner_radius_bottom_right = 8
	select_btn.add_theme_stylebox_override("normal", btn_normal)
	
	var btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.25, 0.25, 0.35)
	btn_hover.corner_radius_top_left = 8
	btn_hover.corner_radius_top_right = 8
	btn_hover.corner_radius_bottom_left = 8
	btn_hover.corner_radius_bottom_right = 8
	select_btn.add_theme_stylebox_override("hover", btn_hover)
	
	var btn_pressed = StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.1, 0.1, 0.15)
	btn_pressed.corner_radius_top_left = 8
	btn_pressed.corner_radius_top_right = 8
	btn_pressed.corner_radius_bottom_left = 8
	btn_pressed.corner_radius_bottom_right = 8
	select_btn.add_theme_stylebox_override("pressed", btn_pressed)
	
	var btn_center = CenterContainer.new()
	btn_center.add_child(select_btn)
	vbox.add_child(btn_center)
	
	var select_action = func():
		_select_movement_type(type_val)
		
	select_btn.pressed.connect(select_action)
	
	card.mouse_entered.connect(func():
		var tween_scale = create_tween().set_parallel(true)
		tween_scale.tween_property(card, "scale", Vector2(1.03, 1.03), 0.15)
		sb.border_color = Color(0.5, 0.5, 0.7)
	)
	card.mouse_exited.connect(func():
		var tween_scale = create_tween().set_parallel(true)
		tween_scale.tween_property(card, "scale", Vector2(1.0, 1.0), 0.15)
		sb.border_color = Color(0.25, 0.25, 0.3)
	)
	
	img_container.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			select_action.call()
	)
	
	select_btn.focus_entered.connect(func():
		var tween_scale = create_tween().set_parallel(true)
		tween_scale.tween_property(card, "scale", Vector2(1.03, 1.03), 0.15)
		sb.border_color = Color(0.5, 0.5, 0.7)
	)
	select_btn.focus_exited.connect(func():
		var tween_scale = create_tween().set_parallel(true)
		tween_scale.tween_property(card, "scale", Vector2(1.0, 1.0), 0.15)
		sb.border_color = Color(0.25, 0.25, 0.3)
	)
	
	card.resized.connect(func():
		card.pivot_offset = card.size / 2.0
	)

func _select_movement_type(type: GameManager.MovementType) -> void:
	GameManager.movement_type = type
	GameManager.movement_type_selected = true
	print("[Disclaimer] Selected movement control: ", GameManager.MovementType.keys()[type])
	
	if move_selection_container:
		move_selection_container.queue_free()
		
	container.show()
	
	current_step = 0
	if pages.size() > 0:
		texture_rect.texture = pages[current_step]
	update_prompt()
	
	await get_tree().process_frame
	
	container.scale = Vector2.ZERO
	container.modulate.a = 0.0
	container.pivot_offset = container.size / 2.0
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(container, "modulate:a", 1.0, 0.4)
