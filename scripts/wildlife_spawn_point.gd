extends Node2D
class_name WildlifeSpawnPoint

## Fixed world location that may or may not currently have a live Sheep
## or Bear standing on it - same fixed-point/respawn-on-a-timer shape as
## ResourceSpawnPoint, just for wildlife instead of trees/rocks. Placed
## in rings by WildlifeField.

const SHEEP_SCENE := preload("res://scenes/sheep.tscn")
const BEAR_SCENE := preload("res://scenes/bear.tscn")

@export var kind: Wildlife.Kind = Wildlife.Kind.SHEEP
@export var spawn_chance: float = 0.4
@export var respawn_delay: float = 45.0

var _current: Node = null
var _respawn_timer: Timer


func _ready() -> void:
	add_to_group("wildlife_spawn_point")
	_respawn_timer = Timer.new()
	_respawn_timer.one_shot = true
	_respawn_timer.wait_time = respawn_delay
	add_child(_respawn_timer)
	_respawn_timer.timeout.connect(_maybe_spawn)
	_maybe_spawn()


func _maybe_spawn() -> void:
	if _current != null and is_instance_valid(_current):
		return
	if randf() > spawn_chance:
		_respawn_timer.start()
		return
	var scene: PackedScene = SHEEP_SCENE if kind == Wildlife.Kind.SHEEP else BEAR_SCENE
	var creature := scene.instantiate()
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	(container if container else get_parent()).add_child(creature)
	creature.global_position = global_position
	creature.tree_exited.connect(_on_creature_gone)
	_current = creature


func _on_creature_gone() -> void:
	_current = null
	_respawn_timer.start()
