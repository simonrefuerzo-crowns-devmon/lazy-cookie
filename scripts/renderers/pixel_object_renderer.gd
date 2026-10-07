extends ObjectRenderer
class_name PixelObjectRenderer

## Baked pixel-art version of ObjectRenderer.
##
## Object geometry is still defined in normal world-space coordinates.
## The visible object shapes are rasterized to an RGBA8 Image using the
## configured pixelation rate, uploaded once as an ImageTexture, and then
## drawn with one texture call until the object data/settings change.
##
## Unlike PixelWallRenderer, ObjectRenderer has no texture construction stage,
## so object fills and outlines are derived from ObjectData / ModelData colors.

@export_category("Pixel Art")

@export_range(1, 16, 1)
var pixelation_rate: int = 2:
	set(value):
		pixelation_rate = maxi(value, 1)
		_invalidate_bake()

@export_range(1, 8, 1)
var line_width_px: int = 1:
	set(value):
		line_width_px = maxi(value, 1)
		_invalidate_bake()

@export_range(0.0, 1.0, 0.05)
var line_darkness: float = 0.35:
	set(value):
		line_darkness = clampf(value, 0.0, 1.0)
		_invalidate_bake()

@export var pixelate_fills: bool = true:
	set(value):
		if pixelate_fills == value:
			return
		pixelate_fills = value
		_invalidate_bake()

@export_category("Baking")

## Rasterize the pixel object renderer into a texture.
## When disabled, the original ObjectRenderer vector drawing is used.
@export var bake_enabled: bool = true:
	set(value):
		if bake_enabled == value:
			return
		bake_enabled = value
		_invalidate_bake()

## Maximum baked width/height in pixel cells.
## Large rooms can exceed this and automatically fall back to live drawing.
@export_range(256, 8192, 256)
var max_bake_cells: int = 4096

## Additional transparent padding around the baked object bounds.
@export_range(0, 32, 1)
var bake_margin_cells: int = 2


const BAKE_SIGNATURE_EMPTY: int = 0


var _bake_texture: ImageTexture = null
var _bake_origin: Vector2i = Vector2i.ZERO
var _bake_signature: int = BAKE_SIGNATURE_EMPTY
var _bake_ok: bool = true


func _ready() -> void:
	super._ready()

	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func set_room(room: RoomData) -> void:
	super.set_room(room)
	_invalidate_bake()


func set_selected_object(object: ObjectData) -> void:
	super.set_selected_object(object)
	_invalidate_bake()


func clear_selection() -> void:
	super.clear_selection()
	_invalidate_bake()


func rebake() -> void:
	_invalidate_bake()


func _invalidate_bake() -> void:
	_bake_signature = BAKE_SIGNATURE_EMPTY
	_bake_texture = null

	if is_inside_tree():
		queue_redraw()


func _on_room_changed() -> void:
	_invalidate_bake()


# -------------------------------------------------------------------------
# Main drawing
# -------------------------------------------------------------------------

func _draw() -> void:
	if _room_data == null:
		return

	# A non-pixel fill is intentionally left to the original ObjectRenderer.
	if not bake_enabled or not pixelate_fills:
		_draw_live()
		return

	_draw_baked()


func _draw_live() -> void:
	if _room_data == null:
		return

	for object_data: ObjectData in _room_data.objects:
		if object_data == null:
			continue

		# Use the original ObjectRenderer implementation unchanged.
		super._draw_object(object_data)


func _draw_baked() -> void:
	var objects: Array[ObjectData] = _get_render_objects()

	if objects.is_empty():
		return

	var signature: int = _calculate_bake_signature(objects)

	if signature != _bake_signature:
		_bake_signature = signature
		_bake_ok = _bake(objects)

	if not _bake_ok:
		_draw_live()
		return

	if _bake_texture == null:
		return

	var step: float = float(maxi(pixelation_rate, 1))
	var texture_size: Vector2 = _bake_texture.get_size()

	draw_texture_rect(
		_bake_texture,
		Rect2(
			Vector2(_bake_origin) * step,
			texture_size * step
		),
		false
	)


func _get_render_objects() -> Array[ObjectData]:
	var result: Array[ObjectData] = []

	if _room_data == null:
		return result

	for object_data: ObjectData in _room_data.objects:
		if object_data != null:
			result.append(object_data)

	return result


# -------------------------------------------------------------------------
# Bake signature
# -------------------------------------------------------------------------

