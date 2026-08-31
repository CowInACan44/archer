@tool
extends Node2D
class_name ArrowField

@export var arrow_texture: Texture2D
@export var max_slots: int = 20
@export var min_radius: float = 35.0
@export var max_radius: float = 70.0
@export var arc_start_degrees: float = 0.0
@export var arc_end_degrees: float = 180.0
@export var rotation_jitter_degrees: float = 20.0
@export var rng_seed: int = 0

## Sprite art points directly right by default, so -90 rotates it to
## point up (planted in the ground). Flip to 90 if it ends up upside down.
@export_range(-180.0, 180.0, 1.0) var base_rotation_offset_degrees: float = -90.0:
	set(value):
		base_rotation_offset_degrees = value
		if Engine.is_editor_hint():
			_build_slots()

signal slots_changed(filled_count: int, max_slots: int)

var _slots: Array[Sprite2D] = []
var _slot_filled: Array[bool] = []


func _ready() -> void:
	_build_slots()


func filled_count() -> int:
	var count := 0
	for filled in _slot_filled:
		if filled:
			count += 1
	return count


func _build_slots() -> void:
	for child in get_children():
		child.queue_free()
	_slots.clear()
	_slot_filled.clear()

	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed

	for i in max_slots:
		var angle_deg: float = rng.randf_range(arc_start_degrees, arc_end_degrees)
		var radius: float = rng.randf_range(min_radius, max_radius)
		var angle_rad := deg_to_rad(angle_deg)
		var pos := Vector2(cos(angle_rad), sin(angle_rad)) * radius

		var arrow := Sprite2D.new()
		arrow.texture = arrow_texture
		arrow.position = pos
		var jitter := deg_to_rad(rng.randf_range(-rotation_jitter_degrees, rotation_jitter_degrees))
		arrow.rotation = deg_to_rad(base_rotation_offset_degrees) + jitter
		add_child(arrow)

		_slots.append(arrow)
		_slot_filled.append(true)


func has_available_slot() -> bool:
	return _slot_filled.has(true)


func consume_one() -> Vector2:
	var filled_indices: Array[int] = []
	for i in _slot_filled.size():
		if _slot_filled[i]:
			filled_indices.append(i)
	if filled_indices.is_empty():
		return global_position

	var idx: int = filled_indices[randi() % filled_indices.size()]
	_slot_filled[idx] = false
	_slots[idx].visible = false
	slots_changed.emit(filled_count(), max_slots)
	return _slots[idx].global_position


func nearest_empty_slot(from_position: Vector2) -> int:
	var best_idx := -1
	var best_dist := INF
	for i in _slot_filled.size():
		if not _slot_filled[i]:
			var d := _slots[i].global_position.distance_to(from_position)
			if d < best_dist:
				best_dist = d
				best_idx = i
	return best_idx


func get_empty_slot_indices() -> Array[int]:
	var result: Array[int] = []
	for i in _slot_filled.size():
		if not _slot_filled[i]:
			result.append(i)
	return result


func fill_slot(idx: int) -> void:
	if idx < 0 or idx >= _slot_filled.size():
		return
	_slot_filled[idx] = true
	_slots[idx].visible = true
	slots_changed.emit(filled_count(), max_slots)


func slot_position(idx: int) -> Vector2:
	if idx < 0 or idx >= _slots.size():
		return global_position
	return _slots[idx].global_position
