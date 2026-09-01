extends CanvasLayer

## Shown once every tower is simultaneously destroyed (see
## KingdomManager.all_towers_destroyed) - previously there was no lose
## condition at all since towers can always be repaired/rebuilt given
## enough materials, so a player could keep going indefinitely.

@onready var panel: Control = $Panel
@onready var restart_button: Button = $Panel/RestartButton

func _ready() -> void:
	## Runs even while the tree is paused, so the Restart button still
	## works after _show_game_over() pauses everything else.
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	restart_button.pressed.connect(_on_restart_pressed)

	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	if km:
		km.all_towers_destroyed.connect(_show_game_over)


func _show_game_over() -> void:
	panel.visible = true
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
