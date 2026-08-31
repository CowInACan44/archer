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
		"radius": 90.0,
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
signal ability_cast(id: String, target: Vector2)
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


func cast(id: String, target: Vector2) -> bool:
	if not is_unlocked(id) or is_on_cooldown(id):
		return false
	var def: Dictionary = ABILITY_DEFS[id]
	var damage: int = def.base_damage + power_level[id] * POWER_DAMAGE_STEP
	var hits: int = def.base_hits + power_level[id] * POWER_HITS_STEP
	var burning: bool = fire_level[id] > 0
	var burn_dps: int = fire_level[id] * FIRE_DPS_PER_LEVEL

	var enemies := _enemies_within(target, def.radius)
	enemies.shuffle()
	for i in mini(hits, enemies.size()):
		var enemy: Node2D = enemies[i]
		if not is_instance_valid(enemy):
			continue
		if burning and enemy.has_method("apply_burn"):
			enemy.apply_burn(burn_dps, FIRE_DURATION)
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, target)

	_spawn_impact_vfx(target)
	_start_cooldown(id, def.base_cooldown)
	ability_cast.emit(id, target)
	return true


func _enemies_within(center: Vector2, radius: float) -> Array:
	var result: Array = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if center.distance_to(enemy.global_position) <= radius:
			result.append(enemy)
	return result


func _spawn_impact_vfx(pos: Vector2) -> void:
	var poof := POOF_SCENE.instantiate()
	get_tree().current_scene.add_child(poof)
	poof.global_position = pos


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
