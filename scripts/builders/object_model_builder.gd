class_name ObjectModelBuilder
extends RefCounted

## API-only builder for composing ObjectData models from nested ModelData parts.
##
## This builder intentionally has no dependency on the RoomBuilder grid. The
## RoomBuilder/Grid API supplies flat-space coordinates when the caller needs
## grid-aware placement; ModelData itself remains grid-agnostic.
##
## Responsibilities:
## - Create and configure ModelData parts.
## - Add, remove, combine, reparent, and detach parts.
## - Move parts with a non-destructive ghost preview.
## - Calculate top/four-side snap candidates without committing a snap.
## - Commit or cancel a move.
## - Edit per-part textures, top texture rotation, and base-color fallback.
## - Preserve individual ModelData identities after models are combined.

signal model_changed(model: ModelData)
signal selection_changed(part: ModelData)
signal move_started(part: ModelData)
signal move_preview_changed(part: ModelData, preview: Dictionary)
signal move_finished(part: ModelData)
signal move_cancelled(part: ModelData)
signal snap_candidates_changed(part: ModelData, candidates: Array)

## Builder defaults. These are runtime API settings, not editor exports.
var default_snap_distance_px: float = 8.0
var default_model_size_px: Vector2 = Vector2(32.0, 32.0)
var default_model_height_px: float = 32.0

## Snap types returned by get_snap_candidates().
enum SnapType {
	NONE,
	TOP,
	FRONT,
	BACK,
	LEFT,
	RIGHT,
}

var active_model: ModelData = null
var selected_part: ModelData = null

var moving_part: ModelData = null
var moving_parent: ModelData = null
var move_original_world_position: Vector2 = Vector2.ZERO
var move_original_world_rotation_degrees: float = 0.0
var move_original_world_base_height_px: float = 0.0
var move_original_parent: ModelData = null
var move_preview_world_position: Vector2 = Vector2.ZERO
var move_preview_world_rotation_degrees: float = 0.0
var move_preview_world_base_height_px: float = 0.0
var move_preview_snap_type: SnapType = SnapType.NONE
var move_preview_target: ModelData = null
var move_preview_candidates: Array = []


func create_model(model_name: String = "Model") -> ModelData:
	var model: ModelData = ModelData.new()
	model.model_name = model_name
	model.size_px = default_model_size_px
	model.height_px = maxf(default_model_height_px, 0.0)
	model.local_position = Vector2.ZERO
	model.local_height_offset_px = 0.0
	active_model = model
	selected_part = model
	selection_changed.emit(model)
	model_changed.emit(model)
	return model


func create_part(
	body_type: ModelData.BodyType = ModelData.BodyType.RECTANGULAR,
	size_px: Vector2 = Vector2.ZERO,
	height_px: float = -1.0,
	model_name: String = "Model Part") -> ModelData:
	var part: ModelData = ModelData.new()
	part.model_name = model_name
	part.body_type = body_type
	if size_px.x > 0.0 and size_px.y > 0.0:
		part.size_px = size_px
	else:
		part.size_px = default_model_size_px
	if height_px >= 0.0:
		part.height_px = height_px
	else:
		part.height_px = default_model_height_px
	return part


func set_active_model(model: ModelData) -> void:
	active_model = model
	selected_part = null
	moving_part = null
	moving_parent = null
	move_preview_candidates.clear()
	selection_changed.emit(null)


func set_selected_part(part: ModelData) -> bool:
	if part == null:
		selected_part = null
		selection_changed.emit(null)
		return true
	if active_model != null and not contains_part(active_model, part, true):
		return false
	selected_part = part
	selection_changed.emit(part)
	return true


func add_part(parent: ModelData, part: ModelData, local_position: Vector2 = Vector2.ZERO, local_height_offset_px: float = 0.0) -> bool:
	if parent == null or part == null or parent == part:
		return false
	if contains_part(part, parent, true):
		return false
	if parent.has_part(part):
		part.local_position = local_position
		part.local_height_offset_px = maxf(local_height_offset_px, 0.0)
		model_changed.emit(get_root_for_part(parent))
		return true

	part.local_position = local_position
	part.local_height_offset_px = maxf(local_height_offset_px, 0.0)
	var added: bool = parent.add_part(part)
	if added:
		model_changed.emit(get_root_for_part(parent))
	return added


