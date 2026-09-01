extends CharacterBody2D
class_name Enemy

@export var move_speed: float = 60.0
@export var attack_range: float = 100.0
@export var attack_damage: int = 6
@export var attack_interval: float = 1.3
@export var max_health: int = 30

@export var knockback_strength: float = 80.0
@export var hit_flash_duration: float = 0.12

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

## Set true by EnemySpawner._spawn_boss() on horde nights - lets a UI widget
## find the current boss (group "boss") and show a dedicated health bar
## instead of the normal per-enemy feedback.
@export var is_boss: bool = false

signal attack_hit_frame_reached
signal health_changed(current: int, max: int)
signal died

@onready var sprite: AnimatedSprite2D = $Spearman
@onready var attack_timer: Timer = $AttackTimer

var current_health: int
var target: Node2D = null
var _current_attack_anim: String = ""

## Burn-over-time, applied by the Volley Shot / Arrow Storm abilities'
## fire upgrade branch (see ability_system.gd). Both timers are children
## of this enemy so they're freed automatically with it - no dangling
## external timer to guard against after death.
var _burn_dps: int = 0
var _burn_tick_timer: Timer
var _burn_duration_timer: Timer
var _base_modulate: Color = Color(1, 1, 1)


func _ready() -> void:
	current_health = max_health
	add_to_group("enemy")
	if is_boss:
		add_to_group("boss")
	attack_timer.wait_time = attack_interval
	attack_timer.timeout.connect(_try_attack)
	attack_timer.start()
	sprite.play("idle")
	sprite.frame_changed.connect(_on_frame_changed)

	_burn_tick_timer = Timer.new()
	_burn_tick_timer.wait_time = 1.0
	add_child(_burn_tick_timer)
	_burn_tick_timer.timeout.connect(_on_burn_tick)

	_burn_duration_timer = Timer.new()
	_burn_duration_timer.one_shot = true
	add_child(_burn_duration_timer)
	_burn_duration_timer.timeout.connect(_clear_burn)

	target = _find_nearest_target()
	health_changed.emit(current_health, max_health)


## Towers and houses are both fair game - previously only towers were,
## which let a horde walk straight past an undefended house without ever
## touching it.
func _find_nearest_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for group in ["tower", "house"]:
		for t in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(t) or ("is_destroyed" in t and t.is_destroyed):
				continue
			var dist := global_position.distance_to(t.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = t
	return nearest


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target) or _target_is_destroyed():
		target = _find_nearest_target()
		if target == null:
			velocity = Vector2.ZERO
			move_and_slide()
			_play_idle_if_needed()
			return

	var to_target := target.global_position - global_position
	if to_target.length() > attack_range:
		velocity = velocity.lerp(to_target.normalized() * move_speed + _separation_force(), 0.3)
		sprite.flip_h = to_target.x < 0
		move_and_slide()

		if velocity.length() < stuck_speed_threshold:
			_play_idle_if_needed()
		elif sprite.animation != "run":
			sprite.play("run")
	else:
		## Still nudged apart even once in range - otherwise every enemy
		## converges to the same attack_range ring around the target and
		## visibly stacks on top of each other instead of surrounding it.
		velocity = velocity.lerp(_separation_force(), 0.3)
		move_and_slide()
		if _current_attack_anim == "":
			_play_idle_if_needed()


const SEPARATION_RADIUS := 44.0
const SEPARATION_STRENGTH := 70.0


func _separation_force() -> Vector2:
	var force := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var offset: Vector2 = global_position - other.global_position
		var dist: float = offset.length()
		if dist > 0.001 and dist < SEPARATION_RADIUS:
			force += offset.normalized() * ((SEPARATION_RADIUS - dist) / SEPARATION_RADIUS)
	return force * SEPARATION_STRENGTH


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
		target = _find_nearest_target()
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
		target = _find_nearest_target()
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return

	if target.has_method("take_damage"):
		target.take_damage(attack_damage)


func take_damage(amount: int, hit_from: Vector2 = Vector2.ZERO) -> void:
	current_health -= amount
	health_changed.emit(current_health, max_health)
	_flash_hit()
	if hit_from != Vector2.ZERO:
		var knock_dir := (global_position - hit_from).normalized()
		velocity += knock_dir * knockback_strength
	if current_health <= 0:
		_die()


func _flash_hit() -> void:
	sprite.modulate = Color(3, 3, 3)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", _base_modulate, hit_flash_duration)


## Burn-over-time from the Volley Shot / Arrow Storm abilities' fire
## upgrade branch (see ability_system.gd).
func apply_burn(dps: int, duration: float) -> void:
	_burn_dps = maxi(_burn_dps, dps)
	_burn_tick_timer.start()
	_burn_duration_timer.wait_time = duration
	_burn_duration_timer.start()
	_base_modulate = Color(1.0, 0.55, 0.3)
	sprite.modulate = _base_modulate


func _on_burn_tick() -> void:
	if current_health <= 0:
		return
	take_damage(_burn_dps)


func _clear_burn() -> void:
	_burn_dps = 0
	_burn_tick_timer.stop()
	_base_modulate = Color(1, 1, 1)
	sprite.modulate = _base_modulate


func _die() -> void:
	died.emit()
	var death_pos := global_position
	call_deferred("_do_death_effects", death_pos)
	queue_free()


func _do_death_effects(death_pos: Vector2) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return

	if gold_pickup_scene:
		var gold_mult: float = gm.gold_drop_chance_mult if "gold_drop_chance_mult" in gm else 1.0
		var gold_chance: float = gold_drop_chance * gm.luck * gold_mult
		if randf() < gold_chance:
			var gold_drop := gold_pickup_scene.instantiate()
			if "amount" in gold_drop and "gold_drop_amount_bonus" in gm:
				gold_drop.amount += gm.gold_drop_amount_bonus
			get_tree().current_scene.add_child(gold_drop)
			gold_drop.global_position = death_pos

	if wood_pickup_scene:
		var wood_mult: float = gm.wood_drop_chance_mult if "wood_drop_chance_mult" in gm else 1.0
		var wood_chance: float = wood_drop_chance * gm.luck * wood_mult
		if randf() < wood_chance:
			var wood_drop := wood_pickup_scene.instantiate()
			if "amount" in wood_drop and "wood_drop_amount_bonus" in gm:
				wood_drop.amount += gm.wood_drop_amount_bonus
			get_tree().current_scene.add_child(wood_drop)
			wood_drop.global_position = death_pos
