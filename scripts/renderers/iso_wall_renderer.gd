class_name IsoWallRenderer
extends WallRenderer

## Isometric renderer for the same flat-plan RoomData/WallSegment geometry.
## Textures and face colors live on WallSegment so the data survives saving.

enum ViewMode {
	ISO1_NO_WALLS,
	ISO2_BACK_WALLS,
	ISO3_ALL_WALLS,
}

const SORT_CHUNK := 48.0
const CORNER_ANGLE := 0.5
const PROBE := 0.02

@export_category("Isometric")
@export var wall_height: float = 96.0:
	set(value):
		wall_height = maxf(value, 0.0)
		queue_redraw()

@export_range(10.0, 45.0, 0.5)
var projection_angle: float = 30.0:
	set(value):
		projection_angle = value
		queue_redraw()

@export_range(0, 3)
var view_quadrant: int = 0:
	set(value):
		view_quadrant = posmod(value, 4)
		queue_redraw()

@export var view_pivot: Vector2 = Vector2.ZERO:
	set(value):
		view_pivot = value
		queue_redraw()

@export var view_mode: ViewMode = ViewMode.ISO3_ALL_WALLS:
	set(value):
		view_mode = value
		queue_redraw()

@export_category("Textures")
@export var texture_tile_size: float = 32.0:
	set(value):
		texture_tile_size = maxf(value, 1.0)
		queue_redraw()

@export var textured_walls: bool = true:
	set(value):
		textured_walls = value
		queue_redraw()

@export_category("Shading")
@export_range(0.0, 1.5, 0.05)
var top_brightness: float = 0.8:
	set(value):
		top_brightness = value
		queue_redraw()

@export_range(0.0, 1.5, 0.05)
var left_brightness: float = 0.6:
	set(value):
		left_brightness = value
		queue_redraw()

@export_range(0.0, 1.5, 0.05)
var right_brightness: float = 0.4:
	set(value):
		right_brightness = value
		queue_redraw()

var _pieces: Array[Dictionary] = []
var _footprint_bounds: Array[Rect2] = []
var _scale := Vector2.ONE


func _init() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func set_segments(segments: Array[WallSegment]) -> void:
	super(segments)
	_build_faces()


func set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	queue_redraw()


func get_view_mode() -> ViewMode:
	return view_mode


func _draw() -> void:
	if view_mode == ViewMode.ISO1_NO_WALLS:
		return

	_scale = Vector2(
		cos(deg_to_rad(projection_angle)),
		sin(deg_to_rad(projection_angle))
	)

	var pieces := _visible_pieces()
	var back_depth := _get_back_depth(pieces)

	for piece in pieces:
		if not _piece_allowed(piece, back_depth):
			continue
		_draw_face(piece)

	for footprint in get_footprints():
		if not _footprint_allowed(footprint, back_depth):
			continue

		var color: Color = footprint["color"]
		var segment_value: Variant = footprint.get("segment", null)
		var top_color := color
		if segment_value is WallSegment:
			top_color = (segment_value as WallSegment).get_top_filler_color()

		var top := _project_all(footprint["points"], wall_height)
		draw_colored_polygon(top, _shade(top_color, top_brightness))

	# Top outlines / vertical corner lines.
	for path in _paths:
		if not _path_allowed(path, back_depth):
			continue

		var color: Color = path["color"]
		var points: PackedVector2Array = path["points"]
		if points.size() < 2:
			continue

		if color.a < 0.99:
			_draw_wireframe(path)
			continue

		var width: float = maxf(path["width"], 1.0)
		var top := _project_all(points, wall_height)
		draw_polyline(top, color, width, antialiased)
		draw_circle(top[0], width * 0.5, color)
		draw_circle(top[top.size() - 1], width * 0.5, color)


func _draw_face(piece: Dictionary) -> void:
	var a: Vector2 = piece["a"]
	var b: Vector2 = piece["b"]
	var color: Color = piece["color"]
	var width: float = piece["width"]

	var a_floor := _project(a, 0.0)
	var b_floor := _project(b, 0.0)
	var a_top := _project(a, wall_height)
	var b_top := _project(b, wall_height)

	var segment_value: Variant = piece.get("segment", null)
	var segment: WallSegment = segment_value as WallSegment
	var face_brightness := _face_brightness(piece["view_normal"])
	var shaded_color := _shade(color, face_brightness)

	if textured_walls and segment != null:
		var face_side: int = int(piece.get("face_side", 0))
		var texture := segment.get_texture_for_side(face_side)
		if texture != null:
			var length := a.distance_to(b)
			var tile := maxf(texture_tile_size, 1.0)
			var u := length / tile
			var v := wall_height / tile
			draw_polygon(
				PackedVector2Array([a_floor, b_floor, b_top, a_top]),
				PackedColorArray([
					_shade(Color.WHITE, face_brightness),
					_shade(Color.WHITE, face_brightness),
					_shade(Color.WHITE, face_brightness),
					_shade(Color.WHITE, face_brightness),
				]),
				PackedVector2Array([
					Vector2(0.0, 0.0),
					Vector2(u, 0.0),
					Vector2(u, v),
					Vector2(0.0, v),
				]),
				texture
			)
		else:
			draw_colored_polygon(
				PackedVector2Array([a_floor, b_floor, b_top, a_top]),
				_shade(segment.get_filler_for_side(face_side), face_brightness)
			)
	else:
		draw_colored_polygon(
			PackedVector2Array([a_floor, b_floor, b_top, a_top]),
			shaded_color
		)

	draw_line(a_floor, b_floor, color, width, antialiased)

	if piece["vertical_a"]:
		_draw_vertical(a_floor, a_top, color, width)
	if piece["vertical_b"]:
		_draw_vertical(b_floor, b_top, color, width)


