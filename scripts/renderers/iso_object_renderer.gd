class_name IsoObjectRenderer
extends Node2D

## Isometric renderer for ObjectData.
## Object textures, vertical height and top profiles are rendered here; the
## regular ObjectRenderer intentionally remains texture-free.

@export_category("Projection")
@export_range(10.0, 45.0, 0.5) var projection_angle: float = 30.0:
	set(value):
		projection_angle = value
		queue_redraw()

@export_range(0, 3, 1) var view_quadrant: int = 0:
	set(value):
		view_quadrant = posmod(value, 4)
		queue_redraw()

@export var view_pivot: Vector2 = Vector2.ZERO:
	set(value):
		view_pivot = value
		queue_redraw()

@export_category("Rendering")
@export var draw_selection: bool = true
@export var antialiased: bool = true
@export var render_contained_objects: bool = false
@export_range(3, 32, 1) var footprint_segments: int = 16
@export_range(3, 32, 1) var top_segments: int = 12

@export_category("Shading")
@export_range(0.0, 2.0, 0.05) var side_brightness_near: float = 0.75
@export_range(0.0, 2.0, 0.05) var side_brightness_far: float = 0.5
@export_range(0.0, 2.0, 0.05) var top_brightness: float = 0.9
@export var opening_color: Color = Color(0.04, 0.04, 0.04, 1.0)

var _room_data: RoomData
var selected_object: ObjectData = null
var _scale := Vector2.ONE


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


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


func set_view_quadrant(quadrant: int) -> void:
	view_quadrant = posmod(quadrant, 4)
	queue_redraw()


func set_view_from_projector(projector: IsoWallRenderer) -> void:
	if projector == null:
		return
	projection_angle = projector.projection_angle
	view_quadrant = projector.view_quadrant
	view_pivot = projector.view_pivot


func project_point(point: Vector2, height: float = 0.0) -> Vector2:
	_update_scale()
	return _project_plan(point, height)


func _update_scale() -> void:
	_scale = Vector2(
		cos(deg_to_rad(projection_angle)),
		sin(deg_to_rad(projection_angle))
	)


func _on_room_changed() -> void:
	queue_redraw()


func _draw() -> void:
	if _room_data == null:
		return

	_update_scale()
	for object in _room_data.objects:
		if object == null:
			continue
		_draw_object(object)


func _draw_object(object: ObjectData) -> void:
	# Custom ModelData objects are rendered by ObjectBuilder's ModelRenderer so
	# their complete nested geometry, textures, four side faces and model-level
	# painter ordering remain intact. Do not draw the legacy body underneath.
	if object.object_model != null:
		return

	var local_outline := _build_footprint(object)
	if local_outline.size() < 3:
		return

	var bottom_ring := PackedVector2Array()
	for point in local_outline:
		bottom_ring.append(object.position + point.rotated(deg_to_rad(object.rotation_degrees)))


	_draw_side_faces(object, bottom_ring)
	_draw_top(object, bottom_ring)
	_draw_top_corner_patches(object, bottom_ring)

	if object == selected_object and draw_selection:
		var top_screen := _project_ring(object, local_outline, object.get_render_height_px())
		var closed := PackedVector2Array(top_screen)
		closed.append(top_screen[0])
		draw_polyline(closed, Color(0.2, 0.9, 1.0, 0.95), 2.0, antialiased)
		draw_line(
			_project_plan(object.position, 0.0),
			_project_plan(object.position, object.get_render_height_px()),
			Color(0.2, 0.9, 1.0, 0.95),
			2.0,
			antialiased
		)


