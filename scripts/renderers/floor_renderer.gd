class_name FloorRenderer
extends Node2D

## Renders FloorSpace polygons in plan view or through the existing IsoWallRenderer projection.
## Floors are deliberately a separate renderer so wall rendering remains focused on wall geometry.

@export var antialiased: bool = true

var _room_data: RoomData
var _isometric_mode := false
var _projector: IsoWallRenderer

func _init() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

func set_room(room: RoomData) -> void:
	_room_data = room
	queue_redraw()

func set_view(isometric: bool, projector: IsoWallRenderer) -> void:
	_isometric_mode = isometric
	_projector = projector
	queue_redraw()

func pick_floor(screen_point: Vector2) -> Dictionary:
	if _room_data == null:
		return {}

	var plan_point := screen_point
	if _isometric_mode and _projector != null:
		plan_point = _projector.screen_to_plan(screen_point, 0.0)

	var best_floor: FloorSpace = null
	var best_area := INF
	var best_index := -1

	for index in _room_data.floor_spaces.size():
		var floor: FloorSpace = _room_data.floor_spaces[index]
		if floor == null or not floor.is_valid():
			continue
		if not floor.contains_point(plan_point):
			continue
		var area := floor.get_area()
		if area < best_area:
			best_area = area
			best_floor = floor
			best_index = index

	if best_floor == null:
		return {}

	return {
		"floor": best_floor,
		"point": plan_point,
		"index": best_index,
	}

func _draw() -> void:
	if _room_data == null:
		return

	for floor in _room_data.floor_spaces:
		if floor == null or not floor.is_valid():
			continue
		_draw_floor(floor)

func _draw_floor(floor: FloorSpace) -> void:
	var points := _project_polygon(floor.polygon)
	if points.size() < 3:
		return

	var fill_colors := PackedColorArray()
	for _point in points:
		fill_colors.append(floor.color)

	if floor.texture != null:
		var uvs := PackedVector2Array()
		var tile_size := maxf(floor.texture_tile_size, 1.0)
		for point in floor.polygon:
			uvs.append(point / tile_size)
		# White vertex colors leave the texture's original colors intact.
		var texture_colors := PackedColorArray()
		for _point in points:
			texture_colors.append(Color.WHITE)
		draw_polygon(points, texture_colors, uvs, floor.texture)
	else:
		draw_polygon(points, fill_colors)

	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, Color(0.12, 0.12, 0.12, 0.28), 1.0, antialiased)

func _project_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	if not _isometric_mode or _projector == null:
		return polygon

	var projected := PackedVector2Array()
	for point in polygon:
		projected.append(_projector.project_point(point, 0.0))
	return projected
