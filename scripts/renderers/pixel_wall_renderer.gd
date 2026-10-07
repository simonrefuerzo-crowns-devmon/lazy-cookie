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


@export_category("Baking")

## Rasterize the pixel look once into a texture and draw that texture, instead
## of re-running every cell on every redraw. It only re-bakes when the visible
## solid geometry, a pixel setting or the projection actually changes.
@export var bake_enabled: bool = true:
	set(value):
		if bake_enabled == value:
			return
		bake_enabled = value
		_bake_signature = 0
		queue_redraw()

## While the view is animating (smooth turns), draw the cheap vector render and
## bake once when it settles, instead of re-baking on every frame.
@export var vector_while_turning: bool = true

## How long the projection must stay unchanged before a turn counts as settled.
@export_range(0.02, 1.0, 0.01)
var view_settle_time: float = 0.12


const MAX_BAKE_CELLS := 8192
const BAKE_UV_EPSILON := 0.001

var _bake_texture: ImageTexture
var _bake_origin := Vector2i.ZERO
var _bake_signature := 0
var _bake_ok := true
var _bake_projection_signature := 0
var _bake_last_change_frame := -100
var _bake_last_change_msec := 0
var _bake_view_animating := false
var _bake_settle_pending := false
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

	# Smooth fills need the live path: they can't be baked at cell resolution.
	if not bake_enabled or not pixelate_fills:
		_draw_live()
		return

	_bake_track_projection()

	if _bake_view_animating and vector_while_turning:
		super()
		return

	_draw_baked()


# Original per-cell renderer, unchanged. Used when baking is off.
func _draw_live() -> void:
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

	# get_pixel() fails on VRAM-compressed images.
	if image.is_compressed():
		image.decompress()

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


# -------------------------------------------------------------------
# Baking
#
# Instead of one draw_rect per cell on every redraw, the pixel look is
# rasterized once into an Image on the same cell grid, uploaded as a texture
# and drawn with a single call. It is rebuilt only when the signature changes.
# Ghost previews (translucent paths / footprints) stay live on top, so moving
# the builder cursor never triggers a re-bake.
# -------------------------------------------------------------------

func rebake() -> void:
	_bake_signature = 0
	queue_redraw()


func _draw_baked() -> void:
	var pieces: Array[Dictionary] = _visible_pieces()
	var back_depth: float = _get_back_depth(pieces)
	var items: Dictionary = _bake_collect_items(pieces, back_depth)
	var signature: int = _bake_hash(items)

	if signature != _bake_signature:
		_bake_signature = signature
		_bake_ok = _bake(items)

	if not _bake_ok:
		_draw_live()
		return

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

	for top in items["ghost_tops"]:
		_draw_pixel_polygon(
			_project_all(top["points"], wall_height),
			_shade(top["color"], top_brightness)
		)

	for path in items["alpha_paths"]:
		_draw_pixel_wireframe(path)


func _bake_collect_items(
		pieces: Array[Dictionary],
		back_depth: float) -> Dictionary:
	var face_pieces: Array[Dictionary] = []
	for piece in pieces:
		if _piece_allowed(piece, back_depth):
			face_pieces.append(piece)

	var solid_tops: Array[Dictionary] = []
	var ghost_tops: Array[Dictionary] = []
	for footprint in get_footprints():
		if not _footprint_allowed(footprint, back_depth):
			continue

		var color: Color = footprint["color"]
		var base_alpha: float = color.a
		var segment_value: Variant = footprint.get("segment", null)
		if segment_value is WallSegment:
			color = (segment_value as WallSegment).get_top_filler_color()

		var entry: Dictionary = {
			"points": footprint["points"],
			"color": color,
		}
		if base_alpha < 0.99:
			ghost_tops.append(entry)
		else:
			solid_tops.append(entry)

	var solid_paths: Array[Dictionary] = []
	var alpha_paths: Array[Dictionary] = []
	for path in _paths:
		if not _path_allowed(path, back_depth):
			continue
		var points: PackedVector2Array = path["points"]
		if points.size() < 2:
			continue
		if (path["color"] as Color).a < 0.99:
			alpha_paths.append(path)
		else:
			solid_paths.append(path)

	return {
		"pieces": face_pieces,
		"solid_tops": solid_tops,
		"ghost_tops": ghost_tops,
		"solid_paths": solid_paths,
		"alpha_paths": alpha_paths,
	}