func _calculate_bake_signature(objects: Array[ObjectData]) -> int:
	var values: Array = [
		pixelation_rate,
		line_width_px,
		line_darkness,
		draw_selection,
		selected_object,
		rounded_corner_segments,
		cylinder_segments,
		max_bake_cells,
		bake_margin_cells,
	]

	for object_data: ObjectData in objects:
		values.append(_get_object_bake_signature(object_data))

	return hash(values)


func _get_object_bake_signature(object_data: ObjectData) -> Array:
	var values: Array = [
		object_data.get_instance_id(),
		object_data.position,
		object_data.rotation_degrees,
		object_data.size_px,
		object_data.base_color,
		object_data.body_shape,
		object_data.has_corners,
		object_data.curved_corners,
		object_data.corner_radius_px,
		object_data.object_model != null,
		object_data == selected_object,
	]

	if object_data.object_model != null:
		values.append(
			_get_model_bake_signature(
				object_data.object_model
			)
		)

	return values


func _get_model_bake_signature(model: ModelData) -> Array:
	if model == null:
		return []

	var values: Array = [
		model.get_instance_id(),
		model.model_name,
		model.base_color,
		model.size_px,
		model.local_position,
		model.local_rotation_degrees,
		model.local_height_offset_px,
		model.height_px,
		model.body_type,
		model.flat_bottom_shape,
		model.has_corners,
		model.corner_style,
		model.corner_radius_px,
		model.top_end_point,
		model.top_end_size_px,
	]

	for part: ModelData in model.parts:
		if part != null:
			values.append(
				_get_model_bake_signature(part)
			)

	return values


# -------------------------------------------------------------------------
# World polygon extraction
# -------------------------------------------------------------------------

func _get_object_world_polygons(
		object_data: ObjectData) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []

	if object_data == null:
		return result

	if object_data.object_model != null:
		_collect_custom_model_polygons(
			object_data.object_model,
			object_data.position,
			object_data.rotation_degrees,
			result
		)
		return result

	var footprint: PackedVector2Array = _build_footprint(object_data)

	if footprint.size() < 3:
		return result

	var radians: float = deg_to_rad(
		object_data.rotation_degrees
	)

	var world_polygon: PackedVector2Array = PackedVector2Array()

	for point: Vector2 in footprint:
		world_polygon.append(
			object_data.position
			+ point.rotated(radians)
		)

	result.append(world_polygon)

	return result


