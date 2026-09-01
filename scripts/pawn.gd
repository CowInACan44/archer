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

enum State { IDLE, SEEKING, GATHERING, RETURNING, FLEEING, SHELTERED, MANUAL_HOLD }

## Job specialization (see hud_tabs.gd's Pawns tab Job row) - GENERALIST is
## the old do-anything behavior every pawn had before this existed, kept as
## the default so an unassigned pawn still works exactly as before. The
## other four are the colored pawns from DESIGN.md: WOOD/STONE restrict
## which resource nodes _find_nearest_resource_node() will pick, HAULER
## and HUNTER opt out of gathering entirely in favor of their own thing
## (a wider pickup-seek radius, and striking back at night respectively).
enum Job { GENERALIST, WOOD, STONE, HAULER, HUNTER }

const JOB_COLORS := {
	Job.GENERALIST: Color(1, 1, 1),
	Job.WOOD: Color(1, 0.85, 0.2),
	Job.STONE: Color(0.55, 0.55, 0.6),
	Job.HAULER: Color(0.45, 0.65, 1.0),
	Job.HUNTER: Color(1.4, 0.5, 0.5),
}

const HAULER_SEEK_RADIUS_MULT := 1.8
const HUNTER_ENGAGE_RADIUS := 90.0
const HUNTER_ATTACK_DAMAGE := 3

const POOF_SCENE := preload("res://scenes/poof.tscn")

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
var job: Job = Job.GENERALIST
var state: State = State.IDLE
var current_health: int
var max_health: int
var carry_amount: int
var carrying_type: String = ""  # "" | "wood" | "stone"
var _carried_amount: int = 0
var _target_node: Node = null
var _wander_target: Vector2
var _is_night := false

## RTS-style player control: once manual_mode is on (via command_move_to/
## command_gather), this pawn stops auto-wandering/auto-gathering on its
## own and only does what it was last told, until command_recall() clears
## it. Persists across the night-flee/shelter cycle - a manual assignment
## picks back up the next Day rather than being lost.
var selected := false
var manual_mode := false
var _manual_move_target: Vector2 = Vector2.ZERO
var _manual_gather_node: Node = null


func _ready() -> void:
	add_to_group("pawn")
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	max_health = base_max_health + (gm.pawn_max_health_bonus if gm else 0)
	carry_amount = base_carry_amount + (gm.pawn_carry_bonus if gm else 0)
	current_health = max_health
	move_speed += gm.pawn_speed_bonus if gm else 0.0
	gather_time = maxf(0.4, gather_time - (gm.mining_speed_bonus if gm else 0.0))
	if job == Job.HAULER:
		pickup_seek_radius *= HAULER_SEEK_RADIUS_MULT
	sprite.modulate = JOB_COLORS.get(job, Color.WHITE)

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


## Player-driven "training" from the Pawns tab's Job row - reassigns this
## pawn's specialization on the spot (no cost/cooldown for this first
## pass). Drops whatever it was doing so the new job takes over immediately
## instead of finishing out an old-job errand first.
func set_job(new_job: Job) -> void:
	if new_job == job:
		return
	job = new_job
	sprite.modulate = JOB_COLORS.get(job, Color.WHITE)
	if not manual_mode and state != State.GATHERING and state != State.RETURNING:
		_release_target()
		state = State.IDLE


func _job_can_gather(kind: int) -> bool:
	match job:
		Job.WOOD:
			return kind == ResourceNode.Kind.WOOD
		Job.STONE:
			return kind == ResourceNode.Kind.STONE
		Job.HAULER, Job.HUNTER:
			return false
		_:
			return true


func _on_phase_changed(phase: int, _day_number: int) -> void:
	_is_night = phase == 1  # DayNightCycle.Phase.NIGHT
	if _is_night:
		if state != State.GATHERING:
			_start_fleeing()
	else:
		if state == State.SHELTERED:
			state = State.IDLE
			visible = true
			_spawn_poof()
			_bounce_in()
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
		State.MANUAL_HOLD:
			_process_manual_hold()


func _process_idle() -> void:
	if _is_night:
		_start_fleeing()
		return

	if manual_mode:
		_process_manual_idle()
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


