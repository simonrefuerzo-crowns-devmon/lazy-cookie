extends IsoWallRenderer
class_name PixelWallRenderer


@export_category("Pixel Art")

@export_range(1, 16, 1)
var pixelation_rate: int = 2:
	set(value):
		pixelation_rate = maxi(value, 1)
		queue_redraw()

@export_range(1, 8, 1)
var line_width_px: int = 1:
	set(value):
		line_width_px = maxi(value, 1)
		queue_redraw()

@export_range(0.0, 1.0, 0.05)
var line_darkness: float = 0.35:
	set(value):
		line_darkness = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var counter_iso_textures: bool = true:
	set(value):
		counter_iso_textures = value
		queue_redraw()

@export var pixelate_fills: bool = true:
	set(value):
		pixelate_fills = value
		queue_redraw()


var _texture_images: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


# -------------------------------------------------------------------
# Main drawing
# -------------------------------------------------------------------

func _draw() -> void:
	if view_mode == ViewMode.ISO1_NO_WALLS:
		return

	_scale = Vector2(
		cos(deg_to_rad(projection_angle)),
		sin(deg_to_rad(projection_angle))
	)

	var pieces: Array[Dictionary] = _visible_pieces()
	var back_depth: float = _get_back_depth(pieces)

	# ---------------------------------------------------------------
	# Wall faces
	# ---------------------------------------------------------------

	for piece in pieces:
		if not _piece_allowed(piece, back_depth):
			continue

		_draw_pixel_face(piece)

	# ---------------------------------------------------------------
	# Room/top surfaces
	# ---------------------------------------------------------------

	for footprint in get_footprints():
		if not _footprint_allowed(footprint, back_depth):
			continue

		var color: Color = footprint["color"]
		var segment_value: Variant = footprint.get("segment", null)

		if segment_value is WallSegment:
			var segment: WallSegment = segment_value as WallSegment
			color = segment.get_top_filler_color()

		var top: PackedVector2Array = _project_all(
			footprint["points"],
			wall_height
		)

		if pixelate_fills:
			_draw_pixel_polygon(
				top,
				_shade(color, top_brightness)
			)
		else:
			draw_colored_polygon(
				top,
				_shade(color, top_brightness)
			)

	# ---------------------------------------------------------------
	# Top outlines / corner lines
	# ---------------------------------------------------------------

	for path in _paths:
		if not _path_allowed(path, back_depth):
			continue

		var points: PackedVector2Array = path["points"]

		if points.size() < 2:
			continue

		var path_color: Color = path["color"]

		# Transparent paths are still drawn, but without texture
		# sampling because they may not represent solid wall faces.
		if path_color.a < 0.99:
			_draw_pixel_wireframe(path)
			continue

		_draw_pixel_top_path(path)


# -------------------------------------------------------------------
# Wall face
# -------------------------------------------------------------------

