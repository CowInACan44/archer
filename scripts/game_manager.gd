extends Node
class_name GameManager

signal gold_changed(amount: int)
signal wood_changed(amount: int)
signal stone_changed(amount: int)
signal meat_changed(amount: int)
signal card_choice_ready(cards: Array)
@export var default_cursor: Texture2D
@export var default_cursor_hotspot: Vector2 = Vector2(4, 4)
var gold: int = 0
var wood: int = 0
var stone: int = 0
var meat: int = 0
var luck: float = 1.0

## Rewards swiping the mouse through several drops fast rather than
## clicking them one at a time - each pickup collected within
## CHAIN_WINDOW seconds of the last one bumps the multiplier, reset by
## any gap longer than that. Only pickup scripts (gold.gd/
## wood_pickup.gd/meat_pickup.gd) call register_pickup_chain() - it's
## deliberately separate from luck, which applies to every gain
## (pawn deliveries, click-harvesting, pickups alike).
const CHAIN_WINDOW := 0.35
const CHAIN_BONUS_PER_STEP := 0.15
const CHAIN_MAX_BONUS := 1.0
var chain_count: int = 0
var _last_pickup_time: float = -999.0
signal chain_changed(count: int)


func register_pickup_chain() -> float:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_pickup_time <= CHAIN_WINDOW:
		chain_count += 1
	else:
		chain_count = 0
	_last_pickup_time = now
	chain_changed.emit(chain_count)
	return 1.0 + minf(chain_count * CHAIN_BONUS_PER_STEP, CHAIN_MAX_BONUS)

## Accumulated upgrade bonuses from picked cards, applied to every tower -
## existing ones immediately, new ones the moment they're built - so
## upgrades aren't lost when a second (or third) tower goes up mid-run.
var total_arrow_damage_bonus: int = 0
var total_fire_rate_reduction: float = 0.0
var total_range_bonus: float = 0.0
var total_tower_health_bonus: int = 0
var volley_unlocked: bool = false
var volley_interval: float = 8.0

