class_name ObjectBuilder
extends Node2D

## Non-isometric object editor.
## Add this after the floor/wall renderers in the world tree. ObjectRenderer
## draws at z_index 2, so it appears after floors and walls while remaining a
## separate renderer from the existing RoomBuilderRendering coordinator.

const SAVE_DIR := "res://assets/baked_tres/object_data/"
const TEXTURE_DIR := "res://assets/textures/all_texture/"
const EPSILON := 0.01
const ACTION_TAKE_MODEL_AS_BODY: int = 900
const ACTION_TAKE_MODEL_AS_MODEL: int = 901
const ACTION_INSERT_SAVED_MODEL_BASE: int = 1800
const MODEL_SAVE_DIR: String = "res://assets/baked_tres/model_data/"

@export_category("Room")
@export var room_data: RoomData
@export var enabled: bool = true

@export_category("Debug")
@export var debug_mode: bool = false:
	set(value):
		debug_mode = value
		_update_debug_state()

@export_category("Default Object")
@export var default_object_name: String = "Object"
@export var default_size_px: Vector2i = Vector2i(32, 32)
@export var default_hp: float = 100.0
@export var default_carried_weight: float = 1.0
@export var default_color: Color = Color.WHITE
@export var default_body_shape: ObjectData.BodyShape = ObjectData.BodyShape.RECTANGULAR
@export var default_has_corners: bool = true
@export var default_curved_corners: bool = false
@export_range(0.0, 4096.0, 1.0) var default_corner_radius_px: float = 4.0
@export_range(0.0, 100000.0, 1.0) var default_height_px: float = 32.0
@export_range(-100000.0, 100000.0, 1.0) var default_height_modifier_px: float = 0.0
@export var default_top_render_style: ObjectData.TopRenderStyle = ObjectData.TopRenderStyle.FLAT
@export_range(0.0, 100000.0, 1.0) var default_top_profile_height_px: float = 8.0
@export_range(3, 32, 1) var default_top_profile_segments: int = 8
@export_range(0.0, 100000.0, 1.0) var default_opening_depth_px: float = 8.0

var object_renderer: ObjectRenderer
var iso_object_renderer: IsoObjectRenderer
var object_model_renderer: ModelRenderer
var selected_object: ObjectData = null
var context_world_position := Vector2.ZERO

## Model editing is delegated to ObjectModelBuilderHelper so this class stays
## focused on ObjectData/UI management.
var model_builder_helper: ObjectModelBuilderHelper

var context_menu_layer: CanvasLayer
var context_menu: PopupMenu
var load_menu: PopupMenu
var take_model_menu: PopupMenu
var insert_model_menu: PopupMenu
var insert_model_files: Array[String] = []
var editor_dialog: ConfirmationDialog
var save_dialog: ConfirmationDialog
var texture_dialog: ConfirmationDialog
var status_dialog: AcceptDialog

var name_edit: LineEdit
var description_edit: TextEdit
var position_x_spin: SpinBox
var position_y_spin: SpinBox
var size_x_spin: SpinBox
var size_y_spin: SpinBox
var rotation_spin: SpinBox
var body_shape_button: OptionButton
var has_corners_check: CheckButton
var curved_corners_check: CheckButton
var corner_radius_spin: SpinBox
var height_spin: SpinBox
var height_modifier_spin: SpinBox
var top_render_style_button: OptionButton
var top_profile_height_spin: SpinBox
var top_profile_segments_spin: SpinBox
var opening_depth_spin: SpinBox
var hp_spin: SpinBox
var weight_spin: SpinBox
var carry_check: CheckButton
var hands_spin: SpinBox
var throw_check: CheckButton
var throw_force_spin: SpinBox
var throw_damage_spin: SpinBox
var break_check: CheckButton
var break_type_button: OptionButton
var break_impact_check: CheckButton
var contain_check: CheckButton
var interaction_paths_edit: LineEdit
var color_button: ColorPickerButton
var corner_size_x_spin: SpinBox
var corner_size_y_spin: SpinBox
var middle_tile_x_spin: SpinBox
var middle_tile_y_spin: SpinBox
var uniform_texture_size_check: CheckButton
var uniform_texture_size_x_spin: SpinBox
var uniform_texture_size_y_spin: SpinBox

var texture_face_button: OptionButton
var texture_buttons: Dictionary = {}
var texture_size_x_spins: Dictionary = {}
var texture_size_y_spins: Dictionary = {}
var save_name_edit: LineEdit
var status_label: Label
var editor_scroll: ScrollContainer

func _ready() -> void:
	if room_data == null:
		var parent_value: Variant = get_parent().get("room_data") if get_parent() != null else null
		if parent_value is RoomData:
			room_data = parent_value
	if room_data == null:
		room_data = RoomData.new()

	_create_model_builder_helper()
	_create_renderer()
	_create_context_menu()
	_create_editor_dialog()
	_create_save_dialog()
	_create_texture_dialog()
	_create_status_dialog()
	_sync_renderer()
	set_process_unhandled_input(false)
	_update_debug_state()


func set_room_data(new_room_data: RoomData) -> void:
	if new_room_data == null:
		return
	if room_data != null and room_data.changed.is_connected(_on_room_changed):
		room_data.changed.disconnect(_on_room_changed)
	room_data = new_room_data
	selected_object = null
	if not room_data.changed.is_connected(_on_room_changed):
		room_data.changed.connect(_on_room_changed)
	if model_builder_helper != null:
		model_builder_helper.set_room_data(room_data)
	_sync_renderer()


func _create_model_builder_helper() -> void:
	model_builder_helper = ObjectModelBuilderHelper.new()
	model_builder_helper.setup(self, room_data)


func _create_renderer() -> void:
	object_renderer = ObjectRenderer.new()
	object_renderer.name = "ObjectRenderer"
	object_renderer.z_index = 2
	add_child(object_renderer)
	object_renderer.set_room(room_data)
	object_renderer.set_selected_object(null)

	iso_object_renderer = IsoObjectRenderer.new()
	iso_object_renderer.name = "IsoObjectRenderer"
	iso_object_renderer.z_index = 3
	add_child(iso_object_renderer)
	iso_object_renderer.set_room(room_data)
	iso_object_renderer.set_selected_object(null)

	object_model_renderer = ModelRenderer.new()
	object_model_renderer.name = "ObjectModelRenderer"
	object_model_renderer.z_index = 4
	add_child(object_model_renderer)
	object_model_renderer.visible = true

	if not room_data.changed.is_connected(_on_room_changed):
		room_data.changed.connect(_on_room_changed)


func _sync_renderer() -> void:
	if object_renderer != null:
		object_renderer.set_room(room_data)
		object_renderer.set_selected_object(selected_object)
		object_renderer.queue_redraw()
	if iso_object_renderer != null:
		iso_object_renderer.set_room(room_data)
		iso_object_renderer.set_selected_object(selected_object)
		iso_object_renderer.queue_redraw()
	if object_model_renderer != null:
		object_model_renderer.set_object_models(_get_custom_model_objects(), selected_object)
		object_model_renderer.queue_redraw()


func _get_custom_model_objects() -> Array[ObjectData]:
	var result: Array[ObjectData] = []
	if room_data == null:
		return result
	for object_data in room_data.objects:
		if object_data != null and object_data.object_model != null:
			result.append(object_data)
	return result


func _on_room_changed() -> void:
	if selected_object != null and not room_data.has_object(selected_object):
		if model_builder_helper != null:
			model_builder_helper.clear_active_object()
		selected_object = null
	if model_builder_helper != null:
		model_builder_helper.validate_active_model()
	_sync_renderer()


# ObjectBuilder is an API when hosted by RoomBuilder. It does not consume
# viewport input itself; RoomBuilderInput routes clicks here explicitly.
func _unhandled_input(_event: InputEvent) -> void:
	pass


func _editor_is_active() -> bool:
	return enabled and debug_mode and room_data != null and object_renderer != null


