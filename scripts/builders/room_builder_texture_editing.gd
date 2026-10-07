class_name RoomBuilderTextureEditing
extends RefCounted

## Iso wall texture selection, preview, sampling, apply, and rollback.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func open_texture_prompt() -> void:
	if not ctx.DEBUG_MODE or not ctx.isometric_mode or ctx.selected_segment == null:
		ctx.ui_module.set_status("Switch to Iso Wall Render and select a wall to edit its texture.")
		return

	ctx.texture_snapshot = {
		"outside_texture": ctx.selected_segment.outside_texture,
		"inside_texture": ctx.selected_segment.inside_texture,
		"outside_filler_color": ctx.selected_segment.outside_filler_color,
		"inside_filler_color": ctx.selected_segment.inside_filler_color,
	}

	ctx.ui_module.select_texture_option(ctx.outside_texture_button, ctx.selected_segment.outside_texture)
	ctx.ui_module.select_texture_option(ctx.inside_texture_button, ctx.selected_segment.inside_texture)
	update_texture_preview(0)
	update_texture_preview(1)

	ctx.texture_dialog.popup_centered(Vector2i(660, 360))
	ctx.ui_module.set_status("Texture preview is live. Apply & Save commits it to RoomData.")

func load_selected_texture(button: OptionButton) -> Texture2D:
	if button == null or button.selected < 0:
		return null
	var metadata: Variant = button.get_item_metadata(button.selected)
	var path := String(metadata)
	if path.is_empty():
		return null
	return load(path) as Texture2D

func on_outside_texture_selected(_index: int) -> void:
	apply_texture_selection(0, ctx.outside_texture_button, ctx.edit_outside_check.button_pressed)

func on_inside_texture_selected(_index: int) -> void:
	apply_texture_selection(1, ctx.inside_texture_button, ctx.edit_inside_check.button_pressed)

func apply_texture_selection(side: int, button: OptionButton, enabled: bool) -> void:
	if ctx.selected_segment == null or not enabled:
		return

	var texture := load_selected_texture(button)
	var filler := sample_nearest_texture_color(texture, ctx.selected_segment.color)
	if side == 0:
		ctx.selected_segment.outside_texture = texture
		ctx.selected_segment.outside_filler_color = filler
	else:
		ctx.selected_segment.inside_texture = texture
		ctx.selected_segment.inside_filler_color = filler

	update_texture_preview(side)
	ctx.rendering.rebuild_walls()

func sample_nearest_texture_color(texture: Texture2D, target: Color) -> Color:
	if texture == null:
		return target

	var image := texture.get_image()
	if image == null or image.is_empty():
		return target

	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return target

	var sample_x := maxi(mini(width, 48), 1)
	var sample_y := maxi(mini(height, 48), 1)
	var best_color := image.get_pixel(0, 0)
	var best_distance := INF

	for y in range(sample_y):
		var py := int(roundf(float(y) * float(height - 1) / float(maxi(sample_y - 1, 1))))
		for x in range(sample_x):
			var px := int(roundf(float(x) * float(width - 1) / float(maxi(sample_x - 1, 1))))
			var candidate := image.get_pixel(px, py)
			if candidate.a <= 0.01:
				continue
			var distance := (candidate.r - target.r) * (candidate.r - target.r)
			distance += (candidate.g - target.g) * (candidate.g - target.g)
			distance += (candidate.b - target.b) * (candidate.b - target.b)
			if distance < best_distance:
				best_distance = distance
				best_color = candidate

	return Color(best_color.r, best_color.g, best_color.b, 1.0)

func update_texture_preview(side: int) -> void:
	if ctx.selected_segment == null:
		return
	var texture := ctx.selected_segment.get_texture_for_side(side)
	var filler := ctx.selected_segment.get_filler_for_side(side)
	if side == 0:
		ctx.outside_texture_preview.texture = texture
		ctx.outside_filler_preview.color = filler
	else:
		ctx.inside_texture_preview.texture = texture
		ctx.inside_filler_preview.color = filler

func on_texture_confirmed() -> void:
	if ctx.selected_segment == null:
		return

	# Restore any side that was not selected for editing.
	if not ctx.edit_outside_check.button_pressed and ctx.texture_snapshot.has("outside_texture"):
		ctx.selected_segment.outside_texture = ctx.texture_snapshot["outside_texture"]
		ctx.selected_segment.outside_filler_color = ctx.texture_snapshot["outside_filler_color"]
	if not ctx.edit_inside_check.button_pressed and ctx.texture_snapshot.has("inside_texture"):
		ctx.selected_segment.inside_texture = ctx.texture_snapshot["inside_texture"]
		ctx.selected_segment.inside_filler_color = ctx.texture_snapshot["inside_filler_color"]

	ctx.room_data.emit_changed()
	ctx.rendering.rebuild_walls()
	ctx.persistence.save_current_room_data()
	ctx.texture_snapshot.clear()
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.ui_module.set_status("Iso wall texture updated, RoomData refreshed, and room data saved.")

func on_texture_canceled() -> void:
	if ctx.selected_segment != null and not ctx.texture_snapshot.is_empty():
		ctx.selected_segment.outside_texture = ctx.texture_snapshot["outside_texture"]
		ctx.selected_segment.inside_texture = ctx.texture_snapshot["inside_texture"]
		ctx.selected_segment.outside_filler_color = ctx.texture_snapshot["outside_filler_color"]
		ctx.selected_segment.inside_filler_color = ctx.texture_snapshot["inside_filler_color"]
		ctx.rendering.rebuild_walls()
	ctx.texture_snapshot.clear()
	ctx.state = RoomBuilderTypes.State.IDLE
	ctx.ui_module.set_status("Iso wall texture edit cancelled.")


# ---------------------------------------------------------------- Deletion
