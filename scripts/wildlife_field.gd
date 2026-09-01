extends Node2D
class_name WildlifeField

## Scatters WildlifeSpawnPoints around the kingdom so Hunter-job pawns
## (see pawn.gd's Job.HUNTER) have real Sheep/Bear to track down - Sheep
## in a closer, denser ring so early hunting/breeding is reachable, Bear
## further out and sparser since it's the tougher, higher-meat target.

const SPAWN_POINT_SCRIPT := preload("res://scripts/wildlife_spawn_point.gd")

@export var sheep_ring_radius: float = 750.0
@export var bear_ring_radius: float = 1100.0
@export var sheep_count: int = 10
@export var bear_count: int = 5
@export var radius_jitter: float = 120.0


func _ready() -> void:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	var center: Vector2 = km.to_global(km.center) if km else Vector2.ZERO
	_scatter(center, sheep_ring_radius, sheep_count, Wildlife.Kind.SHEEP, 0.5)
	_scatter(center, bear_ring_radius, bear_count, Wildlife.Kind.BEAR, 0.3)


func _scatter(center: Vector2, ring_radius: float, count: int, kind: int, chance: float) -> void:
	for i in count:
		var angle: float = (TAU / count) * i + randf_range(-0.3, 0.3)
		var r: float = ring_radius + randf_range(-radius_jitter, radius_jitter)
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * r

		var point := Node2D.new()
		point.set_script(SPAWN_POINT_SCRIPT)
		point.kind = kind
		point.spawn_chance = chance
		add_child(point)
		point.global_position = pos
