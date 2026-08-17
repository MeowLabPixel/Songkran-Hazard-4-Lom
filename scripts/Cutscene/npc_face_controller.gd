@tool
class_name NPCFaceController
extends Node3D

## Generic NPC Face Controller for Cutscenes & Secondary Characters
## Provides real-time audio dB metering speech flapping, keyframable AnimationPlayer controls,
## dynamic auto-blinking, and material duplication.

enum NPCEyeState {
	DEFAULT,
	ANGRY,
	SURPRISE,
	SAD,
	CLOSED,
}

enum NPCMouthState {
	DEFAULT,
	OPEN_SMALL,
	OPEN_WIDE,
	NATURAL_CLOSE,
	NATURAL_OPEN,
}

@export var head_mesh: MeshInstance3D:
	set(val):
		head_mesh = val
		_update_editor_preview()

@export_group("Surface Indices")
@export var eye_surface_index: int = 0:
	set(val):
		eye_surface_index = val
		_update_editor_preview()

@export var mouth_surface_index: int = 1:
	set(val):
		mouth_surface_index = val
		_update_editor_preview()

@export_group("Eye UV Offsets (X, Y)")
@export var eye_offset_default: Vector2 = Vector2(0.0, 0.0):
	set(val):
		eye_offset_default = val
		_update_editor_preview()

@export var eye_offset_angry: Vector2 = Vector2(0.0, 0.133):
	set(val):
		eye_offset_angry = val
		_update_editor_preview()

@export var eye_offset_surprise: Vector2 = Vector2(0.0, 0.272):
	set(val):
		eye_offset_surprise = val
		_update_editor_preview()

@export var eye_offset_sad: Vector2 = Vector2(0.0, 0.588):
	set(val):
		eye_offset_sad = val
		_update_editor_preview()

@export var eye_offset_closed_blink: Vector2 = Vector2(0.0, 0.703):
	set(val):
		eye_offset_closed_blink = val
		_update_editor_preview()

@export_group("Mouth UV Offsets (X, Y)")
@export var mouth_offset_default: Vector2 = Vector2(0.0, 0.0):
	set(val):
		mouth_offset_default = val
		_update_editor_preview()

@export var mouth_offset_open_small: Vector2 = Vector2(0.0, 0.147):
	set(val):
		mouth_offset_open_small = val
		_update_editor_preview()

@export var mouth_offset_open_wide: Vector2 = Vector2(0.0, 0.284):
	set(val):
		mouth_offset_open_wide = val
		_update_editor_preview()

@export var mouth_offset_natural_close: Vector2 = Vector2(0.001, 0.434):
	set(val):
		mouth_offset_natural_close = val
		_update_editor_preview()

@export var mouth_offset_natural_open: Vector2 = Vector2(0.003, 0.568):
	set(val):
		mouth_offset_natural_open = val
		_update_editor_preview()

@export_group("Custom / Extra Expressions (Optional)")
@export var custom_eye_offsets: Dictionary = {}:
	set(val):
		custom_eye_offsets = val
		_update_editor_preview()

@export var custom_mouth_offsets: Dictionary = {}:
	set(val):
		custom_mouth_offsets = val
		_update_editor_preview()

@export var custom_eye_state: String = "":
	set(val):
		custom_eye_state = val
		_update_editor_preview()

@export var custom_mouth_state: String = "":
	set(val):
		custom_mouth_state = val
		_update_editor_preview()

@export_group("Blinking Settings")
@export var enable_blinking: bool = true
@export var min_blink_interval: float = 2.5
@export var max_blink_interval: float = 5.5
@export var blink_duration: float = 0.15

@export_group("AnimationPlayer / Manual Control")
@export var manual_eye_state: NPCEyeState = NPCEyeState.DEFAULT:
	set(val):
		manual_eye_state = val
		_update_editor_preview()

@export var manual_mouth_state: NPCMouthState = NPCMouthState.DEFAULT:
	set(val):
		manual_mouth_state = val
		_update_editor_preview()

@export var override_speech_open_mouth: NPCMouthState = NPCMouthState.DEFAULT:
	set(val):
		override_speech_open_mouth = val
		_update_editor_preview()

@export var override_speech_close_mouth: NPCMouthState = NPCMouthState.DEFAULT:
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
@export var talk_speed: float = 15.0 ## Lip flap speed

