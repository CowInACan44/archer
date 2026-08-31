extends Node2D

## World-space targeting circle shown while an ability is armed (see
## hotbar.gd) - drawn instead of changing the OS cursor since
## KingdomManager already owns the shared cursor every frame for the
## repair-hammer system and would immediately stomp a cursor-shape change.

@export var radius: float = 90.0


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(1, 0.4, 0.1, 0.18))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1, 0.45, 0.1, 0.9), 2.0)
