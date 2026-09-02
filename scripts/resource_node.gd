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

const GOLD_PICKUP_SCENE := preload("res://scenes/GoldPickup.tscn")

@export var kind: Kind = Kind.WOOD
@export var total_amount: int = 15
@export var click_radius: float = 40.0

## Trees have a small chance to also toss out a money bag on top of the
## wood - scaled by the same Gold Drop Rate incremental enemies' gold
## drops use, so that upgrade pays off while chopping too.
@export var wood_gold_bag_chance: float = 0.12
@export var wood_gold_bag_amount: int = 4

@onready var sprite: Sprite2D = $Sprite2D

var claimed_by: Node = null
var _amount_left: int

## Real hand-drawn sway frames (see set_texture()'s TREE_SWAY_SPECIES
## comment) cycled here instead of the rotation-lerp fake sway this used
## to do - trees now use their actual idle animation.
var _sway_frames: Array[Texture2D] = []
var _sway_frame_time := 0.0
var _sway_frame_index := 0
@export var sway_seconds_per_frame: float = 0.35


func _ready() -> void:
	add_to_group("resource_node")
	_amount_left = total_amount
	## Only trees sway - rocks stay still.
	set_process(kind == Kind.WOOD)


func _process(delta: float) -> void:
	if _sway_frames.is_empty():
		return
	_sway_frame_time += delta
	var idx: int = int(_sway_frame_time / sway_seconds_per_frame) % _sway_frames.size()
	if idx != _sway_frame_index:
		_sway_frame_index = idx
		sprite.texture = _sway_frames[idx]


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
	if amount > 0 and kind == Kind.WOOD:
		_maybe_drop_gold_bag()
	if _amount_left <= 0:
		queue_free()
	return amount


func _maybe_drop_gold_bag() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var mult: float = gm.gold_drop_chance_mult if gm and "gold_drop_chance_mult" in gm else 1.0
	var luck: float = gm.luck if gm and "luck" in gm else 1.0
	if randf() >= wood_gold_bag_chance * mult * luck:
		return
	var bag := GOLD_PICKUP_SCENE.instantiate()
	bag.amount = wood_gold_bag_amount
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	(container if container else get_tree().current_scene).add_child(bag)
	bag.global_position = global_position


## Direct player click-to-harvest, independent of (and concurrent with)
## whatever pawn may have this node claimed - a manual "clicker" layer on
## top of the auto-gathering pawns, per the Click Power incremental.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if global_position.distance_to(get_global_mouse_position()) > click_radius:
		return
	var hud: Node = get_tree().get_first_node_in_group("hud_tabs")
	if hud and hud.has_method("is_panel_open_under_mouse") and hud.is_panel_open_under_mouse():
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


## A quick shake/punch when a pawn's swing (or a player click) lands,
## called repeatedly by Pawn during GATHERING (not just once at the end)
## so it reads as being actively struck rather than just standing near
## it. Squash-and-stretch plus a rotation kick reads as a much more
## satisfying hit than a plain uniform scale punch.
func hit_react() -> void:
	var tween := create_tween()
	var punch: float = 0.16 if kind == Kind.STONE else 0.12
	var kick: float = deg_to_rad(randf_range(-1, 1)) * (10.0 if kind == Kind.WOOD else 5.0)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "scale", Vector2(1.0 + punch, 1.0 - punch * 0.6), 0.05)
	tween.parallel().tween_property(sprite, "rotation", sprite.rotation + kick, 0.05)
	tween.tween_property(sprite, "scale", Vector2(1.0 - punch * 0.4, 1.0 + punch * 0.6), 0.08)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "rotation", 0.0, 0.12)


## Tree.png (Update 010's Resources/Trees sheet) packs multiple 192x192
## cells: pixel-diffing each cell's alpha silhouette against its neighbors
## confirmed row 0's 4 cells are a genuine sway cycle (cell 0 and cell 2
## are pixel-identical - a neutral pose - with cells 1/3 leaning a few
## percent either way) and row 1's first 2 cells are a second, shorter
## sway cycle for a slightly different tree - two real "species" rather
## than the Free Pack's Tree1-4.png, which pixel analysis showed were 8
## static variants side by side, not animation frames at all. Rocks are
## already single clean images, no crop needed - they get a random
## ore-tier tint instead.
const TREE_SWAY_FRAME_SIZE := 192
const TREE_SWAY_SPECIES := [
	{"row": 0, "frames": 4},
	{"row": 1, "frames": 2},
]


func set_texture(tex: Texture2D) -> void:
	if kind == Kind.WOOD:
		_build_sway_frames(tex)
		sprite.texture = _sway_frames[0]
	else:
		sprite.texture = tex
		sprite.region_enabled = false
		sprite.modulate = _roll_ore_tint()


func _build_sway_frames(tex: Texture2D) -> void:
	var species: Dictionary = TREE_SWAY_SPECIES[randi() % TREE_SWAY_SPECIES.size()]
	var row: int = species.row
	var frame_count: int = species.frames
	_sway_frames.clear()
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * TREE_SWAY_FRAME_SIZE, row * TREE_SWAY_FRAME_SIZE, TREE_SWAY_FRAME_SIZE, TREE_SWAY_FRAME_SIZE)
		_sway_frames.append(atlas)
	## Stagger each tree's start point around its own cycle so a whole
	## forest doesn't sway in perfect unison.
	_sway_frame_time = randf() * sway_seconds_per_frame * frame_count


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
