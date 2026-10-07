class_name PixelFloorRenderer
extends FloorRenderer

## Pixel-art renderer for FloorSpace polygons.
## The floor remains a normal world-space polygon, but its fill is
## rasterized into screen-aligned nearest-neighbour pixel blocks.

@export_category("Pixel Art")

@export_range(1, 16, 1)
var pixelation_rate: int = 2:
	set(value):
		pixelation_rate = maxi(value, 1)
		queue_redraw()

@export_range(1, 8, 1)
var outline_width_px: int = 1:
	set(value):
		outline_width_px = maxi(value, 1)
		queue_redraw()

@export_range(0.0, 1.0, 0.05)
var outline_darkness: float = 0.35:
	set(value):
		outline_darkness = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var pixelate_fills: bool = true:
	set(value):
		pixelate_fills = value
		queue_redraw()

@export var pixelate_textures: bool = true:
	set(value):
		pixelate_textures = value
		queue_redraw()

@export_category("Baking")

## Rasterize the floors once into a texture instead of re-running every cell
## on every redraw. It only re-bakes when a floor, a pixel setting or the
## projection actually changes.
@export var bake_enabled: bool = true:
	set(value):
		if bake_enabled == value:
			return
		bake_enabled = value
		_bake_signature = 0
		queue_redraw()

## While the view is animating (smooth turns), draw cheap vector floors and
## bake once when it settles, instead of re-baking on every frame.
@export var vector_while_turning: bool = true

## How long the projection must stay unchanged before a turn counts as settled.
@export_range(0.02, 1.0, 0.01)
var view_settle_time: float = 0.12


const MAX_BAKE_CELLS := 8192

var _bake_texture: ImageTexture
var _bake_origin := Vector2i.ZERO
var _bake_signature := 0
var _bake_ok := true
var _bake_live_fills: Array[Dictionary] = []
var _bake_projection_signature := 0
var _bake_watched_projection := 0
var _bake_last_change_frame := -100
var _bake_last_change_msec := 0
var _bake_view_animating := false
var _bake_settle_pending := false

var _texture_images: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	set_process(_isometric_mode and _projector != null)


func set_view(isometric: bool, projector: IsoWallRenderer) -> void:
	# Keep the pixel renderer synchronized with the same projector used by
	# FloorRenderer. During a smooth quadrant turn, the projector can change
	# its projection every frame, so this renderer must redraw every frame too.
	super.set_view(isometric, projector)
	set_process(_isometric_mode and _projector != null)


func _process(_delta: float) -> void:
	if not _isometric_mode or _projector == null:
		return

	if not is_instance_valid(_projector):
		_projector = null
		set_process(false)
		return

	# Only redraw when the projection really changed (smooth turns still stay
	# in sync). Redrawing unconditionally re-rasterized the floor every frame.
	var signature: int = _bake_projection_hash()
	if signature != _bake_watched_projection:
		_bake_watched_projection = signature
		queue_redraw()


func _draw() -> void:
	if _room_data == null:
		return

	if not bake_enabled:
		_draw_live()
		return

	_bake_track_projection()

	if _bake_view_animating and vector_while_turning:
		_draw_vector_floors()
		return

	_draw_baked()


# Original per-cell renderer, unchanged. Used when baking is off.
func _draw_live() -> void:
	if _room_data == null:
		return

	for floor in _room_data.floor_spaces:
		if floor == null or not floor.is_valid():
			continue
		_draw_pixel_floor(floor)


func _draw_pixel_floor(floor: FloorSpace) -> void:
	var projected: PackedVector2Array = _project_polygon(floor.polygon)

	if projected.size() < 3:
		return

	var texture: Texture2D = floor.texture

	if texture != null and pixelate_textures:
		_draw_pixel_textured_polygon(
			floor.polygon,
			projected,
			texture,
			floor.texture_tile_size,
			floor.color
		)
	elif pixelate_fills:
		_draw_pixel_polygon(
			projected,
			floor.color
		)
	else:
		draw_colored_polygon(projected, floor.color)

	_draw_pixel_outline(projected, floor.color)


