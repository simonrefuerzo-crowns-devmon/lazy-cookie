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

	ctx.iso_back_wall_renderer = IsoWallRenderer.new()
	ctx.iso_back_wall_renderer.name = "IsoBackWallRenderer"
	ctx.iso_back_wall_renderer.z_index = 2
	configure_iso_secondary_renderer(ctx.iso_back_wall_renderer)
	ctx.host.add_child(ctx.iso_back_wall_renderer)

	ctx.iso_front_wall_renderer = IsoWallRenderer.new()
	ctx.iso_front_wall_renderer.name = "IsoFrontCutWallRenderer"
	ctx.iso_front_wall_renderer.z_index = 3
	configure_iso_secondary_renderer(ctx.iso_front_wall_renderer)
	ctx.host.add_child(ctx.iso_front_wall_renderer)

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
	ctx.iso_back_wall_renderer.modulate.a = 0.0
	ctx.iso_front_wall_renderer.modulate.a = 0.0
	ctx.floor_renderer.set_view(ctx.isometric_mode, ctx.iso_wall_renderer)
	ctx.ghost_renderer.modulate.a = 0.0 if ctx.isometric_mode else 1.0
	ctx.iso_ghost_renderer.modulate.a = 1.0 if ctx.isometric_mode else 0.0
	_set_iso_layer_projection(ctx.iso_wall_renderer, ctx.iso_view_quadrant)
	_set_iso_layer_projection(ctx.iso_back_wall_renderer, ctx.iso_view_quadrant)
	_set_iso_layer_projection(ctx.iso_front_wall_renderer, ctx.iso_view_quadrant)

func configure_iso_renderer(renderer: IsoWallRenderer) -> void:
	renderer.wall_height = ctx.iso_wall_height
	renderer.texture_tile_size = ctx.debug_texture_tile_size
	renderer.projection_angle = ctx.iso_projection_angle
	renderer.view_quadrant = ctx.iso_view_quadrant
	renderer.view_mode = IsoWallRenderer.ViewMode.ISO3_ALL_WALLS


func configure_iso_secondary_renderer(renderer: IsoWallRenderer) -> void:
	renderer.wall_height = ctx.iso_wall_height
	renderer.texture_tile_size = ctx.debug_texture_tile_size
	renderer.projection_angle = ctx.iso_projection_angle
	renderer.view_quadrant = ctx.iso_view_quadrant
	renderer.view_mode = IsoWallRenderer.ViewMode.ISO3_ALL_WALLS


func _set_iso_layer_projection(renderer: IsoWallRenderer, quadrant: int) -> void:
	if renderer == null:
		return
	renderer.texture_tile_size = ctx.debug_texture_tile_size
	renderer.projection_angle = ctx.iso_projection_angle
	renderer.view_quadrant = posmod(quadrant, 4)
	renderer.view_mode = IsoWallRenderer.ViewMode.ISO3_ALL_WALLS


func _get_front_direction(quadrant: int) -> Vector2:
	match posmod(quadrant, 4):
		1:
			return Vector2(1.0, -1.0).normalized()
		2:
			return Vector2(-1.0, -1.0).normalized()
		3:
			return Vector2(-1.0, 1.0).normalized()
		_:
			return Vector2(1.0, 1.0).normalized()


func _get_wall_partition_center(segments: Array[WallSegment]) -> Vector2:
	if segments.is_empty():
		return Vector2.ZERO

	var total := Vector2.ZERO
	for segment in segments:
		total += (segment.start_point + segment.end_point) * 0.5
	return total / float(segments.size())


func _split_walls_for_quadrant(quadrant: int) -> Array:
	var front: Array[WallSegment] = []
	var back: Array[WallSegment] = []
	if ctx.room_data == null:
		return [front, back]

	var segments: Array[WallSegment] = ctx.room_data.wall_segments
	var center := _get_wall_partition_center(segments)
	var front_direction := _get_front_direction(quadrant)

	for segment in segments:
		var midpoint := (segment.start_point + segment.end_point) * 0.5
		var is_front := (midpoint - center).dot(front_direction) >= 0.0
		if is_front:
			front.append(segment)
		else:
			back.append(segment)

	return [front, back]


