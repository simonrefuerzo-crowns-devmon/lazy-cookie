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

var _texture_images: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _draw() -> void:
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

	_texture_images[key] = image
	return image
