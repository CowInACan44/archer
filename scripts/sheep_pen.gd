extends Node2D
class_name SheepPen

## Player-placed home for Sheep captured alive by a Hunter-job pawn (see
## Wildlife.captured / Pawn._on_wildlife_captured) - each live sheep here
## periodically produces Meat on its own, a slow passive trickle instead
## of every hunt only ever paying off once. The "Wooden Fence" texture
## (also used for the kingdom's connecting walls in kingdom_manager.gd,
## where it's genuinely a repeatable 64x64 tile) is actually a single
## pre-drawn small corral - four corner posts, connecting rails, and a
## gate gap - not a tile meant to repeat, so the pen just uses the whole
## image as one sprite instead of cropping/tiling a corner out of it.
const FENCE_TEXTURE := preload("res://tiny/Tiny Swords (Enemy Pack)/Enemy Pack/Enemies/Goblin Raiders/Wooden Fence/Wooden Fence_64x64 tile.png")

## Native size of the fence image is 256x192 - pen_size is the width it's
## scaled to on screen, height following the same ratio.
@export var pen_size: float = 160.0
@export var max_health: int = 40
@export var capacity: int = 6
@export var meat_per_sheep_cycle: int = 2
@export var cycle_time: float = 20.0
@export var hit_flash_duration: float = 0.12
@export var repair_wood_cost: int = 4
@export var repair_heal_amount: int = 12

var sheep_count: int = 0
var current_health: int
var is_destroyed := false

signal health_changed(current: int, max_health: int)
signal pen_destroyed
signal sheep_count_changed(count: int)

@onready var health_bar_fill: ColorRect = $HealthBar/BarFill
@onready var flock_sprite: AnimatedSprite2D = $FlockSprite


func _ready() -> void:
	add_to_group("sheep_pen")
	current_health = max_health
	health_changed.emit(current_health, max_health)
	_build_fence()
	_refresh_flock_visual()

	var timer := Timer.new()
	timer.wait_time = cycle_time
	add_child(timer)
	timer.timeout.connect(_on_production_tick)
	timer.start()


func _build_fence() -> void:
	var fence := Sprite2D.new()
	fence.texture = FENCE_TEXTURE
	var scale_factor: float = pen_size / FENCE_TEXTURE.get_width()
	fence.scale = Vector2(scale_factor, scale_factor)
	add_child(fence)


## Called by a Hunter pawn delivering a live-captured Sheep.
func add_sheep(count: int = 1) -> void:
	sheep_count = mini(sheep_count + count, capacity)
	sheep_count_changed.emit(sheep_count)
	_refresh_flock_visual()


func _refresh_flock_visual() -> void:
	flock_sprite.visible = sheep_count > 0


func _on_production_tick() -> void:
	if sheep_count <= 0 or is_destroyed:
		return
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("add_meat"):
		gm.add_meat(sheep_count * meat_per_sheep_cycle)


func take_damage(amount: int, hit_from: Vector2 = Vector2.ZERO) -> void:
	if is_destroyed:
		return
	current_health -= amount
	health_changed.emit(current_health, max_health)
	health_bar_fill.anchor_right = clampf(float(current_health) / float(max_health), 0.0, 1.0)
	_flash_hit()
	if current_health <= 0:
		_destroy()


func _flash_hit() -> void:
	flock_sprite.modulate = Color(3, 1.2, 1.2)
	var tween := create_tween()
	tween.tween_property(flock_sprite, "modulate", Color(1, 1, 1), hit_flash_duration)


func needs_repair() -> bool:
	return not is_destroyed and current_health < max_health


## Called by a Repair-job pawn (see pawn.gd's Job.REPAIR) once it arrives.
func try_repair() -> bool:
	if not needs_repair():
		return false
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null or not gm.spend_wood(repair_wood_cost):
		return false
	current_health = mini(current_health + repair_heal_amount, max_health)
	health_changed.emit(current_health, max_health)
	health_bar_fill.anchor_right = clampf(float(current_health) / float(max_health), 0.0, 1.0)
	_flash_repair()
	return true


func _flash_repair() -> void:
	flock_sprite.modulate = Color(1.3, 1.6, 1.3)
	var tween := create_tween()
	tween.tween_property(flock_sprite, "modulate", Color(1, 1, 1), hit_flash_duration)


func _destroy() -> void:
	is_destroyed = true
	pen_destroyed.emit()
	queue_free()
