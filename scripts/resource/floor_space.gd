class_name FloorSpace
extends Resource

## A planar floor region represented by an ordered polygon.
## The polygon is stored in the same flat world coordinates as RoomData walls.

@export var polygon: PackedVector2Array = PackedVector2Array()
@export var color: Color = Color(0.72, 0.72, 0.72, 1.0)
@export var texture: Texture2D = null
@export var texture_tile_size: float = 64.0

func _init(
		p_polygon: PackedVector2Array = PackedVector2Array(),
		p_color: Color = Color(0.72, 0.72, 0.72, 1.0),
		p_texture: Texture2D = null) -> void:
	polygon = p_polygon
	color = p_color
	texture = p_texture

func is_valid() -> bool:
	return polygon.size() >= 3 and absf(get_signed_area()) > 0.5

func get_signed_area() -> float:
	if polygon.size() < 3:
		return 0.0
	var area := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5

func get_area() -> float:
	return absf(get_signed_area())

func get_centroid() -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	var area := get_signed_area()
	if absf(area) < 0.0001:
		var average := Vector2.ZERO
		for point in polygon:
			average += point
		return average / float(maxi(polygon.size(), 1))

	var centroid := Vector2.ZERO
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var cross := a.x * b.y - b.x * a.y
		centroid.x += (a.x + b.x) * cross
		centroid.y += (a.y + b.y) * cross
	return centroid / (6.0 * area)

func contains_point(point: Vector2) -> bool:
	return polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon)
