extends CanvasLayer

## Activated-ability hotbar. Each slot holds one unlocked ability (see
## ability_system.gd) - press a slot to arm it, then left-click a world
## position to cast there (a targeting circle follows the mouse so you
## can see exactly where it'll land). Right-click or Escape cancels.
## Slot->ability assignment is fixed for now; free-form drag-to-slot can
## come later once there's more than two abilities to place.

const SLOT_ORDER := ["volley_shot", "arrow_storm", "", "", ""]
const RETICLE_SCRIPT := preload("res://scripts/ability_reticle.gd")

@onready var slots: Array[Button] = [$HBox/Slot1, $HBox/Slot2, $HBox/Slot3, $HBox/Slot4, $HBox/Slot5]

var _armed_ability: String = ""
var _reticle: Node2D = null

## Volley Shot's reticle is a rectangle the player rotates with the scroll
## wheel before firing (see _unhandled_input) - Arrow Storm's circle
## ignores this since a circle has no orientation to aim.
const RETICLE_ROTATE_STEP := deg_to_rad(15.0)
var _reticle_rotation: float = 0.0


func _ready() -> void:
	for i in slots.size():
		slots[i].pressed.connect(_on_slot_pressed.bind(i))

	## Hotbar sits before AbilitySystem as a sibling in main.tscn, so an
	## immediate group lookup here would run before AbilitySystem._ready()
	## has called add_to_group("ability_system") - the lookup would silently
	## return null and these signals would never connect, leaving every
	## slot permanently disabled even after unlocking the ability (it looked
	## bought but unusable). Waiting a frame sidesteps the ordering entirely,
	## same fix as day_night_cycle.gd uses for the same reason.
	await get_tree().process_frame
	var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
	if ability_system:
		ability_system.ability_unlocked.connect(func(_id): _refresh_slots())
		ability_system.cooldown_started.connect(_on_cooldown_started)

	_refresh_slots()


func _refresh_slots() -> void:
	var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
	for i in slots.size():
		var ability_id: String = SLOT_ORDER[i]
		var slot := slots[i]
		if ability_id == "":
			slot.disabled = true
			slot.tooltip_text = "Empty - reserved for future items"
			slot.modulate = Color(1, 1, 1, 0.5)
			continue
		var unlocked: bool = ability_system != null and ability_system.is_unlocked(ability_id)
		slot.disabled = not unlocked
		slot.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.5)
		var display_name: String = ability_system.ABILITY_DEFS[ability_id].display_name if ability_system else ability_id
		if unlocked:
			slot.tooltip_text = display_name
		else:
			slot.tooltip_text = "%s - locked, unlock it from the Abilities tab" % display_name


func _on_slot_pressed(index: int) -> void:
	var ability_id: String = SLOT_ORDER[index]
	if ability_id == "":
		return
	var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
	if ability_system == null or not ability_system.is_unlocked(ability_id) or ability_system.is_on_cooldown(ability_id):
		return
	_armed_ability = ability_id
	_reticle_rotation = 0.0
	_clear_reticle()


func _process(_delta: float) -> void:
	if _armed_ability == "":
		_clear_reticle()
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if _reticle == null:
		_reticle = _make_reticle()
		get_tree().current_scene.add_child(_reticle)
	_reticle.global_position = cam.get_global_mouse_position()
	if _reticle.shape == "rect":
		_reticle.rotation = _reticle_rotation


func _make_reticle() -> Node2D:
	var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
	var reticle := Node2D.new()
	reticle.set_script(RETICLE_SCRIPT)
	if ability_system and ability_system.ABILITY_DEFS.has(_armed_ability):
		var def: Dictionary = ability_system.ABILITY_DEFS[_armed_ability]
		if def.has("rect_length"):
			reticle.shape = "rect"
			reticle.rect_length = def.rect_length
			reticle.rect_width = def.rect_width
		else:
			reticle.radius = def.get("radius", 90.0)
	return reticle


func _clear_reticle() -> void:
	if _reticle:
		_reticle.queue_free()
		_reticle = null


const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_index := NUMBER_KEYS.find(event.keycode)
		if key_index != -1:
			_on_slot_pressed(key_index)
			return
		if event.keycode == KEY_ESCAPE:
			_armed_ability = ""
			return

	if _armed_ability == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
			var cam := get_viewport().get_camera_2d()
			if ability_system and cam:
				ability_system.cast(_armed_ability, cam.get_global_mouse_position(), _reticle_rotation)
			_armed_ability = ""
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_armed_ability = ""
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_reticle_rotation += RETICLE_ROTATE_STEP
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_reticle_rotation -= RETICLE_ROTATE_STEP


func _on_cooldown_started(ability_id: String, duration: float) -> void:
	## Simple feedback: fade + disable the matching slot for the cooldown
	## instead of a numeric countdown overlay - good enough for a first pass.
	for i in slots.size():
		if SLOT_ORDER[i] != ability_id:
			continue
		var slot := slots[i]
		slot.disabled = true
		slot.modulate = Color(1, 1, 1, 0.4)
		var tween := create_tween()
		tween.tween_interval(duration)
		tween.tween_callback(_on_cooldown_finished.bind(i))


func _on_cooldown_finished(slot_index: int) -> void:
	var ability_system: Node = get_tree().get_first_node_in_group("ability_system")
	var ability_id: String = SLOT_ORDER[slot_index]
	if ability_system and ability_system.is_unlocked(ability_id):
		slots[slot_index].disabled = false
		slots[slot_index].modulate = Color(1, 1, 1, 1)
