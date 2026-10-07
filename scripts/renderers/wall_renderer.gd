# wall_renderer.gd
class_name WallRenderer
extends Node2D

const JOIN_EPSILON := 0.5  ## Ends closer than this (px) count as the same joint.
const MITER_LIMIT := 6.0   ## Max miter length, in half-thicknesses, before bevelling.
const CURVE_STEPS := 16

@export var antialiased: bool = true

var _paths: Array[Dictionary] = []
## Solid shapes of the walls and their joints: {"points": PackedVector2Array, "color": Color}.
## Not used by the flat drawing below; subclasses (e.g. IsoWallRenderer) fill these in.
var _footprints: Array[Dictionary] = []


func set_room(room: RoomData) -> void:
	set_segments(room.wall_segments)


func set_segments(segments: Array[WallSegment]) -> void:
	_paths = _build_paths(segments)
	queue_redraw()


func get_footprints() -> Array[Dictionary]:
	return _footprints


func _draw() -> void:
	for path in _paths:
		var points: PackedVector2Array = path["points"]
		var color: Color = path["color"]
		var width: float = maxf(path["width"], 1.0)
		draw_polyline(points, color, width, antialiased)
		# Round dots hide tiny gaps where lines meet. Skipped for translucent
		# ghosts so overlapping dots don't show up darker.
		if color.a >= 0.99:
			draw_circle(points[0], width * 0.5, color)
			draw_circle(points[points.size() - 1], width * 0.5, color)


# ---------------------------------------------------------------- Geometry

func _build_paths(segments: Array[WallSegment]) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	var arm_map := {} # WallSegment -> [start_arm, end_arm]
	_footprints.clear()

	for node in _collect_nodes(segments):
		_resolve_node(node, paths)
		for arm in node["arms"]:
			var arm_segment: WallSegment = arm["seg"]
			if not arm_map.has(arm_segment):
				arm_map[arm_segment] = [null, null]
			arm_map[arm_segment][arm["end"]] = arm

	for segment in arm_map:
		var arms: Array = arm_map[segment]
		var start_arm: Dictionary = arms[0]
		var end_arm: Dictionary = arms[1]
		# Arms are measured pointing INTO the wall, so at the end of the wall
		# their "plus" and "minus" sides are swapped relative to the wall.
		_add_path(paths, PackedVector2Array([start_arm["corner_plus"], end_arm["corner_minus"]]), segment)
		_add_path(paths, PackedVector2Array([start_arm["corner_minus"], end_arm["corner_plus"]]), segment)
		if start_arm["free"]:
			_add_path(paths, _cap_points(segment, start_arm, segment.start_cap_style), segment)
		if end_arm["free"]:
			_add_path(paths, _cap_points(segment, end_arm, segment.end_cap_style), segment)
		_add_footprint(_segment_outline(segment, start_arm, end_arm), segment.color, segment)
	return paths


## Groups wall ends that share a position into nodes. Each node holds one "arm"
## per wall end meeting there.
func _collect_nodes(segments: Array[WallSegment]) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	for segment in segments:
		if segment.get_length() < 0.01:
			continue
		for end in 2:
			var point := segment.get_point(end)
			var node := {}
			var found := false
			for candidate in nodes:
				if (candidate["pos"] as Vector2).distance_to(point) <= JOIN_EPSILON:
					node = candidate
					found = true
					break
			if not found:
				node = {"pos": point, "arms": []}
				nodes.append(node)
			var direction := segment.get_direction_from(end)
			node["arms"].append({
				"seg": segment,
				"end": end,
				"dir": direction,
				"angle": direction.angle(),
				"pos": node["pos"],
			})
	return nodes


## Works out the corner points of every arm at a node.
func _resolve_node(node: Dictionary, paths: Array[Dictionary]) -> void:
	var p: Vector2 = node["pos"]
	var arms: Array = node["arms"]

	if arms.size() == 1:
		var arm: Dictionary = arms[0]
		var segment: WallSegment = arm["seg"]
		var offset := _perp(arm["dir"]) * segment.thickness * 0.5
		arm["corner_plus"] = p + offset
		arm["corner_minus"] = p - offset
		arm["free"] = true
		return

	for arm in arms:
		arm["free"] = false
	arms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["angle"] < b["angle"])

	# Each pair of angularly neighbouring arms shares one corner.
	for i in arms.size():
		var a: Dictionary = arms[i]
		var b: Dictionary = arms[(i + 1) % arms.size()]
		var corners := _miter_corners(p, a, b)
		a["corner_plus"] = corners[0]
		b["corner_minus"] = corners[1]
		if corners[0].distance_to(corners[1]) > 0.01:
			# Walls of different thickness (or a bevel): connect the step.
			_add_path(paths, PackedVector2Array([corners[0], corners[1]]), a["seg"])
	_add_junction_footprint(arms)


