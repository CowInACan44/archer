extends Node2D

## Shared container for everything that should layer by vertical position
## (towers, pawns, enemies, houses, resource nodes) instead of always
## drawing in a fixed order - y_sort_enabled on this node makes its
## direct children sort by global Y automatically.


func _ready() -> void:
	add_to_group("world_ysort")
