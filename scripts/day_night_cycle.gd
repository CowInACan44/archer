extends Node2D
class_name DayNightCycle

## The temporal spine for the kingdom-growth layer (see DESIGN.md). Day is
## the calm phase - pawns gather, cards can be picked, nothing is
## attacking. Night is the existing wave-combat system, just renamed and
## externally driven instead of self-chaining. EnemySpawner no longer
## starts or re-triggers its own waves - it waits for start_wave() here.

enum Phase { DAY, NIGHT }

@export var day_duration: float = 20.0

## Every Nth night is a horde: a tougher wave plus one boss-tier enemy.
@export var horde_interval: int = 2

@onready var canvas_modulate: CanvasModulate = $CanvasModulate

const DAY_COLOR := Color(1, 1, 1)
const NIGHT_COLOR := Color(0.35, 0.38, 0.55)
@export var tint_transition_duration: float = 2.0

signal phase_changed(phase: Phase, day_number: int)
signal horde_warning(day_number: int)

var phase: Phase = Phase.DAY
var day_number: int = 1

var _day_timer: Timer


func _ready() -> void:
	add_to_group("day_night_cycle")
	_day_timer = Timer.new()
	add_child(_day_timer)
	_day_timer.one_shot = true
	_day_timer.timeout.connect(_start_night)

	## Wait a frame so every other node's _ready() (including EnemySpawner's
	## add_to_group call) has run before we go looking for it by group.
	await get_tree().process_frame
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.wave_cleared.connect(_on_wave_cleared)

	_start_day()


func is_night() -> bool:
	return phase == Phase.NIGHT


func _start_day() -> void:
	phase = Phase.DAY
	phase_changed.emit(phase, day_number)
	_tint_to(DAY_COLOR)
	_day_timer.wait_time = day_duration
	_day_timer.start()


func _start_night() -> void:
	phase = Phase.NIGHT
	phase_changed.emit(phase, day_number)
	_tint_to(NIGHT_COLOR)

	var horde := _is_horde_night()
	if horde:
		horde_warning.emit(day_number)

	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner and spawner.has_method("start_wave"):
		spawner.start_wave(horde)


func _on_wave_cleared(_wave_number: int) -> void:
	day_number += 1
	_start_day()


func _is_horde_night() -> bool:
	return horde_interval > 0 and day_number % horde_interval == 0


func _tint_to(target: Color) -> void:
	if canvas_modulate == null:
		return
	var tween := create_tween()
	tween.tween_property(canvas_modulate, "color", target, tint_transition_duration)