func _draw_pixel_textured_polygon(
	plan_polygon: PackedVector2Array,
	screen_polygon: PackedVector2Array,
	texture: Texture2D,
	tile_size: float,
	fallback_color: Color
) -> void:
	var bounds := Rect2(
		screen_polygon[0],
		Vector2.ZERO
	)

	for point in screen_polygon:
		bounds = bounds.expand(point)

	var step: float = float(maxi(pixelation_rate, 1))
	var min_x: int = floori(bounds.position.x / step) - 1
	var max_x: int = ceili(bounds.end.x / step) + 1
	var min_y: int = floori(bounds.position.y / step) - 1
	var max_y: int = ceili(bounds.end.y / step) + 1

	var image: Image = _get_texture_image(texture)

	if image == null or image.is_empty():
		_draw_pixel_polygon(screen_polygon, fallback_color)
		return

	var safe_tile: float = maxf(tile_size, 1.0)

	for gy in range(min_y, max_y + 1):
		for gx in range(min_x, max_x + 1):
			var pixel_origin := Vector2(
				float(gx) * step,
				float(gy) * step
			)

			var sample_screen := pixel_origin + Vector2.ONE * step * 0.5

			if not Geometry2D.is_point_in_polygon(
				sample_screen,
				screen_polygon
			):
				continue

			var plan_point: Vector2 = _screen_to_plan(sample_screen)

			var sampled: Color = _sample_texture_at_plan(
				image,
				plan_point,
				safe_tile
			)

			# Preserve the floor's alpha while allowing the texture to
			# provide its own RGB/alpha when present.
			if sampled.a <= 0.001:
				continue

			sampled.a *= fallback_color.a

			draw_rect(
				Rect2(
					pixel_origin,
					Vector2.ONE * step
				),
				sampled,
				true
			)


func _draw_pixel_polygon(
	polygon: PackedVector2Array,
	color: Color
) -> void:
	if polygon.size() < 3:
		return

	var bounds := Rect2(
		polygon[0],
		Vector2.ZERO
	)

	for point in polygon:
		bounds = bounds.expand(point)

	var step: float = float(maxi(pixelation_rate, 1))
	var min_x: int = floori(bounds.position.x / step) - 1
	var max_x: int = ceili(bounds.end.x / step) + 1
	var min_y: int = floori(bounds.position.y / step) - 1
	var max_y: int = ceili(bounds.end.y / step) + 1

	for gy in range(min_y, max_y + 1):
		for gx in range(min_x, max_x + 1):
			var pixel_origin := Vector2(
				float(gx) * step,
				float(gy) * step
			)

			var sample_point := pixel_origin + Vector2.ONE * step * 0.5

			if not Geometry2D.is_point_in_polygon(
				sample_point,
				polygon
			):
				continue

			draw_rect(
				Rect2(
					pixel_origin,
					Vector2.ONE * step
				),
				color,
				true
			)


func _draw_pixel_outline(
	polygon: PackedVector2Array,
	base_color: Color
) -> void:
	if polygon.size() < 2:
		return

	var outline_color := Color(
		base_color.r * (1.0 - outline_darkness),
		base_color.g * (1.0 - outline_darkness),
		base_color.b * (1.0 - outline_darkness),
		minf(base_color.a * 0.9, 1.0)
	)

	for index in polygon.size():
		var a: Vector2 = _position_to_pixel(polygon[index])
		var b: Vector2 = _position_to_pixel(
			polygon[(index + 1) % polygon.size()]
		)

		_draw_pixel_line(
			a,
			b,
			outline_color
		)


func _draw_pixel_line(
	a: Vector2,
	b: Vector2,
	color: Color
) -> void:
	var distance: float = a.distance_to(b)

	if distance < 0.01:
		return

	var step: float = float(maxi(pixelation_rate, 1))
	var blocks: int = maxi(ceili(distance / step), 1)
	var line_size: float = step * float(maxi(outline_width_px, 1))

	for i in range(blocks + 1):
		var t: float = clampf(
			float(i) / float(blocks),
			0.0,
			1.0
		)

		var position: Vector2 = _position_to_pixel(a.lerp(b, t))

		draw_rect(
			Rect2(
				position - Vector2.ONE * line_size * 0.5,
				Vector2.ONE * line_size
			),
			color,
			true
		)