func _get_all_object_bake_polygons(
		objects: Array[ObjectData]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for object_data: ObjectData in objects:
		var polygons: Array[PackedVector2Array] = (
			_get_object_world_polygons(object_data)
		)

		for polygon: PackedVector2Array in polygons:
			if polygon.size() < 3:
				continue

			result.append({
				"polygon": polygon,
				"color": object_data.base_color,
				"selected": object_data == selected_object,
				"position": object_data.position,
			})

	return result


# -------------------------------------------------------------------------
# Bake
# -------------------------------------------------------------------------

func _bake(objects: Array[ObjectData]) -> bool:
	_bake_texture = null
	_bake_origin = Vector2i.ZERO

	var records: Array[Dictionary] = (
		_get_all_object_bake_polygons(objects)
	)

	if records.is_empty():
		return true

	var bounds: Rect2
	var has_bounds: bool = false

	for record: Dictionary in records:
		var polygon: PackedVector2Array = record["polygon"]

		for point: Vector2 in polygon:
			if not has_bounds:
				bounds = Rect2(
					point,
					Vector2.ZERO
				)
				has_bounds = true
			else:
				bounds = bounds.expand(point)

	if not has_bounds:
		return true

	var step: float = float(
		maxi(pixelation_rate, 1)
	)

	var margin: int = maxi(
		bake_margin_cells,
		line_width_px + 1
	)

	var origin: Vector2i = Vector2i(
		floori(bounds.position.x / step),
		floori(bounds.position.y / step)
	) - Vector2i(
		margin,
		margin
	)

	var far_corner: Vector2i = Vector2i(
		ceili(bounds.end.x / step),
		ceili(bounds.end.y / step)
	) + Vector2i(
		margin,
		margin
	)

	var cells: Vector2i = far_corner - origin

	if cells.x <= 0 or cells.y <= 0:
		return true

	if cells.x > max_bake_cells or cells.y > max_bake_cells:
		push_warning(
			"PixelObjectRenderer: baked area is too large (%d x %d cells); drawing live instead."
			% [cells.x, cells.y]
		)
		return false

	var canvas: Image = Image.create(
		cells.x,
		cells.y,
		false,
		Image.FORMAT_RGBA8
	)

	# Preserve normal ObjectRenderer painter order:
	# later objects in RoomData.objects draw over earlier ones.
	for record: Dictionary in records:
		var polygon: PackedVector2Array = record["polygon"]
		var color: Color = record["color"]

		_bake_polygon(
			canvas,
			origin,
			polygon,
			color
		)

		if record["selected"] and draw_selection:
			_bake_polygon_outline(
				canvas,
				origin,
				polygon,
				color
			)

	# Draw selection marker once per selected object.
	if draw_selection and selected_object != null:
		_bake_selection_marker(
			canvas,
			origin,
			selected_object.position
		)

	_bake_origin = origin
	_bake_texture = ImageTexture.create_from_image(canvas)

	if _bake_texture == null:
		return false

	return true


# -------------------------------------------------------------------------
# Polygon fill
# -------------------------------------------------------------------------

func _bake_polygon(
		canvas: Image,
		origin: Vector2i,
		polygon: PackedVector2Array,
		color: Color) -> void:
	if polygon.size() < 3:
		return

	var step: float = float(
		maxi(pixelation_rate, 1)
	)

	var spans: Array[Vector3i] = (
		_bake_polygon_spans(
			polygon,
			step
		)
	)

	for span: Vector3i in spans:
		var row: int = span.x
		var first_cell: int = span.y
		var last_cell: int = span.z

		_bake_span(
			canvas,
			first_cell - origin.x,
			row - origin.y,
			last_cell - first_cell + 1,
			color
		)


func _bake_polygon_spans(
		polygon: PackedVector2Array,
	step: float) -> Array[Vector3i]:
	var spans: Array[Vector3i] = []

	var count: int = polygon.size()

	if count < 3:
		return spans

	var min_y: float = polygon[0].y
	var max_y: float = min_y

	for point: Vector2 in polygon:
		min_y = minf(
			min_y,
			point.y
		)
		max_y = maxf(
			max_y,
			point.y
		)

	var first_row: int = floori(
		min_y / step
	) - 1

	var last_row: int = ceili(
		max_y / step
	) + 1

	var intersections: Array[float] = []

	for row: int in range(
		first_row,
		last_row + 1
	):
		var sample_y: float = (
			float(row) + 0.5
		) * step

		intersections.clear()

		for i: int in count:
			var p: Vector2 = polygon[i]
			var q: Vector2 = polygon[
				(i + 1) % count
			]

			if (p.y <= sample_y) != (q.y <= sample_y):
				var denominator: float = q.y - p.y

				if absf(denominator) <= 0.00001:
					continue

				var x_value: float = (
					p.x
					+ (sample_y - p.y)
					/ denominator
					* (q.x - p.x)
				)

				intersections.append(x_value)

		intersections.sort()

		var pair_count: int = intersections.size() / 2

		for pair_index: int in pair_count:
			var x0: float = intersections[
				pair_index * 2
			]

			var x1: float = intersections[
				pair_index * 2 + 1
			]

			if x1 < x0:
				var temp: float = x0
				x0 = x1
				x1 = temp

			var first_cell: int = ceili(
				x0 / step - 0.5
			)

			var last_cell: int = ceili(
				x1 / step - 0.5
			) - 1

			if last_cell >= first_cell:
				spans.append(
					Vector3i(
						row,
						first_cell,
						last_cell
					)
				)

	return spans


# -------------------------------------------------------------------------
# Pixel outline
# -------------------------------------------------------------------------

func _bake_polygon_outline(
		canvas: Image,
		origin: Vector2i,
		polygon: PackedVector2Array,
		base_color: Color) -> void:
	if polygon.size() < 2:
		return

	var outline_color: Color = _line_color(
		base_color
	)

	for index: int in polygon.size():
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[
			(index + 1) % polygon.size()
		]

		_bake_line(
			canvas,
			origin,
			a,
			b,
			outline_color
		)


func _bake_line(
		canvas: Image,
		origin: Vector2i,
		a: Vector2,
		b: Vector2,
		color: Color) -> void:
	var distance: float = a.distance_to(b)

	if distance < 0.01:
		return

	var step: float = float(
		maxi(pixelation_rate, 1)
	)

	var blocks: int = maxi(
		ceili(distance / step),
		1
	)

	for i: int in range(blocks + 1):
		var t: float = clampf(
			float(i) / float(blocks),
			0.0,
			1.0
		)

		var position: Vector2 = a.lerp(
			b,
			t
		)

		_bake_block(
			canvas,
			origin,
			position,
			color
		)


func _bake_block(
		canvas: Image,
		origin: Vector2i,
		world_position: Vector2,
		color: Color) -> void:
	var step: float = float(
		maxi(pixelation_rate, 1)
	)

	var cell: Vector2i = Vector2i(
		floori(world_position.x / step),
		floori(world_position.y / step)
	)

	var width: int = maxi(
		line_width_px,
		1
	)

	var offset: int = (
		width - 1
	) >> 1

	for row: int in width:
		var target_x: int = (
			cell.x
			- offset
			- origin.x
		)

		var target_y: int = (
			cell.y
			- offset
			+ row
			- origin.y
		)

		_bake_span(
			canvas,
			target_x,
			target_y,
			width,
			color
		)


func _line_color(base_color: Color) -> Color:
	var brightness: float = 1.0 - line_darkness

	return Color(
		base_color.r * brightness,
		base_color.g * brightness,
		base_color.b * brightness,
		base_color.a
	)


# -------------------------------------------------------------------------
# Selection marker
# -------------------------------------------------------------------------

func _bake_selection_marker(
		canvas: Image,
		origin: Vector2i,
		world_position: Vector2) -> void:
	var step: float = float(
		maxi(pixelation_rate, 1)
	)

	var radius: float = 3.0

	var min_cell_x: int = floori(
		(world_position.x - radius) / step
	)

	var max_cell_x: int = ceili(
		(world_position.x + radius) / step
	)

	var min_cell_y: int = floori(
		(world_position.y - radius) / step
	)

	var max_cell_y: int = ceili(
		(world_position.y + radius) / step
	)

	var selection_color: Color = Color(
		0.2,
		0.9,
		1.0,
		0.9
	)

	var radius_squared: float = radius * radius

	for cell_y: int in range(
		min_cell_y,
		max_cell_y + 1
	):
		for cell_x: int in range(
			min_cell_x,
			max_cell_x + 1
		):
			var sample_point: Vector2 = (
				Vector2(
					float(cell_x),
					float(cell_y)
				) * step
				+ Vector2.ONE * step * 0.5
			)

			if sample_point.distance_squared_to(
				world_position
			) > radius_squared:
				continue

			_bake_blend_pixel(
				canvas,
				cell_x - origin.x,
				cell_y - origin.y,
				selection_color
			)


# -------------------------------------------------------------------------
# Image compositing
# -------------------------------------------------------------------------

func _bake_span(
		canvas: Image,
		x: int,
		y: int,
		length: int,
		color: Color) -> void:
	if length <= 0:
		return

	if y < 0 or y >= canvas.get_height():
		return

	var start_x: int = maxi(
		x,
		0
	)

	var end_x: int = mini(
		x + length,
		canvas.get_width()
	)

	if end_x <= start_x:
		return

	if color.a >= 0.999:
		canvas.fill_rect(
			Rect2i(
				start_x,
				y,
				end_x - start_x,
				1
			),
			color
		)
		return

	for current_x: int in range(
		start_x,
		end_x
	):
		_bake_blend_pixel(
			canvas,
			current_x,
			y,
			color
		)


func _bake_blend_pixel(
		canvas: Image,
		x: int,
		y: int,
		source: Color) -> void:
	if x < 0 or y < 0:
		return

	if x >= canvas.get_width():
		return

	if y >= canvas.get_height():
		return

	if source.a >= 0.999:
		canvas.set_pixel(
			x,
			y,
			source
		)
		return

	var dest: Color = canvas.get_pixel(
		x,
		y
	)

	var out_alpha: float = (
		source.a
		+ dest.a * (1.0 - source.a)
	)

	if out_alpha <= 0.0001:
		return

	var inverse_alpha: float = (
		1.0 / out_alpha
	)

	var retained_destination: float = (
		dest.a * (1.0 - source.a)
	)

	canvas.set_pixel(
		x,
		y,
		Color(
			(
				source.r * source.a
				+ dest.r * retained_destination
			) * inverse_alpha,
			(
				source.g * source.a
				+ dest.g * retained_destination
			) * inverse_alpha,
			(
				source.b * source.a
				+ dest.b * retained_destination
			) * inverse_alpha,
			out_alpha
		)
	)
