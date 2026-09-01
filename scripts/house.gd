extends Node2D
class_name House

## Player-placed home for pawns. Spawns pawns up to capacity immediately,
## and replaces any that die (to a horde, mostly) after a cooldown so
## losing pawns hurts but doesn't permanently cripple the village. Same
## sprite at every capacity tier per DESIGN.md - only the pawn count goes
## up, no new art needed.

const PAWN_SCENE := preload("res://scenes/pawn.tscn")

@export var capacity: int = 2
@export var pawn_respawn_time: float = 20.0
@export var spawn_scatter_radius: float = 50.0

## Undefended civilian building - much squishier than a tower, so hordes
## that reach the village actually threaten it instead of walking past.
@export var max_health: int = 50
@export var hit_flash_duration: float = 0.12

var pawns: Array[Node] = []
var current_health: int
var is_destroyed := false
var _respawn_timer: Timer

signal health_changed(current: int, max_health: int)
signal house_destroyed

@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar_fill: ColorRect = $HealthBar/BarFill


## Called right after instantiate() by whoever's placing this house, if
## the player picked a variant other than the scene's default - purely
## cosmetic, every variant has the same capacity/health/behavior.
func set_house_texture(tex: Texture2D) -> void:
	sprite.texture = tex


func _ready() -> void:
	add_to_group("house")
	current_health = max_health
	health_changed.emit(current_health, max_health)
	_respawn_timer = Timer.new()
	_respawn_timer.wait_time = pawn_respawn_time
	add_child(_respawn_timer)
	_respawn_timer.timeout.connect(_on_respawn_timer)
	_respawn_timer.start()

	for i in capacity:
		_spawn_pawn()


func take_damage(amount: int, hit_from: Vector2 = Vector2.ZERO) -> void:
	if is_destroyed:
		return
	current_health -= amount
	health_changed.emit(current_health, max_health)
	health_bar_fill.anchor_right = clampf(float(current_health) / float(max_health), 0.0, 1.0)
	_flash_hit()
	if current_health <= 0:
		_destroy()


func _flash_hit() -> void:
	sprite.modulate = Color(3, 1.2, 1.2)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1), hit_flash_duration)


func _destroy() -> void:
	is_destroyed = true
	house_destroyed.emit()
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _spawn_pawn() -> void:
	var pawn := PAWN_SCENE.instantiate()
	pawn.home_house = self
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	(container if container else get_tree().current_scene).add_child(pawn)
	var offset := Vector2(randf_range(-spawn_scatter_radius, spawn_scatter_radius), randf_range(-spawn_scatter_radius, spawn_scatter_radius))
	pawn.global_position = global_position + offset
	pawn.died.connect(_on_pawn_died.bind(pawn))
	pawns.append(pawn)


func _on_pawn_died(pawn: Node) -> void:
	pawns.erase(pawn)


func _on_respawn_timer() -> void:
	if pawns.size() < capacity:
		_spawn_pawn()
