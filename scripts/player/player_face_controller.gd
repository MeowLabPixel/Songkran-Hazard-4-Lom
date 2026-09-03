@tool
class_name PlayerFaceController
extends Node3D

enum EyeState {
	DEFAULT,   # 0.0
	ANGRY,     # 0.133
	SURPRISE,  # 0.272
	FOCUS,     # 0.439 (Scale 0.86)
	SAD,       # 0.588 (Scale 0.847)
	CLOSED,    # 0.703
}

enum MouthState {
	DEFAULT,        # 0.0x / 0.0y
	OPEN_SMALL,     # 0.0x / 0.147y
	OPEN_WIDE,      # 0.0x / 0.284y
	NATURAL_CLOSE,  # 0.001x / 0.434y
	NATURAL_OPEN,   # 0.003x / 0.568y (Medium)
}

const EYE_OFFSETS = {
	EyeState.DEFAULT: 0.0,
	EyeState.ANGRY: 0.133,
	EyeState.SURPRISE: 0.272,
	EyeState.FOCUS: 0.439,
	EyeState.SAD: 0.588,
	EyeState.CLOSED: 0.703,
}

const MOUTH_OFFSETS = {
	MouthState.DEFAULT: Vector2(0.0, 0.0),
	MouthState.OPEN_SMALL: Vector2(0.0, 0.147),
	MouthState.OPEN_WIDE: Vector2(0.0, 0.284),
	MouthState.NATURAL_CLOSE: Vector2(0.001, 0.434),
	MouthState.NATURAL_OPEN: Vector2(0.004, 0.568),
}

@export var head_mesh: MeshInstance3D:
	set(val):
		head_mesh = val
		_update_editor_preview()

@export var player: CharacterBody3D

@export_group("Surface Indices")
@export var eye_surface_index: int = 2:
	set(val):
		eye_surface_index = val
		_update_editor_preview()

@export var mouth_surface_index: int = 3:
	set(val):
		mouth_surface_index = val
		_update_editor_preview()

@export_group("Blinking Settings")
@export var enable_blinking: bool = true
@export var min_blink_interval: float = 2.5
@export var max_blink_interval: float = 5.5
@export var blink_duration: float = 0.15

@export_group("Mouth Set Configuration")
@export var use_natural_mouth_set: bool = false:
	set(val):
		use_natural_mouth_set = val
		_update_editor_preview()

@export_group("Cutscene / Manual Animation")
@export var manual_mode: bool = false:
	set(val):
		manual_mode = val
		_update_editor_preview()

@export var manual_eye_state: EyeState = EyeState.DEFAULT:
	set(val):
		manual_eye_state = val
		_update_editor_preview()

@export var manual_mouth_state: MouthState = MouthState.DEFAULT:
	set(val):
		manual_mouth_state = val
		_update_editor_preview()

@export var override_speech_open_mouth: MouthState = MouthState.DEFAULT:
	set(val):
		override_speech_open_mouth = val
		_update_editor_preview()

@export var override_speech_close_mouth: MouthState = MouthState.DEFAULT:
	set(val):
		override_speech_close_mouth = val
		_update_editor_preview()

@export var hold_mouth_open: bool = false:
	set(val):
		hold_mouth_open = val
		_update_editor_preview()

@export var is_speaking: bool = false:
	set(val):
		is_speaking = val
		_update_editor_preview()

@export_group("Real-Time Audio Metering")
@export var voice_player: Node = null ## Optional AudioStreamPlayer or AudioStreamPlayer3D
@export var voice_bus_name: String = "Voiceline"
@export var speech_db_threshold: float = -55.0 ## Silence threshold in dB (accounts for 3D camera distance attenuation)
@export var speech_hold_time: float = 0.15 ## Smoothing buffer in seconds to close mouth on silent pauses
@export var talk_speed: float = 15.0 ## Lip flap cycle speed

# Overrides & Event Flags
var is_hit_reaction: bool = false
var hit_reaction_timer: float = 0.0

var is_grabbed: bool = false
var is_grab_win: bool = false
var is_grab_fail: bool = false
var grab_win_timer: float = 0.0
var grab_fail_timer: float = 0.0
var cry_linger_timer: float = 0.0
var natural_mouth_linger_timer: float = 0.0
var speech_smile_linger_timer: float = 0.0
var _was_hit_or_fail: bool = false
var _was_attacked: bool = false
var _was_speaking: bool = false
var _last_hp: float = 100.0

var is_takedown: bool = false
var is_die: bool = false