func _update_debug_state() -> void:
	# Input is routed by RoomBuilderInput; ObjectBuilder itself is API-only.
	set_process_unhandled_input(false)
	if model_builder_helper != null:
		model_builder_helper.set_enabled(debug_mode and enabled)
	if debug_mode:
		if is_instance_valid(object_model_renderer):
			object_model_renderer.visible = true
		return

	selected_object = null
	if is_instance_valid(object_renderer):
		object_renderer.clear_selection()
	if is_instance_valid(iso_object_renderer):
		iso_object_renderer.clear_selection()
	if is_instance_valid(object_model_renderer):
		object_model_renderer.visible = false
	if is_instance_valid(context_menu):
		context_menu.hide()
	if is_instance_valid(load_menu):
		load_menu.hide()
	if is_instance_valid(insert_model_menu):
		insert_model_menu.hide()
	if is_instance_valid(editor_dialog):
		editor_dialog.hide()
	if is_instance_valid(save_dialog):
		save_dialog.hide()
	if is_instance_valid(texture_dialog):
		texture_dialog.hide()
	if model_builder_helper != null:
		model_builder_helper.set_enabled(false)


## ------------------------------------------------------------------------
## RoomBuilder API

func set_debug_mode(value: bool) -> void:
	debug_mode = value

func set_render_mode(isometric: bool, projector: IsoWallRenderer = null, duration: float = 0.22) -> void:
	if not is_instance_valid(object_renderer) or not is_instance_valid(iso_object_renderer):
		return

	if projector != null:
		iso_object_renderer.set_view_from_projector(projector)
		if object_model_renderer != null:
			object_model_renderer.set_view_from_projector(projector)

	var target_regular := 0.0 if isometric else 1.0
	var target_iso := 1.0 if isometric else 0.0
	if duration <= 0.0:
		object_renderer.modulate.a = target_regular
		iso_object_renderer.modulate.a = target_iso
		if object_model_renderer != null:
			object_model_renderer.visible = debug_mode and target_iso > 0.0
			object_model_renderer.modulate.a = target_iso
		return

	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(object_renderer, "modulate:a", target_regular, duration)
	tween.tween_property(iso_object_renderer, "modulate:a", target_iso, duration)
	if object_model_renderer != null:
		object_model_renderer.visible = debug_mode and target_iso > 0.0
		tween.tween_property(object_model_renderer, "modulate:a", target_iso, duration)

func sync_projection(projector: IsoWallRenderer) -> void:
	if projector == null:
		return
	if iso_object_renderer != null:
		iso_object_renderer.set_view_from_projector(projector)
		iso_object_renderer.queue_redraw()
	if object_model_renderer != null:
		object_model_renderer.set_view_from_projector(projector)
		object_model_renderer.queue_redraw()
	if model_builder_helper != null:
		model_builder_helper.sync_projection(projector)

func get_selected_object() -> ObjectData:
	return selected_object


func set_object_geometry(
		object: ObjectData,
		shape: ObjectData.BodyShape,
		has_corners: bool = true,
		curved_corners: bool = false,
		corner_radius_px: float = 4.0,
		height_px: float = 32.0,
		height_modifier_px: float = 0.0,
		top_style: ObjectData.TopRenderStyle = ObjectData.TopRenderStyle.FLAT,
		top_profile_height_px: float = 8.0,
		top_profile_segments: int = 8,
		opening_depth_px: float = 8.0) -> bool:
	if not _editor_is_active() or object == null or not room_data.has_object(object):
		return false
	object.body_shape = shape
	object.has_corners = has_corners
	object.curved_corners = curved_corners
	object.corner_radius_px = maxf(corner_radius_px, 0.0)
	object.height_px = maxf(height_px, 0.0)
	object.height_modifier_px = height_modifier_px
	object.top_render_style = top_style
	object.top_profile_height_px = maxf(top_profile_height_px, 0.0)
	object.top_profile_segments = clampi(top_profile_segments, 3, 32)
	object.opening_depth_px = maxf(opening_depth_px, 0.0)
	object.emit_changed()
	room_data.emit_changed()
	_sync_renderer()
	return true


func set_object_height(object: ObjectData, height_px: float) -> bool:
	if object == null or not room_data.has_object(object):
		return false
	object.set_height_px(height_px)
	_sync_renderer()
	return true


func set_height_modifier(object: ObjectData, modifier_px: float) -> bool:
	if object == null or not room_data.has_object(object):
		return false
	object.set_height_modifier_px(modifier_px)
	_sync_renderer()
	return true


func modify_height(object: ObjectData, delta_px: float) -> bool:
	if object == null or not room_data.has_object(object):
		return false
	object.height_modifier_px += delta_px
	object.emit_changed()
	room_data.emit_changed()
	_sync_renderer()
	return true


func select_object_at(world_point: Vector2, clear_when_empty: bool = true) -> ObjectData:
	if not _editor_is_active():
		return null
	return _select_at(world_point, clear_when_empty)

func open_context_menu_at(world_point: Vector2) -> void:
	if not _editor_is_active():
		return
	context_world_position = world_point
	_select_at(world_point, false)
	_open_context_menu()

func add_object_at(world_position: Vector2, open_editor: bool = true) -> ObjectData:
	if not _editor_is_active():
		return null
	context_world_position = world_position
	return _create_object_at(world_position, open_editor)

func open_load_menu_at(world_position: Vector2) -> void:
	if not _editor_is_active():
		return
	context_world_position = world_position
	_populate_load_menu()
	load_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8), Vector2i.ZERO))

## Opens the model move menu without changing the active ObjectData/model part.
## This is used when the user right-clicks while dragging a model part.
func open_model_move_context_at(world_position: Vector2) -> void:
	if not _editor_is_active() or model_builder_helper == null:
		return
	if not model_builder_helper.is_move_active():
		return

	context_world_position = world_position
	model_builder_helper.update_move_preview(world_position, true)
	context_menu.clear()
	model_builder_helper.populate_context_menu(context_menu)
	_append_take_model_context_menu()
	context_menu.position = Vector2i(get_viewport().get_mouse_position())
	context_menu.reset_size()
	context_menu.popup()
	call_deferred("_clamp_context_menu_to_viewport")

func has_object_at(world_point: Vector2) -> bool:
	if object_renderer == null:
		return false
	return object_renderer.pick_object(world_point) != null

func begin_model_create_mode(world_position: Vector2) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.begin_model_create_mode(world_position)

func update_model_create_preview(world_position: Vector2) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.update_model_create_preview(world_position)

func place_model_create_preview(world_position: Vector2) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.place_model_create_preview(world_position)

func handle_model_create_left_click(world_position: Vector2, additive_selection: bool = false) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.handle_model_create_left_click(world_position, additive_selection)

func update_model_create_hover(world_position: Vector2) -> void:
	if model_builder_helper != null:
		model_builder_helper.update_model_create_hover(world_position)

func combine_selected_workspace_models() -> ModelData:
	if model_builder_helper == null:
		return null
	return model_builder_helper.combine_selected_workspace_models()

func get_active_workspace_model() -> ModelData:
	if model_builder_helper == null:
		return null
	return model_builder_helper.get_selected_workspace_model()

func attach_workspace_model_to_object(object_data: ObjectData, model: ModelData = null) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.attach_workspace_model_to_object(object_data, model)

func move_model_create_preview_again(target_model: ModelData = null) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.move_model_create_preview_again(target_model)

func is_model_create_preview_active() -> bool:
	return model_builder_helper != null and model_builder_helper.is_model_create_preview_active()

func get_model_create_preview_model() -> ModelData:
	if model_builder_helper == null:
		return null
	return model_builder_helper.get_model_create_preview_model()

func pick_workspace_model_at(world_point: Vector2) -> ModelData:
	if model_builder_helper == null:
		return null
	return model_builder_helper.get_selected_workspace_model() if model_builder_helper.workspace_hovered_model == null else model_builder_helper.workspace_hovered_model

func begin_model_edit_mode(object_data: ObjectData = null) -> bool:
	if model_builder_helper == null:
		return false
	var target: ObjectData = object_data if object_data != null else selected_object
	return model_builder_helper.begin_model_edit_mode(target)

func is_model_create_mode_active() -> bool:
	return model_builder_helper != null and model_builder_helper.is_model_create_mode_active()

func is_model_edit_mode_active() -> bool:
	return model_builder_helper != null and model_builder_helper.is_model_edit_mode_active()

