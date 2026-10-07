class_name ModelRenderer
extends Node2D

## Isometric renderer for a standalone ModelData tree.
##
## ModelRenderer is independent from RoomBuilder's grid and from ObjectData.
## It can render a temporary model while the Model Create mode is active, and
## can later render a model attached to ObjectData without changing its data.

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
@export var draw_outlines: bool = true
@export_range(1.0, 8.0, 0.5) var outline_width: float = 1.0
@export var visible_in_regular_mode: bool = false
@export var render_all_four_sides: bool = true

@export_category("Render Ordering")
## Uses ModelData.render_order as a manual painter-order priority. Higher
## values are rendered later, so they visually appear in front.
@export var use_model_render_order: bool = true

## When manual render orders are equal, lower visual base height is painted
## first and higher visual base heights are painted later. This makes stacked
## and vertically offset parts naturally layer without using z_index.
@export var use_automatic_height_ordering: bool = true

## When order and height are equal, isometric ground depth is used as the
## final painter-order tie-breaker.
@export var use_automatic_iso_depth_ordering: bool = true

@export_category("Shading")
@export_range(0.0, 2.0, 0.05) var side_brightness_near: float = 0.78
@export_range(0.0, 2.0, 0.05) var side_brightness_far: float = 0.52
@export_range(0.0, 2.0, 0.05) var top_brightness: float = 0.92

@export_category("Model Preview")
@export var render_children: bool = true
@export var ghost_modulate: Color = Color(1.0, 1.0, 1.0, 0.78)

var model: ModelData = null
var model_world_position: Vector2 = Vector2.ZERO
var selected_part: ModelData = null
var ghost_preview: bool = false

## Standalone models being assembled in Model Create mode. Positions are
## intentionally kept outside ModelData because these roots are not children
## of a parent yet.
var workspace_models: Array[ModelData] = []
var workspace_positions: Dictionary = {}
var workspace_selected_models: Array[ModelData] = []
var workspace_hovered_model: ModelData = null
var workspace_preview_model: ModelData = null
var workspace_preview_position: Vector2 = Vector2.ZERO
var workspace_preview_ghost: bool = true

## Persistent ObjectData entries whose primary representation is a custom ModelData.
var object_models: Array[ObjectData] = []
var selected_object: ObjectData = null

var _scale: Vector2 = Vector2.ONE


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func set_model(value: ModelData) -> void:
	model = value
	queue_redraw()


func clear_model() -> void:
	model = null
	selected_part = null
	queue_redraw()


func set_workspace_models(
	models: Array[ModelData],
	positions: Dictionary,
	selected_models: Array[ModelData] = [],
	hovered_model: ModelData = null) -> void:
	workspace_models = models.duplicate()
	workspace_positions = positions.duplicate()
	workspace_selected_models = selected_models.duplicate()
	workspace_hovered_model = hovered_model
	queue_redraw()


func clear_workspace_models() -> void:
	workspace_models.clear()
	workspace_positions.clear()
	workspace_selected_models.clear()
	workspace_hovered_model = null
	workspace_preview_model = null
	queue_redraw()


func set_object_models(objects: Array[ObjectData], selected: ObjectData = null) -> void:
	object_models = objects.duplicate()
	selected_object = selected
	queue_redraw()


func clear_object_models() -> void:
	object_models.clear()
	selected_object = null
	queue_redraw()


func set_workspace_preview(
	preview_model: ModelData,
	position: Vector2,
	ghost: bool = true) -> void:
	workspace_preview_model = preview_model
	workspace_preview_position = position
	workspace_preview_ghost = ghost
	queue_redraw()


func set_world_position(value: Vector2) -> void:
	model_world_position = value
	queue_redraw()


func set_selected_part(part: ModelData) -> void:
	selected_part = part
	queue_redraw()


func set_ghost_preview(enabled: bool) -> void:
	ghost_preview = enabled
	queue_redraw()


