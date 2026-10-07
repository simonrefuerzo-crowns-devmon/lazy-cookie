class_name ObjectModelEditor
extends RefCounted

## Screen-space editor for a single ModelData part.
##
## This editor is intentionally separate from ObjectBuilder and
## ObjectModelBuilderHelper. It edits ModelData directly, while preserving the
## nested model tree and leaving RoomBuilder/Grid ownership outside this class.

signal applied(part: ModelData)
signal cancelled(part: ModelData)

var host: Node = null
var room_data: RoomData = null

var ui_layer: CanvasLayer = null
var dialog: ConfirmationDialog = null
var scroll: ScrollContainer = null
var root: VBoxContainer = null

var target_object: ObjectData = null
var target_part: ModelData = null

var name_edit: LineEdit
var description_edit: TextEdit
var base_color_button: ColorPickerButton
var fallback_check: CheckButton

var size_x_spin: SpinBox
var size_y_spin: SpinBox
var local_x_spin: SpinBox
var local_y_spin: SpinBox
var rotation_spin: SpinBox
var height_offset_spin: SpinBox

var body_type_button: OptionButton
var flat_bottom_button: OptionButton
var has_corners_check: CheckButton
var corner_style_button: OptionButton
var corner_radius_spin: SpinBox
var corner_segments_spin: SpinBox
var height_spin: SpinBox

var top_end_x_spin: SpinBox
var top_end_y_spin: SpinBox
var top_end_size_x_spin: SpinBox
var top_end_size_y_spin: SpinBox
var top_end_style_button: OptionButton
var radial_segments_spin: SpinBox
var hybrid_sections_spin: SpinBox
var top_profile_height_spin: SpinBox

var allow_top_check: CheckButton
var allow_sides_check: CheckButton
var snap_distance_spin: SpinBox

var top_texture_rotation_spin: SpinBox
var rotate_top_texture_space_check: CheckButton

var texture_loadout: ModelTextureLoadout = ModelTextureLoadout.new()
var texture_face_buttons: Dictionary = {}
var texture_snapshot: Dictionary = {}


func setup(owner: Node, initial_room_data: RoomData) -> void:
	host = owner
	room_data = initial_room_data
	_create_dialog()


func set_texture_directory(path: String) -> void:
	if texture_loadout == null:
		texture_loadout = ModelTextureLoadout.new()
	texture_loadout.set_directory(path)
	_refresh_texture_loadout_controls()


func set_room_data(new_room_data: RoomData) -> void:
	room_data = new_room_data


func set_enabled(value: bool) -> void:
	if not value and is_instance_valid(dialog):
		dialog.hide()


func open(object_data: ObjectData, part: ModelData) -> bool:
	if part == null:
		return false
	if host == null or not is_instance_valid(host):
		return false

	target_object = object_data
	target_part = part
	if texture_loadout == null:
		texture_loadout = ModelTextureLoadout.new()
	texture_snapshot = texture_loadout.capture(part)
	_refresh_from_part()
	_resize_and_popup()
	return true


func close() -> void:
	if is_instance_valid(dialog):
		dialog.hide()


func _create_dialog() -> void:
	if host == null or not is_instance_valid(host):
		return

	ui_layer = CanvasLayer.new()
	ui_layer.name = "ObjectModelEditorLayer"
	ui_layer.layer = 101
	host.add_child(ui_layer)

	dialog = ConfirmationDialog.new()
	dialog.name = "ObjectModelEditor"
	dialog.title = "Edit Model Part"
	dialog.ok_button_text = "Apply"
	dialog.cancel_button_text = "Cancel"
	dialog.size = Vector2i(760, 720)
	dialog.min_size = Vector2i(420, 320)
	ui_layer.add_child(dialog)
	dialog.confirmed.connect(_apply)
	dialog.canceled.connect(_cancel)
	dialog.size_changed.connect(_resize_content)

	scroll = ScrollContainer.new()
	scroll.name = "ModelEditorScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)

	root = VBoxContainer.new()
	root.name = "ModelEditorRoot"
	root.custom_minimum_size.x = 680.0
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	_build_ui()
	_resize_content()


