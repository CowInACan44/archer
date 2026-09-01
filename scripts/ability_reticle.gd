extends Node2D

## World-space targeting shape shown while an ability is armed (see
## hotbar.gd), or while placing a house (see hud_tabs.gd) - drawn instead
## of changing the OS cursor since KingdomManager already owns the shared
## cursor every frame for the repair-hammer system and would immediately
## stomp a cursor-shape change.
##
## "circle" (the default, used for Arrow Storm and house placement) is a
## plain radius. "rect" (Volley Shot) is a rotated rectangle - rotation
## comes from this node's own `rotation`, which hotbar.gd drives with the
## scroll wheel while the ability is armed, so the line-shaped volley can
## be aimed at whatever angle a spread-out line of enemies is approaching
## from instead of only ever hitting what happens to be inside a circle.

@export var radius: float = 90.0
@export var shape: String = "circle"  # "circle" | "rect"
@export var rect_length: float = 220.0
@export var rect_width: float = 70.0


func _draw() -> void:
	if shape == "rect":
		var half := Vector2(rect_length, rect_width) * 0.5
		draw_rect(Rect2(-half, half * 2.0), Color(1, 0.4, 0.1, 0.18))
		draw_rect(Rect2(-half, half * 2.0), Color(1, 0.45, 0.1, 0.9), false, 2.0)
	else:
		draw_circle(Vector2.ZERO, radius, Color(1, 0.4, 0.1, 0.18))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1, 0.45, 0.1, 0.9), 2.0)
