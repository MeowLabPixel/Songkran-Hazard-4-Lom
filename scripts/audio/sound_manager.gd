@tool
extends Node

@export_category("Sound Manager")

@export_group("Volume Controls (dB)")
@export_range(-80.0, 6.0) var master_volume: float = 0.0:
	set(val):
		master_volume = val
		_set_bus_vol("Master", val)
@export_range(-80.0, 6.0) var sfx_volume: float = 0.0:
	set(val):
		sfx_volume = val
		_set_bus_vol("SFX", val)
@export_range(-80.0, 6.0) var music_volume: float = 0.0:
	set(val):
		music_volume = val
		_set_bus_vol("Music", val)
@export_range(-80.0, 6.0) var ui_volume: float = 0.0:
	set(val):
		ui_volume = val
		_set_bus_vol("UI", val)
@export_range(-80.0, 6.0) var voiceline_volume: float = 0.0:
	set(val):
		voiceline_volume = val
		_set_bus_vol("Voiceline", val)

@export_group("Muffle Settings")
@export var default_muffle_cutoff: float = 500.0
@export var default_muffle_duration: float = 0.3

@export_group("Music Transition Controls")
@export var music_bpm: float = 112.0
@export var music_beats_per_bar: int = 4
@export_enum("Beat", "Bar", "Immediate") var transition_sync_mode: String = "Beat"
@export var music_crossfade_duration: float = 0.1

@export_group("Editor Utilities")
@export var generate_resources_now: bool = false:
	set(val):
		if val:
			var generator_script = load("res://scripts/audio/sound_event_generator.gd")
			if generator_script:
				var generator = generator_script.new()
				generator.generate_all_events()
				_load_sound_bank_from_disk()
			generate_resources_now = false

@export_group("Sound Event Bank")
@export var sound_bank: Array[SoundEvent] = []

var _events: Dictionary = {}
var _active_instances: Dictionary = {} # event_name -> Array[Node] (players)
var _muffle_tweens: Dictionary = {} # bus_name -> Tween
var _muffle_linger_tweens: Dictionary = {} # bus_name -> Tween

# Interactive Music Players & State
var _music_player_1: AudioStreamPlayer
var _music_player_2: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer = null
var _music_transition_tween: Tween = null
var _pending_transition_tween: Tween = null
var _next_loop_event: String = ""
var _current_music_state: String = "None"

func _set_bus_vol(bus_name: String, db: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, db)

func _load_sound_bank_from_disk() -> void:
	sound_bank.clear()
	var dir = DirAccess.open("res://audio_events")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var event = load("res://audio_events/" + file_name) as SoundEvent
				if event:
					sound_bank.append(event)
			file_name = dir.get_next()
	
	_events.clear()
	for event in sound_bank:
		if event and not event.name.is_empty():
			_events[event.name] = event
			if not _active_instances.has(event.name):
				_active_instances[event.name] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		_load_sound_bank_from_disk()
		return
		
	process_mode = PROCESS_MODE_ALWAYS
	
	# Generate all sound events dynamically from audio files on disk
	var generator_script = load("res://scripts/audio/sound_event_generator.gd")
	if generator_script:
		var generator = generator_script.new()
		generator.generate_all_events()
	
	# Fallback: if sound_bank is empty, load all generated resources dynamically
	if sound_bank.is_empty():
		_load_sound_bank_from_disk()
	else:
		for event in sound_bank:
			if event and not event.name.is_empty():
				_events[event.name] = event
				_active_instances[event.name] = []
	
	# Initialize/create audio buses dynamically
	_setup_audio_buses()
	
	# Apply exported volumes to the newly initialized buses
	_set_bus_vol("Master", master_volume)
	_set_bus_vol("SFX", sfx_volume)
	_set_bus_vol("Music", music_volume)
	_set_bus_vol("UI", ui_volume)
	_set_bus_vol("Voiceline", voiceline_volume)

	# Initialize background music players
	_music_player_1 = AudioStreamPlayer.new()
	_music_player_2 = AudioStreamPlayer.new()
	add_child(_music_player_1)
	add_child(_music_player_2)
	_music_player_1.bus = "Music"
	_music_player_2.bus = "Music"
	
	# Start playing ambient/non-combat music after a brief moment
	get_tree().create_timer(0.1).timeout.connect(play_music_non_combat)
	
	# Print music stream lengths for tempo/beat analysis
	for ev_name in ["Start_Non-combat", "Loop_Non-combat", "Start_Combat", "Loop_Combat"]:
		var ev = _events.get(ev_name)
		if ev:
			var s = ev.stream
			if not s and not ev.streams.is_empty():
				s = ev.streams[0]
			if s:
				print("[MusicLength] ", ev_name, " length: ", s.get_length())

