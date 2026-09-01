extends Control
class_name Minimap

## RuneScape-style minimap: dots for towers/houses/enemies scaled down
## from world position around the kingdom's center, a ring marking where
## the main camera is currently looking, and click-to-jump - clicking
## anywhere on the map tweens the main camera there.

## How much world-space radius the map widget covers.
@export var world_radius: float = 900.0
@export var jump_duration: float = 0.4

var _map_center: Vector2
var _map_radius: float


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _get_kingdom_center() -> Vector2:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	return km.to_global(km.center) if km else Vector2.ZERO


func _world_to_map(world_pos: Vector2, kingdom_center: Vector2) -> Vector2:
	var offset: Vector2 = (world_pos - kingdom_center) * (_map_radius / world_radius)
	if offset.length() > _map_radius:
		offset = offset.normalized() * _map_radius
	return _map_center + offset


func _draw() -> void:
	_map_center = size / 2.0
	_map_radius = minf(size.x, size.y) / 2.0 - 6.0
	var kingdom_center: Vector2 = _get_kingdom_center()

	for t in get_tree().get_nodes_in_group("tower"):
		if not is_instance_valid(t):
			continue
		var destroyed: bool = "is_destroyed" in t and t.is_destroyed
		var col: Color = Color(0.5, 0.5, 0.55) if destroyed else Color(0.95, 0.8, 0.25)
		draw_circle(_world_to_map(t.global_position, kingdom_center), 4.0, col)

	for h in get_tree().get_nodes_in_group("house"):
		if is_instance_valid(h):
			draw_circle(_world_to_map(h.global_position, kingdom_center), 3.0, Color(0.45, 0.8, 0.45))

	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			draw_circle(_world_to_map(e.global_position, kingdom_center), 2.0, Color(0.85, 0.2, 0.2))

	var cam := get_viewport().get_camera_2d()
	if cam:
		var p: Vector2 = _world_to_map(cam.get_screen_center_position(), kingdom_center)
		draw_arc(p, 7.0, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_jump_camera_to(event.position)


func _jump_camera_to(local_click: Vector2) -> void:
	var kingdom_center: Vector2 = _get_kingdom_center()
	var offset: Vector2 = local_click - _map_center
	var world_offset: Vector2 = offset * (world_radius / _map_radius)
	var target: Vector2 = kingdom_center + world_offset

	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var tween := create_tween()
	tween.tween_property(cam, "global_position", target, jump_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
