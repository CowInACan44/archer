extends Node2D
class_name AbilitySystem

## Player-cast, mouse-targeted abilities (see Hotbar) - separate from the
## passive per-tower incrementals in GameManager. Each ability is unlocked
## once (wood cost) then has two upgrade branches bought repeatedly:
## "power" (more damage/more hits) and "fire" (adds a burn-over-time
## elemental effect). Built as one small, self-contained system now so
## more abilities and more elemental branches (poison, lightning, chain
## lightning, ...) can be added to ABILITY_DEFS later without redesigning
## the plumbing - see DESIGN.md.

const POOF_SCENE := preload("res://scenes/poof.tscn")

const ABILITY_DEFS := {
	"volley_shot": {
		"display_name": "Volley Shot",
		"unlock_cost": 40,
		"base_cooldown": 6.0,
		"base_damage": 8,
		"base_hits": 4,
		## Line-shaped instead of Arrow Storm's circle - a rotated rectangle
		## the player aims with the scroll wheel (see hotbar.gd), so it can
		## be lined up along a spread-out row of enemies instead of only
		## ever catching whatever's inside a small fixed circle.
		"rect_length": 220.0,
		"rect_width": 70.0,
	},
	"arrow_storm": {
		"display_name": "Arrow Storm",
		"unlock_cost": 80,
		"base_cooldown": 14.0,
		"base_damage": 6,
		"base_hits": 8,
		"radius": 140.0,
	},
}

const POWER_BASE_COST := 20
const FIRE_BASE_COST := 30
const COST_GROWTH := 1.4

const POWER_DAMAGE_STEP := 3
const POWER_HITS_STEP := 1
const FIRE_DPS_PER_LEVEL := 2
const FIRE_DURATION := 3.0

signal ability_unlocked(id: String)
signal ability_upgraded(id: String, branch: String, level: int)
signal ability_cast(id: String, target: Vector2, aim_rotation: float)
signal cooldown_started(id: String, duration: float)

var unlocked: Dictionary = {}
var power_level: Dictionary = {}
var fire_level: Dictionary = {}
var _cooldown_timers: Dictionary = {}


func _ready() -> void:
	add_to_group("ability_system")
	for id in ABILITY_DEFS:
		unlocked[id] = false
		power_level[id] = 0
		fire_level[id] = 0


func is_unlocked(id: String) -> bool:
	return unlocked.get(id, false)


func unlock_cost(id: String) -> int:
	return ABILITY_DEFS[id].unlock_cost


func unlock(id: String) -> bool:
	if is_unlocked(id):
		return false
	if not _spend(unlock_cost(id)):
		return false
	unlocked[id] = true
	ability_unlocked.emit(id)
	return true


func power_cost(id: String) -> int:
	return int(round(POWER_BASE_COST * pow(COST_GROWTH, power_level[id])))


func fire_cost(id: String) -> int:
	return int(round(FIRE_BASE_COST * pow(COST_GROWTH, fire_level[id])))


func upgrade_power(id: String) -> bool:
	if not is_unlocked(id) or not _spend(power_cost(id)):
		return false
	power_level[id] += 1
	ability_upgraded.emit(id, "power", power_level[id])
	return true


func upgrade_fire(id: String) -> bool:
	if not is_unlocked(id) or not _spend(fire_cost(id)):
		return false
	fire_level[id] += 1
	ability_upgraded.emit(id, "fire", fire_level[id])
	return true


func is_on_cooldown(id: String) -> bool:
	return _cooldown_timers.has(id) and _cooldown_timers[id].time_left > 0.0


func cast(id: String, target: Vector2, aim_rotation: float = 0.0) -> bool:
	if not is_unlocked(id) or is_on_cooldown(id):
		return false
	var def: Dictionary = ABILITY_DEFS[id]
	var damage: int = def.base_damage + power_level[id] * POWER_DAMAGE_STEP
	var hits: int = def.base_hits + power_level[id] * POWER_HITS_STEP
	var burning: bool = fire_level[id] > 0
	var burn_dps: int = fire_level[id] * FIRE_DPS_PER_LEVEL

	## Volley Shot is a player-rotated line, not a circle, so it needs its
	## own rectangular hit-test lined up with whatever angle the reticle
	## was aimed at - a circular check here would silently miss enemies
	## the rectangle reticle visibly covers.
	var enemies: Array
	if id == "volley_shot":
		enemies = _enemies_within_rect(target, def.rect_length, def.rect_width, aim_rotation)
	else:
		enemies = _enemies_within(target, def.radius)
	enemies.shuffle()
	for i in mini(hits, enemies.size()):
		var enemy: Node2D = enemies[i]
		if not is_instance_valid(enemy):
			continue
		if burning and enemy.has_method("apply_burn"):
			enemy.apply_burn(burn_dps, FIRE_DURATION)
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, target)

	_spawn_impact_vfx(id, target, def, aim_rotation)
	_start_cooldown(id, def.base_cooldown)
	ability_cast.emit(id, target, aim_rotation)
	return true


