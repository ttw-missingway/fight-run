extends StaticBody2D
class_name StageGeometry


#region Exports

@export var profile: StageProfile = preload("res://scripts/resources/default_stage_profile.tres")

#endregion


#region Onready

@onready var _stage_fill: Polygon2D = $StageFill

#endregion


#region Private state

var _collision_nodes: Array[CollisionShape2D] = []

#endregion


#region Lifecycle

func _ready() -> void:
	apply_profile(profile)

#endregion


#region Public API

func apply_profile(next_profile: StageProfile) -> void:
	profile = next_profile
	if profile == null:
		return

	_clear_collision_nodes()
	for poly in profile.get_collision_polygons():
		var shape_node := CollisionShape2D.new()
		var shape := ConvexPolygonShape2D.new()
		shape.points = poly
		shape_node.shape = shape
		add_child(shape_node)
		_collision_nodes.append(shape_node)

	if _stage_fill != null:
		_stage_fill.polygon = profile.get_visual_polygon()
		_stage_fill.color = Color(0.25, 0.28, 0.32, 1.0)

#endregion


#region Private helpers

func _clear_collision_nodes() -> void:
	for node in _collision_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_collision_nodes.clear()

#endregion
