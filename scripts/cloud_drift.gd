extends Sprite2D
class_name CloudDrift

## Slow horizontal drift for a decorative cloud sprite - wraps back around
## once it's drifted far enough from its starting point instead of just
## floating off into the distance forever, so the sky reads as alive
## without needing to manage cloud spawning/despawning.

@export var drift_speed: float = 6.0
@export var wrap_distance: float = 500.0

var _start_x: float


func _ready() -> void:
	_start_x = position.x


func _process(delta: float) -> void:
	position.x += drift_speed * delta
	if drift_speed >= 0.0 and position.x > _start_x + wrap_distance:
		position.x = _start_x - wrap_distance
	elif drift_speed < 0.0 and position.x < _start_x - wrap_distance:
		position.x = _start_x + wrap_distance