## Manual-mode counterpart to _process_idle(): re-claims the assigned
## gather node whenever it's free rather than picking whatever's nearest,
## and otherwise just holds position at the last commanded spot.
func _process_manual_idle() -> void:
	if _manual_gather_node != null and is_instance_valid(_manual_gather_node) and _manual_gather_node.is_available():
		if _manual_gather_node.claim(self):
			_target_node = _manual_gather_node
			state = State.SEEKING
			return
	state = State.MANUAL_HOLD


func _process_manual_hold() -> void:
	if global_position.distance_to(_manual_move_target) > arrival_radius:
		_move_toward(_manual_move_target)
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		if sprite.animation != "idle":
			sprite.play("idle")
	if _manual_gather_node != null and is_instance_valid(_manual_gather_node) and _manual_gather_node.is_available():
		if _manual_gather_node.claim(self):
			_target_node = _manual_gather_node
			state = State.SEEKING


## --- RTS-style player commands, called by PawnController -----------------

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## Both commands let an in-progress GATHERING or RETURNING trip finish
## naturally instead of yanking the pawn off it - interrupting GATHERING
## in particular would abandon the resource node still claimed (its
## harvest/release only happens when the gather timer completes), leaving
## it stuck claimed forever. manual_mode/the manual target are recorded
## immediately either way, so _process_idle() picks the command up the
## moment the pawn's current trip naturally ends.
func command_move_to(pos: Vector2) -> void:
	manual_mode = true
	_manual_gather_node = null
	_manual_move_target = pos
	if state == State.GATHERING or state == State.RETURNING:
		return
	_release_target()
	state = State.MANUAL_HOLD


func command_gather(node: Node) -> void:
	manual_mode = true
	_manual_gather_node = node
	_manual_move_target = node.global_position
	if state == State.GATHERING or state == State.RETURNING:
		return
	_release_target()
	state = State.IDLE


func command_recall() -> void:
	manual_mode = false
	_manual_gather_node = null
	if state == State.GATHERING or state == State.RETURNING:
		return
	_release_target()
	state = State.IDLE
	_pick_wander_target()


func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 24, Color(0.3, 0.95, 0.3, 0.9), 2.0)


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
	var door: Vector2 = home_house.get_door_position() if home_house.has_method("get_door_position") else home_house.global_position
	_move_toward(door)
	if global_position.distance_to(door) < arrival_radius:
		if state == State.RETURNING:
			_deliver()
		else:  # FLEEING - made it home safe, shelter until day
			state = State.SHELTERED
			velocity = Vector2.ZERO
			_spawn_poof()
			_bounce_out()


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


func _spawn_poof() -> void:
	var poof := POOF_SCENE.instantiate()
	get_tree().current_scene.add_child(poof)
	poof.global_position = global_position


## A quick squash into the doorway before the pawn disappears into the
## house for the night, instead of just instantly vanishing.
func _bounce_out() -> void:
	sprite.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.3, 0.6), 0.1)
	tween.tween_callback(func(): visible = false)
	tween.tween_callback(func(): sprite.scale = Vector2.ONE)


## Pops back out at the start of Day with a little overshoot instead of
## just snapping to visible.
func _bounce_in() -> void:
	sprite.scale = Vector2(0.5, 1.4)
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


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
	var door: Vector2 = home_house.get_door_position() if home_house.has_method("get_door_position") else home_house.global_position
	var offset := Vector2(randf_range(-wander_radius, wander_radius), randf_range(-wander_radius, wander_radius))
	_wander_target = door + offset


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
		if not _job_can_gather(node.kind):
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
	var search_radius: float = HUNTER_ENGAGE_RADIUS if job == Job.HUNTER else enemy_danger_radius
	var enemy := _find_nearest_enemy_within(search_radius)
	if enemy == null:
		return
	take_damage(enemy_damage_per_tick)
	## Hunters are the "help defend at night" job from DESIGN.md - they
	## still take the same passive damage as any pawn caught outside, but
	## strike back instead of just absorbing it.
	if job == Job.HUNTER and enemy.has_method("take_damage"):
		enemy.take_damage(HUNTER_ATTACK_DAMAGE)


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
