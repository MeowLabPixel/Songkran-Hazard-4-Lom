extends RefCounted
class_name SoundEventGenerator

func generate_all_events() -> void:
	print("[SoundEventGenerator] Starting SoundEvent resource generation...")
	var audio_root = "res://Audio-Sfx-Music"
	var output_dir = "res://audio_events"
	
	# Ensure output directory exists
	var dir_access = DirAccess.open("res://")
	if not dir_access.dir_exists(output_dir):
		dir_access.make_dir(output_dir)
		
	var files = get_files_recursive(audio_root)
	print("[SoundEventGenerator] Found %d raw audio files." % files.size())
	
	# Pass 1: Build a set of all raw basenames (without variation numbers)
	var raw_basenames = {}
	for filepath in files:
		var raw_name = filepath.get_file().get_basename()
		# Strip trailing variation numbers like _1, _01, _002
		var regex = RegEx.new()
		regex.compile("_\\d+$")
		var m = regex.search(raw_name)
		if m:
			raw_name = raw_name.substr(0, m.get_start())
		raw_basenames[raw_name] = true

	# Group files by base event name
	var groups = {}
	
	for filepath in files:
		var filename = filepath.get_file().get_basename()
		
		# Determine category
		var category = "SFX"
		if "/Voicelines/" in filepath:
			category = "Voiceline"
		elif "/Music/" in filepath:
			category = "Music"
		elif "/Uis/" in filepath:
			category = "UI"
			
		var is_3d = (category == "Voiceline" or category == "SFX")
		var use_regions = filename.begins_with("Region_")
		
		var event_name = filename
		# Strip variation numbers first
		var regex = RegEx.new()
		regex.compile("_\\d+$")
		var m = regex.search(event_name)
		if m:
			event_name = event_name.substr(0, m.get_start())
			
		var type = "normal"
		
		# Determine if suffix stripping is appropriate (does the base name exist in raw_basenames?)
		var check_alternative_add = event_name.replace("_Add_Alternative", "").replace("_Alternative_Add", "")
		var check_add = event_name.replace("_Add", "")
		var check_alternative = event_name.replace("_Alternative", "")
		
		if ("_Add_Alternative" in event_name or "_Alternative_Add" in event_name) and raw_basenames.has(check_alternative_add):
			event_name = check_alternative_add
			type = "alternative_add"
		elif "_Add" in event_name and raw_basenames.has(check_add):
			event_name = check_add
			type = "add"
		elif "_Alternative" in event_name and raw_basenames.has(check_alternative):
			event_name = check_alternative
			type = "alternative"
		
		# Setup sequence chaining for Part1 / Part2
		var next_event_name = ""
		if "Part1" in event_name:
			next_event_name = event_name.replace("Part1", "Part2")
			
		if not groups.has(event_name):
			groups[event_name] = {
				"category": category,
				"is_3d": is_3d,
				"use_regions": use_regions,
				"next_event_name": next_event_name,
				"normals": [],
				"adds": [],
				"alternatives": [],
				"alternative_adds": []
			}
			
		var grp = groups[event_name]
		match type:
			"normal": grp.normals.append(filepath)
			"add": grp.adds.append(filepath)
			"alternative": grp.alternatives.append(filepath)
			"alternative_add": grp.alternative_adds.append(filepath)
			
	print("[SoundEventGenerator] Grouped into %d unique SoundEvents." % groups.size())
	
	# Generate and save resources
	var count = 0
	for ev_name in groups:
		var grp = groups[ev_name]
		var event = SoundEvent.new()
		event.name = ev_name
		event.category = grp.category
		event.is_3d = grp.is_3d
		event.use_regions = grp.use_regions
		event.next_event_name = grp.next_event_name
		
		# Set defaults
		event.volume_db = 0.0
		event.pitch_range = Vector2(0.95, 1.05)
		event.volume_randomness_db = 0.5
		event.max_instances = 0
		if grp.category == "Voiceline":
			event.volume_randomness_db = 0.0 # Keep voicelines flat
			
		if grp.use_regions:
			var stream_path = grp.normals[0] if grp.normals.size() > 0 else ""
			if not stream_path.is_empty():
				var s = load(stream_path)
				event.stream = s
				if s:
					event.regions.append(Vector2(0.0, s.get_length()))
					
			if grp.adds.size() > 0:
				var ps_path = grp.adds[0]
				var ps = load(ps_path)
				if ps:
					event.parallel_streams.append(ps)
					event.parallel_regions.append(Vector2(0.0, ps.get_length()))
					
			if grp.alternatives.size() > 0:
				var alt_path = grp.alternatives[0]
				var alts = load(alt_path)
				if alts:
					event.alternative_streams.append(alts)
					event.alternative_regions.append(Vector2(0.0, alts.get_length()))
					
			if grp.alternative_adds.size() > 0:
				var alta_path = grp.alternative_adds[0]
				var altas = load(alta_path)
				if altas:
					event.alternative_parallel_streams.append(altas)
					event.alternative_parallel_regions.append(Vector2(0.0, altas.get_length()))
		else:
			for filepath in grp.normals:
				var s = load(filepath)
				if s: event.streams.append(s)
			for filepath in grp.adds:
				var s = load(filepath)
				if s: event.parallel_streams.append(s)
			for filepath in grp.alternatives:
				var s = load(filepath)
				if s: event.alternative_streams.append(s)
			for filepath in grp.alternative_adds:
				var s = load(filepath)
				if s: event.alternative_parallel_streams.append(s)
				
		# Save resource
		var save_path = output_dir + "/" + ev_name + ".tres"
		var err = ResourceSaver.save(event, save_path)
		if err == OK:
			count += 1
		else:
			push_error("[SoundEventGenerator] Failed to save SoundEvent resource to %s (error %d)" % [save_path, err])
			
	print("[SoundEventGenerator] Successfully generated %d SoundEvent .tres resource files!" % count)

func get_files_recursive(path: String) -> Array[String]:
	var files: Array[String] = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if not file_name.begins_with("."):
					files.append_array(get_files_recursive(path + "/" + file_name))
			else:
				var lower = file_name.to_lower()
				if lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3"):
					if not "not use" in lower:
						files.append(path + "/" + file_name)
			file_name = dir.get_next()
	return files
