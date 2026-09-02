extends Node2D
class_name MapVariant

## Picks one hand-authored "map variant" at random each time this scene
## loads (see main_menu.gd's _on_play_pressed -> change_scene_to_file,
## which instances main.tscn fresh every run) and dresses the outer ring
## of the world in it - water, elevated cliff outcrops, and themed
## scatter decoration (mushrooms, extra bushes, pumpkins, an old
## battlefield's bones/totems). The kingdom itself, resource rings
## (ResourceField) and wildlife rings (WildlifeField) are untouched -
## everything here is placed outside the kingdom's build radius and is
## purely decorative (no collision), so it can't block a pawn's path or
## a tower's placement no matter how a variant's layout comes out.
##
## Water is built procedurally (irregular Polygon2D blobs) rather than
## from the tileset's water tiles - those are all animated ripple/foam
## strips or a cliff-base waterfall effect, nothing that forms a plain
## pond/river shape, so assembling one from them risked the same kind of
## "guessed tile assembly" mistake the sheep pen fence fell into earlier.
## Cliff outcrops instead DO use real tileset art (Tilemap_color3.png) -
## its right half is a grass-topped elevation kit: pixel-diffing every
## 64x64 cell confirmed each column's row-0 cell is a self-contained
## grass tuft and rows 4-5 of that same column are matching cliff-face
## tiles with a flat top edge, meant to stack directly underneath it.

const KINGDOM_CLEARANCE := 660.0
const OUTER_EDGE := 1350.0

## Sampled straight from Water Background color.png (RGB 71/171/169) so
## the procedural pond fill matches the game's actual water palette
## instead of a guessed teal.
const WATER_FILL_COLOR := Color(0.278, 0.671, 0.663, 0.92)
const WATER_RIM_COLOR := Color(0.42, 0.78, 0.75, 0.85)
const WATER_RIM_PULSE_COLOR := Color(0.55, 0.88, 0.84, 0.85)
const WATER_ROCK_TEX := preload("res://tiny/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks in the Water/Water Rocks_01.png")
const CLIFF_SHEET := preload("res://tiny/Tiny Swords (Free Pack)/Terrain/Tileset/Tilemap_color3.png")
const CLIFF_CELL := 64

const BUSH_TEXTURES := [
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Bushes/Bushe1.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Bushes/Bushe2.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Bushes/Bushe3.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Bushes/Bushe4.png"),
]
const ROCK_TEXTURES := [
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Rocks/Rock1.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Rocks/Rock2.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Rocks/Rock3.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Decorations/Rocks/Rock4.png"),
]
const MUSHROOM_TEXTURES := [
	preload("res://tiny/Tiny Swords (Update 010)/Deco/01.png"),
	preload("res://tiny/Tiny Swords (Update 010)/Deco/02.png"),
	preload("res://tiny/Tiny Swords (Update 010)/Deco/03.png"),
]
const PUMPKIN_TEXTURES := [
	preload("res://tiny/Tiny Swords (Update 010)/Deco/12.png"),
	preload("res://tiny/Tiny Swords (Update 010)/Deco/13.png"),
]
const BONE_TEXTURES := [
	preload("res://tiny/Tiny Swords (Update 010)/Deco/14.png"),
	preload("res://tiny/Tiny Swords (Update 010)/Deco/15.png"),
]
const TOTEM_TEXTURES := [
	preload("res://tiny/Tiny Swords (Update 010)/Deco/16.png"),
	preload("res://tiny/Tiny Swords (Update 010)/Deco/17.png"),
]

