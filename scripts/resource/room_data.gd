# room_data.gd
class_name RoomData
extends Resource

const JOIN_EPSILON := 0.5
const FLOOR_AREA_EPSILON := 0.5

@export var wall_segments: Array[WallSegment] = []
@export var floor_spaces: Array[FloorSpace] = []


func add_wall_segment(
		start: Vector2,
		end: Vector2,
		color: Color = Color.WHITE,
		thickness: float = 24.0,
		line_width: float = 3.0,
		start_cap: WallSegment.CapStyle = WallSegment.CapStyle.FLAT,
		end_cap: WallSegment.CapStyle = WallSegment.CapStyle.FLAT) -> WallSegment:
	var segment := WallSegment.new(start, end, color, thickness, line_width, start_cap, end_cap)
	wall_segments.append(segment)
	emit_changed()
	return segment


func remove_wall_segment(segment: WallSegment) -> void:
	wall_segments.erase(segment)
	emit_changed()


func add_floor_space(
		points: PackedVector2Array,
		color: Color = Color(0.72, 0.72, 0.72, 1.0),
		texture: Texture2D = null) -> FloorSpace:
	var polygon := _sanitize_polygon(points)
	if polygon.size() < 3 or absf(_polygon_signed_area(polygon)) <= FLOOR_AREA_EPSILON:
		return null
	if has_floor_for_polygon(polygon):
		return null

	var floor := FloorSpace.new(polygon, color, texture)
	floor_spaces.append(floor)
	emit_changed()
	return floor


func remove_floor_space(floor: FloorSpace) -> void:
	floor_spaces.erase(floor)
	emit_changed()


func has_floor_for_polygon(points: PackedVector2Array) -> bool:
	var signature := polygon_signature(points)
	if signature.is_empty():
		return false
	for floor in floor_spaces:
		if floor == null or not floor.is_valid():
			continue
		if polygon_signature(floor.polygon) == signature:
			return true
	return false


func polygon_signature(points: PackedVector2Array) -> String:
	if points.size() < 3:
		return ""
	var keys: Array[String] = []
	for point in points:
		keys.append("%d:%d" % [int(roundf(point.x / JOIN_EPSILON)), int(roundf(point.y / JOIN_EPSILON))])
	keys.sort()
	return ";".join(keys)


## Finds bounded planar regions formed by connected wall endpoints.
## Walls are expected to be split at body intersections by the builder's snap/join logic.
func find_enclosed_polygons() -> Array[PackedVector2Array]:
	var nodes: Array[Vector2] = []
	var edges: Array[Dictionary] = []
	var edge_keys := {}

	for segment in wall_segments:
		if segment == null or segment.get_length() < 0.01:
			continue
		var a := _get_or_add_graph_node(nodes, segment.start_point)
		var b := _get_or_add_graph_node(nodes, segment.end_point)
		if a == b:
			continue
		var key := "%d:%d" % [mini(a, b), maxi(a, b)]
		if edge_keys.has(key):
			continue
		edge_keys[key] = true
		edges.append({"a": a, "b": b})

	if edges.size() < 3:
		return []

	var adjacency: Array = []
	for _node in nodes:
		adjacency.append([])
	for edge_index in edges.size():
		var edge: Dictionary = edges[edge_index]
		(adjacency[edge["a"]] as Array).append(edge_index)
		(adjacency[edge["b"]] as Array).append(edge_index)

	var visited_directed := {}
	var faces: Array[PackedVector2Array] = []
	var signatures := {}

	for edge_index in edges.size():
		for direction in 2:
			var start_state := edge_index * 2 + direction
			if visited_directed.has(start_state):
				continue

			var polygon := PackedVector2Array()
			var current_state := start_state
			var valid := false
			var safety := maxi(edges.size() * 4, 16)

			for _step in safety:
				if visited_directed.has(current_state):
					valid = current_state == start_state and polygon.size() >= 3
					break
				visited_directed[current_state] = true

				var current_edge_index := current_state / 2
				var current_direction := current_state % 2
				var current_edge: Dictionary = edges[current_edge_index]
				var from_node: int = current_edge["a"] if current_direction == 0 else current_edge["b"]
				var to_node: int = current_edge["b"] if current_direction == 0 else current_edge["a"]
				polygon.append(nodes[from_node])

				var next_state := _find_face_next_state(
					nodes,
					edges,
					adjacency,
					current_edge_index,
					from_node,
					to_node)
				if next_state < 0:
					break
				current_state = next_state

			if not valid or current_state != start_state:
				continue

			var area := _polygon_signed_area(polygon)
			# In Godot's screen/world Y-down coordinates the bounded face traced
			# by the right-hand traversal is clockwise and has positive area.
			if area <= FLOOR_AREA_EPSILON:
				continue

			var cleaned: PackedVector2Array = _sanitize_polygon(polygon)
			if cleaned.size() < 3:
				continue
			var signature := polygon_signature(cleaned)
			if signature.is_empty() or signatures.has(signature):
				continue
			signatures[signature] = true
			faces.append(cleaned)

	return faces


