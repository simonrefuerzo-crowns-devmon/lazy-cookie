class_name RoomBuilderWallOps
extends RefCounted

## Wall selection, creation, snapping flow, extension, and endpoint rebuild.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func pick_wall(point: Vector2, screen_point: Vector2 = Vector2.INF) -> Dictionary:
	if not ctx.DEBUG_MODE or ctx.room_data == null:
		return {}

	if ctx.isometric_mode and ctx.iso_wall_renderer != null:
		var iso_hit := ctx.iso_wall_renderer.pick_wall(
			screen_point if screen_point != Vector2.INF else point
		)
		if not iso_hit.is_empty():
			return iso_hit

	var best_segment: WallSegment = null
	var best_point := Vector2.ZERO
	var best_distance := INF

	for segment in ctx.room_data.wall_segments:
		if segment.get_length() < ctx.min_wall_length:
			continue

		var closest := Geometry2D.get_closest_point_to_segment(
			point,
			segment.start_point,
			segment.end_point
		)
		var center_distance := closest.distance_to(point)
		var hit_distance := (
			segment.thickness * 0.5
			+ segment.line_width * 0.5
			+ ctx.wall_hit_padding
		)

		if center_distance <= hit_distance and center_distance < best_distance:
			best_distance = center_distance
			best_segment = segment
			best_point = closest

	if best_segment == null:
		return {}

	if best_point.distance_to(best_segment.start_point) <= RoomData.JOIN_EPSILON:
		best_point = best_segment.start_point
	elif best_point.distance_to(best_segment.end_point) <= RoomData.JOIN_EPSILON:
		best_point = best_segment.end_point

	return {
		"segment": best_segment,
		"point": best_point,
		"distance": best_distance,
	}

func select_wall(hit: Dictionary) -> void:
	var segment_value: Variant = hit.get("segment", null)
	if segment_value is not WallSegment:
		return
	ctx.selected_segment = segment_value
	var point_value: Variant = hit.get("point", ctx.selected_segment.start_point)
	if point_value is Vector2:
		ctx.selected_point = point_value
	else:
		ctx.selected_point = ctx.selected_segment.start_point
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status("Wall selected. Choose an edit operation from the wall menu.")

func clear_selection() -> void:
	ctx.selected_segment = null
	ctx.selected_point = Vector2.ZERO
	ctx.overlay.queue_redraw()


# ---------------------------------------------------------------- Wall creation

func begin_new_wall(
		start: Vector2,
		operation: int,
		source_segment: WallSegment,
		has_branch: bool) -> void:
	ctx.operation = operation
	ctx.start_point = start
	ctx.end_point = start
	ctx.has_branch_point = has_branch
	ctx.branch_point = start
	ctx.has_snap_target = false
	ctx.selected_floor = null
	ctx.selected_floor_point = Vector2.ZERO
	ctx.editing_segment = null
	ctx.editing_end = -1

	if source_segment != null:
		ctx.pending_color = source_segment.color
		ctx.pending_thickness = source_segment.thickness
		ctx.pending_line_width = source_segment.line_width
		ctx.pending_start_cap = WallSegment.CapStyle.FLAT
		ctx.pending_end_cap = source_segment.end_cap_style

	ctx.ui_module.sync_start_dialog_from_pending()
	ctx.state = RoomBuilderTypes.State.START_PROMPT
	ctx.rendering.clear_ghost()
	ctx.overlay.queue_redraw()
	ctx.ui_module.popup_near_mouse(ctx.start_dialog)

func begin_extension() -> void:
	if ctx.selected_segment == null:
		return

	var source := ctx.selected_segment
	var branch_point := ctx.selected_point

	# A branch from the middle of a wall will split the existing wall when the
	# new segment is finally confirmed. Do not modify room data while previewing.
	var is_body_point := true
	if branch_point.distance_to(source.start_point) <= RoomData.JOIN_EPSILON:
		branch_point = source.start_point
		is_body_point = false
	elif branch_point.distance_to(source.end_point) <= RoomData.JOIN_EPSILON:
		branch_point = source.end_point
		is_body_point = false

	begin_new_wall(branch_point, RoomBuilderTypes.Operation.EXTEND, source, is_body_point)
	ctx.ui_module.set_status("Extending from the selected point. Choose the new wall settings, then place the other end.")

