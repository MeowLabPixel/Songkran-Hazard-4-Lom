extends Node

@export var sound_bank: Array[SoundEvent] = []

var _events: Dictionary = {}
var _active_instances: Dictionary = {} # event_name -> Array[Node] (players)
var _muffle_tweens: Dictionary = {} # bus_name -> Tween

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	
	# Generate all sound events dynamically from audio files on disk
	var generator_script = load("res://scripts/audio/sound_event_generator.gd")
	if generator_script:
		var generator = generator_script.new()
		generator.generate_all_events()
	
	# Fallback: if sound_bank is empty, load all generated resources dynamically
	if sound_bank.is_empty():
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
	
	# Pre-cache events into a dictionary for quick lookup
	for event in sound_bank:
		if event and not event.name.is_empty():
			_events[event.name] = event
			_active_instances[event.name] = []
			
	# Initialize/create audio buses dynamically
	_setup_audio_buses()

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
		
		# Ensure each main category bus has an LPF effect for dynamic muffling
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

# Clean up and trigger sequences
func _on_player_finished(player: Node, event: SoundEvent, parallel_player: Node = null) -> void:
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(parallel_player):
		parallel_player.queue_free()
		
	# Trigger next event in sequence chain if configured
	if not event.next_event_name.is_empty():
		if player is AudioStreamPlayer3D:
			# Play 3D sequence at the same place
			var parent = player.get_parent()
			if parent and parent != get_tree().root:
				play_3d(event.next_event_name, parent)
			else:
				play_3d(event.next_event_name, player.global_position)
		else:
			# Play 2D sequence
			play_2d(event.next_event_name)

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
		
	return player

# Plays a 3D Sound Event (returns the main player node)
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
		
	# Create primary player
	var player = AudioStreamPlayer3D.new()
	
	# Determine parent attachment
	if source is Node3D:
		source.add_child(player)
		player.position = Vector3.ZERO
	else:
		add_child(player)
		if source is Vector3:
			player.global_position = source
			
	_active_instances[event.name].append(player)
	
	# Setup bus routing
	var target_bus = event.category
	if event.effect != "None":
		target_bus += "_" + event.effect
	player.bus = target_bus
	
	# Configure volume, pitch, and attenuation settings
	var random_vol = randf_range(-event.volume_randomness_db, event.volume_randomness_db)
	player.volume_db = event.volume_db + random_vol
	
	var random_pitch = randf_range(event.pitch_range.x, event.pitch_range.y) * pitch_multiplier
	player.pitch_scale = random_pitch
	
	player.max_distance = event.max_distance
	player.unit_size = event.unit_size
	
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
			parallel_player = AudioStreamPlayer3D.new()
			if source is Node3D:
				source.add_child(parallel_player)
				parallel_player.position = Vector3.ZERO
			else:
				add_child(parallel_player)
				if source is Vector3:
					parallel_player.global_position = source
					
			parallel_player.bus = target_bus
			parallel_player.volume_db = event.volume_db + random_vol
			parallel_player.pitch_scale = random_pitch
			parallel_player.stream = event.stream
			parallel_player.max_distance = event.max_distance
			parallel_player.unit_size = event.unit_size
			parallel_player.play(preg.x)
	else:
		player.stream = event.alternative_streams[idx] if alternative else event.streams[idx]
		player.play(start_offset)
		
		# Parallel file layering
		var has_parallel = (alternative and event.alternative_parallel_streams.size() > idx) or (not alternative and event.parallel_streams.size() > idx)
		if has_parallel:
			parallel_player = AudioStreamPlayer3D.new()
			if source is Node3D:
				source.add_child(parallel_player)
				parallel_player.position = Vector3.ZERO
			else:
				add_child(parallel_player)
				if source is Vector3:
					parallel_player.global_position = source
					
			parallel_player.bus = target_bus
			parallel_player.volume_db = event.volume_db + random_vol
			parallel_player.pitch_scale = random_pitch
			parallel_player.stream = event.alternative_parallel_streams[idx] if alternative else event.parallel_streams[idx]
			parallel_player.max_distance = event.max_distance
			parallel_player.unit_size = event.unit_size
			parallel_player.play(start_offset)
			
	# Apply duration limit / automatic cleanup
	if final_duration > 0.0:
		var timer = get_tree().create_timer(final_duration)
		timer.timeout.connect(func(): _on_player_finished(player, event, parallel_player))
	else:
		player.finished.connect(func(): _on_player_finished(player, event, parallel_player))
		
	return player

# Stops all instances of a specific sound event name
func stop(event_name: String) -> void:
	var instances = _active_instances.get(event_name, [])
	for inst in instances:
		if is_instance_valid(inst) and inst.playing:
			inst.stop()
			inst.queue_free()
	_active_instances[event_name] = []

# Muffles or unmuffles a main category bus dynamically over a transition duration
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
		
	# Kill existing tween for this bus
	if _muffle_tweens.has(category_name):
		var old_tween = _muffle_tweens[category_name]
		if old_tween and old_tween.is_valid():
			old_tween.kill()
			
	# Muffled cutoff is 500Hz, clear/normal cutoff is 20000Hz
	var target_cutoff = 500.0 if enabled else 20000.0
	
	var tween = create_tween()
	_muffle_tweens[category_name] = tween
	tween.tween_property(lpf, "cutoff_hz", target_cutoff, transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
