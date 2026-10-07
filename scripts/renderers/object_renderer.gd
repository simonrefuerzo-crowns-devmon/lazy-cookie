class_name ObjectRenderer
extends Node2D

## Regular top-down/world-space object renderer.
## Deliberately does not render any object textures. Textured construction and
## object height belong to IsoObjectRenderer.

@export var antialiased: bool = true
@export var draw_selection: bool = true
@export var render_contained_objects: bool = false
@export_range(8, 64, 1) var rounded_corner_segments: int = 16
@export_range(8, 128, 1) var cylinder_segments: int = 32

var _room_data: RoomData
var selected_object: ObjectData = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_room(room: RoomData) -> void:
	if _room_data != null and _room_data.changed.is_connected(_on_room_changed):
		_room_data.changed.disconnect(_on_room_changed)
	_room_data = room
	if _room_data != null and not _room_data.changed.is_connected(_on_room_changed):
		_room_data.changed.connect(_on_room_changed)
	queue_redraw()


func set_selected_object(object: ObjectData) -> void:
	selected_object = object
	queue_redraw()


func clear_selection() -> void:
	selected_object = null
	queue_redraw()


func pick_object(world_point: Vector2) -> ObjectData:
	if _room_data == null:
		return null
	for index in range(_room_data.objects.size() - 1, -1, -1):
		var object: ObjectData = _room_data.objects[index]
		if object == null:
			continue
		if _contains_point(object, world_point):
			return object
	return null


func get_object_rect(object: ObjectData) -> Rect2:
	if object == null:
		return Rect2()
	if object.object_model != null:
		var polygons: Array[PackedVector2Array] = []
		_collect_custom_model_polygons(object.object_model, object.position, object.rotation_degrees, polygons)
		return _combined_polygon_bounds(polygons)
	var size := Vector2(object.size_px)
	return Rect2(object.position - size * 0.5, size)


func _on_room_changed() -> void:
	queue_redraw()


func _draw() -> void:
	if _room_data == null:
		return
	for object in _room_data.objects:
		if object == null:
			continue
		_draw_object(object)


func _draw_object(object: ObjectData) -> void:
	if object.object_model != null:
		_draw_custom_model_object(object)
		return

	var footprint := _build_footprint(object)
	if footprint.size() < 3:
		return

	draw_set_transform(object.position, deg_to_rad(object.rotation_degrees), Vector2.ONE)
	draw_colored_polygon(footprint, object.base_color)

	if object == selected_object and draw_selection:
		var outline := Color(0.2, 0.9, 1.0, 0.9)
		var closed := PackedVector2Array(footprint)
		closed.append(footprint[0])
		draw_polyline(closed, outline, 2.0, antialiased)
		draw_circle(Vector2.ZERO, 3.0, outline)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_custom_model_object(object: ObjectData) -> void:
	if object == null or object.object_model == null:
		return

	var polygons: Array[PackedVector2Array] = []
	_collect_custom_model_polygons(
		object.object_model,
		object.position,
		object.rotation_degrees,
		polygons)

	for polygon in polygons:
		if polygon.size() < 3:
			continue
		draw_colored_polygon(polygon, object.base_color)
		if object == selected_object and draw_selection:
			var closed := PackedVector2Array(polygon)
			closed.append(polygon[0])
			draw_polyline(closed, Color(0.2, 0.9, 1.0, 0.9), 2.0, antialiased)

	if object == selected_object and draw_selection:
		draw_circle(object.position, 3.0, Color(0.2, 0.9, 1.0, 0.9))


func _collect_custom_model_polygons(
	part: ModelData,
	parent_world_position: Vector2,
	parent_world_rotation: float,
	result: Array[PackedVector2Array]) -> void:
	if part == null:
		return

	var world_rotation: float = parent_world_rotation + part.local_rotation_degrees
	var world_position: Vector2 = parent_world_position + part.local_position.rotated(deg_to_rad(parent_world_rotation))
	var footprint: PackedVector2Array = part.get_flat_footprint_polygon()
	if not part.is_assembly_parent and footprint.size() >= 3:
		var radians: float = deg_to_rad(world_rotation)
		var polygon := PackedVector2Array()
		for point in footprint:
			polygon.append(world_position + point.rotated(radians))
		result.append(polygon)

	for child in part.parts:
		if child == null:
			continue
		_collect_custom_model_polygons(child, world_position, world_rotation, result)


func _custom_model_contains_point(
	root: ModelData,
	object_position: Vector2,
	object_rotation: float,
	world_point: Vector2) -> bool:
	var polygons: Array[PackedVector2Array] = []
	_collect_custom_model_polygons(root, object_position, object_rotation, polygons)
	for polygon in polygons:
		if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(world_point, polygon):
			return true
	return false


func _combined_polygon_bounds(polygons: Array[PackedVector2Array]) -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	for polygon in polygons:
		if polygon.is_empty():
			continue
		for point in polygon:
			if not has_bounds:
				bounds = Rect2(point, Vector2.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(point)
	return bounds


func _build_footprint(object: ObjectData) -> PackedVector2Array:
	var size := Vector2(object.size_px)
	var half := size * 0.5

	match object.body_shape:
		ObjectData.BodyShape.CYLINDER:
			return _build_ellipse(half, cylinder_segments)
		ObjectData.BodyShape.ROUNDED_CORNERS:
			return _build_rounded_rect(half, minf(object.corner_radius_px, minf(half.x, half.y)), rounded_corner_segments)
		_:
			return PackedVector2Array([
				Vector2(-half.x, -half.y),
				Vector2(half.x, -half.y),
				Vector2(half.x, half.y),
				Vector2(-half.x, half.y),
			])


func _build_ellipse(half: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))
	return points


func _build_rounded_rect(half: Vector2, radius: float, arc_segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [
		Vector2(half.x - radius, -half.y + radius),
		Vector2(half.x - radius, half.y - radius),
		Vector2(-half.x + radius, half.y - radius),
		Vector2(-half.x + radius, -half.y + radius),
	]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for corner_index in corners.size():
		for step in arc_segments + 1:
			var t := float(step) / float(arc_segments)
			var angle: float = start_angles[corner_index] + t * PI * 0.5
			points.append(corners[corner_index] + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _contains_point(object: ObjectData, world_point: Vector2) -> bool:
	if object.object_model != null:
		return _custom_model_contains_point(object.object_model, object.position, object.rotation_degrees, world_point)

	var rotation := deg_to_rad(object.rotation_degrees)
	var local := (world_point - object.position).rotated(-rotation)
	var size := Vector2(object.size_px)
	var half := size * 0.5
	match object.body_shape:
		ObjectData.BodyShape.CYLINDER:
			var normalized := Vector2(
				local.x / maxf(half.x, 0.001),
				local.y / maxf(half.y, 0.001)
			)
			return normalized.length_squared() <= 1.0
		ObjectData.BodyShape.ROUNDED_CORNERS:
			var radius := minf(object.corner_radius_px, minf(half.x, half.y))
			var inner_half := half - Vector2(radius, radius)
			var clamped := Vector2(
				clampf(local.x, -inner_half.x, inner_half.x),
				clampf(local.y, -inner_half.y, inner_half.y)
			)
			return clamped.distance_to(local) <= radius
		_:
			return absf(local.x) <= half.x and absf(local.y) <= half.y
