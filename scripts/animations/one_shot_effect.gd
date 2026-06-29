extends AnimatedSprite2D
class_name OneShotEffect


#region Lifecycle

## Plays it's animation once and then frees itself.
func _ready() -> void:
	animation_finished.connect(queue_free)
	play()

#endregion
