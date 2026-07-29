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
@export_range(-80.0, 12.0) var parallel_layer_volume_db: float = 0.0
@export_range(-80.0, 12.0) var alternative_layer_volume_db: float = 0.0

@export_group("Muffle Settings")
@export var enable_muffle: bool = true:
	set(val):
		enable_muffle = val
		if not val:
			_disable_all_muffle()
@export var default_muffle_cutoff: float = 500.0
@export var default_muffle_duration: float = 0.3

@export_group("Spatial Audio Controls")
@export var enable_spatial_effects: bool = true:
	set(val):
		enable_spatial_effects = val
		_update_spatial_effects()
@export var enable_doppler: bool = false:
	set(val):
		enable_doppler = val
		_update_doppler_settings()

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
@export var enable_pitch_randomization: bool = true
@export var sound_bank: Array[SoundEvent] = []

@export_group("Voiceline Control Settings")
@export_range(0.0, 1.0) var voiceline_play_chance: float = 0.5
@export var voiceline_cooldown_min: float = 3.0
@export var voiceline_cooldown_max: float = 5.0

var _events: Dictionary = {}
var _voiceline_cooldowns: Dictionary = {}
var _active_instances: Dictionary = {} # event_name -> Array[Node] (players)
var _muffle_tweens: Dictionary = {} # bus_name -> Tween
var _muffle_linger_tweens: Dictionary = {} # bus_name -> Tween
var _all_spatial_players: Array[AudioStreamPlayer3D] = []
var audio_listener: AudioListener3D = null


func _get_clean_basis(raw_basis: Basis) -> Basis:
	var back = raw_basis.z.normalized()
	var up = raw_basis.y.normalized()
	var right = up.cross(back).normalized()
	up = back.cross(right).normalized()
	return Basis(right, up, back)


func _physics_process(_delta: float) -> void:
	# Keep only valid instances in the list
	var alive: Array[AudioStreamPlayer3D] = []
	for p in _all_spatial_players:
		if is_instance_valid(p):
			alive.append(p)
			if p.has_meta("follow_target"):
				var target = p.get_meta("follow_target")
				if is_instance_valid(target):
					p.global_position = target.global_position
	_all_spatial_players = alive

	# Track player node and camera to update the global unscaled audio listener
	var player_node = get_tree().get_first_node_in_group("player")
	var camera: Camera3D = null
	if player_node != null:
		camera = player_node.get_node_or_null("Camera/edgeSpringArm3D/rearSpringArm3D/Camera3D") as Camera3D
	if camera == null:
		camera = get_viewport().get_camera_3d()

	if camera != null:
		if "use_listener" in camera:
			camera.use_listener = false

	if audio_listener != null:
		if player_node != null and camera != null:
			audio_listener.global_position = player_node.global_position + Vector3(0, 1.5, 0)
			audio_listener.global_basis = _get_clean_basis(camera.global_basis)
		elif camera != null:
			audio_listener.global_position = camera.global_position
			audio_listener.global_basis = _get_clean_basis(camera.global_basis)


func _initialize_spatial_player(p: AudioStreamPlayer3D, source) -> void:
	add_child(p)
	if source is Node3D:
		p.global_position = source.global_position
		p.set_meta("follow_target", source)
	elif source is Vector3:
		p.global_position = source


func _set_bus_vol(bus_name: String, db: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, db)

# Interactive Music Players & State
var _music_player_1: AudioStreamPlayer
var _music_player_2: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer = null
var _music_transition_tween: Tween = null
var _pending_transition_tween: Tween = null
var _next_loop_event: String = ""
var _current_music_state: String = "None"


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
	
	# Load all sound event resources dynamically from disk
	_load_sound_bank_from_disk()
	
	# Initialize/create audio buses dynamically
	_setup_audio_buses()
	
	# Instantiate and set the global audio listener at the root level (under SoundManager)
	# to avoid inherited scale distortion from the player character scene.
	audio_listener = AudioListener3D.new()
	add_child(audio_listener)
	audio_listener.make_current()
	
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
	
	# Start playing ambient/non-combat music after a brief moment (Disabled: started dynamically in world scene)
	# get_tree().create_timer(0.1).timeout.connect(play_music_non_combat)
	
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
				
				# Add effect to sub-bus (only if not SFX category)
				if category != "SFX":
					match effect:
						"Reverb":
							var reverb = AudioEffectReverb.new()
							reverb.room_size = 0.4
							reverb.wet = 0.25
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