func _refresh_iso_segments() -> void:
	if ctx.room_data == null:
		return

	var segments: Array[WallSegment] = ctx.room_data.wall_segments
	var split: Array = _split_walls_for_quadrant(ctx.iso_view_quadrant)
	var front: Array[WallSegment] = split[0]
	var back: Array[WallSegment] = split[1]

	ctx.iso_wall_renderer.set_segments(segments)
	ctx.iso_back_wall_renderer.set_segments(back)
	ctx.iso_front_wall_renderer.set_segments(front)

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

	_cancel_quadrant_transition()

	if ctx.floor_renderer != null:
		ctx.floor_renderer.set_room(ctx.room_data)
		ctx.floor_renderer.set_view(ctx.isometric_mode, ctx.iso_wall_renderer)

	if ctx.wall_renderer != null:
		ctx.wall_renderer.set_room(ctx.room_data)

	if ctx.iso_wall_renderer != null:
		_set_iso_layer_projection(ctx.iso_wall_renderer, ctx.iso_view_quadrant)
		_refresh_iso_segments()

	if ctx.iso_back_wall_renderer != null:
		_set_iso_layer_projection(ctx.iso_back_wall_renderer, ctx.iso_view_quadrant)

	if ctx.iso_front_wall_renderer != null:
		_set_iso_layer_projection(ctx.iso_front_wall_renderer, ctx.iso_view_quadrant)

	if ctx.isometric_mode:
		_apply_iso_mode_targets(false)

	if ctx.overlay != null:
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
	ctx.iso_ghost_renderer.view_mode = IsoWallRenderer.ViewMode.ISO3_ALL_WALLS
	ctx.iso_ghost_renderer.wall_height = ctx.iso_wall_height

	match ctx.iso_view_mode:
		IsoWallRenderer.ViewMode.ISO1_NO_WALLS:
			ctx.iso_ghost_renderer.wall_height = ctx.iso_wall_cut_height
		IsoWallRenderer.ViewMode.ISO2_BACK_WALLS:
			var center := _get_wall_partition_center(ctx.room_data.wall_segments)
			var front_direction := _get_front_direction(ctx.iso_view_quadrant)
			var ghost_midpoint := (ctx.ghost_segment.start_point + ctx.ghost_segment.end_point) * 0.5
			if (ghost_midpoint - center).dot(front_direction) >= 0.0:
				ctx.iso_ghost_renderer.wall_height = ctx.iso_wall_cut_height

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

func _cancel_quadrant_transition() -> void:
	if ctx.iso_quadrant_tween != null and ctx.iso_quadrant_tween.is_valid():
		ctx.iso_quadrant_tween.kill()

	for renderer in ctx.iso_quadrant_transition_renderers:
		if is_instance_valid(renderer):
			renderer.queue_free()

	ctx.iso_quadrant_transition_renderers.clear()


func switch_renderer(use_iso: bool) -> void:
	if ctx.wall_renderer == null or ctx.iso_wall_renderer == null:
		return

	_cancel_quadrant_transition()

	if ctx.isometric_mode == use_iso:
		return

	ctx.isometric_mode = use_iso
	if ctx.floor_renderer != null:
		ctx.floor_renderer.set_view(use_iso, ctx.iso_wall_renderer)

	update_overlay_transform()

	if ctx.renderer_tween != null and ctx.renderer_tween.is_valid():
		ctx.renderer_tween.kill()

	if use_iso:
		ctx.iso_wall_renderer.modulate.a = 0.0
		ctx.iso_back_wall_renderer.modulate.a = 0.0
		ctx.iso_front_wall_renderer.modulate.a = 0.0

	ctx.renderer_tween = ctx.host.create_tween()
	ctx.renderer_tween.set_parallel(true)
	ctx.renderer_tween.set_trans(Tween.TRANS_SINE)
	ctx.renderer_tween.set_ease(Tween.EASE_IN_OUT)

	var duration := maxf(ctx.renderer_switch_duration, 0.001)

	ctx.renderer_tween.tween_property(
		ctx.wall_renderer,
		"modulate:a",
		0.0 if use_iso else 1.0,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.ghost_renderer,
		"modulate:a",
		0.0 if use_iso else 1.0,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_wall_renderer,
		"modulate:a",
		1.0 if use_iso and ctx.iso_view_mode != IsoWallRenderer.ViewMode.ISO2_BACK_WALLS else 0.0,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_back_wall_renderer,
		"modulate:a",
		1.0 if use_iso and ctx.iso_view_mode == IsoWallRenderer.ViewMode.ISO2_BACK_WALLS else 0.0,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_front_wall_renderer,
		"modulate:a",
		1.0 if use_iso and ctx.iso_view_mode == IsoWallRenderer.ViewMode.ISO2_BACK_WALLS else 0.0,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_ghost_renderer,
		"modulate:a",
		1.0 if use_iso else 0.0,
		duration
	)

	if ctx.grid_renderer != null:
		ctx.grid_renderer.queue_redraw()
	if ctx.overlay != null:
		ctx.overlay.queue_redraw()

	ctx.ui_module.set_status(
		"Switched to %s."
		% ("Iso Wall Render" if use_iso else "Wall Render")
	)

