extends HBoxContainer

@onready var amount_label: Label = $Amount


func _ready() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	gm.gold_changed.connect(_on_amount_changed)
	amount_label.text = str(gm.gold)


func _on_amount_changed(amount: int) -> void:
	amount_label.text = str(amount)