func _bake_hash(items: Dictionary) -> int:
	var parts: Array = [
		pixelation_rate,
		line_width_px,
		line_darkness,
		counter_iso_textures,
		textured_walls,
		texture_tile_size,
		wall_height,
		top_brightness,
		left_brightness,
		right_brightness,
		view_mode,
		_bake_projection_hash(),
	]

	for piece in items["pieces"]:
		var segment := piece.get("segment", null) as WallSegment
		var face_side: int = int(piece.get("face_side", 0))
		var texture_id := 0
		if textured_walls and segment != null:
			var texture := segment.get_texture_for_side(face_side)
			if texture != null:
				texture_id = texture.get_instance_id()
		parts.append([
			piece["a"],
			piece["b"],
			piece["color"],
			piece["view_normal"],
			face_side,
			texture_id,
			piece["vertical_a"],
			piece["vertical_b"],
		])

	for top in items["solid_tops"]:
		parts.append([top["points"], top["color"]])

	for path in items["solid_paths"]:
		parts.append(_bake_path_signature(path))

	return hash(parts)


func _bake_path_signature(path: Dictionary) -> Array:
	var segment := path.get("segment", null) as WallSegment
	if segment == null:
		return [path["points"], path["color"]]

	var texture_ids := [0, 0]
	if textured_walls:
		for side in 2:
			var texture := segment.get_texture_for_side(side)
			if texture != null:
				texture_ids[side] = texture.get_instance_id()

	return [
		path["points"],
		path["color"],
		segment.start_point,
		segment.end_point,
		texture_ids,
	]


# Hashes where a few probe points land on screen, so any change of the
# projection (angle, quadrant, pivot, height, or a smooth turn) is detected no
# matter how it is implemented.
func _bake_projection_hash() -> int:
	return hash([
		wall_height,
		view_mode,
		_project(Vector2.ZERO, 0.0),
		_project(Vector2(128.0, 0.0), 0.0),
		_project(Vector2(0.0, 128.0), 0.0),
		_project(Vector2.ZERO, wall_height),
	])


# -------------------------------------------------------------------
# Smooth-turn detection
#
# One projection change = bake right away (like any edit). Changes on
# consecutive frames = a turn animation: draw the cheap vector render until the
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


# -------------------------------------------------------------------
# Bake
# -------------------------------------------------------------------

func _bake(items: Dictionary) -> bool:
	_bake_texture = null

	var step: float = float(maxi(pixelation_rate, 1))
	var points := PackedVector2Array()

	for piece in items["pieces"]:
		var a: Vector2 = piece["a"]
		var b: Vector2 = piece["b"]
		points.append(_project(a, 0.0))
		points.append(_project(b, 0.0))
		points.append(_project(a, wall_height))
		points.append(_project(b, wall_height))

	for top in items["solid_tops"]:
		points.append_array(_project_all(top["points"], wall_height))

	for path in items["solid_paths"]:
		points.append_array(_project_all(path["points"], wall_height))

	if points.is_empty():
		return true

	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point in points:
		min_point = Vector2(
			minf(min_point.x, point.x),
			minf(min_point.y, point.y)
		)
		max_point = Vector2(
			maxf(max_point.x, point.x),
			maxf(max_point.y, point.y)
		)

	var margin: int = maxi(line_width_px, 1) + 2
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
			"PixelWallRenderer: baked area is too large (%d x %d cells); drawing live instead."
			% [cells.x, cells.y]
		)
		return false

	var canvas: Image = Image.create(
		cells.x,
		cells.y,
		false,
		Image.FORMAT_RGBA8
	)

	# Same painter's order as the live renderer: faces, tops, top lines.
	for piece in items["pieces"]:
		_bake_face(canvas, origin, piece)

	for top in items["solid_tops"]:
		_bake_polygon(
			canvas,
			origin,
			_project_all(top["points"], wall_height),
			_shade(top["color"], top_brightness)
		)

	for path in items["solid_paths"]:
		_bake_top_path(canvas, origin, path)

	_bake_origin = origin
	_bake_texture = ImageTexture.create_from_image(canvas)
	return true


