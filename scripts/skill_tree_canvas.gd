extends Control

## Draws the connector lines between skill-tree nodes for skill_tree_view.gd.
## Kept as its own tiny script (rather than the parent script drawing
## directly) since this Control is also the pan/zoom target - its own
## _draw() naturally renders behind the node-button children added on top
## of it, without needing to manage z-order explicitly.

var _lines: Array[Dictionary] = []


func set_lines(lines: Array[Dictionary]) -> void:
	_lines = lines
	queue_redraw()


func _draw() -> void:
	for line in _lines:
		draw_line(line.from, line.to, line.color, line.width, true)