func on_start_confirmed() -> void:
	ctx.ui_module.read_pending_visual_settings()
	ctx.state = RoomBuilderTypes.State.PLACING_END if ctx.operation != RoomBuilderTypes.Operation.REBUILD else RoomBuilderTypes.State.REBUILD_PLACING
	ctx.rendering.update_ghost()
	ctx.ui_module.set_status("Move the mouse and left click to choose the end point. A nearby wall snap will ask before applying.")

func handle_end_click(point: Vector2) -> void:
	ctx.accepted_snap_hits_body = false
	if point.distance_to(ctx.start_point) < ctx.min_wall_length:
		ctx.ui_module.set_status("End point is too close to the start point. Pick another spot.")
		return

	var target := find_snap_target(point)
	if not target.is_empty():
		var target_point: Vector2 = Vector2(target.get("point", point))
		var target_body: bool = bool(target.get("body", false))
		if target_point.distance_to(point) > ctx.snap_epsilon:
			ctx.has_snap_target = true
			ctx.snap_point = target_point
			ctx.snap_hits_body = target_body
			ctx.last_clicked_point = point
			ctx.state = RoomBuilderTypes.State.SNAP_PROMPT
			ctx.snap_dialog.dialog_text = build_snap_question()
			ctx.ui_module.popup_near_mouse(ctx.snap_dialog)
			ctx.overlay.queue_redraw()
			return

	accept_end_point(point, false)

func accept_end_point(point: Vector2, did_snap: bool, snap_body: bool = false) -> void:
	ctx.end_point = point
	ctx.has_snap_target = false
	ctx.snap_hits_body = false
	ctx.accepted_snap_hits_body = did_snap and snap_body
	if did_snap:
		ctx.ui_module.set_status("Snap accepted. Confirm the wall placement.")
	else:
		ctx.ui_module.set_status("End point selected. Confirm the wall placement.")
	ctx.state = RoomBuilderTypes.State.END_PROMPT
	ctx.rendering.update_ghost()
	ctx.end_dialog.dialog_text = build_end_question()
	ctx.ui_module.popup_near_mouse(ctx.end_dialog)

func build_end_question() -> String:
	var prefix := "Extend wall" if ctx.operation == RoomBuilderTypes.Operation.EXTEND else "Build wall"
	if ctx.operation == RoomBuilderTypes.Operation.REBUILD:
		prefix = "Move wall endpoint"
	return "%s to this point?\nLength: %d px" % [prefix, int(ctx.start_point.distance_to(ctx.end_point))]

func build_snap_question() -> String:
	if ctx.snap_hits_body:
		return "Snap this endpoint to the middle of an existing wall?\nThis will split that wall at the snapped point."
	return "Snap this endpoint to the nearby wall endpoint?\nThe endpoints will become one shared joint."

func on_snap_confirmed() -> void:
	if ctx.state != RoomBuilderTypes.State.SNAP_PROMPT:
		return
	accept_end_point(ctx.snap_point, true, ctx.snap_hits_body)

func on_snap_canceled() -> void:
	if ctx.state != RoomBuilderTypes.State.SNAP_PROMPT:
		return
	accept_end_point(ctx.last_clicked_point, false, false)

func on_end_confirmed() -> void:
	if ctx.operation == RoomBuilderTypes.Operation.REBUILD:
		commit_rebuild()
	else:
		commit_new_wall()

