class_name RoomBuilderRendering
extends RefCounted

## Wall renderers, ghost preview, overlay drawing, and render mode switching.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func setup() -> void:
	create_renderers()
	create_overlay()
	update_overlay_transform()

func create_renderers() -> void:
	ctx.floor_renderer = FloorRenderer.new()
	ctx.floor_renderer.name = "FloorRenderer"
	ctx.floor_renderer.z_index = -2
	ctx.host.add_child(ctx.floor_renderer)

	ctx.wall_renderer = WallRenderer.new()
	ctx.wall_renderer.name = "WallRenderer"
	ctx.wall_renderer.z_index = 0
	ctx.host.add_child(ctx.wall_renderer)

	ctx.iso_wall_renderer = IsoWallRenderer.new()
	ctx.iso_wall_renderer.name = "IsoWallRenderer"
	ctx.iso_wall_renderer.z_index = 1
	configure_iso_renderer(ctx.iso_wall_renderer)
	ctx.host.add_child(ctx.iso_wall_renderer)

	ctx.ghost_renderer = WallRenderer.new()
	ctx.ghost_renderer.name = "GhostWallRenderer"
	ctx.ghost_renderer.z_index = 10
	ctx.host.add_child(ctx.ghost_renderer)

	ctx.iso_ghost_renderer = IsoWallRenderer.new()
	ctx.iso_ghost_renderer.name = "IsoGhostWallRenderer"
	ctx.iso_ghost_renderer.z_index = 11
	configure_iso_renderer(ctx.iso_ghost_renderer)
	ctx.host.add_child(ctx.iso_ghost_renderer)

	ctx.ghost_segment = WallSegment.new()
	ctx.ghost_segment.color = Color(ctx.pending_color, ctx.ghost_alpha)
	ctx.ghost_segment.thickness = ctx.pending_thickness
	ctx.ghost_segment.line_width = ctx.pending_line_width
	ctx.ghost_segment.start_cap_style = ctx.pending_start_cap
	ctx.ghost_segment.end_cap_style = ctx.pending_end_cap

	ctx.wall_renderer.modulate.a = 0.0 if ctx.isometric_mode else 1.0
	ctx.iso_wall_renderer.modulate.a = 1.0 if ctx.isometric_mode else 0.0
	ctx.floor_renderer.set_view(ctx.isometric_mode, ctx.iso_wall_renderer)
	ctx.ghost_renderer.modulate.a = 0.0 if ctx.isometric_mode else 1.0
	ctx.iso_ghost_renderer.modulate.a = 1.0 if ctx.isometric_mode else 0.0

func configure_iso_renderer(renderer: IsoWallRenderer) -> void:
	renderer.wall_height = ctx.iso_wall_height
	renderer.texture_tile_size = ctx.debug_texture_tile_size
	renderer.projection_angle = ctx.iso_projection_angle
	renderer.view_quadrant = ctx.iso_view_quadrant
	renderer.view_mode = ctx.iso_view_mode

func create_overlay() -> void:
	ctx.overlay = Node2D.new()
	ctx.overlay.name = "Overlay"
	ctx.overlay.z_index = 20
	ctx.overlay.draw.connect(draw_overlay)
	ctx.host.add_child(ctx.overlay)

func update_overlay_transform() -> void:
	if ctx.overlay == null:
		return
	if not ctx.isometric_mode or ctx.iso_wall_renderer == null:
		ctx.overlay.transform = Transform2D.IDENTITY
		ctx.overlay.queue_redraw()
		return
	var origin := ctx.iso_wall_renderer.project_point(Vector2.ZERO, 0.0)
	var x_axis := ctx.iso_wall_renderer.project_point(Vector2.RIGHT, 0.0) - origin
	var y_axis := ctx.iso_wall_renderer.project_point(Vector2.DOWN, 0.0) - origin
	ctx.overlay.transform = Transform2D(x_axis, y_axis, origin)
	ctx.overlay.queue_redraw()