## Returns the top-most workspace model whose visible isometric silhouette
## contains the supplied viewport/screen coordinate. This complements the
## flat-space picker used by the model builder and allows clicks on elevated
## top faces to select/edit a placed model.
func pick_workspace_model_at_screen(screen_position: Vector2) -> ModelData:
	if workspace_models.is_empty():
		return null

	# Convert the viewport/screen position back into this renderer's local
	# canvas space. The renderer itself then uses the exact same projection
	# function as _draw(), avoiding a second/mismatched transform path.
	var canvas_transform: Transform2D = get_global_transform_with_canvas()
	if absf(canvas_transform.determinant()) <= 0.000001:
		return null
	var local_screen_position: Vector2 = canvas_transform.affine_inverse() * screen_position
	var best_model: ModelData = null
	var best_render_order: int = -2147483647
	var best_height: float = -INF
	var best_depth: float = -INF

	for model_index in range(workspace_models.size() - 1, -1, -1):
		var workspace_model: ModelData = workspace_models[model_index]
		if workspace_model == null:
			continue

		var position_value: Variant = workspace_positions.get(workspace_model, Vector2.ZERO)
		var root_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var hit: Dictionary = _pick_part_recursive_screen(
			workspace_model,
			root_position,
			0.0,
			0.0,
			0,
			local_screen_position)
		if not bool(hit.get("valid", false)):
			continue

		var height_value: float = float(hit.get("height", 0.0))
		var render_order_value: int = int(hit.get("render_order", 0))
		var depth_value: float = float(hit.get("depth", -INF))
		var wins: bool = best_model == null
		if not wins and render_order_value != best_render_order:
			wins = render_order_value > best_render_order
		elif not wins and not is_equal_approx(height_value, best_height):
			wins = height_value > best_height
		elif not wins:
			wins = depth_value >= best_depth
		if wins:
			best_model = workspace_model
			best_render_order = render_order_value
			best_height = height_value
			best_depth = depth_value

	return best_model


func _pick_part_recursive_screen(
	part: ModelData,
	parent_world_position: Vector2,
	parent_world_rotation: float,
	parent_world_height: float,
	parent_render_order: int,
	screen_position: Vector2) -> Dictionary:
	if part == null:
		return {"valid": false}

	var world_rotation: float = parent_world_rotation + part.local_rotation_degrees
	var world_position: Vector2 = parent_world_position + part.local_position.rotated(deg_to_rad(parent_world_rotation))
	var base_height: float = parent_world_height + part.local_height_offset_px
	var effective_render_order: int = parent_render_order + part.render_order
	var bottom_ring: PackedVector2Array = part.get_flat_footprint_polygon()
	if bottom_ring.size() < 3:
		return {"valid": false}

	var top_ring: PackedVector2Array = _build_top_ring(part)
	var top_height: float = base_height + maxf(part.height_px, 0.0)
	var silhouette := PackedVector2Array()
	var rotation_radians: float = deg_to_rad(world_rotation)

	for point in bottom_ring:
		silhouette.append(_project_plan(world_position + point.rotated(rotation_radians), base_height))

	if not top_ring.is_empty():
		for point in top_ring:
			silhouette.append(_project_plan(world_position + point.rotated(rotation_radians), top_height))
	else:
		var top_world: Vector2 = world_position + part.top_end_point.rotated(rotation_radians)
		silhouette.append(_project_plan(top_world, top_height))

	var hull: PackedVector2Array = Geometry2D.convex_hull(silhouette)
	var hit_here: bool = hull.size() >= 3 and Geometry2D.is_point_in_polygon(screen_position, hull)
	if not hit_here and hull.size() >= 3:
		var bounds: Rect2 = _polygon_bounds(hull).grow(6.0)
		hit_here = bounds.has_point(screen_position)
	var depth_value: float = _render_depth_key(world_position)
	var best_hit: Dictionary = {
		"valid": hit_here,
		"part": part,
		"height": top_height if hit_here else -INF,
		"render_order": effective_render_order,
		"depth": depth_value,
	}

	for child in part.parts:
		if child == null:
			continue
		var nested: Dictionary = _pick_part_recursive_screen(
			child,
			world_position,
			world_rotation,
			base_height,
			effective_render_order,
			screen_position)
		if bool(nested.get("valid", false)) and _pick_hit_is_later(nested, best_hit):
			best_hit = nested

	return best_hit