var is_aiming: bool = false

var is_voiceline_playing: bool = false
var is_combat: bool = false
var _voiceline_timer: float = 0.0

# Internal Audio Metering & Talking State
var _speech_hold_timer: float = 0.0
var _talk_time: float = 0.0
var _audio_is_speaking: bool = false
var _audio_peak_db: float = -80.0

# Internal Blinking State
var _blink_timer: float = 0.0
var _next_blink_time: float = 3.0
var _is_blinking: bool = false
var _blink_elapsed: float = 0.0

# Current Active States
var current_eye_state: EyeState = EyeState.DEFAULT
var current_mouth_state: MouthState = MouthState.DEFAULT

# Unique Material References
var _eye_mat: StandardMaterial3D = null
var _mouth_mat: StandardMaterial3D = null

var _isolated_bus_name: String = ""

func _exit_tree() -> void:
	if not Engine.is_editor_hint() and _isolated_bus_name != "":
		var idx = AudioServer.get_bus_index(_isolated_bus_name)
		if idx != -1:
			AudioServer.remove_bus(idx)
			_isolated_bus_name = ""

func _ready() -> void:
	if not player:
		var p = get_parent()
		if p is CharacterBody3D:
			player = p
		elif not Engine.is_editor_hint():
			manual_mode = true
	if player and "HP" in player and not Engine.is_editor_hint():
		_last_hp = float(player.HP)
	_ensure_head_mesh()
	if not Engine.is_editor_hint():
		_ensure_voice_player()
	_ensure_unique_materials()
	_reset_blink_timer()
	_update_editor_preview()

func _update_editor_preview() -> void:
	if not is_inside_tree():
		return
	_ensure_head_mesh()
	_ensure_unique_materials()
	_evaluate_eye_state()
	_evaluate_mouth_state()
	_apply_uv_offsets()

func _ensure_voice_player() -> void:
	# 1. If assigned manually in Inspector, respect it 100%
	if is_instance_valid(voice_player):
		if not Engine.is_editor_hint():
			_ensure_isolated_voice_bus()
		return

	# 2. Check direct children
	for child in get_children():
		if child is AudioStreamPlayer3D or child is AudioStreamPlayer:
			voice_player = child
			if not Engine.is_editor_hint():
				_ensure_isolated_voice_bus()
			return

	# 3. Check player root children
	if player:
		voice_player = player.get_node_or_null("VoicelinePlayer")
		if not voice_player:
			voice_player = player.get_node_or_null("AudioStreamPlayer3D")
		if not voice_player:
			voice_player = player.find_child("VoicelinePlayer", true, false)
		if is_instance_valid(voice_player) and not Engine.is_editor_hint():
			_ensure_isolated_voice_bus()
	elif not voice_player:
		var p = get_parent()
		if p:
			voice_player = p.get_node_or_null("VoicelinePlayer")
			if not voice_player:
				voice_player = p.find_child("VoicelinePlayer", true, false)

func _ensure_isolated_voice_bus() -> void:
	if Engine.is_editor_hint():
		return

	if _isolated_bus_name == "":
		var clean_name = name.replace(" ", "_")
		_isolated_bus_name = "Voice_" + clean_name + "_" + str(get_instance_id())

	var bus_idx = AudioServer.get_bus_index(_isolated_bus_name)
	if bus_idx == -1:
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, _isolated_bus_name)

	var parent_bus = voice_bus_name if voice_bus_name != "" else "Voiceline"
	if AudioServer.get_bus_index(parent_bus) != -1:
		AudioServer.set_bus_send(bus_idx, parent_bus)
	else:
		AudioServer.set_bus_send(bus_idx, "Master")

	if is_instance_valid(voice_player):
		voice_player.bus = _isolated_bus_name

func _ensure_head_mesh() -> void:
	if is_instance_valid(head_mesh):
		return
	# 1. Search locally
	head_mesh = find_child("Head", true, false) as MeshInstance3D
	if not head_mesh:
		head_mesh = find_child("head", true, false) as MeshInstance3D
	if not head_mesh and player:
		head_mesh = player.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/Head") as MeshInstance3D

	# 2. Search up ancestor tree
	if not head_mesh:
		var curr: Node = get_parent()
		while curr and not head_mesh:
			head_mesh = curr.find_child("Head", true, false) as MeshInstance3D
			if not head_mesh:
				head_mesh = curr.find_child("head", true, false) as MeshInstance3D
			curr = curr.get_parent()

