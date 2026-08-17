extends Node3D

@export var cheer_speed: float = 8.0
@export var cheer_height: float = 0.8
@export var wave_speed: float = 2.0
@export var wave_frequency: float = 0.4
@export var idle_bob_speed: float = 2.0
@export var idle_bob_height: float = 0.05
@export var spin_chance: float = 0.05

@export_group("Spawning Effects")
@export var balloon_scene: PackedScene = preload("res://scenes/items/water_balloon.tscn")
@export var water_line_scene: PackedScene = preload("res://GunSystem/Scene/WaterLineVFX/WaterLine.tscn")

@export var balloon_throw_interval_min: float = 1.0
@export var balloon_throw_interval_max: float = 4.0
@export var shot_interval_min: float = 0.2
@export var shot_interval_max: float = 1.0

var members: Array[Node3D] = []
var original_positions: Array[Vector3] = []
var original_rotations: Array[Vector3] = []
var member_offsets: Array[float] = []
var member_spin_multipliers: Array[float] = []

var elapsed_time: float = 0.0
var balloon_timer: float = 0.0
var shot_timer: float = 0.0
var next_balloon_time: float = 1.0
var next_shot_time: float = 0.5

var is_visible: bool = true

func _ready() -> void:
	# Recursively collect all Node3D children that are meshes (the crowd members)
	_collect_members(self)
	
	# Reparent nested meshes to flatten the hierarchy.
	# This ensures parent movements don't double-animate the children.
	var flattened_members: Array[Node3D] = []
	for member in members:
		var global_pos = member.global_position
		if member.get_parent() != self:
			member.get_parent().remove_child(member)
			add_child(member)
			member.global_position = global_pos
		flattened_members.append(member)
	
	members = flattened_members
	
	# Store original positions, rotations and calculate individual offsets
	for i in range(members.size()):
		var member = members[i]
		member.rotation.y = randf_range(0.0, TAU)
		original_positions.append(member.position)
		original_rotations.append(member.rotation)
		
		# Decide if this member will do a 180 spin-jump during cheers
		if randf() < spin_chance:
			member_spin_multipliers.append(1.0 if randf() > 0.5 else -1.0)
		else:
			member_spin_multipliers.append(0.0)
			
		# Unique offset based on spatial position (for wave effect) and a bit of pseudo-randomness
		var spatial_offset = member.position.x * wave_frequency + member.position.z * (wave_frequency * 0.5)
		var rand_offset = randf_range(0.0, TAU)
		member_offsets.append(spatial_offset + rand_offset * 0.1)

	next_balloon_time = randf_range(balloon_throw_interval_min, balloon_throw_interval_max)
	next_shot_time = randf_range(shot_interval_min, shot_interval_max)

	# Performance optimization: Only process when visible on screen
	var notifier = VisibleOnScreenNotifier3D.new()
	add_child(notifier)
	if members.size() > 0:
		var aabb = AABB(members[0].position, Vector3.ZERO)
		for member in members:
			aabb = aabb.merge(AABB(member.position - Vector3(1, 1, 1), Vector3(2, 2, 2)))
		notifier.aabb = aabb
	
	notifier.screen_entered.connect(func(): is_visible = true)
	notifier.screen_exited.connect(func(): is_visible = false)

func _collect_members(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			members.append(child as Node3D)
		_collect_members(child)

func _process(delta: float) -> void:
	elapsed_time += delta

	# Update throwing/shooting timers
	balloon_timer += delta
	if balloon_timer >= next_balloon_time:
		balloon_timer = 0.0
		next_balloon_time = randf_range(balloon_throw_interval_min, balloon_throw_interval_max)
		if is_visible:
			_throw_random_balloon()

	shot_timer += delta
	if shot_timer >= next_shot_time:
		shot_timer = 0.0
		next_shot_time = randf_range(shot_interval_min, shot_interval_max)
		if is_visible:
			_shoot_random_water_line()

	if not is_visible:
		return

	var time = elapsed_time
	var members_count = members.size()
	
	for i in range(members_count):
		var member = members[i]
		var orig_pos = original_positions[i]
		var orig_rot = original_rotations[i]
		var offset = member_offsets[i]
		
		# Combine a stadium wave/cheer bouncing motion
		# We share the sine calculations between the bounce, the tilt, and the spin logic where possible to save CPU
		var wave_time = time * wave_speed + offset
		var wave_envelope = (sin(wave_time) + 1.0) * 0.5
		
		# Idle small bobbing
		var idle_y = sin(time * idle_bob_speed + offset * 5.0) * idle_bob_height
		
		# High cheer jump and tilt (sharing sine phase)
		var cheer_phase = time * cheer_speed + offset
		var sin_cheer = sin(cheer_phase)
		var bounce = abs(sin_cheer)
		var cheer_y = bounce * cheer_height
		
		# Blend between idle and cheering based on the wave envelope
		var displacement = lerp(idle_y, cheer_y, wave_envelope)
		
		# Prevent going below original position during large jumps
		if displacement < 0.0:
			displacement = lerp(displacement, 0.0, wave_envelope)
			
		member.position.y = orig_pos.y + displacement
		
		# Tilt slightly during jump for extra flavor
		var tilt_angle = (sin_cheer * 0.08) * wave_envelope
		member.rotation.z = tilt_angle
		
		# Spin logic: dynamically rotate 180 degrees (PI) during cheer jumps
		var spin_angle = 0.0
		if member_spin_multipliers[i] != 0.0:
			spin_angle = bounce * PI * member_spin_multipliers[i] * wave_envelope
			
		member.rotation.y = orig_rot.y + spin_angle

func _throw_random_balloon() -> void:
	if members.size() < 2 or not balloon_scene:
		return
		
	var source_idx = randi() % members.size()
	var target_idx = randi() % members.size()
	while target_idx == source_idx:
		target_idx = randi() % members.size()
		
	var source = members[source_idx]
	var target = members[target_idx]
	
	var balloon = balloon_scene.instantiate() as WaterBalloon
	if balloon:
		var parent_node = get_parent() if get_parent() else self
		parent_node.add_child(balloon)
		balloon.global_position = source.global_position + Vector3(0, 1.2, 0)
		balloon.launch(target.global_position + Vector3(0, 1.0, 0), 0.0, 1.5, 2.5, 1.2)

func _shoot_random_water_line() -> void:
	if members.size() < 2 or not water_line_scene:
		return
		
	var source_idx = randi() % members.size()
	var target_idx = randi() % members.size()
	while target_idx == source_idx:
		target_idx = randi() % members.size()
		
	var source = members[source_idx]
	var target = members[target_idx]
	
	var water_line = water_line_scene.instantiate()
	if water_line:
		var parent_node = get_parent() if get_parent() else self
		parent_node.add_child(water_line)
		
		# Shoot from source to target
		var start_pos = source.global_position + Vector3(0, 1.0, 0)
		var end_pos = target.global_position + Vector3(0, 1.0, 0)
		water_line.set_line(start_pos, end_pos)
