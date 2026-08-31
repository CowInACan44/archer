extends CharacterBody2D
class_name Enemy

@export var move_speed: float = 60.0
@export var attack_range: float = 100.0
@export var attack_damage: int = 8
@export var attack_interval: float = 1.0
@export var max_health: int = 30

@export var knockback_strength: float = 80.0
@export var hit_flash_duration: float = 0.12
@export var stuck_arrow_scale: float = 1.0

@export var gold_drop_chance: float = 0.6
@export var gold_pickup_scene: PackedScene
@export var wood_drop_chance: float = 0.5
@export var wood_pickup_scene: PackedScene
@export var attack_1_release_frame: int = 3
@export var attack_2_release_frame: int = 4

## Below this actual post-collision speed, treat the enemy as blocked
## by something in front of it (usually another enemy queued at the
## tower) rather than genuinely moving - so it idles instead of
## playing "run" while visually stuck in place.
@export var stuck_speed_threshold: float = 10.0

signal attack_hit_frame_reached

@onready var sprite: AnimatedSprite2D = $Spearman
@onready var attack_timer: Timer = $AttackTimer

var current_health: int
var target: Node2D = null
var stuck_arrows: Array[Node2D] = []
var _current_attack_anim: String = ""


func _ready() -> void:
	current_health = max_health
	add_to_group("enemy")
	attack_timer.wait_time = attack_interval
	attack_timer.timeout.connect(_try_attack)
	attack_timer.start()
	sprite.play("idle")
	sprite.frame_changed.connect(_on_frame_changed)

	target = _find_nearest_tower()


func _find_nearest_tower() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for t in get_tree().get_nodes_in_group("tower"):
		if not is_instance_valid(t) or ("is_destroyed" in t and t.is_destroyed):
			continue
		var dist := global_position.distance_to(t.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = t
	return nearest


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target) or _target_is_destroyed():
		target = _find_nearest_tower()
		if target == null:
			velocity = Vector2.ZERO
			move_and_slide()
			_play_idle_if_needed()
			return

	var to_target := target.global_position - global_position
	if to_target.length() > attack_range:
		velocity = velocity.lerp(to_target.normalized() * move_speed, 0.3)
		sprite.flip_h = to_target.x < 0
		move_and_slide()

		if velocity.length() < stuck_speed_threshold:
			_play_idle_if_needed()
		elif sprite.animation != "run":
			sprite.play("run")
	else:
		velocity = velocity.lerp(Vector2.ZERO, 0.3)
		move_and_slide()
		if _current_attack_anim == "":
			_play_idle_if_needed()


func _play_idle_if_needed() -> void:
	if sprite.animation != "idle" and _current_attack_anim == "":
		sprite.play("idle")


func _target_is_destroyed() -> bool:
	if target == null:
		return false
	return "is_destroyed" in target and target.is_destroyed


func _on_frame_changed() -> void:
	if _current_attack_anim == "":
		return
	var release_frame: int = attack_1_release_frame if _current_attack_anim == "attack_1" else attack_2_release_frame
	if sprite.animation == _current_attack_anim and sprite.frame == release_frame:
		attack_hit_frame_reached.emit()


func _try_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if _target_is_destroyed():
		target = _find_nearest_tower()
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return

	_current_attack_anim = "attack_1" if randi() % 2 == 0 else "attack_2"
	sprite.play(_current_attack_anim)

	await attack_hit_frame_reached
	_current_attack_anim = ""

	if not is_instance_valid(target):
		return
	if _target_is_destroyed():
		target = _find_nearest_tower()
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return

	if target.has_method("take_damage"):
		target.take_damage(attack_damage)


func take_damage(amount: int, hit_from: Vector2 = Vector2.ZERO) -> void:
	current_health -= amount
	_flash_hit()
	if hit_from != Vector2.ZERO:
		var knock_dir := (global_position - hit_from).normalized()
		velocity += knock_dir * knockback_strength
	if current_health <= 0:
		_die()


func _flash_hit() -> void:
	sprite.modulate = Color(3, 3, 3)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1), hit_flash_duration)


func stick_arrow(local_pos: Vector2, arrow_rotation: float, texture: Texture2D) -> void:
	if texture == null:
		return
	var stuck := Sprite2D.new()
	stuck.texture = texture
	stuck.position = local_pos
	stuck.rotation = arrow_rotation
	stuck.scale = Vector2(stuck_arrow_scale, stuck_arrow_scale)
	add_child(stuck)
	stuck_arrows.append(stuck)


func _die() -> void:
	var death_pos := global_position
	call_deferred("_do_death_effects", death_pos)
	queue_free()


func _do_death_effects(death_pos: Vector2) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return

	if gold_pickup_scene:
		var gold_chance: float = gold_drop_chance * gm.luck
		if randf() < gold_chance:
			var gold_drop := gold_pickup_scene.instantiate()
			get_tree().current_scene.add_child(gold_drop)
			gold_drop.global_position = death_pos

	if wood_pickup_scene:
		var wood_chance: float = wood_drop_chance * gm.luck
		if randf() < wood_chance:
			var wood_drop := wood_pickup_scene.instantiate()
			get_tree().current_scene.add_child(wood_drop)
			wood_drop.global_position = death_pos