func _ensure_unique_materials() -> void:
	if not head_mesh:
		return
	
	# Surface 2 - Eyes
	var e_mat = head_mesh.get_surface_override_material(eye_surface_index) as StandardMaterial3D
	if not e_mat:
		var active_e = head_mesh.get_active_material(eye_surface_index)
		if active_e and active_e is StandardMaterial3D:
			e_mat = active_e.duplicate() as StandardMaterial3D
			head_mesh.set_surface_override_material(eye_surface_index, e_mat)
	else:
		if not Engine.is_editor_hint():
			e_mat = e_mat.duplicate() as StandardMaterial3D
			head_mesh.set_surface_override_material(eye_surface_index, e_mat)
	_eye_mat = e_mat

	# Surface 3 - Mouth
	var m_mat = head_mesh.get_surface_override_material(mouth_surface_index) as StandardMaterial3D
	if not m_mat:
		var active_m = head_mesh.get_active_material(mouth_surface_index)
		if active_m and active_m is StandardMaterial3D:
			m_mat = active_m.duplicate() as StandardMaterial3D
			head_mesh.set_surface_override_material(mouth_surface_index, m_mat)
	else:
		if not Engine.is_editor_hint():
			m_mat = m_mat.duplicate() as StandardMaterial3D
			head_mesh.set_surface_override_material(mouth_surface_index, m_mat)
	_mouth_mat = m_mat

func _process(delta: float) -> void:
	if not head_mesh or not _eye_mat or not _mouth_mat:
		_ensure_head_mesh()
		_ensure_unique_materials()
		if not head_mesh:
			return

	if not is_instance_valid(voice_player):
		_ensure_voice_player()

	if not manual_mode and not Engine.is_editor_hint():
		_auto_detect_player_state()

	_update_audio_metering(delta)
	_update_timers(delta)
	_evaluate_eye_state()
	_evaluate_mouth_state()
	if enable_blinking:
		_process_blinking(delta)
	_apply_uv_offsets()

func _update_audio_metering(delta: float) -> void:
	_talk_time += delta
	var has_sound: bool = false

	if is_instance_valid(voice_player):
		var is_active: bool = false
		if voice_player is AudioStreamPlayer3D or voice_player is AudioStreamPlayer:
			is_active = voice_player.has_stream_playback() or voice_player.playing
		elif "playing" in voice_player:
			is_active = bool(voice_player.playing)

		if is_active:
			var target_bus = ""
			if not Engine.is_editor_hint():
				if _isolated_bus_name == "" or String(voice_player.bus) != _isolated_bus_name:
					_ensure_isolated_voice_bus()
				target_bus = _isolated_bus_name
			else:
				target_bus = String(voice_player.bus) if "bus" in voice_player and String(voice_player.bus) != "" else voice_bus_name

			var bus_idx = AudioServer.get_bus_index(target_bus)
			if bus_idx >= 0:
				var peak_l = AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
				var peak_r = AudioServer.get_bus_peak_volume_right_db(bus_idx, 0)
				_audio_peak_db = max(peak_l, peak_r)
				if _audio_peak_db >= speech_db_threshold:
					has_sound = true
			else:
				has_sound = true
				_audio_peak_db = 0.0
		else:
			_audio_peak_db = -80.0
	else:
		_audio_peak_db = -80.0

	if has_sound:
		_speech_hold_timer = speech_hold_time
		_audio_is_speaking = true
	else:
		if _speech_hold_timer > 0.0:
			_speech_hold_timer -= delta
			_audio_is_speaking = true
		else:
			_audio_is_speaking = false

