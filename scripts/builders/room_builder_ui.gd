class_name RoomBuilderUI
extends RefCounted

## Menus, dialogs, construction settings controls, and status display.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func build_ui() -> void:
	ctx.ui = CanvasLayer.new()
	ctx.ui.layer = 100
	ctx.host.add_child(ctx.ui)

	ctx.status_label = Label.new()
	ctx.status_label.position = Vector2(12.0, 8.0)
	ctx.status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx.ui.add_child(ctx.status_label)

	build_general_context_menu()
	build_load_room_menu()
	build_wall_menu()
	build_floor_menu()
	build_floor_dialogs()
	build_start_dialog()
	build_end_dialogs()
	build_rebuild_dialog()
	build_style_dialog()
	build_repaint_dialog()
	build_texture_dialog()
	build_delete_dialog()
	build_save_dialog()

func build_general_context_menu() -> void:
	ctx.context_menu = PopupMenu.new()
	ctx.context_menu.name = "ContextMenu"
	ctx.context_menu.add_item("Save", 0)
	ctx.context_menu.add_separator()
	ctx.context_menu.add_item("Load Room", 2)
	ctx.context_menu.add_separator()
	ctx.context_menu.add_item("Turn Grid Off" if ctx.grid_visible else "Turn Grid On", 1)
	ctx.context_menu.add_separator()
	ctx.context_menu.add_item("Build Floor Polygon", 30)
	ctx.context_menu.add_separator()
	ctx.context_menu.add_item("Wall Render", 10)
	ctx.context_menu.add_item("Iso Wall Render", 11)
	ctx.context_menu.add_separator()
	ctx.context_menu.add_item("Iso1 - No Walls", 20)
	ctx.context_menu.add_item("Iso2 - Back Walls", 21)
	ctx.context_menu.add_item("Iso3 - All Walls", 22)
	ctx.context_menu.id_pressed.connect(on_context_menu_id_pressed)
	ctx.ui.add_child(ctx.context_menu)

func build_load_room_menu() -> void:
	ctx.load_room_menu = PopupMenu.new()
	ctx.load_room_menu.name = "LoadRoomMenu"
	ctx.load_room_menu.id_pressed.connect(on_load_room_menu_id_pressed)
	ctx.ui.add_child(ctx.load_room_menu)

func refresh_load_room_menu() -> void:
	if ctx.load_room_menu == null:
		return

	ctx.load_room_menu.clear()
	var paths: Array[String] = ctx.persistence.get_saved_room_paths()
	if paths.is_empty():
		ctx.load_room_menu.add_item("No .tres RoomData files found", 0)
		ctx.load_room_menu.set_item_disabled(0, true)
		return

	for index in paths.size():
		var path: String = paths[index]
		var item_id := 1000 + index
		ctx.load_room_menu.add_item(path.get_file(), item_id)
		ctx.load_room_menu.set_item_tooltip(ctx.load_room_menu.get_item_index(item_id), path)
		ctx.load_room_menu.set_item_metadata(ctx.load_room_menu.get_item_index(item_id), path)

func open_load_room_menu() -> void:
	refresh_load_room_menu()
	ctx.load_room_menu.popup(Rect2i(Vector2i(ctx.host.get_viewport().get_mouse_position()) + Vector2i(8, 8), Vector2i.ZERO))

func on_load_room_menu_id_pressed(id: int) -> void:
	if id < 1000:
		return
	var item_index := ctx.load_room_menu.get_item_index(id)
	if item_index < 0:
		return
	var metadata: Variant = ctx.load_room_menu.get_item_metadata(item_index)
	var path := String(metadata)
	if path.is_empty():
		return
	ctx.persistence.load_room(path)

func build_wall_menu() -> void:
	ctx.wall_menu = PopupMenu.new()
	ctx.wall_menu.name = "WallMenu"
	ctx.wall_menu.add_item("Extend Wall From Point", 0)
	ctx.wall_menu.add_item("Rebuild Wall From Point", 1)
	ctx.wall_menu.add_item("Delete Wall", 2)
	ctx.wall_menu.add_item("Change End Point Render", 3)
	ctx.wall_menu.add_item("Repaint Wall", 4)
	ctx.wall_menu.add_item("Edit Iso Wall Texture", 6)
	ctx.wall_menu.add_separator()
	ctx.wall_menu.add_item("Cancel", 5)
	ctx.wall_menu.id_pressed.connect(on_wall_menu_id_pressed)
	ctx.ui.add_child(ctx.wall_menu)

