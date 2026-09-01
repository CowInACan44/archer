extends CanvasLayer

## Shown only while a horde-night boss enemy is alive (see
## EnemySpawner._spawn_boss / boss_spawned signal). Hidden the rest of the
## time so it doesn't compete with the regular per-tower health bars.
##
## BarFill is a plain ColorRect anchored left with anchor_right set to the
## health fraction, not a TextureProgressBar - BigBar_Base/Fill.png turned
## out to be multi-piece bar-kit sheets rather than single stretchable
## images (rendered as broken black blocks), the same issue already found
## and fixed this way for the day/night clock bar.

@onready var bar: Control = $Bar
@onready var bar_fill: ColorRect = $Bar/HealthBar/BarFill
@onready var name_label: Label = $Bar/NameLabel

var _current_boss: Node = null


func _ready() -> void:
	bar.visible = false
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.boss_spawned.connect(_on_boss_spawned)


func _on_boss_spawned(boss: Node) -> void:
	_current_boss = boss
	bar.visible = true
	name_label.text = "Horde Boss"
	_update_fill(boss.current_health, boss.max_health)
	boss.health_changed.connect(_on_boss_health_changed)
	boss.died.connect(_on_boss_died)


func _on_boss_health_changed(current: int, max_health: int) -> void:
	_update_fill(current, max_health)


func _update_fill(current: int, max_health: int) -> void:
	bar_fill.anchor_right = clampf(float(current) / float(max_health), 0.0, 1.0) if max_health > 0 else 0.0


func _on_boss_died() -> void:
	bar.visible = false
	_current_boss = null
