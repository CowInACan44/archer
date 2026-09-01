extends Node2D
class_name ResourceField

## Scatters ResourceSpawnPoints around the kingdom in several rings with
## jittered angle/radius so pawns have real forest/quarry areas to
## gather from instead of a thin ring of evenly-spaced dots.

const SPAWN_POINT_SCRIPT := preload("res://scripts/resource_spawn_point.gd")

@export var ring_radii: Array[float] = [650.0, 850.0, 1050.0]
@export var points_per_ring: int = 16
@export var angle_jitter_deg: float = 12.0
@export var radius_jitter: float = 60.0
@export var spawn_chance: float = 0.55


func _ready() -> void:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	var center: Vector2 = km.to_global(km.center) if km else Vector2.ZERO

	var index := 0
	for ring_index in ring_radii.size():
		var ring_radius: float = ring_radii[ring_index]
		## Offset each ring's starting angle so points don't line up
		## radially between rings - reads more like a scattered forest.
		var ring_offset: float = (TAU / points_per_ring) * 0.5 * ring_index

		for i in points_per_ring:
			var angle: float = (TAU / points_per_ring) * i + ring_offset
			angle += deg_to_rad(randf_range(-angle_jitter_deg, angle_jitter_deg))
			var r: float = ring_radius + randf_range(-radius_jitter, radius_jitter)
			var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * r

			var point := Node2D.new()
			point.set_script(SPAWN_POINT_SCRIPT)
			point.kind = ResourceNode.Kind.WOOD if index % 2 == 0 else ResourceNode.Kind.STONE
			point.spawn_chance = spawn_chance
			add_child(point)
			point.global_position = pos
			index += 1
