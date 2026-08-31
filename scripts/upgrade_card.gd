extends Button
class_name UpgradeCard

## One "sheep" in the merchant's train - each carries one upgrade. Stays
## visible after being bought (greyed out, "Sold") rather than vanishing,
## so the merchant's whole stock stays on screen while you shop.

signal card_selected(card: Dictionary, card_button: Node)

@onready var sheep: AnimatedSprite2D = $Sheep
@onready var icon: TextureRect = $Icon
@onready var name_label: Label = $Name
@onready var cost_label: Label = $CostRow/CostLabel

var card_data: Dictionary
var _purchased := false


func setup(data: Dictionary) -> void:
	card_data = data
	_purchased = false
	disabled = false
	modulate = Color.WHITE

	name_label.text = data.get("short_label", data.get("name", ""))
	tooltip_text = data.get("description", data.get("name", ""))
	cost_label.text = str(data.get("cost", 0))
	if data.has("icon"):
		icon.texture = load(data.icon)


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_hover_start)
	mouse_exited.connect(_on_hover_end)
	button_down.connect(_on_press_start)
	button_up.connect(_on_press_end)
	sheep.play("idle")
	pivot_offset = size / 2.0


func mark_purchased() -> void:
	_purchased = true
	disabled = true
	modulate = Color(0.55, 0.55, 0.55, 1.0)
	tooltip_text = "%s (sold)" % card_data.get("name", "")


func flash_cant_afford() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(2.2, 0.6, 0.6), 0.08)
	tween.tween_property(self, "modulate", Color.WHITE, 0.18)


func _on_hover_start() -> void:
	if _purchased:
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.1)


func _on_hover_end() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)


func _on_press_start() -> void:
	if _purchased:
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(0.95, 0.95), 0.05)


func _on_press_end() -> void:
	if _purchased:
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.08)


func _on_pressed() -> void:
	if _purchased:
		return
	card_selected.emit(card_data, self)
