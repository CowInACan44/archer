extends Node
class_name GameManager

signal gold_changed(amount: int)
signal wood_changed(amount: int)
signal card_choice_ready(cards: Array)
@export var default_cursor: Texture2D
@export var default_cursor_hotspot: Vector2 = Vector2(4, 4)
var gold: int = 0
var wood: int = 0
var luck: float = 1.0


func _ready() -> void:
	add_to_group("game_manager")
	if default_cursor:
		Input.set_custom_mouse_cursor(default_cursor, Input.CURSOR_ARROW, default_cursor_hotspot)

func add_gold(amount: int) -> void:
	var scaled: int = int(round(amount * luck))
	gold += scaled
	gold_changed.emit(gold)


func add_wood(amount: int) -> void:
	var scaled: int = int(round(amount * luck))
	wood += scaled
	wood_changed.emit(wood)


func spend_wood(amount: int) -> bool:
	if wood < amount:
		return false
	wood -= amount
	wood_changed.emit(wood)
	return true


func offer_wave_cards() -> void:
	var options: Array = CardPool.get_random_cards(3)
	card_choice_ready.emit(options)


func apply_card(card: Dictionary) -> void:
	var tower: Node = get_tree().get_first_node_in_group("tower")
	if tower == null:
		return
	match card.effect:
		"attack_power":
			tower.arrow_damage_bonus += int(card.value)
		"fire_rate":
			tower.fire_rate = maxf(0.2, tower.fire_rate - float(card.value))
		"volley":
			tower.volley_enabled = true
			tower.volley_interval = card.get("volley_interval", 8.0)
