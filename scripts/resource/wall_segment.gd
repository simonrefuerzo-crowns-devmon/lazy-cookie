# wall_segment.gd
class_name WallSegment
extends Resource

enum CapStyle {
	FLAT,
	CURVE_OUTWARD,
	CURVE_INWARD,
	POINT_CONVEX,
	POINT_CONCAVE,
}

## Centerline of the wall.
@export var start_point := Vector2.ZERO
@export var end_point := Vector2.ZERO

## Wall thickness = the gap between the two parallel lines.
@export var thickness := 24.0
## Stroke width of each of the two parallel lines.
@export var line_width := 3.0
@export var color := Color.WHITE

@export var start_cap_style: CapStyle = CapStyle.FLAT
@export var end_cap_style: CapStyle = CapStyle.FLAT

## Isometric wall-face textures. The two faces correspond to the two
## sides of the wall thickness. Room data remains in flat plan coordinates.
@export_category("Wall Textures")
@export var outside_texture: Texture2D = null
@export var inside_texture: Texture2D = null

## Filler colors used where a texture is not available, and for the top
## surface between the two parallel wall lines. The builder can sample these
## automatically from the selected texture.
@export var outside_filler_color: Color = Color.WHITE
@export var inside_filler_color: Color = Color.WHITE


func _init(
		p_start: Vector2 = Vector2.ZERO,
		p_end: Vector2 = Vector2.ZERO,
		p_color: Color = Color.WHITE,
		p_thickness: float = 24.0,
		p_line_width: float = 3.0,
		p_start_cap: CapStyle = CapStyle.FLAT,
		p_end_cap: CapStyle = CapStyle.FLAT) -> void:
	start_point = p_start
	end_point = p_end
	color = p_color
	thickness = p_thickness
	line_width = p_line_width
	start_cap_style = p_start_cap
	end_cap_style = p_end_cap
	outside_filler_color = color
	inside_filler_color = color


func get_length() -> float:
	return start_point.distance_to(end_point)


## end: 0 = start, 1 = end.
func get_point(end: int) -> Vector2:
	return start_point if end == 0 else end_point


func set_point(end: int, point: Vector2) -> void:
	if end == 0:
		start_point = point
	else:
		end_point = point


func get_cap(end: int) -> CapStyle:
	return start_cap_style if end == 0 else end_cap_style


func set_cap(end: int, style: CapStyle) -> void:
	if end == 0:
		start_cap_style = style
	else:
		end_cap_style = style


## Unit vector pointing from the given end INTO the wall.
func get_direction_from(end: int) -> Vector2:
	var direction := end_point - start_point
	if direction.length_squared() < 0.0001:
		return Vector2.RIGHT
	direction = direction.normalized()
	return direction if end == 0 else -direction


## Distance from a point to the wall's centerline.
func get_distance_to(point: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(point, start_point, end_point).distance_to(point)


func get_texture_for_side(side: int) -> Texture2D:
	return outside_texture if side == 0 else inside_texture


func get_filler_for_side(side: int) -> Color:
	if side == 0:
		return outside_filler_color if outside_texture != null else color
	return inside_filler_color if inside_texture != null else color


func set_texture_for_side(side: int, texture: Texture2D) -> void:
	if side == 0:
		outside_texture = texture
	else:
		inside_texture = texture


func set_filler_for_side(side: int, filler: Color) -> void:
	if side == 0:
		outside_filler_color = filler
	else:
		inside_filler_color = filler


func get_top_filler_color() -> Color:
	if outside_texture != null and inside_texture != null:
		return outside_filler_color.lerp(inside_filler_color, 0.5)
	if outside_texture != null:
		return outside_filler_color
	if inside_texture != null:
		return inside_filler_color
	return color
