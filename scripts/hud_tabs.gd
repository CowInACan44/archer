extends CanvasLayer

## RuneScape-style HUD: a small tab strip that opens Inventory/Stats/Options
## panels on demand instead of keeping everything on screen all the time.
## Only one panel is open at a time.

@onready var inventory_tab_button: BaseButton = $TabStrip/InventoryTabButton
@onready var stats_tab_button: BaseButton = $TabStrip/StatsTabButton
@onready var options_tab_button: BaseButton = $TabStrip/OptionsTabButton

@onready var inventory_panel: Control = $InventoryPanel
@onready var stats_panel: Control = $StatsPanel
@onready var options_panel: Control = $OptionsPanel

@onready var inv_wood_label: Label = $InventoryPanel/VBox/WoodRow/Count
@onready var inv_gold_label: Label = $InventoryPanel/VBox/GoldRow/Count
@onready var inv_arrows_label: Label = $InventoryPanel/VBox/ArrowsRow/Count

@onready var wave_label: Label = $StatsPanel/VBox/WaveLabel
@onready var towers_label: Label = $StatsPanel/VBox/TowersLabel
@onready var gold_label: Label = $StatsPanel/VBox/GoldLabel
@onready var wood_label: Label = $StatsPanel/VBox/WoodLabel

@onready var quit_button: BaseButton = $OptionsPanel/VBox/QuitButton

var _all_panels: Array[Control]


func _ready() -> void:
	add_to_group("hud_tabs")
	_all_panels = [inventory_panel, stats_panel, options_panel]
	for panel in _all_panels:
		panel.visible = false

	inventory_tab_button.tooltip_text = "Inventory"
	stats_tab_button.tooltip_text = "Village Stats"
	options_tab_button.tooltip_text = "Options"

	inventory_tab_button.pressed.connect(_on_tab_pressed.bind(inventory_panel))
	stats_tab_button.pressed.connect(_on_tab_pressed.bind(stats_panel))
	options_tab_button.pressed.connect(_on_tab_pressed.bind(options_panel))
	quit_button.pressed.connect(_on_quit_pressed)

	for tab_button in [inventory_tab_button, stats_tab_button, options_tab_button]:
		tab_button.pivot_offset = tab_button.size / 2.0
		tab_button.mouse_entered.connect(_on_tab_hover_start.bind(tab_button))
		tab_button.mouse_exited.connect(_on_tab_hover_end.bind(tab_button))

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.gold_changed.connect(_on_stat_changed)
		gm.wood_changed.connect(_on_stat_changed)

	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.wave_started.connect(_on_stat_changed)
		spawner.wave_cleared.connect(_on_stat_changed)

	_refresh_stats()
	_refresh_inventory()


## Called by the merchant panel so it doesn't end up overlapping whichever
## HUD tab was left open (e.g. Inventory) when a wave clears.
func close_all_panels() -> void:
	for panel in _all_panels:
		panel.visible = false


func _on_tab_hover_start(tab_button: Control) -> void:
	var tween := create_tween()
	tween.tween_property(tab_button, "scale", Vector2(1.1, 1.1), 0.1)


func _on_tab_hover_end(tab_button: Control) -> void:
	var tween := create_tween()
	tween.tween_property(tab_button, "scale", Vector2.ONE, 0.1)


func _on_tab_pressed(panel: Control) -> void:
	var was_open := panel.visible
	for p in _all_panels:
		p.visible = false
	panel.visible = not was_open
	if panel.visible:
		_refresh_stats()
		_refresh_inventory()


func _on_stat_changed(_value=null) -> void:
	_refresh_stats()
	_refresh_inventory()


func _refresh_stats() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	wave_label.text = "Wave: %d" % (spawner.current_wave if spawner else 0)
	towers_label.text = "Towers: %d" % get_tree().get_nodes_in_group("tower").size()
	gold_label.text = "Gold: %d" % (gm.gold if gm else 0)
	wood_label.text = "Wood: %d" % (gm.wood if gm else 0)


func _refresh_inventory() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	inv_wood_label.text = str(gm.wood if gm else 0)
	inv_gold_label.text = str(gm.gold if gm else 0)

	var total_arrows := 0
	for tower in get_tree().get_nodes_in_group("tower"):
		if not is_instance_valid(tower):
			continue
		var field: Node = tower.get_node_or_null("ArrowField")
		if field and field.has_method("filled_count"):
			total_arrows += field.filled_count()
	inv_arrows_label.text = str(total_arrows)


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
