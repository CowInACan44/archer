extends CanvasLayer

## RuneScape-style HUD: a small tab strip that opens/closes panels instead
## of keeping everything on screen all the time. Only one panel is open at
## a time.

@onready var stats_tab_button: BaseButton = $TabStrip/StatsTabButton
@onready var options_tab_button: BaseButton = $TabStrip/OptionsTabButton
@onready var stats_panel: Control = $StatsPanel
@onready var options_panel: Control = $OptionsPanel

@onready var wave_label: Label = $StatsPanel/VBox/WaveLabel
@onready var towers_label: Label = $StatsPanel/VBox/TowersLabel
@onready var gold_label: Label = $StatsPanel/VBox/GoldLabel
@onready var wood_label: Label = $StatsPanel/VBox/WoodLabel

@onready var quit_button: BaseButton = $OptionsPanel/VBox/QuitButton


func _ready() -> void:
	stats_panel.visible = false
	options_panel.visible = false

	stats_tab_button.tooltip_text = "Village Stats"
	options_tab_button.tooltip_text = "Options"

	stats_tab_button.pressed.connect(_on_stats_tab_pressed)
	options_tab_button.pressed.connect(_on_options_tab_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.gold_changed.connect(_on_stat_changed)
		gm.wood_changed.connect(_on_stat_changed)

	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.wave_started.connect(_on_stat_changed)
		spawner.wave_cleared.connect(_on_stat_changed)

	_refresh_stats()


func _on_stats_tab_pressed() -> void:
	stats_panel.visible = not stats_panel.visible
	if stats_panel.visible:
		options_panel.visible = false
		_refresh_stats()


func _on_options_tab_pressed() -> void:
	options_panel.visible = not options_panel.visible
	if options_panel.visible:
		stats_panel.visible = false


func _on_stat_changed(_value=null) -> void:
	if stats_panel.visible:
		_refresh_stats()


func _refresh_stats() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	wave_label.text = "Wave: %d" % (spawner.current_wave if spawner else 0)
	towers_label.text = "Towers: %d" % get_tree().get_nodes_in_group("tower").size()
	gold_label.text = "Gold: %d" % (gm.gold if gm else 0)
	wood_label.text = "Wood: %d" % (gm.wood if gm else 0)


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