func commit_new_wall() -> void:
	if ctx.start_point.distance_to(ctx.end_point) < ctx.min_wall_length:
		cancel_wall("Wall was not created: it is too short.")
		return

	# If the operation started from a wall body, make that exact location a joint.
	if ctx.has_branch_point:
		ctx.room_data.split_at_point(ctx.branch_point)

	# If the new end was snapped onto a wall body, make that location a joint too.
	if ctx.accepted_snap_hits_body:
		ctx.room_data.split_at_point(ctx.end_point)

	ctx.room_data.add_wall_segment(
		ctx.start_point,
		ctx.end_point,
		ctx.pending_color,
		ctx.pending_thickness,
		ctx.pending_line_width,
		ctx.pending_start_cap,
		ctx.pending_end_cap)

	ctx.rendering.rebuild_walls()
	finish_wall_operation()
	ctx.ui_module.set_status("Wall built. Left click an empty area to start another wall or click a wall to edit it.")
	ctx.floor_ops.prompt_for_new_enclosures()

func reset_wall_operation() -> void:
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.operation = RoomBuilderTypes.Operation.NEW
	ctx.rendering.clear_ghost()
	ctx.has_snap_target = false
	ctx.snap_hits_body = false
	ctx.accepted_snap_hits_body = false
	ctx.has_branch_point = false
	ctx.editing_segment = null
	ctx.editing_end = -1
	ctx.overlay.queue_redraw()

func finish_wall_operation() -> void:
	reset_wall_operation()

func cancel_wall(message: String = "Wall operation cancelled.") -> void:
	reset_wall_operation()
	ctx.ui_module.set_status(message)


# ---------------------------------------------------------------- Snapping

func refresh_snap_preview(point: Vector2) -> void:
	var target := find_snap_target(point)
	if target.is_empty():
		ctx.has_snap_target = false
		ctx.snap_hits_body = false
	else:
		var target_point: Vector2 = Vector2(target.get("point", point))
		var target_body: bool = bool(target.get("body", false))
		ctx.has_snap_target = true
		ctx.snap_point = target_point
		ctx.snap_hits_body = target_body
	ctx.overlay.queue_redraw()

func find_snap_target(point: Vector2) -> Dictionary:
	var exclude: WallSegment = ctx.editing_segment if ctx.operation == RoomBuilderTypes.Operation.REBUILD else null
	return ctx.room_data.find_snap_target(point, maxf(ctx.snap_radius, 0.0), exclude)


# ---------------------------------------------------------------- Wall editing menu

func refresh_wall_menu_state() -> void:
	if ctx.selected_segment == null:
		return

	var can_rebuild := ctx.room_data.is_end_free(ctx.selected_segment, 0) or ctx.room_data.is_end_free(ctx.selected_segment, 1)
	var rebuild_index := ctx.wall_menu.get_item_index(1)
	if rebuild_index >= 0:
		ctx.wall_menu.set_item_disabled(rebuild_index, not can_rebuild)

func begin_rebuild_prompt() -> void:
	if ctx.selected_segment == null:
		return

	var free_start := ctx.room_data.is_end_free(ctx.selected_segment, 0)
	var free_end := ctx.room_data.is_end_free(ctx.selected_segment, 1)

	if not free_start and not free_end:
		ctx.ui_module.set_status("This wall has no free endpoint. Both ends are connected to other walls.")
		return

	ctx.rebuild_end_button.clear()
	if free_start:
		ctx.rebuild_end_button.add_item("Start endpoint", 0)
	if free_end:
		ctx.rebuild_end_button.add_item("End endpoint", 1)

	var preferred_end := -1
	if ctx.selected_point.distance_to(ctx.selected_segment.start_point) <= RoomData.JOIN_EPSILON and free_start:
		preferred_end = 0
	elif ctx.selected_point.distance_to(ctx.selected_segment.end_point) <= RoomData.JOIN_EPSILON and free_end:
		preferred_end = 1
	elif free_start:
		preferred_end = 0
	else:
		preferred_end = 1

	for item_index in range(ctx.rebuild_end_button.item_count):
		if ctx.rebuild_end_button.get_item_id(item_index) == preferred_end:
			ctx.rebuild_end_button.select(item_index)
			break

	ctx.rebuild_end_dialog.dialog_text = "Choose the free endpoint to rebuild.\nThe other endpoint remains fixed."
	ctx.state = RoomBuilderTypes.State.REBUILD_END_PROMPT
	ctx.rebuild_end_dialog.popup_centered(Vector2i(360, 150))