func _draw_pixel_face(piece: Dictionary) -> void:
	var a: Vector2 = piece["a"]
	var b: Vector2 = piece["b"]

	var color: Color = piece["color"]

	var a_floor: Vector2 = _project(a, 0.0)
	var b_floor: Vector2 = _project(b, 0.0)
	var a_top: Vector2 = _project(a, wall_height)
	var b_top: Vector2 = _project(b, wall_height)

	var segment_value: Variant = piece.get("segment", null)
	var segment: WallSegment = segment_value as WallSegment

	var face_brightness: float = _face_brightness(piece["view_normal"])

	var face_side: int = int(piece.get("face_side", 0))

	var texture: Texture2D = null

	if textured_walls and segment != null:
		texture = segment.get_texture_for_side(face_side)

	# ---------------------------------------------------------------
	# Counter-isometric textured face
	#
	# The geometry is still projected iso.
	# The texture pixels themselves remain axis-aligned on screen.
	# ---------------------------------------------------------------

	if counter_iso_textures and texture != null:
		_draw_counter_iso_texture(
			a_floor,
			b_floor,
			a_top,
			b_top,
			texture,
			face_brightness,
			a.distance_to(b)
		)
	else:
		# Fallback for non-textured walls.
		var shaded_color: Color = _shade(
			color,
			face_brightness
		)

		if pixelate_fills:
			_draw_pixel_polygon(
				PackedVector2Array([
					a_floor,
					b_floor,
					b_top,
					a_top
				]),
				shaded_color
			)
		else:
			draw_colored_polygon(
				PackedVector2Array([
					a_floor,
					b_floor,
					b_top,
					a_top
				]),
				shaded_color
			)

	# ---------------------------------------------------------------
	# Bottom wall line
	# ---------------------------------------------------------------

	if texture != null and counter_iso_textures:
		_draw_sampled_line(
			a_floor,
			b_floor,
			texture,
			face_brightness,
			0.0,
			a.distance_to(b)
		)
	else:
		_draw_pixel_line(
			a_floor,
			b_floor,
			_shade(color, face_brightness)
		)

	# ---------------------------------------------------------------
	# Vertical corners
	# ---------------------------------------------------------------

	if piece["vertical_a"]:
		if texture != null and counter_iso_textures:
			_draw_sampled_vertical(
				a_floor,
				a_top,
				texture,
				face_brightness,
				0.0
			)
		else:
			_draw_pixel_line(
				a_floor,
				a_top,
				_shade(color, face_brightness)
			)

	if piece["vertical_b"]:
		if texture != null and counter_iso_textures:
			_draw_sampled_vertical(
				b_floor,
				b_top,
				texture,
				face_brightness,
				1.0
			)
		else:
			_draw_pixel_line(
				b_floor,
				b_top,
				_shade(color, face_brightness)
			)


# -------------------------------------------------------------------
# Counter-ISO texture renderer
# -------------------------------------------------------------------

func _draw_counter_iso_texture(
	a_floor: Vector2,
	b_floor: Vector2,
	a_top: Vector2,
	b_top: Vector2,
	texture: Texture2D,
	brightness: float,
	wall_length: float
) -> void:

	var polygon := PackedVector2Array([
		a_floor,
		b_floor,
		b_top,
		a_top
	])

	var bounds := Rect2(polygon[0], Vector2.ZERO)

	for point in polygon:
		bounds = bounds.expand(point)

	var step: float = float(maxi(pixelation_rate, 1))

	var min_x: int = floori(bounds.position.x / step) - 1
	var max_x: int = ceili(bounds.end.x / step) + 1

	var min_y: int = floori(bounds.position.y / step) - 1
	var max_y: int = ceili(bounds.end.y / step) + 1

	for gy in range(min_y, max_y + 1):
		for gx in range(min_x, max_x + 1):

			var pixel_position := Vector2(
				float(gx) * step,
				float(gy) * step
			)

			var sample_point := pixel_position + Vector2(
				step * 0.5,
				step * 0.5
			)

			if not Geometry2D.is_point_in_polygon(
				sample_point,
				polygon
			):
				continue

			var uv := _face_uv(
				sample_point,
				a_floor,
				b_floor,
				a_top
			)

			if uv.x < -0.001 or uv.x > 1.001:
				continue

			if uv.y < -0.001 or uv.y > 1.001:
				continue

			var sampled := _sample_texture(
				texture,
				uv.x,
				uv.y,
				wall_length
			)

			if sampled.a <= 0.001:
				continue

			sampled = _shade(
				sampled,
				brightness
			)

			draw_rect(
				Rect2(
					pixel_position,
					Vector2(step, step)
				),
				sampled,
				true
			)


# -------------------------------------------------------------------
# Screen point -> wall UV
#
# This is the important part of the counter-iso effect.
#
# The wall remains an isometric parallelogram, but a texture sample
# becomes a NORMAL screen-aligned square.
# -------------------------------------------------------------------

