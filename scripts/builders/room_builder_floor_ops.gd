class_name RoomBuilderFloorOps
extends RefCounted

## Floor creation, enclosure detection, floor selection, and floor appearance state.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func begin_manual_floor() -> void:
	if ctx.room_data == null:
		return
	ctx.selected_floor = null
	ctx.floor_polygon = PackedVector2Array()
	ctx.auto_floor_polygon = PackedVector2Array()
	ctx.state = RoomBuilderTypes.State.FLOOR_PLACING
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status("Floor mode: left click corner-to-corner. Click the first corner to close the polygon. Press Esc to cancel.")

func handle_floor_click(point: Vector2) -> void:
	if ctx.state != RoomBuilderTypes.State.FLOOR_PLACING:
		return

	if ctx.floor_polygon.size() >= 3:
		var close_radius := maxf(ctx.snap_size * 1.5, 6.0)
		if point.distance_to(ctx.floor_polygon[0]) <= close_radius:
			open_manual_floor_confirmation()
			return

	if not ctx.floor_polygon.is_empty():
		var previous := ctx.floor_polygon[ctx.floor_polygon.size() - 1]
		if point.distance_to(previous) <= RoomData.JOIN_EPSILON:
			return

	ctx.floor_polygon.append(point)
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status("Floor polygon: %d corner(s). Click the first corner to close." % ctx.floor_polygon.size())

func open_manual_floor_confirmation() -> void:
	var cleaned := ctx.room_data.sanitize_floor_polygon(ctx.floor_polygon)
	if cleaned.size() < 3 or absf(ctx.room_data.get_polygon_area(cleaned)) <= 0.5:
		ctx.ui_module.set_status("Floor needs at least three non-collinear corners.")
		return

	ctx.floor_polygon = cleaned
	ctx.state = RoomBuilderTypes.State.FLOOR_CONFIRM
	ctx.ui_module.show_floor_confirm(ctx.floor_polygon)
	ctx.overlay.queue_redraw()

func on_manual_floor_confirmed() -> void:
	if ctx.state != RoomBuilderTypes.State.FLOOR_CONFIRM:
		return
	var floor := ctx.room_data.add_floor_space(
		ctx.floor_polygon,
		ctx.default_floor_color,
		null)
	if floor == null:
		ctx.ui_module.set_status("That floor polygon already exists or is invalid.")
		cancel_floor()
		return

	ctx.floor_polygon = PackedVector2Array()
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.rendering.rebuild_walls()
	ctx.ui_module.set_status("Floor created.")
	ctx.overlay.queue_redraw()

func on_manual_floor_canceled() -> void:
	if ctx.state == RoomBuilderTypes.State.FLOOR_CONFIRM:
		ctx.state = RoomBuilderTypes.State.FLOOR_PLACING
		ctx.ui_module.set_status("Floor polygon still active. Continue clicking corners, or press Esc to cancel.")
		ctx.overlay.queue_redraw()

func cancel_floor(message: String = "Floor operation cancelled.") -> void:
	ctx.floor_polygon = PackedVector2Array()
	ctx.auto_floor_polygon = PackedVector2Array()
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status(message)

func draw_preview() -> void:
	if ctx.overlay == null or ctx.floor_polygon.is_empty():
		return

	for i in ctx.floor_polygon.size():
		var point := ctx.floor_polygon[i]
		ctx.overlay.draw_circle(point, 4.5, Color(0.25, 1.0, 0.8, 0.95))
		if i > 0:
			ctx.overlay.draw_line(
				ctx.floor_polygon[i - 1],
				point,
				Color(0.25, 1.0, 0.8, 0.8),
				2.0,
				true)

	if ctx.floor_polygon.size() >= 2:
		ctx.overlay.draw_line(
				ctx.floor_polygon[ctx.floor_polygon.size() - 1],
				ctx.floor_polygon[0],
				Color(0.25, 1.0, 0.8, 0.35),
				1.0,
				true)

func prompt_for_new_enclosures() -> void:
	if ctx.room_data == null:
		return
	if ctx.state != RoomBuilderTypes.State.IDLE:
		return

	var candidates := ctx.room_data.find_enclosed_polygons()
	for polygon in candidates:
		if ctx.room_data.has_floor_for_polygon(polygon):
			continue
		var signature := ctx.room_data.polygon_signature(polygon)
		if signature.is_empty() or ctx.suppressed_auto_floor_signatures.has(signature):
			continue

		ctx.auto_floor_polygon = polygon
		ctx.auto_floor_signature = signature
		ctx.state = RoomBuilderTypes.State.AUTO_FLOOR_PROMPT
		ctx.ui_module.show_auto_floor_prompt(polygon)
		ctx.overlay.queue_redraw()
		return

