extends Node2D
class_name KingdomManager

const TOWER_SCENE := preload("res://scenes/tower.tscn")
const POINT_COUNT := 8

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


func _ready() -> void:
	_generate_points()
	_spawn_tower_at(0)
	camera.global_position = center
	camera.zoom = Vector2.ONE

	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.wave_cleared.connect(_on_wave_cleared)


func _on_wave_cleared(wave_number: int) -> void:
	if wave_number == unlock_at_wave:
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
			return i
	return -1  # all points already unlocked


func can_build_at(index: int) -> bool:
	return index in unlocked_indices and point_towers[index] == null


func _spawn_tower_at(index: int) -> Node:
	var tower := TOWER_SCENE.instantiate()
	tower.global_position = point_positions[index]
	add_child(tower)
	point_towers[index] = tower
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
