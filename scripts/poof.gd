extends AnimatedSprite2D

func _ready() -> void:
	play("poof")  # match whatever your poof animation is actually named
	animation_finished.connect(queue_free)