## --- Skills tab tree ------------------------------------------------------
## One branching node graph per category, rendered by skill_tree_view.gd
## with its own pan/zoom - "level" entries are the always-repeatable
## incrementals (root nodes, never lock, bought/read via the buy/level_prop/
## cost_fn method names below since they keep their own separate economy),
## "node" entries are one-time passive unlocks that branch off them and
## need their prerequisite already unlocked first. col/row are grid
## coordinates (not pixels) the view multiplies by its own spacing - hand-
## placed here so each category's tree shape is exact rather than
## depending on a generic auto-layout algorithm.
const SKILLS_UI_TREE := {
	"combat": [
		{"id": "fire_rate", "kind": "level", "name": "Fire Rate", "requires": "", "buy": "buy_fire_rate", "level_prop": "fire_rate_level", "cost_fn": "fire_rate_cost", "desc": "Tower fire delay", "col": 0, "row": 0},
		{"id": "damage", "kind": "level", "name": "Damage", "requires": "", "buy": "buy_damage", "level_prop": "damage_level", "cost_fn": "damage_cost", "desc": "Arrow damage", "col": 1, "row": 0},
		{"id": "range", "kind": "level", "name": "Range", "requires": "", "buy": "buy_range", "level_prop": "range_level", "cost_fn": "range_cost", "desc": "Tower detection range", "col": 2, "row": 0},
		{"id": "sharpshooter", "kind": "node", "name": "Sharpshooter", "requires": "fire_rate", "cost": {"gold": 40}, "effect": "fire_rate", "value": 0.15, "desc": "-0.15s tower fire delay", "col": 0, "row": 1},
		{"id": "piercing_arrows", "kind": "node", "name": "Piercing Arrows", "requires": "damage", "cost": {"gold": 80}, "effect": "damage", "value": 3, "desc": "+3 arrow damage", "col": 1, "row": 1},
		{"id": "armor_breaker", "kind": "node", "name": "Armor Breaker", "requires": "piercing_arrows", "cost": {"gold": 150, "stone": 15}, "effect": "damage", "value": 4, "desc": "+4 arrow damage", "col": 1, "row": 2},
		{"id": "eagle_eye", "kind": "node", "name": "Eagle Eye", "requires": "range", "cost": {"gold": 70}, "effect": "range", "value": 40.0, "desc": "+40 tower range", "col": 2, "row": 1},
		{"id": "hawk_sight", "kind": "node", "name": "Hawk Sight", "requires": "eagle_eye", "cost": {"gold": 140, "stone": 20}, "effect": "range", "value": 60.0, "desc": "+60 tower range", "col": 2, "row": 2},
	],
	"fortify": [
		{"id": "reinforced_walls", "kind": "node", "name": "Reinforced Walls", "requires": "", "cost": {"wood": 30, "stone": 10}, "effect": "tower_health", "value": 30, "desc": "+30 max tower health", "col": 0, "row": 0},
		{"id": "stonework", "kind": "node", "name": "Stonework", "requires": "reinforced_walls", "cost": {"gold": 60, "stone": 20}, "effect": "tower_health", "value": 40, "desc": "+40 max tower health", "col": 0, "row": 1},
		{"id": "iron_gates", "kind": "node", "name": "Iron Gates", "requires": "", "cost": {"gold": 50, "wood": 20}, "effect": "repair_cost", "value": 2, "desc": "-2 wood tower repair cost", "col": 1, "row": 0},
		## Repair/health-upgrade were separate reserved-space buttons before
		## the node-tree overhaul - folded in as repeatable "action" root
		## nodes instead so Fortify gets a real branching layout like every
		## other category, and every category's tree gets the full panel
		## instead of some space being reserved for non-graph buttons.
		{"id": "repair_action", "kind": "action", "name": "Repair", "requires": "", "action_id": "repair", "cost": {"wood": 4}, "desc": "Repairs the most damaged tower (+30 HP)", "col": 2, "row": 0},
		{"id": "health_upgrade_action", "kind": "action", "name": "Fortify Tower", "requires": "", "action_id": "health_upgrade", "cost": {"gold": 15, "wood": 10}, "desc": "Weakest tower +25 max HP", "col": 2, "row": 1},
	],
	"wood": [
		{"id": "wood_drop", "kind": "level", "name": "Wood Drop", "requires": "", "buy": "buy_wood_drop", "level_prop": "wood_drop_level", "cost_fn": "wood_drop_cost", "desc": "Wood drop chance & amount", "col": 0, "row": 0},
		{"id": "sharp_axes", "kind": "node", "name": "Sharp Axes", "requires": "wood_drop", "cost": {"wood": 25}, "effect": "wood_drop_chance", "value": 0.1, "desc": "+10% wood drop chance", "col": -1, "row": 1},
		{"id": "lumberjack_guild", "kind": "node", "name": "Lumberjack Guild", "requires": "sharp_axes", "cost": {"gold": 70}, "effect": "wood_drop_amount", "value": 2, "desc": "+2 wood per drop", "col": -1, "row": 2},
		{"id": "efficient_harvesting", "kind": "node", "name": "Efficient Harvesting", "requires": "wood_drop", "cost": {"gold": 90}, "effect": "mining_speed", "value": 0.15, "desc": "Faster pawn gathering", "col": 1, "row": 1},
	],
	"coin": [
		{"id": "gold_drop", "kind": "level", "name": "Gold Drop", "requires": "", "buy": "buy_gold_drop", "level_prop": "gold_drop_level", "cost_fn": "gold_drop_cost", "desc": "Gold drop chance & amount", "col": 0, "row": 0},
		{"id": "luck", "kind": "level", "name": "Luck", "requires": "", "buy": "buy_luck", "level_prop": "luck_level", "cost_fn": "luck_cost", "desc": "Overall drop chance & gain", "col": 1, "row": 0},
		{"id": "treasure_hunter", "kind": "node", "name": "Treasure Hunter", "requires": "gold_drop", "cost": {"gold": 90}, "effect": "gold_drop_amount", "value": 2, "desc": "+2 gold per drop", "col": 0, "row": 1},
		{"id": "keen_eye", "kind": "node", "name": "Keen Eye", "requires": "luck", "cost": {"wood": 25}, "effect": "luck", "value": 0.1, "desc": "+0.1 Luck", "col": 1, "row": 1},
		{"id": "fortunes_favor", "kind": "node", "name": "Fortune's Favor", "requires": "keen_eye", "cost": {"gold": 130}, "effect": "luck", "value": 0.15, "desc": "+0.15 Luck", "col": 1, "row": 2},
	],
	"growth": [
		{"id": "population", "kind": "level", "name": "Population", "requires": "", "buy": "buy_population", "level_prop": "population_level", "cost_fn": "population_cost", "desc": "More/tougher enemies, better loot", "col": 0, "row": 0},
		{"id": "master_builder", "kind": "node", "name": "Master Builder", "requires": "population", "cost": {"gold": 100, "stone": 20}, "effect": "house_cap", "value": 1, "desc": "+1 max houses", "col": 0, "row": 1},
		{"id": "urban_planning", "kind": "node", "name": "Urban Planning", "requires": "master_builder", "cost": {"gold": 160, "stone": 30}, "effect": "house_cap", "value": 1, "desc": "+1 max houses", "col": 0, "row": 2},
	],
}

