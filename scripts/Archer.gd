extends AnimatedSprite2D

signal shoot_released

@export var release_frame: int = 5

func _ready() -> void:
	play("idle")
	animation_finished.connect(_on_animation_finished)
	frame_changed.connect(_on_frame_changed)


func _on_frame_changed() -> void:
	if animation == "shoot" and frame == release_frame:
		shoot_released.emit()


func _on_animation_finished() -> void:
	if animation == "shoot":
		play("idle")


func play_shoot() -> void:
	play("shoot")

@export var dust_poof_scene: PackedScene


func poof() -> void:
	if dust_poof_scene:
		var poof_instance := dust_poof_scene.instantiate()
		get_tree().current_scene.add_child(poof_instance)
		poof_instance.global_position = global_position
	visible = false
