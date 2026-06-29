extends Resource
class_name StageProfile

## Describes a stage's ground geometry — raised side flats, sloped transitions,
## and a dipped center — and derives the collision/visual polygons, ground
## heights, walkable bounds, and ledge-hang points from those measurements.

#region Exports

## Walkable half-width from center. Full stage span is half_width * 2.
@export var half_width: float = 720.0
## Width of each sloped transition between side flats and the center dip.
@export var slope_width: float = 68.0
## Half-width of the flat dipped center platform.
@export var center_flat_half_width: float = 260.0
## Surface Y on the raised side flats.
@export var edge_ground_y: float = 92.0
## Surface Y on the flat center dip.
@export var center_ground_y: float = 115.0
@export var floor_thickness: float = 56.0
@export var gameplay_inset: float = 24.0

#endregion


#region Public API

## Width of each raised side flat, between the stage edge and its slope.
func get_edge_flat_width() -> float:
	return maxf(0.0, half_width - center_flat_half_width - slope_width)


## X of the left stage edge.
func get_left_edge_x() -> float:
	return -half_width


## X of the right stage edge.
func get_right_edge_x() -> float:
	return half_width


## X where the left slope begins descending from the side flat.
func get_left_slope_start_x() -> float:
	return -center_flat_half_width - slope_width


## X of the center platform's left edge.
func get_center_flat_left_x() -> float:
	return -center_flat_half_width


## X of the center platform's right edge.
func get_center_flat_right_x() -> float:
	return center_flat_half_width


## X where the right slope finishes rising to the side flat.
func get_right_slope_end_x() -> float:
	return center_flat_half_width + slope_width


## Surface Y at a world X, interpolating across the sloped transitions.
func get_ground_y(x: float) -> float:
	x = clampf(x, -half_width, half_width)
	var left_slope_start := get_left_slope_start_x()
	var center_left := get_center_flat_left_x()
	var center_right := get_center_flat_right_x()
	var right_slope_end := get_right_slope_end_x()

	if x <= left_slope_start:
		return edge_ground_y
	if x <= center_left:
		if slope_width <= 0.0:
			return center_ground_y
		var t := (x - left_slope_start) / slope_width
		return lerpf(edge_ground_y, center_ground_y, t)
	if x <= center_right:
		return center_ground_y
	if x <= right_slope_end:
		if slope_width <= 0.0:
			return edge_ground_y
		var t := (x - center_right) / slope_width
		return lerpf(center_ground_y, edge_ground_y, t)
	return edge_ground_y


## Leftmost X a fighter may walk to, inset from the edge.
func get_walkable_left() -> float:
	return -half_width + gameplay_inset


## Rightmost X a fighter may walk to, inset from the edge.
func get_walkable_right() -> float:
	return half_width - gameplay_inset


## X at which a fighter hangs from the given ledge side.
func get_ledge_hang_x(side: int, body_half_width: float = 16.0) -> float:
	if side < 0:
		return -half_width + body_half_width * 0.5
	return half_width - body_half_width * 0.5


## Y at which a fighter hangs for a given hang X and body height.
func get_ledge_hang_y(hang_x: float, body_height: float = 56.0) -> float:
	return get_ground_y(hang_x) + body_height


## Collision polygons for the floor, one quad per flat/slope segment.
func get_collision_polygons() -> Array[PackedVector2Array]:
	var left_slope_start := get_left_slope_start_x()
	var center_left := get_center_flat_left_x()
	var center_right := get_center_flat_right_x()
	var right_slope_end := get_right_slope_end_x()
	var thick := floor_thickness

	return [
		PackedVector2Array([
			Vector2(-half_width, edge_ground_y),
			Vector2(left_slope_start, edge_ground_y),
			Vector2(left_slope_start, edge_ground_y + thick),
			Vector2(-half_width, edge_ground_y + thick),
		]),
		PackedVector2Array([
			Vector2(left_slope_start, edge_ground_y),
			Vector2(center_left, center_ground_y),
			Vector2(center_left, center_ground_y + thick),
			Vector2(left_slope_start, edge_ground_y + thick),
		]),
		PackedVector2Array([
			Vector2(center_left, center_ground_y),
			Vector2(center_right, center_ground_y),
			Vector2(center_right, center_ground_y + thick),
			Vector2(center_left, center_ground_y + thick),
		]),
		PackedVector2Array([
			Vector2(center_right, center_ground_y),
			Vector2(right_slope_end, edge_ground_y),
			Vector2(right_slope_end, edge_ground_y + thick),
			Vector2(center_right, center_ground_y + thick),
		]),
		PackedVector2Array([
			Vector2(right_slope_end, edge_ground_y),
			Vector2(half_width, edge_ground_y),
			Vector2(half_width, edge_ground_y + thick),
			Vector2(right_slope_end, edge_ground_y + thick),
		]),
	]


## Single outline polygon tracing the whole stage surface for rendering.
func get_visual_polygon() -> PackedVector2Array:
	var left_slope_start := get_left_slope_start_x()
	var center_left := get_center_flat_left_x()
	var center_right := get_center_flat_right_x()
	var right_slope_end := get_right_slope_end_x()
	var thick := floor_thickness

	return PackedVector2Array([
		Vector2(-half_width, edge_ground_y),
		Vector2(left_slope_start, edge_ground_y),
		Vector2(center_left, center_ground_y),
		Vector2(center_right, center_ground_y),
		Vector2(right_slope_end, edge_ground_y),
		Vector2(half_width, edge_ground_y),
		Vector2(half_width, edge_ground_y + thick),
		Vector2(right_slope_end, edge_ground_y + thick),
		Vector2(center_right, center_ground_y + thick),
		Vector2(center_left, center_ground_y + thick),
		Vector2(left_slope_start, edge_ground_y + thick),
		Vector2(-half_width, edge_ground_y + thick),
	])

#endregion