func rebuild_walls() -> void:
	if ctx.room_data == null:
		return

	if ctx.floor_renderer != null:
		ctx.floor_renderer.set_room(ctx.room_data)
		ctx.floor_renderer.set_view(ctx.isometric_mode, ctx.iso_wall_renderer)

	if ctx.wall_renderer != null:
		ctx.wall_renderer.set_room(ctx.room_data)

	if ctx.iso_wall_renderer != null:
		configure_iso_renderer(ctx.iso_wall_renderer)
		ctx.iso_wall_renderer.set_room(ctx.room_data)

	ctx.overlay.queue_redraw()

func update_ghost() -> void:
	if ctx.ghost_renderer == null or ctx.iso_ghost_renderer == null:
		return

	if ctx.state != RoomBuilderTypes.State.PLACING_END and ctx.state != RoomBuilderTypes.State.END_PROMPT and ctx.state != RoomBuilderTypes.State.SNAP_PROMPT and ctx.state != RoomBuilderTypes.State.REBUILD_PLACING:
		clear_ghost()
		ctx.overlay.queue_redraw()
		return

	ctx.ghost_segment.start_point = ctx.start_point
	ctx.ghost_segment.end_point = ctx.end_point
	ctx.ghost_segment.color = Color(ctx.pending_color, ctx.ghost_alpha)
	ctx.ghost_segment.thickness = maxf(ctx.pending_thickness, 1.0)
	ctx.ghost_segment.line_width = maxf(ctx.pending_line_width, 1.0)
	ctx.ghost_segment.start_cap_style = ctx.pending_start_cap
	ctx.ghost_segment.end_cap_style = ctx.pending_end_cap
	var ghost_segments: Array[WallSegment] = [ctx.ghost_segment]

	ctx.ghost_renderer.set_segments(ghost_segments)
	ctx.iso_ghost_renderer.texture_tile_size = ctx.debug_texture_tile_size
	ctx.iso_ghost_renderer.view_mode = ctx.iso_view_mode
	ctx.iso_ghost_renderer.set_segments(ghost_segments)
	ctx.overlay.queue_redraw()

