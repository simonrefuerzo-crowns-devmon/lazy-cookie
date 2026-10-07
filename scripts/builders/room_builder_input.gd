class_name RoomBuilderInput
extends RefCounted

## Mouse, frame update, hover, click routing, and cancellation.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func unhandled_input(event: InputEvent) -> void:
	if not ctx.DEBUG_MODE:
		return
	if event is InputEventMouseButton and event.pressed:
		var mouse_button: int = (event as InputEventMouseButton).button_index
		if mouse_button == MOUSE_BUTTON_LEFT:
			on_left_click()
		elif mouse_button == MOUSE_BUTTON_RIGHT:
			on_right_click()
		return

	if event.is_action_pressed("ui_cancel"):
		handle_cancel()

func process(_delta: float) -> void:
	if not ctx.DEBUG_MODE:
		return
	
	if ctx.grid_renderer != null and ctx.grid_visible:
		ctx.grid_renderer.queue_redraw()

	var mouse_point := get_mouse_point()
	ctx.mouse_preview_point = mouse_point
	ctx.has_mouse_preview = true
	refresh_hover_wall(mouse_point)

	if ctx.state == RoomBuilderTypes.State.FLOOR_PLACING:
		ctx.overlay.queue_redraw()
		return

	if ctx.state == RoomBuilderTypes.State.PLACING_END or ctx.state == RoomBuilderTypes.State.REBUILD_PLACING:
		var point := ctx.mouse_preview_point
		if point != ctx.end_point:
			ctx.end_point = point
		ctx.wall_ops.refresh_snap_preview(point)
		ctx.rendering.update_ghost()
	else:
		ctx.overlay.queue_redraw()

func get_mouse_point() -> Vector2:
	var point := ctx.host.get_local_mouse_position()
	if ctx.isometric_mode and ctx.iso_wall_renderer != null:
		point = ctx.iso_wall_renderer.screen_to_plan(point, 0.0)

	if ctx.snap_size > 0.0:
		point = point.snapped(Vector2(ctx.snap_size, ctx.snap_size))
	return point

func get_grid_cell(point: Vector2) -> Vector2i:
	if ctx.snap_size <= 0.0:
		return Vector2i.ZERO
	return Vector2i(
		int(roundf(point.x / ctx.snap_size)),
		int(roundf(point.y / ctx.snap_size))
	)

func refresh_hover_wall(mouse_point: Vector2) -> void:
	var hit: Dictionary = ctx.wall_ops.pick_wall(mouse_point, ctx.host.get_local_mouse_position())
	var next_segment: WallSegment = null
	var next_point := Vector2.ZERO

	if not hit.is_empty():
		var segment_value: Variant = hit.get("segment", null)
		if segment_value is WallSegment:
			next_segment = segment_value
			var point_value: Variant = hit.get("point", mouse_point)
			if point_value is Vector2:
				next_point = point_value

	var changed := next_segment != ctx.hovered_segment
	if next_segment != null and ctx.hovered_segment == next_segment:
		changed = changed or not next_point.is_equal_approx(ctx.hovered_point)

	ctx.hovered_segment = next_segment
	ctx.hovered_point = next_point

	if changed:
		ctx.overlay.queue_redraw()

func on_left_click() -> void:
	if not ctx.DEBUG_MODE:
		return

	if ctx.state == RoomBuilderTypes.State.FLOOR_PLACING:
		ctx.floor_ops.handle_floor_click(get_mouse_point())
		return

	if ctx.state == RoomBuilderTypes.State.FLOOR_CONFIRM or ctx.state == RoomBuilderTypes.State.AUTO_FLOOR_PROMPT or ctx.state == RoomBuilderTypes.State.FLOOR_EDIT_PROMPT:
		return

	var screen_point := ctx.host.get_local_mouse_position()
	var mouse_point := get_mouse_point()
	var hit: Dictionary = ctx.wall_ops.pick_wall(mouse_point, screen_point)

	match ctx.state:
		RoomBuilderTypes.State.IDLE:
			if not hit.is_empty():
				ctx.wall_ops.select_wall(hit)
				ctx.ui_module.open_wall_menu()
				return
			ctx.wall_ops.clear_selection()
			ctx.floor_ops.clear_selection()
			ctx.wall_ops.begin_new_wall(mouse_point, RoomBuilderTypes.Operation.NEW, null, false)

		RoomBuilderTypes.State.PLACING_END:
			ctx.last_clicked_point = mouse_point
			ctx.wall_ops.handle_end_click(mouse_point)

		RoomBuilderTypes.State.REBUILD_PLACING:
			ctx.last_clicked_point = mouse_point
			ctx.wall_ops.handle_end_click(mouse_point)

func on_right_click() -> void:
	if ctx.state == RoomBuilderTypes.State.FLOOR_PLACING:
		if ctx.floor_polygon.size() >= 3:
			ctx.floor_ops.open_manual_floor_confirmation()
		else:
			ctx.floor_ops.cancel_floor("Floor polygon cancelled.")
		return

	if ctx.state == RoomBuilderTypes.State.FLOOR_CONFIRM or ctx.state == RoomBuilderTypes.State.AUTO_FLOOR_PROMPT or ctx.state == RoomBuilderTypes.State.FLOOR_EDIT_PROMPT:
		return

	var screen_point := ctx.host.get_local_mouse_position()
	var mouse_point := get_mouse_point()
	var hit: Dictionary = ctx.wall_ops.pick_wall(mouse_point, screen_point)
	if not hit.is_empty():
		ctx.floor_ops.clear_selection()
		ctx.wall_ops.select_wall(hit)
		ctx.ui_module.open_wall_menu()
		return

	var floor_hit: Dictionary = ctx.floor_renderer.pick_floor(screen_point) if ctx.floor_renderer != null else {}
	if not floor_hit.is_empty():
		ctx.wall_ops.clear_selection()
		ctx.floor_ops.select_floor(floor_hit)
		ctx.ui_module.open_floor_menu()
		return

	ctx.floor_ops.clear_selection()
	ctx.ui_module.open_context_menu()

func handle_cancel() -> void:
	match ctx.state:
		RoomBuilderTypes.State.PLACING_END, RoomBuilderTypes.State.START_PROMPT, RoomBuilderTypes.State.END_PROMPT, RoomBuilderTypes.State.SNAP_PROMPT:
			ctx.wall_ops.cancel_wall()
		RoomBuilderTypes.State.FLOOR_PLACING:
			ctx.floor_ops.cancel_floor()
		RoomBuilderTypes.State.FLOOR_CONFIRM:
			ctx.floor_ops.cancel_floor()
		RoomBuilderTypes.State.AUTO_FLOOR_PROMPT:
			ctx.floor_ops.on_auto_floor_canceled()
		RoomBuilderTypes.State.FLOOR_EDIT_PROMPT:
			ctx.floor_ops.on_floor_appearance_canceled()
		RoomBuilderTypes.State.REBUILD_END_PROMPT:
			ctx.editing.cancel_edit_prompt("Rebuild cancelled.")
		RoomBuilderTypes.State.REBUILD_PLACING:
			ctx.wall_ops.cancel_wall()
		RoomBuilderTypes.State.STYLE_PROMPT, RoomBuilderTypes.State.REPAINT_PROMPT, RoomBuilderTypes.State.DELETE_PROMPT:
			ctx.editing.cancel_edit_prompt("Edit cancelled.")


# ---------------------------------------------------------------- Wall picking / selection
