class_name ObjectData
extends Resource

## Day-to-day room object data shared by ObjectBuilder, ObjectRenderer and
## IsoObjectRenderer. Top-level resources live in RoomData.objects.
##
## A custom object_model, when assigned, is the primary model representation
## for the object. Existing Object Shape / Iso Top / texture data remain as
## the fallback representation when no custom model is assigned.

@export_category("Identity")
@export var object_name: String = "Object"
@export_multiline var description: String = ""
@export var base_color: Color = Color.WHITE

@export_category("Room Placement")
## World-space center of the object's footprint.
@export var position: Vector2 = Vector2.ZERO
## Physical footprint occupied by the object, in room/world pixels.
@export var size_px: Vector2i = Vector2i(32, 32)
@export_range(-360.0, 360.0, 1.0) var rotation_degrees: float = 0.0

@export_category("Physical")
@export var hp: float = 100.0
## Mass used for carrying and push/pull resistance.
@export_range(0.0, 100000.0, 0.1) var carried_weight: float = 1.0

@export_category("Carry")
@export var can_be_carried: bool = false
@export_range(1, 2, 1) var required_hands: int = 1
@export var can_be_thrown: bool = false
@export_range(0.0, 100000.0, 0.1) var throw_force: float = 100.0
@export_range(0.0, 100.0, 0.05) var throw_damage_multiplier: float = 1.0
@export var can_break_on_throw_impact: bool = true

@export_category("Breaking")
@export var is_breakable: bool = false

enum BreakType {
	SHATTER,
	SPLINTER,
	CRUSH,
	CHIP,
}

@export var break_type: BreakType = BreakType.SHATTER

@export_category("Containment")
@export var can_contain_objects: bool = false
@export var contained_objects: Array[ObjectData] = []

@export_category("Interaction")
@export var interaction_scripts: Array[Script] = []
@export var interaction_script_properties: Dictionary = {}

@export_category("Custom Model")
## Primary visual/model representation of this object.
##
## When assigned, this ModelData completely overrides the legacy Object Shape,
## Iso Top and construction-texture body for rendering. The legacy fields are
## retained as fallback/compatibility data but are not rendered while a custom
## model is assigned.
@export var object_model: ModelData = null

## Optional source asset path used when the model was inserted from the model
## asset browser. Empty means the object model was created directly or embedded.
@export var object_model_source_path: String = ""

## Returns true when a custom model is assigned and should replace the legacy
## ObjectData body in all renderers.
func has_custom_model() -> bool:
	return object_model != null

## Assign the primary custom model and synchronize the ObjectData footprint and
## nominal height so collision/placement and legacy metadata still describe
## the model correctly. The model itself remains the authoritative visual body.
func set_object_model(model: ModelData, source_path: String = "") -> void:
	object_model = model
	object_model_source_path = source_path
	if object_model != null:
		_sync_geometry_from_custom_model(object_model)
	emit_changed()

## Remove the custom model and return rendering responsibility to the legacy
## ObjectData body fields.
func clear_object_model() -> void:
	object_model = null
	object_model_source_path = ""
	emit_changed()

## Returns the complete flat-space bounds occupied by the custom model tree,
## relative to the ObjectData origin.
func get_custom_model_bounds() -> Rect2:
	if object_model == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	_collect_custom_model_bounds(
		object_model,
		Vector2.ZERO,
		0.0,
		min_point,
		max_point)

	if not is_finite(min_point.x) or not is_finite(min_point.y) \
		or not is_finite(max_point.x) or not is_finite(max_point.y):
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	return Rect2(min_point, max_point - min_point)

## Returns the complete aggregate footprint size of the custom model tree.
func get_custom_model_size_px() -> Vector2i:
	var bounds: Rect2 = get_custom_model_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		if object_model != null:
			return Vector2i(
				maxi(int(ceil(object_model.size_px.x)), 1),
				maxi(int(ceil(object_model.size_px.y)), 1))
		return Vector2i(1, 1)
	return Vector2i(
		maxi(int(ceil(bounds.size.x)), 1),
		maxi(int(ceil(bounds.size.y)), 1))

## Returns the highest visible vertical point in the complete custom model tree.
func get_custom_model_height_px() -> float:
	if object_model == null:
		return maxf(height_px + height_modifier_px, 0.0)
	return _get_custom_model_height_recursive(object_model, 0.0)