func _draw_vertical(floor_point: Vector2, top_point: Vector2, color: Color, width: float) -> void:
	draw_line(floor_point, top_point, color, width, antialiased)
	draw_circle(floor_point, width * 0.5, color)
	draw_circle(top_point, width * 0.5, color)


func _draw_wireframe(path: Dictionary) -> void:
	var points: PackedVector2Array = path["points"]
	var color: Color = path["color"]
	var width: float = maxf(path["width"], 1.0)
	draw_polyline(_project_all(points, 0.0), color, width, antialiased)
	draw_polyline(_project_all(points, wall_height), color, width, antialiased)
	for index in path.get("corners", PackedInt32Array()):
		draw_line(
			_project(points[index], 0.0),
			_project(points[index], wall_height),
			color,
			width,
			antialiased
		)


func _face_brightness(normal: Vector2) -> float:
	if normal == Vector2.ZERO:
		return (left_brightness + right_brightness) * 0.5
	var t := clampf(0.5 + 0.5 * (normal.x - normal.y), 0.0, 1.0)
	return lerpf(left_brightness, right_brightness, t)


func _shade(color: Color, brightness: float) -> Color:
	return Color(
		color.r * brightness,
		color.g * brightness,
		color.b * brightness,
		color.a
	)


# -------------------------------------------------------------- Projection

func _project(point: Vector2, height: float) -> Vector2:
	var q := _rotate(point - view_pivot)
	return Vector2(
		(q.x - q.y) * _scale.x,
		(q.x + q.y) * _scale.y - height
	) + view_pivot


func project_point(point: Vector2, height: float = 0.0) -> Vector2:
	# Public wrapper for RoomBuilder overlays and picking.
	_scale = Vector2(
		cos(deg_to_rad(projection_angle)),
		sin(deg_to_rad(projection_angle))
	)
	return _project(point, height)


func screen_to_plan(screen_point: Vector2, height: float = 0.0) -> Vector2:
	_scale = Vector2(
		cos(deg_to_rad(projection_angle)),
		sin(deg_to_rad(projection_angle))
	)

	var sx := screen_point.x - view_pivot.x
	var sy := screen_point.y - view_pivot.y + height

	var cx := _scale.x
	var sy_scale := _scale.y
	if absf(cx) < 0.0001 or absf(sy_scale) < 0.0001:
		return view_pivot

	var a := sx / cx
	var b := sy / sy_scale
	var q := Vector2(
		(a + b) * 0.5,
		(b - a) * 0.5
	)

	return _inverse_rotate(q) + view_pivot


func _project_all(points: PackedVector2Array, height: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i in points.size():
		result[i] = _project(points[i], height)
	return result


func _rotate(v: Vector2) -> Vector2:
	match view_quadrant:
		1:
			return Vector2(-v.y, v.x)
		2:
			return -v
		3:
			return Vector2(v.y, -v.x)
	return v


func _inverse_rotate(v: Vector2) -> Vector2:
	match view_quadrant:
		1:
			return Vector2(v.y, -v.x)
		2:
			return -v
		3:
			return Vector2(-v.y, v.x)
	return v


# ------------------------------------------------------- Face preparation

func _visible_pieces() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for piece in _pieces:
		var normal := _rotate(piece["normal"])
		if normal != Vector2.ZERO and normal.x + normal.y <= 0.001:
			continue

		var middle := _rotate((piece["a"] + piece["b"]) * 0.5 - view_pivot)
		piece["view_normal"] = normal
		piece["depth"] = middle.x + middle.y
		result.append(piece)

	result.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return first["depth"] < second["depth"]
	)
	return result


func _get_back_depth(pieces: Array[Dictionary]) -> float:
	if pieces.is_empty():
		return 0.0
	var min_depth := pieces[0]["depth"] as float
	var max_depth := min_depth
	for piece in pieces:
		var depth: float = piece["depth"]
		min_depth = minf(min_depth, depth)
		max_depth = maxf(max_depth, depth)
	return lerpf(min_depth, max_depth, 0.5)


func _piece_allowed(piece: Dictionary, back_depth: float) -> bool:
	if view_mode == ViewMode.ISO3_ALL_WALLS:
		return true
	return piece["depth"] <= back_depth + 0.001


