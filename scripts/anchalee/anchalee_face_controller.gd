class_name AnchaleeFaceController
extends Node3D

enum EyeState {
	DEFAULT,   # 0.000
	CRY,       # 0.140 - 0.145 (Dynamic shake)
	CLOSED,    # 0.270 - 0.275 (Dynamic shake for ducking/jinking / blink)
	SURPRISE,  # 0.420 (When zombie targets Anchalee)
}

enum MouthState {
	NORMAL,      # 0.277
	SCARE,       # 0.000 - -0.002 (Dynamic shake)
	OPEN_WIDE,   # 0.137 (Voiceline during combat/scare/ducking/surprise)
	OPEN_SMALL,  # 0.423 (Voiceline during normal/calm state)
}

@export var head_mesh: MeshInstance3D
@export var anchalee: CharacterBody3D

@export_group("Surface Indices")
@export var eye_surface_index: int = 0
@export var mouth_surface_index: int = 1

@export_group("Blinking Settings")
@export var enable_blinking: bool = true
@export var min_blink_interval: float = 2.5
@export var max_blink_interval: float = 5.5
@export var blink_duration: float = 0.15

@export_group("Dynamic Shake Settings")
@export var enable_eye_shake: bool = true
@export var enable_mouth_shake: bool = true

@export_subgroup("Cry Eye Shake")
@export var cry_eye_min_y: float = 0.140
@export var cry_eye_max_y: float = 0.145
@export var cry_eye_shake_speed: float = 35.0

@export_subgroup("Closed & Duck Eye Shake")
@export var closed_eye_min_y: float = 0.270
@export var closed_eye_max_y: float = 0.275
@export var closed_eye_shake_speed: float = 30.0

@export_subgroup("Scare Mouth Shake")
@export var scare_mouth_min_y: float = -0.002
@export var scare_mouth_max_y: float = 0.000
@export var scare_mouth_shake_speed: float = 25.0

@export_group("Ducking Anim Eye Window")
@export var duck_eyes_open_start: float = 1.85
@export var duck_eyes_open_end: float = 5.70
@export var duck_loop_length: float = 6.0

# State Flags
var is_hit_reaction: bool = false
var hit_linger_timer: float = 0.0
var is_die: bool = false

var is_ducking: bool = false
var duck_anim_time: float = 0.0
var _was_duck_open_window: bool = false

var is_combat: bool = false
var is_targeted_by_zombie: bool = false
var is_low_hp: bool = false

var is_voiceline_playing: bool = false
var _voiceline_timer: float = 0.0

# Internal Blinking State
var _blink_timer: float = 0.0
var _next_blink_time: float = 3.0
var _is_blinking: bool = false
var _blink_elapsed: float = 0.0

# Internal Animation Time for Shaking
var _shake_time: float = 0.0

# Current Active States
var current_eye_state: EyeState = EyeState.DEFAULT
var current_mouth_state: MouthState = MouthState.NORMAL

# Material References
var _eye_mat: StandardMaterial3D = null
var _mouth_mat: StandardMaterial3D = null

func _ready() -> void:
	if not anchalee:
		var parent = get_parent()
		if parent is CharacterBody3D:
			anchalee = parent
	_ensure_head_mesh()
	_ensure_unique_materials()
	_reset_blink_timer()

func _ensure_head_mesh() -> void:
	if not head_mesh and anchalee:
		head_mesh = anchalee.get_node_or_null("AnchaleeModel/rig_002/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/Head_001") as MeshInstance3D
		if not head_mesh:
			head_mesh = anchalee.find_child("Head_001", true, false) as MeshInstance3D
		if not head_mesh:
			head_mesh = anchalee.find_child("Head", true, false) as MeshInstance3D

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

	_shake_time += delta
	_auto_detect_anchalee_state(delta)
	_update_timers(delta)
	_evaluate_eye_state()
	_evaluate_mouth_state()
	_process_blinking(delta)
	_apply_uv_offsets()

