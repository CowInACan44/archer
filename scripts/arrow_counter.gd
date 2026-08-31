extends HBoxContainer

@onready var count_label: Label = $Count


func _ready() -> void:
	var tower: Node = get_tree().get_first_node_in_group("tower")
	if tower:
		tower.arrows_changed.connect(_on_arrows_changed)


func _on_arrows_changed(current: int, max_arrows: int) -> void:
	count_label.text = "x %d" % current
