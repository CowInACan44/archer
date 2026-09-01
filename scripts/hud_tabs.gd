extends CanvasLayer

## RuneScape-style HUD: a small tab strip that opens Inventory/Stats/Options
## panels on demand instead of keeping everything on screen all the time.
## Only one panel is open at a time.

const HOUSE_SCENE := preload("res://scenes/house.tscn")
const SHEEP_PEN_SCENE := preload("res://scenes/SheepPen.tscn")
const RETICLE_SCRIPT := preload("res://scripts/ability_reticle.gd")

## Purely cosmetic - every variant has the same capacity/health/behavior
## (house.gd's set_house_texture() just swaps the sprite).
const HOUSE_TEXTURES := [
	preload("res://tiny/Tiny Swords (Free Pack)/Buildings/Yellow Buildings/House1.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Buildings/Yellow Buildings/House2.png"),
	preload("res://tiny/Tiny Swords (Free Pack)/Buildings/Yellow Buildings/House3.png"),
]

## How far from another house/tower a new house must be, and how far
## outside the octagon's radius counts as "still inside the kingdom" -
## rough placement validity instead of full collision geometry.
## House1.png is 128px wide - 100 let houses' centers land closer together
## than their own sprite width, so they visibly overlapped. 170 leaves a
## clear gap between two houses placed at the minimum distance.
const HOUSE_MIN_SPACING := 170.0
const KINGDOM_AREA_MULT := 1.3

## How close a click has to land to an already-placed house to select it
## for the Move/Remove tools - half House1.png's 128px width plus a bit of
## forgiveness, not full collision geometry.
const HOUSE_SELECT_RADIUS := 70.0

## Same rough-spacing idea as houses, sized for the pen's 160px fence
## footprint (see sheep_pen.gd's pen_size).
const SHEEP_PEN_MIN_SPACING := 200.0
const SHEEP_PEN_WOOD_COST := 40
const SHEEP_PEN_GOLD_COST := 20

@onready var skills_tab_button: BaseButton = $TabStrip/SkillsTabButton
@onready var abilities_tab_button: BaseButton = $TabStrip/AbilitiesTabButton
@onready var village_tab_button: BaseButton = $TabStrip/VillageTabButton
@onready var pawns_tab_button: BaseButton = $TabStrip/PawnsTabButton
@onready var options_tab_button: BaseButton = $TabStrip/OptionsTabButton

@onready var skills_panel: Control = $SkillsPanel
@onready var abilities_panel: Control = $AbilitiesPanel
@onready var village_panel: Control = $VillagePanel
@onready var pawns_panel: Control = $PawnsPanel
@onready var options_panel: Control = $OptionsPanel

## Always-visible readout by the minimap instead of needing to open a tab
## to see these - replaced the old Inventory and Stats tabs entirely.
@onready var resource_wood_count: Label = $OrbGrid/WoodOrb/Count
@onready var resource_stone_count: Label = $OrbGrid/StoneOrb/Count
@onready var resource_gold_count: Label = $OrbGrid/GoldOrb/Count
@onready var resource_meat_count: Label = $OrbGrid/MeatOrb/Count
@onready var resource_pawns_count: Label = $OrbGrid/PawnsOrb/Count

@onready var repair_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/RepairButton
@onready var health_upgrade_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/HealthUpgradeButton
@onready var fire_rate_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/FireRateButton
@onready var damage_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/DamageButton
@onready var range_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/RangeButton
@onready var wood_drop_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/WoodDropButton
@onready var gold_drop_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/GoldDropButton
@onready var luck_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/LuckButton
@onready var population_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/PopulationButton

@onready var combat_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/CombatCatButton
@onready var fortify_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/FortifyCatButton
@onready var wood_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/WoodCatButton
@onready var coin_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/CoinCatButton
@onready var growth_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/GrowthCatButton
@onready var category_label: Label = $SkillsPanel/ScrollContainer/VBox/CategoryLabel
@onready var passive_skills_row: HBoxContainer = $SkillsPanel/ScrollContainer/VBox/DetailContainer/PassiveSkillsRow

@onready var volley_unlock_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/VolleyUnlockButton
@onready var volley_power_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/VolleyPowerButton
@onready var volley_fire_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/VolleyFireButton
@onready var storm_unlock_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/StormUnlockButton
@onready var storm_power_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/StormPowerButton
@onready var storm_fire_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/StormFireButton

@onready var fullscreen_button: BaseButton = $OptionsPanel/ScrollContainer/VBox/FullscreenButton
@onready var quit_button: BaseButton = $OptionsPanel/ScrollContainer/VBox/QuitButton

@onready var day_night_label: Label = $Minimap/DayLabel