func _draw_side_faces(object: ObjectData, bottom_ring: PackedVector2Array) -> void:
	if bottom_ring.size() < 2:
		return

	var rotation := deg_to_rad(object.rotation_degrees)
	for index in bottom_ring.size():
		var a := bottom_ring[index]
		var b := bottom_ring[(index + 1) % bottom_ring.size()]
		var edge := b - a
		if edge.length_squared() < 0.0001:
			continue

		var local_edge := edge.rotated(-rotation)
		var outward_local := local_edge.orthogonal().normalized()
		var outward_view := _rotate(outward_local)
		if outward_view == Vector2.ZERO or outward_view.x + outward_view.y <= 0.001:
			continue

		var top_z_a := _top_height_at_local(object, (a - object.position).rotated(-rotation))
		var top_z_b := _top_height_at_local(object, (b - object.position).rotated(-rotation))
		var quad := PackedVector2Array([
			_project_plan(a, 0.0),
			_project_plan(b, 0.0),
			_project_plan(b, top_z_b),
			_project_plan(a, top_z_a),
		])

		var texture_slot := _side_texture_slot(local_edge)
		var texture := _get_object_texture(object, texture_slot)
		var brightness := lerpf(side_brightness_far, side_brightness_near, clampf(outward_view.length(), 0.0, 1.0))
		if texture != null:
			var texture_size := object.get_texture_size(texture_slot)
			var length := edge.length()
			var uv := PackedVector2Array([
				Vector2.ZERO,
				Vector2(length / maxf(texture_size.x, 1.0), 0.0),
				Vector2(length / maxf(texture_size.x, 1.0), top_z_b / maxf(texture_size.y, 1.0)),
				Vector2(0.0, top_z_a / maxf(texture_size.y, 1.0)),
			])
			_draw_textured_polygon(quad, uv, texture, Color.WHITE)
		else:
			draw_colored_polygon(quad, _shade(object.base_color, brightness))

		draw_line(quad[0], quad[1], object.base_color, 1.0, antialiased)


func _draw_top(object: ObjectData, bottom_ring: PackedVector2Array) -> void:
	var local_ring := PackedVector2Array()
	var inverse_rotation := deg_to_rad(-object.rotation_degrees)
	for point in bottom_ring:
		local_ring.append((point - object.position).rotated(inverse_rotation))

	match object.top_render_style:
		ObjectData.TopRenderStyle.OPEN:
			_draw_open_top(object, local_ring)
		ObjectData.TopRenderStyle.CURVE_OUTWARD, ObjectData.TopRenderStyle.CURVE_INWARD:
			_draw_curved_top(object, local_ring)
		ObjectData.TopRenderStyle.POINT_OUTWARD, ObjectData.TopRenderStyle.POINT_INWARD:
			_draw_point_top(object, local_ring)
		_:
			_draw_flat_top(object, local_ring)


func _draw_flat_top(object: ObjectData, local_ring: PackedVector2Array) -> void:
	var center := Vector2.ZERO
	for point in local_ring:
		center += point
	center /= float(local_ring.size())
	var z := object.get_render_height_px()
	var texture := object.middle_texture
	if texture != null:
		_draw_top_polygon(object, local_ring, center, z, z, texture)
	else:
		var projected := _project_ring(object, local_ring, z)
		draw_colored_polygon(projected, _shade(object.base_color, top_brightness))


func _draw_curved_top(object: ObjectData, local_ring: PackedVector2Array) -> void:
	var center := Vector2.ZERO
	for point in local_ring:
		center += point
	center /= float(local_ring.size())
	var center_offset := object.top_profile_height_px
	if object.top_render_style == ObjectData.TopRenderStyle.CURVE_INWARD:
		center_offset = -center_offset
	var texture := object.middle_texture
	for index in local_ring.size():
		var a := local_ring[index]
		var b := local_ring[(index + 1) % local_ring.size()]
		var uv_center := _top_uv(center, object)
		var uv_a := _top_uv(a, object)
		var uv_b := _top_uv(b, object)
		var vertices := PackedVector2Array([
			_project_plan(object.position + a.rotated(deg_to_rad(object.rotation_degrees)), object.get_render_height_px()),
			_project_plan(object.position + b.rotated(deg_to_rad(object.rotation_degrees)), object.get_render_height_px()),
			_project_plan(object.position + center.rotated(deg_to_rad(object.rotation_degrees)), object.get_render_height_px() + center_offset),
		])
		if texture != null:
			_draw_textured_polygon(vertices, PackedVector2Array([uv_a, uv_b, uv_center]), texture, Color.WHITE)
		else:
			draw_colored_polygon(vertices, _shade(object.base_color, top_brightness))


func _draw_point_top(object: ObjectData, local_ring: PackedVector2Array) -> void:
	var center := Vector2.ZERO
	for point in local_ring:
		center += point
	center /= float(local_ring.size())
	var center_offset := object.top_profile_height_px
	if object.top_render_style == ObjectData.TopRenderStyle.POINT_INWARD:
		center_offset = -center_offset
	var texture := object.middle_texture
	for index in local_ring.size():
		var a := local_ring[index]
		var b := local_ring[(index + 1) % local_ring.size()]
		var center_plan := object.position + center.rotated(deg_to_rad(object.rotation_degrees))
		var vertices := PackedVector2Array([
			_project_plan(object.position + a.rotated(deg_to_rad(object.rotation_degrees)), object.get_render_height_px()),
			_project_plan(object.position + b.rotated(deg_to_rad(object.rotation_degrees)), object.get_render_height_px()),
			_project_plan(center_plan, object.get_render_height_px() + center_offset),
		])
		if texture != null:
			_draw_textured_polygon(
				vertices,
				PackedVector2Array([
					_top_uv(a, object),
					_top_uv(b, object),
					_top_uv(center, object),
				]),
				texture,
				Color.WHITE
			)
		else:
			draw_colored_polygon(vertices, _shade(object.base_color, top_brightness))