func remove_part(parent: ModelData, part: ModelData) -> bool:
	if parent == null or part == null:
		return false
	var removed: bool = parent.remove_part(part)
	if removed:
		if selected_part == part:
			set_selected_part(null)
		model_changed.emit(get_root_for_part(parent))
	return removed


func combine_into_parent(parent: ModelData, parts: Array[ModelData]) -> bool:
	if parent == null:
		return false
	var changed: bool = false
	for part in parts:
		if part == null or part == parent:
			continue
		if contains_part(part, parent, true):
			continue
		var world_pose: Dictionary = get_world_pose(active_model, part)
		if not bool(world_pose.get("valid", false)):
			continue
		var old_parent: ModelData = find_parent(active_model, part)
		if old_parent != null:
			old_parent.remove_part(part)
		if parent.add_part(part):
			_apply_world_pose_to_parent(active_model, part, parent, world_pose)
			changed = true

	if changed:
		var root: ModelData = get_root_for_part(parent)
		model_changed.emit(root)
	return changed


## Creates a new parent ModelData and places the requested parts inside it.
## The selected parts keep their individual identities and local geometry.
func combine_model(
	parent: ModelData,
	parts: Array[ModelData],
	combined_name: String = "Combined Model") -> ModelData:
	if parent == null or parts.is_empty():
		return null

	var valid_parts: Array[ModelData] = []
	for part in parts:
		if part == null or part == parent:
			continue
		if not contains_part(parent, part, true):
			continue
		if find_parent(parent, part) != parent:
			continue
		valid_parts.append(part)

	if valid_parts.is_empty():
		return null

	var combined: ModelData = ModelData.new()
	combined.model_name = combined_name
	combined.base_color = parent.base_color
	combined.size_px = default_model_size_px
	combined.height_px = 0.0
	combined.local_position = _average_part_world_position(parent, valid_parts)
	combined.local_height_offset_px = 0.0
	combined.allow_parts_on_top = true
	combined.allow_parts_on_sides = true

	var combined_position: Vector2 = combined.local_position
	var parent_world_position: Vector2 = Vector2.ZERO
	var parent_world_rotation: float = 0.0
	if active_model != null:
		var parent_pose: Dictionary = get_world_pose(active_model, parent)
		if bool(parent_pose.get("valid", false)):
			parent_world_position = parent_pose["position"]
			parent_world_rotation = parent_pose["rotation_degrees"]

	combined.local_position = _world_to_parent_position(
		combined_position,
		parent_world_position,
		parent_world_rotation)
	combined.local_rotation_degrees = 0.0
	combined.local_height_offset_px = 0.0

	if not parent.add_part(combined):
		return null

	for part in valid_parts:
		var part_pose: Dictionary = get_world_pose(active_model, part)
		parent.remove_part(part)
		combined.add_part(part)
		_apply_world_pose_to_parent(active_model, part, combined, part_pose)

	model_changed.emit(get_root_for_part(parent))
	selected_part = combined
	selection_changed.emit(combined)
	return combined


func detach_part(root: ModelData, part: ModelData) -> bool:
	if root == null or part == null or root == part:
		return false
	if not contains_part(root, part, true):
		return false

	var old_parent: ModelData = find_parent(root, part)
	if old_parent == null:
		return false

	var world_pose: Dictionary = get_world_pose(root, part)
	if not bool(world_pose.get("valid", false)):
		return false

	old_parent.remove_part(part)
	if not root.add_part(part):
		old_parent.add_part(part)
		return false

	_apply_world_pose_to_parent(root, part, root, world_pose)
	selected_part = part
	model_changed.emit(root)
	selection_changed.emit(part)
	return true


## Detaches a part and immediately enters move-preview mode.
func detach_part_and_begin_move(root: ModelData, part: ModelData) -> bool:
	if not detach_part(root, part):
		return false
	return begin_move_part(root, part)