func _setup_audio_buses() -> void:
	var categories = ["SFX", "Music", "UI", "Voiceline"]
	var effects = ["Reverb", "Muffled", "Retro"]
	
	# Ensure main category buses exist or fall back to Master
	for category in categories:
		var cat_idx = AudioServer.get_bus_index(category)
		if cat_idx == -1:
			# If category bus doesn't exist, we will create it and send it to Master
			cat_idx = AudioServer.bus_count
			AudioServer.add_bus(cat_idx)
			AudioServer.set_bus_name(cat_idx, category)
			AudioServer.set_bus_send(cat_idx, "Master")
		
		# Only add LowPassFilter to Music bus for player get_hit muffling
		if category == "Music":
			var lpf_found = false
			for i in range(AudioServer.get_bus_effect_count(cat_idx)):
				if AudioServer.get_bus_effect(cat_idx, i) is AudioEffectLowPassFilter:
					lpf_found = true
					break
			if not lpf_found:
				var lpf = AudioEffectLowPassFilter.new()
				lpf.cutoff_hz = 20000.0 # start open
				AudioServer.add_bus_effect(cat_idx, lpf)

		# Create sub-buses for Category + Effect combinations (e.g., SFX_Reverb)
		for effect in effects:
			var sub_bus_name = category + "_" + effect
			var sub_idx = AudioServer.get_bus_index(sub_bus_name)
			if sub_idx == -1:
				sub_idx = AudioServer.bus_count
				AudioServer.add_bus(sub_idx)
				AudioServer.set_bus_name(sub_idx, sub_bus_name)
				AudioServer.set_bus_send(sub_idx, category) # route output to main category
				
				# Add effect to sub-bus
				match effect:
					"Reverb":
						var reverb = AudioEffectReverb.new()
						reverb.room_size = 0.6
						reverb.wet = 0.4
						AudioServer.add_bus_effect(sub_idx, reverb)
					"Muffled":
						var lpf = AudioEffectLowPassFilter.new()
						lpf.cutoff_hz = 1000.0 # muffled
						AudioServer.add_bus_effect(sub_idx, lpf)
					"Retro":
						var dist = AudioEffectDistortion.new()
						dist.mode = AudioEffectDistortion.MODE_CLIP
						dist.drive = 0.5
						AudioServer.add_bus_effect(sub_idx, dist)

# Helper to check polyphony (max_instances) and prune old players
func _check_polyphony(event: SoundEvent) -> bool:
	if event.max_instances <= 0:
		return true
		
	var instances: Array = _active_instances.get(event.name, [])
	
	# Prune any instances that have been freed
	var active = []
	for inst in instances:
		if is_instance_valid(inst) and inst.is_inside_tree() and inst.playing:
			active.append(inst)
	_active_instances[event.name] = active
	
	if active.size() >= event.max_instances:
		# Stop and free the oldest instance to make room
		var oldest = active.pop_front()
		if is_instance_valid(oldest):
			oldest.stop()
			oldest.queue_free()
			
	return true

# Clean up player nodes when finished
func _on_player_finished(player: Node, event: SoundEvent, parallel_player: Node = null) -> void:
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(parallel_player):
		parallel_player.queue_free()

