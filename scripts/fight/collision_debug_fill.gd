@tool
extends Polygon2D
class_name CollisionDebugFill

## Polygon2D that auto-conforms to its parent CollisionShape2D's shape size.
## Updates live in the editor when the shape is resized. Attach to any DebugFill
## node that is a direct child of a CollisionShape2D.


#region Lifecycle

func _ready() -> void:
	var parent := get_parent() as CollisionShape2D
	if parent == null:
		return
	if parent.shape != null:
		parent.shape.changed.connect(_sync)
	_sync()

#endregion


#region Private helpers

func _sync() -> void:
	var parent := get_parent() as CollisionShape2D
	if parent == null or parent.shape == null:
		return
	if parent.shape is RectangleShape2D:
		var half := (parent.shape as RectangleShape2D).size * 0.5
		polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2( half.x, -half.y),
			Vector2( half.x,  half.y),
			Vector2(-half.x,  half.y),
		])

#endregion
