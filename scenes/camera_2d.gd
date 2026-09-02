extends Camera2D

@export var zoom_step: float = 0.1
@export var min_zoom: float = 0.2
@export var max_zoom: float = 3.0
@export var pan_speed: float = 800.0  # pixels/sec via WASD/arrows, scales with zoom

var _dragging := false
var _drag_start_mouse: Vector2
var _drag_start_cam_pos: Vector2


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not _ability_aim_active() and not _ui_blocking():
				_zoom_by(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not _ability_aim_active() and not _ui_blocking():
				_zoom_by(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and _ui_blocking():
				return
			_dragging = event.pressed
			if _dragging:
				_drag_start_mouse = get_viewport().get_mouse_position()
				_drag_start_cam_pos = global_position

	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = (get_viewport().get_mouse_position() - _drag_start_mouse) * zoom.x
		global_position = _drag_start_cam_pos - delta


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1

	if move != Vector2.ZERO:
		global_position += move.normalized() * pan_speed * zoom.x * delta


func _zoom_by(amount: float) -> void:
	var new_zoom: float = clampf(zoom.x + amount, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)


## Volley Shot's rectangle reticle uses the same scroll wheel to rotate
## (see hotbar.gd) - the camera shouldn't also zoom while that's happening.
func _ability_aim_active() -> bool:
	var hotbar: Node = get_tree().get_first_node_in_group("hotbar")
	return hotbar != null and hotbar.has_method("is_ability_armed") and hotbar.is_ability_armed()


## A HUD panel with nothing to scroll doesn't consume the wheel event
## itself, so it fell through to here and zoomed the world camera right
## through the open menu; same guard stops a middle-drag pan starting
## from inside a panel.
func _ui_blocking() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("hud_tabs")
	return hud != null and hud.has_method("is_panel_open_under_mouse") and hud.is_panel_open_under_mouse()