func build_floor_menu() -> void:
	ctx.floor_menu = PopupMenu.new()
	ctx.floor_menu.name = "FloorMenu"
	ctx.floor_menu.add_item("Edit Floor Color / Texture", 0)
	ctx.floor_menu.add_item("Delete Floor", 1)
	ctx.floor_menu.add_separator()
	ctx.floor_menu.add_item("Cancel", 2)
	ctx.floor_menu.id_pressed.connect(on_floor_menu_id_pressed)
	ctx.ui.add_child(ctx.floor_menu)

func open_floor_menu() -> void:
	if ctx.selected_floor == null:
		return
	ctx.floor_menu.popup(Rect2i(Vector2i(ctx.host.get_viewport().get_mouse_position()) + Vector2i(8, 8), Vector2i.ZERO))

func on_floor_menu_id_pressed(id: int) -> void:
	match id:
		0:
			ctx.floor_ops.open_appearance_prompt()
		1:
			ctx.floor_ops.delete_selected_floor()
		2:
			ctx.floor_ops.clear_selection()

func open_wall_menu() -> void:
	if ctx.selected_segment == null:
		return

	ctx.wall_ops.ctx.wall_ops.refresh_wall_menu_state()
	ctx.wall_menu.popup(Rect2i(Vector2i(ctx.host.get_viewport().get_mouse_position()) + Vector2i(8, 8), Vector2i.ZERO))

func on_wall_menu_id_pressed(id: int) -> void:
	match id:
		0:
			ctx.wall_ops.begin_extension()
		1:
			ctx.wall_ops.begin_rebuild_prompt()
		2:
			ctx.editing.delete_selected_wall()
		3:
			ctx.editing.open_style_prompt()
		4:
			ctx.editing.open_repaint_prompt()
		5:
			ctx.wall_ops.clear_selection()
		6:
			ctx.texture.open_texture_prompt()

func open_context_menu() -> void:
	ctx.context_menu.popup(Rect2i(Vector2i(ctx.host.get_viewport().get_mouse_position()) + Vector2i(8, 8), Vector2i.ZERO))

func on_context_menu_id_pressed(id: int) -> void:
	match id:
		0:
			ctx.name_edit.text = ctx.last_saved_name
			ctx.name_dialog.popup_centered(Vector2i(380, 120))
			ctx.name_edit.grab_focus()
			ctx.name_edit.select_all()
		1:
			ctx.grid.toggle_grid()
		2:
			open_load_room_menu()
		30:
			ctx.floor_ops.begin_manual_floor()
		10:
			ctx.rendering.switch_renderer(false)
		11:
			ctx.rendering.switch_renderer(true)
		20:
			ctx.rendering.set_iso_view_mode(IsoWallRenderer.ViewMode.ISO1_NO_WALLS)
		21:
			ctx.rendering.set_iso_view_mode(IsoWallRenderer.ViewMode.ISO2_BACK_WALLS)
		22:
			ctx.rendering.set_iso_view_mode(IsoWallRenderer.ViewMode.ISO3_ALL_WALLS)

func update_context_menu_grid_item() -> void:
	if ctx.context_menu == null:
		return
	var index := ctx.context_menu.get_item_index(1)
	if index >= 0:
		ctx.context_menu.set_item_text(index, "Turn Grid Off" if ctx.grid_visible else "Turn Grid On")


# ---------------------------------------------------------------- UI