# Plays a 2D Sound Event (returns the main player node)
func play_2d(event_name: String, start_offset: float = 0.0, duration: float = -1.0, alternative: bool = false) -> AudioStreamPlayer2D:
	var event: SoundEvent = _events.get(event_name)
	if not event:
		push_warning("[SoundManager] SoundEvent '%s' not found." % event_name)
		return null
		
	_check_polyphony(event)
	
	var idx = event.get_next_variation_index(alternative)
	if idx == -1:
		push_warning("[SoundManager] SoundEvent '%s' has no streams/regions configured." % event_name)
		return null
		
	# Create primary player
	var player = AudioStreamPlayer2D.new()
	add_child(player)
	_active_instances[event.name].append(player)
	
	# Setup bus routing
	var target_bus = event.category
	if event.effect != "None":
		target_bus += "_" + event.effect
	player.bus = target_bus
	
	# Configure volume and pitch with randomness
	var random_vol = randf_range(-event.volume_randomness_db, event.volume_randomness_db)
	player.volume_db = event.volume_db + random_vol
	
	var random_pitch = randf_range(event.pitch_range.x, event.pitch_range.y)
	player.pitch_scale = random_pitch
	
	# Playback details (Multi-file vs Regions)
	var final_duration = duration
	var parallel_player: AudioStreamPlayer2D = null
	
	if event.use_regions:
		var reg = event.alternative_regions[idx] if alternative else event.regions[idx]
		player.stream = event.stream
		player.play(reg.x)
		if final_duration < 0.0:
			final_duration = reg.y
			
		# Parallel region layering
		var has_parallel = (alternative and event.alternative_parallel_regions.size() > idx) or (not alternative and event.parallel_regions.size() > idx)
		if has_parallel:
			var preg = event.alternative_parallel_regions[idx] if alternative else event.parallel_regions[idx]
			parallel_player = AudioStreamPlayer2D.new()
			add_child(parallel_player)
			parallel_player.bus = target_bus
			parallel_player.volume_db = event.volume_db + random_vol
			parallel_player.pitch_scale = random_pitch
			parallel_player.stream = event.stream # Assuming same master file
			parallel_player.play(preg.x)
	else:
		player.stream = event.alternative_streams[idx] if alternative else event.streams[idx]
		player.play(start_offset)
		
		# Parallel file layering
		var has_parallel = (alternative and event.alternative_parallel_streams.size() > idx) or (not alternative and event.parallel_streams.size() > idx)
		if has_parallel:
			parallel_player = AudioStreamPlayer2D.new()
			add_child(parallel_player)
			parallel_player.bus = target_bus
			parallel_player.volume_db = event.volume_db + random_vol
			parallel_player.pitch_scale = random_pitch
			parallel_player.stream = event.alternative_parallel_streams[idx] if alternative else event.parallel_streams[idx]
			parallel_player.play(start_offset)
			
	# Apply duration limit / automatic cleanup
	if final_duration > 0.0:
		var timer = get_tree().create_timer(final_duration)
		timer.timeout.connect(func(): _on_player_finished(player, event, parallel_player))
	else:
		player.finished.connect(func(): _on_player_finished(player, event, parallel_player))
		
	# Trigger next event in sequence chain immediately (simultaneously)
	if not event.next_event_name.is_empty():
		play_2d(event.next_event_name, start_offset, duration, alternative)
		
	return player