func _enemies_within(center: Vector2, radius: float) -> Array:
	var result: Array = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if center.distance_to(enemy.global_position) <= radius:
			result.append(enemy)
	return result


## Rectangle hit-test in the reticle's own rotated space - transform each
## enemy into that space instead of rotating the rectangle itself.
func _enemies_within_rect(center: Vector2, length: float, width: float, rot: float) -> Array:
	var result: Array = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var local: Vector2 = (enemy.global_position - center).rotated(-rot)
		if absf(local.x) <= length * 0.5 and absf(local.y) <= width * 0.5:
			result.append(enemy)
	return result


## Each ability gets a VFX that actually reads as what it is, instead of
## both just dropping the same smoke poof on the target - Volley Shot is a
## line of arrows flying in across the rectangle the player aimed, Arrow
## Storm is a circular rain of arrows falling across the whole blast radius.
func _spawn_impact_vfx(id: String, pos: Vector2, def: Dictionary, aim_rotation: float) -> void:
	match id:
		"volley_shot":
			_spawn_volley_vfx(pos, aim_rotation, def.rect_length, def.rect_width)
		"arrow_storm":
			_spawn_storm_vfx(pos, def.radius)
		_:
			var poof := POOF_SCENE.instantiate()
			get_tree().current_scene.add_child(poof)
			poof.global_position = pos


const ARROW_TEXTURE := preload("res://tiny/Tiny Swords (Free Pack)/Units/Blue Units/Archer/Arrow.png")
const VOLLEY_ARROW_COUNT := 5
const VOLLEY_FLIGHT_DISTANCE := 140.0
const STORM_ARROW_COUNT := 10
const STORM_FALL_HEIGHT := 160.0


## Arrows spread along the rectangle's length (its aimed long axis) and
## fly in together from one side along its width axis, so the volley
## reads as a single line of arrows sweeping across the whole rectangle
## instead of converging on one point.
func _spawn_volley_vfx(pos: Vector2, rot: float, length: float, width: float) -> void:
	var length_dir := Vector2.RIGHT.rotated(rot)
	var width_dir := length_dir.orthogonal()
	var side: float = 1.0 if randf() < 0.5 else -1.0
	for i in VOLLEY_ARROW_COUNT:
		var offset: float = (i - (VOLLEY_ARROW_COUNT - 1) / 2.0) * (length / VOLLEY_ARROW_COUNT)
		var land_pos: Vector2 = pos + length_dir * offset
		var start_pos: Vector2 = land_pos + width_dir * side * (VOLLEY_FLIGHT_DISTANCE + width * 0.5)
		var arrow := Sprite2D.new()
		arrow.texture = ARROW_TEXTURE
		arrow.rotation = (land_pos - start_pos).angle()
		arrow.global_position = start_pos
		get_tree().current_scene.add_child(arrow)
		var tween := arrow.create_tween()
		tween.tween_interval(i * 0.03)
		tween.tween_property(arrow, "global_position", land_pos, 0.12)
		tween.tween_interval(0.6)
		tween.tween_property(arrow, "modulate:a", 0.0, 0.2)
		tween.tween_callback(arrow.queue_free)


func _spawn_storm_vfx(pos: Vector2, radius: float) -> void:
	for i in STORM_ARROW_COUNT:
		var r: float = radius * sqrt(randf())
		var angle := randf() * TAU
		var land_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * r
		var start_pos: Vector2 = land_pos - Vector2(0, STORM_FALL_HEIGHT)
		var arrow := Sprite2D.new()
		arrow.texture = ARROW_TEXTURE
		arrow.rotation = deg_to_rad(90.0)
		arrow.global_position = start_pos
		get_tree().current_scene.add_child(arrow)
		var tween := arrow.create_tween()
		tween.tween_interval(randf() * 0.5)
		tween.tween_property(arrow, "global_position", land_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_interval(0.5)
		tween.tween_property(arrow, "modulate:a", 0.0, 0.2)
		tween.tween_callback(arrow.queue_free)


func _start_cooldown(id: String, duration: float) -> void:
	if not _cooldown_timers.has(id):
		var t := Timer.new()
		t.one_shot = true
		add_child(t)
		_cooldown_timers[id] = t
	var timer: Timer = _cooldown_timers[id]
	timer.wait_time = duration
	timer.start()
	cooldown_started.emit(id, duration)


func _spend(amount: int) -> bool:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	return gm != null and gm.spend_wood(amount)