var unlocked_skill_nodes: Dictionary = {}
var skill_house_cap_bonus: int = 0
var total_repair_cost_reduction: int = 0
signal skill_tree_changed


func skill_node_unlocked(id: String) -> bool:
	return unlocked_skill_nodes.get(id, false)


## True once the node's prerequisite (if any) is already unlocked - what
## gates a node from being buyable at all, separate from whether the
## player can currently afford it. "level" entries have no prerequisite
## and never lock; they're roots the "node" entries branch off from.
func skill_node_available(node: Dictionary) -> bool:
	return node.requires == "" or skill_node_unlocked(node.requires)


func buy_skill_node(category: String, id: String) -> bool:
	for node in SKILLS_UI_TREE.get(category, []):
		if node.id != id or node.kind != "node":
			continue
		if skill_node_unlocked(id) or not skill_node_available(node):
			return false
		if not _spend_cost(node.cost):
			return false
		unlocked_skill_nodes[id] = true
		_apply_skill_effect(node.effect, node.value)
		skill_tree_changed.emit()
		return true
	return false


func _apply_skill_effect(effect: String, value) -> void:
	match effect:
		"fire_rate":
			total_fire_rate_reduction += value
			for tower in get_tree().get_nodes_in_group("tower"):
				tower.set_fire_rate(maxf(0.2, tower.fire_rate - value))
		"damage":
			total_arrow_damage_bonus += int(value)
			for tower in get_tree().get_nodes_in_group("tower"):
				tower.arrow_damage_bonus = total_arrow_damage_bonus
		"range":
			total_range_bonus += value
			for tower in get_tree().get_nodes_in_group("tower"):
				tower.detection_range += value
		"tower_health":
			total_tower_health_bonus += int(value)
			for tower in get_tree().get_nodes_in_group("tower"):
				tower.max_health += int(value)
				tower.current_health += int(value)
		"repair_cost":
			total_repair_cost_reduction += int(value)
			for tower in get_tree().get_nodes_in_group("tower"):
				tower.repair_wood_cost = maxi(1, tower.repair_wood_cost - int(value))
		"wood_drop_chance":
			wood_drop_chance_mult += value
		"wood_drop_amount":
			wood_drop_amount_bonus += int(value)
		"mining_speed":
			mining_speed_bonus += value
			for pawn in get_tree().get_nodes_in_group("pawn"):
				if pawn.has_method("apply_mining_speed_bonus"):
					pawn.apply_mining_speed_bonus(value)
		"gold_drop_chance":
			gold_drop_chance_mult += value
		"gold_drop_amount":
			gold_drop_amount_bonus += int(value)
		"luck":
			luck += value
		"house_cap":
			skill_house_cap_bonus += int(value)

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
var luck_level: int = 0

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

## luck already does double duty everywhere it's read: Enemy.gd and
## ResourceNode multiply every drop CHANCE roll by it, and
## add_gold()/add_wood() multiply the AMOUNT of every gain by it - so one
## Luck stat naturally covers both "more stuff drops" and "pickups are
## worth more" without needing three overlapping incrementals.
const LUCK_STEP := 0.06

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
	tower.max_health += total_tower_health_bonus
	tower.current_health += total_tower_health_bonus
	tower.repair_wood_cost = maxi(1, tower.repair_wood_cost - total_repair_cost_reduction)
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


func add_meat(amount: int) -> void:
	var scaled: int = int(round(amount * luck))
	meat += scaled
	meat_changed.emit(meat)


func spend_meat(amount: int) -> bool:
	if meat < amount:
		return false
	meat -= amount
	meat_changed.emit(meat)
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


func luck_cost() -> Dictionary:
	return _tiered_cost(luck_level)


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


func buy_luck() -> bool:
	if not _spend_cost(luck_cost()):
		return false
	luck_level += 1
	luck += LUCK_STEP
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
	for pawn in get_tree().get_nodes_in_group("pawn"):
		if pawn.has_method("apply_carry_bonus"):
			pawn.apply_carry_bonus(PAWN_CARRY_STEP)
	incrementals_changed.emit()
	return true


func pawn_speed_cost() -> Dictionary:
	return _tiered_cost(pawn_speed_level)