# Plays a 3D Sound Event (returns the main player node)
# source can be a Vector3 (position) or a Node3D (attaches to it)
# source can be a Vector3 (position) or a Node3D (attaches to it)
func play_3d(event_name: String, source = null, start_offset: float = 0.0, duration: float = -1.0, pitch_multiplier: float = 1.0, alternative: bool = false) -> AudioStreamPlayer3D:
	var event: SoundEvent = _events.get(event_name)
	if not event:
		push_warning("[SoundManager] SoundEvent '%s' not found." % event_name)
		return null
		
	_check_polyphony(event)
	
	var idx = event.get_next_variation_index(alternative)
	if idx == -1:
		push_warning("[SoundManager] SoundEvent '%s' has no streams/regions configured." % event_name)
		return null
		
	# Create primary SpatialAudioPlayer3D
	var player = SpatialAudioPlayer3D.new()
	
	_active_instances[event.name].append(player)
	
	# Setup bus routing
	var target_bus = event.category
	if event.effect != "None":
		target_bus += "_" + event.effect
	player.bus = target_bus
	
	# Configure volume, pitch, and attenuation settings BEFORE adding to scene tree
	# so that SpatialAudioPlayer3D's _ready() captures them as base values
	var random_vol = randf_range(-event.volume_randomness_db, event.volume_randomness_db)
	player.volume_db = event.volume_db + random_vol
	
	var random_pitch = randf_range(event.pitch_range.x, event.pitch_range.y) * pitch_multiplier
	player.pitch_scale = random_pitch
	
	# Attenuation ranges
	var is_footstep = "footstep" in event_name
	var is_player_footstep = event_name == "leon_footstep"
	var target_max_distance = 15.0 if is_footstep else event.max_distance
	var target_unit_size = (5.0 if is_player_footstep else 1.0) if is_footstep else event.unit_size
	
	player.max_distance = target_max_distance
	player.unit_size = target_unit_size
	
	# Determine emitter position for area query
	var emitter_pos = Vector3.ZERO
	if source is Node3D:
		emitter_pos = source.global_position
	elif source is Vector3:
		emitter_pos = source
		
	# Check if emitter is inside a ReverbArea or ReverbShape
	var has_reverb = false
	var world_3d : World3D = null
	if source is Node3D:
		world_3d = source.get_world_3d()
	if not world_3d and is_inside_tree():
		world_3d = get_viewport().find_world_3d()
		
	if world_3d:
		var space_state = world_3d.direct_space_state
		if space_state:
			var query = PhysicsPointQueryParameters3D.new()
			query.position = emitter_pos
			query.collide_with_areas = true
			query.collide_with_bodies = false
			var hits = space_state.intersect_point(query)
			for hit in hits:
				var collider = hit.get("collider")
				if collider and (collider.name.to_lower().contains("reverbarea") or collider.name.to_lower().contains("reverbshape")):
					has_reverb = true
					break
					
	# Configure SpatialAudioPlayer3D specific properties
	player.inner_radius = target_unit_size
	player.falloff_distance = maxf(target_max_distance - target_unit_size, 1.0)
	player.enable_volume_attenuation = true
	player.audio_occlusion = true
	player.room_size_reverb = has_reverb
	player.ignore_listener_body = true
	player.panning_strength = 0.85
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	
	if is_footstep:
		# Use inverse square distance falloff for steps
		player.attenuation_function = 4 # natural/inverse square
	else:
		player.attenuation_function = 2 # logarithmic/inverse
		
	# Determine parent attachment and trigger _ready()
	if source is Node3D:
		source.add_child(player)
		player.position = Vector3.ZERO
	else:
		add_child(player)
		if source is Vector3:
			player.global_position = source
			
	# Playback details (Multi-file vs Regions)
	var final_duration = duration
	var parallel_player: AudioStreamPlayer3D = null
	
	if event.use_regions:
		var reg = event.alternative_regions[idx] if alternative else event.regions[idx]
		player.stream = event.stream
		player.play(reg.x)
		if final_duration < 0.0:
			final_duration = reg.y
			
		# Parallel region layering
		var has_parallel = (alternative and event.alternative_parallel_regions.size() > idx) or (not alternative and event.parallel_regions.size() > idx)
		if has_parallel:
			var preg = event.alternative_parallel_regions[idx] if alternative else event.parallel_regions[idx]
			parallel_player = SpatialAudioPlayer3D.new()
			parallel_player.bus = target_bus
			parallel_player.volume_db = event.volume_db + random_vol
			parallel_player.pitch_scale = random_pitch
			parallel_player.stream = event.stream
			
			parallel_player.max_distance = target_max_distance
			parallel_player.unit_size = target_unit_size
			parallel_player.inner_radius = target_unit_size
			parallel_player.falloff_distance = maxf(target_max_distance - target_unit_size, 1.0)
			parallel_player.enable_volume_attenuation = true
			parallel_player.audio_occlusion = true
			parallel_player.room_size_reverb = has_reverb
			parallel_player.ignore_listener_body = true
			parallel_player.panning_strength = 0.85
			parallel_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
			if is_footstep:
				parallel_player.attenuation_function = 4
			else:
				parallel_player.attenuation_function = 2
				
			if source is Node3D:
				source.add_child(parallel_player)
				parallel_player.position = Vector3.ZERO
			else:
				add_child(parallel_player)
				if source is Vector3:
					parallel_player.global_position = source
					
			parallel_player.play(preg.x)
	else:
		player.stream = event.alternative_streams[idx] if alternative else event.streams[idx]
		player.play(start_offset)
		
		# Parallel file layering
		var has_parallel = (alternative and event.alternative_parallel_streams.size() > idx) or (not alternative and event.parallel_streams.size() > idx)
		if has_parallel:
			parallel_player = SpatialAudioPlayer3D.new()
			parallel_player.bus = target_bus
			parallel_player.volume_db = event.volume_db + random_vol
			parallel_player.pitch_scale = random_pitch
			parallel_player.stream = event.alternative_parallel_streams[idx] if alternative else event.parallel_streams[idx]
			
			parallel_player.max_distance = target_max_distance
			parallel_player.unit_size = target_unit_size
			parallel_player.inner_radius = target_unit_size
			parallel_player.falloff_distance = maxf(target_max_distance - target_unit_size, 1.0)
			parallel_player.enable_volume_attenuation = true
			parallel_player.audio_occlusion = true
			parallel_player.room_size_reverb = has_reverb
			parallel_player.ignore_listener_body = true
			parallel_player.panning_strength = 0.85
			parallel_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
			if is_footstep:
				parallel_player.attenuation_function = 4
			else:
				parallel_player.attenuation_function = 2
				
			if source is Node3D:
				source.add_child(parallel_player)
				parallel_player.position = Vector3.ZERO
			else:
				add_child(parallel_player)
				if source is Vector3:
					parallel_player.global_position = source
					
			parallel_player.play(start_offset)
			
	# Apply duration limit / automatic cleanup
	if final_duration > 0.0:
		var timer = get_tree().create_timer(final_duration)
		timer.timeout.connect(func(): _on_player_finished(player, event, parallel_player))
	else:
		player.finished.connect(func(): _on_player_finished(player, event, parallel_player))
		
	# Trigger next event in sequence chain immediately (simultaneously)
	if not event.next_event_name.is_empty():
		play_3d(event.next_event_name, source, start_offset, duration, pitch_multiplier, alternative)
		
	return player