func _apply_iso_mode_targets(animate: bool = true) -> void:
	var duration := maxf(ctx.iso_view_transition_duration, 0.001)
	var target_all_alpha := 0.0
	var target_back_alpha := 0.0
	var target_front_alpha := 0.0
	var target_all_height := ctx.iso_wall_height

	match ctx.iso_view_mode:
		IsoWallRenderer.ViewMode.ISO1_NO_WALLS:
			target_all_alpha = 1.0
			target_all_height = ctx.iso_wall_cut_height
		IsoWallRenderer.ViewMode.ISO2_BACK_WALLS:
			target_back_alpha = 1.0
			target_front_alpha = 1.0
		IsoWallRenderer.ViewMode.ISO3_ALL_WALLS:
			target_all_alpha = 1.0
			target_all_height = ctx.iso_wall_height

	if not animate:
		ctx.iso_wall_renderer.modulate.a = target_all_alpha
		ctx.iso_back_wall_renderer.modulate.a = target_back_alpha
		ctx.iso_front_wall_renderer.modulate.a = target_front_alpha
		ctx.iso_wall_renderer.wall_height = target_all_height
		ctx.iso_back_wall_renderer.wall_height = ctx.iso_wall_height
		ctx.iso_front_wall_renderer.wall_height = ctx.iso_wall_cut_height
		return

	if ctx.renderer_tween != null and ctx.renderer_tween.is_valid():
		ctx.renderer_tween.kill()

	ctx.renderer_tween = ctx.host.create_tween()
	ctx.renderer_tween.set_parallel(true)
	ctx.renderer_tween.set_trans(Tween.TRANS_SINE)
	ctx.renderer_tween.set_ease(Tween.EASE_IN_OUT)

	ctx.renderer_tween.tween_property(
		ctx.iso_wall_renderer,
		"modulate:a",
		target_all_alpha,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_back_wall_renderer,
		"modulate:a",
		target_back_alpha,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_front_wall_renderer,
		"modulate:a",
		target_front_alpha,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_wall_renderer,
		"wall_height",
		target_all_height,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_back_wall_renderer,
		"wall_height",
		ctx.iso_wall_height,
		duration
	)
	ctx.renderer_tween.tween_property(
		ctx.iso_front_wall_renderer,
		"wall_height",
		ctx.iso_wall_cut_height,
		duration
	)


func set_iso_view_mode(mode: IsoWallRenderer.ViewMode) -> void:
	if not ctx.isometric_mode:
		switch_renderer(true)

	ctx.iso_view_mode = mode
	_refresh_iso_segments()
	_apply_iso_mode_targets(true)
	update_overlay_transform()

	match mode:
		IsoWallRenderer.ViewMode.ISO1_NO_WALLS:
			ctx.ui_module.set_status("Iso1 active: walls are cut to %.1f px." % ctx.iso_wall_cut_height)
		IsoWallRenderer.ViewMode.ISO2_BACK_WALLS:
			ctx.ui_module.set_status("Iso2 active: back 180° are full height; front 180° are cut to %.1f px." % ctx.iso_wall_cut_height)
		IsoWallRenderer.ViewMode.ISO3_ALL_WALLS:
			ctx.ui_module.set_status("Iso3 active: all walls rendered at full height.")

	if ctx.overlay != null:
		ctx.overlay.queue_redraw()


func _make_quadrant_transition_renderer(
	name: String,
	z_index: int,
	quadrant: int,
	wall_height: float,
	segments: Array[WallSegment],
	target_alpha: float
) -> IsoWallRenderer:
	var renderer := IsoWallRenderer.new()
	renderer.name = name
	renderer.z_index = z_index
	renderer.wall_height = wall_height
	renderer.texture_tile_size = ctx.debug_texture_tile_size
	renderer.projection_angle = ctx.iso_projection_angle
	renderer.view_quadrant = posmod(quadrant, 4)
	renderer.view_mode = IsoWallRenderer.ViewMode.ISO3_ALL_WALLS
	renderer.set_segments(segments)
	renderer.modulate.a = 0.0
	ctx.host.add_child(renderer)
	return renderer


