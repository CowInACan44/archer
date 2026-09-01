extends Control

## A static decorative border ring drawn on top of the circular minimap's
## live view - purely cosmetic framing.


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 2.0
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.35, 0.22, 0.1, 0.9), 3.0)