func on_auto_floor_confirmed() -> void:
	if ctx.state != RoomBuilderTypes.State.AUTO_FLOOR_PROMPT:
		return

	var polygon := ctx.auto_floor_polygon
	var floor := ctx.room_data.add_floor_space(polygon, ctx.default_floor_color, null)
	ctx.auto_floor_polygon = PackedVector2Array()
	ctx.auto_floor_signature = ""
	ctx.state = RoomBuilderTypes.State.IDLE
	if floor == null:
		ctx.ui_module.set_status("The enclosed section was already covered or could not become a floor.")
	else:
		ctx.ui_module.set_status("Enclosed space automatically floored.")
	ctx.overlay.queue_redraw()
	prompt_for_new_enclosures()

func on_auto_floor_canceled() -> void:
	if ctx.state != RoomBuilderTypes.State.AUTO_FLOOR_PROMPT:
		return
	if not ctx.auto_floor_signature.is_empty():
		ctx.suppressed_auto_floor_signatures[ctx.auto_floor_signature] = true
	ctx.auto_floor_polygon = PackedVector2Array()
	ctx.auto_floor_signature = ""
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status("Enclosed space left empty. You can build a floor manually from the RoomBuilder context menu.")
	prompt_for_new_enclosures()

func select_floor(hit: Dictionary) -> void:
	var floor_value: Variant = hit.get("floor", null)
	if not floor_value is FloorSpace:
		return
	ctx.selected_floor = floor_value
	ctx.selected_floor_point = Vector2(hit.get("point", floor_value.get_centroid()))
	ctx.selected_segment = null
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status("Floor selected. Choose an edit operation from the floor menu.")

func clear_selection() -> void:
	ctx.selected_floor = null
	ctx.selected_floor_point = Vector2.ZERO
	ctx.overlay.queue_redraw()

func open_appearance_prompt() -> void:
	if ctx.selected_floor == null:
		return
	ctx.floor_appearance_snapshot = {
		"color": ctx.selected_floor.color,
		"texture": ctx.selected_floor.texture,
		"texture_tile_size": ctx.selected_floor.texture_tile_size,
	}
	ctx.state = RoomBuilderTypes.State.FLOOR_EDIT_PROMPT
	ctx.ui_module.show_floor_appearance(ctx.selected_floor)

func on_floor_color_changed(color: Color) -> void:
	if ctx.selected_floor == null:
		return
	ctx.selected_floor.color = color
	ctx.rendering.rebuild_walls()

func on_floor_texture_selected(_index: int) -> void:
	if ctx.selected_floor == null:
		return
	ctx.selected_floor.texture = ctx.ui_module.load_selected_floor_texture()
	ctx.rendering.rebuild_walls()

func on_floor_appearance_confirmed() -> void:
	if ctx.selected_floor == null:
		ctx.state = RoomBuilderTypes.State.IDLE
		return
	ctx.selected_floor.texture_tile_size = maxf(ctx.ui_module.get_floor_texture_tile_size(), 1.0)
	ctx.room_data.emit_changed()
	ctx.floor_appearance_snapshot.clear()
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.rendering.rebuild_walls()
	ctx.persistence.save_current_room_data()
	ctx.ui_module.set_status("Floor appearance updated and room data saved.")

func on_floor_appearance_canceled() -> void:
	if ctx.selected_floor != null and not ctx.floor_appearance_snapshot.is_empty():
		ctx.selected_floor.color = ctx.floor_appearance_snapshot["color"]
		ctx.selected_floor.texture = ctx.floor_appearance_snapshot["texture"]
		ctx.selected_floor.texture_tile_size = ctx.floor_appearance_snapshot["texture_tile_size"]
	ctx.floor_appearance_snapshot.clear()
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.rendering.rebuild_walls()
	ctx.ui_module.set_status("Floor appearance edit cancelled.")

func delete_selected_floor() -> void:
	if ctx.selected_floor == null:
		return
	ctx.room_data.remove_floor_space(ctx.selected_floor)
	ctx.selected_floor = null
	ctx.selected_floor_point = Vector2.ZERO
	ctx.rendering.rebuild_walls()
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status("Floor deleted.")
