extends Control
class_name Minimap

## RuneScape-style circular minimap: a SubViewport camera shares the main
## World2D so it renders the actual live terrain/trees/towers/enemies
## instead of hand-drawn stand-in dots, cropped into a circle via shader
## (see circular_mask.gdshader). Click anywhere on it to jump the main
## camera there.

@export var world_diameter: float = 1900.0
@export var jump_duration: float = 0.4

@onready var sub_viewport: SubViewport = $SubViewport
@onready var mini_camera: Camera2D = $SubViewport/MiniCamera
@onready var view_rect: TextureRect = $ViewRect


func _ready() -> void:
	sub_viewport.world_2d = get_viewport().world_2d
	view_rect.texture = sub_viewport.get_texture()
	mini_camera.make_current()
	set_process(true)


func _process(_delta: float) -> void:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	mini_camera.global_position = km.to_global(km.center) if km else Vector2.ZERO

	var vp_size: Vector2 = sub_viewport.size
	var zoom_value: float = minf(vp_size.x, vp_size.y) / world_diameter
	mini_camera.zoom = Vector2(zoom_value, zoom_value)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	## The Control itself is a square, but only the inscribed circle is
	## actually visible (see circular_mask.gdshader) - without this check
	## clicking a corner outside the drawn circle still registered and
	## jumped the camera to whatever far-flung point that corner mapped to.
	var map_center: Vector2 = size / 2.0
	var click_radius: float = minf(size.x, size.y) / 2.0
	if event.position.distance_to(map_center) > click_radius:
		return
	_jump_camera_to(event.position)


func _jump_camera_to(local_click: Vector2) -> void:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	var kingdom_center: Vector2 = km.to_global(km.center) if km else Vector2.ZERO
	var map_center: Vector2 = size / 2.0
	var offset: Vector2 = local_click - map_center
	var world_offset: Vector2 = offset * (world_diameter / minf(size.x, size.y))
	var target: Vector2 = kingdom_center + world_offset

	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var tween := create_tween()
	tween.tween_property(cam, "global_position", target, jump_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