func _auto_detect_anchalee_state(delta: float) -> void:
	if not anchalee:
		return

	# Detect Low HP (< 50% Max HP)
	var hp: float = 100.0
	var max_hp: float = 100.0
	if "health" in anchalee:
		hp = float(anchalee.health)
	if "max_health" in anchalee:
		max_hp = float(anchalee.max_health)
	is_low_hp = (max_hp > 0.0) and ((hp / max_hp) < 0.50)

	# Detect state machine states
	var sm = anchalee.get_node_or_null("AnchaleeStateMachine")
	if not sm:
		sm = anchalee.get_node_or_null("StateMachine")
	if not sm:
		sm = anchalee.get_node_or_null("Statemachine")

	var is_in_hit: bool = false
	var was_ducking = is_ducking
	if sm and "current_state" in sm and sm.current_state:
		var sname = String(sm.current_state.name)
		is_die = (sname == "AnchaleeStateDie" or sname == "Die")
		is_ducking = (sname in ["AnchaleeStateDuck", "AnchaleeStateJink", "Duck", "Jink"])
		if sname in ["AnchaleeStateHit", "Hit", "StateHit"]:
			is_in_hit = true

	if is_ducking:
		if not was_ducking:
			duck_anim_time = 0.0
		else:
			duck_anim_time += delta
	else:
		duck_anim_time = 0.0

	is_hit_reaction = is_in_hit
	is_targeted_by_zombie = _check_is_targeted_by_zombie()
	is_combat = _check_is_in_combat()

func _check_is_targeted_by_zombie() -> bool:
	if not anchalee or not anchalee.is_inside_tree():
		return false
	var tree = anchalee.get_tree()
	if not tree:
		return false
	var enemies = tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Node3D:
			if "current_target" in enemy and enemy.current_target == anchalee:
				return true
			if "target" in enemy and enemy.target == anchalee:
				return true
	return false

func _check_is_in_combat() -> bool:
	if is_hit_reaction or is_ducking or is_targeted_by_zombie:
		return true

	if anchalee and anchalee.is_inside_tree():
		var tree = anchalee.get_tree()
		if tree:
			var enemies = tree.get_nodes_in_group("enemies")
			for enemy in enemies:
				if is_instance_valid(enemy) and enemy is Node3D:
					if anchalee.global_position.distance_to(enemy.global_position) <= 12.0:
						return true

	var sound_mgr = get_node_or_null("/root/SoundManager")
	if sound_mgr and "_current_music_state" in sound_mgr:
		if sound_mgr._current_music_state in ["CombatStart", "CombatLoop"]:
			return true

	return false

func _update_timers(delta: float) -> void:
	if hit_linger_timer > 0.0:
		hit_linger_timer -= delta

	if _voiceline_timer > 0.0:
		_voiceline_timer -= delta
		if _voiceline_timer <= 0.0:
			is_voiceline_playing = false

func _evaluate_eye_state() -> void:
	# Priority 1: CRY Eyes (0.140 - 0.145) - Active hit reaction, death, or 1.0s hit linger
	if is_hit_reaction or is_die or hit_linger_timer > 0.0:
		current_eye_state = EyeState.CRY
		return

	# Priority 2: SURPRISE Eyes (0.420) - Zombie enemy is targeting Anchalee
	if is_targeted_by_zombie:
		current_eye_state = EyeState.SURPRISE
		return

	# Priority 3: Ducking / Jinking State
	if is_ducking:
		var current_duck_time = duck_anim_time
		if duck_loop_length > 0.0:
			current_duck_time = fmod(duck_anim_time, duck_loop_length)

		var is_eyes_open_window = (current_duck_time >= duck_eyes_open_start) and (current_duck_time <= duck_eyes_open_end)

		# Reset blinking timer whenever entering the open-eyes window so blinking starts fresh
		if is_eyes_open_window and not _was_duck_open_window:
			_reset_blink_timer()
			_is_blinking = false

		_was_duck_open_window = is_eyes_open_window

		if is_eyes_open_window:
			# Resume default eyes and dynamic blinking during 1.85s to 5.7s
			if _is_blinking:
				if is_low_hp:
					current_eye_state = EyeState.CRY
				else:
					current_eye_state = EyeState.CLOSED
			else:
				current_eye_state = EyeState.DEFAULT
		else:
			# Closed/Cry eyes before 1.85s and after 5.7s
			if is_low_hp:
				current_eye_state = EyeState.CRY
			else:
				current_eye_state = EyeState.CLOSED
		return
	else:
		if _was_duck_open_window:
			_was_duck_open_window = false
			_reset_blink_timer()
			_is_blinking = false

	# Priority 4: Dynamic Auto-Blinking
	if _is_blinking:
		if is_low_hp:
			current_eye_state = EyeState.CRY
		else:
			current_eye_state = EyeState.CLOSED
		return

	# Priority 5: DEFAULT Eyes (0.000)
	current_eye_state = EyeState.DEFAULT

