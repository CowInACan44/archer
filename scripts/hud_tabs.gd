extends CanvasLayer

## RuneScape-style HUD: a small tab strip that opens Inventory/Stats/Options
## panels on demand instead of keeping everything on screen all the time.
## Only one panel is open at a time.

const HOUSE_SCENE := preload("res://scenes/house.tscn")
const RETICLE_SCRIPT := preload("res://scripts/ability_reticle.gd")

## How far from another house/tower a new house must be, and how far
## outside the octagon's radius counts as "still inside the kingdom" -
## rough placement validity instead of full collision geometry.
## House1.png is 128px wide - 100 let houses' centers land closer together
## than their own sprite width, so they visibly overlapped. 170 leaves a
## clear gap between two houses placed at the minimum distance.
const HOUSE_MIN_SPACING := 170.0
const KINGDOM_AREA_MULT := 1.3

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
@onready var resource_wood_count: Label = $ResourceReadout/VBox/WoodRow/Count
@onready var resource_stone_count: Label = $ResourceReadout/VBox/StoneRow/Count
@onready var resource_gold_count: Label = $ResourceReadout/VBox/GoldRow/Count

@onready var repair_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/RepairButton
@onready var health_upgrade_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/HealthUpgradeButton
@onready var fire_rate_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/FireRateButton
@onready var damage_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/DamageButton
@onready var range_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/RangeButton
@onready var wood_drop_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/WoodDropButton
@onready var gold_drop_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/GoldDropButton
@onready var population_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/DetailContainer/PopulationButton

@onready var combat_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/CombatCatButton
@onready var fortify_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/FortifyCatButton
@onready var wood_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/WoodCatButton
@onready var coin_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/CoinCatButton
@onready var growth_cat_button: BaseButton = $SkillsPanel/ScrollContainer/VBox/CategoryGrid/GrowthCatButton
@onready var category_label: Label = $SkillsPanel/ScrollContainer/VBox/CategoryLabel

@onready var volley_unlock_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/VolleyUnlockButton
@onready var volley_power_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/VolleyPowerButton
@onready var volley_fire_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/VolleyFireButton
@onready var storm_unlock_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/StormUnlockButton
@onready var storm_power_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/StormPowerButton
@onready var storm_fire_button: BaseButton = $AbilitiesPanel/ScrollContainer/VBox/StormFireButton

@onready var fullscreen_button: BaseButton = $OptionsPanel/ScrollContainer/VBox/FullscreenButton
@onready var quit_button: BaseButton = $OptionsPanel/ScrollContainer/VBox/QuitButton

@onready var day_night_label: Label = $DayNightWidget/Label
@onready var clock_bar_fill: ColorRect = $DayNightWidget/ClockBar/BarFill

@onready var pawns_label: Label = $VillagePanel/ScrollContainer/VBox/PawnsLabel
@onready var place_house_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PlaceHouseButton
@onready var pawn_health_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PawnHealthButton
@onready var pawn_carry_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PawnCarryButton
@onready var pawn_speed_button: BaseButton = $VillagePanel/ScrollContainer/VBox/PawnSpeedButton
@onready var mining_speed_button: BaseButton = $VillagePanel/ScrollContainer/VBox/MiningSpeedButton
@onready var click_power_button: BaseButton = $VillagePanel/ScrollContainer/VBox/ClickPowerButton
@onready var village_locked_hint: Label = $VillagePanel/ScrollContainer/VBox/LockedHint

@onready var pawns_selected_label: Label = $PawnsPanel/ScrollContainer/VBox/SelectedLabel
@onready var select_all_button: BaseButton = $PawnsPanel/ScrollContainer/VBox/SelectAllButton
@onready var recall_all_button: BaseButton = $PawnsPanel/ScrollContainer/VBox/RecallAllButton

