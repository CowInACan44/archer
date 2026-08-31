extends Node2D
class_name WoodPickup

@export var amount: int = 5
@export var pickup_radius: float = 24.0
@export var float_amplitude: float = 3.0
@export var float_speed: float = 4.0

@export var toss_duration: float = 0.4
@export var toss_spins: float = 1.5
@export var toss_arc_height: float = 50.0

@export var scatter_radius: float = 40.0
@export var scatter_duration: float = 0.35

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _collected := false
var _float_time := 0.0
var _settled := false


func _ready() -> void:
	sprite.play("spawn")
	sprite.animation_finished.connect(_on_spawn_finished)
	call_deferred("_scatter_on_spawn")

func _scatter_on_spawn() -> void:
	var offset := Vector2(randf_range(-scatter_radius, scatter_radius), randf_range(-scatter_radius, scatter_radius))
	var target := global_position + offset
	var tween := create_tween()
	tween.tween_property(self, "global_position", target, scatter_duration) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func(): _settled = true)


func _on_spawn_finished() -> void:
	if sprite.animation == "spawn":
		sprite.play("idle")


func _process(delta: float) -> void:
	if _collected:
		return
	_float_time += delta
	sprite.position.y = -abs(sin(_float_time * float_speed)) * float_amplitude

	var mouse_pos := get_global_mouse_position()
	if global_position.distance_to(mouse_pos) <= pickup_radius:
		_collect()


func _collect() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var tower: Node = gm.nearest_tower(global_position) if gm else null
	if tower == null:
		queue_free()
		return

	_collected = true
	var start_pos: Vector2 = global_position
	var target_pos: Vector2 = tower.global_position

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_update_toss_position.bind(start_pos, target_pos), 0.0, 1.0, toss_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "rotation_degrees", 360.0 * toss_spins, toss_duration) \
		.set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(_on_arrival)


func _update_toss_position(t: float, start_pos: Vector2, end_pos: Vector2) -> void:
	var flat := start_pos.lerp(end_pos, t)
	var arc := toss_arc_height * 4.0 * t * (1.0 - t)
	global_position = flat + Vector2(0, -arc)


func _on_arrival() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("add_wood"):
		gm.add_wood(amount)
	queue_free()