func is_model_mode_active() -> bool:
	return model_builder_helper != null and model_builder_helper.is_model_mode_active()

func exit_model_edit_mode() -> void:
	if model_builder_helper != null:
		model_builder_helper.exit_model_mode()

func open_model_edit_context_at(world_position: Vector2) -> void:
	if not _editor_is_active() or model_builder_helper == null:
		return
	if not model_builder_helper.is_model_mode_active():
		return

	context_world_position = world_position
	if model_builder_helper.is_model_edit_mode_active():
		model_builder_helper.select_part_at(world_position)
	else:
		model_builder_helper.model_create_world_position = world_position
		model_builder_helper.update_model_create_hover(world_position)
		model_builder_helper.set_workspace_context_model(model_builder_helper.workspace_hovered_model)

	context_menu.clear()
	model_builder_helper.populate_context_menu(context_menu)
	_append_take_model_context_menu()
	context_menu.position = Vector2i(get_viewport().get_mouse_position())
	context_menu.reset_size()
	context_menu.popup()
	call_deferred("_clamp_context_menu_to_viewport")

## ------------------------------------------------------------------------
## ObjectModelBuilder bridge API

func take_workspace_model_as_body(model: ModelData = null) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.take_workspace_model_as_body(model)


func take_workspace_model_as_model(model: ModelData = null) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.take_workspace_model_as_model(model)


func insert_saved_model_into_object(object_data: ObjectData, file_name: String) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.insert_saved_model_into_object(object_data, file_name)


func get_model_builder_helper() -> ObjectModelBuilderHelper:
	return model_builder_helper

func create_object_model(object_data: ObjectData = null, model_name: String = "Model") -> ModelData:
	if model_builder_helper == null:
		return null
	var target: ObjectData = object_data if object_data != null else selected_object
	return model_builder_helper.create_object_model(target, model_name)

func select_model_part_at(world_point: Vector2) -> ModelData:
	if model_builder_helper == null:
		return null
	return model_builder_helper.select_part_at(world_point)

func begin_model_part_move_at(world_point: Vector2) -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.begin_move_at(world_point)

func update_model_part_move_preview(world_point: Vector2, use_snapping: bool = true) -> Dictionary:
	if model_builder_helper == null:
		return {}
	return model_builder_helper.update_move_preview(world_point, use_snapping)

func commit_model_part_move() -> bool:
	if model_builder_helper == null:
		return false
	return model_builder_helper.commit_move()

func cancel_model_part_move() -> void:
	if model_builder_helper != null:
		model_builder_helper.cancel_move()

func is_model_part_move_active() -> bool:
	return model_builder_helper != null and model_builder_helper.is_move_active()

func get_model_move_preview() -> Dictionary:
	if model_builder_helper == null:
		return {}
	return model_builder_helper.get_move_preview()

func get_model_snap_candidates(world_point: Vector2) -> Array:
	if model_builder_helper == null:
		return []
	return model_builder_helper.get_snap_candidates_at(world_point)

func _select_at(world_point: Vector2, clear_when_empty: bool = true) -> ObjectData:
	var picked := object_renderer.pick_object(world_point) if object_renderer != null else null
	if picked != null:
		selected_object = picked
	elif clear_when_empty:
		selected_object = null
	if object_renderer != null:
		object_renderer.set_selected_object(selected_object)
		object_renderer.queue_redraw()
	if iso_object_renderer != null:
		iso_object_renderer.set_selected_object(selected_object)
		iso_object_renderer.queue_redraw()
	if model_builder_helper != null:
		model_builder_helper.set_active_object(selected_object)
		if selected_object != null:
			model_builder_helper.select_part_at(world_point)
	return selected_object


func _create_context_menu() -> void:
	# PopupMenu must live in canvas/UI space, not under the ObjectBuilder Node2D.
	context_menu_layer = CanvasLayer.new()
	context_menu_layer.name = "ObjectContextMenuLayer"
	context_menu_layer.layer = 100
	add_child(context_menu_layer)

	context_menu = PopupMenu.new()
	context_menu.name = "ObjectContextMenu"
	context_menu_layer.add_child(context_menu)
	context_menu.id_pressed.connect(_on_context_id_pressed)

	# All submenu PopupMenus used by context_menu should be children of
	# context_menu itself.
	load_menu = PopupMenu.new()
	load_menu.name = "LoadObjectMenu"
	context_menu.add_child(load_menu)
	load_menu.id_pressed.connect(_on_load_id_pressed)

	take_model_menu = PopupMenu.new()
	take_model_menu.name = "TakeModelIntoObjectMenu"
	context_menu.add_child(take_model_menu)
	take_model_menu.id_pressed.connect(_on_take_model_id_pressed)

	insert_model_menu = PopupMenu.new()
	insert_model_menu.name = "InsertModelMenu"
	context_menu.add_child(insert_model_menu)
	insert_model_menu.id_pressed.connect(_on_insert_model_id_pressed)
	insert_model_menu.about_to_popup.connect(_on_insert_model_menu_about_to_popup)

func _on_context_id_pressed(id: int) -> void:
	if not _editor_is_active():
		return

	# Give the model builder first chance to handle its own actions.
	if model_builder_helper != null and model_builder_helper.handle_context_action(id):
		return

	match id:
		1:
			_open_editor()

		2:
			_open_texture_editor()

		3:
			_move_selected_here()

		4:
			_open_save_dialog()

		5:
			_delete_selected()

		6:
			_create_object_at(context_world_position)

		7:
			selected_object = null

			if model_builder_helper != null:
				model_builder_helper.clear_active_object()

			if object_renderer != null:
				object_renderer.clear_selection()

			if iso_object_renderer != null:
				iso_object_renderer.clear_selection()

			if object_model_renderer != null:
				object_model_renderer.set_selected_object(null)
				object_model_renderer.queue_redraw()

		8, 9:
			# Informational disabled entries.
			pass

func _open_context_menu() -> void:
	if not _editor_is_active():
		return

	context_menu.clear()
	load_menu.clear()
	insert_model_menu.clear()
	take_model_menu.clear()

	var hovered: ObjectData = object_renderer.pick_object(context_world_position) if object_renderer != null else null

	if hovered != null:
		selected_object = hovered

		if object_renderer != null:
			object_renderer.set_selected_object(selected_object)

		if iso_object_renderer != null:
			iso_object_renderer.set_selected_object(selected_object)

		if model_builder_helper != null:
			model_builder_helper.set_active_object(selected_object)
			model_builder_helper.select_part_at(context_world_position)

		context_menu.add_item("Edit Selected Object", 1)
		context_menu.add_item("Edit Textures", 2)
		context_menu.add_item("Move Selected Here", 3)

		context_menu.add_separator()

		if hovered.can_store_objects():
			context_menu.add_item("Can Contain Objects", 8)
			var contain_info_index: int = context_menu.get_item_index(8)
			if contain_info_index >= 0:
				context_menu.set_item_disabled(contain_info_index, true)
		else:
			context_menu.add_item("Cannot Place Object On Top", 9)
			var blocked_info_index: int = context_menu.get_item_index(9)
			if blocked_info_index >= 0:
				context_menu.set_item_disabled(blocked_info_index, true)

		context_menu.add_separator()

		# ------------------------------------------------------------
		# Saved-model insertion
		# ------------------------------------------------------------
		_populate_insert_model_menu()

		var insert_label: String = "Replace Model" if hovered.has_custom_model() else "Insert Model"
		context_menu.add_submenu_node_item(insert_label, insert_model_menu)

		context_menu.add_separator()

		context_menu.add_item("Save Selected Object", 4)
		context_menu.add_item("Delete Selected Object", 5)

	else:
		selected_object = null

		if object_renderer != null:
			object_renderer.set_selected_object(null)

		if iso_object_renderer != null:
			iso_object_renderer.set_selected_object(null)

		if model_builder_helper != null:
			model_builder_helper.clear_active_object()

		context_menu.add_item("Create Object Here", 6)
		context_menu.add_item("Move Selected Here", 3)

	# ------------------------------------------------------------
	# Restore the Load submenu after context_menu.clear()
	# ------------------------------------------------------------
	_populate_load_menu()
	context_menu.add_separator()
	context_menu.add_submenu_node_item("Load Object Here", load_menu)

	# ------------------------------------------------------------
	# Existing model-builder context actions
	# ------------------------------------------------------------
	if model_builder_helper != null:
		model_builder_helper.set_active_object(selected_object)

		if selected_object != null:
			model_builder_helper.select_part_at(context_world_position)

		model_builder_helper.populate_context_menu(context_menu)

		# We now own the saved-model insertion menu, so remove the
		# helper's old "Insert Model" action if it added one.
		var old_insert_index: int = context_menu.get_item_index(
			ObjectModelBuilderHelper.ACTION_CREATE_MODEL
		)

		if old_insert_index >= 0:
			context_menu.remove_item(old_insert_index)

		_append_take_model_context_menu()

	context_menu.add_separator()
	context_menu.add_item("Clear Selection", 7)

	var has_selection: bool = (
		selected_object != null
		and room_data != null
		and room_data.has_object(selected_object)
	)

	var move_index: int = context_menu.get_item_index(3)
	if move_index >= 0:
		context_menu.set_item_disabled(move_index, not has_selection)

	var save_index: int = context_menu.get_item_index(4)
	if save_index >= 0:
		context_menu.set_item_disabled(save_index, not has_selection)

	var delete_index: int = context_menu.get_item_index(5)
	if delete_index >= 0:
		context_menu.set_item_disabled(delete_index, not has_selection)

	context_menu.position = Vector2i(get_viewport().get_mouse_position())
	context_menu.reset_size()
	context_menu.popup()

	call_deferred("_clamp_context_menu_to_viewport")


