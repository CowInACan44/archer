extends CharacterBody2D
class_name Pawn

## Auto-assigned villager: idles near its house, walks out to gather from
## the nearest available Tree/Rock (see resource_node.gd) or to pick up a
## nearby Gold/Wood drop, carries what it collects home, and delivers it.
## At night it drops whatever errand it's on and rushes home, sheltering
## once it arrives - a pawn still caught outside takes periodic damage
## from any enemy nearby and can die (see DESIGN.md's "pawns rush home or
## die trying" framing). Auto-assign only for this first pass - no
## player-driven pathing yet.

enum State { IDLE, SEEKING, GATHERING, RETURNING, FLEEING, SHELTERED }

@export var move_speed: float = 45.0
@export var base_max_health: int = 15
## Starts at just 1 log/chunk per trip - the Pawn Carry Up incremental
## (GameManager.pawn_carry_bonus) is what raises this.
@export var base_carry_amount: int = 1
@export var gather_time: float = 1.6
@export var swing_interval: float = 0.5
@export var wander_radius: float = 60.0
@export var pickup_seek_radius: float = 260.0
@export var resource_seek_radius: float = 320.0
@export var arrival_radius: float = 24.0

## Rough "caught outside during a horde" danger instead of a full
## multi-target enemy AI rewrite - see DESIGN.md open questions.
@export var enemy_danger_radius: float = 70.0
@export var enemy_damage_per_tick: int = 4

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var gather_timer: Timer = $GatherTimer
@onready var damage_timer: Timer = $DamageTimer
@onready var swing_timer: Timer = $SwingTimer
@onready var carry_logs: Array[Sprite2D] = [$CarryStack/Log1, $CarryStack/Log2, $CarryStack/Log3]

signal died

var home_house: Node = null
var state: State = State.IDLE
var current_health: int
var max_health: int
var carry_amount: int
var carrying_type: String = ""  # "" | "wood" | "stone"
var _carried_amount: int = 0
var _target_node: Node = null
var _wander_target: Vector2
var _is_night := false


func _ready() -> void:
	add_to_group("pawn")
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	max_health = base_max_health + (gm.pawn_max_health_bonus if gm else 0)
	carry_amount = base_carry_amount + (gm.pawn_carry_bonus if gm else 0)
	current_health = max_health

	gather_timer.one_shot = true
	gather_timer.timeout.connect(_on_gather_finished)
	damage_timer.timeout.connect(_on_damage_tick)
	damage_timer.start()
	swing_timer.wait_time = swing_interval
	swing_timer.timeout.connect(_on_swing_tick)

	var day_cycle: Node = get_tree().get_first_node_in_group("day_night_cycle")
	if day_cycle:
		_is_night = day_cycle.is_night()
		day_cycle.phase_changed.connect(_on_phase_changed)

	_pick_wander_target()
	if _is_night:
		_start_fleeing()


## Called by GameManager.buy_pawn_health() for every pawn that already
## exists when the incremental is bought.
func apply_health_bonus(amount: int) -> void:
	max_health += amount
	current_health += amount


func _on_phase_changed(phase: int, _day_number: int) -> void:
	_is_night = phase == 1  # DayNightCycle.Phase.NIGHT
	if _is_night:
		if state != State.GATHERING:
			_start_fleeing()
	else:
		if state == State.SHELTERED:
			state = State.IDLE
			visible = true
			_pick_wander_target()


func _start_fleeing() -> void:
	_release_target()
	state = State.FLEEING


func _physics_process(_delta: float) -> void:
	match state:
		State.IDLE:
			_process_idle()
		State.SEEKING:
			_process_seeking()
		State.GATHERING:
			velocity = Vector2.ZERO
			move_and_slide()
		State.RETURNING, State.FLEEING:
			_process_returning()
		State.SHELTERED:
			velocity = Vector2.ZERO


func _process_idle() -> void:
	if _is_night:
		_start_fleeing()
		return

	var pickup := _find_nearest_pickup()
	if pickup:
		_target_node = pickup
		state = State.SEEKING
		return

	var node := _find_nearest_resource_node()
	if node and node.claim(self):
		_target_node = node
		state = State.SEEKING
		return

	_move_toward(_wander_target)
	if global_position.distance_to(_wander_target) < 8.0:
		_pick_wander_target()


func _process_seeking() -> void:
	if _is_night:
		_release_target()
		_start_fleeing()
		return
	if _target_node == null or not is_instance_valid(_target_node):
		_target_node = null
		state = State.IDLE
		return

	_move_toward(_target_node.global_position)
	if global_position.distance_to(_target_node.global_position) < arrival_radius:
		_arrive_at_target()


