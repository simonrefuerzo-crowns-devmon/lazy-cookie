class_name ModelTextureLoadout
extends RefCounted

## Texture loadout API for ModelData.
##
## Follows the same loading rules used by the wall texture UI:
## - one configured directory
## - direct files only (no recursive traversal)
## - png, jpg, jpeg, webp, svg
## - sorted path list
## - an explicit empty/None entry
##
## Models expose five selectable loadout faces:
## FRONT, BACK, LEFT, RIGHT, TOP.

signal changed(part: ModelData, face: int)

enum Face {
	FRONT,
	BACK,
	LEFT,
	RIGHT,
	TOP,
}

const NONE_PATH: String = ""
const NONE_LABEL: String = "None / Filler Only"
const SUPPORTED_EXTENSIONS: Array[String] = [
	"png",
	"jpg",
	"jpeg",
	"webp",
	"svg",
]
const LOADOUT_FACES: Array[int] = [
	Face.FRONT,
	Face.BACK,
	Face.LEFT,
	Face.RIGHT,
	Face.TOP,
]

var directory: String = "res://assets/textures/all_texture/"


func _init(initial_directory: String = "res://assets/textures/all_texture/") -> void:
	set_directory(initial_directory)


func set_directory(path: String) -> void:
	directory = path.strip_edges()


func get_texture_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return paths

	for file_name in dir.get_files():
		var extension := file_name.get_extension().to_lower()
		if extension not in SUPPORTED_EXTENSIONS:
			continue
		var full_path := directory.path_join(file_name)
		var texture: Texture2D = load(full_path) as Texture2D
		if texture != null:
			paths.append(full_path)

	paths.sort()
	return paths


func load_texture(path: String) -> Texture2D:
	var clean_path := path.strip_edges()
	if clean_path.is_empty():
		return null
	return load(clean_path) as Texture2D


func get_texture(part: ModelData, face: int) -> Texture2D:
	var face_data := _get_face_data(part, face)
	if face_data == null:
		return null
	return face_data.get_texture("middle")


func get_texture_path(part: ModelData, face: int) -> String:
	var texture := get_texture(part, face)
	if texture == null:
		return NONE_PATH
	return texture.resource_path


func set_texture(part: ModelData, face: int, texture: Texture2D) -> bool:
	var face_data := _get_face_data(part, face, true)
	if face_data == null:
		return false
	face_data.set_texture("middle", texture)
	part.emit_changed()
	changed.emit(part, face)
	return true


func set_texture_path(part: ModelData, face: int, path: String) -> bool:
	return set_texture(part, face, load_texture(path))


func capture(part: ModelData) -> Dictionary:
	var snapshot: Dictionary = {}
	if part == null:
		return snapshot
	for face in LOADOUT_FACES:
		snapshot[face] = get_texture_path(part, face)
	return snapshot


func apply(part: ModelData, loadout: Dictionary) -> bool:
	if part == null:
		return false

	var changed_any := false
	for face in LOADOUT_FACES:
		if not loadout.has(face):
			continue
		var value: Variant = loadout.get(face, NONE_PATH)
		var path := String(value)
		var texture := load_texture(path)
		var current_path := get_texture_path(part, face)
		if current_path == path:
			continue
		if set_texture(part, face, texture):
			changed_any = true

	if changed_any:
		part.emit_changed()
	return changed_any


func get_face_label(face: int) -> String:
	match face:
		Face.FRONT:
			return "Front"
		Face.BACK:
			return "Back"
		Face.LEFT:
			return "Left"
		Face.RIGHT:
			return "Right"
		Face.TOP:
			return "Top"
	return "Unknown"


func _get_model_face_target(face: int) -> int:
	match face:
		Face.FRONT:
			return ObjectFaceTextureData.FaceTarget.FRONT
		Face.BACK:
			return ObjectFaceTextureData.FaceTarget.BACK
		Face.LEFT:
			return ObjectFaceTextureData.FaceTarget.LEFT
		Face.RIGHT:
			return ObjectFaceTextureData.FaceTarget.RIGHT
		Face.TOP:
			return ObjectFaceTextureData.FaceTarget.TOP
	return -1


func _get_face_data(
	part: ModelData,
	face: int,
	create_if_missing: bool = false) -> ObjectFaceTextureData:
	if part == null:
		return null
	var target := _get_model_face_target(face)
	if target < 0:
		return null
	if create_if_missing:
		return part.get_or_create_face_texture_set(target)
	return part.get_face_texture_set(target)