func begin_move_part(root: ModelData, part: ModelData) -> bool:
	if root == null or part == null or root == part:
		return false
	if not contains_part(root, part, true):
		return false
	if moving_part != null:
		cancel_move()

	var parent: ModelData = find_parent(root, part)
	if parent == null:
		return false
	var pose: Dictionary = get_world_pose(root, part)
	if not bool(pose.get("valid", false)):
		return false

	active_model = root
	selected_part = part
	moving_part = part
	moving_parent = parent
	move_original_parent = parent
	move_original_world_position = pose["position"]
	move_original_world_rotation_degrees = pose["rotation_degrees"]
	move_original_world_base_height_px = pose["base_height_px"]
	move_preview_world_position = move_original_world_position
	move_preview_world_rotation_degrees = move_original_world_rotation_degrees
	move_preview_world_base_height_px = move_original_world_base_height_px
	move_preview_snap_type = SnapType.NONE
	move_preview_target = null
	move_preview_candidates.clear()

	move_started.emit(part)
	selection_changed.emit(part)
	return true


## Updates a move without changing the real ModelData transform.
## The returned Dictionary is intended for a future ghost renderer.
func update_move_preview(world_position: Vector2, use_snapping: bool = true) -> Dictionary:
	if moving_part == null or active_model == null:
		return {}

	move_preview_world_position = world_position
	move_preview_world_base_height_px = move_original_world_base_height_px
	move_preview_snap_type = SnapType.NONE
	move_preview_target = null

	var candidates: Array = get_snap_candidates(
		active_model,
		moving_part,
		world_position)
	move_preview_candidates = candidates
	snap_candidates_changed.emit(moving_part, candidates)

	if use_snapping and not candidates.is_empty():
		var best: Dictionary = candidates[0]
		if bool(best.get("within_threshold", false)):
			move_preview_world_position = best["position"]
			move_preview_world_base_height_px = best["base_height_px"]
			move_preview_snap_type = int(best.get("snap_type", SnapType.NONE))
			move_preview_target = best["target"]

	var preview: Dictionary = get_move_preview()
	move_preview_changed.emit(moving_part, preview)
	return preview


func get_move_preview_footprint() -> PackedVector2Array:
	if moving_part == null or active_model == null:
		return PackedVector2Array()
	return _get_world_footprint(active_model, moving_part, move_preview_world_position, true)


func get_move_preview() -> Dictionary:
	if moving_part == null:
		return {}
	return {
		"valid": true,
		"part": moving_part,
		"position": move_preview_world_position,
		"rotation_degrees": move_preview_world_rotation_degrees,
		"base_height_px": move_preview_world_base_height_px,
		"snap_type": move_preview_snap_type,
		"target": move_preview_target,
		"candidates": move_preview_candidates.duplicate(),
	}


## Commits the current ghost position. If snap_type is supplied, a matching
## candidate is preferred; callers can right-click/confirm without snapping by
## leaving it as NONE.
func commit_move(snap_type: SnapType = SnapType.NONE, target: ModelData = null) -> bool:
	if moving_part == null or active_model == null or moving_parent == null:
		return false

	var destination_position: Vector2 = move_preview_world_position
	var destination_height: float = move_preview_world_base_height_px
	var destination_target: ModelData = target
	if snap_type != SnapType.NONE:
		var snapped: Dictionary = _find_requested_candidate(snap_type, target)
		if not snapped.is_empty():
			destination_position = snapped["position"]
			destination_height = snapped["base_height_px"]
			destination_target = snapped["target"]

	var source_part: ModelData = moving_part
	var root: ModelData = active_model
	var destination_parent: ModelData = moving_parent
	if destination_target != null:
		if snap_type == SnapType.TOP:
			destination_parent = destination_target
		else:
			var sibling_parent: ModelData = find_parent(root, destination_target)
			if sibling_parent != null:
				destination_parent = sibling_parent

	var world_pose: Dictionary = {
		"valid": true,
		"position": destination_position,
		"rotation_degrees": move_preview_world_rotation_degrees,
		"base_height_px": destination_height,
	}

	if destination_parent != moving_parent:
		if not _reparent_preserve_world(root, source_part, destination_parent, world_pose):
			return false
	else:
		_apply_world_pose_to_parent(root, source_part, destination_parent, world_pose)

	moving_part = null
	moving_parent = null
	move_original_parent = null
	move_preview_candidates.clear()
	move_preview_snap_type = SnapType.NONE
	move_preview_target = null

	model_changed.emit(root)
	move_finished.emit(source_part)
	return true