func build_start_dialog() -> void:
	ctx.start_dialog = ConfirmationDialog.new()
	ctx.start_dialog.name = "StartWallDialog"
	ctx.start_dialog.title = "Start Wall"
	ctx.start_dialog.ok_button_text = "Start Wall"
	ctx.start_dialog.cancel_button_text = "Cancel"
	ctx.start_dialog.canceled.connect(Callable(ctx.wall_ops, "on_start_canceled"))
	ctx.start_dialog.confirmed.connect(Callable(ctx.wall_ops, "on_start_confirmed"))

	var box := VBoxContainer.new()
	var question := Label.new()
	question.text = "Start building a wall here?"
	box.add_child(question)

	box.add_child(make_separator())
	box.add_child(make_color_row("Color", false))
	box.add_child(make_float_row("Wall gap / thickness", 1.0, 256.0, 1.0, false))
	box.add_child(make_float_row("Parallel line width", 1.0, 32.0, 1.0, true))

	var start_cap_row := HBoxContainer.new()
	var start_cap_label := Label.new()
	start_cap_label.text = "Start end render"
	start_cap_label.custom_minimum_size.x = 150.0
	ctx.start_cap_button = OptionButton.new()
	ctx.start_cap_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_cap_options(ctx.start_cap_button)
	ctx.start_cap_button.item_selected.connect(on_start_cap_changed)
	start_cap_row.add_child(start_cap_label)
	start_cap_row.add_child(ctx.start_cap_button)
	box.add_child(start_cap_row)

	var end_cap_row := HBoxContainer.new()
	var end_cap_label := Label.new()
	end_cap_label.text = "End render"
	end_cap_label.custom_minimum_size.x = 150.0
	ctx.end_cap_button = OptionButton.new()
	ctx.end_cap_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_cap_options(ctx.end_cap_button)
	ctx.end_cap_button.item_selected.connect(on_end_cap_changed)
	end_cap_row.add_child(end_cap_label)
	end_cap_row.add_child(ctx.end_cap_button)
	box.add_child(end_cap_row)

	ctx.start_dialog.add_child(box)
	ctx.ui.add_child(ctx.start_dialog)

func make_separator() -> HSeparator:
	var separator := HSeparator.new()
	return separator

