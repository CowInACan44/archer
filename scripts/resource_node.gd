extends Node2D
class_name ResourceNode

## A gatherable Tree (Wood) or Rock (Stone) field, populated by
## ResourceSpawnPoint at the start of the matching Day/Night phase (trees
## by day, rocks by night - see DESIGN.md). Pawns claim one before
## walking to it so two pawns don't both commit to the same node, then
## harvest() drains it until it's empty and frees itself.

enum Kind { WOOD, STONE }

@export var kind: Kind = Kind.WOOD
@export var total_amount: int = 15

@onready var sprite: Sprite2D = $Sprite2D

var claimed_by: Node = null
var _amount_left: int


func _ready() -> void:
	add_to_group("resource_node")
	_amount_left = total_amount


func is_available() -> bool:
	return _amount_left > 0 and claimed_by == null


func claim(pawn: Node) -> bool:
	if not is_available():
		return false
	claimed_by = pawn
	return true


func release(pawn: Node) -> void:
	if claimed_by == pawn:
		claimed_by = null


## Returns how much was actually taken (may be less than requested_amount
## if the node was close to empty). Frees the node once drained.
func harvest(requested_amount: int) -> int:
	var amount: int = mini(requested_amount, _amount_left)
	_amount_left -= amount
	if _amount_left <= 0:
		queue_free()
	return amount


## Trees (1536x192-ish sheets, a few idle-sway frames) get cropped to
## their first frame as a plain static sprite; rocks are already single
## clean images, no cropping needed.
func set_texture(tex: Texture2D) -> void:
	sprite.texture = tex
	if kind == Kind.WOOD:
		var size := tex.get_height()
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, size, size)
	else:
		sprite.region_enabled = false