func _path_allowed(path: Dictionary, back_depth: float) -> bool:
	if view_mode == ViewMode.ISO3_ALL_WALLS:
		return true
	var points: PackedVector2Array = path["points"]
	if points.is_empty():
		return false
	return _depth_for_point(_average_points(points)) <= back_depth + 0.001


func _footprint_allowed(footprint: Dictionary, back_depth: float) -> bool:
	if view_mode == ViewMode.ISO3_ALL_WALLS:
		return true
	return _depth_for_point(_average_points(footprint["points"])) <= back_depth + 0.001


func _average_points(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in points:
		total += point
	return total / float(points.size())


func _depth_for_point(point: Vector2) -> float:
	var q := _rotate(point - view_pivot)
	return q.x + q.y


func _build_faces() -> void:
	_pieces.clear()
	_footprint_bounds.clear()

	for footprint in get_footprints():
		var polygon: PackedVector2Array = footprint["points"]
		if polygon.is_empty():
			continue
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		_footprint_bounds.append(bounds.grow(0.1))

	for path in _paths:
		var points: PackedVector2Array = path["points"]
		var corners := _find_corners(points)
		path["corners"] = corners
		if (path["color"] as Color).a < 0.99:
			continue
		for i in points.size() - 1:
			_add_face(
				points[i],
				points[i + 1],
				path,
				corners.has(i),
				corners.has(i + 1)
			)


func _find_corners(points: PackedVector2Array) -> PackedInt32Array:
	var corners := PackedInt32Array([0])
	for i in range(1, points.size() - 1):
		var before := (points[i] - points[i - 1]).normalized()
		var after := (points[i + 1] - points[i]).normalized()
		if absf(before.angle_to(after)) > CORNER_ANGLE:
			corners.append(i)
	corners.append(points.size() - 1)
	return corners


func _add_face(
		a: Vector2,
		b: Vector2,
		path: Dictionary,
		vertical_a: bool,
		vertical_b: bool) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return

	var normal := _outward_normal(a, b)
	var segment_value: Variant = path.get("segment", null)
	var segment: WallSegment = segment_value as WallSegment
	var face_side := 0
	if segment != null and normal != Vector2.ZERO:
		var perp := (segment.end_point - segment.start_point).normalized().orthogonal()
		if normal.dot(perp) < 0.0:
			face_side = 1

	var count := maxi(ceili(length / SORT_CHUNK), 1)
	for i in count:
		_pieces.append({
			"a": a.lerp(b, float(i) / count),
			"b": a.lerp(b, float(i + 1) / count),
			"normal": normal,
			"color": path["color"],
			"width": maxf(path["width"], 1.0),
			"vertical_a": vertical_a and i == 0,
			"vertical_b": vertical_b and i == count - 1,
			"segment": segment,
			"face_side": face_side,
		})


func _outward_normal(a: Vector2, b: Vector2) -> Vector2:
	var side := (b - a).normalized().orthogonal()
	var middle := (a + b) * 0.5
	var solid_plus := _is_solid(middle + side * PROBE)
	var solid_minus := _is_solid(middle - side * PROBE)
	if solid_plus == solid_minus:
		return Vector2.ZERO
	return -side if solid_plus else side


func _is_solid(point: Vector2) -> bool:
	var footprints := get_footprints()
	for i in footprints.size():
		if i >= _footprint_bounds.size():
			continue
		if not _footprint_bounds[i].has_point(point):
			continue
		var polygon: PackedVector2Array = footprints[i]["points"]
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


# ------------------------------------------------------------ Wall picking

func pick_wall(screen_point: Vector2) -> Dictionary:
	if view_mode == ViewMode.ISO1_NO_WALLS:
		return {}

	var best_segment: WallSegment = null
	var best_distance := INF
	var best_plan_point := Vector2.ZERO
	var best_depth := INF
	var pieces := _visible_pieces()
	var back_depth := _get_back_depth(pieces)

	for piece in pieces:
		if not _piece_allowed(piece, back_depth):
			continue
		if piece["normal"] == Vector2.ZERO:
			continue
		var points := PackedVector2Array([
			_project(piece["a"], 0.0),
			_project(piece["b"], 0.0),
			_project(piece["b"], wall_height),
			_project(piece["a"], wall_height),
		])
		if not Geometry2D.is_point_in_polygon(screen_point, points):
			continue

		var segment_value: Variant = piece.get("segment", null)
		if not segment_value is WallSegment:
			continue
		var segment: WallSegment = segment_value
		var center : Vector2 = (piece["a"] + piece["b"]) * 0.5
		var distance := screen_point.distance_to(_project(center, wall_height * 0.5))
		if distance < best_distance or (is_equal_approx(distance, best_distance) and piece["depth"] < best_depth):
			best_distance = distance
			best_depth = piece["depth"]
			best_segment = segment
			best_plan_point = center

	if best_segment == null:
		return {}

	return {
		"segment": best_segment,
		"point": best_plan_point,
		"distance": best_distance,
	}