func _position_to_pixel(position: Vector2) -> Vector2:
	var step: float = float(maxi(pixelation_rate, 1))

	return Vector2(
		floorf(position.x / step) * step + step * 0.5,
		floorf(position.y / step) * step + step * 0.5
	)


func _screen_to_plan(screen_point: Vector2) -> Vector2:
	if not _isometric_mode or _projector == null:
		return screen_point

	return _projector.screen_to_plan(
		screen_point,
		0.0
	)


func _sample_texture_at_plan(
	image: Image,
	plan_point: Vector2,
	tile_size: float
) -> Color:
	var width: int = image.get_width()
	var height: int = image.get_height()

	if width <= 0 or height <= 0:
		return Color.WHITE

	var u: float = fposmod(
		plan_point.x / tile_size,
		1.0
	)

	var v: float = fposmod(
		plan_point.y / tile_size,
		1.0
	)

	var sample_x: int = clampi(
		floori(u * float(width)),
		0,
		width - 1
	)

	var sample_y: int = clampi(
		floori(v * float(height)),
		0,
		height - 1
	)

	return image.get_pixel(
		sample_x,
		sample_y
	)


func _get_texture_image(texture: Texture2D) -> Image:
	if texture == null:
		return null

	var key: int = texture.get_instance_id()

	if _texture_images.has(key):
		var cached: Variant = _texture_images[key]
		if cached is Image:
			return cached

	var image: Image = texture.get_image()

	if image == null or image.is_empty():
		return null

	# get_pixel() fails on VRAM-compressed images.
	if image.is_compressed():
		image.decompress()

	_texture_images[key] = image
	return image


# -------------------------------------------------------------------
# Baking
#
# Instead of one draw_rect per cell on every redraw, all floors are
# rasterized once into an Image on the same cell grid, uploaded as a texture
# and drawn with a single call. It is rebuilt only when the signature changes.
# -------------------------------------------------------------------

func rebake() -> void:
	_bake_signature = 0
	queue_redraw()


func _draw_baked() -> void:
	var floors: Array[FloorSpace] = _bake_valid_floors()
	var signature: int = _bake_hash(floors)

	if signature != _bake_signature:
		_bake_signature = signature
		_bake_ok = _bake(floors)

	if not _bake_ok:
		_draw_live()
		return

	# Smooth (non-pixelated) fills can't be baked; they sit under the texture.
	for entry in _bake_live_fills:
		draw_colored_polygon(entry["points"], entry["color"])

	if _bake_texture != null:
		var step: float = float(maxi(pixelation_rate, 1))
		draw_texture_rect(
			_bake_texture,
			Rect2(
				Vector2(_bake_origin) * step,
				_bake_texture.get_size() * step
			),
			false
		)


func _bake_valid_floors() -> Array[FloorSpace]:
	var result: Array[FloorSpace] = []
	for floor_space in _room_data.floor_spaces:
		if floor_space == null or not floor_space.is_valid():
			continue
		result.append(floor_space)
	return result


func _bake_hash(floors: Array[FloorSpace]) -> int:
	var parts: Array = [
		pixelation_rate,
		outline_width_px,
		outline_darkness,
		pixelate_fills,
		pixelate_textures,
		_isometric_mode,
		_bake_projection_hash(),
	]

	for floor_space in floors:
		var texture_id := 0
		if floor_space.texture != null:
			texture_id = floor_space.texture.get_instance_id()
		parts.append([
			floor_space.polygon,
			texture_id,
			floor_space.texture_tile_size,
			floor_space.color,
		])

	return hash(parts)