func cancel_move() -> void:
	if moving_part == null or active_model == null:
		return

	var part: ModelData = moving_part
	var world_pose: Dictionary = {
		"valid": true,
		"position": move_original_world_position,
		"rotation_degrees": move_original_world_rotation_degrees,
		"base_height_px": move_original_world_base_height_px,
	}
	var current_parent: ModelData = find_parent(active_model, part)
	if current_parent != null and move_original_parent != null and current_parent != move_original_parent:
		current_parent.remove_part(part)
		move_original_parent.add_part(part)
	_apply_world_pose_to_parent(active_model, part, move_original_parent, world_pose)

	moving_part = null
	moving_parent = null
	move_original_parent = null
	move_preview_candidates.clear()
	move_preview_target = null
	move_preview_snap_type = SnapType.NONE

	model_changed.emit(active_model)
	move_cancelled.emit(part)


## Returns all top/side snap candidates sorted by distance to the pointer.
## No snapping is performed by this function.
func get_snap_candidates(root: ModelData, source: ModelData, world_position: Vector2) -> Array:
	var candidates: Array = []
	if root == null or source == null or root == source:
		return candidates
	if not contains_part(root, source, true):
		return candidates

	var source_polygon: PackedVector2Array = _get_world_footprint(root, source, world_position, true)
	if source_polygon.is_empty():
		return candidates
	var source_bounds: Rect2 = _polygon_bounds(source_polygon)
	var source_half_x: float = source_bounds.size.x * 0.5
	var source_half_y: float = source_bounds.size.y * 0.5

	for target in root.get_all_parts_recursive(true):
		if target == null or target == source:
			continue
		if _is_descendant_of(source, target):
			continue

		var target_polygon: PackedVector2Array = _get_world_footprint(root, target, Vector2.ZERO, false)
		if target_polygon.is_empty():
			continue
		var target_bounds: Rect2 = _polygon_bounds(target_polygon)
		var target_pose: Dictionary = get_world_pose(root, target)
		if not bool(target_pose.get("valid", false)):
			continue

		if target.can_accept_top_part():
			var top_position: Vector2 = target_pose["position"]
			var top_height: float = target_pose["base_height_px"] + target.get_top_height_px()
			_append_snap_candidate(
				candidates,
				SnapType.TOP,
				target,
				top_position,
				top_height,
				world_position)

		if target.can_accept_side_part():
			var front_y: float = target_bounds.position.y - source_half_y
			var back_y: float = target_bounds.end.y + source_half_y
			var left_x: float = target_bounds.position.x - source_half_x
			var right_x: float = target_bounds.end.x + source_half_x

			var front_position: Vector2 = Vector2(
				clampf(world_position.x, target_bounds.position.x + source_half_x, target_bounds.end.x - source_half_x),
				front_y)
			var back_position: Vector2 = Vector2(
				clampf(world_position.x, target_bounds.position.x + source_half_x, target_bounds.end.x - source_half_x),
				back_y)
			var left_position: Vector2 = Vector2(
				left_x,
				clampf(world_position.y, target_bounds.position.y + source_half_y, target_bounds.end.y - source_half_y))
			var right_position: Vector2 = Vector2(
				right_x,
				clampf(world_position.y, target_bounds.position.y + source_half_y, target_bounds.end.y - source_half_y))

			_append_snap_candidate(candidates, SnapType.FRONT, target, front_position, target_pose["base_height_px"], world_position)
			_append_snap_candidate(candidates, SnapType.BACK, target, back_position, target_pose["base_height_px"], world_position)
			_append_snap_candidate(candidates, SnapType.LEFT, target, left_position, target_pose["base_height_px"], world_position)
			_append_snap_candidate(candidates, SnapType.RIGHT, target, right_position, target_pose["base_height_px"], world_position)

	candidates.sort_custom(Callable(self, "_sort_snap_candidates"))
	return candidates


func get_best_snap_candidate(root: ModelData, source: ModelData, world_position: Vector2) -> Dictionary:
	var candidates: Array = get_snap_candidates(root, source, world_position)
	if candidates.is_empty():
		return {}
	return candidates[0]


