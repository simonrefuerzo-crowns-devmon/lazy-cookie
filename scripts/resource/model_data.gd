class_name ModelData
extends Resource

## Composable model-part data used by ObjectModelBuilder and model renderers.
##
## A ModelData can contain other ModelData resources. The root ModelData acts as
## the complete object model, while every child remains an independent part for
## placement, snapping, texture editing, detaching, and rendering.

@export_category("Identity")
@export var model_name: String = "Model Part"
@export_multiline var description: String = ""
@export var base_color: Color = Color.WHITE
@export var use_base_color_fallback: bool = true

@export_category("Flat Footprint")
## Size of this model part on the isometric flat-space plane.
##
## ModelData is independent of the RoomBuilder environment.
## ObjectModelBuilder is responsible for any coordinate or placement conversion.
@export var size_px: Vector2 = Vector2(4.0, 4.0)

## Local flat-space center relative to the parent ModelData.
## The root model normally uses Vector2.ZERO.
@export var local_position: Vector2 = Vector2.ZERO

## Rotation of this part relative to its parent flat-space orientation.
@export_range(-360.0, 360.0, 1.0) var local_rotation_degrees: float = 0.0

## Vertical offset from the parent's base plane. A model snapped onto another
## model's top can use the supporting model's top height as this value.
@export var local_height_offset_px: float = 0.0

@export_category("Body Geometry")
enum BodyType {
	RECTANGULAR,
	CYLINDER,
	PYRAMID,
	CONE,
	HYBRID,
}

@export var body_type: BodyType = BodyType.RECTANGULAR

## Shape of the flat bottom footprint. BodyType controls how that footprint
## continues upward through its height.
enum FlatBottomShape {
	RECTANGLE,
	ELLIPSE,
}

@export var flat_bottom_shape: FlatBottomShape = FlatBottomShape.RECTANGLE

## Whether the flat footprint has explicit corners. Cylinder/ellipse bases do
## not use rectangular corner settings.
@export var has_corners: bool = true

enum CornerStyle {
	SOLID_RECT,
	ROUNDED,
	CURVED,
}

@export var corner_style: CornerStyle = CornerStyle.SOLID_RECT
@export_range(0.0, 4096.0, 1.0) var corner_radius_px: float = 4.0
@export_range(1, 32, 1) var corner_segments: int = 6

## Height of this model part measured upward from its own base plane.
@export_range(0.0, 100000.0, 1.0) var height_px: float = 24.0

@export_category("Render Ordering")
## Manual painter-order priority used by ModelRenderer. Higher values are
## rendered later, placing the model/part visually in front of lower values.
## A value of 0 keeps the normal automatic depth ordering.
@export var render_order: int = 0

## Point on the flat plane where the upper body ends.
##
## For PYRAMID and CONE this is the apex/end point. For HYBRID it describes
## the upper body's endpoint. For RECTANGULAR/CYLINDER it defaults to the
## center unless a future builder chooses to use it for custom profiles.
@export var top_end_point: Vector2 = Vector2.ZERO

## Optional top footprint size for HYBRID/custom upper sections. Zero means the
## upper section collapses to top_end_point for point-ended bodies.
@export var top_end_size_px: Vector2 = Vector2.ZERO

## Number of polygon samples used for ellipse/circular bodies.
@export_range(3, 128, 1) var radial_segments: int = 24

## Number of visible profile sections reserved for HYBRID models.
## A future ObjectModelBuilder can use these as construction stages without
## changing the root ModelData structure.
@export_range(1, 32, 1) var hybrid_section_count: int = 1

@export_category("Top Surface")
## Extra top profile amount used by custom/hybrid construction.
@export_range(0.0, 100000.0, 1.0) var top_profile_height_px: float = 0.0

## For point-ended or hybrid tops, controls how the top endpoint is interpreted.
enum TopEndStyle {
	CENTER_POINT,
	POINT,
	FLAT_END,
}

@export var top_end_style: TopEndStyle = TopEndStyle.CENTER_POINT

@export_category("Model Parts")
## When true, this ModelData is a structural parent only. Its children are
## the visual/physical model parts. ObjectData can reference this parent as the
## complete model while snapping and rendering continue to address children.
@export var is_assembly_parent: bool = false

## Child ModelData parts. Each part keeps its own geometry and remains
## independently addressable after the parent is combined.
@export var parts: Array[ModelData] = []

## Whether this part is allowed to have other model parts attached to its top.
@export var allow_parts_on_top: bool = true

## Whether other model parts may snap against the bottom face of this part.
@export var allow_parts_on_bottom: bool = true