func _sync_geometry_from_custom_model(model: ModelData) -> void:
	if model == null:
		return

	size_px = model.get_size_px() if model.parts.is_empty() else get_custom_model_size_px()
	size_px = Vector2i(maxi(size_px.x, 1), maxi(size_px.y, 1))
	height_px = maxf(get_custom_model_height_px(), 0.0)

	var leaves: Array[ModelData] = model.get_all_parts_recursive(false)
	var single_visual_part: ModelData = null
	if leaves.is_empty() and not model.is_assembly_parent:
		single_visual_part = model
	elif model.is_assembly_parent and leaves.size() == 1 and leaves[0] != null:
		single_visual_part = leaves[0]

	if single_visual_part != null:
		var part: ModelData = single_visual_part
		if part.flat_bottom_shape == ModelData.FlatBottomShape.ELLIPSE or part.body_type == ModelData.BodyType.CYLINDER or part.body_type == ModelData.BodyType.CONE:
			body_shape = BodyShape.CYLINDER
		elif part.has_corners and part.corner_style != ModelData.CornerStyle.SOLID_RECT:
			body_shape = BodyShape.ROUNDED_CORNERS
		else:
			body_shape = BodyShape.RECTANGULAR
		has_corners = part.has_corners
		curved_corners = part.corner_style == ModelData.CornerStyle.CURVED
		corner_radius_px = maxf(part.corner_radius_px, 0.0)
	else:
		body_shape = BodyShape.RECTANGULAR
		has_corners = false
		curved_corners = false
		corner_radius_px = 0.0

func _collect_custom_model_bounds(
	part: ModelData,
	parent_position: Vector2,
	parent_rotation_degrees: float,
	min_point: Vector2,
	max_point: Vector2) -> void:
	if part == null:
		return

	var world_rotation: float = parent_rotation_degrees + part.local_rotation_degrees
	var world_position: Vector2 = parent_position + part.local_position.rotated(deg_to_rad(parent_rotation_degrees))
	var radians: float = deg_to_rad(world_rotation)

	if not part.is_assembly_parent:
		for point in part.get_flat_footprint_polygon():
			var world_point: Vector2 = world_position + point.rotated(radians)
			min_point.x = minf(min_point.x, world_point.x)
			min_point.y = minf(min_point.y, world_point.y)
			max_point.x = maxf(max_point.x, world_point.x)
			max_point.y = maxf(max_point.y, world_point.y)

	for child in part.parts:
		if child != null:
			_collect_custom_model_bounds(child, world_position, world_rotation, min_point, max_point)

func _get_custom_model_height_recursive(part: ModelData, parent_base_height: float) -> float:
	if part == null:
		return parent_base_height

	var base_height: float = parent_base_height + maxf(part.local_height_offset_px, 0.0)
	var highest: float = base_height + maxf(part.height_px, 0.0) + maxf(part.top_profile_height_px, 0.0)

	for child in part.parts:
		if child == null:
			continue
		highest = maxf(highest, _get_custom_model_height_recursive(child, base_height))

	return highest

@export_category("Object Shape")
enum BodyShape {
	RECTANGULAR,
	ROUNDED_CORNERS,
	CYLINDER,
}

## Top-down footprint shape. ROUNDED_CORNERS uses corner_radius_px while
## CYLINDER treats the footprint as an ellipse/cylinder base.
@export var body_shape: BodyShape = BodyShape.RECTANGULAR

## Whether the object uses explicit corner geometry. Kept separate from the
## shape enum so builders/scripts can describe objects without forcing a shape.
@export var has_corners: bool = true

## When true, rectangular corners are curved using corner_radius_px.
@export var curved_corners: bool = false
@export_range(0.0, 4096.0, 1.0) var corner_radius_px: float = 4.0

## Vertical base height used by IsoObjectRenderer.
@export_range(0.0, 100000.0, 1.0) var height_px: float = 32.0

## Additive runtime/editor modifier applied to the ISO render height.
@export_range(-100000.0, 100000.0, 1.0) var height_modifier_px: float = 0.0

@export_category("Iso Top")
enum TopRenderStyle {
	FLAT,
	CURVE_OUTWARD,
	CURVE_INWARD,
	OPEN,
	POINT_OUTWARD,
	POINT_INWARD,
}

## Controls the top surface profile in the isometric renderer.
@export var top_render_style: TopRenderStyle = TopRenderStyle.FLAT

## Height of the top profile above/below the object's nominal height.
@export_range(0.0, 100000.0, 1.0) var top_profile_height_px: float = 8.0

## Number of radial segments used to approximate curved/rounded tops.
@export_range(3, 32, 1) var top_profile_segments: int = 8

## Depth of the visible inner cavity for OPEN tops.
@export_range(0.0, 100000.0, 1.0) var opening_depth_px: float = 8.0

@export_category("Textures - Construction")
## Textures are optional. A middle texture may stand alone; corners and edges
## may be mixed and omitted.
@export var corner_top_left: Texture2D
@export var corner_top_right: Texture2D
@export var corner_bottom_left: Texture2D
@export var corner_bottom_right: Texture2D

## Legacy/common corner size. Kept for compatibility with existing builder data.
@export var corner_size_px: Vector2i = Vector2i(8, 8)

@export_category("Textures - Tileable Edges")
@export var edge_top: Texture2D
@export var edge_bottom: Texture2D
@export var edge_left: Texture2D
@export var edge_right: Texture2D

