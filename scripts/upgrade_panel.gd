extends CanvasLayer
class_name UpgradePanel

## The merchant's cart between waves: three sheep, each carrying an
## upgrade you can buy with gold. Unlike the old free pick-one card,
## the panel stays open after a purchase so you can buy more than one
## if you can afford it - you leave when you're done, not when you pick.

@onready var slots: Array[UpgradeCard] = [
	$Control/HBoxContainer/UpgradeCard,
	$Control/HBoxContainer/UpgradeCard2,
	$Control/HBoxContainer/UpgradeCard3,
]
@onready var leave_button: BaseButton = $Control/LeaveButton


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	leave_button.pressed.connect(_on_leave_pressed)

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.card_choice_ready.connect(_on_cards_ready)


func _on_cards_ready(cards: Array) -> void:
	## Don't let a HUD tab left open (e.g. Inventory) sit on top of the
	## merchant when a wave clears mid-browse.
	var hud: Node = get_tree().get_first_node_in_group("hud_tabs")
	if hud and hud.has_method("close_all_panels"):
		hud.close_all_panels()

	for i in slots.size():
		if i < cards.size():
			slots[i].visible = true
			slots[i].setup(cards[i])
			if not slots[i].card_selected.is_connected(_on_card_selected):
				slots[i].card_selected.connect(_on_card_selected)
		else:
			slots[i].visible = false
	visible = true
	get_tree().paused = true


func _on_card_selected(card: Dictionary, card_button: UpgradeCard) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	var cost: int = card.get("cost", 0)
	if not gm.spend_gold(cost):
		card_button.flash_cant_afford()
		return
	gm.apply_card(card)
	card_button.mark_purchased()


func _on_leave_pressed() -> void:
	visible = false
	get_tree().paused = false
