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


## Tree1-4.png are NOT animation frames despite the wide sheet - pixel
## analysis showed each is 8 different tree/bush variants side by side,
## each exactly width/8 wide regardless of the sheet's height. Cropping
## with a height-based square (the pattern that works for the pawn/enemy
## strips) bled into the start of the next variant, showing two trees
## fused together. Rocks are already single clean images, no crop needed.
const TREE_VARIANT_COUNT := 8


func set_texture(tex: Texture2D) -> void:
	sprite.texture = tex
	if kind == Kind.WOOD:
		var cell_width := tex.get_width() / TREE_VARIANT_COUNT
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, cell_width, tex.get_height())
	else:
		sprite.region_enabled = false