# Internal Speech & Audio Metering State
var is_voiceline_playing: bool = false
var _voiceline_timer: float = 0.0
var _speech_hold_timer: float = 0.0
var _talk_time: float = 0.0
var _audio_is_speaking: bool = false
var _audio_peak_db: float = -80.0
var _was_speaking: bool = false

# Internal Blinking State
var _blink_timer: float = 0.0
var _next_blink_time: float = 3.0
var _is_blinking: bool = false
var _blink_elapsed: float = 0.0

# Current Active States
var current_eye_state: NPCEyeState = NPCEyeState.DEFAULT
var current_mouth_state: NPCMouthState = NPCMouthState.DEFAULT

# Material References
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

	# 2. Check direct children ONLY (non-recursive)
	for child in get_children():
		if child is AudioStreamPlayer3D or child is AudioStreamPlayer:
			voice_player = child
			if not Engine.is_editor_hint():
				_ensure_isolated_voice_bus()
			return

	# 3. Check parent/root
	var p = get_parent()
	if p:
		voice_player = p.get_node_or_null("VoicelineNpc")
		if not voice_player:
			voice_player = p.get_node_or_null("VoicelinePlayer")
		if not voice_player:
			voice_player = p.find_child("VoicelineNpc", true, false)
		if not voice_player:
			voice_player = p.find_child("VoicelinePlayer", true, false)
		if is_instance_valid(voice_player) and not Engine.is_editor_hint():
			_ensure_isolated_voice_bus()

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
	head_mesh = find_child("Head", true, false) as MeshInstance3D
	if not head_mesh:
		head_mesh = find_child("head", true, false) as MeshInstance3D
	if not head_mesh:
		head_mesh = find_child("Head_001", true, false) as MeshInstance3D

	if not head_mesh:
		var curr: Node = get_parent()
		while curr and not head_mesh:
			head_mesh = curr.find_child("Head", true, false) as MeshInstance3D
			if not head_mesh:
				head_mesh = curr.find_child("head", true, false) as MeshInstance3D
			if not head_mesh:
				head_mesh = curr.find_child("Head_001", true, false) as MeshInstance3D
			curr = curr.get_parent()

func _ensure_unique_materials() -> void:
	if not head_mesh:
		return

	# Eye Material
	if eye_surface_index >= 0:
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

	# Mouth Material
	if mouth_surface_index >= 0:
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

	_update_timers(delta)
	_update_audio_metering(delta)
	_evaluate_eye_state()
	_evaluate_mouth_state()
	if enable_blinking:
		_process_blinking(delta)
	_apply_uv_offsets()

func _update_timers(delta: float) -> void:
	if _voiceline_timer > 0.0:
		_voiceline_timer -= delta
		if _voiceline_timer <= 0.0:
			is_voiceline_playing = false

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

func _evaluate_eye_state() -> void:
	current_eye_state = manual_eye_state