func _auto_detect_player_state() -> void:
	if not player:
		return

	if "is_aimming" in player:
		is_aiming = player.is_aimming

	var sm = player.get_node_or_null("Statemachine")
	if sm and "current_state" in sm and sm.current_state:
		var sname = sm.current_state.name
		is_takedown = (sname == "Takedown")
		is_die = (sname == "Die")

		if sname == "Get_hit":
			is_hit_reaction = true
		elif hit_reaction_timer <= 0.0 and not is_die:
			is_hit_reaction = false

		if sname == "Grab":
			var grab_state_node = sm.current_state
			var is_exit_phase: bool = false
			var last_anim: String = ""

			if "is_exiting" in grab_state_node:
				is_exit_phase = bool(grab_state_node.is_exiting)
			if "last_anim" in grab_state_node:
				last_anim = String(grab_state_node.last_anim)

			if is_exit_phase:
				if last_anim == "Grab/Win":
					is_grab_win = true
					is_grab_fail = false
					is_grabbed = false
				elif last_anim == "Grab/Fail":
					is_grab_fail = true
					is_grab_win = false
					is_grabbed = false
				else:
					is_grabbed = true
					is_grab_win = false
					is_grab_fail = false
			else:
				# QTE Loop Phase before resolution -> SURPRISE eyes
				is_grabbed = true
				is_grab_win = false
				is_grab_fail = false
		else:
			is_grabbed = false
			if grab_win_timer <= 0.0:
				is_grab_win = false
			if grab_fail_timer <= 0.0:
				is_grab_fail = false

		# Return to Idle/Locomotion: clean up all temporary action state flags
		if sname in ["Idle", "Walk", "Run", "Sprint"]:
			if hit_reaction_timer <= 0.0:
				is_hit_reaction = false
			if grab_win_timer <= 0.0:
				is_grab_win = false
			if grab_fail_timer <= 0.0:
				is_grab_fail = false
			is_grabbed = false
			is_takedown = false

	# Detect transition out of hit or grab_fail to start 1.0s cry linger
	var is_currently_hit_or_fail = is_hit_reaction or is_grab_fail
	if is_currently_hit_or_fail:
		_was_hit_or_fail = true
	elif _was_hit_or_fail:
		_was_hit_or_fail = false
		cry_linger_timer = 1.0

	# Detect transition out of being attacked to linger in natural close mouth
	var is_currently_attacked = is_hit_reaction or is_grabbed or is_grab_fail or is_die
	if is_currently_attacked:
		_was_attacked = true
	elif _was_attacked:
		_was_attacked = false
		natural_mouth_linger_timer = 1.8 # Linger in serious/natural close for 1.8s after attack

	var current_hp: float = 100.0
	if player and "HP" in player:
		current_hp = float(player.HP)
		if current_hp < _last_hp:
			natural_mouth_linger_timer = 1.8
		_last_hp = current_hp

	is_combat = _check_is_in_combat()

func _check_is_in_combat() -> bool:
	if is_aiming or is_takedown or is_grabbed or is_grab_win or is_grab_fail or is_hit_reaction or is_die:
		return true

	if player:
		var sm = player.get_node_or_null("Statemachine")
		if sm and "current_state" in sm and sm.current_state:
			var sname = sm.current_state.name
			if sname in ["Takedown", "Grab", "Get_hit", "Knockdown", "Die"]:
				return true

	var sound_mgr = get_node_or_null("/root/SoundManager")
	if sound_mgr and "_current_music_state" in sound_mgr:
		if sound_mgr._current_music_state in ["CombatStart", "CombatLoop"]:
			return true

	if player:
		var tree = player.get_tree()
		if tree:
			var enemies = tree.get_nodes_in_group("enemies")
			for enemy in enemies:
				if is_instance_valid(enemy) and enemy is Node3D:
					if player.global_position.distance_to(enemy.global_position) <= 12.0:
						return true

	return false

func _update_timers(delta: float) -> void:
	if hit_reaction_timer > 0.0:
		hit_reaction_timer -= delta
		if hit_reaction_timer <= 0.0:
			is_hit_reaction = false

	if grab_win_timer > 0.0:
		grab_win_timer -= delta
		if grab_win_timer <= 0.0:
			is_grab_win = false

	if grab_fail_timer > 0.0:
		grab_fail_timer -= delta
		if grab_fail_timer <= 0.0:
			is_grab_fail = false

	if cry_linger_timer > 0.0:
		cry_linger_timer -= delta

	if natural_mouth_linger_timer > 0.0:
		natural_mouth_linger_timer -= delta

	if speech_smile_linger_timer > 0.0:
		speech_smile_linger_timer -= delta

	if _voiceline_timer > 0.0:
		_voiceline_timer -= delta
		if _voiceline_timer <= 0.0:
			is_voiceline_playing = false