@onready var pawns_label: Label = $VillagePanel/ScrollContainer/VBox/PawnsLabel
@onready var place_house_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PlaceHouseButton
@onready var place_pen_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PlacePenButton
@onready var house_style_buttons: Array[BaseButton] = [
	$VillagePanel/ScrollContainer/VBox/HouseStyleGrid/Style1Button,
	$VillagePanel/ScrollContainer/VBox/HouseStyleGrid/Style2Button,
	$VillagePanel/ScrollContainer/VBox/HouseStyleGrid/Style3Button,
]
@onready var house_cap_label: Label = $VillagePanel/ScrollContainer/VBox/HouseCapLabel
@onready var selected_house_label: Label = $VillagePanel/ScrollContainer/VBox/SelectedHouseLabel
@onready var move_house_button: BaseButton = $VillagePanel/ScrollContainer/VBox/MoveHouseButton
@onready var remove_house_button: BaseButton = $VillagePanel/ScrollContainer/VBox/RemoveHouseButton
@onready var pawn_health_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PawnHealthButton
@onready var pawn_carry_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PawnCarryButton
@onready var pawn_speed_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PawnSpeedButton
@onready var mining_speed_button: BaseButton = $VillagePanel/ScrollContainer/VBox/MiningSpeedButton
@onready var click_power_button: BaseButton = $VillagePanel/ScrollContainer/VBox/ClickPowerButton
@onready var village_locked_hint: Label = $VillagePanel/ScrollContainer/VBox/LockedHint

@onready var pawns_selected_label: Label = $PawnsPanel/ScrollContainer/VBox/SelectedLabel
@onready var total_pawns_label: Label = $PawnsPanel/ScrollContainer/VBox/TotalPawnsLabel
## Row -> {count_label, minus, plus} for each specialist job's +/- counter
## in the Pawns tab (see GameManager.pawn_job_targets/reconcile_pawn_jobs).
@onready var job_allocator_rows: Dictionary = {
	Pawn.Job.WOOD: $PawnsPanel/ScrollContainer/VBox/JobAllocator/WoodRow,
	Pawn.Job.STONE: $PawnsPanel/ScrollContainer/VBox/JobAllocator/StoneRow,
	Pawn.Job.HAULER: $PawnsPanel/ScrollContainer/VBox/JobAllocator/HaulRow,
	Pawn.Job.HUNTER: $PawnsPanel/ScrollContainer/VBox/JobAllocator/HuntRow,
}
@onready var select_all_button: BaseButton = $PawnsPanel/ScrollContainer/VBox/SelectAllButton
@onready var recall_all_button: BaseButton = $PawnsPanel/ScrollContainer/VBox/RecallAllButton

var _all_panels: Array[Control]
var _placing_house := false
var _placing_pen := false
var _house_style_index := 0
var _placement_reticle: Node2D = null
var _relocating_house: Node = null
var _selected_house: Node = null

## RuneScape-style Skills tab: one icon per category, only the selected
## category's buttons are shown below the grid at a time - built from
## the same buttons/incrementals as before, just grouped instead of one
## long always-visible list.
var _skill_categories: Dictionary = {}
var _selected_category: String = "combat"