func draw_overlay() -> void:
	if ctx.hovered_segment != null:
		var hover_start := ctx.hovered_segment.start_point
		var hover_end := ctx.hovered_segment.end_point
		ctx.overlay.draw_line(
			hover_start,
			hover_end,
			Color(0.2, 0.9, 1.0, 0.75),
			2.5,
			true)

		var hover_mid := (hover_start + hover_end) * 0.5
		var hover_dir := hover_end - hover_start
		if hover_dir.length_squared() > 0.0001:
			var hover_normal := Vector2(-hover_dir.y, hover_dir.x).normalized()
			var hover_label_pos := hover_mid + hover_normal * (maxf(ctx.hovered_segment.thickness * 0.5, 8.0) + 14.0)

			var segment_length := hover_start.distance_to(hover_end)
			var hover_text := "Segment: %.1f px × %.1f px" % [
				segment_length,
				ctx.hovered_segment.thickness
			]
			ctx.overlay.draw_string(
				ThemeDB.fallback_font,
				hover_label_pos,
				hover_text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				13,
				Color(0.2, 0.9, 1.0, 1.0))

	if ctx.selected_floor != null:
		var floor_points := ctx.selected_floor.polygon
		if floor_points.size() >= 3:
			var selected_floor_outline: PackedVector2Array = floor_points.duplicate()
			selected_floor_outline.append(selected_floor_outline[0])
			ctx.overlay.draw_polyline(selected_floor_outline, Color(1.0, 0.85, 0.15, 0.9), 2.0, true)
			ctx.overlay.draw_circle(ctx.selected_floor_point, 5.0, Color(1.0, 0.85, 0.15, 0.9))

	if ctx.selected_segment != null:
		var start := ctx.selected_segment.start_point
		var end := ctx.selected_segment.end_point
		ctx.overlay.draw_line(start, end, Color(1.0, 0.85, 0.15, 0.9), 1.5, true)
		ctx.overlay.draw_circle(start, 5.0, Color(0.25, 1.0, 0.4, 0.9))
		ctx.overlay.draw_circle(end, 5.0, Color(1.0, 0.35, 0.25, 0.9))

	# Always show the snapped mouse cell/coordinate.
	if ctx.has_mouse_preview:
		var cell: Vector2i = ctx.input.get_grid_cell(ctx.mouse_preview_point)
		if ctx.snap_size > 0.0:
			var half_snap := ctx.snap_size * 0.5
			var cell_origin := Vector2(cell.x * ctx.snap_size, cell.y * ctx.snap_size)
			ctx.overlay.draw_rect(
				Rect2(
					cell_origin - Vector2(half_snap, half_snap),
					Vector2(ctx.snap_size, ctx.snap_size)),
				Color(1.0, 1.0, 1.0, 0.10),
				false,
				1.0)

		var cell_label_pos := ctx.mouse_preview_point + Vector2(10.0, 18.0)
		var cell_text := "Cell: (%d, %d)" % [cell.x, cell.y]
		ctx.overlay.draw_string(
			ThemeDB.fallback_font,
			cell_label_pos,
			cell_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			13,
			Color.WHITE)

	if ctx.state == RoomBuilderTypes.State.START_PROMPT:
		var radius := maxf(ctx.pending_thickness * 0.5, 2.0)
		ctx.overlay.draw_circle(ctx.start_point, radius, Color(ctx.pending_color, ctx.ghost_alpha))
		ctx.overlay.draw_arc(ctx.start_point, radius + 2.0, 0.0, TAU, 32, Color.WHITE, 1.0)

	if ctx.state == RoomBuilderTypes.State.PLACING_END or ctx.state == RoomBuilderTypes.State.END_PROMPT or ctx.state == RoomBuilderTypes.State.SNAP_PROMPT or ctx.state == RoomBuilderTypes.State.REBUILD_PLACING:
		ctx.overlay.draw_circle(ctx.start_point, 4.0, Color(0.25, 1.0, 0.4, 1.0))
		ctx.overlay.draw_circle(ctx.end_point, 4.0, Color(1.0, 0.35, 0.25, 1.0))

		var label_pos := (ctx.start_point + ctx.end_point) * 0.5 + Vector2(8.0, -8.0)
		var length_text := "Length: %d px" % int(ctx.start_point.distance_to(ctx.end_point))
		ctx.overlay.draw_string(
			ThemeDB.fallback_font,
			label_pos,
			length_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			14,
			Color.WHITE)

		# Angle preview: a live arc at the fixed endpoint plus the signed angle.
		var preview_delta := ctx.end_point - ctx.start_point
		if preview_delta.length_squared() > 0.0001:
			var angle_rad := preview_delta.angle()
			var angle_deg := rad_to_deg(angle_rad)
			var angle_radius := maxf(ctx.pending_thickness * 0.5 + 10.0, 24.0)

			ctx.overlay.draw_arc(
				ctx.start_point,
				angle_radius,
				0.0,
				angle_rad,
				32,
				Color(1.0, 0.65, 0.2, 0.95),
				1.5,
				true)

			var angle_mid := angle_rad * 0.5
			var angle_label_pos := ctx.start_point + Vector2(cos(angle_mid), sin(angle_mid)) * (angle_radius + 8.0)
			ctx.overlay.draw_string(
				ThemeDB.fallback_font,
				angle_label_pos,
				"Angle: %+.1f°" % angle_deg,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				13,
				Color(1.0, 0.65, 0.2, 1.0))

	if ctx.floor_ops != null and (ctx.state == RoomBuilderTypes.State.FLOOR_PLACING or ctx.state == RoomBuilderTypes.State.FLOOR_CONFIRM):
		ctx.floor_ops.draw_preview()

	if ctx.has_snap_target and (ctx.state == RoomBuilderTypes.State.PLACING_END or ctx.state == RoomBuilderTypes.State.REBUILD_PLACING):
		ctx.overlay.draw_circle(ctx.snap_point, 8.0, Color(0.2, 0.9, 1.0, 0.85), false, 2.0, true)
		var snap_label := "SNAP" if not ctx.snap_hits_body else "SNAP + BRANCH"
		ctx.overlay.draw_string(
			ThemeDB.fallback_font,
			ctx.snap_point + Vector2(10.0, -10.0),
			snap_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			Color(0.2, 0.9, 1.0, 1.0))

