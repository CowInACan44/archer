extends TextureButton
class_name HealthUpgradeButton

func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	var tower: Node = get_tree().get_first_node_in_group("tower")
	if tower and tower.has_method("try_upgrade_health"):
		tower.try_upgrade_health()
