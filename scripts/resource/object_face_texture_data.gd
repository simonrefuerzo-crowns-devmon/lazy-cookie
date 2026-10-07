# object_face_texture_data.gd
class_name ObjectFaceTextureData
extends Resource

## Complete texture construction set for one logical object face.
## Each face owns independent corners, edges, middle texture and sizing.

enum FaceTarget {
	FRONT,
	BACK,
	LEFT,
	RIGHT,
	TOP,
	BOTTOM,
}

@export var face_target: FaceTarget = FaceTarget.FRONT
## Enables texture rendering for this face. Geometry remains rendered even when false.
@export var texture_enabled: bool = true

@export_category("Corners")
@export var corner_top_left: Texture2D
@export var corner_top_right: Texture2D
@export var corner_bottom_left: Texture2D
@export var corner_bottom_right: Texture2D

@export_category("Edges")
@export var edge_top: Texture2D
@export var edge_bottom: Texture2D
@export var edge_left: Texture2D
@export var edge_right: Texture2D

@export_category("Middle")
@export var middle_texture: Texture2D

@export_category("Sizing")
@export var use_uniform_texture_size: bool = true
@export var uniform_texture_size_px: Vector2 = Vector2(16.0, 16.0)
## Keys: corner_top_left, corner_top_right, corner_bottom_left,
## corner_bottom_right, edge_top, edge_bottom, edge_left, edge_right, middle.
@export var texture_size_overrides: Dictionary = {}


func _init() -> void:
	_normalize()


func _normalize() -> void:
	uniform_texture_size_px = Vector2(
		maxf(uniform_texture_size_px.x, 1.0),
		maxf(uniform_texture_size_px.y, 1.0)
	)
	var normalized_target := clampi(
		int(face_target),
		FaceTarget.FRONT,
		FaceTarget.BOTTOM
	)
	match normalized_target:
		FaceTarget.FRONT:
			face_target = FaceTarget.FRONT
		FaceTarget.BACK:
			face_target = FaceTarget.BACK
		FaceTarget.LEFT:
			face_target = FaceTarget.LEFT
		FaceTarget.RIGHT:
			face_target = FaceTarget.RIGHT
		FaceTarget.TOP:
			face_target = FaceTarget.TOP
		FaceTarget.BOTTOM:
			face_target = FaceTarget.BOTTOM


func get_texture_size(slot: String) -> Vector2:
	if use_uniform_texture_size:
		return uniform_texture_size_px
	var value: Variant = texture_size_overrides.get(slot, uniform_texture_size_px)
	if value is Vector2:
		var size := value as Vector2
		return Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	return uniform_texture_size_px


func set_texture_size(slot: String, size: Vector2) -> void:
	texture_size_overrides[slot] = Vector2(
		maxf(size.x, 1.0),
		maxf(size.y, 1.0)
	)
	if use_uniform_texture_size:
		uniform_texture_size_px = texture_size_overrides[slot]
	emit_changed()


func has_any_texture() -> bool:
	return (
		corner_top_left != null or
		corner_top_right != null or
		corner_bottom_left != null or
		corner_bottom_right != null or
		edge_top != null or
		edge_bottom != null or
		edge_left != null or
		edge_right != null or
		middle_texture != null
	)


func get_texture(slot: String) -> Texture2D:
	match slot:
		"corner_top_left": return corner_top_left
		"corner_top_right": return corner_top_right
		"corner_bottom_left": return corner_bottom_left
		"corner_bottom_right": return corner_bottom_right
		"edge_top": return edge_top
		"edge_bottom": return edge_bottom
		"edge_left": return edge_left
		"edge_right": return edge_right
		"middle": return middle_texture
	return null


func set_texture(slot: String, texture: Texture2D) -> void:
	match slot:
		"corner_top_left": corner_top_left = texture
		"corner_top_right": corner_top_right = texture
		"corner_bottom_left": corner_bottom_left = texture
		"corner_bottom_right": corner_bottom_right = texture
		"edge_top": edge_top = texture
		"edge_bottom": edge_bottom = texture
		"edge_left": edge_left = texture
		"edge_right": edge_right = texture
		"middle": middle_texture = texture
	emit_changed()
