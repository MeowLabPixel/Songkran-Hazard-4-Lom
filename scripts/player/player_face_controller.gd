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
	DEFAULT,     # 0.0
	OPEN_SMALL,  # 0.147
	OPEN_WIDE,   # 0.284
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
	MouthState.DEFAULT: 0.0,
	MouthState.OPEN_SMALL: 0.147,
	MouthState.OPEN_WIDE: 0.284,
}

@export var head_mesh: MeshInstance3D
@export var player: CharacterBody3D

@export_group("Surface Indices")
@export var eye_surface_index: int = 2
@export var mouth_surface_index: int = 3

@export_group("Blinking Settings")
@export var enable_blinking: bool = true
@export var min_blink_interval: float = 2.5
@export var max_blink_interval: float = 5.5
@export var blink_duration: float = 0.15

# Overrides & Event Flags
var is_hit_reaction: bool = false
var hit_reaction_timer: float = 0.0

var is_grabbed: bool = false
var is_grab_win: bool = false
var is_grab_fail: bool = false
var grab_win_timer: float = 0.0
var grab_fail_timer: float = 0.0
var cry_linger_timer: float = 0.0
var _was_hit_or_fail: bool = false

var is_takedown: bool = false
var is_die: bool = false

var is_aiming: bool = false

var is_voiceline_playing: bool = false
var is_combat: bool = false
var _voiceline_timer: float = 0.0

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

func _ready() -> void:
	if not player:
		player = get_parent() as CharacterBody3D
	_ensure_head_mesh()
	_ensure_unique_materials()
	_reset_blink_timer()

func _ensure_head_mesh() -> void:
	if not head_mesh and player:
		head_mesh = player.get_node_or_null("Re4Lom Base Rig/rig/Skeleton3D/Head") as MeshInstance3D

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
		m_mat = m_mat.duplicate() as StandardMaterial3D
		head_mesh.set_surface_override_material(mouth_surface_index, m_mat)
	_mouth_mat = m_mat

func _process(delta: float) -> void:
	if not head_mesh or not _eye_mat or not _mouth_mat:
		_ensure_head_mesh()
		_ensure_unique_materials()
		if not head_mesh:
			return

	_auto_detect_player_state()
	_update_timers(delta)
	_evaluate_eye_state()
	_evaluate_mouth_state()
	_process_blinking(delta)
	_apply_uv_offsets()

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

	# Detect transition out of hit or grab_fail to start 2.0s cry linger
	var is_currently_hit_or_fail = is_hit_reaction or is_grab_fail
	if is_currently_hit_or_fail:
		_was_hit_or_fail = true
	elif _was_hit_or_fail:
		_was_hit_or_fail = false
		cry_linger_timer = 1.0

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

	if _voiceline_timer > 0.0:
		_voiceline_timer -= delta
		if _voiceline_timer <= 0.0:
			is_voiceline_playing = false

func _evaluate_eye_state() -> void:
	var current_hp: float = 100.0
	var max_hp: float = 100.0
	if player:
		if "HP" in player:
			current_hp = float(player.HP)
		if "MaxHP" in player:
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
	if not is_voiceline_playing:
		current_mouth_state = MouthState.DEFAULT
	elif current_eye_state in [EyeState.FOCUS, EyeState.ANGRY, EyeState.SURPRISE]:
		current_mouth_state = MouthState.OPEN_WIDE
	else:
		current_mouth_state = MouthState.OPEN_SMALL

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
	var mouth_uv_y: float = MOUTH_OFFSETS.get(current_mouth_state, 0.0)
	if _mouth_mat:
		_mouth_mat.uv1_offset.y = mouth_uv_y

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

func trigger_voiceline(duration: float = 1.0, is_combat_speech: bool = false) -> void:
	is_voiceline_playing = true
	is_combat = is_combat_speech
	_voiceline_timer = duration

func set_voiceline_playing(playing: bool, combat: bool = false) -> void:
	is_voiceline_playing = playing
	is_combat = combat
	if playing and _voiceline_timer <= 0.0:
		_voiceline_timer = 1.0