func _ready() -> void:
	add_to_group("hud_tabs")
	_all_panels = [skills_panel, abilities_panel, village_panel, pawns_panel, options_panel]
	for panel in _all_panels:
		panel.visible = false

	skills_tab_button.tooltip_text = "Skills & Upgrades"
	abilities_tab_button.tooltip_text = "Abilities"
	village_tab_button.tooltip_text = "Village"
	pawns_tab_button.tooltip_text = "Pawns"
	options_tab_button.tooltip_text = "Options"

	skills_tab_button.pressed.connect(_on_tab_pressed.bind(skills_panel))
	abilities_tab_button.pressed.connect(_on_tab_pressed.bind(abilities_panel))
	village_tab_button.pressed.connect(_on_tab_pressed.bind(village_panel))
	pawns_tab_button.pressed.connect(_on_tab_pressed.bind(pawns_panel))
	options_tab_button.pressed.connect(_on_tab_pressed.bind(options_panel))
	quit_button.pressed.connect(_on_quit_pressed)
	fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	_refresh_fullscreen_label()
	repair_button.pressed.connect(_on_repair_pressed)
	health_upgrade_button.pressed.connect(_on_health_upgrade_pressed)
	fire_rate_button.pressed.connect(_on_buy_incremental.bind("fire_rate"))
	damage_button.pressed.connect(_on_buy_incremental.bind("damage"))
	range_button.pressed.connect(_on_buy_incremental.bind("range"))
	wood_drop_button.pressed.connect(_on_buy_incremental.bind("wood_drop"))
	gold_drop_button.pressed.connect(_on_buy_incremental.bind("gold_drop"))
	luck_button.pressed.connect(_on_buy_incremental.bind("luck"))
	population_button.pressed.connect(_on_buy_incremental.bind("population"))
	place_house_button.pressed.connect(_on_place_house_pressed)
	place_pen_button.pressed.connect(_on_place_pen_pressed)
	move_house_button.pressed.connect(_on_move_house_pressed)
	remove_house_button.pressed.connect(_on_remove_house_pressed)
	for i in house_style_buttons.size():
		house_style_buttons[i].pressed.connect(_on_house_style_pressed.bind(i))
	pawn_health_button.pressed.connect(_on_buy_incremental.bind("pawn_health"))
	pawn_carry_button.pressed.connect(_on_buy_incremental.bind("pawn_carry"))
	pawn_speed_button.pressed.connect(_on_buy_incremental.bind("pawn_speed"))
	mining_speed_button.pressed.connect(_on_buy_incremental.bind("mining_speed"))
	click_power_button.pressed.connect(_on_buy_incremental.bind("click_power"))
	select_all_button.pressed.connect(_on_select_all_pressed)
	recall_all_button.pressed.connect(_on_recall_all_pressed)
	for j in job_allocator_rows:
		var row: HBoxContainer = job_allocator_rows[j]
		row.get_node("MinusButton").pressed.connect(_on_job_target_step.bind(j, -1))
		row.get_node("PlusButton").pressed.connect(_on_job_target_step.bind(j, 1))

	var gm_pawn_jobs: Node = get_tree().get_first_node_in_group("game_manager")
	if gm_pawn_jobs:
		gm_pawn_jobs.pawn_job_targets_changed.connect(_refresh_job_allocator)

	_skill_categories = {
		"combat": {"label": "Combat - Tower Fire Rate, Damage & Range", "button": combat_cat_button, "items": [fire_rate_button, damage_button, range_button]},
		"fortify": {"label": "Fortify - Repair & Max Health", "button": fortify_cat_button, "items": [repair_button, health_upgrade_button]},
		"wood": {"label": "Woodcutting - Wood Drop Rate", "button": wood_cat_button, "items": [wood_drop_button]},
		"coin": {"label": "Coin - Gold Drop Rate & Luck", "button": coin_cat_button, "items": [gold_drop_button, luck_button]},
		"growth": {"label": "Growth - Population", "button": growth_cat_button, "items": [population_button]},
	}
	for cat_id in _skill_categories:
		_skill_categories[cat_id]["button"].pressed.connect(_select_category.bind(cat_id))
	_select_category(_selected_category)

	volley_unlock_button.pressed.connect(_on_ability_action.bind("volley_shot", "unlock"))
	volley_power_button.pressed.connect(_on_ability_action.bind("volley_shot", "power"))
	volley_fire_button.pressed.connect(_on_ability_action.bind("volley_shot", "fire"))
	storm_unlock_button.pressed.connect(_on_ability_action.bind("arrow_storm", "unlock"))
	storm_power_button.pressed.connect(_on_ability_action.bind("arrow_storm", "power"))
	storm_fire_button.pressed.connect(_on_ability_action.bind("arrow_storm", "fire"))

	var gm_incrementals: Node = get_tree().get_first_node_in_group("game_manager")
	if gm_incrementals:
		gm_incrementals.incrementals_changed.connect(_refresh_incrementals)
		gm_incrementals.skill_tree_changed.connect(func(): _rebuild_passive_skills(_selected_category))
		gm_incrementals.skill_tree_changed.connect(_refresh_village)

	var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
	if ability_system:
		ability_system.ability_unlocked.connect(func(_id): _refresh_abilities())
		ability_system.ability_upgraded.connect(func(_id, _branch, _level): _refresh_abilities())
	_refresh_abilities()

	var pawn_controller: Node = get_tree().get_first_node_in_group("pawn_controller")
	if pawn_controller:
		pawn_controller.selection_changed.connect(_on_pawn_selection_changed)

	for tab_button in [skills_tab_button, abilities_tab_button, village_tab_button, pawns_tab_button, options_tab_button]:
		tab_button.pivot_offset = tab_button.size / 2.0
		tab_button.mouse_entered.connect(_on_tab_hover_start.bind(tab_button))
		tab_button.mouse_exited.connect(_on_tab_hover_end.bind(tab_button))

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.gold_changed.connect(_on_stat_changed)
		gm.wood_changed.connect(_on_stat_changed)
		gm.stone_changed.connect(_on_stat_changed)
		gm.meat_changed.connect(_on_stat_changed)

	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.wave_started.connect(_on_stat_changed)
		spawner.wave_started.connect(_on_wave_started)
		spawner.wave_cleared.connect(_on_stat_changed)

	var day_cycle: Node = get_tree().get_first_node_in_group("day_night_cycle")
	if day_cycle:
		day_cycle.phase_changed.connect(_on_phase_changed)
		day_cycle.horde_warning.connect(_on_horde_warning)
		## All-towers-built (which unlocks houses) usually happens on a
		## Night->Day transition via KingdomManager's wave_cleared hook, so
		## re-check the Village panel's lock state on every phase change too.
		day_cycle.phase_changed.connect(func(_p, _d): _refresh_village())

	_refresh_resources()
	_refresh_incrementals()
	_refresh_village()


