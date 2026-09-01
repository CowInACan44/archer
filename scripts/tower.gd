extends StaticBody2D
class_name Tower

const ARROW_SCENE := preload("res://scenes/arrow.tscn")

@export var fire_rate: float = 1.2
@export var detection_range: float = 400.0
@export var max_health: int = 140

@export var destroyed_texture: Texture2D

@export var hit_flash_duration: float = 0.12
@export var bounce_strength: float = 0.15
@export var bounce_duration: float = 0.2

@export var repair_wood_cost: int = 4
@export var repair_heal_amount: int = 30
@export var hammer_cursor: Texture2D
@export var hammer_cursor_hotspot: Vector2 = Vector2(4, 4)

@export var health_upgrade_gold_cost: int = 15
@export var health_upgrade_wood_cost: int = 10
@export var health_upgrade_amount: int = 25

@export var rebuild_wood_cost: int = 30
@export var rebuild_gold_cost: int = 20

const MIN_FLIGHT_TIME := 0.25
const MAX_FLIGHT_TIME := 0.7
const FLIGHT_TIME_DISTANCE_REF := 400.0

@onready var archer: AnimatedSprite2D = $Archer
@onready var fire_point_right: Marker2D = $Archer/FirePoint_Right
@onready var fire_point_left: Marker2D = $Archer/FirePoint_Left
@onready var fire_timer: Timer = $FireTimer
@onready var tower_sprite: Sprite2D = $Sprite2D
@onready var health_bar: Range = $HealthBar
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

signal tower_destroyed
signal health_upgraded(new_max_health: int, upgrade_count: int)

var current_health: int
var current_target: Node2D = null
var is_destroyed := false

## Arrows are unlimited - the archer never runs out, so power comes purely
## from these upgrades (damage/fire rate/volley) instead of an ammo count.
var arrow_damage_bonus: int = 0
var volley_enabled: bool = false
var volley_interval: float = 8.0
var _volley_timer: Timer

var health_upgrade_count: int = 0
var _original_texture: Texture2D


func _ready() -> void:
	current_health = max_health
	add_to_group("tower")
	fire_timer.wait_time = fire_rate
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	fire_timer.start()

	_volley_timer = Timer.new()
	add_child(_volley_timer)
	_volley_timer.timeout.connect(_on_volley_timer_timeout)

	health_bar.max_value = max_health
	health_bar.value = current_health

	_original_texture = tower_sprite.texture


## Updates both the exported rate and the running timer - changing
## fire_rate alone doesn't affect fire_timer once it's already ticking.
func set_fire_rate(new_rate: float) -> void:
	fire_rate = new_rate
	fire_timer.wait_time = fire_rate


## Called by kingdom_manager.gd once every one of the 8 octagon points has
## a standing tower - swaps in a grander stone-tower base texture as the
## visual "the kingdom is fully fortified now" payoff, purely cosmetic.
func set_fortified(tex: Texture2D) -> void:
	tower_sprite.texture = tex


func _process(_delta: float) -> void:
	if is_destroyed:
		return
	current_target = _find_nearest_enemy()

	if volley_enabled and _volley_timer.is_stopped():
		_volley_timer.wait_time = volley_interval
		_volley_timer.start()


func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := detection_range
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest


func _on_fire_timer_timeout() -> void:
	if is_destroyed:
		return
	if current_target == null or not is_instance_valid(current_target):
		return
	_fire_at(current_target)


func _fire_at(target: Node2D) -> void:
	var flight_time := _calc_flight_time(fire_point_right.global_position, target.global_position)
	var predicted_pos := _predict_target_position(target, flight_time)
	var facing_left := predicted_pos.x < global_position.x
	archer.flip_h = facing_left
	archer.play_shoot()

	await archer.shoot_released
	if is_destroyed:
		return

	var fire_point: Marker2D = fire_point_left if facing_left else fire_point_right
	var arrow: Arrow = ARROW_SCENE.instantiate()
	get_tree().current_scene.add_child(arrow)
	arrow.flight_time = flight_time
	arrow.damage += arrow_damage_bonus
	arrow.launch(fire_point.global_position, predicted_pos)