func make_color_row(label_text: String, repaint: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150.0

	var button := ColorPickerButton.new()
	button.custom_minimum_size = Vector2(140.0, 28.0)
	if repaint:
		ctx.repaint_color_button = button
	else:
		ctx.color_button = button
		button.color_changed.connect(on_start_color_changed)

	row.add_child(label)
	row.add_child(button)
	return row

func make_float_row(label_text: String, min_value: float, max_value: float, step: float, is_line_width: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150.0

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if is_line_width:
		ctx.line_width_spin = spin
		spin.value_changed.connect(on_start_line_width_changed)
	else:
		ctx.thickness_spin = spin
		spin.value_changed.connect(on_start_thickness_changed)

	row.add_child(label)
	row.add_child(spin)
	return row

func add_cap_options(button: OptionButton) -> void:
	button.add_item("Flat", WallSegment.CapStyle.FLAT)
	button.add_item("Curve Outward", WallSegment.CapStyle.CURVE_OUTWARD)
	button.add_item("Curve Inward", WallSegment.CapStyle.CURVE_INWARD)
	button.add_item("Point Convex", WallSegment.CapStyle.POINT_CONVEX)
	button.add_item("Point Concave", WallSegment.CapStyle.POINT_CONCAVE)

func build_end_dialogs() -> void:
	ctx.end_dialog = ConfirmationDialog.new()
	ctx.end_dialog.name = "BuildWallDialog"
	ctx.end_dialog.title = "Build Wall"
	ctx.end_dialog.ok_button_text = "Build Wall"
	ctx.end_dialog.cancel_button_text = "Pick Again"
	ctx.end_dialog.confirmed.connect(Callable(ctx.wall_ops, "on_end_confirmed"))
	ctx.end_dialog.canceled.connect(Callable(ctx.wall_ops, "on_end_canceled"))
	ctx.ui.add_child(ctx.end_dialog)

	ctx.snap_dialog = ConfirmationDialog.new()
	ctx.snap_dialog.name = "SnapDialog"
	ctx.snap_dialog.title = "Wall Snap"
	ctx.snap_dialog.ok_button_text = "Snap"
	ctx.snap_dialog.cancel_button_text = "Don't Snap"
	ctx.snap_dialog.confirmed.connect(Callable(ctx.wall_ops, "on_snap_confirmed"))
	ctx.snap_dialog.canceled.connect(Callable(ctx.wall_ops, "on_snap_canceled"))
	ctx.ui.add_child(ctx.snap_dialog)

func build_rebuild_dialog() -> void:
	ctx.rebuild_end_dialog = ConfirmationDialog.new()
	ctx.rebuild_end_dialog.name = "RebuildEndpointDialog"
	ctx.rebuild_end_dialog.title = "Rebuild Wall From Point"
	ctx.rebuild_end_dialog.ok_button_text = "Move Endpoint"
	ctx.rebuild_end_dialog.cancel_button_text = "Cancel"
	ctx.rebuild_end_button = OptionButton.new()
	ctx.rebuild_end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctx.rebuild_end_dialog.add_child(ctx.rebuild_end_button)
	ctx.rebuild_end_dialog.confirmed.connect(Callable(ctx.wall_ops, "on_rebuild_end_confirmed"))
	ctx.rebuild_end_dialog.canceled.connect(Callable(ctx.wall_ops, "on_rebuild_end_canceled"))
	ctx.ui.add_child(ctx.rebuild_end_dialog)

func build_style_dialog() -> void:
	ctx.style_dialog = ConfirmationDialog.new()
	ctx.style_dialog.name = "StyleDialog"
	ctx.style_dialog.title = "Change End Point Render"
	ctx.style_dialog.ok_button_text = "Apply"
	ctx.style_dialog.cancel_button_text = "Cancel"

	var box := VBoxContainer.new()

	var end_row := HBoxContainer.new()
	var end_label := Label.new()
	end_label.text = "Endpoint"
	end_label.custom_minimum_size.x = 120.0
	ctx.style_end_button = OptionButton.new()
	ctx.style_end_button.add_item("Start", 0)
	ctx.style_end_button.add_item("End", 1)
	ctx.style_end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_row.add_child(end_label)
	end_row.add_child(ctx.style_end_button)
	box.add_child(end_row)

	var cap_row := HBoxContainer.new()
	var cap_label := Label.new()
	cap_label.text = "Render"
	cap_label.custom_minimum_size.x = 120.0
	ctx.style_cap_button = OptionButton.new()
	add_cap_options(ctx.style_cap_button)
	ctx.style_cap_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_row.add_child(cap_label)
	cap_row.add_child(ctx.style_cap_button)
	box.add_child(cap_row)

	ctx.style_dialog.add_child(box)
	ctx.style_dialog.confirmed.connect(Callable(ctx.editing, "on_style_confirmed"))
	ctx.style_dialog.canceled.connect(Callable(ctx.editing, "on_style_canceled"))
	ctx.ui.add_child(ctx.style_dialog)

func build_repaint_dialog() -> void:
	ctx.repaint_dialog = ConfirmationDialog.new()
	ctx.repaint_dialog.name = "RepaintDialog"
	ctx.repaint_dialog.title = "Repaint Wall"
	ctx.repaint_dialog.ok_button_text = "Repaint"
	ctx.repaint_dialog.cancel_button_text = "Cancel"
	ctx.repaint_dialog.add_child(make_color_row("Wall color", true))
	ctx.repaint_dialog.confirmed.connect(Callable(ctx.editing, "on_repaint_confirmed"))
	ctx.repaint_dialog.canceled.connect(Callable(ctx.editing, "on_repaint_canceled"))
	ctx.ui.add_child(ctx.repaint_dialog)

func build_texture_dialog() -> void:
	ctx.texture_dialog = ConfirmationDialog.new()
	ctx.texture_dialog.name = "IsoWallTextureDialog"
	ctx.texture_dialog.title = "Iso Wall Texture"
	ctx.texture_dialog.ok_button_text = "Apply & Save"
	ctx.texture_dialog.cancel_button_text = "Cancel"

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(620.0, 300.0)

	var info := Label.new()
	info.text = "Choose a tiled texture for either wall face. The filler color is sampled from the nearest color in the selected texture. Changes preview live."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)
	root.add_child(make_separator())

	var faces := HBoxContainer.new()

	var outside_box := VBoxContainer.new()
	outside_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctx.edit_outside_check = CheckButton.new()
	ctx.edit_outside_check.text = "Edit Outside Wall"
	ctx.edit_outside_check.button_pressed = true
	outside_box.add_child(ctx.edit_outside_check)
	ctx.outside_texture_button = make_texture_option()
	outside_box.add_child(ctx.outside_texture_button)
	ctx.outside_texture_preview = make_texture_preview()
	outside_box.add_child(ctx.outside_texture_preview)
	ctx.outside_filler_preview = ColorRect.new()
	ctx.outside_filler_preview.custom_minimum_size = Vector2(1.0, 28.0)
	outside_box.add_child(ctx.outside_filler_preview)

	var inside_box := VBoxContainer.new()
	inside_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctx.edit_inside_check = CheckButton.new()
	ctx.edit_inside_check.text = "Edit Inner Wall"
	ctx.edit_inside_check.button_pressed = true
	inside_box.add_child(ctx.edit_inside_check)
	ctx.inside_texture_button = make_texture_option()
	inside_box.add_child(ctx.inside_texture_button)
	ctx.inside_texture_preview = make_texture_preview()
	inside_box.add_child(ctx.inside_texture_preview)
	ctx.inside_filler_preview = ColorRect.new()
	ctx.inside_filler_preview.custom_minimum_size = Vector2(1.0, 28.0)
	inside_box.add_child(ctx.inside_filler_preview)

	faces.add_child(outside_box)
	faces.add_child(inside_box)
	root.add_child(faces)

	ctx.texture_dialog.add_child(root)
	ctx.texture_dialog.confirmed.connect(Callable(ctx.texture, "on_texture_confirmed"))
	ctx.texture_dialog.canceled.connect(Callable(ctx.texture, "on_texture_canceled"))
	ctx.outside_texture_button.item_selected.connect(Callable(ctx.texture, "on_outside_texture_selected"))
	ctx.inside_texture_button.item_selected.connect(Callable(ctx.texture, "on_inside_texture_selected"))
	ctx.ui.add_child(ctx.texture_dialog)

func make_texture_option() -> OptionButton:
	var button := OptionButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	populate_texture_option(button)
	return button

func make_texture_preview() -> TextureRect:
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(1.0, 110.0)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return preview

func populate_texture_option(button: OptionButton) -> void:
	button.clear()
	button.add_item("None / Filler Only", 0)
	button.set_item_metadata(0, "")

	var paths: Array[String] = []
	var dir := DirAccess.open(ctx.debug_texture_directory)
	if dir != null:
		for file_name in dir.get_files():
			var ext := file_name.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp", "svg"]:
				paths.append(ctx.debug_texture_directory.path_join(file_name))
	paths.sort()

	for path in paths:
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		var index := button.item_count
		button.add_item(path.get_file(), index)
		button.set_item_metadata(index, path)

func select_texture_option(button: OptionButton, texture: Texture2D) -> void:
	var target_path := "" if texture == null else texture.resource_path
	var selected := 0
	for i in button.item_count:
		var metadata: Variant = button.get_item_metadata(i)
		if String(metadata) == target_path:
			selected = i
			break
	button.select(selected)

func build_floor_dialogs() -> void:
	ctx.auto_floor_dialog = ConfirmationDialog.new()
	ctx.auto_floor_dialog.name = "AutoFloorDialog"
	ctx.auto_floor_dialog.title = "Enclosed Space Detected"
	ctx.auto_floor_dialog.ok_button_text = "Auto-Floor"
	ctx.auto_floor_dialog.cancel_button_text = "Leave Empty"
	ctx.auto_floor_dialog.confirmed.connect(Callable(ctx.floor_ops, "on_auto_floor_confirmed"))
	ctx.auto_floor_dialog.canceled.connect(Callable(ctx.floor_ops, "on_auto_floor_canceled"))
	ctx.ui.add_child(ctx.auto_floor_dialog)

	ctx.floor_confirm_dialog = ConfirmationDialog.new()
	ctx.floor_confirm_dialog.name = "FloorConfirmDialog"
	ctx.floor_confirm_dialog.title = "Create Floor Polygon"
	ctx.floor_confirm_dialog.ok_button_text = "Create Floor"
	ctx.floor_confirm_dialog.cancel_button_text = "Keep Editing"
	ctx.floor_confirm_dialog.confirmed.connect(Callable(ctx.floor_ops, "on_manual_floor_confirmed"))
	ctx.floor_confirm_dialog.canceled.connect(Callable(ctx.floor_ops, "on_manual_floor_canceled"))
	ctx.ui.add_child(ctx.floor_confirm_dialog)

	ctx.floor_appearance_dialog = ConfirmationDialog.new()
	ctx.floor_appearance_dialog.name = "FloorAppearanceDialog"
	ctx.floor_appearance_dialog.title = "Floor Appearance"
	ctx.floor_appearance_dialog.ok_button_text = "Apply & Save"
	ctx.floor_appearance_dialog.cancel_button_text = "Cancel"

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(520.0, 280.0)

	var info := Label.new()
	info.text = "Use the fallback color when no texture is selected. A texture is tiled across the floor polygon."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)
	root.add_child(make_separator())
	root.add_child(make_floor_color_row())

	var texture_label := Label.new()
	texture_label.text = "Texture"
	root.add_child(texture_label)
	ctx.floor_texture_button = make_texture_option()
	ctx.floor_texture_button.item_selected.connect(Callable(ctx.floor_ops, "on_floor_texture_selected"))
	root.add_child(ctx.floor_texture_button)

	ctx.floor_texture_preview = make_texture_preview()
	root.add_child(ctx.floor_texture_preview)

	var tile_row := HBoxContainer.new()
	var tile_label := Label.new()
	tile_label.text = "Texture tile size"
	tile_label.custom_minimum_size.x = 150.0
	ctx.floor_texture_tile_spin = SpinBox.new()
	ctx.floor_texture_tile_spin.min_value = 8.0
	ctx.floor_texture_tile_spin.max_value = 1024.0
	ctx.floor_texture_tile_spin.step = 1.0
	tile_row.add_child(tile_label)
	tile_row.add_child(ctx.floor_texture_tile_spin)
	root.add_child(tile_row)

	ctx.floor_appearance_dialog.add_child(root)
	ctx.floor_appearance_dialog.confirmed.connect(Callable(ctx.floor_ops, "on_floor_appearance_confirmed"))
	ctx.floor_appearance_dialog.canceled.connect(Callable(ctx.floor_ops, "on_floor_appearance_canceled"))
	ctx.ui.add_child(ctx.floor_appearance_dialog)

