extends CharacterBody2D
class_name Pawn

## Auto-assigned villager: idles near its house, walks out to gather from
## the nearest available Tree/Rock (see resource_node.gd) or to pick up a
## nearby Gold/Wood drop. Wood/stone go straight into the shared stockpile
## the moment they're harvested - there's nothing physical enough about a
## log or a chunk of ore to be worth a separate haul-it-home errand, so
## gathering doesn't have a carry/return trip the way it used to. A
## captured Sheep is the one thing a pawn still physically carries
## (see _on_wildlife_captured) since it's a live animal that needs an
## actual trip to a pen. At night a pawn drops whatever errand it's on and
## rushes home, sheltering once it arrives - a pawn still caught outside
## takes periodic damage from any enemy nearby and can die (see
## DESIGN.md's "pawns rush home or die trying" framing). Auto-assign only
## for this first pass - no player-driven pathing yet.

enum State { IDLE, SEEKING, GATHERING, HUNTING, RETURNING, FLEEING, SHELTERED }

## Job specialization (see hud_tabs.gd's Pawns tab Job row) - GENERALIST is
## the old do-anything behavior every pawn had before this existed, kept as
## the default so an unassigned pawn still works exactly as before. WOOD/
## STONE restrict which resource nodes _find_nearest_resource_node() will
## pick; HUNTER opts out of gathering entirely to track down wildlife and
## strike back at anything that attacks at night.
enum Job { GENERALIST, WOOD, STONE, HUNTER }

## Real per-team colored sprites (same rig, different palette) instead of
## a tint - matches the actual team identity: Stone->Black team, Hunt->Red
## team. Generalist and Wood both keep the default Yellow sprite baked
## into this scene's Sprite node, since neither needs to look different.
const TEAM_FRAMES := {
	Job.STONE: preload("res://scenes/pawn_frames_black.tres"),
	Job.HUNTER: preload("res://scenes/pawn_frames_red.tres"),
}

const HUNTER_ENGAGE_RADIUS := 90.0
const HUNTER_ATTACK_DAMAGE := 3
## A pawn's own collision capsule is 14px, Sheep's is 18px and Bear's is
## 22px - the shared arrival_radius (24) used for resource nodes is
## smaller than either combined radius (32/36), so a Hunter's own solid
## collision physically stopped it short of ever reaching arrival_radius
## of its prey - it would push against the target forever, never actually
## engaging it. Resource nodes have no collision shape at all, so they
## never hit this problem; wildlife does, needing its own larger radius.
const HUNTER_ARRIVAL_RADIUS := 45.0
## What a captured Sheep is worth if there's no Sheep Pen built yet to
## actually deliver it to - hunting still pays off immediately, just not
## as well as a live delivery does over time via the pen's production.
const SHEEP_NO_PEN_MEAT_BONUS := 5

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
## Effectively unbounded - a pawn should consider every Tree/Rock/Sheep/
## Bear anywhere on the map, not just whatever's within some fixed nearby
## radius (a house built close to the kingdom center used to leave its
## pawns with nothing in range at all, wandering the doorstep forever
## instead of ever gathering anything). "Nearest" is still how a target
## gets picked among everything found - that's just a sensible tie-
## breaker, not a limit on what a pawn can see.
@export var resource_seek_radius: float = INF
@export var arrival_radius: float = 24.0

## Rough "caught outside during a horde" danger instead of a full
## multi-target enemy AI rewrite - see DESIGN.md open questions.
@export var enemy_danger_radius: float = 70.0
@export var enemy_damage_per_tick: int = 4

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var gather_timer: Timer = $GatherTimer
@onready var damage_timer: Timer = $DamageTimer
@onready var swing_timer: Timer = $SwingTimer

signal died

var home_house: Node = null
var job: Job = Job.GENERALIST
var state: State = State.IDLE
var current_health: int
var max_health: int
var carry_amount: int
var carrying_type: String = ""  # "" | "sheep" - the only thing still physically carried home
var _carried_amount: int = 0
var _target_node: Node = null
var _wander_target: Vector2
var _is_night := false

var _default_frames: SpriteFrames


func _ready() -> void:
	add_to_group("pawn")
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	max_health = base_max_health + (gm.pawn_max_health_bonus if gm else 0)
	carry_amount = base_carry_amount + (gm.pawn_carry_bonus if gm else 0)
	current_health = max_health
	move_speed += gm.pawn_speed_bonus if gm else 0.0
	gather_time = maxf(0.4, gather_time - (gm.mining_speed_bonus if gm else 0.0))
	_default_frames = sprite.sprite_frames
	_apply_job_sprite()

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