func _evaluate_mouth_state() -> void:
	var active_speaking = is_speaking or _audio_is_speaking
	if active_speaking:
		if not _was_speaking:
			_talk_time = (PI * 0.5) / (talk_speed if talk_speed > 0.0 else 15.0)
		_was_speaking = true
	elif _was_speaking:
		_was_speaking = false

	# 1. Hold mouth open override
	if hold_mouth_open:
		if override_speech_open_mouth != NPCMouthState.DEFAULT:
			current_mouth_state = override_speech_open_mouth
		elif manual_mouth_state in [NPCMouthState.OPEN_SMALL, NPCMouthState.OPEN_WIDE, NPCMouthState.NATURAL_OPEN]:
			current_mouth_state = manual_mouth_state
		else:
			current_mouth_state = NPCMouthState.OPEN_SMALL
		return

	# 2. If animator explicitly keyframed an open mouth pose and not speaking, hold it directly
	if not active_speaking and manual_mouth_state in [NPCMouthState.OPEN_SMALL, NPCMouthState.OPEN_WIDE, NPCMouthState.NATURAL_OPEN]:
		current_mouth_state = manual_mouth_state
		return

	# 3. Determine Open & Close Flap Pairs
	var is_surprised = (manual_eye_state == NPCEyeState.SURPRISE)
	var is_crying = (manual_eye_state == NPCEyeState.SAD)
	var is_natural = (manual_mouth_state == NPCMouthState.NATURAL_CLOSE)

	# Target Open Mouth:
	var target_open: NPCMouthState
	if override_speech_open_mouth != NPCMouthState.DEFAULT:
		target_open = override_speech_open_mouth
	elif is_surprised:
		target_open = NPCMouthState.OPEN_WIDE
	elif is_crying or is_natural:
		target_open = NPCMouthState.NATURAL_OPEN
	else:
		target_open = NPCMouthState.OPEN_SMALL

	# Target Close Mouth:
	var target_close: NPCMouthState
	if override_speech_close_mouth != NPCMouthState.DEFAULT:
		target_close = override_speech_close_mouth
	elif is_crying or is_natural:
		target_close = NPCMouthState.NATURAL_CLOSE
	else:
		target_close = manual_mouth_state

	# 4. When Speaking, oscillate between target_open and target_close
	if active_speaking:
		var flap = (sin(_talk_time * talk_speed) + 1.0) * 0.5
		current_mouth_state = target_open if flap > 0.35 else target_close
		return

	# 5. Silent / Resting State
	if is_crying:
		current_mouth_state = NPCMouthState.NATURAL_CLOSE
	else:
		current_mouth_state = manual_mouth_state

func _reset_blink_timer() -> void:
	_blink_timer = 0.0
	_next_blink_time = randf_range(min_blink_interval, max_blink_interval)

func _process_blinking(delta: float) -> void:
	if not enable_blinking or current_eye_state == NPCEyeState.CLOSED:
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

func _get_current_eye_uv() -> Vector2:
	# 1. Blinking takes priority unless already in closed state
	if _is_blinking and current_eye_state != NPCEyeState.CLOSED:
		return eye_offset_closed_blink

	# 2. Check custom string state if set
	if custom_eye_state != "" and custom_eye_offsets.has(custom_eye_state):
		var c_val = custom_eye_offsets[custom_eye_state]
		if c_val is Vector2:
			return c_val
		elif c_val is float or c_val is int:
			return Vector2(0.0, float(c_val))

	# 3. Standard enum states
	match current_eye_state:
		NPCEyeState.DEFAULT:
			return eye_offset_default
		NPCEyeState.ANGRY:
			return eye_offset_angry
		NPCEyeState.SURPRISE:
			return eye_offset_surprise
		NPCEyeState.SAD:
			return eye_offset_sad
		NPCEyeState.CLOSED:
			return eye_offset_closed_blink
		_:
			return eye_offset_default

func _get_current_mouth_uv() -> Vector2:
	# 1. Check custom string state if set
	if custom_mouth_state != "" and custom_mouth_offsets.has(custom_mouth_state):
		var c_val = custom_mouth_offsets[custom_mouth_state]
		if c_val is Vector2:
			return c_val
		elif c_val is float or c_val is int:
			return Vector2(0.0, float(c_val))

	# 2. Standard enum states
	match current_mouth_state:
		NPCMouthState.DEFAULT:
			return mouth_offset_default
		NPCMouthState.OPEN_SMALL:
			return mouth_offset_open_small
		NPCMouthState.OPEN_WIDE:
			return mouth_offset_open_wide
		NPCMouthState.NATURAL_CLOSE:
			return mouth_offset_natural_close
		NPCMouthState.NATURAL_OPEN:
			return mouth_offset_natural_open
		_:
			return mouth_offset_default

func _apply_uv_offsets() -> void:
	var eye_uv: Vector2 = _get_current_eye_uv()
	if _eye_mat:
		_eye_mat.uv1_offset.x = eye_uv.x
		_eye_mat.uv1_offset.y = eye_uv.y

	var mouth_uv: Vector2 = _get_current_mouth_uv()
	if _mouth_mat:
		_mouth_mat.uv1_offset.x = mouth_uv.x
		_mouth_mat.uv1_offset.y = mouth_uv.y

# --- Public API Functions ---

func trigger_voiceline(duration: float = 1.0) -> void:
	is_voiceline_playing = true
	_voiceline_timer = duration

func trigger_speech(duration: float = 1.0) -> void:
	_speech_hold_timer = duration
	_audio_is_speaking = true