func make_floor_color_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Fallback color"
	label.custom_minimum_size.x = 150.0
	ctx.floor_color_button = ColorPickerButton.new()
	ctx.floor_color_button.custom_minimum_size = Vector2(140.0, 28.0)
	ctx.floor_color_button.color_changed.connect(Callable(ctx.floor_ops, "on_floor_color_changed"))
	row.add_child(label)
	row.add_child(ctx.floor_color_button)
	return row

func show_auto_floor_prompt(polygon: PackedVector2Array) -> void:
	ctx.auto_floor_dialog.dialog_text = "The walls now enclose a complete section (%d corners, %.1f px²). Automatically create a floor for this enclosed space?" % [polygon.size(), ctx.room_data.get_polygon_area(polygon)]
	popup_near_mouse(ctx.auto_floor_dialog)

func show_floor_confirm(polygon: PackedVector2Array) -> void:
	ctx.floor_confirm_dialog.dialog_text = "Create a floor from %d corners?\nArea: %.1f px²" % [polygon.size(), ctx.room_data.get_polygon_area(polygon)]
	popup_near_mouse(ctx.floor_confirm_dialog)

func show_floor_appearance(floor: FloorSpace) -> void:
	ctx.floor_color_button.color = floor.color
	select_texture_option(ctx.floor_texture_button, floor.texture)
	ctx.floor_texture_preview.texture = floor.texture
	ctx.floor_texture_tile_spin.value = floor.texture_tile_size
	popup_near_mouse(ctx.floor_appearance_dialog)