# Hashes where a few probe points land on screen, so any change of the
# projection (angle, quadrant, pivot, or a smooth turn) is detected no matter
# how it is implemented.
func _bake_projection_hash() -> int:
	if not _isometric_mode or _projector == null:
		return 0
	if not is_instance_valid(_projector):
		return 0

	return hash([
		_projector.project_point(Vector2.ZERO, 0.0),
		_projector.project_point(Vector2(128.0, 0.0), 0.0),
		_projector.project_point(Vector2(0.0, 128.0), 0.0),
	])


# -------------------------------------------------------------------
# Smooth-turn detection
#
# One projection change = bake right away (like any edit). Changes on
# consecutive frames = a turn animation: draw cheap vector floors until the
# projection has been still for view_settle_time, then bake once.
# -------------------------------------------------------------------

func _bake_track_projection() -> void:
	var signature: int = _bake_projection_hash()
	if signature == _bake_projection_signature:
		return

	_bake_projection_signature = signature

	var frame: int = Engine.get_frames_drawn()
	if frame - _bake_last_change_frame <= 2:
		_bake_view_animating = true

	_bake_last_change_frame = frame
	_bake_last_change_msec = Time.get_ticks_msec()

	if _bake_view_animating:
		_bake_arm_settle_check()


func _bake_arm_settle_check() -> void:
	if _bake_settle_pending or not is_inside_tree():
		return
	_bake_settle_pending = true
	get_tree().create_timer(view_settle_time).timeout.connect(
		_bake_on_settle_check
	)


func _bake_on_settle_check() -> void:
	_bake_settle_pending = false

	var quiet: float = float(
		Time.get_ticks_msec() - _bake_last_change_msec
	) / 1000.0
	if quiet < view_settle_time * 0.9:
		_bake_arm_settle_check()
		return

	_bake_view_animating = false
	queue_redraw()


# Cheap stand-in while the view is animating: textures keep tiling through
# UVs, but nothing is pixelated.
func _draw_vector_floors() -> void:
	for floor_space in _bake_valid_floors():
		var projected: PackedVector2Array = _project_polygon(
			floor_space.polygon
		)
		if projected.size() < 3:
			continue

		var texture: Texture2D = floor_space.texture
		if texture != null and pixelate_textures:
			var tile: float = maxf(floor_space.texture_tile_size, 1.0)
			var uvs := PackedVector2Array()
			for point in floor_space.polygon:
				uvs.append(point / tile)

			if uvs.size() == projected.size():
				draw_colored_polygon(
					projected,
					Color(1.0, 1.0, 1.0, floor_space.color.a),
					uvs,
					texture
				)
				continue

		draw_colored_polygon(projected, floor_space.color)


# -------------------------------------------------------------------
# Bake
# -------------------------------------------------------------------

func _bake(floors: Array[FloorSpace]) -> bool:
	_bake_texture = null
	_bake_live_fills.clear()

	var step: float = float(maxi(pixelation_rate, 1))
	var projected_polygons: Array[PackedVector2Array] = []
	var has_points := false
	var min_point := Vector2.ZERO
	var max_point := Vector2.ZERO

	for floor_space in floors:
		var projected: PackedVector2Array = _project_polygon(
			floor_space.polygon
		)
		projected_polygons.append(projected)

		if projected.size() < 3:
			continue

		for point in projected:
			if not has_points:
				min_point = point
				max_point = point
				has_points = true
				continue
			min_point = Vector2(
				minf(min_point.x, point.x),
				minf(min_point.y, point.y)
			)
			max_point = Vector2(
				maxf(max_point.x, point.x),
				maxf(max_point.y, point.y)
			)

	if not has_points:
		return true

	var margin: int = maxi(outline_width_px, 1) + 2
	var origin := Vector2i(
		floori(min_point.x / step),
		floori(min_point.y / step)
	) - Vector2i(margin, margin)
	var far_corner := Vector2i(
		ceili(max_point.x / step),
		ceili(max_point.y / step)
	) + Vector2i(margin, margin)
	var cells: Vector2i = far_corner - origin

	if cells.x > MAX_BAKE_CELLS or cells.y > MAX_BAKE_CELLS:
		push_warning(
			"PixelFloorRenderer: baked area is too large (%d x %d cells); drawing live instead."
			% [cells.x, cells.y]
		)
		return false

	var canvas: Image = Image.create(
		cells.x,
		cells.y,
		false,
		Image.FORMAT_RGBA8
	)
	var to_plan: Transform2D = _bake_screen_to_plan()

	for i in floors.size():
		var floor_space: FloorSpace = floors[i]
		var projected: PackedVector2Array = projected_polygons[i]

		if projected.size() < 3:
			continue

		var texture: Texture2D = floor_space.texture

		if texture != null and pixelate_textures:
			_bake_textured_polygon(
				canvas,
				origin,
				projected,
				to_plan,
				texture,
				floor_space.texture_tile_size,
				floor_space.color
			)
		elif pixelate_fills:
			_bake_polygon(canvas, origin, projected, floor_space.color)
		else:
			_bake_live_fills.append({
				"points": projected,
				"color": floor_space.color,
			})

		_bake_outline(canvas, origin, projected, floor_space.color)

	_bake_origin = origin
	_bake_texture = ImageTexture.create_from_image(canvas)
	return true