func should_prompt_for_snap(root: ModelData, source: ModelData, world_position: Vector2) -> bool:
	var best: Dictionary = get_best_snap_candidate(root, source, world_position)
	return not best.is_empty() and bool(best.get("within_threshold", false))


func get_part_at_flat_position(root: ModelData, world_position: Vector2, include_root: bool = true) -> ModelData:
	if root == null:
		return null
	var candidates: Array[ModelData] = root.get_all_parts_recursive(include_root)
	var best: ModelData = null
	var best_height: float = -INF
	var best_depth: int = -1
	for part in candidates:
		if part == null:
			continue
		var polygon: PackedVector2Array = _get_world_footprint(root, part, Vector2.ZERO, false)
		if polygon.is_empty() or not Geometry2D.is_point_in_polygon(world_position, polygon):
			continue
		var pose: Dictionary = get_world_pose(root, part)
		if not bool(pose.get("valid", false)):
			continue
		var depth: int = get_part_depth(root, part)
		var height: float = float(pose["base_height_px"])
		if height > best_height or (is_equal_approx(height, best_height) and depth > best_depth):
			best = part
			best_height = height
			best_depth = depth
	return best


func get_part_depth(root: ModelData, part: ModelData) -> int:
	if root == null or part == null:
		return -1
	if root == part:
		return 0
	var depth: int = _find_depth_recursive(root, part, 0)
	return depth


func get_root_for_part(part: ModelData) -> ModelData:
	if active_model == null or part == null:
		return null
	if active_model == part:
		return active_model
	return active_model if contains_part(active_model, part, true) else null


func contains_part(root: ModelData, part: ModelData, include_root: bool = false) -> bool:
	if root == null or part == null:
		return false
	if include_root and root == part:
		return true
	return _contains_part_recursive(root, part)


func find_parent(root: ModelData, part: ModelData) -> ModelData:
	if root == null or part == null or root == part:
		return null
	return _find_parent_recursive(root, part)


## Sets one of the five texture constructions on an individual part.
func set_part_face_textures(
	part: ModelData,
	face: int,
	texture_set: ObjectFaceTextureData) -> bool:
	if part == null or texture_set == null:
		return false
	part.set_face_texture_set(face, texture_set)
	var root: ModelData = get_root_for_part(part)
	if root != null:
		model_changed.emit(root)
	return true


func set_part_top_texture_rotation(part: ModelData, degrees: float) -> bool:
	if part == null:
		return false
	part.set_top_texture_rotation_degrees(degrees)
	var root: ModelData = get_root_for_part(part)
	if root != null:
		model_changed.emit(root)
	return true


func paint_part_base_color(part: ModelData, color: Color, enable_fallback: bool = true) -> bool:
	if part == null:
		return false
	part.base_color = color
	part.use_base_color_fallback = enable_fallback
	part.emit_changed()
	var root: ModelData = get_root_for_part(part)
	if root != null:
		model_changed.emit(root)
	return true


func set_part_texture_fallback(part: ModelData, enabled: bool) -> bool:
	if part == null:
		return false
	part.use_base_color_fallback = enabled
	part.emit_changed()
	var root: ModelData = get_root_for_part(part)
	if root != null:
		model_changed.emit(root)
	return true


func set_part_geometry(
	part: ModelData,
	body_type: ModelData.BodyType,
	size_px: Vector2,
	height_px: float,
	top_end_point: Vector2 = Vector2.ZERO,
	top_end_size_px: Vector2 = Vector2.ZERO) -> bool:
	if part == null:
		return false
	part.body_type = body_type
	part.size_px = Vector2(maxf(size_px.x, 1.0), maxf(size_px.y, 1.0))
	part.height_px = maxf(height_px, 0.0)
	part.top_end_point = top_end_point
	part.top_end_size_px = Vector2(maxf(top_end_size_px.x, 0.0), maxf(top_end_size_px.y, 0.0))
	part.emit_changed()
	var root: ModelData = get_root_for_part(part)
	if root != null:
		model_changed.emit(root)
	return true


func set_part_position(part: ModelData, local_position: Vector2, local_height_offset_px: float = 0.0) -> bool:
	if part == null:
		return false
	part.local_position = local_position
	part.local_height_offset_px = maxf(local_height_offset_px, 0.0)
	part.emit_changed()
	var root: ModelData = get_root_for_part(part)
	if root != null:
		model_changed.emit(root)
	return true


