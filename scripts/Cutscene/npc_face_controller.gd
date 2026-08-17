class_name NPCFaceController
extends Node3D

## Generic NPC Face Controller for Cutscenes & Secondary Characters
## Provides real-time audio dB metering speech flapping, keyframable AnimationPlayer controls,
## dynamic auto-blinking, and material duplication.

enum NPCEyeState {
	DEFAULT,   # 0.0
	ANGRY,     # 0.133
	SURPRISE,  # 0.272
	SAD,       # 0.588
	CLOSED,    # 0.703
}

enum NPCMouthState {
	DEFAULT,        # 0.0x / 0.0y
	OPEN_SMALL,     # 0.0x / 0.147y
	OPEN_WIDE,      # 0.0x / 0.284y
	NATURAL_CLOSE,  # 0.001x / 0.434y
	NATURAL_OPEN,   # 0.003x / 0.568y
}

const DEFAULT_EYE_OFFSETS = {
	NPCEyeState.DEFAULT: 0.0,
	NPCEyeState.ANGRY: 0.133,
	NPCEyeState.SURPRISE: 0.272,
	NPCEyeState.SAD: 0.588,
	NPCEyeState.CLOSED: 0.703,
}

const DEFAULT_MOUTH_OFFSETS = {
	NPCMouthState.DEFAULT: Vector2(0.0, 0.0),
	NPCMouthState.OPEN_SMALL: Vector2(0.0, 0.147),
	NPCMouthState.OPEN_WIDE: Vector2(0.0, 0.284),
	NPCMouthState.NATURAL_CLOSE: Vector2(0.001, 0.434),
	NPCMouthState.NATURAL_OPEN: Vector2(0.003, 0.568),
}

@export var head_mesh: MeshInstance3D

@export_group("Surface Indices")
@export var eye_surface_index: int = 0
@export var mouth_surface_index: int = 1

@export_group("Blinking Settings")
@export var enable_blinking: bool = true
@export var min_blink_interval: float = 2.5
@export var max_blink_interval: float = 5.5
@export var blink_duration: float = 0.15

@export_group("AnimationPlayer / Manual Control")
@export var manual_eye_state: NPCEyeState = NPCEyeState.DEFAULT ## Eye expression keyframable in AnimationPlayer
@export var manual_mouth_state: NPCMouthState = NPCMouthState.DEFAULT ## Resting mouth shape keyframable in AnimationPlayer
@export var is_speaking: bool = false ## Manual flag to force speech flapping if needed

@export_group("Real-Time Audio Metering")
@export var voice_player: Node = null ## Optional AudioStreamPlayer or AudioStreamPlayer3D
@export var voice_bus_name: String = "Voiceline"
@export var speech_db_threshold: float = -55.0 ## Silence threshold in dB (accounts for 3D camera distance attenuation)
@export var speech_hold_time: float = 0.20 ## Smoothing buffer in seconds to close mouth on silent pauses
@export var talk_speed: float = 12.0 ## Lip flap speed

# Internal Speech & Audio Metering State
var is_voiceline_playing: bool = false
var _voiceline_timer: float = 0.0
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
var current_eye_state: NPCEyeState = NPCEyeState.DEFAULT
var current_mouth_state: NPCMouthState = NPCMouthState.DEFAULT

# Material References
var _eye_mat: StandardMaterial3D = null
var _mouth_mat: StandardMaterial3D = null

func _ready() -> void:
	_ensure_head_mesh()
	_ensure_voice_player()
	_ensure_unique_materials()
	_reset_blink_timer()

func _ensure_voice_player() -> void:
	if not is_instance_valid(voice_player):
		voice_player = find_child("VoicelinePlayer", true, false)
		if not voice_player:
			voice_player = find_child("AudioStreamPlayer3D", true, false)
		if not voice_player:
			var p = get_parent()
			if p:
				voice_player = p.get_node_or_null("VoicelinePlayer")
				if not voice_player:
					voice_player = p.find_child("VoicelinePlayer", true, false)
				if not voice_player:
					voice_player = p.find_child("AudioStreamPlayer3D", true, false)

func _ensure_head_mesh() -> void:
	if not head_mesh:
		head_mesh = find_child("Head", true, false) as MeshInstance3D
		if not head_mesh:
			head_mesh = find_child("head", true, false) as MeshInstance3D

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
		var is_playing: bool = false
		if "playing" in voice_player:
			is_playing = bool(voice_player.playing)

		if is_playing:
			var target_bus = voice_bus_name
			if "bus" in voice_player and String(voice_player.bus) != "":
				target_bus = String(voice_player.bus)

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
	elif is_voiceline_playing:
		var bus_idx = AudioServer.get_bus_index(voice_bus_name)
		if bus_idx >= 0:
			var peak_l = AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
			var peak_r = AudioServer.get_bus_peak_volume_right_db(bus_idx, 0)
			_audio_peak_db = max(peak_l, peak_r)
			if _audio_peak_db >= speech_db_threshold:
				has_sound = true
		else:
			has_sound = true
			_audio_peak_db = -10.0

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
		var flap = (sin(_talk_time * talk_speed) + 1.0) * 0.5
		if flap > 0.35:
			if _audio_peak_db > -20.0 or manual_eye_state in [NPCEyeState.ANGRY, NPCEyeState.SURPRISE]:
				current_mouth_state = NPCMouthState.OPEN_WIDE
			else:
				current_mouth_state = NPCMouthState.OPEN_SMALL
		else:
			current_mouth_state = manual_mouth_state
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

func _apply_uv_offsets() -> void:
	# Eye UV
	var active_eye: NPCEyeState = NPCEyeState.CLOSED if (_is_blinking and current_eye_state != NPCEyeState.CLOSED) else current_eye_state
	var eye_uv_y: float = DEFAULT_EYE_OFFSETS.get(active_eye, 0.0)

	if _eye_mat:
		_eye_mat.uv1_offset.y = eye_uv_y

	# Mouth UV
	var mouth_uv: Vector2 = DEFAULT_MOUTH_OFFSETS.get(current_mouth_state, Vector2.ZERO)
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