func _should_block_voiceline(event_name: String, source = null) -> bool:
	# Only apply to zombie and Anchalee voicelines (excluding breathing sounds)
	var is_zombie = event_name.begins_with("vo_zombie_")
	var is_anchalee = event_name.begins_with("vo_anchalee_") and not event_name.begins_with("vo_anchalee_Exhausted") and not event_name.begins_with("vo_anchalee_Panting")
	
	if not is_zombie and not is_anchalee:
		return false
		
	var time_now = Time.get_ticks_msec() / 1000.0
	
	# Clean up expired cooldown entries to prevent memory growth
	var expired_keys = []
	for key in _voiceline_cooldowns:
		if time_now >= _voiceline_cooldowns[key]:
			expired_keys.append(key)
	for key in expired_keys:
		_voiceline_cooldowns.erase(key)
		
	# Determine the tracking key: instance_id of source if valid node, otherwise generic string prefix
	var tracking_key = ""
	if typeof(source) == TYPE_OBJECT and is_instance_valid(source):
		tracking_key = str(source.get_instance_id())
	else:
		tracking_key = "zombie" if is_zombie else "anchalee"
		
	# 1. Cooldown Check
	if _voiceline_cooldowns.has(tracking_key):
		var cooldown_end = _voiceline_cooldowns[tracking_key]
		if time_now < cooldown_end:
			# Cooldown active, block playing
			return true
			
	# 2. Play Chance Check
	if randf() > voiceline_play_chance:
		# Block playing but do not trigger full 3-5s cooldown (so it can try next time)
		return true
		
	# Passed both checks! We will play the voiceline.
	# Set a new random cooldown between min and max settings.
	var cooldown_duration = randf_range(voiceline_cooldown_min, voiceline_cooldown_max)
	_voiceline_cooldowns[tracking_key] = time_now + cooldown_duration
	return false