func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var bounds: Rect2 = Rect2(points[0], Vector2.ZERO)
	for index in range(1, points.size()):
		bounds = bounds.expand(points[index])
	return bounds


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
		sin(deg_to_rad(projection_angle)))


func _draw() -> void:
	if model == null and workspace_models.is_empty() and object_models.is_empty() and workspace_preview_model == null:
		return

	_update_scale()

	if model != null:
		_draw_part_recursive(model, model_world_position, 0.0, 0.0, model == selected_part)

	var workspace_records: Array[Dictionary] = []
	for workspace_model in workspace_models:
		if workspace_model == null:
			continue
		var workspace_position_value: Variant = workspace_positions.get(workspace_model, Vector2.ZERO)
		var workspace_position: Vector2 = workspace_position_value if workspace_position_value is Vector2 else Vector2.ZERO
		var selected_root: bool = workspace_selected_models.has(workspace_model)
		if workspace_hovered_model == workspace_model:
			selected_root = true
		_collect_render_records(
			workspace_model,
			workspace_position,
			0.0,
			0.0,
			0,
			selected_root,
			workspace_records)
	_draw_render_records(workspace_records)

	var object_records: Array[Dictionary] = []
	for object_data in object_models:
		if object_data == null or object_data.object_model == null:
			continue
		_collect_render_records(
			object_data.object_model,
			object_data.position,
			object_data.rotation_degrees,
			0.0,
			0,
			object_data == selected_object,
			object_records)
	_draw_render_records(object_records)

	if workspace_preview_model != null:
		var previous_ghost: bool = ghost_preview
		ghost_preview = workspace_preview_ghost
		_draw_part_recursive(workspace_preview_model, workspace_preview_position, 0.0, 0.0, true)
		ghost_preview = previous_ghost


func _draw_part_recursive(
	part: ModelData,
	parent_world_position: Vector2,
	parent_world_rotation: float,
	parent_world_height: float,
	root_selected: bool = false) -> void:
	if part == null:
		return

	var records: Array[Dictionary] = []
	_collect_render_records(
		part,
		parent_world_position,
		parent_world_rotation,
		parent_world_height,
		0,
		root_selected,
		records)
	_draw_render_records(records)


func _collect_render_records(
	part: ModelData,
	parent_world_position: Vector2,
	parent_world_rotation: float,
	parent_world_height: float,
	parent_render_order: int,
	root_selected: bool,
	records: Array[Dictionary]) -> void:
	if part == null:
		return

	var world_rotation: float = parent_world_rotation + part.local_rotation_degrees
	var world_position: Vector2 = parent_world_position + part.local_position.rotated(deg_to_rad(parent_world_rotation))
	var base_height: float = parent_world_height + part.local_height_offset_px
	var effective_render_order: int = parent_render_order + part.render_order

	if not part.is_assembly_parent and part.get_flat_footprint_polygon().size() >= 3:
		records.append({
			"part": part,
			"position": world_position,
			"rotation": world_rotation,
			"base_height": base_height,
			"render_order": effective_render_order,
			"depth": _render_depth_key(world_position),
			"root_selected": root_selected,
			"sequence": records.size(),
		})

	if not render_children:
		return

	for child in part.parts:
		if child == null:
			continue
		_collect_render_records(
			child,
			world_position,
			world_rotation,
			base_height,
			effective_render_order,
			root_selected,
			records)


