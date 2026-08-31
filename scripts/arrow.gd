extends Area2D
class_name Arrow

@export var damage: int = 10
@export var flight_time: float = 0.6  # overwritten per-shot by Tower.gd
@export var arc_height: float = 80.0  # how high the arc peaks, in pixels

@export var amount: int = 5

var start_pos: Vector2
var end_pos: Vector2
var _elapsed := 0.0
var _resolved := false  # hit something or landed - stops further movement


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func launch(from_position: Vector2, to_position: Vector2) -> void:
	start_pos = from_position
	end_pos = to_position
	global_position = start_pos


func _physics_process(delta: float) -> void:
	if _resolved:
		return
	_elapsed += delta
	var t := clampf(_elapsed / flight_time, 0.0, 1.0)

	var flat_pos := start_pos.lerp(end_pos, t)
	var arc_offset := arc_height * 4.0 * t * (1.0 - t)  # parabola, peaks at t=0.5
	var new_pos := flat_pos + Vector2(0, -arc_offset)

	rotation = (new_pos - global_position).angle()
	global_position = new_pos

	if t >= 1.0:
		_land()


@onready var sprite: Sprite2D = $Sprite2D
@export var stuck_texture: Texture2D  # the tip-missing arrow art, used once it's lodged in an enemy

func _on_body_entered(body: Node2D) -> void:
	if _resolved:
		return
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		_resolved = true
		body.take_damage(damage, global_position)
		if body.has_method("stick_arrow"):
			var local_pos: Vector2 = body.to_local(global_position)
			var visual_texture: Texture2D = stuck_texture if stuck_texture else sprite.texture
			body.stick_arrow(local_pos, rotation - body.rotation, visual_texture)
		queue_free()

func _land() -> void:
	if _resolved:
		return
	_resolved = true
	queue_free()