func _draw_open_top(object: ObjectData, local_ring: PackedVector2Array) -> void:
	var outer_projected := _project_ring(object, local_ring, object.get_render_height_px())
	var inner_local := _shrink_ring(local_ring, 0.78)
	var inner_height := maxf(object.get_render_height_px() - object.opening_depth_px, 0.0)
	var inner_projected := _project_ring(object, inner_local, inner_height)

	var texture := object.middle_texture
	for index in local_ring.size():
		var next := (index + 1) % local_ring.size()
		var vertices := PackedVector2Array([
			outer_projected[index], outer_projected[next],
			inner_projected[next], inner_projected[index],
		])
		if texture != null:
			_draw_textured_polygon(
				vertices,
				PackedVector2Array([
					_top_uv(local_ring[index], object),
					_top_uv(local_ring[next], object),
					_top_uv(inner_local[next], object),
					_top_uv(inner_local[index], object),
				]),
				texture,
				Color.WHITE
			)
		else:
			draw_colored_polygon(vertices, _shade(object.base_color, top_brightness))

	draw_colored_polygon(inner_projected, opening_color)


func _draw_top_corner_patches(object: ObjectData, bottom_ring: PackedVector2Array) -> void:
	if not object.has_corners or object.body_shape == ObjectData.BodyShape.CYLINDER:
		return
	var half := Vector2(object.size_px) * 0.5
	var size := object.corner_size_px
	var patches := [
		[object.corner_top_left, Rect2(-half.x, -half.y, size.x, size.y), "corner_top_left"],
		[object.corner_top_right, Rect2(half.x - size.x, -half.y, size.x, size.y), "corner_top_right"],
		[object.corner_bottom_left, Rect2(-half.x, half.y - size.y, size.x, size.y), "corner_bottom_left"],
		[object.corner_bottom_right, Rect2(half.x - size.x, half.y - size.y, size.x, size.y), "corner_bottom_right"],
	]
	if object.top_render_style == ObjectData.TopRenderStyle.OPEN:
		return
	var rotation := deg_to_rad(object.rotation_degrees)
	for patch in patches:
		var texture: Texture2D = patch[0]
		if texture == null:
			continue
		var rect: Rect2 = patch[1]
		var texture_slot: String = patch[2]
		var points := PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		])
		var projected := PackedVector2Array()
		for point in points:
			var profile_height := _top_height_at_local(object, point)
			projected.append(_project_plan(object.position + point.rotated(rotation), profile_height))
		var uv := PackedVector2Array([
			Vector2.ZERO,
			Vector2(1.0, 0.0),
			Vector2.ONE,
			Vector2(0.0, 1.0),
		])
		_draw_textured_polygon(projected, uv, texture, Color.WHITE)


func _draw_top_polygon(object: ObjectData, local_ring: PackedVector2Array, center: Vector2, center_z: float, ring_z: float, texture: Texture2D) -> void:
	for index in local_ring.size():
		var next := (index + 1) % local_ring.size()
		var rotation := deg_to_rad(object.rotation_degrees)
		var a := object.position + local_ring[index].rotated(rotation)
		var b := object.position + local_ring[next].rotated(rotation)
		var c := object.position + center.rotated(rotation)
		var vertices := PackedVector2Array([
			_project_plan(a, ring_z),
			_project_plan(b, ring_z),
			_project_plan(c, center_z),
		])
		if texture != null:
			_draw_textured_polygon(vertices, PackedVector2Array([
				_top_uv(local_ring[index], object),
				_top_uv(local_ring[next], object),
				_top_uv(center, object),
			]), texture, Color.WHITE)
		else:
			draw_colored_polygon(vertices, _shade(object.base_color, top_brightness))


func _draw_textured_polygon(vertices: PackedVector2Array, uvs: PackedVector2Array, texture: Texture2D, modulation: Color) -> void:
	var colors := PackedColorArray()
	for _point in vertices:
		colors.append(modulation)
	draw_polygon(vertices, colors, uvs, texture)