func _bake_face(
		canvas: Image,
		origin: Vector2i,
		piece: Dictionary) -> void:
	var a: Vector2 = piece["a"]
	var b: Vector2 = piece["b"]
	var color: Color = piece["color"]

	var a_floor: Vector2 = _project(a, 0.0)
	var b_floor: Vector2 = _project(b, 0.0)
	var a_top: Vector2 = _project(a, wall_height)
	var b_top: Vector2 = _project(b, wall_height)

	var segment := piece.get("segment", null) as WallSegment
	var face_brightness: float = _face_brightness(piece["view_normal"])
	var face_side: int = int(piece.get("face_side", 0))
	var wall_length: float = a.distance_to(b)

	var texture: Texture2D = null
	if textured_walls and segment != null:
		texture = segment.get_texture_for_side(face_side)

	var sampled: bool = counter_iso_textures and texture != null

	if sampled:
		_bake_counter_iso_face(
			canvas, origin, a_floor, b_floor, a_top,
			texture, face_brightness, wall_length
		)
		_bake_sampled_line(
			canvas, origin, a_floor, b_floor,
			texture, face_brightness, 0.0, wall_length
		)
	else:
		_bake_polygon(
			canvas,
			origin,
			PackedVector2Array([a_floor, b_floor, b_top, a_top]),
			_shade(color, face_brightness)
		)
		_bake_line(
			canvas, origin, a_floor, b_floor,
			_shade(color, face_brightness)
		)

	if piece["vertical_a"]:
		if sampled:
			_bake_sampled_vertical(
				canvas, origin, a_floor, a_top,
				texture, face_brightness, 0.0
			)
		else:
			_bake_line(
				canvas, origin, a_floor, a_top,
				_shade(color, face_brightness)
			)

	if piece["vertical_b"]:
		if sampled:
			_bake_sampled_vertical(
				canvas, origin, b_floor, b_top,
				texture, face_brightness, 1.0
			)
		else:
			_bake_line(
				canvas, origin, b_floor, b_top,
				_shade(color, face_brightness)
			)


# Screen-aligned texture cells on an iso parallelogram. Same math as
# _draw_counter_iso_texture, but with the UV solve inlined and no per-cell
# polygon test or draw call.
func _bake_counter_iso_face(
		canvas: Image,
		origin: Vector2i,
		a_floor: Vector2,
		b_floor: Vector2,
		a_top: Vector2,
		texture: Texture2D,
		brightness: float,
		wall_length: float) -> void:
	var axis_u: Vector2 = b_floor - a_floor
	var axis_v: Vector2 = a_top - a_floor
	var determinant: float = axis_u.x * axis_v.y - axis_u.y * axis_v.x
	if absf(determinant) < 0.00001:
		return
	var inv_det: float = 1.0 / determinant

	var image: Image = _get_texture_image(texture)
	var tex_w := 0
	var tex_h := 0
	if image != null:
		tex_w = image.get_width()
		tex_h = image.get_height()
	var has_image: bool = tex_w > 0 and tex_h > 0

	var tile: float = maxf(texture_tile_size, 1.0)
	var u_scale: float = wall_length / tile
	var v_scale: float = wall_height / tile
	var step: float = float(maxi(pixelation_rate, 1))

	var b_top: Vector2 = b_floor + axis_v
	var min_x: float = minf(minf(a_floor.x, b_floor.x), minf(a_top.x, b_top.x))
	var max_x: float = maxf(maxf(a_floor.x, b_floor.x), maxf(a_top.x, b_top.x))
	var min_y: float = minf(minf(a_floor.y, b_floor.y), minf(a_top.y, b_top.y))
	var max_y: float = maxf(maxf(a_floor.y, b_floor.y), maxf(a_top.y, b_top.y))

	var first_col: int = floori(min_x / step) - 1
	var last_col: int = ceili(max_x / step) + 1
	var first_row: int = floori(min_y / step) - 1
	var last_row: int = ceili(max_y / step) + 1
	var canvas_w: int = canvas.get_width()
	var canvas_h: int = canvas.get_height()

	for gy in range(first_row, last_row + 1):
		var cy: int = gy - origin.y
		if cy < 0 or cy >= canvas_h:
			continue
		var rel_y: float = (float(gy) + 0.5) * step - a_floor.y

		for gx in range(first_col, last_col + 1):
			var cx: int = gx - origin.x
			if cx < 0 or cx >= canvas_w:
				continue
			var rel_x: float = (float(gx) + 0.5) * step - a_floor.x

			var u: float = (rel_x * axis_v.y - rel_y * axis_v.x) * inv_det
			if u < -BAKE_UV_EPSILON or u > 1.0 + BAKE_UV_EPSILON:
				continue
			var v: float = (axis_u.x * rel_y - axis_u.y * rel_x) * inv_det
			if v < -BAKE_UV_EPSILON or v > 1.0 + BAKE_UV_EPSILON:
				continue

			var texel := Color.WHITE
			if has_image:
				var tx: int = clampi(
					floori(fposmod(u * u_scale, 1.0) * float(tex_w)),
					0,
					tex_w - 1
				)
				var ty: int = clampi(
					floori(fposmod(v * v_scale, 1.0) * float(tex_h)),
					0,
					tex_h - 1
				)
				texel = image.get_pixel(tx, ty)

			if texel.a <= 0.001:
				continue

			_bake_blend_pixel(
				canvas,
				cx,
				cy,
				Color(
					texel.r * brightness,
					texel.g * brightness,
					texel.b * brightness,
					texel.a
				)
			)