func load_selected_floor_texture() -> Texture2D:
	if ctx.floor_texture_button == null or ctx.floor_texture_button.selected < 0:
		return null
	var metadata: Variant = ctx.floor_texture_button.get_item_metadata(ctx.floor_texture_button.selected)
	var path := String(metadata)
	if path.is_empty():
		ctx.floor_texture_preview.texture = null
		return null
	var texture := load(path) as Texture2D
	ctx.floor_texture_preview.texture = texture
	return texture

func get_floor_texture_tile_size() -> float:
	if ctx.floor_texture_tile_spin == null:
		return ctx.floor_texture_tile_size
	return float(ctx.floor_texture_tile_spin.value)

func build_delete_dialog() -> void:
	ctx.delete_dialog = ConfirmationDialog.new()
	ctx.delete_dialog.name = "DeleteWallDialog"
	ctx.delete_dialog.title = "Delete Wall"
	ctx.delete_dialog.ok_button_text = "Delete"
	ctx.delete_dialog.cancel_button_text = "Cancel"
	ctx.delete_dialog.confirmed.connect(Callable(ctx.editing, "on_delete_confirmed"))
	ctx.delete_dialog.canceled.connect(Callable(ctx.editing, "on_delete_canceled"))
	ctx.ui.add_child(ctx.delete_dialog)