func _build_ui() -> void:
	root.add_child(_section_label("Identity"))
	name_edit = _add_line("Model Part Name")
	description_edit = TextEdit.new()
	description_edit.custom_minimum_size.y = 70.0
	root.add_child(_labeled_control("Description", description_edit))
	base_color_button = ColorPickerButton.new()
	base_color_button.custom_minimum_size.y = 32.0
	root.add_child(_labeled_control("Base Color", base_color_button))
	fallback_check = _add_check("Use Base Color Fallback")

	root.add_child(_section_label("Flat Placement"))
	size_x_spin = _add_spin("Size X", 1.0, 100000.0, 1.0)
	size_y_spin = _add_spin("Size Y", 1.0, 100000.0, 1.0)
	local_x_spin = _add_spin("Local X", -100000.0, 100000.0, 1.0)
	local_y_spin = _add_spin("Local Y", -100000.0, 100000.0, 1.0)
	rotation_spin = _add_spin("Local Rotation", -360.0, 360.0, 1.0)
	height_offset_spin = _add_spin("Local Height Offset", 0.0, 100000.0, 1.0)

	root.add_child(_section_label("Body Geometry"))
	body_type_button = _make_option_button()
	body_type_button.add_item("Rectangular", ModelData.BodyType.RECTANGULAR)
	body_type_button.add_item("Cylinder", ModelData.BodyType.CYLINDER)
	body_type_button.add_item("Pyramid", ModelData.BodyType.PYRAMID)
	body_type_button.add_item("Cone", ModelData.BodyType.CONE)
	body_type_button.add_item("Hybrid", ModelData.BodyType.HYBRID)
	root.add_child(_labeled_control("Body Type", body_type_button))

	flat_bottom_button = _make_option_button()
	flat_bottom_button.add_item("Rectangle", ModelData.FlatBottomShape.RECTANGLE)
	flat_bottom_button.add_item("Ellipse", ModelData.FlatBottomShape.ELLIPSE)
	root.add_child(_labeled_control("Flat Bottom Shape", flat_bottom_button))

	has_corners_check = _add_check("Has Corners")
	corner_style_button = _make_option_button()
	corner_style_button.add_item("Solid Rectangle Corners", ModelData.CornerStyle.SOLID_RECT)
	corner_style_button.add_item("Rounded Corners", ModelData.CornerStyle.ROUNDED)
	corner_style_button.add_item("Curved Corners", ModelData.CornerStyle.CURVED)
	root.add_child(_labeled_control("Corner Style", corner_style_button))
	corner_radius_spin = _add_spin("Corner Radius", 0.0, 4096.0, 1.0)
	corner_segments_spin = _add_spin("Corner Segments", 1.0, 32.0, 1.0)
	height_spin = _add_spin("Height", 0.0, 100000.0, 1.0)

	root.add_child(_section_label("Upper / Hybrid Geometry"))
	top_end_x_spin = _add_spin("Top End X", -100000.0, 100000.0, 1.0)
	top_end_y_spin = _add_spin("Top End Y", -100000.0, 100000.0, 1.0)
	top_end_size_x_spin = _add_spin("Top End Size X", 0.0, 100000.0, 1.0)
	top_end_size_y_spin = _add_spin("Top End Size Y", 0.0, 100000.0, 1.0)
	top_end_style_button = _make_option_button()
	top_end_style_button.add_item("Center Point", ModelData.TopEndStyle.CENTER_POINT)
	top_end_style_button.add_item("Point", ModelData.TopEndStyle.POINT)
	top_end_style_button.add_item("Flat End", ModelData.TopEndStyle.FLAT_END)
	root.add_child(_labeled_control("Top End Style", top_end_style_button))
	radial_segments_spin = _add_spin("Radial Segments", 3.0, 128.0, 1.0)
	hybrid_sections_spin = _add_spin("Hybrid Sections", 1.0, 32.0, 1.0)
	top_profile_height_spin = _add_spin("Top Profile Height", 0.0, 100000.0, 1.0)

	root.add_child(_section_label("Attachment / Snapping"))
	allow_top_check = _add_check("Allow Parts On Top")
	allow_sides_check = _add_check("Allow Parts On Four Sides")
	snap_distance_spin = _add_spin("Snap Distance", 0.0, 256.0, 1.0)

	root.add_child(_section_label("Top Texture Orientation"))
	top_texture_rotation_spin = _add_spin("Top Texture Rotation", -360.0, 360.0, 1.0)
	rotate_top_texture_space_check = _add_check("Rotate Top Texture Space")

	root.add_child(_section_label("Texture Loadout (5 Faces)"))
	var texture_note := _label("Each face uses the same loadout rule as wall textures: choose one direct texture asset from the configured texture directory, or None / Filler Only.")
	texture_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(texture_note)
	for face in ModelTextureLoadout.LOADOUT_FACES:
		var button := OptionButton.new()
		button.custom_minimum_size.y = 30.0
		button.item_selected.connect(_on_texture_loadout_selected.bind(face))
		texture_face_buttons[face] = button
		root.add_child(_labeled_control(texture_loadout.get_face_label(face) + " Face", button))

	var note := _label("This editor changes the selected ModelData part directly. Its children remain separate ModelData parts and keep their own geometry and identity.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)


func _refresh_from_part() -> void:
	if target_part == null:
		return

	name_edit.text = target_part.model_name
	description_edit.text = target_part.description
	base_color_button.color = target_part.base_color
	fallback_check.button_pressed = target_part.use_base_color_fallback

	size_x_spin.value = target_part.size_px.x
	size_y_spin.value = target_part.size_px.y
	local_x_spin.value = target_part.local_position.x
	local_y_spin.value = target_part.local_position.y
	rotation_spin.value = target_part.local_rotation_degrees
	height_offset_spin.value = target_part.local_height_offset_px

	_select_option(body_type_button, target_part.body_type)
	_select_option(flat_bottom_button, target_part.flat_bottom_shape)
	has_corners_check.button_pressed = target_part.has_corners
	_select_option(corner_style_button, target_part.corner_style)
	corner_radius_spin.value = target_part.corner_radius_px
	corner_segments_spin.value = target_part.corner_segments
	height_spin.value = target_part.height_px

	top_end_x_spin.value = target_part.top_end_point.x
	top_end_y_spin.value = target_part.top_end_point.y
	top_end_size_x_spin.value = target_part.top_end_size_px.x
	top_end_size_y_spin.value = target_part.top_end_size_px.y
	_select_option(top_end_style_button, target_part.top_end_style)
	radial_segments_spin.value = target_part.radial_segments
	hybrid_sections_spin.value = target_part.hybrid_section_count
	top_profile_height_spin.value = target_part.top_profile_height_px

	allow_top_check.button_pressed = target_part.allow_parts_on_top
	allow_sides_check.button_pressed = target_part.allow_parts_on_sides
	snap_distance_spin.value = target_part.snap_distance_px

	top_texture_rotation_spin.value = target_part.top_texture_rotation_degrees
	rotate_top_texture_space_check.button_pressed = target_part.rotate_top_texture_space
	_refresh_texture_loadout_controls()


func _refresh_texture_loadout_controls() -> void:
	if target_part == null or texture_loadout == null:
		return
	var paths: Array[String] = texture_loadout.get_texture_paths()
	for face in ModelTextureLoadout.LOADOUT_FACES:
		var button: OptionButton = texture_face_buttons.get(face) as OptionButton
		if button == null:
			continue
		button.clear()
		button.add_item(ModelTextureLoadout.NONE_LABEL)
		button.set_item_metadata(0, ModelTextureLoadout.NONE_PATH)
		var selected_index: int = 0
		var wanted_path: String = texture_loadout.get_texture_path(target_part, face)
		for path in paths:
			button.add_item(path.get_file())
			var index: int = button.item_count - 1
			button.set_item_metadata(index, path)
			button.set_item_tooltip(index, path)
			if path == wanted_path:
				selected_index = index
		button.select(selected_index)


func _on_texture_loadout_selected(index: int, face: int) -> void:
	if target_part == null or texture_loadout == null:
		return
	var button: OptionButton = texture_face_buttons.get(face) as OptionButton
	if button == null or index < 0:
		return
	var metadata: Variant = button.get_item_metadata(index)
	var path := String(metadata)
	texture_loadout.set_texture_path(target_part, face, path)
	if target_object != null:
		target_object.emit_changed()
	if room_data != null:
		room_data.emit_changed()


func _restore_texture_snapshot() -> void:
	if target_part == null or texture_loadout == null or texture_snapshot.is_empty():
		return
	texture_loadout.apply(target_part, texture_snapshot)
	if target_object != null:
		target_object.emit_changed()
	if room_data != null:
		room_data.emit_changed()


func _apply() -> void:
	if target_part == null:
		return

	target_part.model_name = name_edit.text.strip_edges()
	if target_part.model_name.is_empty():
		target_part.model_name = "Model Part"
	target_part.description = description_edit.text
	target_part.base_color = base_color_button.color
	target_part.use_base_color_fallback = fallback_check.button_pressed

	target_part.size_px = Vector2(
		maxf(float(size_x_spin.value), 1.0),
		maxf(float(size_y_spin.value), 1.0))
	target_part.local_position = Vector2(
		float(local_x_spin.value),
		float(local_y_spin.value))
	target_part.local_rotation_degrees = float(rotation_spin.value)
	target_part.local_height_offset_px = maxf(float(height_offset_spin.value), 0.0)

	target_part.body_type = body_type_button.get_selected_id()
	target_part.flat_bottom_shape = flat_bottom_button.get_selected_id()
	target_part.has_corners = has_corners_check.button_pressed
	target_part.corner_style = corner_style_button.get_selected_id()
	target_part.corner_radius_px = maxf(float(corner_radius_spin.value), 0.0)
	target_part.corner_segments = clampi(int(corner_segments_spin.value), 1, 32)
	target_part.height_px = maxf(float(height_spin.value), 0.0)

	target_part.top_end_point = Vector2(
		float(top_end_x_spin.value),
		float(top_end_y_spin.value))
	target_part.top_end_size_px = Vector2(
		maxf(float(top_end_size_x_spin.value), 0.0),
		maxf(float(top_end_size_y_spin.value), 0.0))
	target_part.top_end_style = top_end_style_button.get_selected_id()
	target_part.radial_segments = clampi(int(radial_segments_spin.value), 3, 128)
	target_part.hybrid_section_count = clampi(int(hybrid_sections_spin.value), 1, 32)
	target_part.top_profile_height_px = maxf(float(top_profile_height_spin.value), 0.0)

	target_part.allow_parts_on_top = allow_top_check.button_pressed
	target_part.allow_parts_on_sides = allow_sides_check.button_pressed
	target_part.snap_distance_px = maxf(float(snap_distance_spin.value), 0.0)

	target_part.top_texture_rotation_degrees = float(top_texture_rotation_spin.value)
	target_part.rotate_top_texture_space = rotate_top_texture_space_check.button_pressed

	target_part.emit_changed()
	if target_object != null:
		target_object.emit_changed()
	if room_data != null:
		room_data.emit_changed()

	texture_snapshot.clear()
	applied.emit(target_part)
	dialog.hide()


func _cancel() -> void:
	_restore_texture_snapshot()
	texture_snapshot.clear()
	cancelled.emit(target_part)


func _resize_and_popup() -> void:
	if not is_instance_valid(dialog):
		return
	_resize_content()
	var viewport_size := host.get_viewport().get_visible_rect().size
	var available := Vector2i(
		maxi(int(viewport_size.x) - 32, 1),
		maxi(int(viewport_size.y) - 32, 1))
	var safe_size := Vector2i(
		clampi(760, mini(420, available.x), available.x),
		clampi(720, mini(320, available.y), available.y))
	dialog.size = safe_size
	dialog.popup_centered_clamped(safe_size, 0.95)


func _resize_content() -> void:
	if not is_instance_valid(dialog) or not is_instance_valid(scroll):
		return
	var window_size := dialog.size
	const MARGIN := 10
	const BUTTON_AREA_HEIGHT := 56
	scroll.position = Vector2(MARGIN, MARGIN)
	scroll.size = Vector2(
		maxf(float(window_size.x - MARGIN * 2), 1.0),
		maxf(float(window_size.y - MARGIN * 2 - BUTTON_AREA_HEIGHT), 1.0))


func _section_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 16)
	return label


func _label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label


func _make_option_button() -> OptionButton:
	var button := OptionButton.new()
	button.custom_minimum_size.y = 30.0
	return button


func _select_option(button: OptionButton, id: int) -> void:
	if button == null:
		return
	for index in button.item_count:
		if button.get_item_id(index) == id:
			button.select(index)
			return


func _add_line(label_text: String) -> LineEdit:
	var edit := LineEdit.new()
	root.add_child(_labeled_control(label_text, edit))
	return edit


func _add_spin(label_text: String, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	root.add_child(_labeled_control(label_text, spin))
	return spin


func _add_check(label_text: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = label_text
	root.add_child(check)
	return check


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	box.add_child(control)
	return box