func _draw_render_records(records: Array[Dictionary]) -> void:
	if records.is_empty():
		return

	records.sort_custom(Callable(self, "_compare_render_records"))
	for record in records:
		var part: ModelData = record.get("part") as ModelData
		if part == null:
			continue
		var record_position: Vector2 = record.get("position", Vector2.ZERO) as Vector2
		var record_rotation: float = float(record.get("rotation", 0.0))
		_draw_part(
			part,
			record_position,
			record_rotation,
			float(record["base_height"]),
			bool(record.get("root_selected", false)))


func _compare_render_records(a: Dictionary, b: Dictionary) -> bool:
	var order_a: int = int(a.get("render_order", 0))
	var order_b: int = int(b.get("render_order", 0))
	if use_model_render_order and order_a != order_b:
		return order_a < order_b

	if use_automatic_height_ordering:
		var height_a: float = float(a.get("base_height", 0.0))
		var height_b: float = float(b.get("base_height", 0.0))
		if not is_equal_approx(height_a, height_b):
			return height_a < height_b

	if use_automatic_iso_depth_ordering:
		var depth_a: float = float(a.get("depth", 0.0))
		var depth_b: float = float(b.get("depth", 0.0))
		if not is_equal_approx(depth_a, depth_b):
			return depth_a < depth_b

	return int(a.get("sequence", 0)) < int(b.get("sequence", 0))


func _render_depth_key(world_position: Vector2) -> float:
	var rotated_position: Vector2 = _rotate(world_position - view_pivot)
	return rotated_position.x + rotated_position.y


func _pick_hit_is_later(candidate: Dictionary, current: Dictionary) -> bool:
	var candidate_order: int = int(candidate.get("render_order", 0))
	var current_order: int = int(current.get("render_order", 0))
	if use_model_render_order and candidate_order != current_order:
		return candidate_order > current_order

	var candidate_height: float = float(candidate.get("height", -INF))
	var current_height: float = float(current.get("height", -INF))
	if not is_equal_approx(candidate_height, current_height):
		return candidate_height > current_height

	return float(candidate.get("depth", -INF)) >= float(current.get("depth", -INF))


func _draw_part(
	part: ModelData,
	world_position: Vector2,
	world_rotation: float,
	base_height: float,
	root_selected: bool = false) -> void:
	if part.is_assembly_parent:
		return

	var bottom_ring: PackedVector2Array = part.get_flat_footprint_polygon()
	if bottom_ring.size() < 3:
		return

	var rotation_radians: float = deg_to_rad(world_rotation)
	var world_bottom_ring: PackedVector2Array = PackedVector2Array()
	for point in bottom_ring:
		world_bottom_ring.append(world_position + point.rotated(rotation_radians))

	var top_ring: PackedVector2Array = _build_top_ring(part)
	var top_point_mode: bool = top_ring.is_empty()
	var top_height: float = base_height + maxf(part.height_px, 0.0)

	_draw_part_sides(
		part,
		bottom_ring,
		world_bottom_ring,
		top_ring,
		top_point_mode,
		world_position,
		world_rotation,
		base_height,
		top_height)

	if not top_point_mode:
		_draw_part_top(
			part,
			top_ring,
			world_position,
			world_rotation,
			top_height)

	if (part == selected_part or root_selected and (workspace_selected_models.has(part) or part == selected_object_model_root())) and draw_selection:
		_draw_selection_outline(
			part,
			world_bottom_ring,
			top_ring,
			world_position,
			world_rotation,
			top_height)


func selected_object_model_root() -> ModelData:
	return selected_object.object_model if selected_object != null else null


