extends Node
class_name GameManager

signal gold_changed(amount: int)
signal wood_changed(amount: int)
signal stone_changed(amount: int)
signal card_choice_ready(cards: Array)
@export var default_cursor: Texture2D
@export var default_cursor_hotspot: Vector2 = Vector2(4, 4)
var gold: int = 0
var wood: int = 0
var stone: int = 0
var luck: float = 1.0

## Accumulated upgrade bonuses from picked cards, applied to every tower -
## existing ones immediately, new ones the moment they're built - so
## upgrades aren't lost when a second (or third) tower goes up mid-run.
var total_arrow_damage_bonus: int = 0
var total_fire_rate_reduction: float = 0.0
var total_range_bonus: float = 0.0
var volley_unlocked: bool = false
var volley_interval: float = 8.0

## --- Wood-cost incrementals (the Skills tab) ---
## Repeatable, always-available upgrades bought with wood instead of the
## (currently disabled) gold-cost merchant cards above - each is a level
## you can keep buying, cost scaling up per level already bought.
signal incrementals_changed

var fire_rate_level: int = 0
var damage_level: int = 0
var range_level: int = 0
var wood_drop_level: int = 0
var gold_drop_level: int = 0
var population_level: int = 0

## Shared cost curve for every incremental (this section and the Village
## ones below): cheap and wood-only for the first few levels so a fresh
## run can actually afford something (a starting wallet of ~10 wood used
## to be less than every single incremental's base cost), then gold-only
## for a stretch once a gold income is going, then gold+wood together at
## the high end - population also asks for stone there, since it's the
## "grow the kingdom" tree.
const TIER1_WOOD_COSTS := [2, 4, 8, 12, 18]
const TIER2_LEVELS := 5
const TIER2_BASE_GOLD := 15
const TIER2_GOLD_GROWTH := 1.4
const TIER3_BASE_GOLD := 30
const TIER3_BASE_WOOD := 20
const TIER3_BASE_STONE := 10
const TIER3_GROWTH := 1.3

## 0.05 was hard to feel purchase-to-purchase (needed ~8-10 buys before
## the difference was obvious against the 1.2s base) - bumped so each
## level reads as a real change.
const FIRE_RATE_STEP := 0.09
const DAMAGE_STEP := 1
const RANGE_STEP := 25.0
const WOOD_DROP_CHANCE_STEP := 0.08
const WOOD_DROP_AMOUNT_STEP := 1
const GOLD_DROP_CHANCE_STEP := 0.08
const GOLD_DROP_AMOUNT_STEP := 1

## Applied on top of each enemy's own drop chance/amount exports.
var wood_drop_chance_mult: float = 1.0
var wood_drop_amount_bonus: int = 0
var gold_drop_chance_mult: float = 1.0
var gold_drop_amount_bonus: int = 0

## --- Village incrementals (the Village/Build tab) ---
## Pawn-focused upgrades, same repeatable/scaling-cost shape as the
## combat incrementals above.
var pawn_health_level: int = 0
var pawn_carry_level: int = 0
var pawn_speed_level: int = 0
var mining_speed_level: int = 0

const PAWN_HEALTH_STEP := 5
const PAWN_CARRY_STEP := 1
const PAWN_SPEED_STEP := 6.0
const MINING_SPEED_STEP := 0.12

var pawn_max_health_bonus: int = 0
var pawn_carry_bonus: int = 0
var pawn_speed_bonus: float = 0.0
var mining_speed_bonus: float = 0.0

## Manual "clicker" layer - click a tree/rock directly to harvest it
## yourself, independent of the pawns' auto-gathering. Starts at 1 like
## a pawn's base carry, same tiered cost curve.
var click_power_level: int = 0
const CLICK_POWER_STEP := 1
var click_power: int = 1

const HOUSE_WOOD_COST := 30
const HOUSE_GOLD_COST := 15


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
	tower.detection_range += total_range_bonus
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


func add_stone(amount: int) -> void:
	var scaled: int = int(round(amount * luck))
	stone += scaled
	stone_changed.emit(stone)


func spend_stone(amount: int) -> bool:
	if stone < amount:
		return false
	stone -= amount
	stone_changed.emit(stone)
	return true


## level: how many times this incremental has already been bought.
## uses_stone: whether tier 3 (level 10+) also asks for stone on top of
## gold+wood - only Population uses this for now.
func _tiered_cost(level: int, uses_stone: bool = false) -> Dictionary:
	if level < TIER1_WOOD_COSTS.size():
		return {"wood": TIER1_WOOD_COSTS[level]}
	if level < TIER1_WOOD_COSTS.size() + TIER2_LEVELS:
		var t2: int = level - TIER1_WOOD_COSTS.size()
		return {"gold": int(round(TIER2_BASE_GOLD * pow(TIER2_GOLD_GROWTH, t2)))}
	var t3: int = level - TIER1_WOOD_COSTS.size() - TIER2_LEVELS
	var cost: Dictionary = {
		"gold": int(round(TIER3_BASE_GOLD * pow(TIER3_GROWTH, t3))),
		"wood": int(round(TIER3_BASE_WOOD * pow(TIER3_GROWTH, t3))),
	}
	if uses_stone:
		cost["stone"] = int(round(TIER3_BASE_STONE * pow(TIER3_GROWTH, t3)))
	return cost


func _can_afford(cost: Dictionary) -> bool:
	return wood >= cost.get("wood", 0) and gold >= cost.get("gold", 0) and stone >= cost.get("stone", 0)


