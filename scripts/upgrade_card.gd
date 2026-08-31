extends TextureButton
class_name UpgradeCard

signal card_selected(card: Dictionary)

@onready var icon: AnimatedSprite2D = $Icon
@onready var name_label: Label = $Name

var card_data: Dictionary


func setup(data: Dictionary) -> void:
	card_data = data
	name_label.text = data.get("short_label", data.get("name", ""))
	tooltip_text = data.get("description", data.get("name", ""))
	if data.has("icon_frames"):
		icon.sprite_frames = load(data.icon_frames)
		icon.play("default")


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_hover_start)
	mouse_exited.connect(_on_hover_end)
	button_down.connect(_on_press_start)
	button_up.connect(_on_press_end)
	name_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
	pivot_offset = size / 2.0


func _on_hover_start() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.1)


func _on_hover_end() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)


func _on_press_start() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(0.95, 0.95), 0.05)


func _on_press_end() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.08)


func _on_pressed() -> void:
	card_selected.emit(card_data)