func _evaluate_eye_state() -> void:
	if manual_mode:
		current_eye_state = manual_eye_state
		return

	var current_hp: float = 100.0
	var max_hp: float = 100.0
	if player:
		if "HP" in player and player.HP != null:
			current_hp = float(player.HP)
		if "MaxHP" in player and player.MaxHP != null:
			max_hp = float(player.MaxHP)

	var is_low_hp: bool = (max_hp > 0.0) and ((current_hp / max_hp) <= 0.50)

	# Priority 1: Surprised Eyes (Active Grab Loop overrides crying linger)
	if is_grabbed:
		current_eye_state = EyeState.SURPRISE
		return

	# Priority 2: Angry Eyes (Takedown or Grab Win Success overrides crying linger)
	if is_takedown or is_grab_win:
		current_eye_state = EyeState.ANGRY
		return

	# Priority 3: Crying / Sad Eyes (Active Get_hit, Die, Grab Fail, or 1.0s Linger duration)
	if is_hit_reaction or is_die or is_grab_fail or cry_linger_timer > 0.0:
		current_eye_state = EyeState.SAD
		return

	# Priority 4: Aiming (Only reached when 1.0s cry linger duration has finished)
	if is_aiming:
		if is_low_hp:
			current_eye_state = EyeState.FOCUS
		else:
			current_eye_state = EyeState.ANGRY
		return

	# Priority 5: Baseline Idle / Locomotion depending on HP
	if current_hp <= 30.0:
		current_eye_state = EyeState.CLOSED
	elif is_low_hp:
		current_eye_state = EyeState.SAD
	else:
		current_eye_state = EyeState.DEFAULT

func _evaluate_mouth_state() -> void:
	var active_speaking = is_speaking or _audio_is_speaking
	
	if active_speaking:
		if not _was_speaking:
			_talk_time = (PI * 0.5) / (talk_speed if talk_speed > 0.0 else 15.0)
		_was_speaking = true
		speech_smile_linger_timer = 1.0 # primed to 1.0s while speaking
	elif _was_speaking:
		_was_speaking = false
		speech_smile_linger_timer = 1.0 # countdown starts when speaking finishes

	# --- 1. Manual / Cutscene Mode ---
	if manual_mode:
		# A. Hold mouth open override
		if hold_mouth_open:
			if override_speech_open_mouth != MouthState.DEFAULT:
				current_mouth_state = override_speech_open_mouth
			elif manual_mouth_state in [MouthState.OPEN_SMALL, MouthState.OPEN_WIDE, MouthState.NATURAL_OPEN]:
				current_mouth_state = manual_mouth_state
			else:
				current_mouth_state = MouthState.OPEN_SMALL
			return

		# B. If animator keyframed an explicit open mouth pose and not speaking, hold it directly
		if not active_speaking and manual_mouth_state in [MouthState.OPEN_SMALL, MouthState.OPEN_WIDE, MouthState.NATURAL_OPEN]:
			current_mouth_state = manual_mouth_state
			return

		# C. Determine Open & Close Flap Pairs
		var is_manual_surprised = (manual_eye_state == EyeState.SURPRISE)
		var is_manual_crying = (manual_eye_state == EyeState.SAD)
		var is_manual_natural = (manual_mouth_state == MouthState.NATURAL_CLOSE or use_natural_mouth_set)

		# Target Open Mouth:
		var target_open: MouthState
		if override_speech_open_mouth != MouthState.DEFAULT:
			target_open = override_speech_open_mouth
		elif is_manual_surprised:
			target_open = MouthState.OPEN_WIDE
		elif is_manual_crying or is_manual_natural:
			target_open = MouthState.NATURAL_OPEN
		else:
			target_open = MouthState.OPEN_SMALL

		# Target Close Mouth:
		var target_close: MouthState
		if override_speech_close_mouth != MouthState.DEFAULT:
			target_close = override_speech_close_mouth
		elif is_manual_crying or is_manual_natural:
			target_close = MouthState.NATURAL_CLOSE
		else:
			target_close = manual_mouth_state

		# D. When Speaking, oscillate between target_open and target_close
		if active_speaking:
			var flap = (sin(_talk_time * talk_speed) + 1.0) * 0.5
			current_mouth_state = target_open if flap > 0.35 else target_close
			return

		# E. Silent / Resting State
		if is_manual_crying:
			current_mouth_state = MouthState.NATURAL_CLOSE
		elif speech_smile_linger_timer > 0.0 and is_manual_natural:
			current_mouth_state = MouthState.NATURAL_CLOSE
		else:
			current_mouth_state = manual_mouth_state
		return

	# --- 2. Gameplay Mode ---
	var is_currently_attacked = is_hit_reaction or is_grabbed or is_grab_fail or is_die
	var is_crying = (current_eye_state == EyeState.SAD) or is_currently_attacked or (cry_linger_timer > 0.0)
	var is_surprised = (current_eye_state == EyeState.SURPRISE) or is_grabbed
	var is_natural = use_natural_mouth_set or is_currently_attacked or (natural_mouth_linger_timer > 0.0)

	# 1. Active Hurt / Attacked
	if is_currently_attacked:
		if is_die or is_surprised:
			current_mouth_state = MouthState.OPEN_WIDE
		else:
			var pain_flap = (sin(_talk_time * (talk_speed * 0.8)) + 1.0) * 0.5
			if pain_flap > 0.40:
				current_mouth_state = MouthState.OPEN_WIDE if (is_hit_reaction or is_grab_fail) else MouthState.NATURAL_OPEN
			else:
				current_mouth_state = MouthState.NATURAL_CLOSE
		return

	# 2. Gameplay Speaking Flap Pairs
	if active_speaking:
		var target_open: MouthState
		if is_surprised:
			target_open = MouthState.OPEN_WIDE
		elif is_crying or is_natural:
			target_open = MouthState.NATURAL_OPEN
		else:
			target_open = MouthState.OPEN_SMALL

		var target_close: MouthState
		if is_crying or is_natural or is_surprised:
			target_close = MouthState.NATURAL_CLOSE
		else:
			target_close = MouthState.DEFAULT

		var flap = (sin(_talk_time * talk_speed) + 1.0) * 0.5
		current_mouth_state = target_open if flap > 0.35 else target_close
		return

	# 3. Gameplay Resting State
	if is_surprised:
		current_mouth_state = MouthState.OPEN_WIDE
	elif is_crying or is_natural:
		current_mouth_state = MouthState.NATURAL_CLOSE
	else:
		current_mouth_state = MouthState.DEFAULT