func _project_ring(object: ObjectData, local_ring: PackedVector2Array, height: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var rotation := deg_to_rad(object.rotation_degrees)
	for point in local_ring:
		result.append(_project_plan(object.position + point.rotated(rotation), height))
	return result


func _project_plan(point: Vector2, height: float) -> Vector2:
	var q := _rotate(point - view_pivot)
	return Vector2(
		(q.x - q.y) * _scale.x,
		(q.x + q.y) * _scale.y - height
	) + view_pivot


func _rotate(value: Vector2) -> Vector2:
	match view_quadrant:
		1:
			return Vector2(-value.y, value.x)
		2:
			return -value
		3:
			return Vector2(value.y, -value.x)
	return value


func _build_footprint(object: ObjectData) -> PackedVector2Array:
	var half := Vector2(object.size_px) * 0.5
	if object.body_shape == ObjectData.BodyShape.CYLINDER:
		var ellipse := PackedVector2Array()
		for i in footprint_segments:
			var angle := TAU * float(i) / float(footprint_segments)
			ellipse.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))
		return ellipse

	if object.body_shape == ObjectData.BodyShape.ROUNDED_CORNERS or object.curved_corners:
		return _build_rounded_rect(half, minf(object.corner_radius_px, minf(half.x, half.y)), object.top_profile_segments)

	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


func _build_rounded_rect(half: Vector2, radius: float, segment_count: int = 8) -> PackedVector2Array:
	if radius <= 0.01:
		return PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
	var points := PackedVector2Array()
	var centers := [
		Vector2(half.x - radius, -half.y + radius),
		Vector2(half.x - radius, half.y - radius),
		Vector2(-half.x + radius, half.y - radius),
		Vector2(-half.x + radius, -half.y + radius),
	]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var segments := clampi(segment_count, 3, 32)
	for corner_index in centers.size():
		for step in segments + 1:
			var t := float(step) / float(segments)
			var angle: float = start_angles[corner_index] + t * PI * 0.5
			points.append(centers[corner_index] + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _top_height_at_local(object: ObjectData, local_point: Vector2) -> float:
	var base := object.get_render_height_px()
	match object.top_render_style:
		ObjectData.TopRenderStyle.CURVE_OUTWARD, ObjectData.TopRenderStyle.CURVE_INWARD, ObjectData.TopRenderStyle.POINT_OUTWARD, ObjectData.TopRenderStyle.POINT_INWARD:
			var half := Vector2(object.size_px) * 0.5
			var nx := local_point.x / maxf(half.x, 0.001)
			var ny := local_point.y / maxf(half.y, 0.001)
			var radial := clampf(Vector2(nx, ny).length(), 0.0, 1.0)
			var profile := object.top_profile_height_px * (1.0 - radial)
			if object.top_render_style == ObjectData.TopRenderStyle.CURVE_INWARD or object.top_render_style == ObjectData.TopRenderStyle.POINT_INWARD:
				return base - profile
			return base + profile
		ObjectData.TopRenderStyle.OPEN:
			return base
		_:
			return base


func _top_uv(local_point: Vector2, object: ObjectData) -> Vector2:
	var tile := object.get_texture_size("middle")
	return Vector2(local_point.x / maxf(tile.x, 1.0), local_point.y / maxf(tile.y, 1.0))


func _shade(color: Color, brightness: float) -> Color:
	return Color(
		color.r * brightness,
		color.g * brightness,
		color.b * brightness,
		color.a
	)


func _shrink_ring(ring: PackedVector2Array, factor: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in ring:
		result.append(point * factor)
	return result


func _side_texture_slot(local_edge: Vector2) -> String:
	if absf(local_edge.x) >= absf(local_edge.y):
		return "edge_top" if local_edge.x > 0.0 else "edge_bottom"
	return "edge_right" if local_edge.y > 0.0 else "edge_left"


func _get_object_texture(object: ObjectData, slot: String) -> Texture2D:
	match slot:
		"corner_top_left": return object.corner_top_left
		"corner_top_right": return object.corner_top_right
		"corner_bottom_left": return object.corner_bottom_left
		"corner_bottom_right": return object.corner_bottom_right
		"edge_top": return object.edge_top
		"edge_bottom": return object.edge_bottom
		"edge_left": return object.edge_left
		"edge_right": return object.edge_right
		"middle": return object.middle_texture
	return null