func _face_uv(
	point: Vector2,
	a_floor: Vector2,
	b_floor: Vector2,
	a_top: Vector2
) -> Vector2:

	var axis_u: Vector2 = b_floor - a_floor
	var axis_v: Vector2 = a_top - a_floor

	var relative: Vector2 = point - a_floor

	var determinant: float = _cross(
		axis_u,
		axis_v
	)

	if absf(determinant) < 0.00001:
		return Vector2(-1.0, -1.0)

	var u: float = _cross(
		relative,
		axis_v
	) / determinant

	var v: float = _cross(
		axis_u,
		relative
	) / determinant

	return Vector2(u, v)


func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


# -------------------------------------------------------------------
# Texture sampling
# -------------------------------------------------------------------

func _sample_texture(
	texture: Texture2D,
	u: float,
	v: float,
	wall_length: float
) -> Color:

	var image: Image = _get_texture_image(texture)

	if image == null:
		return Color.WHITE

	if image.get_width() <= 0 or image.get_height() <= 0:
		return Color.WHITE

	var tile: float = maxf(
		texture_tile_size,
		1.0
	)

	# Same tiling concept as the original IsoWallRenderer:
	# U = wall length / tile size
	# V = wall height / tile size
	var tiled_u: float = fposmod(
		u * wall_length / tile,
		1.0
	)

	var tiled_v: float = fposmod(
		v * wall_height / tile,
		1.0
	)

	# Nearest-neighbour sampling.
	var sample_x: int = clampi(
		floori(
			tiled_u * float(image.get_width())
		),
		0,
		image.get_width() - 1
	)

	var sample_y: int = clampi(
		floori(
			tiled_v * float(image.get_height())
		),
		0,
		image.get_height() - 1
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
		return _texture_images[key]

	var image: Image = texture.get_image()

	if image == null:
		return null

	_texture_images[key] = image

	return image


# -------------------------------------------------------------------
# Pixel sampled line art
# -------------------------------------------------------------------

func _draw_sampled_line(
	a: Vector2,
	b: Vector2,
	texture: Texture2D,
	brightness: float,
	v: float,
	wall_length: float
) -> void:

	var distance: float = a.distance_to(b)

	if distance < 0.01:
		return

	var step: float = float(maxi(pixelation_rate, 1))
	var blocks: int = maxi(
		ceili(distance / step),
		1
	)

	var line_size: float = step * float(
		maxi(line_width_px, 1)
	)

	for i in range(blocks + 1):
		var t: float = clampf(
			float(i) / float(blocks),
			0.0,
			1.0
		)

		var position: Vector2 = a.lerp(
			b,
			t
		)

		var sampled: Color = _sample_texture(
			texture,
			t,
			v,
			wall_length
		)

		sampled = _line_color(
			sampled,
			brightness
		)

		draw_rect(
			Rect2(
				_position_to_pixel(position)
					- Vector2.ONE * line_size * 0.5,
				Vector2.ONE * line_size
			),
			sampled,
			true
		)


func _draw_sampled_vertical(
	floor_point: Vector2,
	top_point: Vector2,
	texture: Texture2D,
	brightness: float,
	u: float
) -> void:

	var distance: float = floor_point.distance_to(
		top_point
	)

	if distance < 0.01:
		return

	var step: float = float(maxi(pixelation_rate, 1))

	var blocks: int = maxi(
		ceili(distance / step),
		1
	)

	var line_size: float = step * float(
		maxi(line_width_px, 1)
	)

	for i in range(blocks + 1):
		var t: float = clampf(
			float(i) / float(blocks),
			0.0,
			1.0
		)

		var position: Vector2 = floor_point.lerp(
			top_point,
			t
		)

		var sampled := _sample_texture(
			texture,
			u,
			t,
			floor_point.distance_to(top_point)
		)

		sampled = _line_color(
			sampled,
			brightness
		)

		draw_rect(
			Rect2(
				_position_to_pixel(position)
					- Vector2.ONE * line_size * 0.5,
				Vector2.ONE * line_size
			),
			sampled,
			true
		)


func _line_color(
	texture_color: Color,
	brightness: float
) -> Color:

	var darkened: float = 1.0 - line_darkness

	return _shade(
		texture_color,
		brightness * darkened
	)


# -------------------------------------------------------------------
# Pixel line renderer
# -------------------------------------------------------------------

func _draw_pixel_line(
	a: Vector2,
	b: Vector2,
	color: Color
) -> void:

	var distance: float = a.distance_to(b)

	if distance < 0.01:
		return

	var step: float = float(maxi(pixelation_rate, 1))

	var blocks: int = maxi(
		ceili(distance / step),
		1
	)

	var size: float = step * float(
		maxi(line_width_px, 1)
	)

	for i in range(blocks + 1):
		var t: float = clampf(
			float(i) / float(blocks),
			0.0,
			1.0
		)

		var position: Vector2 = a.lerp(
			b,
			t
		)

		position = _position_to_pixel(position)

		draw_rect(
			Rect2(
				position - Vector2.ONE * size * 0.5,
				Vector2.ONE * size
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


# -------------------------------------------------------------------
# Pixel polygon fill
# -------------------------------------------------------------------

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

			var position := Vector2(
				float(gx) * step,
				float(gy) * step
			)

			var sample_point := position + Vector2(
				step * 0.5,
				step * 0.5
			)

			if not Geometry2D.is_point_in_polygon(
				sample_point,
				polygon
			):
				continue

			draw_rect(
				Rect2(
					position,
					Vector2.ONE * step
				),
				color,
				true
			)


# -------------------------------------------------------------------
# Pixelated top path
# -------------------------------------------------------------------

func _draw_pixel_top_path(path: Dictionary) -> void:
	var points: PackedVector2Array = path["points"]

	if points.size() < 2:
		return

	var segment_value: Variant = path.get(
		"segment",
		null
	)

	var segment: WallSegment = segment_value as WallSegment

	for i in range(points.size() - 1):
		var plan_a: Vector2 = points[i]
		var plan_b: Vector2 = points[i + 1]

		var screen_a: Vector2 = _project(
			plan_a,
			wall_height
		)

		var screen_b: Vector2 = _project(
			plan_b,
			wall_height
		)

		if segment == null:
			_draw_pixel_line(
				screen_a,
				screen_b,
				path["color"]
			)
			continue

		var normal: Vector2 = _outward_normal(
			plan_a,
			plan_b
		)

		var face_side: int = 0

		if normal != Vector2.ZERO:
			var perpendicular := (
				segment.end_point
				- segment.start_point
			).normalized().orthogonal()

			if normal.dot(perpendicular) < 0.0:
				face_side = 1

		var texture: Texture2D = null

		if textured_walls:
			texture = segment.get_texture_for_side(
				face_side
			)

		var brightness: float = _face_brightness(
			_rotate(normal)
		)

		if texture != null and counter_iso_textures:
			_draw_sampled_line(
				screen_a,
				screen_b,
				texture,
				brightness,
				1.0,
				plan_a.distance_to(plan_b)
			)
		else:
			_draw_pixel_line(
				screen_a,
				screen_b,
				_shade(
					path["color"],
					brightness
				)
			)


# -------------------------------------------------------------------
# Wireframe
# -------------------------------------------------------------------

func _draw_pixel_wireframe(path: Dictionary) -> void:
	var points: PackedVector2Array = path["points"]
	var color: Color = path["color"]

	if points.size() < 2:
		return

	for i in range(points.size() - 1):
		var a: Vector2 = _project(
			points[i],
			0.0
		)

		var b: Vector2 = _project(
			points[i + 1],
			0.0
		)

		_draw_pixel_line(
			a,
			b,
			color
		)

		a = _project(
			points[i],
			wall_height
		)

		b = _project(
			points[i + 1],
			wall_height
		)

		_draw_pixel_line(
			a,
			b,
			color
		)

	var corners: PackedInt32Array = path.get(
		"corners",
		PackedInt32Array()
	)

	for index in corners:
		var floor_point: Vector2 = _project(
			points[index],
			0.0
		)

		var top_point: Vector2 = _project(
			points[index],
			wall_height
		)

		_draw_pixel_line(
			floor_point,
			top_point,
			color
		)