# The screen -> plan mapping is affine, so it is sampled once and reused as a
# Transform2D instead of calling the projector for every cell.
func _bake_screen_to_plan() -> Transform2D:
	if not _isometric_mode or _projector == null:
		return Transform2D.IDENTITY

	var plan_origin: Vector2 = _projector.screen_to_plan(Vector2.ZERO, 0.0)
	var x_axis: Vector2 = (
		_projector.screen_to_plan(Vector2.RIGHT, 0.0) - plan_origin
	)
	var y_axis: Vector2 = (
		_projector.screen_to_plan(Vector2.DOWN, 0.0) - plan_origin
	)
	return Transform2D(x_axis, y_axis, plan_origin)


func _bake_textured_polygon(
		canvas: Image,
		origin: Vector2i,
		screen_polygon: PackedVector2Array,
		to_plan: Transform2D,
		texture: Texture2D,
		tile_size: float,
		fallback_color: Color) -> void:
	var image: Image = _get_texture_image(texture)

	if image == null or image.is_empty():
		_bake_polygon(canvas, origin, screen_polygon, fallback_color)
		return

	var tex_w: int = image.get_width()
	var tex_h: int = image.get_height()
	var safe_tile: float = maxf(tile_size, 1.0)
	var step: float = float(maxi(pixelation_rate, 1))
	var plan_step: Vector2 = to_plan.x * step
	var canvas_w: int = canvas.get_width()
	var canvas_h: int = canvas.get_height()

	for span in _bake_polygon_spans(screen_polygon, step):
		var cy: int = span.x - origin.y
		if cy < 0 or cy >= canvas_h:
			continue

		var plan: Vector2 = to_plan * Vector2(
			(float(span.y) + 0.5) * step,
			(float(span.x) + 0.5) * step
		)

		for gx in range(span.y, span.z + 1):
			var cx: int = gx - origin.x

			if cx >= 0 and cx < canvas_w:
				var tx: int = clampi(
					floori(fposmod(plan.x / safe_tile, 1.0) * float(tex_w)),
					0,
					tex_w - 1
				)
				var ty: int = clampi(
					floori(fposmod(plan.y / safe_tile, 1.0) * float(tex_h)),
					0,
					tex_h - 1
				)
				var texel: Color = image.get_pixel(tx, ty)

				if texel.a > 0.001:
					texel.a *= fallback_color.a
					_bake_blend_pixel(canvas, cx, cy, texel)

			plan += plan_step


func _bake_outline(
		canvas: Image,
		origin: Vector2i,
		polygon: PackedVector2Array,
		base_color: Color) -> void:
	if polygon.size() < 2:
		return

	var outline_color := Color(
		base_color.r * (1.0 - outline_darkness),
		base_color.g * (1.0 - outline_darkness),
		base_color.b * (1.0 - outline_darkness),
		minf(base_color.a * 0.9, 1.0)
	)

	for index in polygon.size():
		_bake_line(
			canvas,
			origin,
			polygon[index],
			polygon[(index + 1) % polygon.size()],
			outline_color
		)


