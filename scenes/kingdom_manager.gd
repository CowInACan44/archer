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

@export var center: Vector2 = Vector2.ZERO
@export var radius: float = 600.0
@export var start_angle_offset_deg: float = -90.0  # -90 = point 0 at top
@export var unlock_at_wave: int = 5

var point_positions: Array[Vector2] = []
var point_towers: Array[Node] = []          # null until built
var unlocked_indices: Array[int] = [0]      # point 0 starts unlocked

signal point_unlocked(index: int, world_position: Vector2)
signal tower_built(index: int, tower: Node)


@onready var camera: Camera2D = $Camera2D

@export var zoom_per_point: float = 0.08   # how much to zoom out per unlocked point
@export var zoom_tween_duration: float = 1.0
@export var min_zoom: float = 0.35          # don't zoom out past this

var _wall_container: Node2D
var _walled_segments: Array[int] = []  # index i means the edge point_positions[i] -> point_positions[i+1] is built


func _ready() -> void:
	_generate_points()

	_wall_container = Node2D.new()
	_wall_container.name = "Walls"
	_wall_container.z_index = -1
	add_child(_wall_container)

	_spawn_tower_at(0)
	camera.global_position = center
	camera.zoom = Vector2.ONE

	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.wave_cleared.connect(_on_wave_cleared)


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
	tower.global_position = point_positions[index]
	add_child(tower)
	point_towers[index] = tower

	## New towers start with every upgrade card already picked this run,
	## so a tower built at point 5 isn't weaker than the ones built earlier.
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("register_tower"):
		gm.register_tower(tower)

	tower_built.emit(index, tower)
	return tower


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
