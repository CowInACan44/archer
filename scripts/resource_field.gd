extends Node2D
class_name ResourceField

## Scatters ResourceSpawnPoints in a ring around the kingdom so pawns
## have trees/rocks to gather from without hand-placing dozens of nodes
## in main.tscn - alternates Wood/Stone points evenly around the circle.

const SPAWN_POINT_SCRIPT := preload("res://scripts/resource_spawn_point.gd")

@export var point_count: int = 12
@export var radius: float = 780.0
@export var spawn_chance: float = 0.6


func _ready() -> void:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	var center: Vector2 = km.to_global(km.center) if km else Vector2.ZERO

	for i in point_count:
		var angle: float = (TAU / point_count) * i
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius

		var point := Node2D.new()
		point.set_script(SPAWN_POINT_SCRIPT)
		point.kind = ResourceNode.Kind.WOOD if i % 2 == 0 else ResourceNode.Kind.STONE
		point.spawn_chance = spawn_chance
		add_child(point)
		point.global_position = pos
