extends Control

@onready var transition_rect: ColorRect = $CanvasLayer/TransitionRect

var world_scene_path: String = "res://player/test/world.tscn"
var is_loading_started := false
var is_scene_ready := false
var scene_instance: Node = null
var shader_material: ShaderMaterial = null

func _ready() -> void:
	print("[LoadingScreen] Ready, starting async load: ", world_scene_path)
	
	# Start loading the world scene asynchronously
	ResourceLoader.load_threaded_request(world_scene_path)
	
	# Set up the shader material dynamically
	var shader = load("res://addons/shader/transition.gdshader") as Shader
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	
	# Set initial uniforms (fully transparent factor = 0.0)
	shader_material.set_shader_parameter("base_color", Color(0.02, 0.02, 0.03, 1.0))
	shader_material.set_shader_parameter("node_resolution", size)
	shader_material.set_shader_parameter("factor", 0.0) # Start fully transparent
	shader_material.set_shader_parameter("width", 0.4)
	
	# Generate a gradient texture dynamically
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color.BLACK, Color.WHITE])
	
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = gradient
	grad_tex.fill = GradientTexture2D.FILL_LINEAR
	grad_tex.fill_from = Vector2(0.0, 0.0)
	grad_tex.fill_to = Vector2(1.0, 0.0)
	
	shader_material.set_shader_parameter("gradient_texture", grad_tex)
	
	# Apply shader to transition ColorRect
	transition_rect.material = shader_material
	transition_rect.show()
	
	# Ensure resolution uniform updates on resize
	resized.connect(func():
		if shader_material:
			shader_material.set_shader_parameter("node_resolution", size)
	)

func _process(delta: float) -> void:
	if is_loading_started:
		return
		
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(world_scene_path, progress)
	
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		is_loading_started = true
		print("[LoadingScreen] Scene loaded successfully. Starting transition flow.")
		var scene_resource = ResourceLoader.load_threaded_get(world_scene_path)
		scene_instance = scene_resource.instantiate()
		is_scene_ready = true
		_start_transition_flow()
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		is_loading_started = true
		printerr("[LoadingScreen] Failed to load world scene asynchronously!")

func _start_transition_flow() -> void:
	print("[LoadingScreen] Starting screen cover tween...")
	# 1. Tween factor from 0.0 (transparent) to 1.0 (opaque cover)
	var tween_cover = create_tween()
	tween_cover.tween_method(
		func(val: float): shader_material.set_shader_parameter("factor", val),
		0.0,
		1.0,
		0.6 # 0.6 second cover duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	tween_cover.finished.connect(func():
		print("[LoadingScreen] Cover opaque. Hiding UI elements and swapping to world scene...")
		# Hide the background and text so that only the transition shader rect covers the screen
		$CanvasLayer/Background.hide()
		$CanvasLayer/CenterContainer.hide()

		# 2. Add world scene to root and swap current scene
		get_tree().root.add_child(scene_instance)
		get_tree().current_scene = scene_instance
		
		# Start game manager loop
		if get_tree().root.has_node("GameManager"):
			get_tree().root.get_node("GameManager").start_game()
			
		print("[LoadingScreen] World scene added. Starting reveal transition...")
		# 3. Tween factor from 1.0 (opaque cover) to 0.0 (transparent reveal)
		var tween_reveal = create_tween()
		tween_reveal.tween_method(
			func(val: float): shader_material.set_shader_parameter("factor", val),
			1.0,
			0.0,
			0.6 # 0.6 second reveal duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
		# 4. Clean up loading screen on completion
		tween_reveal.finished.connect(func():
			print("[LoadingScreen] Transition complete. Freeing loading screen...")
			queue_free()
		)
	)