func _arrive_at_target() -> void:
	if _target_node.is_in_group("resource_node"):
		state = State.GATHERING
		sprite.play("chop" if _target_node.kind == ResourceNode.Kind.WOOD else "mine")
		gather_timer.wait_time = gather_time
		gather_timer.start()
		swing_timer.start()
	else:
		## It's a gold/wood pickup - the pickup itself auto-collects once a
		## pawn is close enough (see gold_pickup.gd/wood_pickup.gd), so
		## there's nothing more for the pawn to do here.
		_target_node = null
		state = State.IDLE


func _on_swing_tick() -> void:
	if state == State.GATHERING and _target_node and is_instance_valid(_target_node):
		_target_node.hit_react()


func _on_gather_finished() -> void:
	swing_timer.stop()
	if _target_node == null or not is_instance_valid(_target_node):
		state = State.IDLE
		return
	var node: Node = _target_node
	var amount: int = node.harvest(carry_amount)
	node.release(self)
	_target_node = null

	if amount <= 0:
		state = State.IDLE
		return

	carrying_type = "wood" if node.kind == ResourceNode.Kind.WOOD else "stone"
	_carried_amount = amount
	_update_carry_visual()
	state = State.RETURNING


func _process_returning() -> void:
	if home_house == null or not is_instance_valid(home_house):
		state = State.IDLE
		return
	_move_toward(home_house.global_position)
	if global_position.distance_to(home_house.global_position) < arrival_radius:
		if state == State.RETURNING:
			_deliver()
		else:  # FLEEING - made it home safe, shelter until day
			state = State.SHELTERED
			visible = false
			velocity = Vector2.ZERO


func _deliver() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm:
		if carrying_type == "wood":
			gm.add_wood(_carried_amount)
		elif carrying_type == "stone":
			gm.add_stone(_carried_amount)
	carrying_type = ""
	_carried_amount = 0
	_update_carry_visual()
	if _is_night:
		_start_fleeing()
	else:
		state = State.IDLE
		_pick_wander_target()


## Shows a small stack of log icons above the pawn while it's hauling
## wood home - one icon per log up to 3, so carrying 3+ (once the Pawn
## Carry Up incremental is bought a couple of times) reads as "a stack"
## rather than just a bigger number nobody can see. Stone/gold don't
## have an equivalent icon yet, so they stay invisible for now.
func _update_carry_visual() -> void:
	var shown: int = clampi(_carried_amount, 0, carry_logs.size()) if carrying_type == "wood" else 0
	for i in carry_logs.size():
		carry_logs[i].visible = i < shown


func _move_toward(target: Vector2) -> void:
	var to_target := target - global_position
	if to_target.length() < 4.0:
		velocity = Vector2.ZERO
	else:
		velocity = to_target.normalized() * move_speed
		sprite.flip_h = to_target.x < 0
	move_and_slide()
	if velocity.length() > 1.0:
		_play_move_animation()
	elif sprite.animation != "idle":
		sprite.play("idle")


func _play_move_animation() -> void:
	var anim := "run"
	if carrying_type == "wood":
		anim = "carry_wood"
	elif carrying_type == "stone":
		anim = "carry_stone"
	if sprite.animation != anim:
		sprite.play(anim)


func _pick_wander_target() -> void:
	if home_house == null or not is_instance_valid(home_house):
		_wander_target = global_position
		return
	var offset := Vector2(randf_range(-wander_radius, wander_radius), randf_range(-wander_radius, wander_radius))
	_wander_target = home_house.global_position + offset


func _find_nearest_pickup() -> Node:
	var nearest: Node = null
	var nearest_dist := pickup_seek_radius
	for group in ["gold_pickup", "wood_pickup"]:
		for p in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(p):
				continue
			var dist := global_position.distance_to(p.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = p
	return nearest


func _find_nearest_resource_node() -> Node:
	var nearest: Node = null
	var nearest_dist := resource_seek_radius
	for node in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(node) or not node.is_available():
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest


func _release_target() -> void:
	swing_timer.stop()
	if _target_node and is_instance_valid(_target_node) and _target_node.has_method("release"):
		_target_node.release(self)
	_target_node = null


func _on_damage_tick() -> void:
	if not _is_night or state == State.SHELTERED:
		return
	if _find_nearest_enemy_within(enemy_danger_radius):
		take_damage(enemy_damage_per_tick)


func _find_nearest_enemy_within(radius: float) -> Node:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy) and global_position.distance_to(enemy.global_position) <= radius:
			return enemy
	return null


func take_damage(amount: int) -> void:
	current_health -= amount
	sprite.modulate = Color(3, 1, 1)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.15)
	if current_health <= 0:
		_die()


func _die() -> void:
	_release_target()
	died.emit()
	queue_free()