## Called by the merchant panel so it doesn't end up overlapping whichever
## HUD tab was left open when a wave clears.
func close_all_panels() -> void:
	for panel in _all_panels:
		panel.visible = false


func _on_tab_hover_start(tab_button: Control) -> void:
	var tween := create_tween()
	tween.tween_property(tab_button, "scale", Vector2(1.1, 1.1), 0.1)


func _on_tab_hover_end(tab_button: Control) -> void:
	var tween := create_tween()
	tween.tween_property(tab_button, "scale", Vector2.ONE, 0.1)


func _on_tab_pressed(panel: Control) -> void:
	var was_open := panel.visible
	for p in _all_panels:
		p.visible = false
	panel.visible = not was_open
	if panel.visible:
		_refresh_resources()
		_refresh_village()


func _select_category(cat_id: String) -> void:
	if not _skill_categories.has(cat_id):
		return
	_selected_category = cat_id
	for id in _skill_categories:
		var data: Dictionary = _skill_categories[id]
		var is_selected: bool = id == cat_id
		data["button"].modulate = Color(1, 1, 1) if is_selected else Color(0.65, 0.65, 0.65)
		for item in data["items"]:
			item.visible = is_selected
	category_label.text = _skill_categories[cat_id]["label"]
	_rebuild_passive_skills(cat_id)


## Rebuilds the Passive Skills row for the selected category from
## GameManager.SKILL_TREE - a plain button per node with a "->" arrow
## between them (a simple visual chain instead of a full node-graph
## renderer), locked/greyed until its prerequisite is unlocked.
func _rebuild_passive_skills(cat_id: String) -> void:
	for child in passive_skills_row.get_children():
		child.queue_free()

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	var nodes: Array = gm.SKILL_TREE.get(cat_id, [])
	for i in nodes.size():
		var node: Dictionary = nodes[i]
		if i > 0:
			var arrow := Label.new()
			arrow.text = "->"
			arrow.add_theme_color_override("font_color", Color(0.4, 0.25, 0.1, 1))
			passive_skills_row.add_child(arrow)

		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var unlocked: bool = gm.skill_node_unlocked(node.id)
		var available: bool = gm.skill_node_available(node)
		button.disabled = unlocked or not available
		if unlocked:
			button.text = "%s (unlocked)\n%s" % [node.name, node.desc]
			button.modulate = Color(0.6, 0.9, 0.6)
		elif available:
			button.text = "%s - %s\n%s" % [node.name, gm.format_cost(node.cost), node.desc]
		else:
			button.text = "%s (locked)" % node.name
			button.modulate = Color(0.6, 0.6, 0.6)
		button.pressed.connect(_on_skill_node_pressed.bind(cat_id, node.id, button))
		passive_skills_row.add_child(button)


func _on_skill_node_pressed(cat_id: String, node_id: String, button: BaseButton) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	if not gm.buy_skill_node(cat_id, node_id):
		var tween := create_tween()
		tween.tween_property(button, "modulate", Color(1, 0.4, 0.4), 0.1)
		tween.tween_property(button, "modulate", Color(1, 1, 1), 0.15)


func _on_select_all_pressed() -> void:
	var pawn_controller: Node = get_tree().get_first_node_in_group("pawn_controller")
	if pawn_controller:
		pawn_controller.select_all()


func _on_recall_all_pressed() -> void:
	var pawn_controller: Node = get_tree().get_first_node_in_group("pawn_controller")
	if pawn_controller:
		pawn_controller.recall_all()


func _on_pawn_selection_changed(count: int) -> void:
	pawns_selected_label.text = "Selected: %d" % count


## Count-based job allocation (Pawns tab) - the player just says how many
## pawns should be doing each job and GameManager.reconcile_pawn_jobs()
## drafts/releases Generalists to match, rather than the player having to
## click individual pawns in the world and assign them one at a time.
func _on_job_target_step(job: Pawn.Job, delta: int) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	var current: int = gm.pawn_job_targets.get(job, 0)
	gm.set_pawn_job_target(job, current + delta)


func _refresh_job_allocator() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var total: int = get_tree().get_nodes_in_group("pawn").size()
	var assigned := 0
	for job in job_allocator_rows:
		var target: int = gm.pawn_job_targets.get(job, 0) if gm else 0
		assigned += target
		var row: HBoxContainer = job_allocator_rows[job]
		row.get_node("CountLabel").text = str(target)
	total_pawns_label.text = "Total Pawns: %d (%d unassigned)" % [total, maxi(0, total - assigned)]


func _on_stat_changed(_value=null) -> void:
	_refresh_resources()
	_refresh_village()


