@tool
extends EditorPlugin

var _add_acoustic_button : Button = null


func _enter_tree() -> void:
	# Listen for selection changes in the editor.
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	_remove_button()
	if get_editor_interface().get_selection().selection_changed.is_connected(_on_selection_changed):
		get_editor_interface().get_selection().selection_changed.disconnect(_on_selection_changed)


func _on_selection_changed() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()

	# Show the button when exactly one CollisionObject3D or CSGShape3D is
	# selected and it doesn't already have an AcousticBody child.
	if selected.size() == 1 and (selected[0] is CollisionObject3D or selected[0] is CSGShape3D):
		var node : Node3D = selected[0]
		var already_has := AcousticBody.find_on(node) != null
		if not already_has:
			_show_button(node)
			return

	_remove_button()


func _show_button(target: Node3D) -> void:
	if _add_acoustic_button != null:
		return  # already visible

	_add_acoustic_button = Button.new()
	_add_acoustic_button.text = "AcousticBody"
	_add_acoustic_button.flat = true
	_add_acoustic_button.tooltip_text = "Add an AcousticBody child to this node"
	_add_acoustic_button.add_theme_font_size_override("font_size", 15)

	# Strip all internal padding so the button matches the toolbar height.
	var empty_style := StyleBoxEmpty.new()
	_add_acoustic_button.add_theme_stylebox_override("normal", empty_style)
	_add_acoustic_button.add_theme_stylebox_override("hover", empty_style)
	_add_acoustic_button.add_theme_stylebox_override("pressed", empty_style)
	_add_acoustic_button.add_theme_stylebox_override("focus", empty_style)
	_add_acoustic_button.add_theme_constant_override("h_separation", 4)

	# Scale the icon down to 16×16 so it doesn't inflate the toolbar.
	var src_tex : Texture2D = preload("images/acoustic_body.svg")
	var img := src_tex.get_image()
	img.resize(16, 16, Image.INTERPOLATE_LANCZOS)
	_add_acoustic_button.icon = ImageTexture.create_from_image(img)

	_add_acoustic_button.pressed.connect(_on_add_acoustic_pressed.bind(target))

	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _add_acoustic_button)


func _remove_button() -> void:
	if _add_acoustic_button != null:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _add_acoustic_button)
		_add_acoustic_button.queue_free()
		_add_acoustic_button = null


func _on_add_acoustic_pressed(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		_remove_button()
		return

	# Don't add a duplicate.
	if AcousticBody.find_on(target) != null:
		_remove_button()
		return

	var undo_redo := get_undo_redo()
	var acoustic := AcousticBody.new()
	acoustic.name = "AcousticBody"

	undo_redo.create_action("Add AcousticBody")
	undo_redo.add_do_method(target, "add_child", acoustic, true)
	undo_redo.add_do_method(acoustic, "set_owner", get_editor_interface().get_edited_scene_root())
	undo_redo.add_do_reference(acoustic)
	undo_redo.add_undo_method(target, "remove_child", acoustic)
	undo_redo.commit_action()

	# Select the new node so the user can assign a material immediately.
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(acoustic)

	_remove_button()