func _on_volley_timer_timeout() -> void:
	if is_destroyed:
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) > detection_range:
			continue
		_fire_at(enemy)


func _calc_flight_time(from: Vector2, to: Vector2) -> float:
	var dist := from.distance_to(to)
	var ratio := clampf(dist / FLIGHT_TIME_DISTANCE_REF, 0.0, 1.0)
	return lerpf(MIN_FLIGHT_TIME, MAX_FLIGHT_TIME, ratio)


func _predict_target_position(target: Node2D, flight_time: float) -> Vector2:
	var target_velocity := Vector2.ZERO
	if target is CharacterBody2D:
		target_velocity = target.velocity
	return target.global_position + target_velocity * flight_time


func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	current_health = max(current_health - amount, 0)
	health_bar.value = current_health
	_flash_hit()
	_bounce()
	if current_health <= 0:
		_destroy()


func _flash_hit() -> void:
	tower_sprite.modulate = Color(3, 3, 3)
	var tween := create_tween()
	tween.tween_property(tower_sprite, "modulate", Color(1, 1, 1), hit_flash_duration)


func _bounce() -> void:
	tower_sprite.scale = Vector2(1.0 + bounce_strength, 1.0 - bounce_strength)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(tower_sprite, "scale", Vector2.ONE, bounce_duration)


func needs_repair() -> bool:
	return not is_destroyed and current_health < max_health


## Whether a world-space point (e.g. the mouse) is over this tower's
## collision footprint. Used by KingdomManager's single, centralized
## repair-cursor scan instead of each tower fighting over the shared OS
## cursor via its own mouse_entered/exited signals - with several towers
## on screen, two towers' signals could race and leave the wrong cursor
## showing depending on scene-tree processing order.
func contains_point(point: Vector2) -> bool:
	if collision_shape == null or collision_shape.shape == null:
		return false
	var shape: RectangleShape2D = collision_shape.shape
	var center: Vector2 = global_position + collision_shape.position
	var half: Vector2 = shape.size / 2.0
	var local: Vector2 = point - center
	return absf(local.x) <= half.x and absf(local.y) <= half.y


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not contains_point(get_global_mouse_position()):
		return
	if is_destroyed:
		try_rebuild()
	else:
		try_repair()


func try_repair() -> void:
	if not needs_repair():
		return
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null or not gm.has_method("spend_wood"):
		return
	if gm.spend_wood(repair_wood_cost):
		current_health = min(current_health + repair_heal_amount, max_health)
		health_bar.value = current_health
		_bounce()


func can_afford_health_upgrade() -> bool:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return false
	return gm.gold >= health_upgrade_gold_cost and gm.wood >= health_upgrade_wood_cost


func try_upgrade_health() -> bool:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return false
	if gm.gold < health_upgrade_gold_cost or gm.wood < health_upgrade_wood_cost:
		return false

	gm.gold -= health_upgrade_gold_cost
	gm.gold_changed.emit(gm.gold)
	gm.wood -= health_upgrade_wood_cost
	gm.wood_changed.emit(gm.wood)

	max_health += health_upgrade_amount
	current_health += health_upgrade_amount
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_upgrade_count += 1

	health_upgraded.emit(max_health, health_upgrade_count)
	return true


func _destroy() -> void:
	is_destroyed = true
	fire_timer.stop()

	if tower_sprite and destroyed_texture:
		tower_sprite.texture = destroyed_texture

	archer.poof()

	tower_destroyed.emit()


func try_rebuild() -> bool:
	if not is_destroyed:
		return false
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return false
	if gm.gold < rebuild_gold_cost or gm.wood < rebuild_wood_cost:
		return false
	gm.spend_gold(rebuild_gold_cost)
	gm.spend_wood(rebuild_wood_cost)

	is_destroyed = false
	current_health = max_health
	health_bar.value = current_health
	if tower_sprite and _original_texture:
		tower_sprite.texture = _original_texture
	archer.visible = true
	fire_timer.start()
	_bounce()
	return true