var _current_day_number: int = 1


func _on_phase_changed(phase: int, day_number: int) -> void:
	_current_day_number = day_number
	var phase_text := "Night" if phase == 1 else "Day"  # DayNightCycle.Phase.NIGHT == 1
	day_night_label.text = "Day %d\n%s" % [day_number, phase_text]
	day_night_label.modulate = Color(1, 1, 1) if phase_text == "Day" else Color(0.75, 0.8, 1.0)


## wave_started fires from inside EnemySpawner.start_wave() - after
## current_wave has already been incremented, unlike phase_changed (which
## fires before start_wave() is even called) - so this is the signal to
## use for an accurate wave number rather than computing it in
## _on_phase_changed, which would show the previous wave for a moment.
func _on_wave_started(wave_number: int) -> void:
	day_night_label.text = "Day %d\nNight (Wave %d)" % [_current_day_number, wave_number]


func _on_horde_warning(_day_number: int) -> void:
	day_night_label.text += "\nHORDE!"
	var tween := create_tween()
	tween.set_loops(4)
	tween.tween_property(day_night_label, "modulate", Color(1, 0.3, 0.3), 0.3)
	tween.tween_property(day_night_label, "modulate", Color(0.85, 0.85, 1.0), 0.3)


## Drives the always-visible readout by the minimap - replaces the old
## Inventory and Stats tabs, which just duplicated these same numbers
## behind an extra click.
func _refresh_resources() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	resource_wood_count.text = str(gm.wood if gm else 0)
	resource_stone_count.text = str(gm.stone if gm else 0)
	resource_gold_count.text = str(gm.gold if gm else 0)
	resource_meat_count.text = str(gm.meat if gm else 0)
	resource_pawns_count.text = str(get_tree().get_nodes_in_group("pawn").size())
	_refresh_job_allocator()


## These buttons live in a UI panel, not hovering over the world like the
## old hotbar did, so "nearest tower to mouse" doesn't mean anything here -
## the mouse is just wherever the button is. Pick a sensible target instead:
## the most damaged tower for repair, the weakest tower for a health upgrade.
func _most_damaged_tower() -> Node:
	var best: Node = null
	var best_missing := 0
	for tower in get_tree().get_nodes_in_group("tower"):
		if not is_instance_valid(tower) or not tower.has_method("needs_repair"):
			continue
		if not tower.needs_repair():
			continue
		var missing: int = tower.max_health - tower.current_health
		if missing > best_missing:
			best_missing = missing
			best = tower
	return best


func _weakest_tower() -> Node:
	var best: Node = null
	var best_max_health := INF
	for tower in get_tree().get_nodes_in_group("tower"):
		if not is_instance_valid(tower) or ("is_destroyed" in tower and tower.is_destroyed):
			continue
		if tower.max_health < best_max_health:
			best_max_health = tower.max_health
			best = tower
	return best


func _on_repair_pressed() -> void:
	var tower: Node = _most_damaged_tower()
	if tower and tower.has_method("try_repair"):
		tower.try_repair()


func _on_health_upgrade_pressed() -> void:
	var tower: Node = _weakest_tower()
	if tower and tower.has_method("try_upgrade_health"):
		tower.try_upgrade_health()


func _refresh_incrementals() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	fire_rate_button.text = "Fire Rate Up (Lv %d) - %s" % [gm.fire_rate_level, gm.format_cost(gm.fire_rate_cost())]
	damage_button.text = "Arrow Damage Up (Lv %d) - %s" % [gm.damage_level, gm.format_cost(gm.damage_cost())]
	range_button.text = "Archer Range Up (Lv %d) - %s" % [gm.range_level, gm.format_cost(gm.range_cost())]
	wood_drop_button.text = "Wood Drop Rate Up (Lv %d) - %s" % [gm.wood_drop_level, gm.format_cost(gm.wood_drop_cost())]
	gold_drop_button.text = "Gold Drop Rate Up (Lv %d) - %s" % [gm.gold_drop_level, gm.format_cost(gm.gold_drop_cost())]
	luck_button.text = "Luck Up (Lv %d) - %s" % [gm.luck_level, gm.format_cost(gm.luck_cost())]
	population_button.text = "Population Up (Lv %d) - %s" % [gm.population_level, gm.format_cost(gm.population_cost())]
	_refresh_village()