func sanitize_floor_polygon(points: PackedVector2Array) -> PackedVector2Array:
	return _sanitize_polygon(points)

func get_polygon_area(points: PackedVector2Array) -> float:
	return absf(_polygon_signed_area(points))

## True if no other wall touches this end of the segment (so it has a free cap
## and can be moved).
func is_end_free(segment: WallSegment, end: int) -> bool:
	var point := segment.get_point(end)
	for other in wall_segments:
		if other == segment:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, other.start_point, other.end_point)
		if closest.distance_to(point) <= JOIN_EPSILON:
			return false
	return true


## Finds something near `point` to snap to. Wall end points win over wall bodies.
## Returns {} or {"point": Vector2, "body": bool}. `body` is true when the target
## is the middle of a wall (joining there splits that wall).
func find_snap_target(point: Vector2, radius: float, exclude: WallSegment = null) -> Dictionary:
	var best := {}
	var best_dist := radius
	for segment in wall_segments:
		if segment == exclude:
			continue
		for end in 2:
			var end_pos := segment.get_point(end)
			var end_dist := end_pos.distance_to(point)
			if end_dist <= best_dist:
				best_dist = end_dist
				best = {"point": end_pos, "body": false}
	if not best.is_empty():
		return best

	best_dist = radius
	for segment in wall_segments:
		if segment == exclude:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, segment.start_point, segment.end_point)
		if closest.distance_to(segment.start_point) <= JOIN_EPSILON \
				or closest.distance_to(segment.end_point) <= JOIN_EPSILON:
			continue
		var body_dist := closest.distance_to(point)
		if body_dist <= best_dist:
			best_dist = body_dist
			best = {"point": closest, "body": true}
	return best


## True if `point` lies on the middle of a wall (not at one of its ends).
func is_point_on_body(point: Vector2, exclude: WallSegment = null) -> bool:
	for segment in wall_segments:
		if segment == exclude:
			continue
		if point.distance_to(segment.start_point) <= JOIN_EPSILON \
				or point.distance_to(segment.end_point) <= JOIN_EPSILON:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, segment.start_point, segment.end_point)
		if closest.distance_to(point) <= JOIN_EPSILON:
			return true
	return false


## Splits every wall whose body passes through `point` into two walls so a
## branch can join there. Both halves keep the original look. Returns true if
## anything was split.
func split_at_point(point: Vector2, exclude: WallSegment = null) -> bool:
	var did_split := false
	for segment in wall_segments.duplicate():
		if segment == exclude:
			continue
		if point.distance_to(segment.start_point) <= JOIN_EPSILON \
				or point.distance_to(segment.end_point) <= JOIN_EPSILON:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, segment.start_point, segment.end_point)
		if closest.distance_to(point) > JOIN_EPSILON:
			continue
		var tail := segment.duplicate() as WallSegment
		tail.start_point = point
		tail.start_cap_style = WallSegment.CapStyle.FLAT
		segment.end_point = point
		segment.end_cap_style = WallSegment.CapStyle.FLAT
		wall_segments.insert(wall_segments.find(segment) + 1, tail)
		did_split = true
	if did_split:
		emit_changed()
	return did_split


func _get_or_add_graph_node(nodes: Array[Vector2], point: Vector2) -> int:
	for index in nodes.size():
		if nodes[index].distance_to(point) <= JOIN_EPSILON:
			return index
	nodes.append(point)
	return nodes.size() - 1


func _find_face_next_state(
		nodes: Array[Vector2],
		edges: Array[Dictionary],
		adjacency: Array,
		current_edge_index: int,
		from_node: int,
		to_node: int) -> int:
	var incoming := nodes[from_node] - nodes[to_node]
	if incoming.length_squared() < 0.000001:
		return -1
	var reverse_angle := incoming.angle()
	var best_state := -1
	var best_turn := INF

	var adjacent_edges: Array = adjacency[to_node]
	for edge_index in adjacent_edges:
		if edge_index == current_edge_index:
			continue
		var edge: Dictionary = edges[edge_index]
		var other_node: int = edge["b"] if edge["a"] == to_node else edge["a"]
		var outgoing := nodes[other_node] - nodes[to_node]
		if outgoing.length_squared() < 0.000001:
			continue
		var clockwise_turn := fposmod(reverse_angle - outgoing.angle(), TAU)
		if clockwise_turn < best_turn:
			best_turn = clockwise_turn
			var direction := 0 if edge["a"] == to_node else 1
			best_state = edge_index * 2 + direction

	return best_state


func _sanitize_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		if result.is_empty() or result[result.size() - 1].distance_to(point) > JOIN_EPSILON:
			result.append(point)
	if result.size() >= 2 and result[0].distance_to(result[result.size() - 1]) <= JOIN_EPSILON:
		result.remove_at(result.size() - 1)
	return result


func _polygon_signed_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
