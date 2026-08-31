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

var pawns: Array[Node] = []
var _respawn_timer: Timer


func _ready() -> void:
	add_to_group("house")
	_respawn_timer = Timer.new()
	_respawn_timer.wait_time = pawn_respawn_time
	add_child(_respawn_timer)
	_respawn_timer.timeout.connect(_on_respawn_timer)
	_respawn_timer.start()

	for i in capacity:
		_spawn_pawn()


func _spawn_pawn() -> void:
	var pawn := PAWN_SCENE.instantiate()
	pawn.home_house = self
	get_tree().current_scene.add_child(pawn)
	var offset := Vector2(randf_range(-spawn_scatter_radius, spawn_scatter_radius), randf_range(-spawn_scatter_radius, spawn_scatter_radius))
	pawn.global_position = global_position + offset
	pawn.died.connect(_on_pawn_died.bind(pawn))
	pawns.append(pawn)


func _on_pawn_died(pawn: Node) -> void:
	pawns.erase(pawn)


func _on_respawn_timer() -> void:
	if pawns.size() < capacity:
		_spawn_pawn()