## effect: which GameManager.buy_*() incremental to call - kept as a
## string so a single handler can bind to all four buttons instead of
## four near-identical callbacks.
func _on_buy_incremental(effect: String) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	var bought := false
	var button: BaseButton = null
	match effect:
		"fire_rate":
			button = fire_rate_button
			bought = gm.buy_fire_rate()
		"damage":
			button = damage_button
			bought = gm.buy_damage()
		"range":
			button = range_button
			bought = gm.buy_range()
		"wood_drop":
			button = wood_drop_button
			bought = gm.buy_wood_drop()
		"gold_drop":
			button = gold_drop_button
			bought = gm.buy_gold_drop()
		"luck":
			button = luck_button
			bought = gm.buy_luck()
		"population":
			button = population_button
			bought = gm.buy_population()
		"pawn_health":
			button = pawn_health_button
			bought = gm.buy_pawn_health()
		"pawn_carry":
			button = pawn_carry_button
			bought = gm.buy_pawn_carry()
		"pawn_speed":
			button = pawn_speed_button
			bought = gm.buy_pawn_speed()
		"mining_speed":
			button = mining_speed_button
			bought = gm.buy_mining_speed()
		"click_power":
			button = click_power_button
			bought = gm.buy_click_power()

	if not bought and button:
		var tween := create_tween()
		tween.tween_property(button, "modulate", Color(1, 0.4, 0.4), 0.1)
		tween.tween_property(button, "modulate", Color(1, 1, 1), 0.15)
	## incrementals_changed (emitted by every successful buy_*()) refreshes
	## the button labels - no need to do it here too.


func _refresh_abilities() -> void:
	var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
	if ability_system == null:
		return
	_refresh_ability_row("volley_shot", volley_unlock_button, volley_power_button, volley_fire_button, ability_system)
	_refresh_ability_row("arrow_storm", storm_unlock_button, storm_power_button, storm_fire_button, ability_system)


func _refresh_ability_row(id: String, unlock_button: BaseButton, power_button: BaseButton, fire_button: BaseButton, ability_system: Node) -> void:
	var unlocked: bool = ability_system.is_unlocked(id)
	unlock_button.disabled = unlocked
	unlock_button.text = "Unlocked" if unlocked else "Unlock - %d Wood" % ability_system.unlock_cost(id)
	power_button.disabled = not unlocked
	power_button.text = "Power Up (Lv %d) - %d Wood" % [ability_system.power_level[id], ability_system.power_cost(id)]
	fire_button.disabled = not unlocked
	fire_button.text = "Fire Branch (Lv %d) - %d Wood" % [ability_system.fire_level[id], ability_system.fire_cost(id)]


## action: "unlock", "power", or "fire" - which AbilitySystem call to make
## for the given ability id.
func _on_ability_action(id: String, action: String) -> void:
	var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
	if ability_system == null:
		return
	var bought := false
	var button: BaseButton = null
	match action:
		"unlock":
			button = volley_unlock_button if id == "volley_shot" else storm_unlock_button
			bought = ability_system.unlock(id)
		"power":
			button = volley_power_button if id == "volley_shot" else storm_power_button
			bought = ability_system.upgrade_power(id)
		"fire":
			button = volley_fire_button if id == "volley_shot" else storm_fire_button
			bought = ability_system.upgrade_fire(id)

	if not bought and button:
		var tween := create_tween()
		tween.tween_property(button, "modulate", Color(1, 0.4, 0.4), 0.1)
		tween.tween_property(button, "modulate", Color(1, 1, 1), 0.15)
	## ability_unlocked/ability_upgraded (connected in _ready) call
	## _refresh_abilities() on success - nothing more to do here.


func _on_fullscreen_pressed() -> void:
	var is_fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_refresh_fullscreen_label()


func _refresh_fullscreen_label() -> void:
	var is_fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_button.text = "Fullscreen: On" if is_fullscreen else "Fullscreen: Off"


func _refresh_village() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	pawns_label.text = "Pawns: %d" % get_tree().get_nodes_in_group("pawn").size()
	pawn_health_button.text = "Pawn Health Up (Lv %d) - %s" % [gm.pawn_health_level, gm.format_cost(gm.pawn_health_cost())]
	pawn_carry_button.text = "Pawn Carry Up (Lv %d) - %s" % [gm.pawn_carry_level, gm.format_cost(gm.pawn_carry_cost())]
	pawn_speed_button.text = "Pawn Speed Up (Lv %d) - %s" % [gm.pawn_speed_level, gm.format_cost(gm.pawn_speed_cost())]
	mining_speed_button.text = "Mining Speed Up (Lv %d) - %s" % [gm.mining_speed_level, gm.format_cost(gm.mining_speed_cost())]
	click_power_button.text = "Click Power Up (Lv %d) - %s" % [gm.click_power_level, gm.format_cost(gm.click_power_cost())]

	var unlocked: bool = gm.houses_unlocked()
	var cap: int = gm.house_cap()
	var count: int = _current_house_count()
	village_locked_hint.visible = not unlocked
	place_house_button.disabled = not unlocked or _placing_house or count >= cap
	if _placing_house:
		place_house_button.text = "Placing... (click the map)"
	elif unlocked and count >= cap:
		place_house_button.text = "Houses Full (%d/%d)" % [count, cap]
	else:
		place_house_button.text = "Place House (%d Wood, %d Gold)" % [gm.HOUSE_WOOD_COST, gm.HOUSE_GOLD_COST]
	house_cap_label.visible = unlocked
	house_cap_label.text = "Houses: %d / %d" % [count, cap]

	place_pen_button.disabled = not unlocked or _placing_pen
	place_pen_button.text = "Placing... (click the map)" if _placing_pen else "Place Sheep Pen (%d Wood, %d Gold)" % [SHEEP_PEN_WOOD_COST, SHEEP_PEN_GOLD_COST]

	_refresh_house_selection_ui()