## Only spends if every resource the cost dict names is affordable -
## never partially pays.
func _spend_cost(cost: Dictionary) -> bool:
	if not _can_afford(cost):
		return false
	if cost.has("wood"):
		spend_wood(cost["wood"])
	if cost.has("gold"):
		spend_gold(cost["gold"])
	if cost.has("stone"):
		spend_stone(cost["stone"])
	return true


## Formats a _tiered_cost() dict for button labels, e.g. "8 Wood" or
## "26 Wood, 39 Gold".
func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	if cost.has("wood"):
		parts.append("%d Wood" % cost["wood"])
	if cost.has("gold"):
		parts.append("%d Gold" % cost["gold"])
	if cost.has("stone"):
		parts.append("%d Stone" % cost["stone"])
	return ", ".join(parts)


func fire_rate_cost() -> Dictionary:
	return _tiered_cost(fire_rate_level)


func damage_cost() -> Dictionary:
	return _tiered_cost(damage_level)


func range_cost() -> Dictionary:
	return _tiered_cost(range_level)


func wood_drop_cost() -> Dictionary:
	return _tiered_cost(wood_drop_level)


func gold_drop_cost() -> Dictionary:
	return _tiered_cost(gold_drop_level)


func population_cost() -> Dictionary:
	return _tiered_cost(population_level, true)


func buy_fire_rate() -> bool:
	if not _spend_cost(fire_rate_cost()):
		return false
	fire_rate_level += 1
	total_fire_rate_reduction += FIRE_RATE_STEP
	for tower in get_tree().get_nodes_in_group("tower"):
		tower.set_fire_rate(maxf(0.2, tower.fire_rate - FIRE_RATE_STEP))
	incrementals_changed.emit()
	return true


func buy_damage() -> bool:
	if not _spend_cost(damage_cost()):
		return false
	damage_level += 1
	total_arrow_damage_bonus += DAMAGE_STEP
	for tower in get_tree().get_nodes_in_group("tower"):
		tower.arrow_damage_bonus = total_arrow_damage_bonus
	incrementals_changed.emit()
	return true


func buy_range() -> bool:
	if not _spend_cost(range_cost()):
		return false
	range_level += 1
	total_range_bonus += RANGE_STEP
	for tower in get_tree().get_nodes_in_group("tower"):
		tower.detection_range += RANGE_STEP
	incrementals_changed.emit()
	return true


func buy_wood_drop() -> bool:
	if not _spend_cost(wood_drop_cost()):
		return false
	wood_drop_level += 1
	wood_drop_chance_mult += WOOD_DROP_CHANCE_STEP
	wood_drop_amount_bonus += WOOD_DROP_AMOUNT_STEP
	incrementals_changed.emit()
	return true


func buy_gold_drop() -> bool:
	if not _spend_cost(gold_drop_cost()):
		return false
	gold_drop_level += 1
	gold_drop_chance_mult += GOLD_DROP_CHANCE_STEP
	gold_drop_amount_bonus += GOLD_DROP_AMOUNT_STEP
	incrementals_changed.emit()
	return true


## Raises enemy pressure (more enemies per wave, more can be alive at once)
## in exchange for better loot - this is the "push the difficulty for
## better rewards" lever the population tree is meant to be. Different,
## tougher enemy types unlocking over time is already handled by
## EnemySpawner's per-wave roster ramp (see enemy_spawner.gd).
func buy_population() -> bool:
	if not _spend_cost(population_cost()):
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


func pawn_health_cost() -> Dictionary:
	return _tiered_cost(pawn_health_level)


func pawn_carry_cost() -> Dictionary:
	return _tiered_cost(pawn_carry_level)


func buy_pawn_health() -> bool:
	if not _spend_cost(pawn_health_cost()):
		return false
	pawn_health_level += 1
	pawn_max_health_bonus += PAWN_HEALTH_STEP
	for pawn in get_tree().get_nodes_in_group("pawn"):
		if pawn.has_method("apply_health_bonus"):
			pawn.apply_health_bonus(PAWN_HEALTH_STEP)
	incrementals_changed.emit()
	return true


func buy_pawn_carry() -> bool:
	if not _spend_cost(pawn_carry_cost()):
		return false
	pawn_carry_level += 1
	pawn_carry_bonus += PAWN_CARRY_STEP
	incrementals_changed.emit()
	return true


func pawn_speed_cost() -> Dictionary:
	return _tiered_cost(pawn_speed_level)


func buy_pawn_speed() -> bool:
	if not _spend_cost(pawn_speed_cost()):
		return false
	pawn_speed_level += 1
	pawn_speed_bonus += PAWN_SPEED_STEP
	incrementals_changed.emit()
	return true


func mining_speed_cost() -> Dictionary:
	return _tiered_cost(mining_speed_level)


func buy_mining_speed() -> bool:
	if not _spend_cost(mining_speed_cost()):
		return false
	mining_speed_level += 1
	mining_speed_bonus += MINING_SPEED_STEP
	incrementals_changed.emit()
	return true


func click_power_cost() -> Dictionary:
	return _tiered_cost(click_power_level)


func buy_click_power() -> bool:
	if not _spend_cost(click_power_cost()):
		return false
	click_power_level += 1
	click_power += CLICK_POWER_STEP
	incrementals_changed.emit()
	return true


## Houses unlock once every octagon point has a standing tower - "a few
## towers in" is already the early game, the full ring is the signal the
## kingdom-growth layer should open up (see DESIGN.md).
## Unlocked at the 2nd tower (not the full 8-tower ring) so pawns/houses
## ease the player into the kingdom-growth layer early instead of being
## a distant, all-or-nothing reward.
func houses_unlocked() -> bool:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	if km == null:
		return false
	var built_count := 0
	for t in km.point_towers:
		if t != null and is_instance_valid(t):
			built_count += 1
	return built_count >= 2


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