func on_rebuild_end_confirmed() -> void:
	if ctx.selected_segment == null:
		ctx.state = RoomBuilderTypes.State.IDLE
		return

	if ctx.rebuild_end_button.item_count <= 0:
		return

	ctx.editing_end = ctx.rebuild_end_button.get_selected_id()
	if ctx.editing_end != 0 and ctx.editing_end != 1:
		return

	if not ctx.room_data.is_end_free(ctx.selected_segment, ctx.editing_end):
		ctx.ui_module.set_status("That endpoint is no longer free and cannot be moved.")
		ctx.state = RoomBuilderTypes.State.IDLE
		return

	ctx.editing_segment = ctx.selected_segment
	ctx.operation = RoomBuilderTypes.Operation.REBUILD
	ctx.pending_color = ctx.editing_segment.color
	ctx.pending_thickness = ctx.editing_segment.thickness
	ctx.pending_line_width = ctx.editing_segment.line_width
	ctx.pending_start_cap = ctx.editing_segment.start_cap_style
	ctx.pending_end_cap = ctx.editing_segment.end_cap_style

	if ctx.editing_end == 0:
		ctx.start_point = ctx.editing_segment.end_point
		ctx.end_point = ctx.editing_segment.start_point
	else:
		ctx.start_point = ctx.editing_segment.start_point
		ctx.end_point = ctx.editing_segment.end_point

	ctx.has_snap_target = false
	ctx.state = RoomBuilderTypes.State.REBUILD_PLACING
	ctx.rendering.update_ghost()
	ctx.ui_module.set_status("Move the free endpoint. The existing wall stays unchanged until you confirm the new position.")
	ctx.overlay.queue_redraw()

func commit_rebuild() -> void:
	if ctx.editing_segment == null or ctx.editing_end < 0:
		cancel_wall()
		return

	var fixed_point := ctx.editing_segment.get_point(1 - ctx.editing_end)
	if fixed_point.distance_to(ctx.end_point) < ctx.min_wall_length:
		ctx.ui_module.set_status("Endpoint cannot be moved onto the other endpoint.")
		ctx.state = RoomBuilderTypes.State.REBUILD_PLACING
		ctx.rendering.update_ghost()
		return

	# The new endpoint is the `ctx.end_point` in the rebuild preview, while the
	# opposite endpoint remains fixed at `ctx.start_point`.
	if ctx.accepted_snap_hits_body:
		ctx.room_data.split_at_point(ctx.end_point, ctx.editing_segment)

	if ctx.editing_end == 0:
		ctx.editing_segment.start_point = ctx.end_point
	else:
		ctx.editing_segment.end_point = ctx.end_point

	ctx.room_data.emit_changed()
	ctx.rendering.rebuild_walls()
	var moved_segment := ctx.editing_segment
	finish_wall_operation()
	ctx.selected_segment = moved_segment
	ctx.selected_point = ctx.end_point
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status("Wall endpoint rebuilt and all joints were regenerated.")
	ctx.floor_ops.prompt_for_new_enclosures()


# ---------------------------------------------------------------- Endpoint style editing

func on_start_canceled() -> void:
	cancel_wall()

func on_end_canceled() -> void:
	if ctx.operation == RoomBuilderTypes.Operation.REBUILD:
		ctx.state = RoomBuilderTypes.State.REBUILD_PLACING
		ctx.ui_module.set_status("Pick a different endpoint position, or press Esc to cancel the rebuild.")
	else:
		ctx.state = RoomBuilderTypes.State.PLACING_END
		ctx.ui_module.set_status("Pick a different end point, or press Esc to cancel.")
	ctx.rendering.update_ghost()


func on_rebuild_end_canceled() -> void:
	if ctx.state == RoomBuilderTypes.State.REBUILD_END_PROMPT:
		ctx.state = RoomBuilderTypes.State.IDLE
		ctx.ui_module.set_status("Rebuild cancelled.")