# -------------------------------------------------------------------
# Cell painting
# -------------------------------------------------------------------

func _bake_polygon(
		canvas: Image,
		origin: Vector2i,
		polygon: PackedVector2Array,
		color: Color) -> void:
	var step: float = float(maxi(pixelation_rate, 1))
	for span in _bake_polygon_spans(polygon, step):
		_bake_span(
			canvas,
			span.y - origin.x,
			span.x - origin.y,
			span.z - span.y + 1,
			color
		)


# Scanline fill: for each cell row, the runs of cells whose centers are inside
# the polygon. Returns Vector3i(row, first_cell, last_cell).
func _bake_polygon_spans(
		polygon: PackedVector2Array,
		step: float) -> Array[Vector3i]:
	var spans: Array[Vector3i] = []
	var count: int = polygon.size()
	if count < 3:
		return spans

	var min_y: float = polygon[0].y
	var max_y: float = min_y
	for point in polygon:
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)

	var xs: Array[float] = []
	for row in range(floori(min_y / step) - 1, ceili(max_y / step) + 2):
		var y: float = (float(row) + 0.5) * step
		xs.clear()

		for i in count:
			var p: Vector2 = polygon[i]
			var q: Vector2 = polygon[(i + 1) % count]
			if (p.y <= y) != (q.y <= y):
				xs.append(p.x + (y - p.y) / (q.y - p.y) * (q.x - p.x))

		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var first: int = ceili(xs[k] / step - 0.5)
			var last: int = ceili(xs[k + 1] / step - 0.5) - 1
			if last >= first:
				spans.append(Vector3i(row, first, last))

	return spans


func _bake_line(
		canvas: Image,
		origin: Vector2i,
		a: Vector2,
		b: Vector2,
		color: Color) -> void:
	var distance: float = a.distance_to(b)
	if distance < 0.01:
		return

	var step: float = float(maxi(pixelation_rate, 1))
	var blocks: int = maxi(ceili(distance / step), 1)

	for i in range(blocks + 1):
		var t: float = clampf(float(i) / float(blocks), 0.0, 1.0)
		_bake_block(canvas, origin, a.lerp(b, t), color)


# One line block: outline_width_px x outline_width_px cells centered on the
# cell under the point. Always grid-aligned, including even widths.
func _bake_block(
		canvas: Image,
		origin: Vector2i,
		screen_point: Vector2,
		color: Color) -> void:
	var step: float = float(maxi(pixelation_rate, 1))
	var width: int = maxi(outline_width_px, 1)
	var cell := Vector2i(
		floori(screen_point.x / step),
		floori(screen_point.y / step)
	)
	var offset: int = (width - 1) >> 1

	for row in width:
		_bake_span(
			canvas,
			cell.x - offset - origin.x,
			cell.y - offset + row - origin.y,
			width,
			color
		)


func _bake_span(
		canvas: Image,
		x: int,
		y: int,
		length: int,
		color: Color) -> void:
	if length <= 0:
		return

	if color.a >= 0.999:
		canvas.fill_rect(Rect2i(x, y, length, 1), color)
		return

	if y < 0 or y >= canvas.get_height():
		return

	for cx in range(maxi(x, 0), mini(x + length, canvas.get_width())):
		_bake_blend_pixel(canvas, cx, y, color)


func _bake_blend_pixel(
		canvas: Image,
		x: int,
		y: int,
		source: Color) -> void:
	if source.a >= 0.999:
		canvas.set_pixel(x, y, source)
		return

	var dest: Color = canvas.get_pixel(x, y)
	var out_a: float = source.a + dest.a * (1.0 - source.a)
	if out_a <= 0.0001:
		return

	var inv: float = 1.0 / out_a
	var keep: float = dest.a * (1.0 - source.a)
	canvas.set_pixel(
		x,
		y,
		Color(
			(source.r * source.a + dest.r * keep) * inv,
			(source.g * source.a + dest.g * keep) * inv,
			(source.b * source.a + dest.b * keep) * inv,
			out_a
		)
	)