## Each variant is a themed arrangement rather than pure noise - water/
## cliffs sit in one angular arc (e.g. "a river along the north side")
## so a run reads as a distinct place, not just randomly speckled decor.
const MAP_VARIANTS := [
	{
		"name": "Riverside Vale",
		"water": [{"angle": 90.0, "arc": 70.0, "dist": 850.0, "count": 4, "radius": 130.0}],
		"cliffs": [],
		"scatter": [{"pool": "mushroom", "count": 10}, {"pool": "bush", "count": 6}],
	},
	{
		"name": "Rocky Highlands",
		"water": [],
		"cliffs": [{"angle": 300.0, "arc": 80.0, "dist": 950.0, "count": 5}],
		"scatter": [{"pool": "rock", "count": 8}, {"pool": "bush", "count": 4}],
	},
	{
		"name": "Mushroom Hollow",
		"water": [],
		"cliffs": [],
		"scatter": [{"pool": "mushroom", "count": 16}, {"pool": "bush", "count": 10}],
	},
	{
		"name": "Twin Lakes",
		"water": [
			{"angle": 40.0, "arc": 50.0, "dist": 900.0, "count": 3, "radius": 110.0},
			{"angle": 220.0, "arc": 50.0, "dist": 900.0, "count": 3, "radius": 110.0},
		],
		"cliffs": [],
		"scatter": [{"pool": "bush", "count": 8}, {"pool": "mushroom", "count": 6}],
	},
	{
		"name": "Windswept Bluffs",
		"water": [{"angle": 160.0, "arc": 40.0, "dist": 1000.0, "count": 3, "radius": 100.0}],
		"cliffs": [{"angle": 20.0, "arc": 90.0, "dist": 900.0, "count": 6}],
		"scatter": [{"pool": "rock", "count": 10}],
	},
	{
		"name": "Old Battlefield",
		"water": [{"angle": 260.0, "arc": 40.0, "dist": 950.0, "count": 3, "radius": 100.0}],
		"cliffs": [],
		"scatter": [{"pool": "bone", "count": 8}, {"pool": "totem", "count": 4}, {"pool": "rock", "count": 5}],
	},
]


func _ready() -> void:
	var variant: Dictionary = MAP_VARIANTS[randi() % MAP_VARIANTS.size()]
	name = "MapVariant_" + variant.name.replace(" ", "")

	for water in variant.water:
		_build_water_patch(water)
	for cliff in variant.cliffs:
		_build_cliff_cluster(cliff)
	for scatter in variant.scatter:
		_scatter_decoration(scatter.pool, scatter.count)


func _random_point_in_arc(center_angle_deg: float, arc_deg: float, dist: float, dist_jitter: float = 80.0) -> Vector2:
	var angle := deg_to_rad(center_angle_deg + randf_range(-arc_deg * 0.5, arc_deg * 0.5))
	var r: float = clampf(dist + randf_range(-dist_jitter, dist_jitter), KINGDOM_CLEARANCE, OUTER_EDGE)
	return Vector2(cos(angle), sin(angle)) * r


## A pond/river bend built from several overlapping irregular blobs
## instead of one shape, so a "river" reads as a winding band rather
## than a single perfect circle.
func _build_water_patch(spec: Dictionary) -> void:
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	if container == null:
		container = self
	var anchor: Vector2 = _random_point_in_arc(spec.angle, 0.0, spec.dist, 0.0)
	## One direction for the whole patch (perpendicular to the anchor's
	## radial angle, i.e. running "along" the kingdom's edge) so the
	## blobs read as a single elongated pond/river bend instead of a
	## scatter of independently-placed circles.
	var flow_dir := Vector2.from_angle(deg_to_rad(spec.angle + 90.0))
	var span: float = float(spec.radius) * float(spec.count) * 0.9
	for i in int(spec.count):
		var t: float = (float(i) / maxf(1.0, float(spec.count) - 1.0)) - 0.5
		var wobble := Vector2(randf_range(-25.0, 25.0), randf_range(-25.0, 25.0))
		var blob_pos: Vector2 = anchor + flow_dir * span * t + wobble
		_spawn_water_blob(container, blob_pos, float(spec.radius) * randf_range(0.8, 1.15))