func _get_blink_rate_multiplier() -> float:
	match current_eye_state:
		EyeState.FOCUS:
			return 1.75 # Slower by 75%
		EyeState.ANGRY:
			return 1.50 # Slower by 50%
		_:
			return 1.0

func _reset_blink_timer() -> void:
	_blink_timer = 0.0
	var mult = _get_blink_rate_multiplier()
	_next_blink_time = randf_range(min_blink_interval, max_blink_interval) * mult

func _process_blinking(delta: float) -> void:
	if not enable_blinking or current_eye_state == EyeState.CLOSED:
		_is_blinking = false
		return

	if _is_blinking:
		_blink_elapsed += delta
		if _blink_elapsed >= blink_duration:
			_is_blinking = false
			_reset_blink_timer()
	else:
		_blink_timer += delta
		if _blink_timer >= _next_blink_time:
			_is_blinking = true
			_blink_elapsed = 0.0

func _apply_uv_offsets() -> void:
	# Eye UV
	var active_eye: EyeState = EyeState.CLOSED if _is_blinking else current_eye_state
	var eye_uv_y: float = EYE_OFFSETS.get(active_eye, 0.0)

	if _eye_mat:
		_eye_mat.uv1_offset.y = eye_uv_y
		if active_eye == EyeState.SAD:
			_eye_mat.uv1_scale.y = 0.847
		elif active_eye == EyeState.FOCUS:
			_eye_mat.uv1_scale.y = 0.86
		else:
			_eye_mat.uv1_scale.y = 1.0

	# Mouth UV
	var mouth_uv: Vector2 = MOUTH_OFFSETS.get(current_mouth_state, Vector2.ZERO)
	if _mouth_mat:
		_mouth_mat.uv1_offset.x = mouth_uv.x
		_mouth_mat.uv1_offset.y = mouth_uv.y

# --- Public API Functions ---

func notify_hit(duration: float = 0.8) -> void:
	is_hit_reaction = true
	hit_reaction_timer = duration
	cry_linger_timer = 1.0

func notify_grabbed(grabbed: bool) -> void:
	is_grabbed = grabbed

func notify_takedown(active: bool) -> void:
	is_takedown = active

func notify_grab_win(duration: float = 1.2) -> void:
	is_grab_win = true
	grab_win_timer = duration

func notify_grab_fail(duration: float = 1.2) -> void:
	is_grab_fail = true
	grab_fail_timer = duration
	cry_linger_timer = 1.0

func set_aiming(aiming: bool) -> void:
	is_aiming = aiming

func set_mouth_state(state: MouthState) -> void:
	current_mouth_state = state

func trigger_voiceline(duration: float = 1.0, is_combat_speech: bool = false) -> void:
	is_voiceline_playing = true
	is_combat = is_combat_speech
	_voiceline_timer = duration

func set_voiceline_playing(playing: bool, combat: bool = false) -> void:
	is_voiceline_playing = playing
	is_combat = combat
	if playing and _voiceline_timer <= 0.0:
		_voiceline_timer = 1.0