func set_part_rotation(part: ModelData, degrees: float) -> bool:
	if part == null:
		return false
	part.local_rotation_degrees = degrees
	part.emit_changed()
	var root: ModelData = get_root_for_part(part)
	if root != null:
		model_changed.emit(root)
	return true


func build_model_on_object(object_data: ObjectData, model: ModelData) -> bool:
	if object_data == null or model == null:
		return false
	object_data.set_object_model(model)
	active_model = model
	selected_part = model
	selection_changed.emit(model)
	model_changed.emit(model)
	return true


func attach_model_to_object(object_data: ObjectData, model: ModelData) -> bool:
	return build_model_on_object(object_data, model)


func clear_object_model(object_data: ObjectData) -> bool:
	if object_data == null:
		return false
	var previous_model: Resource = object_data.object_model
	object_data.set_object_model(null)
	if previous_model == active_model:
		active_model = null
	selected_part = null
	return true


func get_context_actions_for_part(root: ModelData, part: ModelData) -> Array[String]:
	var actions: Array[String] = []
	if root == null or part == null or not contains_part(root, part, true):
		return actions
	actions.append("Move Part")
	if part != root:
		actions.append("Detach Part")
	if part != root and _can_combine_direct_children(root, part):
		actions.append("Combine Model")
	actions.append("Set Textures")
	actions.append("Paint Base Color")
	return actions


func _can_combine_direct_children(root: ModelData, part: ModelData) -> bool:
	var parent: ModelData = find_parent(root, part)
	return parent != null and parent.parts.size() >= 2


## Returns a world-space pose dictionary for a part.
## Position/rotation are flat-space. base_height_px is vertical height of the
## part's local base above the root's base plane.
func get_world_pose(root: ModelData, part: ModelData) -> Dictionary:
	if root == null or part == null:
		return {"valid": false}
	if root == part:
		return {
			"valid": true,
			"position": part.local_position,
			"rotation_degrees": part.local_rotation_degrees,
			"base_height_px": part.local_height_offset_px,
		}
	return _get_world_pose_recursive(
		root,
		part,
		root.local_position,
		root.local_rotation_degrees,
		root.local_height_offset_px)


func _get_world_pose_recursive(
	parent: ModelData,
	target: ModelData,
	parent_world_position: Vector2,
	parent_world_rotation_degrees: float,
	parent_world_height: float) -> Dictionary:
	for child in parent.parts:
		if child == null:
			continue
		var child_rotation: float = parent_world_rotation_degrees + child.local_rotation_degrees
		var child_position: Vector2 = parent_world_position + child.local_position.rotated(deg_to_rad(parent_world_rotation_degrees))
		var child_height: float = parent_world_height + child.local_height_offset_px
		if child == target:
			return {
				"valid": true,
				"position": child_position,
				"rotation_degrees": child_rotation,
				"base_height_px": child_height,
			}
		var nested: Dictionary = _get_world_pose_recursive(
			child,
			target,
			child_position,
			child_rotation,
			child_height)
		if bool(nested.get("valid", false)):
			return nested
	return {"valid": false}


func _get_world_footprint(
	root: ModelData,
	part: ModelData,
	override_position: Vector2,
	use_override_position: bool = false) -> PackedVector2Array:
	var pose: Dictionary = get_world_pose(root, part)
	if not bool(pose.get("valid", false)):
		return PackedVector2Array()
	var polygon: PackedVector2Array = part.get_flat_footprint_polygon()
	var result: PackedVector2Array = PackedVector2Array()
	var position: Vector2 = pose["position"]
	if use_override_position:
		position = override_position
	var rotation_radians: float = deg_to_rad(float(pose["rotation_degrees"]))
	for point in polygon:
		result.append(position + point.rotated(rotation_radians))
	return result


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var min_point: Vector2 = polygon[0]
	var max_point: Vector2 = polygon[0]
	for point in polygon:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return Rect2(min_point, max_point - min_point)