func _current_house_count() -> int:
	return get_tree().get_nodes_in_group("house").size()


func _on_place_house_pressed() -> void:
	if _placing_house:
		return
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null or not gm.houses_unlocked():
		return
	if _current_house_count() >= gm.house_cap():
		return
	if gm.wood < gm.HOUSE_WOOD_COST or gm.gold < gm.HOUSE_GOLD_COST:
		var tween := create_tween()
		tween.tween_property(place_house_button, "modulate", Color(1, 0.4, 0.4), 0.1)
		tween.tween_property(place_house_button, "modulate", Color(1, 1, 1), 0.15)
		return
	_relocating_house = null
	_placing_house = true
	_refresh_village()


## --- Move/Remove/Reskin an already-placed house -------------------------

func _on_house_style_pressed(i: int) -> void:
	_house_style_index = i
	if _selected_house != null and is_instance_valid(_selected_house) and _selected_house.has_method("set_house_texture"):
		_selected_house.set_house_texture(HOUSE_TEXTURES[i])


func _on_move_house_pressed() -> void:
	if _selected_house == null or not is_instance_valid(_selected_house):
		return
	_relocating_house = _selected_house
	_placing_house = true
	_refresh_village()


func _on_remove_house_pressed() -> void:
	if _selected_house == null or not is_instance_valid(_selected_house):
		return
	var house: Node = _selected_house
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.add_wood(int(round(gm.HOUSE_WOOD_COST * gm.HOUSE_REMOVE_REFUND_MULT)))
		gm.add_gold(int(round(gm.HOUSE_GOLD_COST * gm.HOUSE_REMOVE_REFUND_MULT)))
	_rehome_or_release_pawns(house)
	_select_house(null)
	house.queue_free()
	_refresh_village()


## Whatever pawns lived in a removed house move in with the nearest other
## house instead of just vanishing - if there isn't one left, they've got
## nowhere to shelter and are lost, same as any pawn caught out with no
## home to run to.
func _rehome_or_release_pawns(house: Node) -> void:
	for pawn in house.pawns.duplicate():
		if not is_instance_valid(pawn):
			continue
		var new_home: Node = _nearest_other_house(pawn.global_position, house)
		if new_home and new_home.has_method("adopt_pawn"):
			pawn.home_house = new_home
			new_home.adopt_pawn(pawn)
			if pawn.has_method("command_recall"):
				pawn.command_recall()
		else:
			pawn.queue_free()