# ---------------------------------------------------------------- Input

func switch_renderer(use_iso: bool) -> void:
	if ctx.wall_renderer == null or ctx.iso_wall_renderer == null:
		return

	if ctx.isometric_mode == use_iso:
		return

	ctx.isometric_mode = use_iso
	if ctx.floor_renderer != null:
		ctx.floor_renderer.set_view(use_iso, ctx.iso_wall_renderer)

	update_overlay_transform()

	configure_iso_renderer(ctx.iso_wall_renderer)
	ctx.iso_wall_renderer.set_room(ctx.room_data)
	ctx.wall_renderer.set_room(ctx.room_data)

	if ctx.renderer_tween != null and ctx.renderer_tween.is_valid():
		ctx.renderer_tween.kill()

	ctx.renderer_tween = ctx.host.create_tween() \
		.set_parallel(true) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)

	ctx.renderer_tween.tween_property(
		ctx.wall_renderer,
		"modulate:a",
		0.0 if use_iso else 1.0,
		ctx.renderer_switch_duration
	)

	ctx.renderer_tween.tween_property(
		ctx.iso_wall_renderer,
		"modulate:a",
		1.0 if use_iso else 0.0,
		ctx.renderer_switch_duration
	)

	ctx.renderer_tween.tween_property(
		ctx.ghost_renderer,
		"modulate:a",
		0.0 if use_iso else 1.0,
		ctx.renderer_switch_duration
	)

	ctx.renderer_tween.tween_property(
		ctx.iso_ghost_renderer,
		"modulate:a",
		1.0 if use_iso else 0.0,
		ctx.renderer_switch_duration
	)

	# Redraw the construction grid using the new projection.
	if ctx.grid_renderer != null:
		ctx.grid_renderer.queue_redraw()

	ctx.overlay.queue_redraw()

	ctx.ui_module.set_status(
		"Switched to %s."
		% ("Iso Wall Render" if use_iso else "Wall Render")
	)

func set_iso_view_mode(mode: IsoWallRenderer.ViewMode) -> void:
	if not ctx.isometric_mode:
		switch_renderer(true)
	ctx.iso_view_mode = mode
	if ctx.iso_wall_renderer != null:
		ctx.iso_wall_renderer.set_view_mode(mode)
	if ctx.iso_ghost_renderer != null:
		ctx.iso_ghost_renderer.set_view_mode(mode)
	ctx.overlay.queue_redraw()

	match mode:
		IsoWallRenderer.ViewMode.ISO1_NO_WALLS:
			ctx.ui_module.set_status("Iso1 active: no walls rendered.")
		IsoWallRenderer.ViewMode.ISO2_BACK_WALLS:
			ctx.ui_module.set_status("Iso2 active: only the farther/back half of the walls is rendered.")
		IsoWallRenderer.ViewMode.ISO3_ALL_WALLS:
			ctx.ui_module.set_status("Iso3 active: all walls rendered.")

func clear_ghost() -> void:
	var empty_segments: Array[WallSegment] = []
	if ctx.ghost_renderer != null:
		ctx.ghost_renderer.set_segments(empty_segments)
	if ctx.iso_ghost_renderer != null:
		ctx.iso_ghost_renderer.set_segments(empty_segments)


# ---------------------------------------------------------------- Utility
