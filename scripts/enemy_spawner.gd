extends Node2D
class_name EnemySpawner

const GOBLIN_SCENE := preload("res://scenes/gob_spear.tscn")
const MINOTAUR_SCENE := preload("res://scenes/minotaur.tscn")

## Enemy roster for waves, keyed by the wave each one starts appearing in
## (1 = available from the start). Built here as a plain script constant
## instead of an exported array - a typed Array export can't be reliably
## overridden from a .tscn file's property list, so a scene-file roster
## silently fell back to nothing spawning past the first entry. To add a
## new enemy type: build its scene the same way as gob_spear.tscn/
## minotaur.tscn (one AnimatedSprite2D child named "Spearman" using
## Enemy.gd, frames sliced at Rect2(i * frame_height, 0, frame_height,
## frame_height) since these sheets are single-row strips where frame
## size == image height), then add it to this table.
##
## base_weight/ramp_weight_per_wave control how often each type gets
## picked once unlocked - a flat 50/50 the instant a tougher type unlocks
## made waves swing wildly (a run of bad luck could roll almost all
## Minotaurs). Instead each type starts rare right at its unlock wave and
## gradually becomes more common the further past that wave you get.
const ROSTER := [
	{"scene": GOBLIN_SCENE, "unlock_wave": 1, "base_weight": 4.0, "ramp_weight_per_wave": 0.0},
	{"scene": MINOTAUR_SCENE, "unlock_wave": 5, "base_weight": 0.5, "ramp_weight_per_wave": 0.2},
]

@export var spawn_left: Marker2D
@export var spawn_right: Marker2D

@export var base_enemy_count: int = 3
@export var enemies_per_wave_increase: int = 1
@export var base_spawn_interval: float = 1.5
@export var min_spawn_interval: float = 0.3
@export var interval_decrease_per_wave: float = 0.15

## Hard cap on how many enemies can be alive/on-screen at once, independent
## of the wave's total count - excess enemies simply wait their turn to
## spawn as earlier ones die, instead of piling onto the tower all at once.
@export var max_concurrent_enemies: int = 6

## Per-wave toughness scaling, on top of the count/spawn-rate ramp above -
## otherwise late waves are just more of the same weak enemy instead of a
## real difficulty curve.
@export var wave_health_scale: float = 0.10
@export var wave_damage_scale: float = 0.05
@export var wave_speed_scale: float = 0.015
@export var max_speed_multiplier: float = 1.5

## How much tougher a horde-night boss is than a normal same-wave Minotaur.
@export var horde_boss_health_mult: float = 3.0
@export var horde_boss_damage_mult: float = 1.5
@export var horde_boss_scale: float = 1.6

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal boss_spawned(boss: Node)

var current_wave := 0
var enemies_remaining_to_spawn := 0
var enemies_alive := 0
var _spawn_timer: Timer


func _ready() -> void:
	add_to_group("enemy_spawner")
	_spawn_timer = Timer.new()
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_spawn_one)
	## Waves no longer self-start or self-chain here - DayNightCycle drives
	## pacing (Day for pawn management, Night for combat) by calling
	## start_wave() on each Night. See scripts/day_night_cycle.gd.


## Called by DayNightCycle at the start of each Night. is_horde spawns one
## extra tough boss enemy on top of the normal wave roster.
func start_wave(is_horde: bool = false) -> void:
	current_wave += 1
	var count: int = base_enemy_count + (current_wave - 1) * enemies_per_wave_increase
	var interval: float = maxf(min_spawn_interval, base_spawn_interval - (current_wave - 1) * interval_decrease_per_wave)

	enemies_remaining_to_spawn = count
	_spawn_timer.wait_time = interval
	_spawn_timer.start()
	wave_started.emit(current_wave)

	if is_horde:
		_spawn_boss()


func _spawn_boss() -> void:
	var spawn_point: Marker2D = spawn_left if randi() % 2 == 0 else spawn_right
	var boss := MINOTAUR_SCENE.instantiate()
	_scale_enemy_for_wave(boss)
	boss.max_health = int(round(boss.max_health * horde_boss_health_mult))
	boss.attack_damage = int(round(boss.attack_damage * horde_boss_damage_mult))
	boss.is_boss = true
	get_tree().current_scene.add_child(boss)
	boss.global_position = spawn_point.global_position
	boss.scale *= horde_boss_scale
	boss.tree_exited.connect(_on_enemy_removed)

	enemies_alive += 1
	boss_spawned.emit(boss)


## Weighted pick among unlocked roster entries - see the ROSTER comment for
## why this isn't a flat random choice.
func _pick_enemy_scene() -> PackedScene:
	var candidates: Array = []
	var total_weight := 0.0
	for entry in ROSTER:
		if current_wave < entry.unlock_wave:
			continue
		var weight: float = entry.base_weight + entry.ramp_weight_per_wave * (current_wave - entry.unlock_wave)
		candidates.append({"scene": entry.scene, "weight": weight})
		total_weight += weight

	## Always fall back to the first entry rather than spawning nothing if
	## the roster is somehow misconfigured.
	if candidates.is_empty():
		return ROSTER[0].scene if not ROSTER.is_empty() else null

	var roll := randf() * total_weight
	for c in candidates:
		roll -= c.weight
		if roll <= 0.0:
			return c.scene
	return candidates[-1].scene


func _spawn_one() -> void:
	if enemies_remaining_to_spawn <= 0:
		_spawn_timer.stop()
		return

	## Excess enemies just wait for the timer's next tick instead of piling
	## on - the timer keeps ticking (rather than stopping) so spawning
	## resumes automatically the moment room opens up.
	if enemies_alive >= max_concurrent_enemies:
		return

	var chosen_scene := _pick_enemy_scene()
	if chosen_scene == null:
		_spawn_timer.stop()
		return

	var spawn_point: Marker2D = spawn_left if randi() % 2 == 0 else spawn_right
	var enemy := chosen_scene.instantiate()
	_scale_enemy_for_wave(enemy)
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn_point.global_position
	enemy.tree_exited.connect(_on_enemy_removed)

	enemies_remaining_to_spawn -= 1
	enemies_alive += 1


## Must run before add_child() - Enemy._ready() reads max_health into
## current_health once, so scaling it after the enemy enters the tree
## would leave current_health at the old, lower value.
func _scale_enemy_for_wave(enemy: Node) -> void:
	var wave_index: int = current_wave - 1  # wave 1 = no bonus yet
	if wave_index <= 0:
		return
	if "max_health" in enemy:
		enemy.max_health = int(round(enemy.max_health * (1.0 + wave_health_scale * wave_index)))
	if "attack_damage" in enemy:
		enemy.attack_damage = int(round(enemy.attack_damage * (1.0 + wave_damage_scale * wave_index)))
	if "move_speed" in enemy:
		var speed_mult: float = minf(max_speed_multiplier, 1.0 + wave_speed_scale * wave_index)
		enemy.move_speed *= speed_mult


func _on_enemy_removed() -> void:
	enemies_alive -= 1
	if not is_inside_tree():
		return
	if enemies_alive <= 0 and enemies_remaining_to_spawn <= 0:
		wave_cleared.emit(current_wave)
		## No more merchant popup on wave clear - upgrades are bought any
		## time from the Skills tab's wood-cost incrementals instead. The
		## traveling merchant (GameManager.offer_wave_cards) is disabled
		## for now, not deleted - see DESIGN.md for bringing it back later
		## as a trinket/rare-item vendor.
		## Pacing into the next Night (how long the following Day lasts) is
		## DayNightCycle's job now - it listens for wave_cleared and calls
		## start_wave() again once Day is over.