# Plays a 2D Sound Event (returns the main player node)
func play_2d(event_name: String, start_offset: float = 0.0, duration: float = -1.0, alternative: bool = false) -> AudioStreamPlayer2D:
	if _should_block_voiceline(event_name, null):
		return null
		
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
			var use_alt_layer_vol = alternative if event_name != "watergun_hit" else false
			var layer_vol_offset = (alternative_layer_volume_db + event.alternative_volume_db) if use_alt_layer_vol else (parallel_layer_volume_db + event.parallel_volume_db)
			parallel_player.volume_db = event.volume_db + random_vol + layer_vol_offset
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
			var use_alt_layer_vol = alternative if event_name != "watergun_hit" else false
			var layer_vol_offset = (alternative_layer_volume_db + event.alternative_volume_db) if use_alt_layer_vol else (parallel_layer_volume_db + event.parallel_volume_db)
			parallel_player.volume_db = event.volume_db + random_vol + layer_vol_offset
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
	if _should_block_voiceline(event_name, source):
		return null
		
	var event: SoundEvent = _events.get(event_name)
	if not event:
		push_warning("[SoundManager] SoundEvent '%s' not found." % event_name)
		return null
		
	_check_polyphony(event)
	
	var lookup_alt = false if event_name == "watergun_hit" else alternative
	var idx = event.get_next_variation_index(lookup_alt)
	if idx == -1:
		push_warning("[SoundManager] SoundEvent '%s' has no streams/regions configured." % event_name)
		return null
		
	# Create primary AudioStreamPlayer3D
	var player = AudioStreamPlayer3D.new()
	player.set_meta("event_name", event_name)
	_all_spatial_players.append(player)
	
	_active_instances[event.name].append(player)
	
	# Setup bus routing
	var target_bus = event.category
	if event.effect != "None":
		target_bus += "_" + event.effect
	player.bus = target_bus
	
	var random_vol = randf_range(-event.volume_randomness_db, event.volume_randomness_db)
	player.volume_db = event.volume_db + random_vol
	
	var random_pitch = (randf_range(event.pitch_range.x, event.pitch_range.y) * pitch_multiplier) if enable_pitch_randomization else 1.0
	player.pitch_scale = random_pitch
	
	# Attenuation ranges
	var target_max_distance = event.max_distance
	var target_unit_size = event.unit_size
	
	player.max_distance = target_max_distance
	player.unit_size = target_unit_size
	player.attenuation_filter_cutoff_hz = 20500.0
	player.attenuation_filter_db = 0.0
	
	var is_player_sound = (
		event_name.begins_with("watergun_pistol_") or 
		event_name.begins_with("Superpump_") or 
		event_name == "leon_footstep" or 
		event_name.begins_with("vo_leon_")
	)
	if not enable_spatial_effects or is_player_sound:
		player.panning_strength = 0.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	else:
		player.panning_strength = 0.85
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP if enable_doppler else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	
	# Playback details (Multi-file vs Regions)
	var final_duration = duration
	var parallel_player: AudioStreamPlayer3D = null
	
	if event.use_regions:
		var reg = event.alternative_regions[idx] if alternative else event.regions[idx]
		player.stream = event.stream
		_initialize_spatial_player(player, source)
		player.play(reg.x)
		if final_duration < 0.0:
			final_duration = reg.y
			
		# Parallel region layering
		var has_parallel = (alternative and event.alternative_parallel_regions.size() > idx) or (not alternative and event.parallel_regions.size() > idx)
		if has_parallel:
			var preg = event.alternative_parallel_regions[idx] if alternative else event.parallel_regions[idx]
			parallel_player = AudioStreamPlayer3D.new()
			parallel_player.set_meta("event_name", event_name)
			_all_spatial_players.append(parallel_player)
			parallel_player.bus = target_bus
			var use_alt_layer_vol = alternative if event_name != "watergun_hit" else false
			var layer_vol_offset = (alternative_layer_volume_db + event.alternative_volume_db) if use_alt_layer_vol else (parallel_layer_volume_db + event.parallel_volume_db)
			parallel_player.volume_db = event.volume_db + random_vol + layer_vol_offset
			parallel_player.pitch_scale = random_pitch
			parallel_player.stream = event.stream
			
			parallel_player.max_distance = target_max_distance
			parallel_player.unit_size = target_unit_size
			parallel_player.attenuation_filter_cutoff_hz = 20500.0
			parallel_player.attenuation_filter_db = 0.0
			
			if not enable_spatial_effects or is_player_sound:
				parallel_player.panning_strength = 0.0
				parallel_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			else:
				parallel_player.panning_strength = 0.85
				parallel_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
				
			parallel_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP if enable_doppler else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
				
			_initialize_spatial_player(parallel_player, source)
			parallel_player.play(preg.x)
	else:
		if event_name == "watergun_hit":
			player.stream = event.streams[idx]
		else:
			player.stream = event.alternative_streams[idx] if alternative else event.streams[idx]
		_initialize_spatial_player(player, source)
		player.play(start_offset)
		
		# Parallel file layering
		var has_parallel = false
		if event_name == "watergun_hit":
			has_parallel = alternative and (event.parallel_streams.size() > 0)
		else:
			has_parallel = (alternative and event.alternative_parallel_streams.size() > idx) or (not alternative and event.parallel_streams.size() > idx)

		if has_parallel:
			parallel_player = AudioStreamPlayer3D.new()
			parallel_player.set_meta("event_name", event_name)
			_all_spatial_players.append(parallel_player)
			parallel_player.bus = target_bus
			var use_alt_layer_vol = alternative if event_name != "watergun_hit" else false
			var layer_vol_offset = (alternative_layer_volume_db + event.alternative_volume_db) if use_alt_layer_vol else (parallel_layer_volume_db + event.parallel_volume_db)
			parallel_player.volume_db = event.volume_db + random_vol + layer_vol_offset
			parallel_player.pitch_scale = random_pitch
			if event_name == "watergun_hit":
				var parallel_idx = idx % event.parallel_streams.size()
				parallel_player.stream = event.parallel_streams[parallel_idx]
			else:
				parallel_player.stream = event.alternative_parallel_streams[idx] if alternative else event.parallel_streams[idx]
			
			parallel_player.max_distance = target_max_distance
			parallel_player.unit_size = target_unit_size
			parallel_player.attenuation_filter_cutoff_hz = 20500.0
			parallel_player.attenuation_filter_db = 0.0
			
			if not enable_spatial_effects or is_player_sound:
				parallel_player.panning_strength = 0.0
				parallel_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			else:
				parallel_player.panning_strength = 0.85
				parallel_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
				
			parallel_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP if enable_doppler else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
				
			_initialize_spatial_player(parallel_player, source)
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

