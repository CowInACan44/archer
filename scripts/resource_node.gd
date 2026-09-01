extends Node2D
class_name ResourceNode

## A gatherable Tree (Wood) or Rock (Stone) field, populated by
## ResourceSpawnPoint at the start of the matching Day/Night phase (trees
## by day, rocks by night - see DESIGN.md). Pawns claim one before
## walking to it so two pawns don't both commit to the same node, then
## harvest() drains it until it's empty and frees itself.

enum Kind { WOOD, STONE }

## Purely cosmetic ore tiers for now - same Rock sprite, different tint,
## no distinct economy yet (per the user's "for now just different color
## gradient" request). Weighted so plain Stone is the common case and
## Gold is a rare treat.
const ORE_TIERS := [
	{"tint": Color(1, 1, 1), "weight": 6.0},
	{"tint": Color(1.0, 0.55, 0.35), "weight": 2.5},  # iron - rust orange
	{"tint": Color(1.0, 0.85, 0.25), "weight": 1.0},  # gold - yellow
]

@export var kind: Kind = Kind.WOOD
@export var total_amount: int = 15
@export var click_radius: float = 40.0

@onready var sprite: Sprite2D = $Sprite2D

var claimed_by: Node = null
var _amount_left: int
var _sway_time := 0.0
var _sway_seed := 0.0


func _ready() -> void:
	add_to_group("resource_node")
	_amount_left = total_amount
	_sway_seed = randf() * TAU
	## Only trees sway - rocks stay still.
	set_process(kind == Kind.WOOD)


func _process(delta: float) -> void:
	_sway_time += delta
	sprite.rotation = sin(_sway_time * 1.3 + _sway_seed) * 0.035


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


## Direct player click-to-harvest, independent of (and concurrent with)
## whatever pawn may have this node claimed - a manual "clicker" layer on
## top of the auto-gathering pawns, per the Click Power incremental.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if global_position.distance_to(get_global_mouse_position()) > click_radius:
		return
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	var click_power: int = gm.click_power if "click_power" in gm else 1
	var amount: int = harvest(click_power)
	if amount <= 0:
		return
	hit_react()
	if kind == Kind.WOOD:
		gm.add_wood(amount)
	else:
		gm.add_stone(amount)


## A quick shake/punch when a pawn's swing lands, called repeatedly by
## Pawn during GATHERING (not just once at the end) so it reads as being
## actively struck rather than just standing near it.
func hit_react() -> void:
	var tween := create_tween()
	var punch: float = 0.12 if kind == Kind.STONE else 0.08
	tween.tween_property(sprite, "scale", Vector2.ONE * (1.0 + punch), 0.06)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.1)


## Tree1-4.png are NOT animation frames despite the wide sheet - pixel
## analysis showed each is 8 different tree/bush variants side by side,
## each exactly width/8 wide regardless of the sheet's height. Cropping
## with a height-based square (the pattern that works for the pawn/enemy
## strips) bled into the start of the next variant, showing two trees
## fused together. Rocks are already single clean images, no crop needed
## - they get a random ore-tier tint instead.
const TREE_VARIANT_COUNT := 8


func set_texture(tex: Texture2D) -> void:
	sprite.texture = tex
	if kind == Kind.WOOD:
		var cell_width := tex.get_width() / TREE_VARIANT_COUNT
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, cell_width, tex.get_height())
	else:
		sprite.region_enabled = false
		sprite.modulate = _roll_ore_tint()


func _roll_ore_tint() -> Color:
	var total := 0.0
	for tier in ORE_TIERS:
		total += tier.weight
	var roll := randf() * total
	for tier in ORE_TIERS:
		roll -= tier.weight
		if roll <= 0.0:
			return tier.tint
	return ORE_TIERS[0].tint
