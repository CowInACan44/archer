extends Sprite2D
class_name CloudDrift

## Slow horizontal drift for a decorative cloud - wraps back around once
## it's drifted far enough from its starting point instead of just
## floating off into the distance forever, so the sky reads as alive
## without needing to manage cloud spawning/despawning.
##
## The cloud PUFF itself is never actually drawn (see _ready) - in a
## top-down game there's no real height axis to place a cloud "above"
## the ground on, so a visible semi-transparent shape drifting at the
## same screen depth as everything else just reads as fog crawling
## across the grass. A moving dark patch on the ground reads unambiguously
## as something passing overhead casting a shadow, which is the only
## piece of the illusion a top-down view can actually sell - so that
## shadow (see _make_shadow) is the only thing that renders.

@export var drift_speed: float = 6.0
@export var wrap_distance: float = 500.0
@export var cast_shadow: bool = true

const SHADOW_COLOR := Color(0.05, 0.08, 0.05, 0.16)
const SHADOW_SCALE := Vector2(0.9, 0.55)
## The ground tile layer and every world entity default to z_index 0 -
## anything negative here would draw the shadow BEHIND the ground itself
## (invisible). 0 puts it in the same layer as the ground and everything
## else; since SkyLayer is the last child in main.tscn, ties there still
## draw the shadow on top when it happens to cross a pawn/tree, which
## reads correctly as the shadow passing over them.
const SHADOW_Z_INDEX := 0

var _start_x: float


func _ready() -> void:
	_start_x = position.x
	if cast_shadow:
		_make_shadow()
	## self_modulate (unlike modulate) doesn't propagate to children, so
	## this hides only the cloud puff itself, not the shadow just added.
	self_modulate.a = 0.0


func _process(delta: float) -> void:
	position.x += drift_speed * delta
	if drift_speed >= 0.0 and position.x > _start_x + wrap_distance:
		position.x = _start_x - wrap_distance
	elif drift_speed < 0.0 and position.x < _start_x - wrap_distance:
		position.x = _start_x + wrap_distance


## z_as_relative = false makes this child's z_index absolute rather than
## stacked on top of the cloud's own (elevated) z_index, so it draws at a
## fixed layer regardless of how high the cloud layer itself sits in draw
## order - while still inheriting the cloud's position every frame for
## free, since it's a plain child of this node.
func _make_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.texture = texture
	shadow.region_enabled = region_enabled
	shadow.region_rect = region_rect
	shadow.modulate = SHADOW_COLOR
	shadow.z_as_relative = false
	shadow.z_index = SHADOW_Z_INDEX
	shadow.scale = SHADOW_SCALE
	add_child(shadow)