func _disable_all_muffle() -> void:
	var buses = ["Master", "SFX", "Music", "UI", "Voiceline"]
	for category in buses:
		var bus_idx = AudioServer.get_bus_index(category)
		if bus_idx != -1:
			for i in range(AudioServer.get_bus_effect_count(bus_idx)):
				var effect = AudioServer.get_bus_effect(bus_idx, i)
				if effect is AudioEffectLowPassFilter:
					effect.cutoff_hz = 20000.0
		if _muffle_tweens.has(category):
			var t = _muffle_tweens[category]
			if t and t.is_valid():
				t.kill()
		if _muffle_linger_tweens.has(category):
			var l = _muffle_linger_tweens[category]
			if l and l.is_valid():
				l.kill()

func _update_spatial_effects() -> void:
	for p in _all_spatial_players:
		if is_instance_valid(p):
			var event_name = p.get_meta("event_name") if p.has_meta("event_name") else ""
			var is_player_sound = (
				event_name.begins_with("watergun_pistol_") or 
				event_name.begins_with("Superpump_") or 
				event_name == "leon_footstep" or 
				event_name.begins_with("vo_leon_")
			)
			if not enable_spatial_effects or is_player_sound:
				p.panning_strength = 0.0
				p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			else:
				p.panning_strength = 0.85
				p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

func _update_doppler_settings() -> void:
	for p in _all_spatial_players:
		if is_instance_valid(p):
			p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP if enable_doppler else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED

# Muffles or unmuffles a main category bus dynamically over a transition duration (with recovery linger)
func set_bus_muffled(category_name: String, enabled: bool, transition_duration: float = 0.1) -> void:
	if not enable_muffle:
		enabled = false

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

# Plays Main Theme
func play_main_theme() -> void:
	if _current_music_state == "MainTheme":
		return
	_current_music_state = "MainTheme"
	_play_music_stream("MainTheme")

# Returns whether the current music is MainTheme
func is_playing_main_theme() -> bool:
	return _current_music_state == "MainTheme"

# Fades out all active music players smoothly over duration
func fade_out_music(duration: float = 1.0) -> void:
	_current_music_state = "None"
	_next_loop_event = ""
	if _music_player_1.finished.is_connected(_on_music_track_finished):
		_music_player_1.finished.disconnect(_on_music_track_finished)
	if _music_player_2.finished.is_connected(_on_music_track_finished):
		_music_player_2.finished.disconnect(_on_music_track_finished)
	
	var tween = create_tween().set_parallel(true)
	if _music_player_1.playing:
		tween.tween_property(_music_player_1, "volume_db", -80.0, duration)
	if _music_player_2.playing:
		tween.tween_property(_music_player_2, "volume_db", -80.0, duration)
	
	tween.finished.connect(func():
		_music_player_1.stop()
		_music_player_2.stop()
		_music_player_1.volume_db = 0.0
		_music_player_2.volume_db = 0.0
		_active_music_player = null
	)

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
