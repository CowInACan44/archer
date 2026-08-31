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

## --- Wood-cost incrementals (the Skills tab) ---
## Repeatable, always-available upgrades bought with wood instead of the
## (currently disabled) gold-cost merchant cards above - each is a level
## you can keep buying, cost scaling up per level already bought.
signal incrementals_changed

var fire_rate_level: int = 0
var damage_level: int = 0
var wood_drop_level: int = 0
var population_level: int = 0

const FIRE_RATE_BASE_COST := 12
const DAMAGE_BASE_COST := 12
const WOOD_DROP_BASE_COST := 10
const POPULATION_BASE_COST := 18
const INCREMENTAL_COST_GROWTH := 1.35

const FIRE_RATE_STEP := 0.05
const DAMAGE_STEP := 1
const WOOD_DROP_CHANCE_STEP := 0.08
const WOOD_DROP_AMOUNT_STEP := 1
const GOLD_DROP_AMOUNT_STEP := 1

## Applied on top of each enemy's own drop chance/amount exports.
var wood_drop_chance_mult: float = 1.0
var wood_drop_amount_bonus: int = 0
var gold_drop_amount_bonus: int = 0


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


func _incremental_cost(base_cost: int, level: int) -> int:
	return int(round(base_cost * pow(INCREMENTAL_COST_GROWTH, level)))


func fire_rate_cost() -> int:
	return _incremental_cost(FIRE_RATE_BASE_COST, fire_rate_level)


func damage_cost() -> int:
	return _incremental_cost(DAMAGE_BASE_COST, damage_level)


func wood_drop_cost() -> int:
	return _incremental_cost(WOOD_DROP_BASE_COST, wood_drop_level)


func population_cost() -> int:
	return _incremental_cost(POPULATION_BASE_COST, population_level)


func buy_fire_rate() -> bool:
	if not spend_wood(fire_rate_cost()):
		return false
	fire_rate_level += 1
	total_fire_rate_reduction += FIRE_RATE_STEP
	for tower in get_tree().get_nodes_in_group("tower"):
		tower.set_fire_rate(maxf(0.2, tower.fire_rate - FIRE_RATE_STEP))
	incrementals_changed.emit()
	return true


func buy_damage() -> bool:
	if not spend_wood(damage_cost()):
		return false
	damage_level += 1
	total_arrow_damage_bonus += DAMAGE_STEP
	for tower in get_tree().get_nodes_in_group("tower"):
		tower.arrow_damage_bonus = total_arrow_damage_bonus
	incrementals_changed.emit()
	return true


func buy_wood_drop() -> bool:
	if not spend_wood(wood_drop_cost()):
		return false
	wood_drop_level += 1
	wood_drop_chance_mult += WOOD_DROP_CHANCE_STEP
	wood_drop_amount_bonus += WOOD_DROP_AMOUNT_STEP
	incrementals_changed.emit()
	return true


## Raises enemy pressure (more enemies per wave, more can be alive at once)
## in exchange for better loot - this is the "push the difficulty for
## better rewards" lever the population tree is meant to be. Different,
## tougher enemy types unlocking over time is already handled by
## EnemySpawner's per-wave roster ramp (see enemy_spawner.gd).
func buy_population() -> bool:
	if not spend_wood(population_cost()):
		return false
	population_level += 1
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.base_enemy_count += 1
		spawner.max_concurrent_enemies += 1
	gold_drop_amount_bonus += GOLD_DROP_AMOUNT_STEP
	wood_drop_amount_bonus += WOOD_DROP_AMOUNT_STEP
	incrementals_changed.emit()
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