func _build_top_ring(part: ModelData) -> PackedVector2Array:
	match part.body_type:
		ModelData.BodyType.RECTANGULAR, ModelData.BodyType.CYLINDER:
			return part.get_flat_footprint_polygon()
		ModelData.BodyType.PYRAMID, ModelData.BodyType.CONE, ModelData.BodyType.HYBRID:
			if part.top_end_size_px.x <= 0.0 or part.top_end_size_px.y <= 0.0:
				return PackedVector2Array()
			return _build_end_ring(part)
	return part.get_flat_footprint_polygon()


func _build_end_ring(part: ModelData) -> PackedVector2Array:
	var half: Vector2 = part.top_end_size_px * 0.5
	var center: Vector2 = part.top_end_point

	if part.flat_bottom_shape == ModelData.FlatBottomShape.ELLIPSE or part.body_type == ModelData.BodyType.CONE:
		var ellipse := PackedVector2Array()
		var segments: int = clampi(part.radial_segments, 3, 128)
		for index in range(segments):
			var angle: float = TAU * float(index) / float(segments)
			ellipse.append(center + Vector2(cos(angle) * half.x, sin(angle) * half.y))
		return ellipse

	if not part.has_corners or part.corner_style == ModelData.CornerStyle.SOLID_RECT or part.corner_radius_px <= 0.0:
		return PackedVector2Array([
			center + Vector2(-half.x, -half.y),
			center + Vector2(half.x, -half.y),
			center + Vector2(half.x, half.y),
			center + Vector2(-half.x, half.y),
		])

	return _build_rounded_rect(
		center,
		half,
		minf(part.corner_radius_px, minf(half.x, half.y)),
		part.corner_segments)


