extends Node2D
class_name SkyLayer

## Keeps a small drifting cloud layer positioned over wherever the main
## camera currently is (see cloud_drift.gd for the actual per-cloud
## drift/wrap), so clouds read as part of the world no matter where the
## player has scrolled to instead of only ever existing near the
## kingdom's starting position.

@export var vertical_offset: float = -420.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		global_position = Vector2(cam.global_position.x, cam.global_position.y + vertical_offset)