func _on_insert_model_menu_about_to_popup() -> void:
	_populate_insert_model_menu()


func _populate_insert_model_menu() -> void:
	if insert_model_menu == null:
		return

	insert_model_files = _get_saved_model_asset_files()
	insert_model_menu.clear()

	if insert_model_files.is_empty():
		insert_model_menu.add_item("No saved models", ACTION_INSERT_SAVED_MODEL_BASE)
		insert_model_menu.set_item_disabled(0, true)
		return

	for index: int in range(insert_model_files.size()):
		var relative_path: String = insert_model_files[index]
		var item_id: int = ACTION_INSERT_SAVED_MODEL_BASE + index
		insert_model_menu.add_item(relative_path.get_basename(), item_id)
		var item_index: int = insert_model_menu.get_item_index(item_id)
		if item_index >= 0:
			insert_model_menu.set_item_tooltip(item_index, MODEL_SAVE_DIR + relative_path)


func _get_saved_model_asset_files() -> Array[String]:
	var result: Array[String] = []
	_collect_saved_model_asset_files_recursive(MODEL_SAVE_DIR, result)
	result.sort()
	return result


func _collect_saved_model_asset_files_recursive(directory_path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path: String = directory_path.trim_suffix("/") + "/" + file_name
			if directory.current_is_dir():
				_collect_saved_model_asset_files_recursive(full_path, result)
			elif file_name.get_extension().to_lower() == "tres":
				var model_resource: ModelData = ResourceLoader.load(full_path) as ModelData
				if model_resource != null:
					result.append(full_path.trim_prefix(MODEL_SAVE_DIR))
		file_name = directory.get_next()
	directory.list_dir_end()


func _on_insert_model_id_pressed(id: int) -> void:
	if not _editor_is_active() or model_builder_helper == null:
		return

	var file_index: int = id - ACTION_INSERT_SAVED_MODEL_BASE
	if file_index < 0 or file_index >= insert_model_files.size():
		return
	if selected_object == null or not room_data.has_object(selected_object):
		_show_status("Select an object before inserting a model.")
		return

	var file_name: String = insert_model_files[file_index]
	model_builder_helper.insert_saved_model_into_object(selected_object, file_name)
	_sync_renderer()


func _append_take_model_context_menu() -> void:
	if take_model_menu == null or model_builder_helper == null:
		return
	if not model_builder_helper.is_model_create_mode_active():
		return

	var target: ModelData = model_builder_helper.workspace_context_model
	if target == null:
		target = model_builder_helper.workspace_hovered_model
	if target == null or not model_builder_helper.workspace_models.has(target):
		return

	take_model_menu.clear()
	take_model_menu.add_item("As Body", ACTION_TAKE_MODEL_AS_BODY)
	take_model_menu.add_item("As-Is Model", ACTION_TAKE_MODEL_AS_MODEL)
	context_menu.add_submenu_node_item("Take Model into Object", take_model_menu)


func _on_take_model_id_pressed(id: int) -> void:
	if not _editor_is_active() or model_builder_helper == null:
		return
	if not model_builder_helper.is_model_create_mode_active():
		return

	var target: ModelData = model_builder_helper.workspace_context_model
	if target == null:
		target = model_builder_helper.workspace_hovered_model
	if target == null or not model_builder_helper.workspace_models.has(target):
		_show_status("No workspace model is selected.")
		return

	match id:
		ACTION_TAKE_MODEL_AS_BODY:
			model_builder_helper.take_workspace_model_as_body(target)
		ACTION_TAKE_MODEL_AS_MODEL:
			model_builder_helper.take_workspace_model_as_model(target)

func _populate_load_menu() -> void:
	if load_menu == null:
		return

	load_menu.clear()

	var files: Array[String] = _get_saved_object_files()

	if files.is_empty():
		load_menu.add_item("No loadable ObjectData found", 0)
		load_menu.set_item_disabled(0, true)
		return

	for index in files.size():
		var path: String = files[index]
		var display_name: String = path.get_file().get_basename()

		load_menu.add_item(display_name, index + 1)

		# Keep the full resource path attached to the menu item.
		load_menu.set_item_metadata(index, path)


func _get_saved_object_files() -> Array[String]:
	var result: Array[String] = []

	_collect_saved_object_files(SAVE_DIR, result)

	result.sort()
	return result


func _collect_saved_object_files(directory_path: String, result: Array[String]) -> void:
	var entries: PackedStringArray = ResourceLoader.list_directory(directory_path)

	for raw_entry in entries:
		var entry: String = str(raw_entry)

		# ResourceLoader.list_directory() marks directories with "/".
		if entry.ends_with("/"):
			var child_directory: String = directory_path.path_join(
				entry.trim_suffix("/")
			)

			_collect_saved_object_files(child_directory, result)
			continue

		# We only want Godot resource files.
		if entry.get_extension().to_lower() != "tres":
			continue

		var resource_path: String = directory_path.path_join(entry)

		# Only expose actual ObjectData resources.
		var resource: Resource = ResourceLoader.load(
			resource_path,
			"",
			ResourceLoader.CACHE_MODE_REUSE
		)

		if resource is ObjectData:
			result.append(resource_path)


func _on_load_id_pressed(id: int) -> void:
	if not _editor_is_active():
		return

	if id <= 0:
		return

	# Prefer the metadata attached when the menu was populated.
	if load_menu != null:
		var item_index: int = load_menu.get_item_index(id)

		if item_index >= 0:
			var metadata: Variant = load_menu.get_item_metadata(item_index)

			if metadata != null:
				var resource_path: String = str(metadata)

				if not resource_path.is_empty():
					_load_object_at(resource_path, context_world_position)
					return

	# Fallback in case the menu metadata is unavailable.
	var files: Array[String] = _get_saved_object_files()

	var array_index: int = id - 1

	if array_index < 0 or array_index >= files.size():
		return

	_load_object_at(files[array_index], context_world_position)


func _load_object_at(resource_path: String, world_position: Vector2) -> void:
	if not _editor_is_active():
		return

	var path: String = resource_path.strip_edges()

	if path.is_empty():
		return

	# Accept either:
	#   res://assets/.../object.tres
	# or:
	#   object.tres
	#
	# This keeps the function compatible with the older caller style.
	if not path.begins_with("res://"):
		path = SAVE_DIR.path_join(path)

	if not ResourceLoader.exists(path):
		_show_status("Object resource does not exist: %s" % path)
		return

	var loaded_resource: Resource = ResourceLoader.load(
		path,
		"",
		ResourceLoader.CACHE_MODE_REUSE
	)

	var loaded: ObjectData = loaded_resource as ObjectData

	if loaded == null:
		_show_status("Resource is not a valid ObjectData: %s" % path)
		return

	var object: ObjectData = loaded.duplicate(true) as ObjectData

	if object == null:
		_show_status("Could not duplicate ObjectData: %s" % path)
		return

	object.position = world_position

	if not _can_place_object(
		object.position,
		object.size_px,
		object.rotation_degrees,
		null
	):
		_show_status(
			"Cannot load object here: its occupied space overlaps another object."
		)
		return

	room_data.add_object(object)
	_select_object(object)

	_show_status(
		"Loaded %s." % object.object_name
	)

func _create_object_at(world_position: Vector2, open_editor: bool = true) -> ObjectData:
	if not _editor_is_active():
		return null
	var object := ObjectData.new()
	object.object_name = default_object_name
	object.position = world_position
	object.size_px = Vector2i(maxi(default_size_px.x, 1), maxi(default_size_px.y, 1))
	object.hp = maxf(default_hp, 0.0)
	object.carried_weight = maxf(default_carried_weight, 0.0)
	object.base_color = default_color
	object.body_shape = default_body_shape
	object.has_corners = default_has_corners
	object.curved_corners = default_curved_corners
	object.corner_radius_px = maxf(default_corner_radius_px, 0.0)
	object.height_px = maxf(default_height_px, 0.0)
	object.height_modifier_px = default_height_modifier_px
	object.top_render_style = default_top_render_style
	object.top_profile_height_px = maxf(default_top_profile_height_px, 0.0)
	object.top_profile_segments = clampi(default_top_profile_segments, 3, 32)
	object.opening_depth_px = maxf(default_opening_depth_px, 0.0)

	if not _can_place_object(object.position, object.size_px, object.rotation_degrees, null):
		_show_status("Cannot create object: its occupied space overlaps another object.")
		return null

	room_data.add_object(object)
	_select_object(object)
	if open_editor:
		_open_editor()
	return object


func _select_object(object: ObjectData) -> void:
	selected_object = object
	if object_renderer != null:
		object_renderer.set_selected_object(object)
		object_renderer.queue_redraw()
	if iso_object_renderer != null:
		iso_object_renderer.set_selected_object(object)
		iso_object_renderer.queue_redraw()
	if model_builder_helper != null:
		model_builder_helper.set_active_object(object)


func _move_selected_here() -> void:
	if not _editor_is_active():
		return
	if selected_object == null or not room_data.has_object(selected_object):
		return
	if not _can_place_object(context_world_position, selected_object.size_px, selected_object.rotation_degrees, selected_object):
		_show_status("Cannot move object here: its occupied space overlaps another object.")
		return
	selected_object.position = context_world_position
	selected_object.emit_changed()
	room_data.emit_changed()
	_sync_renderer()


func _delete_selected() -> void:
	if not _editor_is_active():
		return
	if selected_object == null:
		return
	var deleted_name := selected_object.object_name
	if model_builder_helper != null:
		model_builder_helper.clear_object_model(selected_object)
	room_data.remove_object(selected_object)
	selected_object = null
	_sync_renderer()
	_show_status("Deleted %s." % deleted_name)


func _can_place_object(position: Vector2, size: Vector2i, rotation_degrees: float, excluded: ObjectData) -> bool:
	var candidate := _occupied_aabb(position, size, rotation_degrees)
	for object in room_data.objects:
		if object == null or object == excluded:
			continue
		var existing := _occupied_aabb(object.position, object.size_px, object.rotation_degrees)
		if _strict_rect_overlap(candidate, existing):
			return false
	return true


func _occupied_aabb(position: Vector2, size: Vector2i, rotation_degrees: float) -> Rect2:
	var half := Vector2(size) * 0.5
	var radians := deg_to_rad(rotation_degrees)
	var c := absf(cos(radians))
	var s := absf(sin(radians))
	var extent := Vector2(
		c * half.x + s * half.y,
		s * half.x + c * half.y
	)
	return Rect2(position - extent, extent * 2.0)


func _strict_rect_overlap(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - EPSILON \
		and a.end.x > b.position.x + EPSILON \
		and a.position.y < b.end.y - EPSILON \
		and a.end.y > b.position.y + EPSILON


# -------------------------------------------------------------------------
# Property editor

func _create_editor_dialog() -> void:
	editor_dialog = ConfirmationDialog.new()
	editor_dialog.name = "ObjectEditor"
	editor_dialog.title = "Edit Object"
	editor_dialog.ok_button_text = "Apply"
	editor_dialog.cancel_button_text = "Cancel"
	editor_dialog.size = Vector2i(620, 560)
	editor_dialog.min_size = Vector2i(320, 240)
	add_child(editor_dialog)
	editor_dialog.confirmed.connect(_apply_editor)
	editor_dialog.size_changed.connect(_resize_editor_dialog_content)

	editor_scroll = ScrollContainer.new()
	editor_scroll.name = "EditorScroll"
	editor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor_dialog.add_child(editor_scroll)

	var root := VBoxContainer.new()
	root.custom_minimum_size.x = 560.0
	root.add_theme_constant_override("separation", 8)
	editor_scroll.add_child(root)

	name_edit = _add_line(root, "Name")
	description_edit = TextEdit.new()
	description_edit.custom_minimum_size.y = 70.0
	root.add_child(_label("Description"))
	root.add_child(description_edit)

	root.add_child(_label("Placement"))
	position_x_spin = _add_spin(root, "Position X", -100000.0, 100000.0, 1.0)
	position_y_spin = _add_spin(root, "Position Y", -100000.0, 100000.0, 1.0)
	size_x_spin = _add_spin(root, "Size X", 1.0, 100000.0, 1.0)
	size_y_spin = _add_spin(root, "Size Y", 1.0, 100000.0, 1.0)
	rotation_spin = _add_spin(root, "Rotation", -360.0, 360.0, 1.0)

	root.add_child(_label("ISO Geometry"))
	body_shape_button = OptionButton.new()
	for body_shape in [ObjectData.BodyShape.RECTANGULAR, ObjectData.BodyShape.ROUNDED_CORNERS, ObjectData.BodyShape.CYLINDER]:
		body_shape_button.add_item(_body_shape_name(body_shape), body_shape)
	root.add_child(_labeled_control("Body Shape", body_shape_button))
	has_corners_check = _add_check(root, "Has Corners")
	curved_corners_check = _add_check(root, "Curved Corners")
	corner_radius_spin = _add_spin(root, "Corner Radius", 0.0, 4096.0, 1.0)
	height_spin = _add_spin(root, "Height", 0.0, 100000.0, 1.0)
	height_modifier_spin = _add_spin(root, "Height Modifier", -100000.0, 100000.0, 1.0)
	top_render_style_button = OptionButton.new()
	for top_style in [ObjectData.TopRenderStyle.FLAT, ObjectData.TopRenderStyle.CURVE_OUTWARD, ObjectData.TopRenderStyle.CURVE_INWARD, ObjectData.TopRenderStyle.OPEN, ObjectData.TopRenderStyle.POINT_OUTWARD, ObjectData.TopRenderStyle.POINT_INWARD]:
		top_render_style_button.add_item(_top_render_style_name(top_style), top_style)
	root.add_child(_labeled_control("Top Render Style", top_render_style_button))
	top_profile_height_spin = _add_spin(root, "Top Profile Height", 0.0, 100000.0, 1.0)
	top_profile_segments_spin = _add_spin(root, "Top Profile Segments", 3.0, 32.0, 1.0)
	opening_depth_spin = _add_spin(root, "Opening Depth", 0.0, 100000.0, 1.0)

	root.add_child(_label("Physical"))
	hp_spin = _add_spin(root, "HP", 0.0, 1000000.0, 1.0)
	weight_spin = _add_spin(root, "Carried Weight", 0.0, 1000000.0, 0.1)

	root.add_child(_label("Carry"))
	carry_check = _add_check(root, "Can Be Carried")
	hands_spin = _add_spin(root, "Required Hands", 1.0, 2.0, 1.0)
	throw_check = _add_check(root, "Can Be Thrown")
	throw_force_spin = _add_spin(root, "Throw Force", 0.0, 1000000.0, 1.0)
	throw_damage_spin = _add_spin(root, "Throw Damage Multiplier", 0.0, 100.0, 0.05)

	root.add_child(_label("Breaking"))
	break_check = _add_check(root, "Is Breakable")
	break_impact_check = _add_check(root, "Break On Throw Impact")
	break_type_button = OptionButton.new()
	for break_type in [ObjectData.BreakType.SHATTER, ObjectData.BreakType.SPLINTER, ObjectData.BreakType.CRUSH, ObjectData.BreakType.CHIP]:
		break_type_button.add_item(_break_type_name(break_type), break_type)
	root.add_child(_label("Break Type"))
	root.add_child(break_type_button)

	root.add_child(_label("Containment / Interaction"))
	contain_check = _add_check(root, "Can Contain Objects")
	interaction_paths_edit = _add_line(root, "Interaction Scripts (; separated res:// paths)")

	root.add_child(_label("Appearance"))
	color_button = ColorPickerButton.new()
	color_button.custom_minimum_size = Vector2(0, 32)
	root.add_child(_labeled_control("Base Color", color_button))

	root.add_child(_label("Construction Sizes"))
	var size_help := _label("Texture slots are optional. A middle texture may stand alone; corners and edges may be mixed or omitted.")
	size_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(size_help)
	uniform_texture_size_check = _add_check(root, "Use One Size For All Textures")
	uniform_texture_size_check.toggled.connect(_on_uniform_texture_size_toggled)
	uniform_texture_size_x_spin = _add_spin(root, "All Texture Width", 1.0, 1024.0, 1.0)
	uniform_texture_size_y_spin = _add_spin(root, "All Texture Height", 1.0, 1024.0, 1.0)

	# Keep the old common controls visible for compatibility with existing
	# ObjectData while the newer per-slot sizing UI drives the actual values.
	corner_size_x_spin = _add_spin(root, "Legacy Corner Width", 1.0, 512.0, 1.0)
	corner_size_y_spin = _add_spin(root, "Legacy Corner Height", 1.0, 512.0, 1.0)
	middle_tile_x_spin = _add_spin(root, "Legacy Middle Tile X", 1.0, 1024.0, 1.0)
	middle_tile_y_spin = _add_spin(root, "Legacy Middle Tile Y", 1.0, 1024.0, 1.0)

	_resize_editor_dialog_content()


func _resize_editor_dialog_content() -> void:
	if not is_instance_valid(editor_dialog) or not is_instance_valid(editor_scroll):
		return
	var window_size := editor_dialog.size
	const MARGIN := 10
	const BUTTON_AREA_HEIGHT := 56
	editor_scroll.position = Vector2(MARGIN, MARGIN)
	editor_scroll.size = Vector2(
		maxf(float(window_size.x - MARGIN * 2), 1.0),
		maxf(float(window_size.y - MARGIN * 2 - BUTTON_AREA_HEIGHT), 1.0)
	)


func _open_editor() -> void:
	if not _editor_is_active():
		return
	if selected_object == null or not room_data.has_object(selected_object):
		_show_status("Select one object before editing.")
		return

	var object := selected_object
	name_edit.text = object.object_name
	description_edit.text = object.description
	position_x_spin.value = object.position.x
	position_y_spin.value = object.position.y
	size_x_spin.value = object.size_px.x
	size_y_spin.value = object.size_px.y
	rotation_spin.value = object.rotation_degrees
	body_shape_button.select(object.body_shape)
	has_corners_check.button_pressed = object.has_corners
	curved_corners_check.button_pressed = object.curved_corners
	corner_radius_spin.value = object.corner_radius_px
	height_spin.value = object.height_px
	height_modifier_spin.value = object.height_modifier_px
	top_render_style_button.select(object.top_render_style)
	top_profile_height_spin.value = object.top_profile_height_px
	top_profile_segments_spin.value = object.top_profile_segments
	opening_depth_spin.value = object.opening_depth_px
	hp_spin.value = object.hp
	weight_spin.value = object.carried_weight
	carry_check.button_pressed = object.can_be_carried
	hands_spin.value = clampi(object.required_hands, 1, 2)
	throw_check.button_pressed = object.can_be_thrown
	throw_force_spin.value = object.throw_force
	throw_damage_spin.value = object.throw_damage_multiplier
	break_check.button_pressed = object.is_breakable
	break_impact_check.button_pressed = object.can_break_on_throw_impact
	break_type_button.select(object.break_type)
	contain_check.button_pressed = object.can_contain_objects
	interaction_paths_edit.text = _script_paths_to_text(object.interaction_scripts)
	color_button.color = object.base_color
	corner_size_x_spin.value = object.corner_size_px.x
	corner_size_y_spin.value = object.corner_size_px.y
	middle_tile_x_spin.value = object.middle_tile_size_px.x
	middle_tile_y_spin.value = object.middle_tile_size_px.y
	uniform_texture_size_check.button_pressed = object.use_uniform_texture_size
	uniform_texture_size_x_spin.value = object.uniform_texture_size_px.x
	uniform_texture_size_y_spin.value = object.uniform_texture_size_px.y
	_sync_texture_size_controls(object)
	_popup_window_fitted(editor_dialog, Vector2i(760, 760), Vector2i(320, 240))
	call_deferred("_resize_editor_dialog_content")


func _apply_editor() -> void:
	if not _editor_is_active():
		return
	if selected_object == null or not room_data.has_object(selected_object):
		return

	var new_position := Vector2(position_x_spin.value, position_y_spin.value)
	var new_size := Vector2i(
		maxi(int(size_x_spin.value), 1),
		maxi(int(size_y_spin.value), 1)
	)
	var new_rotation := float(rotation_spin.value)

	if not _can_place_object(new_position, new_size, new_rotation, selected_object):
		_show_status("Object was not changed: the new footprint overlaps another object.")
		return

	var object := selected_object
	object.object_name = name_edit.text.strip_edges()
	if object.object_name.is_empty():
		object.object_name = "Object"
	object.description = description_edit.text
	object.position = new_position
	object.size_px = new_size
	object.rotation_degrees = new_rotation
	object.body_shape = body_shape_button.get_selected_id()
	object.has_corners = has_corners_check.button_pressed
	object.curved_corners = curved_corners_check.button_pressed
	object.corner_radius_px = maxf(float(corner_radius_spin.value), 0.0)
	object.height_px = maxf(float(height_spin.value), 0.0)
	object.height_modifier_px = float(height_modifier_spin.value)
	object.top_render_style = top_render_style_button.get_selected_id()
	object.top_profile_height_px = maxf(float(top_profile_height_spin.value), 0.0)
	object.top_profile_segments = clampi(int(top_profile_segments_spin.value), 3, 32)
	object.opening_depth_px = maxf(float(opening_depth_spin.value), 0.0)
	object.hp = maxf(float(hp_spin.value), 0.0)
	object.carried_weight = maxf(float(weight_spin.value), 0.0)
	object.can_be_carried = carry_check.button_pressed
	object.required_hands = clampi(int(hands_spin.value), 1, 2)
	object.can_be_thrown = throw_check.button_pressed
	object.throw_force = maxf(float(throw_force_spin.value), 0.0)
	object.throw_damage_multiplier = maxf(float(throw_damage_spin.value), 0.0)
	object.is_breakable = break_check.button_pressed
	object.can_break_on_throw_impact = break_impact_check.button_pressed
	object.break_type = break_type_button.get_selected_id()
	object.can_contain_objects = contain_check.button_pressed
	object.base_color = color_button.color
	object.corner_size_px = Vector2i(
		maxi(int(corner_size_x_spin.value), 1),
		maxi(int(corner_size_y_spin.value), 1)
	)
	object.middle_tile_size_px = Vector2(
		maxf(float(middle_tile_x_spin.value), 1.0),
		maxf(float(middle_tile_y_spin.value), 1.0)
	)
	object.use_uniform_texture_size = uniform_texture_size_check.button_pressed
	object.uniform_texture_size_px = Vector2(
		maxf(float(uniform_texture_size_x_spin.value), 1.0),
		maxf(float(uniform_texture_size_y_spin.value), 1.0)
	)
	for slot in texture_buttons.keys():
		var size := Vector2(
			maxf(float(texture_size_x_spins[slot].value), 1.0),
			maxf(float(texture_size_y_spins[slot].value), 1.0)
		)
		object.texture_size_overrides[slot] = size
	if object.use_uniform_texture_size:
		object.corner_size_px = Vector2i(
			maxi(roundi(object.uniform_texture_size_px.x), 1),
			maxi(roundi(object.uniform_texture_size_px.y), 1)
		)
		object.middle_tile_size_px = object.uniform_texture_size_px
	else:
		var middle_size := object.get_texture_size("middle")
		object.middle_tile_size_px = middle_size
		var tl_size := object.get_texture_size("corner_top_left")
		object.corner_size_px = Vector2i(maxi(roundi(tl_size.x), 1), maxi(roundi(tl_size.y), 1))
	object.interaction_scripts = _load_script_paths(interaction_paths_edit.text)
	object.emit_changed()
	room_data.emit_changed()
	_sync_renderer()
	_show_status("Updated %s." % object.object_name)


func _on_uniform_texture_size_toggled(pressed: bool) -> void:
	if not is_instance_valid(uniform_texture_size_x_spin):
		return
	uniform_texture_size_x_spin.editable = pressed
	uniform_texture_size_y_spin.editable = pressed
	for slot in texture_size_x_spins.keys():
		texture_size_x_spins[slot].editable = not pressed
		texture_size_y_spins[slot].editable = not pressed
# -------------------------------------------------------------------------
# Texture editor

func _create_texture_dialog() -> void:
	texture_dialog = ConfirmationDialog.new()
	texture_dialog.name = "ObjectTextureEditor"
	texture_dialog.title = "Edit Object Face Textures"
	texture_dialog.ok_button_text = "Apply"
	texture_dialog.size = Vector2i(700, 600)
	add_child(texture_dialog)
	texture_dialog.confirmed.connect(_apply_textures)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_dialog.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	var help := _label("Choose a face target. Each face has its own corners, edges, and middle texture. Bottom textures are disabled by default.")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(help)

	texture_face_button = OptionButton.new()
	root.add_child(_labeled_control("Face Target", texture_face_button))
	for target in _texture_face_targets():
		texture_face_button.add_item(_texture_face_target_label(target), target)
	texture_face_button.item_selected.connect(_on_texture_face_target_selected)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_child(_label("Texture Slot"))
	grid.add_child(_label("Texture"))
	grid.add_child(_label("Width"))
	grid.add_child(_label("Height"))
	root.add_child(grid)

	for slot in _texture_slots():
		grid.add_child(_label(_texture_slot_label(slot)))

		var button := OptionButton.new()
		button.custom_minimum_size.x = 260.0
		texture_buttons[slot] = button
		grid.add_child(button)

		var size_x := SpinBox.new()
		size_x.min_value = 1.0
		size_x.max_value = 1024.0
		size_x.step = 1.0
		size_x.allow_greater = true
		size_x.allow_lesser = true
		texture_size_x_spins[slot] = size_x
		grid.add_child(size_x)

		var size_y := SpinBox.new()
		size_y.min_value = 1.0
		size_y.max_value = 1024.0
		size_y.step = 1.0
		size_y.allow_greater = true
		size_y.allow_lesser = true
		texture_size_y_spins[slot] = size_y
		grid.add_child(size_y)


func _open_texture_editor() -> void:
	if not _editor_is_active():
		return
	if selected_object == null or not room_data.has_object(selected_object):
		_show_status("Select one object before editing textures.")
		return
	var object := selected_object
	if texture_face_button.selected < 0:
		texture_face_button.select(ObjectFaceTextureData.FaceTarget.FRONT)
	_refresh_texture_dropdowns(object)
	_sync_texture_size_controls(object)
	_popup_window_fitted(texture_dialog, Vector2i(800, 680), Vector2i(520, 320))


func _apply_textures() -> void:
	if not _editor_is_active():
		return
	if selected_object == null or not room_data.has_object(selected_object):
		return
	var object := selected_object
	var face_data := _selected_face_texture_data(object)
	if face_data == null:
		return

	for slot in texture_buttons.keys():
		var texture := _texture_from_button(texture_buttons[slot])
		face_data.set_texture(slot, texture)
		var size := Vector2(
			maxf(float(texture_size_x_spins[slot].value), 1.0),
			maxf(float(texture_size_y_spins[slot].value), 1.0)
		)
		face_data.texture_size_overrides[slot] = size

	face_data.texture_enabled = true
	face_data.use_uniform_texture_size = uniform_texture_size_check.button_pressed
	face_data.uniform_texture_size_px = Vector2(
		maxf(float(uniform_texture_size_x_spin.value), 1.0),
		maxf(float(uniform_texture_size_y_spin.value), 1.0)
	)
	if face_data.use_uniform_texture_size:
		for slot in _texture_slots():
			face_data.texture_size_overrides[slot] = face_data.uniform_texture_size_px

	face_data.emit_changed()
	object.emit_changed()
	room_data.emit_changed()
	_sync_renderer()


func _refresh_texture_dropdowns(object: ObjectData) -> void:
	var paths := _get_texture_paths()
	var face_data := _selected_face_texture_data(object)
	if face_data == null:
		return
	for slot in texture_buttons.keys():
		var button: OptionButton = texture_buttons[slot]
		button.clear()
		button.add_item("None")
		button.set_item_metadata(0, "")
		var wanted := _resource_path(face_data.get_texture(slot))
		var selected_index := 0
		for path in paths:
			button.add_item(path.get_file())
			var item_index := button.item_count - 1
			button.set_item_metadata(item_index, path)
			button.set_item_tooltip(item_index, path)
			if path == wanted:
				selected_index = item_index
		button.select(selected_index)


func _selected_face_texture_data(object: ObjectData) -> ObjectFaceTextureData:
	if object == null or texture_face_button == null or texture_face_button.selected < 0:
		return null
	var target_id: int = texture_face_button.get_item_id(texture_face_button.selected)
	return object.get_or_create_face_texture_set(target_id)


func _on_texture_face_target_selected(_index: int) -> void:
	if not is_instance_valid(texture_dialog) or not texture_dialog.visible:
		return
	if selected_object == null or not room_data.has_object(selected_object):
		return
	_refresh_texture_dropdowns(selected_object)
	_sync_texture_size_controls(selected_object)


func _get_texture_paths() -> Array[String]:
	var paths: Array[String] = []
	_collect_texture_paths(TEXTURE_DIR, paths)
	paths.sort()
	return paths


func _collect_texture_paths(directory_path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path := directory_path.trim_suffix("/") + "/" + file_name
			if directory.current_is_dir():
				_collect_texture_paths(full_path, result)
			else:
				var extension := file_name.get_extension().to_lower()
				if extension in ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]:
					var texture := ResourceLoader.load(full_path) as Texture2D
					if texture != null:
						result.append(full_path)
		file_name = directory.get_next()
	directory.list_dir_end()


func _sync_texture_size_controls(object: ObjectData) -> void:
	var face_data := _selected_face_texture_data(object)
	if face_data == null:
		return
	uniform_texture_size_check.button_pressed = face_data.use_uniform_texture_size
	uniform_texture_size_x_spin.value = face_data.uniform_texture_size_px.x
	uniform_texture_size_y_spin.value = face_data.uniform_texture_size_px.y
	_on_uniform_texture_size_toggled(face_data.use_uniform_texture_size)
	for slot in texture_buttons.keys():
		var size := face_data.get_texture_size(slot)
		texture_size_x_spins[slot].value = size.x
		texture_size_y_spins[slot].value = size.y


func _texture_from_button(button: OptionButton) -> Texture2D:
	if button == null or button.selected < 0:
		return null
	var path: String = str(button.get_item_metadata(button.selected))
	if path.is_empty():
		return null
	return ResourceLoader.load(path) as Texture2D


func _set_object_texture(object: ObjectData, slot: String, texture: Texture2D) -> void:
	var face_data := _selected_face_texture_data(object)
	if face_data != null:
		face_data.set_texture(slot, texture)


func _get_object_texture(object: ObjectData, slot: String) -> Texture2D:
	var face_data := _selected_face_texture_data(object)
	if face_data == null:
		return null
	return face_data.get_texture(slot)


func _texture_face_targets() -> Array[int]:
	return [
		ObjectFaceTextureData.FaceTarget.FRONT,
		ObjectFaceTextureData.FaceTarget.BACK,
		ObjectFaceTextureData.FaceTarget.LEFT,
		ObjectFaceTextureData.FaceTarget.RIGHT,
		ObjectFaceTextureData.FaceTarget.TOP,
		ObjectFaceTextureData.FaceTarget.BOTTOM,
	]


func _texture_face_target_label(target: int) -> String:
	match target:
		ObjectFaceTextureData.FaceTarget.FRONT: return "Front"
		ObjectFaceTextureData.FaceTarget.BACK: return "Back"
		ObjectFaceTextureData.FaceTarget.LEFT: return "Left"
		ObjectFaceTextureData.FaceTarget.RIGHT: return "Right"
		ObjectFaceTextureData.FaceTarget.TOP: return "Top"
		ObjectFaceTextureData.FaceTarget.BOTTOM: return "Bottom (off by default)"
	return "Unknown"


func _texture_slots() -> Array[String]:
	return [
		"corner_top_left", "corner_top_right", "corner_bottom_left", "corner_bottom_right",
		"edge_top", "edge_bottom", "edge_left", "edge_right", "middle"
	]


func _texture_slot_label(slot: String) -> String:
	match slot:
		"corner_top_left": return "Corner Top Left"
		"corner_top_right": return "Corner Top Right"
		"corner_bottom_left": return "Corner Bottom Left"
		"corner_bottom_right": return "Corner Bottom Right"
		"edge_top": return "Upper / Top"
		"edge_bottom": return "Lower / Bottom"
		"edge_left": return "Side Left"
		"edge_right": return "Side Right"
		"middle": return "Middle"
	return slot


func _on_texture_dialog_resized() -> void:
	_refresh_texture_dropdowns(selected_object)


func _load_texture_path(path: String) -> Texture2D:
	var clean := path.strip_edges()
	if clean.is_empty():
		return null
	return ResourceLoader.load(clean) as Texture2D


func _resource_path(resource: Resource) -> String:
	if resource == null:
		return ""
	return resource.resource_path

# -------------------------------------------------------------------------
# Saving

func _create_save_dialog() -> void:
	save_dialog = ConfirmationDialog.new()
	save_dialog.name = "SaveObjectDialog"
	save_dialog.title = "Save ObjectData"
	save_dialog.ok_button_text = "Save"
	save_dialog.size = Vector2i(460, 160)
	add_child(save_dialog)
	save_dialog.confirmed.connect(_save_selected)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save_dialog.add_child(root)
	root.add_child(_label("Save to res://assets/baked_tres/object_data/"))
	save_name_edit = LineEdit.new()
	root.add_child(save_name_edit)


func _open_save_dialog() -> void:
	if not _editor_is_active():
		return
	if selected_object == null or not room_data.has_object(selected_object):
		_show_status("Select one object before saving.")
		return
	save_name_edit.text = _sanitize_file_name(selected_object.object_name)
	save_dialog.popup_centered()


func _save_selected() -> void:
	if not _editor_is_active():
		return
	if selected_object == null or not room_data.has_object(selected_object):
		return
	var file_base := _sanitize_file_name(save_name_edit.text)
	if file_base.is_empty():
		_show_status("Invalid object filename.")
		return

	var absolute_dir := ProjectSettings.globalize_path(SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var path := SAVE_DIR + file_base + ".tres"
	var error := ResourceSaver.save(selected_object, path)
	if error != OK:
		_show_status("Failed to save %s (error %d)." % [path, error])
		return
	_show_status("Saved ObjectData to %s." % path)


func _sanitize_file_name(value: String) -> String:
	var result := value.strip_edges()
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	result = result.replace(":", "_")
	result = result.replace("*", "_")
	result = result.replace("?", "_")
	result = result.replace("\"", "_")
	result = result.replace("<", "_")
	result = result.replace(">", "_")
	result = result.replace("|", "_")
	return result


# -------------------------------------------------------------------------
# Small UI helpers

func _create_status_dialog() -> void:
	status_dialog = AcceptDialog.new()
	status_dialog.name = "ObjectStatus"
	status_dialog.title = "Object Builder"
	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(420, 80)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_dialog.add_child(status_label)
	add_child(status_dialog)


func _popup_window_fitted(window: Window, preferred_size: Vector2i, minimum_size: Vector2i) -> void:
	if window == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var available := Vector2i(
		maxi(int(viewport_size.x) - 32, 1),
		maxi(int(viewport_size.y) - 32, 1)
	)
	var clamped_minimum := Vector2i(
		mini(minimum_size.x, available.x),
		mini(minimum_size.y, available.y)
	)
	window.min_size = clamped_minimum
	var safe_size := Vector2i(
		clampi(preferred_size.x, clamped_minimum.x, available.x),
		clampi(preferred_size.y, clamped_minimum.y, available.y)
	)
	window.size = safe_size
	window.popup_centered()


func _clamp_context_menu_to_viewport() -> void:
	if not is_instance_valid(context_menu) or not context_menu.visible:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var menu_size := context_menu.size
	var margin := 8
	var max_x := maxi(int(viewport_size.x - menu_size.x - margin), margin)
	var max_y := maxi(int(viewport_size.y - menu_size.y - margin), margin)
	var position := context_menu.position
	position.x = clampi(position.x, margin, max_x)
	position.y = clampi(position.y, margin, max_y)
	context_menu.position = position


func _show_status(message: String) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_dialog.popup_centered()


func _label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label


func _add_line(parent: Container, label_text: String) -> LineEdit:
	var edit := LineEdit.new()
	parent.add_child(_labeled_control(label_text, edit))
	return edit


func _add_spin(parent: Container, label_text: String, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	parent.add_child(_labeled_control(label_text, spin))
	return spin


func _add_check(parent: Container, label_text: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = label_text
	parent.add_child(check)
	return check


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	box.add_child(control)
	return box


func _body_shape_name(value: ObjectData.BodyShape) -> String:
	match value:
		ObjectData.BodyShape.RECTANGULAR:
			return "Rectangular"
		ObjectData.BodyShape.ROUNDED_CORNERS:
			return "Rounded Corners"
		ObjectData.BodyShape.CYLINDER:
			return "Cylinder / Round"
	return "Unknown"


func _top_render_style_name(value: ObjectData.TopRenderStyle) -> String:
	match value:
		ObjectData.TopRenderStyle.FLAT:
			return "Flat"
		ObjectData.TopRenderStyle.CURVE_OUTWARD:
			return "Curving Outward"
		ObjectData.TopRenderStyle.CURVE_INWARD:
			return "Curving Inward"
		ObjectData.TopRenderStyle.OPEN:
			return "Open"
		ObjectData.TopRenderStyle.POINT_OUTWARD:
			return "Pointed Outward"
		ObjectData.TopRenderStyle.POINT_INWARD:
			return "Pointed Inward"
	return "Unknown"


func _break_type_name(value: ObjectData.BreakType) -> String:
	match value:
		ObjectData.BreakType.SHATTER:
			return "Shatter"
		ObjectData.BreakType.SPLINTER:
			return "Splinter"
		ObjectData.BreakType.CRUSH:
			return "Crush"
		ObjectData.BreakType.CHIP:
			return "Chip"
	return "Unknown"


func _script_paths_to_text(scripts: Array[Script]) -> String:
	var paths: Array[String] = []
	for script in scripts:
		if script != null and not script.resource_path.is_empty():
			paths.append(script.resource_path)
	return ";".join(paths)


func _load_script_paths(text_value: String) -> Array[Script]:
	var result: Array[Script] = []
	for raw_path in text_value.split(";", false):
		var path := raw_path.strip_edges()
		if path.is_empty():
			continue
		var script := ResourceLoader.load(path) as Script
		if script != null:
			result.append(script)
	return result