func _build_rounded_rect(
	center: Vector2,
	half: Vector2,
	radius: float,
	segment_count: int) -> PackedVector2Array:
	if radius <= 0.01:
		return PackedVector2Array([
			center + Vector2(-half.x, -half.y),
			center + Vector2(half.x, -half.y),
			center + Vector2(half.x, half.y),
			center + Vector2(-half.x, half.y),
		])

	var points := PackedVector2Array()
	var centers: Array[Vector2] = [
		center + Vector2(half.x - radius, -half.y + radius),
		center + Vector2(half.x - radius, half.y - radius),
		center + Vector2(-half.x + radius, half.y - radius),
		center + Vector2(-half.x + radius, -half.y + radius),
	]
	var start_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	var segments: int = clampi(segment_count, 3, 32)
	for corner_index in centers.size():
		for step in range(segments + 1):
			var t: float = float(step) / float(segments)
			var angle: float = start_angles[corner_index] + t * PI * 0.5
			points.append(centers[corner_index] + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _draw_part_sides(
	part: ModelData,
	local_bottom_ring: PackedVector2Array,
	world_bottom_ring: PackedVector2Array,
	top_ring: PackedVector2Array,
	top_point_mode: bool,
	world_position: Vector2,
	world_rotation: float,
	base_height: float,
	top_height: float) -> void:
	if world_bottom_ring.size() < 2:
		return

	var side_records: Array[Dictionary] = []
	var rotation_radians: float = deg_to_rad(world_rotation)

	if top_point_mode:
		var top_local: Vector2 = part.top_end_point
		var top_world: Vector2 = world_position + top_local.rotated(rotation_radians)
		for index in world_bottom_ring.size():
			var next: int = (index + 1) % world_bottom_ring.size()
			var a: Vector2 = world_bottom_ring[index]
			var b: Vector2 = world_bottom_ring[next]
			var local_a: Vector2 = local_bottom_ring[index]
			var local_b: Vector2 = local_bottom_ring[next]
			var vertices := PackedVector2Array([
				_project_plan(a, base_height),
				_project_plan(b, base_height),
				_project_plan(top_world, top_height),
			])
			_append_side_record(side_records, part, local_a, local_b, vertices, base_height, top_height, a, b, top_world)
		_draw_sorted_side_records(side_records)
		return

	if top_ring.size() != world_bottom_ring.size():
		# A custom end ring with a different sample count is rendered against its
		# nearest corresponding sample rather than being dropped entirely.
		var top_center_world: Vector2 = world_position + part.top_end_point.rotated(rotation_radians)
		for index in world_bottom_ring.size():
			var next: int = (index + 1) % world_bottom_ring.size()
			var a: Vector2 = world_bottom_ring[index]
			var b: Vector2 = world_bottom_ring[next]
			var local_a: Vector2 = local_bottom_ring[index]
			var local_b: Vector2 = local_bottom_ring[next]
			var triangle := PackedVector2Array([
				_project_plan(a, base_height),
				_project_plan(b, base_height),
				_project_plan(top_center_world, top_height),
			])
			_append_side_record(side_records, part, local_a, local_b, triangle, base_height, top_height, a, b, top_center_world)
		_draw_sorted_side_records(side_records)
		return

	for index in world_bottom_ring.size():
		var next: int = (index + 1) % world_bottom_ring.size()
		var a: Vector2 = world_bottom_ring[index]
		var b: Vector2 = world_bottom_ring[next]
		var ta: Vector2 = world_position + top_ring[index].rotated(rotation_radians)
		var tb: Vector2 = world_position + top_ring[next].rotated(rotation_radians)
		var local_a: Vector2 = local_bottom_ring[index]
		var local_b: Vector2 = local_bottom_ring[next]
		var top_local_a: Vector2 = top_ring[index]
		var top_local_b: Vector2 = top_ring[next]

		var top_z_a: float = top_height + _top_endpoint_height(part, top_local_a)
		var top_z_b: float = top_height + _top_endpoint_height(part, top_local_b)
		var quad := PackedVector2Array([
			_project_plan(a, base_height),
			_project_plan(b, base_height),
			_project_plan(tb, top_z_b),
			_project_plan(ta, top_z_a),
		])
		var face_midpoint: Vector2 = (a + b + ta + tb) * 0.25
		_append_side_record(side_records, part, local_a, local_b, quad, base_height, maxf(top_z_a, top_z_b), a, b, face_midpoint)

	_draw_sorted_side_records(side_records)


func _append_side_record(
	records: Array[Dictionary],
	part: ModelData,
	local_a: Vector2,
	local_b: Vector2,
	vertices: PackedVector2Array,
	base_height: float,
	top_height: float,
	world_a: Vector2,
	world_b: Vector2,
	world_top_or_midpoint: Vector2) -> void:
	if vertices.size() < 3:
		return

	var local_edge: Vector2 = local_b - local_a
	if local_edge.length_squared() <= 0.000001:
		return

	var outward_local: Vector2 = Vector2(-local_edge.y, local_edge.x).normalized()
	var outward_view: Vector2 = _rotate(outward_local)
	if not render_all_four_sides and outward_view.x + outward_view.y <= 0.0:
		return

	var side_depth: float = _render_depth_key(world_top_or_midpoint)
	if top_height != base_height:
		var bottom_midpoint: Vector2 = (world_a + world_b) * 0.5
		var midpoint_depth: float = _render_depth_key(bottom_midpoint)
		side_depth = (side_depth + midpoint_depth) * 0.5

	records.append({
		"part": part,
		"local_a": local_a,
		"local_b": local_b,
		"vertices": vertices,
		"base_height": base_height,
		"top_height": top_height,
		"depth": side_depth,
		"sequence": records.size(),
	})


func _draw_sorted_side_records(records: Array[Dictionary]) -> void:
	if records.is_empty():
		return

	if render_all_four_sides:
		records.sort_custom(Callable(self, "_compare_side_records"))

	for record in records:
		var part: ModelData = record.get("part") as ModelData
		if part == null:
			continue
		_draw_side_surface(
			part,
			record.get("local_a", Vector2.ZERO) as Vector2,
			record.get("local_b", Vector2.ZERO) as Vector2,
			record.get("vertices", PackedVector2Array()),
			float(record.get("base_height", 0.0)),
			float(record.get("top_height", 0.0)))


func _compare_side_records(a: Dictionary, b: Dictionary) -> bool:
	var depth_a: float = float(a.get("depth", 0.0))
	var depth_b: float = float(b.get("depth", 0.0))
	if not is_equal_approx(depth_a, depth_b):
		return depth_a < depth_b
	return int(a.get("sequence", 0)) < int(b.get("sequence", 0))


func _top_endpoint_height(part: ModelData, _local_point: Vector2) -> float:
	if part.body_type == ModelData.BodyType.HYBRID:
		return maxf(part.top_profile_height_px, 0.0)
	return 0.0


func _draw_side_surface(
	part: ModelData,
	local_a: Vector2,
	local_b: Vector2,
	vertices: PackedVector2Array,
	base_height: float,
	top_height: float) -> void:
	if vertices.size() < 3:
		return

	var local_edge: Vector2 = local_b - local_a
	if local_edge.length_squared() <= 0.000001:
		return

	var outward_local: Vector2 = Vector2(-local_edge.y, local_edge.x).normalized()
	var outward_view: Vector2 = _rotate(outward_local)
	if not render_all_four_sides and outward_view.x + outward_view.y <= 0.0:
		return

	var face_target: ObjectFaceTextureData.FaceTarget = _face_target_for_normal(outward_local)
	var face_data: ObjectFaceTextureData = part.get_face_texture_set(face_target)
	var texture: Texture2D = face_data.get_texture("middle") if face_data != null else null
	var brightness: float = lerpf(
		side_brightness_far,
		side_brightness_near,
		clampf((outward_view.x + outward_view.y) * 0.5, 0.0, 1.0))

	if ghost_preview:
		brightness *= ghost_modulate.a

	if texture != null and face_data != null and face_data.texture_enabled:
		var length: float = local_edge.length()
		var texture_size: Vector2 = face_data.get_texture_size("middle")
		var safe_texture_width: float = maxf(texture_size.x, 1.0)
		var safe_texture_height: float = maxf(texture_size.y, 1.0)
		var height_span: float = maxf(absf(top_height - base_height), 1.0)
		var uv_scale_x: float = length / safe_texture_width
		var uv_scale_y: float = height_span / safe_texture_height
		var uvs := PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(uv_scale_x, 0.0),
			Vector2(uv_scale_x, uv_scale_y),
			Vector2(0.0, uv_scale_y),
		])
		if vertices.size() == 3:
			uvs.resize(3)
			draw_polygon(vertices, _surface_colors(vertices.size(), ghost_modulate), uvs, texture)
		else:
			draw_polygon(vertices, _surface_colors(vertices.size(), ghost_modulate), uvs, texture)
	else:
		draw_colored_polygon(vertices, _shade(part.base_color, brightness))

	if draw_outlines:
		var outline_color: Color = part.base_color
		outline_color.a *= ghost_modulate.a if ghost_preview else 1.0
		for index in vertices.size():
			draw_line(
				vertices[index],
				vertices[(index + 1) % vertices.size()],
				outline_color,
				outline_width,
				antialiased)


