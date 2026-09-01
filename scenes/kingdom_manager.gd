extends Node2D
class_name KingdomManager

const TOWER_SCENE := preload("res://scenes/tower.tscn")
const POINT_COUNT := 8

## Placeholder wall art - there's no dedicated wall/palisade tileset in the
## asset pack yet, so we reuse the goblin camp's wooden fence tile spaced
## out along each unlocked edge. Swap FENCE_REGION if a different sub-tile
## from the sheet reads better once you can preview it in the editor.
const FENCE_TEXTURE := preload("res://tiny/Tiny Swords (Enemy Pack)/Enemy Pack/Enemies/Goblin Raiders/Wooden Fence/Wooden Fence_64x64 tile.png")
const FENCE_REGION := Rect2(0, 0, 64, 64)
const FENCE_TILE_SIZE := 64.0

## Grander stone-tower base art for the "kingdom fully fortified" payoff
## once all 8 points are built (see _check_kingdom_expanded) - there's no
## dedicated wall/gate tileset in the asset packs to build real
## fortification geometry from, so the wall ring gets a stone tint
## instead of new geometry, and the towers themselves get a taller,
## sturdier base texture from the Knights faction set.
const FORTIFIED_TOWER_TEXTURE := preload("res://tiny/Tiny Swords (Update 010)/Factions/Knights/Buildings/Tower/Tower_Yellow.png")
const FORTIFIED_WALL_TINT := Color(0.62, 0.64, 0.7, 1.0)

@export var center: Vector2 = Vector2.ZERO
@export var radius: float = 600.0
@export var start_angle_offset_deg: float = -90.0  # -90 = point 0 at top
@export var unlock_at_wave: int = 5

var point_positions: Array[Vector2] = []
var point_towers: Array[Node] = []          # null until built
var unlocked_indices: Array[int] = [0]      # point 0 starts unlocked

signal point_unlocked(index: int, world_position: Vector2)
signal tower_built(index: int, tower: Node)

## Fires once, the moment every tower ever built is simultaneously
## destroyed - previously there was no actual lose condition since a
## tower can always be repaired/rebuilt given enough materials, so a
## player could keep going indefinitely even with every tower down.
signal all_towers_destroyed

## Fires once, the moment all 8 octagon points have a standing tower at
## the same time - the "expand into a kingdom" milestone from DESIGN.md.
signal kingdom_expanded
var _kingdom_expanded_fired := false


@onready var camera: Camera2D = $Camera2D

@export var zoom_per_point: float = 0.08   # how much to zoom out per unlocked point
@export var zoom_tween_duration: float = 1.0
@export var min_zoom: float = 0.35          # don't zoom out past this

var _wall_container: Node2D
var _walled_segments: Array[int] = []  # index i means the edge point_positions[i] -> point_positions[i+1] is built


func _ready() -> void:
	add_to_group("kingdom_manager")
	_generate_points()

	_wall_container = Node2D.new()
	_wall_container.name = "Walls"
	_wall_container.z_index = -1
	add_child(_wall_container)

	_spawn_tower_at(0)
	## Center on the actual first tower, not the abstract octagon "center" -
	## those only match if center/radius happen to line up with point 0,
	## which left the camera looking at empty ground far from the tower.
	camera.global_position = point_positions[0]
	camera.zoom = Vector2.ONE

	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.wave_cleared.connect(_on_wave_cleared)


## A single, centralized scan for the repair-hammer cursor instead of each
## tower fighting over the shared OS cursor via its own mouse_entered/
## exited signals - with several towers on screen those could race and
## leave the wrong cursor showing depending on scene-tree processing
## order (this is why only the first-built tower ever showed the hammer).
func _process(_delta: float) -> void:
	var mouse_pos := get_global_mouse_position()
	var hovered_tower: Node = null
	for t in point_towers:
		if t == null or not is_instance_valid(t):
			continue
		if t.has_method("contains_point") and t.contains_point(mouse_pos):
			hovered_tower = t
			break

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var wants_hammer: bool = hovered_tower and hovered_tower.hammer_cursor and (hovered_tower.needs_repair() or hovered_tower.is_destroyed)
	if wants_hammer:
		Input.set_custom_mouse_cursor(hovered_tower.hammer_cursor, Input.CURSOR_ARROW, hovered_tower.hammer_cursor_hotspot)
	elif gm and gm.default_cursor:
		Input.set_custom_mouse_cursor(gm.default_cursor, Input.CURSOR_ARROW, gm.default_cursor_hotspot)
	else:
		Input.set_custom_mouse_cursor(null)


func _on_wave_cleared(wave_number: int) -> void:
	## Every unlock_at_wave waves (not just the first time), so the octagon
	## keeps filling in over the course of a run instead of stopping after
	## one extra tower.
	if unlock_at_wave > 0 and wave_number % unlock_at_wave == 0:
		var index := unlock_next_point()
		if index != -1:
			try_build_tower(index)
			_zoom_out_camera()


func _zoom_out_camera() -> void:
	var target_zoom_value: float = maxf(min_zoom, 1.0 - zoom_per_point * unlocked_indices.size())
	var target_zoom := Vector2(target_zoom_value, target_zoom_value)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "zoom", target_zoom, zoom_tween_duration)


