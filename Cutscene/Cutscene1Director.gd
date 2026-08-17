extends Node3D

## Cutscene1Director.gd
## Handles cutscene sequencing and renders MarwinCall.ogv directly onto the 3D phone screen mesh
signal cutscene_finished

@export_group("Playback Settings")
@export var autoplay_on_load: bool = true ## When true, cutscene plays immediately when scene loads
@export var starting_animation: String = "FullCutscene" ## Animation to play on load (e.g. FullCutscene or logo_out)

@export_group("Video Configuration")
@export_file("*.ogv") var video_path: String = "res://Cutscene/MarwinCall.ogv"
@export var video_start_time: float = 22.8 ## Time in seconds after FullCutscene starts to begin video
@export var auto_start_video: bool = true ## When true, automatically starts video at video_start_time
@export var loop_video: bool = false
@export var play_fullscreen_overlay: bool = false ## Also display fullscreen CanvasLayer overlay if desired
@export_range(0.0, 5.0) var screen_emission_energy: float = 1.2 ## Phone screen glow intensity

@onready var anim: AnimationPlayer = (
	get_node_or_null("Cutscene1/AnimationPlayer") as AnimationPlayer
	if has_node("Cutscene1/AnimationPlayer")
	else (
		get_node_or_null("Cutscene1/AnimationPlayer - Cutscene1") as AnimationPlayer
		if has_node("Cutscene1/AnimationPlayer - Cutscene1")
		else find_child("AnimationPlayer*", true, false) as AnimationPlayer
	)
)
@onready var cutscene_cam: Camera3D = get_node_or_null("Cutscene1/Camera") as Camera3D
@onready var video_player: VideoStreamPlayer = get_node_or_null("CanvasLayer/VideoPlayerFullscreen") as VideoStreamPlayer
@onready var phone_screen: MeshInstance3D = _find_phone_screen()

var _phone_viewport: SubViewport = null
var _phone_video_player: VideoStreamPlayer = null
var _phone_material: StandardMaterial3D = null
var cutscene_started: bool = false

func _find_phone_screen() -> MeshInstance3D:
	var s = get_node_or_null("Cutscene1/player/Skeleton3D/hand_fk_R/Phone/Screen") as MeshInstance3D
	if not s:
		s = find_child("Screen", true, false) as MeshInstance3D
	return s

func _ready() -> void:
	_setup_phone_video_screen()
	
	# Listen for when animations start and finish
	if anim:
		anim.animation_started.connect(_on_animation_started)
		anim.animation_finished.connect(_on_animation_finished)
	
	print("[Cutscene1] Ready - initializing cutscene...")

	if autoplay_on_load:
		await get_tree().process_frame
		if cutscene_cam:
			cutscene_cam.make_current()
		
		if anim:
			if starting_animation != "" and anim.has_animation(starting_animation):
				anim.play(starting_animation)
				print("[Cutscene1] Autoplaying animation: ", starting_animation)
			elif anim.has_animation("FullCutscene"):
				anim.play("FullCutscene")
				print("[Cutscene1] Autoplaying FullCutscene animation")
			elif anim.has_animation("logo_out"):
				anim.play("logo_out")
				print("[Cutscene1] Autoplaying logo_out animation")
			elif anim.get_animation_list().size() > 0:
				var first_anim = anim.get_animation_list()[0]
				anim.play(first_anim)
				print("[Cutscene1] Autoplaying first animation: ", first_anim)

func _setup_phone_video_screen() -> void:
	if not phone_screen:
		phone_screen = _find_phone_screen()

	# 1. Create dedicated SubViewport for phone screen rendering
	_phone_viewport = SubViewport.new()
	_phone_viewport.name = "PhoneScreenSubViewport"
	_phone_viewport.size = Vector2i(720, 1280) # 9:16 phone aspect ratio
	_phone_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_phone_viewport)

	# 2. Create VideoStreamPlayer inside the SubViewport
	_phone_video_player = VideoStreamPlayer.new()
	_phone_video_player.name = "PhoneVideoStream"
	_phone_video_player.expand = true
	_phone_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_phone_video_player.bus = "Voiceline"
	_phone_video_player.finished.connect(_on_phone_video_finished)
	_phone_viewport.add_child(_phone_video_player)

	# 3. Load video stream resource
	var stream_res = _load_video_stream()
	if stream_res:
		_phone_video_player.stream = stream_res
		if video_player:
			video_player.stream = stream_res
		print("[Cutscene1] Video stream loaded successfully: ", stream_res.resource_path)
	else:
		push_warning("[Cutscene1] Could not find MarwinCall.ogv video file!")

	# 4. Create and apply 3D glowing material to Phone Screen mesh
	if phone_screen:
		_phone_material = StandardMaterial3D.new()
		_phone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		var vp_tex = _phone_viewport.get_texture()
		_phone_material.albedo_texture = vp_tex
		_phone_material.emission_enabled = true
		_phone_material.emission_texture = vp_tex
		_phone_material.emission_energy_multiplier = screen_emission_energy
		
		phone_screen.set_surface_override_material(0, _phone_material)
		print("[Cutscene1] 3D Phone Screen material applied to: ", phone_screen.get_path())

func _load_video_stream() -> VideoStream:
	if video_path != "" and ResourceLoader.exists(video_path):
		return load(video_path) as VideoStream
	elif ResourceLoader.exists("res://Cutscene/MarwinCall.ogv"):
		return load("res://Cutscene/MarwinCall.ogv") as VideoStream
	elif ResourceLoader.exists("res://Audio System and SFX/Cutscene/MarwinCall.ogv"):
		return load("res://Audio System and SFX/Cutscene/MarwinCall.ogv") as VideoStream
	return null

func _on_animation_started(anim_name: String) -> void:
	if anim_name == "FullCutscene" and not cutscene_started:
		cutscene_started = true
		print("[Cutscene1] FullCutscene started")
		if auto_start_video:
			start_video_countdown()

func _on_animation_finished(anim_name: String) -> void:
	# When logo_out finishes, play FullCutscene
	if anim_name == "logo_out":
		print("[Cutscene1] logo_out finished - starting FullCutscene...")
		
		# Activate cutscene camera
		await get_tree().process_frame
		if cutscene_cam:
			cutscene_cam.make_current()
		
		# Play FullCutscene
		if anim and anim.has_animation("FullCutscene"):
			anim.play("FullCutscene")
			print("[Cutscene1] Playing FullCutscene animation")
		else:
			push_error("[Cutscene1] FullCutscene animation not found!")
	elif anim_name == "FullCutscene":
		emit_signal("cutscene_finished")

func start_video_countdown() -> void:
	if video_start_time > 0:
		await get_tree().create_timer(video_start_time).timeout
		play_video()
	else:
		play_video()

## Public methods to call directly via script or AnimationPlayer method tracks
func play_video() -> void:
	if _phone_video_player and _phone_video_player.stream != null:
		print("[Cutscene1] Playing video on 3D Phone Screen...")
		_phone_video_player.play()
	
	if play_fullscreen_overlay and video_player and video_player.stream != null:
		video_player.visible = true
		video_player.play()

func stop_video() -> void:
	if _phone_video_player:
		_phone_video_player.stop()
	if video_player:
		video_player.stop()
		video_player.visible = false
	print("[Cutscene1] Video stopped.")

func _on_phone_video_finished() -> void:
	if loop_video:
		if _phone_video_player:
			_phone_video_player.play()
	else:
		print("[Cutscene1] Phone screen video playback finished.")