## Called by GameManager.buy_pawn_carry() for every pawn that already
## exists when the incremental is bought - without this, buying it only
## affected pawns spawned afterward and looked like it did nothing.
func apply_carry_bonus(amount: int) -> void:
	carry_amount += amount


## Called by GameManager.buy_pawn_speed() for every pawn that already
## exists when the incremental is bought.
func apply_speed_bonus(amount: float) -> void:
	move_speed += amount


## Called by GameManager.buy_mining_speed() and the "mining_speed" skill
## node effect for every pawn that already exists when the bonus is
## granted.
func apply_mining_speed_bonus(amount: float) -> void:
	gather_time = maxf(0.4, gather_time - amount)


## Player-driven "training" from the Pawns tab's Job row - reassigns this
## pawn's specialization on the spot (no cost/cooldown for this first
## pass). Drops whatever it was doing so the new job takes over immediately
## instead of finishing out an old-job errand first.
func set_job(new_job: Job) -> void:
	if new_job == job:
		return
	job = new_job
	_apply_job_sprite()
	if state != State.GATHERING and state != State.RETURNING:
		_release_target()
		state = State.IDLE


## Swaps in the real per-team colored sprite for this job (or back to the
## default Yellow for Generalist/Wood) instead of tinting - keeps whatever
## animation was already playing so a mid-swing reassignment doesn't
## visibly reset the pawn to its idle pose.
func _apply_job_sprite() -> void:
	var target: SpriteFrames = TEAM_FRAMES.get(job, _default_frames)
	if sprite.sprite_frames == target:
		return
	var current_anim: StringName = sprite.animation
	sprite.sprite_frames = target
	sprite.play(current_anim)


func _job_can_gather(kind: int) -> bool:
	match job:
		Job.WOOD:
			return kind == ResourceNode.Kind.WOOD
		Job.STONE:
			return kind == ResourceNode.Kind.STONE
		Job.HUNTER:
			return false
		_:
			return true


func _on_phase_changed(phase: int, _day_number: int) -> void:
	_is_night = phase == 1  # DayNightCycle.Phase.NIGHT
	if _is_night:
		if state != State.GATHERING and state != State.HUNTING:
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
		State.HUNTING:
			_process_hunting()
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

	if job == Job.HUNTER:
		var prey := _find_nearest_wildlife()
		if prey and prey.claim(self):
			_target_node = prey
			state = State.SEEKING
			return
		_move_toward(_wander_target)
		if global_position.distance_to(_wander_target) < 8.0:
			_pick_wander_target()
		return

	var node := _find_nearest_resource_node()
	if node and node.claim(self):
		_target_node = node
		state = State.SEEKING
		return

	_move_toward(_wander_target)
	if global_position.distance_to(_wander_target) < 8.0:
		_pick_wander_target()


func _process_hunting() -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	## The wildlife died or got captured (see Wildlife._resolve_death) and
	## freed itself - _on_wildlife_captured() already moved a successful
	## capture into RETURNING, so landing here with a gone target only
	## means it was killed outright (Meat already dropped on its own).
	if _target_node == null or not is_instance_valid(_target_node):
		swing_timer.stop()
		state = State.IDLE


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
	var radius: float = HUNTER_ARRIVAL_RADIUS if _target_node.is_in_group("wildlife") else arrival_radius
	if global_position.distance_to(_target_node.global_position) < radius:
		_arrive_at_target()


func _arrive_at_target() -> void:
	if _target_node.is_in_group("resource_node"):
		state = State.GATHERING
		sprite.play("chop" if _target_node.kind == ResourceNode.Kind.WOOD else "mine")
		gather_timer.wait_time = gather_time
		gather_timer.start()
		swing_timer.start()
	elif _target_node.is_in_group("wildlife"):
		state = State.HUNTING
		sprite.play("chop")
		swing_timer.start()
		if _target_node.has_signal("captured"):
			_target_node.captured.connect(_on_wildlife_captured, CONNECT_ONE_SHOT)
	else:
		## It's a gold/wood pickup - the pickup itself auto-collects once a
		## pawn is close enough (see gold_pickup.gd/wood_pickup.gd), so
		## there's nothing more for the pawn to do here.
		_target_node = null
		state = State.IDLE