func _nearest_other_house(from_pos: Vector2, exclude: Node) -> Node:
	var nearest: Node = null
	var nearest_dist := INF
	for h in get_tree().get_nodes_in_group("house"):
		if h == exclude or not is_instance_valid(h):
			continue
		var dist: float = from_pos.distance_to(h.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = h
	return nearest


func _find_house_near(pos: Vector2) -> Node:
	var nearest: Node = null
	var nearest_dist := HOUSE_SELECT_RADIUS
	for h in get_tree().get_nodes_in_group("house"):
		if not is_instance_valid(h):
			continue
		var dist: float = pos.distance_to(h.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = h
	return nearest


func _select_house(house: Node) -> void:
	if _selected_house != null and is_instance_valid(_selected_house) and _selected_house.has_method("set_selected"):
		_selected_house.set_selected(false)
	_selected_house = house
	if _selected_house != null and _selected_house.has_method("set_selected"):
		_selected_house.set_selected(true)
	_refresh_house_selection_ui()


func _refresh_house_selection_ui() -> void:
	var has_selection: bool = _selected_house != null and is_instance_valid(_selected_house)
	if not has_selection:
		_selected_house = null
	selected_house_label.visible = has_selection
	move_house_button.visible = has_selection
	remove_house_button.visible = has_selection
	if has_selection:
		selected_house_label.text = "Selected House (%d Pawns)" % _selected_house.pawns.size()


func _process(_delta: float) -> void:
	if not (_placing_house or _placing_pen):
		if _placement_reticle:
			_placement_reticle.queue_free()
			_placement_reticle = null
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if _placement_reticle == null:
		_placement_reticle = Node2D.new()
		_placement_reticle.set_script(RETICLE_SCRIPT)
		_placement_reticle.radius = (SHEEP_PEN_MIN_SPACING if _placing_pen else HOUSE_MIN_SPACING) * 0.5
		get_tree().current_scene.add_child(_placement_reticle)
	_placement_reticle.global_position = cam.get_global_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if _placing_house:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var cam := get_viewport().get_camera_2d()
				if cam:
					_try_place_house(cam.get_global_mouse_position())
				_placing_house = false
				_relocating_house = null
				_refresh_village()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_placing_house = false
				_relocating_house = null
				_refresh_village()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_placing_house = false
			_relocating_house = null
			_refresh_village()
		return

	if _placing_pen:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var cam := get_viewport().get_camera_2d()
				if cam:
					_try_place_pen(cam.get_global_mouse_position())
				_placing_pen = false
				_refresh_village()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_placing_pen = false
				_refresh_village()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_placing_pen = false
			_refresh_village()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return
		_select_house(_find_house_near(cam.get_global_mouse_position()))


## Rough placement validity - inside the kingdom's general area and not
## overlapping another house or tower - rather than full collision
## geometry against every building shape. exclude lets a house being
## relocated ignore its own old spot when checking spacing against itself.
func _is_valid_house_spot(pos: Vector2, exclude: Node = null) -> bool:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	if km == null:
		return false
	var center: Vector2 = km.to_global(km.center)
	if pos.distance_to(center) > km.radius * KINGDOM_AREA_MULT:
		return false
	for h in get_tree().get_nodes_in_group("house"):
		if h != exclude and is_instance_valid(h) and pos.distance_to(h.global_position) < HOUSE_MIN_SPACING:
			return false
	for t in get_tree().get_nodes_in_group("tower"):
		if is_instance_valid(t) and pos.distance_to(t.global_position) < HOUSE_MIN_SPACING:
			return false
	return true


func _try_place_house(pos: Vector2) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return

	if _relocating_house != null and is_instance_valid(_relocating_house):
		if not _is_valid_house_spot(pos, _relocating_house):
			return
		_relocating_house.global_position = pos
		_relocating_house = null
		return

	if not _is_valid_house_spot(pos) or _current_house_count() >= gm.house_cap():
		return
	if not gm.spend_wood(gm.HOUSE_WOOD_COST):
		return
	if not gm.spend_gold(gm.HOUSE_GOLD_COST):
		gm.add_wood(gm.HOUSE_WOOD_COST)  # refund - gold check failed after wood already spent
		return

	var house := HOUSE_SCENE.instantiate()
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	(container if container else get_tree().current_scene).add_child(house)
	## set_house_texture() touches an @onready sprite var, only valid once
	## _ready() has run - which add_child() triggers synchronously, so this
	## must come after add_child(), not before.
	if house.has_method("set_house_texture"):
		house.set_house_texture(HOUSE_TEXTURES[_house_style_index])
	house.global_position = pos
	_refresh_village()


## --- Sheep Pen placement --------------------------------------------------

func _on_place_pen_pressed() -> void:
	if _placing_pen:
		return
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null or not gm.houses_unlocked():
		return
	if gm.wood < SHEEP_PEN_WOOD_COST or gm.gold < SHEEP_PEN_GOLD_COST:
		var tween := create_tween()
		tween.tween_property(place_pen_button, "modulate", Color(1, 0.4, 0.4), 0.1)
		tween.tween_property(place_pen_button, "modulate", Color(1, 1, 1), 0.15)
		return
	_placing_pen = true
	_refresh_village()


func _is_valid_pen_spot(pos: Vector2) -> bool:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	if km == null:
		return false
	var center: Vector2 = km.to_global(km.center)
	if pos.distance_to(center) > km.radius * KINGDOM_AREA_MULT:
		return false
	for h in get_tree().get_nodes_in_group("house"):
		if is_instance_valid(h) and pos.distance_to(h.global_position) < SHEEP_PEN_MIN_SPACING:
			return false
	for t in get_tree().get_nodes_in_group("tower"):
		if is_instance_valid(t) and pos.distance_to(t.global_position) < SHEEP_PEN_MIN_SPACING:
			return false
	for p in get_tree().get_nodes_in_group("sheep_pen"):
		if is_instance_valid(p) and pos.distance_to(p.global_position) < SHEEP_PEN_MIN_SPACING:
			return false
	return true


func _try_place_pen(pos: Vector2) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null or not _is_valid_pen_spot(pos):
		return
	if not gm.spend_wood(SHEEP_PEN_WOOD_COST):
		return
	if not gm.spend_gold(SHEEP_PEN_GOLD_COST):
		gm.add_wood(SHEEP_PEN_WOOD_COST)  # refund - gold check failed after wood already spent
		return

	var pen := SHEEP_PEN_SCENE.instantiate()
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	(container if container else get_tree().current_scene).add_child(pen)
	pen.global_position = pos
	_refresh_village()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
