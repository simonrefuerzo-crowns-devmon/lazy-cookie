class_name RoomBuilderEditing
extends RefCounted

## Endpoint style, repaint, deletion, and edit prompt state.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func open_style_prompt() -> void:
	if ctx.selected_segment == null:
		return

	ctx.state = RoomBuilderTypes.State.STYLE_PROMPT
	ctx.style_end_button.select(0)
	ctx.style_cap_button.select(ctx.selected_segment.get_cap(0))
	ctx.style_dialog.dialog_text = "Choose which endpoint to change and its render style.\nConnected endpoints will be joined by WallRenderer while the saved style is retained."
	ctx.style_dialog.popup_centered(Vector2i(420, 190))

func on_style_confirmed() -> void:
	if ctx.selected_segment == null:
		return

	var end_id := ctx.style_end_button.get_selected_id()
	var style_id := ctx.style_cap_button.get_selected_id()
	if end_id != 0 and end_id != 1:
		return
	if style_id < WallSegment.CapStyle.FLAT or style_id > WallSegment.CapStyle.POINT_CONCAVE:
		return

	ctx.selected_segment.set_cap(end_id, style_id)
	ctx.room_data.emit_changed()
	ctx.rendering.rebuild_walls()
	ctx.ui_module.set_status("Endpoint render updated and connected wall geometry regenerated.")


# ---------------------------------------------------------------- Repainting

func open_repaint_prompt() -> void:
	if ctx.selected_segment == null:
		return
	ctx.state = RoomBuilderTypes.State.REPAINT_PROMPT
	ctx.repaint_color_button.color = ctx.selected_segment.color
	ctx.repaint_dialog.dialog_text = "Choose the wall color. Both parallel wall lines use this color."
	ctx.repaint_dialog.popup_centered(Vector2i(380, 150))

func on_repaint_confirmed() -> void:
	if ctx.selected_segment == null:
		return
	ctx.selected_segment.color = ctx.repaint_color_button.color
	ctx.room_data.emit_changed()
	ctx.rendering.rebuild_walls()
	ctx.ui_module.set_status("Wall repainted.")


# ---------------------------------------------------------------- Iso wall texture editing

func delete_selected_wall() -> void:
	if ctx.selected_segment == null:
		return
	ctx.state = RoomBuilderTypes.State.DELETE_PROMPT
	ctx.delete_dialog.dialog_text = "Delete the selected wall?\nThis cannot be undone from the room builder."
	ctx.delete_dialog.popup_centered(Vector2i(360, 140))

func on_delete_confirmed() -> void:
	if ctx.selected_segment == null:
		return
	var deleted := ctx.selected_segment
	ctx.room_data.remove_wall_segment(deleted)
	ctx.selected_segment = null
	ctx.selected_point = Vector2.ZERO
	ctx.rendering.rebuild_walls()
	ctx.overlay.queue_redraw()
	ctx.ui_module.set_status("Wall deleted.")


# ---------------------------------------------------------------- General context / saving

func on_style_canceled() -> void:
	cancel_edit_prompt("Endpoint style change cancelled.")

func on_repaint_canceled() -> void:
	cancel_edit_prompt("Repaint cancelled.")

func on_delete_canceled() -> void:
	cancel_edit_prompt("Delete cancelled.")

func cancel_edit_prompt(message: String) -> void:
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.ui_module.set_status(message)