var _all_panels: Array[Control]
var _placing_house := false
var _placement_reticle: Node2D = null

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
	population_button.pressed.connect(_on_buy_incremental.bind("population"))
	place_house_button.pressed.connect(_on_place_house_pressed)
	pawn_health_button.pressed.connect(_on_buy_incremental.bind("pawn_health"))
	pawn_carry_button.pressed.connect(_on_buy_incremental.bind("pawn_carry"))
	pawn_speed_button.pressed.connect(_on_buy_incremental.bind("pawn_speed"))
	mining_speed_button.pressed.connect(_on_buy_incremental.bind("mining_speed"))
	click_power_button.pressed.connect(_on_buy_incremental.bind("click_power"))
	select_all_button.pressed.connect(_on_select_all_pressed)
	recall_all_button.pressed.connect(_on_recall_all_pressed)

	_skill_categories = {
		"combat": {"label": "Combat - Tower Fire Rate, Damage & Range", "button": combat_cat_button, "items": [fire_rate_button, damage_button, range_button]},
		"fortify": {"label": "Fortify - Repair & Max Health", "button": fortify_cat_button, "items": [repair_button, health_upgrade_button]},
		"wood": {"label": "Woodcutting - Wood Drop Rate", "button": wood_cat_button, "items": [wood_drop_button]},
		"coin": {"label": "Coin - Gold Drop Rate", "button": coin_cat_button, "items": [gold_drop_button]},
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


func _on_stat_changed(_value=null) -> void:
	_refresh_resources()
	_refresh_village()


var _current_day_number: int = 1


func _on_phase_changed(phase: int, day_number: int) -> void:
	_current_day_number = day_number
	var phase_text := "Night" if phase == 1 else "Day"  # DayNightCycle.Phase.NIGHT == 1
	day_night_label.text = "Day %d\n%s" % [day_number, phase_text]
	day_night_label.modulate = Color(1, 1, 1) if phase_text == "Day" else Color(0.85, 0.85, 1.0)
	clock_bar_fill.color = Color(0.6, 0.65, 1.0, 1) if phase == 1 else Color(0.95, 0.85, 0.3, 1)


## wave_started fires from inside EnemySpawner.start_wave() - after
## current_wave has already been incremented, unlike phase_changed (which
## fires before start_wave() is even called) - so this is the signal to
## use for an accurate wave number rather than computing it in
## _on_phase_changed, which would show the previous wave for a moment.
func _on_wave_started(wave_number: int) -> void:
	day_night_label.text = "Day %d\nNight (Wave %d)" % [_current_day_number, wave_number]


## Ticks the clock bar down over the Day, standing full (representing
## "in combat") through the Night so it doesn't read as broken/frozen.
## BarFill is anchored left with anchor_right set to the fraction, so it
## visually shrinks/grows from the right edge - a plain ColorRect instead
## of a texture bar, since the pack's bar assets turned out to be a
## multi-piece sheet rather than a single background image (same class
## of surprise as the Tree sprite sheets - see resource_node.gd).
func _update_clock_bar() -> void:
	var day_cycle: Node = get_tree().get_first_node_in_group("day_night_cycle")
	if day_cycle == null:
		return
	var fraction: float = 1.0 if day_cycle.is_night() else day_cycle.day_time_left_fraction()
	clock_bar_fill.anchor_right = fraction


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
	village_locked_hint.visible = not unlocked
	place_house_button.disabled = not unlocked or _placing_house
	place_house_button.text = "Placing... (click the map)" if _placing_house else "Place House (%d Wood, %d Gold)" % [gm.HOUSE_WOOD_COST, gm.HOUSE_GOLD_COST]


func _on_place_house_pressed() -> void:
	if _placing_house:
		return
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null or not gm.houses_unlocked():
		return
	if gm.wood < gm.HOUSE_WOOD_COST or gm.gold < gm.HOUSE_GOLD_COST:
		var tween := create_tween()
		tween.tween_property(place_house_button, "modulate", Color(1, 0.4, 0.4), 0.1)
		tween.tween_property(place_house_button, "modulate", Color(1, 1, 1), 0.15)
		return
	_placing_house = true
	_refresh_village()


func _process(_delta: float) -> void:
	_update_clock_bar()

	if not _placing_house:
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
		_placement_reticle.radius = HOUSE_MIN_SPACING * 0.5
		get_tree().current_scene.add_child(_placement_reticle)
	_placement_reticle.global_position = cam.get_global_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if not _placing_house:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var cam := get_viewport().get_camera_2d()
			if cam:
				_try_place_house(cam.get_global_mouse_position())
			_placing_house = false
			_refresh_village()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_placing_house = false
			_refresh_village()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_placing_house = false
		_refresh_village()


## Rough placement validity - inside the kingdom's general area and not
## overlapping another house or tower - rather than full collision
## geometry against every building shape.
func _is_valid_house_spot(pos: Vector2) -> bool:
	var km: Node = get_tree().get_first_node_in_group("kingdom_manager")
	if km == null:
		return false
	var center: Vector2 = km.to_global(km.center)
	if pos.distance_to(center) > km.radius * KINGDOM_AREA_MULT:
		return false
	for h in get_tree().get_nodes_in_group("house"):
		if is_instance_valid(h) and pos.distance_to(h.global_position) < HOUSE_MIN_SPACING:
			return false
	for t in get_tree().get_nodes_in_group("tower"):
		if is_instance_valid(t) and pos.distance_to(t.global_position) < HOUSE_MIN_SPACING:
			return false
	return true


func _try_place_house(pos: Vector2) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null or not _is_valid_house_spot(pos):
		return
	if not gm.spend_wood(gm.HOUSE_WOOD_COST):
		return
	if not gm.spend_gold(gm.HOUSE_GOLD_COST):
		gm.add_wood(gm.HOUSE_WOOD_COST)  # refund - gold check failed after wood already spent
		return

	var house := HOUSE_SCENE.instantiate()
	var container: Node = get_tree().get_first_node_in_group("world_ysort")
	(container if container else get_tree().current_scene).add_child(house)
	house.global_position = pos
	_refresh_village()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