func _append_snap_candidate(
	candidates: Array,
	snap_type: SnapType,
	target: ModelData,
	position: Vector2,
	base_height_px: float,
	pointer_position: Vector2) -> void:
	var distance: float = pointer_position.distance_to(position)
	var target_threshold: float = maxf(target.snap_distance_px, default_snap_distance_px)
	candidates.append({
		"snap_type": snap_type,
		"target": target,
		"position": position,
		"base_height_px": base_height_px,
		"distance_px": distance,
		"threshold_px": target_threshold,
		"within_threshold": distance <= target_threshold,
	})


func _sort_snap_candidates(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("distance_px", INF)) < float(b.get("distance_px", INF))


func _find_requested_candidate(snap_type: SnapType, target: ModelData) -> Dictionary:
	if move_preview_candidates.is_empty():
		return {}
	for candidate in move_preview_candidates:
		if int(candidate.get("snap_type", SnapType.NONE)) != int(snap_type):
			continue
		if target != null and candidate.get("target") != target:
			continue
		return candidate
	return {}


func _reparent_preserve_world(
	root: ModelData,
	part: ModelData,
	new_parent: ModelData,
	desired_world_pose: Dictionary) -> bool:
	if root == null or part == null or new_parent == null or part == new_parent:
		return false
	if _contains_part_recursive(part, new_parent):
		return false

	var old_parent: ModelData = find_parent(root, part)
	if old_parent == new_parent:
		_apply_world_pose_to_parent(root, part, new_parent, desired_world_pose)
		return true

	if old_parent != null:
		old_parent.remove_part(part)
	if not new_parent.add_part(part):
		if old_parent != null:
			old_parent.add_part(part)
		return false
	_apply_world_pose_to_parent(root, part, new_parent, desired_world_pose)
	return true


func _apply_world_pose_to_parent(
	root: ModelData,
	part: ModelData,
	new_parent: ModelData,
	world_pose: Dictionary) -> void:
	if part == null or new_parent == null:
		return

	var parent_pose: Dictionary = get_world_pose(root, new_parent)
	var parent_position: Vector2 = Vector2.ZERO
	var parent_rotation: float = 0.0
	var parent_height: float = 0.0
	if bool(parent_pose.get("valid", false)):
		parent_position = parent_pose["position"]
		parent_rotation = parent_pose["rotation_degrees"]
		parent_height = parent_pose["base_height_px"]

	var world_position: Vector2 = world_pose["position"]
	var world_rotation: float = float(world_pose["rotation_degrees"])
	var world_height: float = float(world_pose["base_height_px"])

	part.local_position = _world_to_parent_position(world_position, parent_position, parent_rotation)
	part.local_rotation_degrees = world_rotation - parent_rotation
	part.local_height_offset_px = maxf(world_height - parent_height, 0.0)
	part.emit_changed()


func _world_to_parent_position(world_position: Vector2, parent_world_position: Vector2, parent_world_rotation_degrees: float) -> Vector2:
	return (world_position - parent_world_position).rotated(-deg_to_rad(parent_world_rotation_degrees))


func _average_part_world_position(root: ModelData, parts: Array[ModelData]) -> Vector2:
	if parts.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	var count: int = 0
	for part in parts:
		var pose: Dictionary = get_world_pose(root, part)
		if not bool(pose.get("valid", false)):
			continue
		total += pose["position"]
		count += 1
	if count == 0:
		return Vector2.ZERO
	return total / float(count)


func _contains_part_recursive(parent: ModelData, target: ModelData) -> bool:
	for child in parent.parts:
		if child == target:
			return true
		if child != null and _contains_part_recursive(child, target):
			return true
	return false


func _find_parent_recursive(parent: ModelData, target: ModelData) -> ModelData:
	for child in parent.parts:
		if child == target:
			return parent
		if child != null:
			var nested: ModelData = _find_parent_recursive(child, target)
			if nested != null:
				return nested
	return null


func _find_depth_recursive(parent: ModelData, target: ModelData, current_depth: int) -> int:
	for child in parent.parts:
		if child == target:
			return current_depth + 1
		if child != null:
			var nested_depth: int = _find_depth_recursive(child, target, current_depth + 1)
			if nested_depth >= 0:
				return nested_depth
	return -1


func _is_descendant_of(ancestor_candidate: ModelData, possible_descendant: ModelData) -> bool:
	if ancestor_candidate == null or possible_descendant == null:
		return false
	return _contains_part_recursive(ancestor_candidate, possible_descendant)