func _on_swing_tick() -> void:
	if _target_node == null or not is_instance_valid(_target_node):
		return
	if state == State.GATHERING:
		_target_node.hit_react()
	elif state == State.HUNTING:
		_target_node.take_damage(HUNTER_ATTACK_DAMAGE)


## A capture (Sheep only - see Wildlife._resolve_death) doesn't leave the
## wildlife's body behind the way a kill does, so there's nothing to
## harvest - instead the pawn itself now carries the sheep home alive.
func _on_wildlife_captured() -> void:
	swing_timer.stop()
	_target_node = null
	carrying_type = "sheep"
	_carried_amount = 1
	state = State.RETURNING


## Wood/stone are deposited straight into the shared stockpile the moment
## they're harvested instead of being carried home on a separate trip -
## see the class doc comment for why.
func _on_gather_finished() -> void:
	swing_timer.stop()
	if _target_node == null or not is_instance_valid(_target_node):
		state = State.IDLE
		return
	var node: Node = _target_node
	var amount: int = node.harvest(carry_amount)
	node.release(self)
	_target_node = null

	if amount > 0:
		var gm: Node = get_tree().get_first_node_in_group("game_manager")
		if gm:
			if node.kind == ResourceNode.Kind.WOOD:
				gm.add_wood(amount)
			else:
				gm.add_stone(amount)
	state = State.IDLE


func _process_returning() -> void:
	if home_house == null or not is_instance_valid(home_house):
		state = State.IDLE
		return
	var door: Vector2
	if carrying_type == "sheep":
		var pen := _nearest_sheep_pen()
		door = pen.global_position if pen else (home_house.get_door_position() if home_house.has_method("get_door_position") else home_house.global_position)
	else:
		door = home_house.get_door_position() if home_house.has_method("get_door_position") else home_house.global_position
	_move_toward(door)
	if global_position.distance_to(door) < arrival_radius:
		if state == State.RETURNING:
			_deliver()
		else:  # FLEEING - made it home safe, shelter until day
			state = State.SHELTERED
			velocity = Vector2.ZERO
			_spawn_poof()
			_bounce_out()


## The only thing a pawn still physically carries home - a live captured
## Sheep, delivered to the nearest pen (or converted straight to meat if
## there's no pen built yet). Wood/stone deposit instantly on harvest
## instead (see _on_gather_finished) so RETURNING is sheep-only now.
func _deliver() -> void:
	var pen := _nearest_sheep_pen()
	if pen and pen.has_method("add_sheep"):
		pen.add_sheep(1)
	else:
		var gm: Node = get_tree().get_first_node_in_group("game_manager")
		if gm:
			gm.add_meat(SHEEP_NO_PEN_MEAT_BONUS)
	carrying_type = ""
	_carried_amount = 0
	if _is_night:
		_start_fleeing()
	else:
		state = State.IDLE
		_pick_wander_target()


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
	## A house's pawns spawn and wander in the same small area around its
	## door, so without this they'd keep colliding with each other and
	## visibly jostling back and forth instead of settling or passing by.
	velocity += _pawn_separation_force()
	move_and_slide()
	if velocity.length() > 1.0:
		_play_move_animation()
	elif sprite.animation != "idle":
		sprite.play("idle")


const PAWN_SEPARATION_RADIUS := 26.0
const PAWN_SEPARATION_STRENGTH := 55.0


func _pawn_separation_force() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("pawn"):
		if other == self or not is_instance_valid(other):
			continue
		var offset: Vector2 = global_position - other.global_position
		var dist: float = offset.length()
		if dist > 0.01 and dist < PAWN_SEPARATION_RADIUS:
			push += offset.normalized() * (1.0 - dist / PAWN_SEPARATION_RADIUS)
	return push * PAWN_SEPARATION_STRENGTH


func _play_move_animation() -> void:
	if sprite.animation != "run":
		sprite.play("run")


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


func _find_nearest_wildlife() -> Node:
	var nearest: Node = null
	var nearest_dist := resource_seek_radius
	for w in get_tree().get_nodes_in_group("wildlife"):
		if not is_instance_valid(w) or not w.is_available():
			continue
		var dist := global_position.distance_to(w.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = w
	return nearest


func _nearest_sheep_pen() -> Node:
	var nearest: Node = null
	var nearest_dist := INF
	for p in get_tree().get_nodes_in_group("sheep_pen"):
		if not is_instance_valid(p):
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = p
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