# Stops all instances of a specific sound event name
func stop(event_name: String) -> void:
	var instances = _active_instances.get(event_name, [])
	for inst in instances:
		if is_instance_valid(inst) and inst.playing:
			inst.stop()
			inst.queue_free()
	_active_instances[event_name] = []

# Muffles or unmuffles a main category bus dynamically over a transition duration (with recovery linger)
func set_bus_muffled(category_name: String, enabled: bool, transition_duration: float = 0.1) -> void:
	var bus_idx = AudioServer.get_bus_index(category_name)
	if bus_idx == -1:
		push_warning("[SoundManager] Audio bus '%s' not found." % category_name)
		return
		
	# Find LPF effect on category bus
	var lpf: AudioEffectLowPassFilter = null
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectLowPassFilter:
			lpf = effect
			break
			
	if not lpf:
		push_warning("[SoundManager] Low-pass filter effect not found on bus '%s'." % category_name)
		return
		
	# Kill existing tweens and linger tweens for this bus
	if _muffle_tweens.has(category_name):
		var old_tween = _muffle_tweens[category_name]
		if old_tween and old_tween.is_valid():
			old_tween.kill()
	if _muffle_linger_tweens.has(category_name):
		var old_linger = _muffle_linger_tweens[category_name]
		if old_linger and old_linger.is_valid():
			old_linger.kill()
			
	# Muffled cutoff is 500Hz, clear/normal cutoff is 20000Hz
	var target_cutoff = 500.0 if enabled else 20000.0
	
	if not enabled:
		# Linger the recovery unmuffling for 1.2 seconds so it stays muffled for a bit
		var linger_tween = create_tween()
		_muffle_linger_tweens[category_name] = linger_tween
		linger_tween.tween_interval(1.2)
		linger_tween.tween_callback(func():
			var tween = create_tween()
			_muffle_tweens[category_name] = tween
			tween.tween_property(lpf, "cutoff_hz", target_cutoff, transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		)
	else:
		var tween = create_tween()
		_muffle_tweens[category_name] = tween
		tween.tween_property(lpf, "cutoff_hz", target_cutoff, transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Plays Non-Combat start, transitioning to Non-Combat loop
func play_music_non_combat() -> void:
	if _current_music_state == "NonCombatStart" or _current_music_state == "NonCombatLoop":
		return
	_current_music_state = "NonCombatStart"
	_play_music_stream("Start_Non-combat", "Loop_Non-combat")

# Plays Combat start, transitioning to Combat loop
func play_music_combat() -> void:
	if _current_music_state == "CombatStart" or _current_music_state == "CombatLoop":
		return
	_current_music_state = "CombatStart"
	_play_music_stream("Start_Combat", "Loop_Combat")

# Stops all music players
func stop_music() -> void:
	_current_music_state = "None"
	_next_loop_event = ""
	if _music_player_1.finished.is_connected(_on_music_track_finished):
		_music_player_1.finished.disconnect(_on_music_track_finished)
	if _music_player_2.finished.is_connected(_on_music_track_finished):
		_music_player_2.finished.disconnect(_on_music_track_finished)
	_music_player_1.stop()
	_music_player_2.stop()
	_active_music_player = null

# Internally manages crossfading between music streams with beat-synced scheduling
func _play_music_stream(event_name: String, loop_on_finish_event: String = "", is_gapless: bool = false) -> void:
	if _pending_transition_tween and _pending_transition_tween.is_valid():
		_pending_transition_tween.kill()
		
	var delay_time = 0.0
	if _active_music_player and _active_music_player.playing and transition_sync_mode != "Immediate" and not is_gapless:
		var pos = _active_music_player.get_playback_position()
		var beat_duration = 60.0 / music_bpm
		if transition_sync_mode == "Beat":
			var time_since_last_beat = fmod(pos, beat_duration)
			delay_time = beat_duration - time_since_last_beat
		elif transition_sync_mode == "Bar":
			var bar_duration = beat_duration * music_beats_per_bar
			var time_since_last_bar = fmod(pos, bar_duration)
			delay_time = bar_duration - time_since_last_bar
			
	if delay_time > 0.02:
		_pending_transition_tween = create_tween()
		_pending_transition_tween.tween_interval(delay_time)
		_pending_transition_tween.tween_callback(func(): _execute_music_crossfade(event_name, loop_on_finish_event, is_gapless))
	else:
		_execute_music_crossfade(event_name, loop_on_finish_event, is_gapless)

# Executes the crossfade once the scheduled beat boundary is hit
func _execute_music_crossfade(event_name: String, loop_on_finish_event: String = "", is_gapless: bool = false) -> void:
	var event: SoundEvent = _events.get(event_name)
	if not event:
		push_warning("[SoundManager] Music event '%s' not found." % event_name)
		return
		
	var stream_to_play: AudioStream = null
	if not event.streams.is_empty():
		stream_to_play = event.streams[0]
	elif event.stream:
		stream_to_play = event.stream
		
	if not stream_to_play:
		push_warning("[SoundManager] Music event '%s' has no stream configured." % event_name)
		return
		
	var next_player = _music_player_2 if _active_music_player == _music_player_1 else _music_player_1
	var prev_player = _active_music_player
	
	# Disconnect finished signal to clear previous sequence state
	if _music_player_1.finished.is_connected(_on_music_track_finished):
		_music_player_1.finished.disconnect(_on_music_track_finished)
	if _music_player_2.finished.is_connected(_on_music_track_finished):
		_music_player_2.finished.disconnect(_on_music_track_finished)
		
	next_player.stream = stream_to_play
	
	if is_gapless:
		next_player.volume_db = event.volume_db
		next_player.play()
		if prev_player and prev_player.playing:
			prev_player.stop()
	else:
		next_player.volume_db = -80.0
		next_player.play()
		
	_active_music_player = next_player
	_next_loop_event = loop_on_finish_event
	
	# Setup loop or finished transition callbacks
	if not loop_on_finish_event.is_empty():
		next_player.finished.connect(_on_music_track_finished)
	else:
		next_player.finished.connect(func():
			if _active_music_player == next_player:
				next_player.play()
		)
		if event_name == "Loop_Non-combat":
			_current_music_state = "NonCombatLoop"
		elif event_name == "Loop_Combat":
			_current_music_state = "CombatLoop"
			
	if not is_gapless:
		# Crossfade using linear amplitude to prevent dB volume dipping
		if _music_transition_tween and _music_transition_tween.is_valid():
			_music_transition_tween.kill()
			
		var target_linear = db_to_linear(event.volume_db)
		
		_music_transition_tween = create_tween().set_parallel(true)
		_music_transition_tween.tween_method(
			func(val): next_player.volume_db = linear_to_db(val),
			0.0,
			target_linear,
			music_crossfade_duration
		)
		
		if prev_player and prev_player.playing:
			var prev_linear = db_to_linear(prev_player.volume_db)
			_music_transition_tween.tween_method(
				func(val): prev_player.volume_db = linear_to_db(val),
				prev_linear,
				0.0,
				music_crossfade_duration
			)
			_music_transition_tween.chain().tween_callback(prev_player.stop)

func _on_music_track_finished() -> void:
	if not _next_loop_event.is_empty():
		var loop_ev = _next_loop_event
		_next_loop_event = ""
		_play_music_stream(loop_ev, "", true)