func build_save_dialog() -> void:
	ctx.name_dialog = ConfirmationDialog.new()
	ctx.name_dialog.name = "SaveRoomDialog"
	ctx.name_dialog.title = "Save Room Data"
	ctx.name_dialog.ok_button_text = "Save"
	ctx.name_dialog.cancel_button_text = "Cancel"

	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "File name (saved to %s)" % ctx.save_dir
	ctx.name_edit = LineEdit.new()
	ctx.name_edit.placeholder_text = "bedroom1"
	box.add_child(label)
	box.add_child(ctx.name_edit)
	ctx.name_dialog.add_child(box)
	ctx.name_dialog.register_text_enter(ctx.name_edit)
	ctx.name_dialog.confirmed.connect(Callable(ctx.persistence, "on_save_confirmed"))
	ctx.name_dialog.canceled.connect(Callable(ctx.persistence, "on_save_canceled"))
	ctx.ui.add_child(ctx.name_dialog)


# ---------------------------------------------------------------- Construction settings / dialog utility

func read_pending_visual_settings() -> void:
	ctx.pending_color = ctx.color_button.color
	ctx.pending_thickness = maxf(float(ctx.thickness_spin.value), 1.0)
	ctx.pending_line_width = maxf(float(ctx.line_width_spin.value), 1.0)
	ctx.pending_start_cap = ctx.start_cap_button.get_selected_id() as WallSegment.CapStyle
	ctx.pending_end_cap = ctx.end_cap_button.get_selected_id() as WallSegment.CapStyle

func sync_start_dialog_from_pending() -> void:
	if ctx.color_button == null:
		return
	ctx.color_button.color = ctx.pending_color
	ctx.thickness_spin.value = ctx.pending_thickness
	ctx.line_width_spin.value = ctx.pending_line_width
	ctx.start_cap_button.select(ctx.pending_start_cap)
	ctx.end_cap_button.select(ctx.pending_end_cap)

func on_start_color_changed(value: Color) -> void:
	ctx.pending_color = value
	ctx.rendering.update_ghost()

func on_start_thickness_changed(value: float) -> void:
	ctx.pending_thickness = maxf(value, 1.0)
	ctx.rendering.update_ghost()

func on_start_line_width_changed(value: float) -> void:
	ctx.pending_line_width = maxf(value, 1.0)
	ctx.rendering.update_ghost()

func on_start_cap_changed(index: int) -> void:
	set_pending_cap(0, index)

func on_end_cap_changed(index: int) -> void:
	set_pending_cap(1, index)

func set_pending_cap(end_id: int, cap_id: int) -> void:
	var cap_style := cap_id as WallSegment.CapStyle
	if end_id == 0:
		ctx.pending_start_cap = cap_style
	else:
		ctx.pending_end_cap = cap_style
	ctx.rendering.update_ghost()

func popup_near_mouse(dialog: Window) -> void:
	var pos := Vector2i(ctx.host.get_viewport().get_mouse_position()) + Vector2i(24, 24)
	dialog.popup(Rect2i(pos, Vector2i.ZERO))

func set_status(message: String) -> void:
	if ctx.status_label != null:
		ctx.status_label.text = message

func setup() -> void:
	build_ui()

# Signals are wired directly to the owning module so RoomBuilder remains the coordinator only.