func _draw_part_top(
	part: ModelData,
	top_ring: PackedVector2Array,
	world_position: Vector2,
	world_rotation: float,
	top_height: float) -> void:
	if top_ring.size() < 3:
		return

	var center_local: Vector2 = Vector2.ZERO
	for point in top_ring:
		center_local += point
	center_local /= float(top_ring.size())

	var center_world: Vector2 = world_position + center_local.rotated(deg_to_rad(world_rotation))
	var face_data: ObjectFaceTextureData = part.top_face_textures
	var texture: Texture2D = face_data.get_texture("middle") if face_data != null else null

	for index in top_ring.size():
		var next: int = (index + 1) % top_ring.size()
		var a_world: Vector2 = world_position + top_ring[index].rotated(deg_to_rad(world_rotation))
		var b_world: Vector2 = world_position + top_ring[next].rotated(deg_to_rad(world_rotation))
		var vertices := PackedVector2Array([
			_project_plan(a_world, top_height),
			_project_plan(b_world, top_height),
			_project_plan(center_world, top_height),
		])

		if texture != null and face_data != null and face_data.texture_enabled:
			var uvs := PackedVector2Array([
				_top_uv(top_ring[index], part),
				_top_uv(top_ring[next], part),
				_top_uv(center_local, part),
			])
			draw_polygon(vertices, _surface_colors(3, ghost_modulate), uvs, texture)
		else:
			draw_colored_polygon(vertices, _shade(part.base_color, top_brightness))

	if draw_outlines:
		var outline := PackedVector2Array()
		for point in top_ring:
			var world_point: Vector2 = world_position + point.rotated(deg_to_rad(world_rotation))
			outline.append(_project_plan(world_point, top_height))
		if outline.size() >= 2:
			outline.append(outline[0])
			draw_polyline(outline, part.base_color, outline_width, antialiased)