## Whether other model parts may snap against the four side faces of this part.
@export var allow_parts_on_sides: bool = true

## Side/top snapping distance in pixels used by future ObjectModelBuilder tools.
@export_range(0.0, 256.0, 1.0) var snap_distance_px: float = 8.0

@export_category("Textures - Four Sides")
## The wall-style construction system is reused for each visible side.
@export var front_face_textures: ObjectFaceTextureData
@export var back_face_textures: ObjectFaceTextureData
@export var left_face_textures: ObjectFaceTextureData
@export var right_face_textures: ObjectFaceTextureData

@export_category("Textures - Top")
@export var top_face_textures: ObjectFaceTextureData

@export_category("Textures - Bottom")
@export var bottom_face_textures: ObjectFaceTextureData

## Rotation applied to the top texture construction in degrees. The renderer
## can use this to control which direction the top pattern faces.
@export_range(-360.0, 360.0, 1.0) var top_texture_rotation_degrees: float = 0.0

## When true, the renderer may rotate the entire top texture coordinate space
## instead of rotating individual texture resources.
@export var rotate_top_texture_space: bool = true

func _init() -> void:
	_ensure_texture_sets()
	_normalize()


func _ensure_texture_sets() -> void:
	if front_face_textures == null:
		front_face_textures = ObjectFaceTextureData.new()
	front_face_textures.face_target = ObjectFaceTextureData.FaceTarget.FRONT

	if back_face_textures == null:
		back_face_textures = ObjectFaceTextureData.new()
	back_face_textures.face_target = ObjectFaceTextureData.FaceTarget.BACK

	if left_face_textures == null:
		left_face_textures = ObjectFaceTextureData.new()
	left_face_textures.face_target = ObjectFaceTextureData.FaceTarget.LEFT

	if right_face_textures == null:
		right_face_textures = ObjectFaceTextureData.new()
	right_face_textures.face_target = ObjectFaceTextureData.FaceTarget.RIGHT

	if top_face_textures == null:
		top_face_textures = ObjectFaceTextureData.new()
	top_face_textures.face_target = ObjectFaceTextureData.FaceTarget.TOP

	if bottom_face_textures == null:
		bottom_face_textures = ObjectFaceTextureData.new()
	bottom_face_textures.face_target = ObjectFaceTextureData.FaceTarget.BOTTOM
	bottom_face_textures.texture_enabled = false

	front_face_textures.texture_enabled = true
	back_face_textures.texture_enabled = true
	left_face_textures.texture_enabled = true
	right_face_textures.texture_enabled = true
	top_face_textures.texture_enabled = true


func _normalize() -> void:
	size_px = Vector2(maxf(size_px.x, 1.0), maxf(size_px.y, 1.0))
	height_px = maxf(height_px, 0.0)
	local_height_offset_px = maxf(local_height_offset_px, 0.0)
	top_end_size_px = Vector2(maxf(top_end_size_px.x, 0.0), maxf(top_end_size_px.y, 0.0))
	corner_radius_px = maxf(corner_radius_px, 0.0)
	corner_segments = clampi(corner_segments, 1, 32)
	radial_segments = clampi(radial_segments, 3, 128)
	hybrid_section_count = clampi(hybrid_section_count, 1, 32)
	top_profile_height_px = maxf(top_profile_height_px, 0.0)
	snap_distance_px = maxf(snap_distance_px, 0.0)


func get_size_px() -> Vector2:
	return size_px


func get_render_height_px() -> float:
	return height_px + local_height_offset_px


func get_top_height_px() -> float:
	return get_render_height_px() + top_profile_height_px


func get_face_texture_set(face: int) -> ObjectFaceTextureData:
	match face:
		ObjectFaceTextureData.FaceTarget.FRONT:
			return front_face_textures
		ObjectFaceTextureData.FaceTarget.BACK:
			return back_face_textures
		ObjectFaceTextureData.FaceTarget.LEFT:
			return left_face_textures
		ObjectFaceTextureData.FaceTarget.RIGHT:
			return right_face_textures
		ObjectFaceTextureData.FaceTarget.TOP:
			return top_face_textures
		ObjectFaceTextureData.FaceTarget.BOTTOM:
			return bottom_face_textures
	return null


func get_or_create_face_texture_set(face: int) -> ObjectFaceTextureData:
	_ensure_texture_sets()
	return get_face_texture_set(face)