func _evaluate_mouth_state() -> void:
	# Priority 1: Voiceline Playing
	if is_voiceline_playing:
		if is_combat or is_ducking or current_eye_state == EyeState.SURPRISE:
			current_mouth_state = MouthState.OPEN_WIDE
		else:
			current_mouth_state = MouthState.OPEN_SMALL
		return

	# Priority 2: Scare / Combat / Ducking
	if is_combat or is_ducking:
		current_mouth_state = MouthState.SCARE
		return

	# Priority 3: NORMAL Mouth (0.277)
	current_mouth_state = MouthState.NORMAL

func _reset_blink_timer() -> void:
	_blink_timer = 0.0
	_next_blink_time = randf_range(min_blink_interval, max_blink_interval)

func _process_blinking(delta: float) -> void:
	if not enable_blinking:
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

func _get_shaken_offset(min_val: float, max_val: float, speed: float = 30.0, enabled: bool = true) -> float:
	var mid = (min_val + max_val) * 0.5
	if not enabled:
		return mid
	var half_range = (max_val - min_val) * 0.5
	return mid + sin(_shake_time * speed) * half_range

func _apply_uv_offsets() -> void:
	# Eye UV
	var eye_uv_y: float = 0.0
	match current_eye_state:
		EyeState.CRY:
			eye_uv_y = _get_shaken_offset(cry_eye_min_y, cry_eye_max_y, cry_eye_shake_speed, enable_eye_shake)
		EyeState.CLOSED:
			if is_ducking:
				eye_uv_y = _get_shaken_offset(closed_eye_min_y, closed_eye_max_y, closed_eye_shake_speed, enable_eye_shake)
			else:
				# Normal blinking
				eye_uv_y = (closed_eye_min_y + closed_eye_max_y) * 0.5
		EyeState.SURPRISE:
			eye_uv_y = 0.420
		EyeState.DEFAULT:
			eye_uv_y = 0.000

	if _eye_mat:
		_eye_mat.uv1_offset.y = eye_uv_y

	# Mouth UV
	var mouth_uv_y: float = 0.277
	match current_mouth_state:
		MouthState.SCARE:
			mouth_uv_y = _get_shaken_offset(scare_mouth_min_y, scare_mouth_max_y, scare_mouth_shake_speed, enable_mouth_shake)
		MouthState.OPEN_WIDE:
			mouth_uv_y = 0.137
		MouthState.OPEN_SMALL:
			mouth_uv_y = 0.423
		MouthState.NORMAL:
			mouth_uv_y = 0.277

	if _mouth_mat:
		_mouth_mat.uv1_offset.y = mouth_uv_y

# --- Public API Functions ---

func notify_hit(duration: float = 1.0) -> void:
	is_hit_reaction = true
	hit_linger_timer = duration

func trigger_voiceline(duration: float = 1.2, is_combat_speech: bool = false) -> void:
	is_voiceline_playing = true
	if is_combat_speech:
		is_combat = true
	_voiceline_timer = duration

func set_ducking(ducking: bool) -> void:
	is_ducking = ducking
