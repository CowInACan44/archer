extends Node2D

## The goblin's attack_damage and the tower's near-infinite max_health are
## overridden directly on the instanced nodes in main_menu.tscn, so this
## fight just loops forever in the background instead of ever resolving.

@onready var tower_decoration: Node = $TowerDecoration
@onready var play_button: BaseButton = $UI/VBox/PlayButton
@onready var quit_button: BaseButton = $UI/VBox/QuitButton


func _ready() -> void:
	_hide_gameplay_only_ui(tower_decoration, "HealthBar")
	_hide_gameplay_only_ui(tower_decoration, "BuyArrowsButton")
	_hide_gameplay_only_ui(tower_decoration, "HealthUpgradeButton")

	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _hide_gameplay_only_ui(parent: Node, child_name: String) -> void:
	if parent == null:
		return
	var child: Node = parent.get_node_or_null(child_name)
	if child:
		child.visible = false


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
