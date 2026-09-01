extends Node2D
class_name ResourceSpawnPoint

## A fixed world location that may or may not currently have a
## ResourceNode standing on it. Trees have a chance to appear at the
## start of each Day, rock/mineral nodes at the start of each Night -
## day = wood-leaning, night = stone-leaning per DESIGN.md - so pawns
## always have something to do, and the world doesn't fill up solid.

const RESOURCE_NODE_SCENE := preload("res://scenes/resource_node.tscn")

const TREE_TEXTURES := [
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Trees/Tree1.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Trees/Tree2.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Trees/Tree3.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Trees/Tree4.png"),
]
const ROCK_TEXTURES := [
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Rocks/Rock1.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Rocks/Rock2.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Rocks/Rock3.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Rocks/Rock4.png"),
]

@export var kind: ResourceNode.Kind = ResourceNode.Kind.WOOD
@export var spawn_chance: float = 0.6

## Trees/rocks scattered in a wide ring can still land close enough to a
## tower or house to visually overlap it (spotted growing right out of a
## tower) - skip spawning there instead.
@export var building_clearance: float = 110.0

var _current: Node = null


func _ready() -> void:
	add_to_group("resource_spawn_point")
	var day_cycle: Node = get_tree().get_first_node_in_group("day_night_cycle")
	if day_cycle:
		day_cycle.phase_changed.connect(_on_phase_changed)
		## Give day-phase (wood) points an immediate chance to populate on
		## a fresh game rather than waiting for the first phase change.
		if kind == ResourceNode.Kind.WOOD and day_cycle.phase == 0:
			_maybe_spawn()


func _on_phase_changed(phase: int, _day_number: int) -> void:
	var day_phase: bool = phase == 0  # DayNightCycle.Phase.DAY
	var matches: bool = (kind == ResourceNode.Kind.WOOD) == day_phase
	if matches:
		_maybe_spawn()


func _maybe_spawn() -> void:
	if _current != null and is_instance_valid(_current):
		return
	if randf() > spawn_chance:
		return
	if _too_close_to_buildings():
		return
	var node := RESOURCE_NODE_SCENE.instantiate()
	node.kind = kind
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	(container if container else get_parent()).add_child(node)
	node.global_position = global_position
	node.tree_exited.connect(_on_node_gone)
	_current = node

	var textures: Array = TREE_TEXTURES if kind == ResourceNode.Kind.WOOD else ROCK_TEXTURES
	node.set_texture(textures[randi() % textures.size()])


func _on_node_gone() -> void:
	_current = null


func _too_close_to_buildings() -> bool:
	for t in get_tree().get_nodes_in_group("tower"):
		if is_instance_valid(t) and global_position.distance_to(t.global_position) < building_clearance:
			return true
	for h in get_tree().get_nodes_in_group("house"):
		if is_instance_valid(h) and global_position.distance_to(h.global_position) < building_clearance:
			return true
	return false