func _draw_selection_outline(
	part: ModelData,
	world_bottom_ring: PackedVector2Array,
	top_ring: PackedVector2Array,
	world_position: Vector2,
	world_rotation: float,
	top_height: float) -> void:
	if world_bottom_ring.is_empty():
		return

	var color := Color(0.2, 0.9, 1.0, 0.95)
	var outline := PackedVector2Array()
	if not top_ring.is_empty():
		for point in top_ring:
			var world_point: Vector2 = world_position + point.rotated(deg_to_rad(world_rotation))
			outline.append(_project_plan(world_point, top_height))
	else:
		var top_point: Vector2 = world_position + part.top_end_point.rotated(deg_to_rad(world_rotation))
		var top_screen: Vector2 = _project_plan(top_point, top_height)
		for point in world_bottom_ring:
			var bottom_screen: Vector2 = _project_plan(point, 0.0)
			draw_line(bottom_screen, top_screen, color, 1.5, antialiased)
		return

	if outline.size() >= 2:
		outline.append(outline[0])
		draw_polyline(outline, color, 2.0, antialiased)


func _face_target_for_normal(normal: Vector2) -> ObjectFaceTextureData.FaceTarget:
	if absf(normal.x) >= absf(normal.y):
		return ObjectFaceTextureData.FaceTarget.RIGHT if normal.x > 0.0 else ObjectFaceTextureData.FaceTarget.LEFT
	return ObjectFaceTextureData.FaceTarget.FRONT if normal.y > 0.0 else ObjectFaceTextureData.FaceTarget.BACK


func _top_uv(local_point: Vector2, part: ModelData) -> Vector2:
	var size: Vector2 = part.top_face_textures.get_texture_size("middle") if part.top_face_textures != null else Vector2(16.0, 16.0)
	var point: Vector2 = local_point
	if part.rotate_top_texture_space:
		point = point.rotated(deg_to_rad(part.top_texture_rotation_degrees))
	return Vector2(
		point.x / maxf(size.x, 1.0),
		point.y / maxf(size.y, 1.0))


func _surface_colors(count: int, modulation: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for _index in count:
		colors.append(modulation)
	return colors


func _shade(color: Color, brightness: float) -> Color:
	return Color(
		color.r * brightness,
		color.g * brightness,
		color.b * brightness,
		color.a * (ghost_modulate.a if ghost_preview else 1.0))


func _project_plan(point: Vector2, height: float) -> Vector2:
	var q: Vector2 = _rotate(point - view_pivot)
	return Vector2(
		(q.x - q.y) * _scale.x,
		(q.x + q.y) * _scale.y - height) + view_pivot


func _rotate(value: Vector2) -> Vector2:
	match view_quadrant:
		1:
			return Vector2(-value.y, value.x)
		2:
			return -value
		3:
			return Vector2(value.y, -value.x)
	return value
