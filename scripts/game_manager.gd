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

## Accumulated upgrade bonuses from picked cards, applied to every tower -
## existing ones immediately, new ones the moment they're built - so
## upgrades aren't lost when a second (or third) tower goes up mid-run.
var total_arrow_damage_bonus: int = 0
var total_fire_rate_reduction: float = 0.0
var volley_unlocked: bool = false
var volley_interval: float = 8.0


func _ready() -> void:
	add_to_group("game_manager")
	if default_cursor:
		Input.set_custom_mouse_cursor(default_cursor, Input.CURSOR_ARROW, default_cursor_hotspot)


## Nearest tower to a world position, ignoring destroyed towers. Used by
## pickups so they fly to whichever tower they're actually next to instead
## of always the first tower ever built.
func nearest_tower(from_position: Vector2) -> Node:
	var nearest: Node = null
	var nearest_dist := INF
	for t in get_tree().get_nodes_in_group("tower"):
		if not is_instance_valid(t) or ("is_destroyed" in t and t.is_destroyed):
			continue
		var dist: float = from_position.distance_to(t.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = t
	return nearest


## Called by kingdom_manager right after a new tower is built so it starts
## with every upgrade already picked this run, matching its siblings.
func register_tower(tower: Node) -> void:
	tower.arrow_damage_bonus = total_arrow_damage_bonus
	tower.set_fire_rate(maxf(0.2, tower.fire_rate - total_fire_rate_reduction))
	if volley_unlocked:
		tower.volley_enabled = true
		tower.volley_interval = volley_interval


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


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func offer_wave_cards() -> void:
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	var wave: int = spawner.current_wave if spawner else 1
	var options: Array = CardPool.get_random_cards(3, wave)
	card_choice_ready.emit(options)


func apply_card(card: Dictionary) -> void:
	var towers := get_tree().get_nodes_in_group("tower")
	match card.effect:
		"attack_power":
			total_arrow_damage_bonus += int(card.value)
			for tower in towers:
				tower.arrow_damage_bonus = total_arrow_damage_bonus
		"fire_rate":
			total_fire_rate_reduction += float(card.value)
			for tower in towers:
				tower.set_fire_rate(maxf(0.2, tower.fire_rate - float(card.value)))
		"volley":
			volley_unlocked = true
			volley_interval = card.get("volley_interval", 8.0)
			for tower in towers:
				tower.volley_enabled = true
				tower.volley_interval = volley_interval