func set_iso_view_quadrant(quadrant: int, animate: bool = true) -> void:
	var target_quadrant := posmod(quadrant, 4)
	if target_quadrant == ctx.iso_view_quadrant:
		_notify_camera_quadrant(target_quadrant, false)
		return

	var old_quadrant := ctx.iso_view_quadrant
	var duration := maxf(ctx.iso_quadrant_turn_duration, 0.001)

	if not animate:
		ctx.iso_view_quadrant = target_quadrant
		_set_iso_layer_projection(ctx.iso_wall_renderer, target_quadrant)
		_set_iso_layer_projection(ctx.iso_back_wall_renderer, target_quadrant)
		_set_iso_layer_projection(ctx.iso_front_wall_renderer, target_quadrant)
		_refresh_iso_segments()
		_notify_camera_quadrant(target_quadrant, false)
		update_overlay_transform()
		return

	_cancel_quadrant_transition()

	var split_target: Array = _split_walls_for_quadrant(target_quadrant)
	var target_front: Array[WallSegment] = split_target[0]
	var target_back: Array[WallSegment] = split_target[1]

	var target_all_alpha := ctx.iso_wall_renderer.modulate.a
	var target_back_alpha := ctx.iso_back_wall_renderer.modulate.a
	var target_front_alpha := ctx.iso_front_wall_renderer.modulate.a

	var transition_all := _make_quadrant_transition_renderer(
		"IsoQuadrantTransitionAll",
		4,
		target_quadrant,
		ctx.iso_wall_renderer.wall_height,
		ctx.room_data.wall_segments,
		target_all_alpha
	)
	var transition_back := _make_quadrant_transition_renderer(
		"IsoQuadrantTransitionBack",
		5,
		target_quadrant,
		ctx.iso_back_wall_renderer.wall_height,
		target_back,
		target_back_alpha
	)
	var transition_front := _make_quadrant_transition_renderer(
		"IsoQuadrantTransitionFront",
		6,
		target_quadrant,
		ctx.iso_front_wall_renderer.wall_height,
		target_front,
		target_front_alpha
	)

	ctx.iso_quadrant_transition_renderers = [transition_all, transition_back, transition_front]

	ctx.iso_quadrant_tween = ctx.host.create_tween()
	ctx.iso_quadrant_tween.set_parallel(true)
	ctx.iso_quadrant_tween.set_trans(Tween.TRANS_SINE)
	ctx.iso_quadrant_tween.set_ease(Tween.EASE_IN_OUT)

	ctx.iso_quadrant_tween.tween_property(ctx.iso_wall_renderer, "modulate:a", 0.0, duration)
	ctx.iso_quadrant_tween.tween_property(ctx.iso_back_wall_renderer, "modulate:a", 0.0, duration)
	ctx.iso_quadrant_tween.tween_property(ctx.iso_front_wall_renderer, "modulate:a", 0.0, duration)
	ctx.iso_quadrant_tween.tween_property(transition_all, "modulate:a", target_all_alpha, duration)
	ctx.iso_quadrant_tween.tween_property(transition_back, "modulate:a", target_back_alpha, duration)
	ctx.iso_quadrant_tween.tween_property(transition_front, "modulate:a", target_front_alpha, duration)

	var quadrant_finished: Callable = func() -> void:
		if is_instance_valid(ctx.iso_wall_renderer):
			ctx.iso_wall_renderer.modulate.a = target_all_alpha
			_set_iso_layer_projection(ctx.iso_wall_renderer, target_quadrant)
		if is_instance_valid(ctx.iso_back_wall_renderer):
			ctx.iso_back_wall_renderer.modulate.a = target_back_alpha
			_set_iso_layer_projection(ctx.iso_back_wall_renderer, target_quadrant)
		if is_instance_valid(ctx.iso_front_wall_renderer):
			ctx.iso_front_wall_renderer.modulate.a = target_front_alpha
			_set_iso_layer_projection(ctx.iso_front_wall_renderer, target_quadrant)

		ctx.iso_view_quadrant = target_quadrant
		_refresh_iso_segments()

		for renderer in ctx.iso_quadrant_transition_renderers:
			if is_instance_valid(renderer):
				renderer.queue_free()
		ctx.iso_quadrant_transition_renderers.clear()
		_notify_camera_quadrant(target_quadrant, false)
		update_overlay_transform()

	ctx.iso_quadrant_tween.finished.connect(quadrant_finished, CONNECT_ONE_SHOT)

	_notify_camera_quadrant(target_quadrant, true)
	ctx.ui_module.set_status("Turning Iso view from quadrant %d to quadrant %d." % [old_quadrant + 1, target_quadrant + 1])


func _notify_camera_quadrant(quadrant: int, animate: bool) -> void:
	if ctx.host == null:
		return

	var viewport := ctx.host.get_viewport()
	if viewport == null:
		return

	var camera := viewport.get_camera_2d()
	if camera != null and camera.has_method("set_iso_view_quadrant"):
		camera.call("set_iso_view_quadrant", quadrant, animate)

func clear_ghost() -> void:
	var empty_segments: Array[WallSegment] = []
	if ctx.ghost_renderer != null:
		ctx.ghost_renderer.set_segments(empty_segments)
	if ctx.iso_ghost_renderer != null:
		ctx.iso_ghost_renderer.set_segments(empty_segments)


# ---------------------------------------------------------------- Utility