func _generate_points() -> void:
	point_positions.clear()
	point_towers.clear()
	for i in range(POINT_COUNT):
		var angle := deg_to_rad(start_angle_offset_deg + (360.0 / POINT_COUNT) * i)
		var pos := center + Vector2(cos(angle), sin(angle)) * radius
		point_positions.append(pos)
		point_towers.append(null)


func unlock_next_point() -> int:
	for i in range(POINT_COUNT):
		if i not in unlocked_indices:
			unlocked_indices.append(i)
			point_unlocked.emit(i, point_positions[i])
			_update_walls()
			return i
	return -1  # all points already unlocked


## Fills in a fence segment for any edge whose both endpoints are now
## unlocked. Points unlock in order (0, 1, 2, ...) so this naturally grows
## a connected wall arc around the octagon instead of leaving gaps.
func _update_walls() -> void:
	for i in range(POINT_COUNT):
		var next_i := (i + 1) % POINT_COUNT
		if i in _walled_segments:
			continue
		if i in unlocked_indices and next_i in unlocked_indices:
			_build_wall_segment(point_positions[i], point_positions[next_i])
			_walled_segments.append(i)


func _build_wall_segment(from_pos: Vector2, to_pos: Vector2) -> void:
	var segment := to_pos - from_pos
	var length := segment.length()
	if length <= 0.0:
		return
	var angle := segment.angle()
	var tile_count := int(ceil(length / FENCE_TILE_SIZE))

	for i in range(tile_count):
		var t: float = (i + 0.5) / tile_count
		var post := Sprite2D.new()
		post.texture = FENCE_TEXTURE
		post.region_enabled = true
		post.region_rect = FENCE_REGION
		post.position = from_pos.lerp(to_pos, t)
		post.rotation = angle
		_wall_container.add_child(post)


func can_build_at(index: int) -> bool:
	return index in unlocked_indices and point_towers[index] == null


func _spawn_tower_at(index: int) -> Node:
	var tower := TOWER_SCENE.instantiate()
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	(container if container else get_tree().current_scene).add_child(tower)
	tower.global_position = point_positions[index]
	point_towers[index] = tower
	tower.tower_destroyed.connect(_check_all_towers_destroyed)

	## New towers start with every upgrade card already picked this run,
	## so a tower built at point 5 isn't weaker than the ones built earlier.
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("register_tower"):
		gm.register_tower(tower)

	_clear_resource_nodes_near(tower.global_position)

	## A tower rebuilt after the kingdom already fully expanded should
	## come back fortified too, not revert to the plain starting look.
	if _kingdom_expanded_fired and tower.has_method("set_fortified"):
		tower.set_fortified(FORTIFIED_TOWER_TEXTURE)

	tower_built.emit(index, tower)
	_check_kingdom_expanded()
	return tower


func _check_kingdom_expanded() -> void:
	if _kingdom_expanded_fired:
		return
	if get_built_tower_positions().size() < POINT_COUNT:
		return
	_kingdom_expanded_fired = true
	for tower in point_towers:
		if tower != null and is_instance_valid(tower) and tower.has_method("set_fortified"):
			tower.set_fortified(FORTIFIED_TOWER_TEXTURE)
	for tile in _wall_container.get_children():
		tile.modulate = FORTIFIED_WALL_TINT
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("apply_kingdom_expansion_bonus"):
		gm.apply_kingdom_expansion_bonus()
	kingdom_expanded.emit()


## A tree/rock can grow on a spot before a tower is later built there
## (ResourceSpawnPoints don't know a tower is coming) - clear anything
## already standing where the new tower just went up instead of leaving
## it looking like the tower grew out of a tree.
var _game_over_fired := false


func _check_all_towers_destroyed() -> void:
	if _game_over_fired:
		return
	var any_built := false
	for t in point_towers:
		if t == null or not is_instance_valid(t):
			continue
		any_built = true
		if not t.is_destroyed:
			return
	if any_built:
		_game_over_fired = true
		all_towers_destroyed.emit()


func _clear_resource_nodes_near(pos: Vector2, clearance: float = 110.0) -> void:
	for node in get_tree().get_nodes_in_group("resource_node"):
		if is_instance_valid(node) and pos.distance_to(node.global_position) < clearance:
			node.queue_free()


func try_build_tower(index: int) -> Node:
	if not can_build_at(index):
		return null
	return _spawn_tower_at(index)


func get_unlocked_empty_points() -> Array[int]:
	var result: Array[int] = []
	for i in unlocked_indices:
		if point_towers[i] == null:
			result.append(i)
	return result


## World positions of every currently-standing (built and not destroyed)
## tower - used by EnemySpawner to spread spawns around the whole octagon
## instead of clustering near wherever the fixed spawn markers happen to
## sit, which used to make every enemy "nearest tower" resolve to the
## same one regardless of where it actually spawned.
func get_built_tower_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for t in point_towers:
		if t == null or not is_instance_valid(t):
			continue
		if "is_destroyed" in t and t.is_destroyed:
			continue
		result.append(t.global_position)
	return result