func _bake_sampled_line(
		canvas: Image,
		origin: Vector2i,
		a: Vector2,
		b: Vector2,
		texture: Texture2D,
		brightness: float,
		v: float,
		wall_length: float) -> void:
	var distance: float = a.distance_to(b)
	if distance < 0.01:
		return

	var step: float = float(maxi(pixelation_rate, 1))
	var blocks: int = maxi(ceili(distance / step), 1)

	for i in range(blocks + 1):
		var t: float = clampf(float(i) / float(blocks), 0.0, 1.0)
		var color: Color = _line_color(
			_sample_texture(texture, t, v, wall_length),
			brightness
		)
		_bake_block(canvas, origin, a.lerp(b, t), color)


func _bake_sampled_vertical(
		canvas: Image,
		origin: Vector2i,
		floor_point: Vector2,
		top_point: Vector2,
		texture: Texture2D,
		brightness: float,
		u: float) -> void:
	var distance: float = floor_point.distance_to(top_point)
	if distance < 0.01:
		return

	var step: float = float(maxi(pixelation_rate, 1))
	var blocks: int = maxi(ceili(distance / step), 1)

	for i in range(blocks + 1):
		var t: float = clampf(float(i) / float(blocks), 0.0, 1.0)
		var color: Color = _line_color(
			_sample_texture(texture, u, t, distance),
			brightness
		)
		_bake_block(canvas, origin, floor_point.lerp(top_point, t), color)


func _bake_top_path(
		canvas: Image,
		origin: Vector2i,
		path: Dictionary) -> void:
	var points: PackedVector2Array = path["points"]
	if points.size() < 2:
		return

	var segment := path.get("segment", null) as WallSegment

	for i in range(points.size() - 1):
		var plan_a: Vector2 = points[i]
		var plan_b: Vector2 = points[i + 1]
		var screen_a: Vector2 = _project(plan_a, wall_height)
		var screen_b: Vector2 = _project(plan_b, wall_height)

		if segment == null:
			_bake_line(canvas, origin, screen_a, screen_b, path["color"])
			continue

		var normal: Vector2 = _outward_normal(plan_a, plan_b)
		var face_side := 0
		if normal != Vector2.ZERO:
			var perpendicular := (
				segment.end_point - segment.start_point
			).normalized().orthogonal()
			if normal.dot(perpendicular) < 0.0:
				face_side = 1

		var texture: Texture2D = null
		if textured_walls:
			texture = segment.get_texture_for_side(face_side)

		var brightness: float = _face_brightness(_rotate(normal))

		if texture != null and counter_iso_textures:
			_bake_sampled_line(
				canvas, origin, screen_a, screen_b,
				texture, brightness, 1.0, plan_a.distance_to(plan_b)
			)
		else:
			_bake_line(
				canvas, origin, screen_a, screen_b,
				_shade(path["color"], brightness)
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


# One line block: line_width_px x line_width_px cells centered on the cell
# under the point. Always grid-aligned, including even widths.
func _bake_block(
		canvas: Image,
		origin: Vector2i,
		screen_point: Vector2,
		color: Color) -> void:
	var step: float = float(maxi(pixelation_rate, 1))
	var width: int = maxi(line_width_px, 1)
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
