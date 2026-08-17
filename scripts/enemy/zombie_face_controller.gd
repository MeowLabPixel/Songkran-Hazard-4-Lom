class_name ZombieFaceController
extends Node3D

enum ZombieEyeState {
	DEFAULT, # 0.0
	HURT,    # 0.139
	ANGRY,   # Male: 0.285, Female: 0.280
}

@export var head_mesh: MeshInstance3D
@export var enemy: EnemyBase
@export var is_female: bool = false

@export_group("Surface Indices")
@export var eye_surface_index: int = 0
@export var mouth_surface_index: int = 1

@export_group("Eye Shake Settings")
@export var enable_eye_shake: bool = true
@export var eye_shake_amplitude: float = 0.001
@export var eye_shake_speed: float = 15.0

@export_group("Mouth Breathing Settings")
@export var enable_mouth_breathing: bool = true
@export var breath_speed: float = 4.0

@export_subgroup("Male Mouth Settings")
@export var male_mouth_rest_offset: float = -0.006
@export var male_mouth_rest_scale: float = 1.18
@export var male_mouth_breath_offset: float = 0.006
@export var male_mouth_breath_scale: float = 0.93

@export_subgroup("Female Mouth Settings")
@export var female_mouth_rest_offset: float = -0.006
@export var female_mouth_rest_scale: float = 1.10
@export var female_mouth_breath_offset: float = 0.000
@export var female_mouth_breath_scale: float = 0.88

@export_group("Cutscene / Manual Animation")
@export var manual_mode: bool = false ## When true, AnimationPlayer keyframes or manual properties control facial expressions
@export var manual_eye_state: ZombieEyeState = ZombieEyeState.DEFAULT ## Eye expression keyframable in AnimationPlayer

@export_group("Real-Time Audio Metering")
@export var voice_player: Node = null ## Optional AudioStreamPlayer or AudioStreamPlayer3D
@export var voice_bus_name: String = "Voiceline"
@export var speech_db_threshold: float = -55.0 ## Silence threshold in dB (accounts for 3D camera distance attenuation)
@export var speech_hold_time: float = 0.22 ## Smoothing buffer in seconds to bridge audio syllables smoothly
@export var vocal_boost_on_speech: float = 4.0 ## Multiplier for mouth stretch speed when vocalizing

# State Flags
var is_hit_reaction: bool = false
var hurt_linger_timer: float = 0.0

# Current Active Eye State
var current_eye_state: ZombieEyeState = ZombieEyeState.DEFAULT

# Internal Procedural Timers & Audio Metering
var _breath_time: float = 0.0
var _vocal_boost_timer: float = 0.0
var _vocal_boost_multiplier: float = 1.0
var _speech_hold_timer: float = 0.0
var _audio_peak_db: float = -80.0

# Material References
var _eye_mat: StandardMaterial3D = null
var _mouth_mat: StandardMaterial3D = null

func _ready() -> void:
	if not enemy:
		var parent = get_parent()
		if parent is EnemyBase:
			enemy = parent
	_ensure_gender()
	_ensure_head_mesh()
	_ensure_unique_materials()

func _ensure_gender() -> void:
	if enemy:
		if "voice_character" in enemy and String(enemy.voice_character) == "Zombie Female":
			is_female = true
		elif "FMelee" in enemy.name or "Female" in enemy.name or "female" in String(enemy.name).to_lower():
			is_female = true

func _ensure_head_mesh() -> void:
	if not head_mesh and enemy:
		head_mesh = enemy.get_node_or_null("ZombieModel/rig/GeneralSkeleton/Head") as MeshInstance3D
		if not head_mesh:
			head_mesh = enemy.get_node_or_null("rig/GeneralSkeleton/Head") as MeshInstance3D
		if not head_mesh:
			head_mesh = enemy.find_child("Head", true, false) as MeshInstance3D

func _ensure_unique_materials() -> void:
	if not head_mesh:
		return

	# Surface 0 - Eyes
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

	# Surface 1 - Mouth
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

	_breath_time += delta

	if not manual_mode:
		_auto_detect_enemy_state()
	_update_audio_metering(delta)
	_update_timers(delta)
	_evaluate_eye_state()
	_apply_uv_offsets()

func _update_audio_metering(delta: float) -> void:
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

	if has_sound:
		_speech_hold_timer = speech_hold_time
		_vocal_boost_multiplier = vocal_boost_on_speech
	else:
		if _speech_hold_timer > 0.0:
			_speech_hold_timer -= delta
			_vocal_boost_multiplier = vocal_boost_on_speech
		elif _vocal_boost_timer <= 0.0:
			_vocal_boost_multiplier = 1.0

func _auto_detect_enemy_state() -> void:
	if not enemy:
		return

	_ensure_gender()

	var sm = enemy.get_node_or_null("StateMachine")
	if not sm:
		sm = enemy.get_node_or_null("Statemachine")
	if not sm:
		sm = enemy.get_node_or_null("state_machine")

	var is_in_hit_state: bool = false
	if sm and "current_state" in sm and sm.current_state:
		var cstate = sm.current_state
		var sname = String(cstate.name)

		# Detect active hit / stun / knockdown / takedown / die state
		if sname in ["StateHit", "Hit", "HitPush", "Knockdown", "StateKnockdown", "Takedownable", "StateTakedownable", "Die", "StateDie"]:
			is_in_hit_state = true

	is_hit_reaction = is_in_hit_state

