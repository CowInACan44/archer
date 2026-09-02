extends Node2D

## The goblin's attack_damage and the tower's near-infinite max_health are
## overridden directly on the instanced nodes in main_menu.tscn, so this
## fight just loops forever in the background instead of ever resolving.

const ARROW_SCENE := preload("res://scenes/arrow.tscn")
const MIN_FLIGHT_TIME := 0.2
const MAX_FLIGHT_TIME := 0.45
const FLIGHT_TIME_DISTANCE_REF := 900.0

@onready var tower_decoration: Node = $TowerDecoration
@onready var archer: AnimatedSprite2D = $TowerDecoration/Archer
@onready var fire_point_right: Marker2D = $TowerDecoration/Archer/FirePoint_Right
@onready var fire_point_left: Marker2D = $TowerDecoration/Archer/FirePoint_Left
@onready var camera: Camera2D = $Camera2D
@onready var play_button: BaseButton = $UI/VBox/PlayButton
@onready var quit_button: BaseButton = $UI/VBox/QuitButton


var _mouse_follow_enabled := true


func _ready() -> void:
	_hide_gameplay_only_ui(tower_decoration, "HealthBar")

	for button in [play_button, quit_button]:
		button.pivot_offset = button.size / 2.0

	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


## The archer only has left/right frames (no up/down aim), so "following
## the mouse" means flipping to face whichever side of it the cursor is
## currently on - same flip_h convention _shoot_button() already uses to
## aim at a pressed button.
func _process(_delta: float) -> void:
	if not _mouse_follow_enabled:
		return
	var mouse_pos := get_global_mouse_position()
	archer.flip_h = mouse_pos.x < archer.global_position.x


func _hide_gameplay_only_ui(parent: Node, child_name: String) -> void:
	if parent == null:
		return
	var child: Node = parent.get_node_or_null(child_name)
	if child:
		child.visible = false


func _on_play_pressed() -> void:
	await _shoot_button(play_button)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	await _shoot_button(quit_button)
	get_tree().quit()


## A little visual love for the menu: the archer actually fires an arrow
## at whichever button was pressed before that button's real action
## (change scene / quit) happens, reusing the exact same shoot animation
## and arrow-launch flow tower.gd uses to fire on enemies in-game.
func _shoot_button(button: BaseButton) -> void:
	play_button.disabled = true
	quit_button.disabled = true
	_mouse_follow_enabled = false

	var target_pos := _world_pos_for_control(button)
	var flight_time := _calc_flight_time(fire_point_right.global_position, target_pos)
	var facing_left := target_pos.x < archer.global_position.x
	archer.flip_h = facing_left
	archer.play_shoot()
	await archer.shoot_released

	var fire_point: Marker2D = fire_point_left if facing_left else fire_point_right
	var arrow: Arrow = ARROW_SCENE.instantiate()
	add_child(arrow)
	arrow.flight_time = flight_time
	arrow.launch(fire_point.global_position, target_pos)
	_mouse_follow_enabled = true

	await get_tree().create_timer(flight_time).timeout
	_bounce_button(button)
	await get_tree().create_timer(0.12).timeout


## Screen-space Control position -> the world-space point that currently
## projects onto it, so an arrow (a world-space Area2D) can visually
## "hit" a UI button living in a separate CanvasLayer. The menu's camera
## never moves, but this stays correct even if that ever changes.
func _world_pos_for_control(control: Control) -> Vector2:
	var screen_center: Vector2 = control.get_global_rect().get_center()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return camera.global_position + (screen_center - viewport_size * 0.5) / camera.zoom


func _calc_flight_time(from: Vector2, to: Vector2) -> float:
	var dist := from.distance_to(to)
	return clampf(dist / FLIGHT_TIME_DISTANCE_REF, MIN_FLIGHT_TIME, MAX_FLIGHT_TIME)


func _bounce_button(button: BaseButton) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.12, 1.12), 0.08)
	tween.tween_property(button, "scale", Vector2.ONE, 0.12)
