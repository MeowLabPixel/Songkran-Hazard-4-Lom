extends Label

var velocity: Vector2 = Vector2.ZERO
var gravity: float = 500.0
var life_time: float = 1.2
var elapsed_time: float = 0.0

func _ready() -> void:
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

func _process(delta: float) -> void:
	elapsed_time += delta
	velocity.y += gravity * delta
	position += velocity * delta
	
	modulate.a = clamp(1.0 - (elapsed_time / life_time), 0.0, 1.0)
	
	if elapsed_time >= life_time:
		queue_free()
