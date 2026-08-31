extends CanvasLayer
class_name UpgradePanel

@onready var slots: Array[UpgradeCard] = [
	$Control/HBoxContainer/UpgradeCard,
	$Control/HBoxContainer/UpgradeCard2,
	$Control/HBoxContainer/UpgradeCard3,
]


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	print("UpgradePanel found gm: ", gm)
	if gm:
		gm.card_choice_ready.connect(_on_cards_ready)


func _on_cards_ready(cards: Array) -> void:
	for i in slots.size():
		if i < cards.size():
			slots[i].setup(cards[i])
			if not slots[i].card_selected.is_connected(_on_card_selected):
				slots[i].card_selected.connect(_on_card_selected)
	visible = true
	get_tree().paused = true


func _on_card_selected(card: Dictionary) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.apply_card(card)
	visible = false
	get_tree().paused = false