## Corner between arm a's "plus" edge and arm b's "minus" edge.
## Returns [corner_for_a, corner_for_b] (identical when the edges meet cleanly).
func _miter_corners(p: Vector2, a: Dictionary, b: Dictionary) -> PackedVector2Array:
	var segment_a: WallSegment = a["seg"]
	var segment_b: WallSegment = b["seg"]
	var half_a := segment_a.thickness * 0.5
	var half_b := segment_b.thickness * 0.5
	var dir_a: Vector2 = a["dir"]
	var dir_b: Vector2 = b["dir"]
	var point_a := p + _perp(dir_a) * half_a
	var point_b := p - _perp(dir_b) * half_b
	var hit = Geometry2D.line_intersects_line(point_a, dir_a, point_b, dir_b)
	if hit is Vector2 and (hit as Vector2).distance_to(p) <= maxf(half_a, half_b) * MITER_LIMIT:
		return PackedVector2Array([hit, hit])
	return PackedVector2Array([point_a, point_b])


## Points joining the two parallel lines at a free end.
func _cap_points(segment: WallSegment, arm: Dictionary, style: WallSegment.CapStyle) -> PackedVector2Array:
	var p: Vector2 = arm["pos"]
	var u: Vector2 = arm["dir"] # points into the wall
	var perp := _perp(u)
	var half := segment.thickness * 0.5
	var depth := minf(half, segment.get_length() * 0.5)
	var corner_plus: Vector2 = arm["corner_plus"]
	var corner_minus: Vector2 = arm["corner_minus"]

	match style:
		WallSegment.CapStyle.CURVE_OUTWARD, WallSegment.CapStyle.CURVE_INWARD:
			var bulge := -1.0 if style == WallSegment.CapStyle.CURVE_OUTWARD else 1.0
			var points := PackedVector2Array()
			for i in range(CURVE_STEPS + 1):
				var angle := PI * float(i) / float(CURVE_STEPS)
				points.append(p + perp * (half * cos(angle)) + u * (bulge * depth * sin(angle)))
			return points
		WallSegment.CapStyle.POINT_CONVEX:
			return PackedVector2Array([corner_plus, p - u * depth, corner_minus])
		WallSegment.CapStyle.POINT_CONCAVE:
			return PackedVector2Array([corner_plus, p + u * depth, corner_minus])
		_:
			return PackedVector2Array([corner_plus, corner_minus])


## Closed outline of one wall: along its + side, round the end, back along its
## - side, round the start.
func _segment_outline(segment: WallSegment, start_arm: Dictionary, end_arm: Dictionary) -> PackedVector2Array:
	var outline := PackedVector2Array([start_arm["corner_plus"], end_arm["corner_minus"]])
	if end_arm["free"]:
		var end_cap := _cap_points(segment, end_arm, segment.end_cap_style)
		end_cap.reverse()
		outline.append_array(end_cap)
	else:
		outline.append(end_arm["corner_plus"])
	outline.append(start_arm["corner_minus"])
	if start_arm["free"]:
		var start_cap := _cap_points(segment, start_arm, segment.start_cap_style)
		start_cap.reverse()
		outline.append_array(start_cap)
	return outline


## The area in the middle of a node that none of the walls' own outlines cover.
func _add_junction_footprint(arms: Array) -> void:
	var points := PackedVector2Array()
	var color: Color = (arms[0]["seg"] as WallSegment).color
	for arm in arms:
		points.append(arm["corner_minus"])
		points.append(arm["corner_plus"])
		var arm_color: Color = (arm["seg"] as WallSegment).color
		if arm_color.a > color.a:
			color = arm_color
	var junction_segment: WallSegment = arms[0]["seg"]
	_add_footprint(points, color, junction_segment)


## Stores a footprint, dropping repeated points and shapes with no area.
func _add_footprint(
		points: PackedVector2Array,
		color: Color,
		segment: WallSegment = null) -> void:
	var cleaned := PackedVector2Array()
	for point in points:
		if cleaned.is_empty() or cleaned[cleaned.size() - 1].distance_to(point) > 0.01:
			cleaned.append(point)
	while cleaned.size() > 1 and cleaned[0].distance_to(cleaned[cleaned.size() - 1]) <= 0.01:
		cleaned.remove_at(cleaned.size() - 1)
	if cleaned.size() < 3:
		return
	var area := 0.0
	for i in cleaned.size():
		var next := cleaned[(i + 1) % cleaned.size()]
		area += cleaned[i].x * next.y - next.x * cleaned[i].y
	if absf(area) < 0.02 or Geometry2D.triangulate_polygon(cleaned).is_empty():
		return
	_footprints.append({
		"points": cleaned,
		"color": color,
		"segment": segment,
	})


func _add_path(paths: Array[Dictionary], points: PackedVector2Array, segment: WallSegment) -> void:
	paths.append({
		"points": points,
		"color": segment.color,
		"width": segment.line_width,
		"segment": segment,
	})


func _perp(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)