func _is_angry_animation_active() -> bool:
	if not enemy:
		return false

	var detected_anims: Array[String] = []

	# 1. Check AnimationPlayer current_animation
	if enemy.anim_player and enemy.anim_player.is_playing():
		detected_anims.append(String(enemy.anim_player.current_animation))

	# 2. Check AnimationTree active state machine node playbacks
	if enemy.anim_tree and enemy.anim_tree.active:
		var root_pb = enemy.anim_tree.get("parameters/playback")
		if root_pb:
			var r_node = String(root_pb.get_current_node())
			if r_node != "":
				detected_anims.append(r_node)
				var sub_pb = enemy.anim_tree.get("parameters/" + r_node + "/playback")
				if sub_pb:
					var sub_node = String(sub_pb.get_current_node())
					if sub_node != "":
						detected_anims.append(sub_node)

	# 3. Check StateMachine current_state variables
	var sm = enemy.get_node_or_null("StateMachine")
	if not sm:
		sm = enemy.get_node_or_null("Statemachine")
	if not sm:
		sm = enemy.get_node_or_null("state_machine")

	if sm and "current_state" in sm and sm.current_state:
		var cstate = sm.current_state
		if "_current_target_anim" in cstate:
			detected_anims.append(String(cstate._current_target_anim))
		if "last_anim" in cstate:
			detected_anims.append(String(cstate.last_anim))

	# Target Angry Animations
	var angry_targets = [
		"Zombie Attack 1",
		"Zombie Attack 2",
		"Zombie Attempt Grab",
		"Zombie Grab success"
	]

	# Target Angry Fallback Identifiers
	for a in detected_anims:
		if a == "":
			continue
		for target in angry_targets:
			if a == target:
				return true
		var a_lower = a.to_lower()
		if "attack 1" in a_lower or "attack 2" in a_lower or "attempt grab" in a_lower or "grab success" in a_lower:
			return true
		if "attack_1" in a_lower or "attack_2" in a_lower or "grab_reach" in a_lower or "grab/win" in a_lower or "grab_success" in a_lower:
			return true

	return false

func _update_timers(delta: float) -> void:
	if hurt_linger_timer > 0.0:
		hurt_linger_timer -= delta

	if _vocal_boost_timer > 0.0:
		_vocal_boost_timer -= delta
		if _vocal_boost_timer <= 0.0:
			_vocal_boost_multiplier = 1.0

func _evaluate_eye_state() -> void:
	if manual_mode:
		current_eye_state = manual_eye_state
		return

	# Priority 1: Active Hit / Stun / Takedown / Die State (0.139)
	if is_hit_reaction:
		current_eye_state = ZombieEyeState.HURT
		return

	# Priority 2: ANGRY Eyes (0.285 Male / 0.280 Female) - Detected via direct AnimationTree / AnimationPlayer names
	if _is_angry_animation_active():
		current_eye_state = ZombieEyeState.ANGRY
		return

	# Priority 3: HURT Linger Timer (0.139) - Lingering hit reaction when not playing an angry animation
	if hurt_linger_timer > 0.0:
		current_eye_state = ZombieEyeState.HURT
		return

	# Priority 4: DEFAULT Eyes (0.000) - Idle, wandering, grab loop, etc.
	current_eye_state = ZombieEyeState.DEFAULT

func _apply_uv_offsets() -> void:
	# Eye UV & Smooth Wave Shake
	var base_eye_uv_y: float = 0.0
	var current_shake_speed: float = eye_shake_speed
	var current_shake_amp: float = eye_shake_amplitude

	match current_eye_state:
		ZombieEyeState.HURT:
			base_eye_uv_y = 0.139
			current_shake_speed = eye_shake_speed * 2.0
			current_shake_amp = eye_shake_amplitude + 0.002
		ZombieEyeState.ANGRY:
			base_eye_uv_y = 0.280 if is_female else 0.285
			current_shake_speed = eye_shake_speed * 1.5
		ZombieEyeState.DEFAULT:
			base_eye_uv_y = 0.000

	if _eye_mat:
		var eye_offset_y = base_eye_uv_y
		if enable_eye_shake:
			eye_offset_y += sin(_breath_time * current_shake_speed) * current_shake_amp
		_eye_mat.uv1_offset.y = eye_offset_y

	# Mouth UV Breathing Offset & Y Scale Stretch Simulation
	if _mouth_mat:
		if enable_mouth_breathing:
			var current_speed = breath_speed * _vocal_boost_multiplier
			var t = (sin(_breath_time * current_speed) + 1.0) * 0.5
			var rest_offset = female_mouth_rest_offset if is_female else male_mouth_rest_offset
			var rest_scale = female_mouth_rest_scale if is_female else male_mouth_rest_scale
			var breath_offset = female_mouth_breath_offset if is_female else male_mouth_breath_offset
			var breath_scale = female_mouth_breath_scale if is_female else male_mouth_breath_scale

			_mouth_mat.uv1_offset.y = lerp(rest_offset, breath_offset, t)
			_mouth_mat.uv1_scale.y = lerp(rest_scale, breath_scale, t)
		else:
			_mouth_mat.uv1_offset.y = 0.0
			_mouth_mat.uv1_scale.y = 1.0

# --- Public API Functions ---

func notify_hit(duration: float = 1.0) -> void:
	hurt_linger_timer = max(hurt_linger_timer, duration)

func trigger_vocal_boost(duration: float = 1.5, multiplier: float = 5.0) -> void:
	_vocal_boost_timer = duration
	_vocal_boost_multiplier = multiplier