func set_face_texture_set(face: int, texture_set: ObjectFaceTextureData) -> void:
	if texture_set == null:
		return

	match face:
		ObjectFaceTextureData.FaceTarget.FRONT:
			front_face_textures = texture_set
		ObjectFaceTextureData.FaceTarget.BACK:
			back_face_textures = texture_set
		ObjectFaceTextureData.FaceTarget.LEFT:
			left_face_textures = texture_set
		ObjectFaceTextureData.FaceTarget.RIGHT:
			right_face_textures = texture_set
		ObjectFaceTextureData.FaceTarget.TOP:
			top_face_textures = texture_set
		ObjectFaceTextureData.FaceTarget.BOTTOM:
			bottom_face_textures = texture_set

	emit_changed()


func set_top_texture_rotation_degrees(value: float) -> void:
	top_texture_rotation_degrees = value
	emit_changed()


func add_part(part: ModelData) -> bool:
	if part == null or part == self:
		return false
	if parts.has(part):
		return false
	parts.append(part)
	emit_changed()
	return true


func remove_part(part: ModelData) -> bool:
	if part == null:
		return false
	var index := parts.find(part)
	if index < 0:
		return false
	parts.remove_at(index)
	emit_changed()
	return true


func has_part(part: ModelData) -> bool:
	return part != null and parts.has(part)


func get_part_count() -> int:
	return parts.size()


func get_all_parts_recursive(include_self: bool = false) -> Array[ModelData]:
	var result: Array[ModelData] = []
	if include_self:
		result.append(self)
	_collect_parts_recursive(self, result)
	return result


func _collect_parts_recursive(parent: ModelData, result: Array[ModelData]) -> void:
	for part in parent.parts:
		if part == null or result.has(part):
			continue
		result.append(part)
		_collect_parts_recursive(part, result)


func get_flat_footprint_polygon() -> PackedVector2Array:
	var footprint_size := get_size_px()
	var half := footprint_size * 0.5

	if flat_bottom_shape == FlatBottomShape.ELLIPSE:
		return _build_ellipse_polygon(half)

	if not has_corners or corner_style == CornerStyle.SOLID_RECT or corner_radius_px <= 0.0:
		return PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])

	return _build_rounded_rectangle_polygon(half)


func _build_ellipse_polygon(half: Vector2) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for index in range(radial_segments):
		var angle := TAU * float(index) / float(radial_segments)
		polygon.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))
	return polygon


func _build_rounded_rectangle_polygon(half: Vector2) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var radius_x := minf(corner_radius_px, half.x)
	var radius_y := minf(corner_radius_px, half.y)
	var radius := minf(radius_x, radius_y)
	var segments := corner_segments

	var centers := [
		Vector2(half.x - radius, -half.y + radius),
		Vector2(half.x - radius, half.y - radius),
		Vector2(-half.x + radius, half.y - radius),
		Vector2(-half.x + radius, -half.y + radius),
	]
	var start_angles := [
		-deg_to_rad(90.0),
		0.0,
		deg_to_rad(90.0),
		PI,
	]

	for corner_index in range(4):
		var center: Vector2 = centers[corner_index]
		var start_angle: float = start_angles[corner_index]
		for segment_index in range(segments + 1):
			var t := float(segment_index) / float(segments)
			var angle := start_angle + deg_to_rad(90.0) * t
			polygon.append(center + Vector2(cos(angle), sin(angle)) * radius)

	return polygon


func get_local_bounds() -> Rect2:
	var polygon := get_flat_footprint_polygon()
	if polygon.is_empty():
		return Rect2(local_position, Vector2.ZERO)

	var min_point := polygon[0]
	var max_point := polygon[0]
	for point in polygon:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	return Rect2(min_point + local_position, max_point - min_point)


func get_top_end_point() -> Vector2:
	return top_end_point + local_position


func get_snap_radius_px() -> float:
	return snap_distance_px


func can_accept_top_part() -> bool:
	return allow_parts_on_top


func can_accept_bottom_part() -> bool:
	return allow_parts_on_bottom


func can_accept_side_part() -> bool:
	return allow_parts_on_sides


func is_composite() -> bool:
	return not parts.is_empty()


func is_point_ended_body() -> bool:
	return body_type == BodyType.PYRAMID or body_type == BodyType.CONE or top_end_style == TopEndStyle.POINT


func set_size_px(value: Vector2) -> void:
	size_px = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
	emit_changed()


func set_height_px(value: float) -> void:
	height_px = maxf(value, 0.0)
	emit_changed()


func set_render_order(value: int) -> void:
	render_order = value
	emit_changed()


func set_local_position(value: Vector2) -> void:
	local_position = value
	emit_changed()


func set_local_height_offset_px(value: float) -> void:
	local_height_offset_px = maxf(value, 0.0)
	emit_changed()


func set_local_rotation_degrees(value: float) -> void:
	local_rotation_degrees = value
	emit_changed()
