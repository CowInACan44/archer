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
const ROSTER := [
	{"scene": GOBLIN_SCENE, "unlock_wave": 1},
	{"scene": MINOTAUR_SCENE, "unlock_wave": 5},
]

@export var spawn_left: Marker2D
@export var spawn_right: Marker2D

@export var base_enemy_count: int = 3
@export var enemies_per_wave_increase: int = 2
@export var base_spawn_interval: float = 1.5
@export var min_spawn_interval: float = 0.3
@export var interval_decrease_per_wave: float = 0.15

@export var time_between_waves: float = 6.0

## Per-wave toughness scaling, on top of the count/spawn-rate ramp above -
## otherwise late waves are just more of the same weak enemy instead of a
## real difficulty curve.
@export var wave_health_scale: float = 0.10
@export var wave_damage_scale: float = 0.05
@export var wave_speed_scale: float = 0.015
@export var max_speed_multiplier: float = 1.5

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)

var current_wave := 0
var enemies_remaining_to_spawn := 0
var enemies_alive := 0
var _spawn_timer: Timer


func _ready() -> void:
	add_to_group("enemy_spawner")
	_spawn_timer = Timer.new()
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_spawn_one)
	_start_next_wave()


func _start_next_wave() -> void:
	current_wave += 1
	var count: int = base_enemy_count + (current_wave - 1) * enemies_per_wave_increase
	var interval: float = maxf(min_spawn_interval, base_spawn_interval - (current_wave - 1) * interval_decrease_per_wave)

	enemies_remaining_to_spawn = count
	_spawn_timer.wait_time = interval
	_spawn_timer.start()
	wave_started.emit(current_wave)


func _available_enemy_scenes() -> Array[PackedScene]:
	var result: Array[PackedScene] = []
	for entry in ROSTER:
		if current_wave >= entry.unlock_wave:
			result.append(entry.scene)
	## Always fall back to the first entry rather than spawning nothing if
	## the roster is somehow misconfigured.
	if result.is_empty() and not ROSTER.is_empty():
		result.append(ROSTER[0].scene)
	return result


func _spawn_one() -> void:
	if enemies_remaining_to_spawn <= 0:
		_spawn_timer.stop()
		return

	var available := _available_enemy_scenes()
	if available.is_empty():
		_spawn_timer.stop()
		return
	var chosen_scene: PackedScene = available[randi() % available.size()]

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

		var gm: Node = get_tree().get_first_node_in_group("game_manager")
		if gm:
			gm.offer_wave_cards()

		if not is_inside_tree():
			return
		await get_tree().create_timer(time_between_waves).timeout
		if not is_inside_tree():
			return
		_start_next_wave()
