extends CanvasLayer

## Bottom hotbar for tower actions - repair / buy arrows / upgrade health -
## that used to be separate floating buttons hovering over every tower.
## Each action targets whichever tower is nearest the mouse cursor, so one
## hotbar works for as many towers as you've built.

@onready var slot_1: BaseButton = $HBox/Slot1
@onready var slot_2: BaseButton = $HBox/Slot2
@onready var slot_3: BaseButton = $HBox/Slot3
@onready var slot_4: BaseButton = $HBox/Slot4
@onready var slot_5: BaseButton = $HBox/Slot5

var _buy_arrows_cooldown := false


func _ready() -> void:
	slot_1.tooltip_text = "Repair Nearest Tower (5 Wood)"
	slot_2.tooltip_text = "Buy 5 Arrows (2 Gold, 1 Wood)"
	slot_3.tooltip_text = "Upgrade Max Health"
	slot_4.tooltip_text = "Coming soon"
	slot_5.tooltip_text = "Coming soon"
	slot_4.disabled = true
	slot_5.disabled = true

	slot_1.pressed.connect(_use_repair)
	slot_2.pressed.connect(_use_buy_arrows)
	slot_3.pressed.connect(_use_health_upgrade)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_1:
			_use_repair()
		KEY_2:
			_use_buy_arrows()
		KEY_3:
			_use_health_upgrade()


func _nearest_tower_to_mouse() -> Node:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return null
	var camera: Camera2D = get_viewport().get_camera_2d()
	var mouse_world: Vector2 = camera.get_global_mouse_position() if camera else Vector2.ZERO
	return gm.nearest_tower(mouse_world)


func _use_repair() -> void:
	var tower: Node = _nearest_tower_to_mouse()
	if tower and tower.has_method("try_repair"):
		tower.try_repair()


func _use_buy_arrows() -> void:
	if _buy_arrows_cooldown:
		return
	var tower: Node = _nearest_tower_to_mouse()
	if tower == null or not tower.has_method("try_buy_arrows"):
		return
	if tower.try_buy_arrows(0):
		_start_buy_arrows_cooldown(tower.arrow_buy_cooldown)


func _start_buy_arrows_cooldown(duration: float) -> void:
	_buy_arrows_cooldown = true
	slot_2.disabled = true
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(func():
		_buy_arrows_cooldown = false
		slot_2.disabled = false
	)


func _use_health_upgrade() -> void:
	var tower: Node = _nearest_tower_to_mouse()
	if tower and tower.has_method("try_upgrade_health"):
		tower.try_upgrade_health()
