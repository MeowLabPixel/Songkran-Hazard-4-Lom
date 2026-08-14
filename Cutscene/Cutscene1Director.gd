extends Node3D

## Cutscene1Director.gd
## Handles video playback during cutscene animation
## Listens for logo_out to finish, then plays FullCutscene

signal cutscene_finished

@onready var anim         := $"Cutscene1/AnimationPlayer - Cutscene1"
@onready var cutscene_cam := $"Cutscene1/Camera"
@onready var video_player := $CanvasLayer/VideoPlayerFullscreen

@export_file("*.ogv") var video_path: String = "res://Audio System and SFX/Cutscene/MarwinCall.ogv"
@export var video_start_time: float = 22.8

var cutscene_started: bool = false

func _ready() -> void:
	# Just load the video, DON'T start anything
	if video_path != "" and ResourceLoader.exists(video_path):
		video_player.stream = load(video_path)
		print("[Cutscene1] Video loaded: ", video_path)
	
	# Listen for when animations start and finish
	if anim:
		anim.animation_started.connect(_on_animation_started)
		anim.animation_finished.connect(_on_animation_finished)
	
	print("[Cutscene1] Ready - waiting for logo_out to finish...")

func _on_animation_started(anim_name: String) -> void:
	if anim_name == "FullCutscene" and not cutscene_started:
		cutscene_started = true
		print("[Cutscene1] FullCutscene started - triggering video...")
		start_video_countdown()

func _on_animation_finished(anim_name: String) -> void:
	# When logo_out finishes, play FullCutscene
	if anim_name == "logo_out":
		print("[Cutscene1] logo_out finished - starting FullCutscene...")
		
		# Activate cutscene camera
		await get_tree().process_frame
		cutscene_cam.make_current()
		
		# Play FullCutscene
		if anim.has_animation("FullCutscene"):
			anim.play("FullCutscene")
			print("[Cutscene1] Playing FullCutscene animation")
		else:
			push_error("[Cutscene1] FullCutscene animation not found!")

func start_video_countdown() -> void:
	# Wait for the video trigger time
	if video_start_time > 0 and video_player.stream != null:
		await get_tree().create_timer(video_start_time).timeout
		play_video()

func play_video() -> void:
	if video_player.stream == null:
		push_warning("[Cutscene1] No video loaded!")
		return
	
	print("[Cutscene1] Showing fullscreen video...")
	video_player.visible = true
	video_player.play()
	
	await video_player.finished
	
	video_player.visible = false
	print("[Cutscene1] Video finished")