func _spawn_water_blob(container: Node, pos: Vector2, radius: float) -> void:
	var fill := Polygon2D.new()
	fill.polygon = _blob_points(radius)
	fill.color = WATER_FILL_COLOR
	fill.position = pos
	fill.z_as_relative = false
	container.add_child(fill)
	fill.global_position = pos

	var rim := Polygon2D.new()
	rim.polygon = _blob_points(radius * 0.82)
	rim.color = WATER_RIM_COLOR
	rim.z_as_relative = false
	fill.add_child(rim)

	## Gentle shimmer instead of trying to align the tileset's animated
	## ripple strip to an arbitrary blob edge - a slow color pulse reads
	## as moving water without needing pixel-perfect tile alignment.
	var tween := fill.create_tween()
	tween.set_loops()
	tween.tween_property(rim, "color", WATER_RIM_PULSE_COLOR, 1.4)
	tween.tween_property(rim, "color", WATER_RIM_COLOR, 1.4)

	if randf() < 0.6:
		var rock := Sprite2D.new()
		rock.texture = WATER_ROCK_TEX
		rock.region_enabled = true
		rock.region_rect = Rect2(0, 0, 64, 64)  # first frame of a 16-frame ripple loop, used as a static rock+splash accent
		rock.scale = Vector2.ONE * randf_range(1.4, 2.0)
		rock.position = Vector2.from_angle(randf() * TAU) * radius * 0.75
		fill.add_child(rock)


func _blob_points(radius: float, sides: int = 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var angle: float = TAU * float(i) / float(sides)
		var r: float = radius * randf_range(0.75, 1.15)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts


## Stacks a grass-top tile over 1-2 cliff-face tiles from the same
## sheet column to form a standalone elevated outcrop - see the class
## doc comment for how this pairing was verified against the art.
func _build_cliff_cluster(spec: Dictionary) -> void:
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	if container == null:
		container = self
	var columns := [5, 6, 7, 8]
	for i in int(spec.count):
		var pos: Vector2 = _random_point_in_arc(spec.angle, spec.arc, spec.dist)
		var col: int = columns[randi() % columns.size()]
		var height: int = 1 + (randi() % 2)
		_spawn_cliff_outcrop(container, pos, col, height)


func _spawn_cliff_outcrop(container: Node, pos: Vector2, col: int, height: int) -> void:
	var root := Node2D.new()
	container.add_child(root)
	root.global_position = pos

	var grass := Sprite2D.new()
	grass.texture = _cliff_cell(col, 0)
	root.add_child(grass)

	for h in height:
		var cliff := Sprite2D.new()
		cliff.texture = _cliff_cell(col, 4 + h)
		cliff.position = Vector2(0, CLIFF_CELL * (h + 1))
		root.add_child(cliff)


func _cliff_cell(col: int, row: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = CLIFF_SHEET
	atlas.region = Rect2(col * CLIFF_CELL, row * CLIFF_CELL, CLIFF_CELL, CLIFF_CELL)
	return atlas


func _scatter_decoration(pool: String, count: int) -> void:
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	if container == null:
		container = self
	var textures: Array = _pool_textures(pool)
	if textures.is_empty():
		return
	for i in count:
		var sprite := Sprite2D.new()
		sprite.texture = textures[randi() % textures.size()]
		if pool == "bush":
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, 128, 128)
		sprite.scale = Vector2.ONE * randf_range(0.85, 1.2)
		container.add_child(sprite)
		sprite.global_position = _random_point_in_arc(randf() * 360.0, 360.0, 950.0, 380.0)


func _pool_textures(pool: String) -> Array:
	match pool:
		"mushroom":
			return MUSHROOM_TEXTURES
		"bush":
			return BUSH_TEXTURES
		"rock":
			return ROCK_TEXTURES
		"pumpkin":
			return PUMPKIN_TEXTURES
		"bone":
			return BONE_TEXTURES
		"totem":
			return TOTEM_TEXTURES
	return []
