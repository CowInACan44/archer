extends CharacterBody2D
class_name Wildlife

## Neutral, non-aggressive creature wandering the world - unlike anything
## in Enemy.gd's roster, this never targets or attacks the kingdom. Only
## a Hunter-job pawn (see pawn.gd's Job.HUNTER) goes looking for these -
## everyone else just leaves them alone. Bears always drop Meat on death;
## Sheep have a chance per hit to be captured alive instead, so a Hunter
## can haul them back to a Sheep Pen for breeding rather than only ever
## getting a one-time meat drop.

enum Kind { SHEEP, BEAR }

const MEAT_PICKUP_SCENE := preload("res://scenes/MeatPickup.tscn")
const POOF_SCENE := preload("res://scenes/poof.tscn")

@export var kind: Kind = Kind.SHEEP
@export var max_health: int = 12
@export var wander_radius: float = 90.0
@export var wander_speed: float = 24.0
@export var meat_amount: int = 6
## Sheep-only: chance a killing blow captures it alive instead of it
## dying outright. Ignored for Bear, which always just dies for Meat.
@export var capture_chance: float = 0.5

@onready var sprite: AnimatedSprite2D = $Sprite

var current_health: int
var claimed_by: Node = null
var is_dead := false
var _home_position: Vector2
var _wander_target: Vector2
var _idle_time := 0.0

signal died
signal captured


func _ready() -> void:
	add_to_group("wildlife")
	current_health = max_health
	_home_position = global_position
	_wander_target = global_position
	_pick_wander_target()


func is_available() -> bool:
	return not is_dead and claimed_by == null


func claim(pawn: Node) -> bool:
	if not is_available():
		return false
	claimed_by = pawn
	return true


func release(pawn: Node) -> void:
	if claimed_by == pawn:
		claimed_by = null


func take_damage(amount: int, hit_from: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return
	current_health -= amount
	sprite.modulate = Color(3, 1, 1)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.15)
	if current_health <= 0:
		_resolve_death()


func _resolve_death() -> void:
	is_dead = true
	if kind == Kind.SHEEP and randf() < capture_chance:
		captured.emit()
		queue_free()
		return
	var poof := POOF_SCENE.instantiate()
	get_tree().current_scene.add_child(poof)
	poof.global_position = global_position
	var meat := MEAT_PICKUP_SCENE.instantiate()
	meat.amount = meat_amount
	get_tree().current_scene.add_child(meat)
	meat.global_position = global_position
	died.emit()
	queue_free()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	## Held still by a Hunter pawn currently fighting it - no independent
	## wandering while claimed, so it doesn't drag its attacker around.
	if claimed_by != null:
		velocity = Vector2.ZERO
		move_and_slide()
		_play_anim("idle")
		return

	if global_position.distance_to(_wander_target) < 6.0:
		velocity = Vector2.ZERO
		_idle_time -= delta
		if _idle_time <= 0.0:
			_pick_wander_target()
	else:
		var to_target := _wander_target - global_position
		velocity = to_target.normalized() * wander_speed
		sprite.flip_h = to_target.x < 0
	move_and_slide()
	_play_anim("run" if velocity.length() > 1.0 else "idle")


func _play_anim(anim: String) -> void:
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)


func _pick_wander_target() -> void:
	_idle_time = randf_range(1.5, 4.0)
	var offset := Vector2(randf_range(-wander_radius, wander_radius), randf_range(-wander_radius, wander_radius))
	_wander_target = _home_position + offset
