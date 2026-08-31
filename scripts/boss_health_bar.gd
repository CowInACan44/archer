extends CanvasLayer

## Shown only while a horde-night boss enemy is alive (see
## EnemySpawner._spawn_boss / boss_spawned signal). Hidden the rest of the
## time so it doesn't compete with the regular per-tower health bars.

@onready var bar: Control = $Bar
@onready var health_bar: TextureProgressBar = $Bar/HealthBar
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
	health_bar.max_value = boss.max_health
	health_bar.value = boss.current_health
	boss.health_changed.connect(_on_boss_health_changed)
	boss.died.connect(_on_boss_died)


func _on_boss_health_changed(current: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = current


func _on_boss_died() -> void:
	bar.visible = false
	_current_boss = null