@export_category("Textures - Middle")
## Repeated independently along both X and Y to fill an area.
@export var middle_texture: Texture2D
@export var middle_tile_size_px: Vector2 = Vector2(16.0, 16.0)

@export_category("Textures - Size Overrides")
@export var use_uniform_texture_size: bool = true
@export var uniform_texture_size_px: Vector2 = Vector2(16.0, 16.0)
@export var texture_size_overrides: Dictionary = {}

@export_category("Textures - Face Targets")
## Each logical face owns its own corner, edge and middle texture set.
## Side faces and the top are texture-enabled by default; the bottom is disabled.
@export var front_face_textures: ObjectFaceTextureData
@export var back_face_textures: ObjectFaceTextureData
@export var left_face_textures: ObjectFaceTextureData
@export var right_face_textures: ObjectFaceTextureData
@export var top_face_textures: ObjectFaceTextureData
@export var bottom_face_textures: ObjectFaceTextureData
@export var render_bottom_face: bool = false

func _init() -> void:
	_ensure_face_texture_sets()
	_normalize()

func _ensure_face_texture_sets() -> void:
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

func _normalize() -> void:
	required_hands = clampi(required_hands, 1, 2)
	size_px = Vector2i(maxi(size_px.x, 1), maxi(size_px.y, 1))
	corner_size_px = Vector2i(maxi(corner_size_px.x, 1), maxi(corner_size_px.y, 1))
	hp = maxf(hp, 0.0)
	carried_weight = maxf(carried_weight, 0.0)
	throw_force = maxf(throw_force, 0.0)
	throw_damage_multiplier = maxf(throw_damage_multiplier, 0.0)
	middle_tile_size_px = Vector2(
		maxf(middle_tile_size_px.x, 1.0),
		maxf(middle_tile_size_px.y, 1.0)
	)
	uniform_texture_size_px = Vector2(
		maxf(uniform_texture_size_px.x, 1.0),
		maxf(uniform_texture_size_px.y, 1.0)
	)
	corner_radius_px = maxf(corner_radius_px, 0.0)
	height_px = maxf(height_px, 0.0)
	top_profile_height_px = maxf(top_profile_height_px, 0.0)
	top_profile_segments = clampi(top_profile_segments, 3, 32)
	opening_depth_px = maxf(opening_depth_px, 0.0)

func get_texture_size(slot: String) -> Vector2:
	if use_uniform_texture_size:
		return uniform_texture_size_px
	var value: Variant = texture_size_overrides.get(slot, uniform_texture_size_px)
	if value is Vector2:
		var size: Vector2 = value
		return Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	return uniform_texture_size_px

func get_render_height_px() -> float:
	return maxf(height_px + height_modifier_px, 0.0)

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
	_ensure_face_texture_sets()
	var set: ObjectFaceTextureData = get_face_texture_set(face)
	if set == null:
		return null
	return set

func set_height_px(value: float) -> void:
	height_px = maxf(value, 0.0)
	emit_changed()

func set_height_modifier_px(value: float) -> void:
	height_modifier_px = value
	emit_changed()

func set_shape(
	shape: BodyShape,
	corners: bool = true,
	curved: bool = false,
	radius: float = 4.0) -> void:
	body_shape = shape
	has_corners = corners
	curved_corners = curved
	corner_radius_px = maxf(radius, 0.0)
	emit_changed()

func set_texture_size(slot: String, size: Vector2) -> void:
	var safe: Vector2 = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	texture_size_overrides[slot] = safe
	if slot == "middle":
		middle_tile_size_px = safe
	elif slot.begins_with("corner_"):
		corner_size_px = Vector2i(maxi(roundi(safe.x), 1), maxi(roundi(safe.y), 1))
	else:
		corner_size_px = Vector2i(maxi(roundi(safe.x), 1), maxi(roundi(safe.y), 1))
	emit_changed()

func set_size_px(value: Vector2i) -> void:
	size_px = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
	emit_changed()

func get_size_px() -> Vector2i:
	return size_px

func set_hp(value: float) -> void:
	hp = maxf(value, 0.0)
	emit_changed()

func apply_damage(amount: float) -> bool:
	if amount <= 0.0:
		return is_destroyed()
	hp = maxf(hp - amount, 0.0)
	emit_changed()
	return is_destroyed()

func is_destroyed() -> bool:
	return hp <= 0.0

func is_carryable() -> bool:
	return can_be_carried and required_hands >= 1 and required_hands <= 2

func is_throwable() -> bool:
	return is_carryable() and can_be_thrown

func can_store_objects() -> bool:
	return can_contain_objects

func add_contained_object(object: ObjectData) -> bool:
	if object == null or not can_contain_objects:
		return false
	contained_objects.append(object)
	emit_changed()
	return true

func remove_contained_object(object: ObjectData) -> void:
	contained_objects.erase(object)
	emit_changed()
