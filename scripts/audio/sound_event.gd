class_name SoundEvent
extends Resource

@export var name: String = ""
@export_range(-40.0, 20.0) var volume_db: float = 0.0
@export var pitch_range: Vector2 = Vector2(0.95, 1.05)
@export_range(0.0, 5.0) var volume_randomness_db: float = 0.0
@export var is_3d: bool = false
@export var max_instances: int = 0
@export_enum("SFX", "Music", "UI", "Voiceline") var category: String = "SFX"

@export_group("3D Attenuation")
@export var max_distance: float = 10.0
@export_range(0.0, 10.0) var unit_size: float = 3.0

@export_group("Filters")
@export_enum("None", "Reverb", "Muffled", "Retro") var effect: String = "None"

@export_group("Playback Mode")
@export var use_regions: bool = false
@export var streams: Array[AudioStream] = []
@export var stream: AudioStream
@export var regions: Array[Vector2] = [] # x = start_time, y = duration

@export_group("Sequencing")
@export var next_event_name: String = ""

@export_group("Layers")
@export var parallel_streams: Array[AudioStream] = []
@export var parallel_regions: Array[Vector2] = [] # x = start_time, y = duration

@export_group("Alternative")
@export var alternative_streams: Array[AudioStream] = []
@export var alternative_parallel_streams: Array[AudioStream] = []
@export var alternative_regions: Array[Vector2] = [] # x = start_time, y = duration
@export var alternative_parallel_regions: Array[Vector2] = [] # x = start_time, y = duration

var _last_played_index: int = -1

# Selects variation index using shuffle/no-repeat logic
func get_next_variation_index(alt: bool) -> int:
	var list_size = 0
	if use_regions:
		list_size = alternative_regions.size() if alt else regions.size()
	else:
		list_size = alternative_streams.size() if alt else streams.size()
		
	if list_size <= 0:
		return -1
	if list_size == 1:
		return 0
		
	var choices = []
	for i in range(list_size):
		if i != _last_played_index:
			choices.append(i)
			
	var selected = choices[randi() % choices.size()]
	_last_played_index = selected
	return selected
