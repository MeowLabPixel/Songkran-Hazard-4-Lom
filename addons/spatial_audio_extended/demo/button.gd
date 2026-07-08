extends Node3D

signal activated

## The key that triggers activation when pressed inside the area.
@export var activation_key : Key = KEY_E

## The [Area3D] child that defines the interaction zone.
## If not set, the first [Area3D] child is used automatically.
@export var area : Area3D

var _player_inside := false
@onready var spatial_audio_player_3d1: SpatialAudioPlayer3D = $"../Speaker1/SpatialAudioPlayer3D"
@onready var spatial_audio_player_3d2: SpatialAudioPlayer3D = $"../Speaker2/SpatialAudioPlayer3D"
@onready var spatial_audio_player_3d3: SpatialAudioPlayer3D = $"../Speaker3/SpatialAudioPlayer3D"
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	if area == null:
		push_warning("%s: No Area3D found — interaction will not work." % name)
		return
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == activation_key:
			activate()
			get_viewport().set_input_as_handled()

var is_activated := false
func activate() -> void:
	if !is_activated:
		activated.emit()
		is_activated = true
		animation_player.play("push")
		spatial_audio_player_3d1.play_with_delay()
		await get_tree().create_timer(2.0).timeout
		spatial_audio_player_3d2.play_with_delay()
		await get_tree().create_timer(2.0).timeout
		spatial_audio_player_3d3.play_with_delay()
		animation_player.play("static")
		is_activated = false



func _on_body_entered(_body: Node3D) -> void:
	_player_inside = true


func _on_body_exited(_body: Node3D) -> void:
	_player_inside = false