func buy_pawn_speed() -> bool:
	if not _spend_cost(pawn_speed_cost()):
		return false
	pawn_speed_level += 1
	pawn_speed_bonus += PAWN_SPEED_STEP
	for pawn in get_tree().get_nodes_in_group("pawn"):
		if pawn.has_method("apply_speed_bonus"):
			pawn.apply_speed_bonus(PAWN_SPEED_STEP)
	incrementals_changed.emit()
	return true


func mining_speed_cost() -> Dictionary:
	return _tiered_cost(mining_speed_level)


func buy_mining_speed() -> bool:
	if not _spend_cost(mining_speed_cost()):
		return false
	mining_speed_level += 1
	mining_speed_bonus += MINING_SPEED_STEP
	for pawn in get_tree().get_nodes_in_group("pawn"):
		if pawn.has_method("apply_mining_speed_bonus"):
			pawn.apply_mining_speed_bonus(MINING_SPEED_STEP)
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


const HOUSE_REMOVE_REFUND_MULT := 0.5


## One house slot per standing tower - grows naturally as the kingdom's
## tower ring fills in instead of a flat cap that's either meaningless
## early or a hard wall late.
func house_cap() -> int:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	if km == null:
		return 0
	var built_count := 0
	for t in km.point_towers:
		if t != null and is_instance_valid(t):
			built_count += 1
	return built_count + skill_house_cap_bonus


## --- Pawn job allocation (Pawns tab) --------------------------------------
## Count-based instead of click-select-then-assign: the player just says
## "I want N pawns doing X" per job and whichever pawns are currently
## Generalist get drafted/released to make it so - no need to click
## individual pawns in the world to specialize them.
var pawn_job_targets: Dictionary = {
	Pawn.Job.WOOD: 0,
	Pawn.Job.STONE: 0,
	Pawn.Job.HUNTER: 0,
}
signal pawn_job_targets_changed


func set_pawn_job_target(job: Pawn.Job, count: int) -> void:
	pawn_job_targets[job] = maxi(0, count)
	pawn_job_targets_changed.emit()
	reconcile_pawn_jobs()


## Called whenever the targets change, and whenever the pawn population
## itself changes (a house spawns/loses one) - see house.gd - so the
## actual assigned counts drift back toward the targets on their own
## instead of only updating right when a +/- button is pressed.
func reconcile_pawn_jobs() -> void:
	var by_job: Dictionary = {
		Pawn.Job.GENERALIST: [], Pawn.Job.WOOD: [], Pawn.Job.STONE: [], Pawn.Job.HUNTER: [],
	}
	for p in get_tree().get_nodes_in_group("pawn"):
		if is_instance_valid(p):
			by_job[p.job].append(p)

	var specialist_jobs: Array = [Pawn.Job.WOOD, Pawn.Job.STONE, Pawn.Job.HUNTER]

	## Demote surplus pawns (a target got lowered, or population shrank)
	## back into the Generalist pool first, before promoting anyone else,
	## so a target that got raised can immediately draw from pawns a
	## lowered target just freed up in the same pass.
	for job in specialist_jobs:
		var target: int = pawn_job_targets.get(job, 0)
		var current: Array = by_job[job]
		while current.size() > target:
			var p = current.pop_back()
			p.set_job(Pawn.Job.GENERALIST)
			by_job[Pawn.Job.GENERALIST].append(p)

	for job in specialist_jobs:
		var target: int = pawn_job_targets.get(job, 0)
		var current: Array = by_job[job]
		var pool: Array = by_job[Pawn.Job.GENERALIST]
		while current.size() < target and not pool.is_empty():
			var p = pool.pop_back()
			p.set_job(job)
			current.append(p)


## One-time reward for KingdomManager.kingdom_expanded (every one of the 8
## octagon points has a standing tower) - the asset packs don't include an
## actual stone wall/gate tileset to build real fortification geometry
## from, so the milestone's tangible payoff is a permanent kingdom-wide
## bonus on top of the cosmetic tower/wall re-skin KingdomManager applies
## alongside this.
const KINGDOM_EXPANSION_TOWER_HEALTH_BONUS := 50
const KINGDOM_EXPANSION_HOUSE_CAP_BONUS := 2


func apply_kingdom_expansion_bonus() -> void:
	total_tower_health_bonus += KINGDOM_EXPANSION_TOWER_HEALTH_BONUS
	for tower in get_tree().get_nodes_in_group("tower"):
		tower.max_health += KINGDOM_EXPANSION_TOWER_HEALTH_BONUS
		tower.current_health += KINGDOM_EXPANSION_TOWER_HEALTH_BONUS
	skill_house_cap_bonus += KINGDOM_EXPANSION_HOUSE_CAP_BONUS


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
