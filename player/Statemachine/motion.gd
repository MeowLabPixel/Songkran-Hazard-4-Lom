extends State
class_name Motion
signal velocity_updated(vel:Vector3)
const SPEED: float = 5.0
const SPEED_sprint: float = 8.0
const acceleration:float = 1000
const Gravity: float = 9.8

static var input_dir: Vector2 = Vector2.ZERO
static var direction: Vector3 = Vector3.ZERO
static var velocity: Vector3 = Vector3.ZERO
static var _active_direction: Vector2 = Vector2.ZERO
var is_moving =true

func _ready() -> void:
	velocity_updated.connect(owner.set_velocity_from_motion)

func set_direction() -> void:
	if GameManager.movement_type == GameManager.MovementType.TANK:
		var up = Input.is_action_pressed("ui_up")
		var down = Input.is_action_pressed("ui_down")
		
		input_dir = Vector2.ZERO
		if up:
			input_dir.y = -1.0
		elif down:
			input_dir.y = 1.0
			
		direction = owner.global_transform.basis * Vector3(0.0, 0.0, input_dir.y)
	elif GameManager.movement_type == GameManager.MovementType.MODERN:
		var up = Input.is_action_pressed("ui_up")
		var down = Input.is_action_pressed("ui_down")
		var left = Input.is_action_pressed("ui_left")
		var right = Input.is_action_pressed("ui_right")
		
		var horizontal = 0.0
		if right: horizontal += 1.0
		if left: horizontal -= 1.0
		var vertical = 0.0
		if down: vertical += 1.0
		if up: vertical -= 1.0
		
		input_dir = Vector2(horizontal, vertical)
		if input_dir.length_squared() > 0.0:
			input_dir = input_dir.normalized()
			
		direction = owner.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	else:
		var up = Input.is_action_pressed("ui_up")
		var down = Input.is_action_pressed("ui_down")
		var left = Input.is_action_pressed("ui_left")
		var right = Input.is_action_pressed("ui_right")
		
		# New input takes over
		if Input.is_action_just_pressed("ui_up"): _active_direction = Vector2(0, -1)
		elif Input.is_action_just_pressed("ui_down"): _active_direction = Vector2(0, 1)
		elif Input.is_action_just_pressed("ui_left"): _active_direction = Vector2(-1, 0)
		elif Input.is_action_just_pressed("ui_right"): _active_direction = Vector2(1, 0)
		
		# If the key for the active direction is released, clear it
		if _active_direction == Vector2(0, -1) and not up: _active_direction = Vector2.ZERO
		if _active_direction == Vector2(0, 1) and not down: _active_direction = Vector2.ZERO
		if _active_direction == Vector2(-1, 0) and not left: _active_direction = Vector2.ZERO
		if _active_direction == Vector2(1, 0) and not right: _active_direction = Vector2.ZERO
		
		# Fallback to any other currently held key if active direction was cleared
		if _active_direction == Vector2.ZERO:
			if up: _active_direction = Vector2(0, -1)
			elif down: _active_direction = Vector2(0, 1)
			elif left: _active_direction = Vector2(-1, 0)
			elif right: _active_direction = Vector2(1, 0)
			
		input_dir = _active_direction
		direction = owner.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)

func calculate_velocity(_speed:float,_direction: Vector3,delta:float)->void:
	velocity.x = move_toward(velocity.x,_direction.x*_speed,acceleration*delta)
	velocity.z = move_toward(velocity.z,_direction.z*_speed,acceleration*delta)
	velocity_updated.emit(velocity)
	
func calculate_gravity(delta:float) -> void:
		if not owner.is_on_floor():
			velocity.y += Gravity * delta
			
func update_moving(value):
	is_moving = value
