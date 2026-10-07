class_name ObjectModelBuilderHelper
extends RefCounted

## Thin integration layer between ObjectBuilder and ObjectModelBuilder.
##
## ObjectBuilder remains responsible for ObjectData, existing object UI, and
## the object renderers. This helper owns model-editing state and translates
## context-menu / pointer calls into ObjectModelBuilder API calls.
##
## It intentionally has no dependency on RoomBuilder's grid. Callers provide
## flat-space coordinates obtained from the RoomBuilder/Grid pipeline.

signal model_changed(object_data: ObjectData, model: ModelData)
signal model_part_selected(object_data: ObjectData, part: ModelData)
signal move_preview_changed(object_data: ObjectData, part: ModelData, preview: Dictionary)
signal snap_candidates_changed(object_data: ObjectData, part: ModelData, candidates: Array)
signal part_texture_edit_requested(object_data: ObjectData, part: ModelData)
signal part_color_edit_requested(object_data: ObjectData, part: ModelData)

const ACTION_CREATE_MODEL: int = 100
const ACTION_EDIT_MODEL: int = 101
const ACTION_MOVE_PART: int = 102
const ACTION_DETACH_PART: int = 103
const ACTION_COMBINE_PARTS: int = 104
const ACTION_EDIT_PART_TEXTURES: int = 105
const ACTION_PAINT_PART: int = 106
const ACTION_CLEAR_MODEL: int = 107
const ACTION_EXIT_MODEL_MODE: int = 108
const ACTION_CREATE_MODEL_AT_CURSOR: int = 109
const ACTION_MOVE_MODEL_PREVIEW: int = 110
const ACTION_COMBINE_WORKSPACE_MODELS: int = 111
const ACTION_CREATE_NEW_MODEL: int = 112
const ACTION_MOVE_WORKSPACE_MODEL: int = 113
const ACTION_ATTACH_NEARBY_MODEL: int = 114
const ACTION_FREE_ATTACH_MODEL: int = 115
const ACTION_COPY_MODEL: int = 116
const ACTION_DELETE_WORKSPACE_MODEL: int = 117
const ACTION_EDIT_WORKSPACE_PART_BASE: int = 1000
const ACTION_RENDER_BEHIND: int = 140
const ACTION_RENDER_IN_FRONT: int = 141
const ACTION_RESET_RENDER_ORDER: int = 142
const ACTION_SAVE_WORKSPACE_MODEL: int = 150
const ACTION_TRANSPOSE_WORKSPACE_MODEL: int = 151
const ACTION_LOAD_WORKSPACE_MODEL_BASE: int = 1600
const ACTION_CONFIRM_FREE_ATTACH: int = 130
const ACTION_CANCEL_FREE_ATTACH: int = 131
const EPSILON: float = 0.01

enum EditMode {
	NONE,
	MODEL_CREATE,
	MODEL_EDIT,
}

const ACTION_CONFIRM_MOVE: int = 120
const ACTION_CANCEL_MOVE: int = 121
const ACTION_SNAP_TOP: int = 122
const ACTION_SNAP_FRONT: int = 123
const ACTION_SNAP_BACK: int = 124
const ACTION_SNAP_LEFT: int = 125
const ACTION_SNAP_RIGHT: int = 126

signal edit_mode_changed(mode: EditMode)

var host: Node = null
var room_data: RoomData = null
var api: ObjectModelBuilder
var active_object: ObjectData = null
var enabled: bool = true
var edit_mode: EditMode = EditMode.NONE
var model_create_world_position: Vector2 = Vector2.ZERO
var model_editor: ObjectModelEditor = null
var model_renderer: ModelRenderer = null
var model_create_model: ModelData = null
var model_create_preview_active: bool = false
var model_create_preview_position: Vector2 = Vector2.ZERO
var model_create_prompt: ConfirmationDialog = null
var model_create_prompt_position: Vector2 = Vector2.ZERO
var model_create_auto_stack_on_top: bool = false
var model_create_base_height_offset_px: float = 0.0
var insert_model_menu: PopupMenu
var insert_model_files: Array[String] = []

var workspace_models: Array[ModelData] = []
var workspace_positions: Dictionary = {}
var workspace_selected_models: Array[ModelData] = []
var workspace_hovered_model: ModelData = null
var workspace_context_model: ModelData = null

var workspace_combine_dialog: ConfirmationDialog = null
var workspace_combine_candidates: Array = []
var workspace_combine_choice: OptionButton = null

## Rebuilt each time the model-create context menu is populated. Each entry
## maps an action id to one nested workspace part for direct editing.
var workspace_context_part_edit_targets: Array[ModelData] = []

var free_attach_active: bool = false
var free_attach_source: ModelData = null
var free_attach_target: ModelData = null
var free_attach_original_position: Vector2 = Vector2.ZERO
var free_attach_preview_position: Vector2 = Vector2.ZERO
var free_attach_attach_on_top: bool = true
var free_attach_original_height_offset_px: float = 0.0
var free_attach_prompt: ConfirmationDialog = null
var free_attach_prompt_check: CheckButton = null

## Deep-copied model resource used by the workspace copy/paste action. The
## clipboard stays available after a paste so the same model can be pasted
## repeatedly with left-click until another model is copied or model mode exits.
var model_clipboard: ModelData = null

## Reusable model assets are stored as self-contained Godot Resource (.tres) files.
const MODEL_SAVE_DIR: String = "res://assets/baked_tres/model_data/"
var model_save_dialog: ConfirmationDialog = null
var model_save_name_edit: LineEdit = null
var model_load_menu: PopupMenu = null
var model_load_files: Array[String] = []


func setup(owner: Node, initial_room_data: RoomData) -> void:
	host = owner
	room_data = initial_room_data
	api = ObjectModelBuilder.new()
	var texture_directory_value: Variant = owner.get("model_texture_directory") if owner != null else null
	if texture_directory_value is String and not String(texture_directory_value).is_empty():
		if api.has_method("set_texture_loadout_directory"):
			api.call("set_texture_loadout_directory", String(texture_directory_value))
	api.model_changed.connect(_on_api_model_changed)
	api.selection_changed.connect(_on_api_selection_changed)
	api.move_preview_changed.connect(_on_api_move_preview_changed)
	api.snap_candidates_changed.connect(_on_api_snap_candidates_changed)
	model_renderer = ModelRenderer.new()
	model_renderer.name = "ModelRenderer"
	model_renderer.z_index = 6
	host.add_child(model_renderer)
	model_renderer.visible = false

	model_editor = ObjectModelEditor.new()
	model_editor.setup(owner, initial_room_data)
	if texture_directory_value is String and not String(texture_directory_value).is_empty():
		if model_editor.has_method("set_texture_directory"):
			model_editor.call("set_texture_directory", String(texture_directory_value))
	model_editor.applied.connect(_on_model_editor_applied)
	model_editor.cancelled.connect(_on_model_editor_cancelled)
	_create_model_create_prompt()
	_create_workspace_combine_dialog()
	_create_model_save_dialog()
	set_room_data(initial_room_data)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and api != null and api.moving_part != null:
		api.cancel_move()
	if not enabled and model_editor != null:
		model_editor.close()
	if not enabled and model_create_prompt != null:
		model_create_prompt.hide()
	if not enabled:
		exit_model_mode()


func set_room_data(new_room_data: RoomData) -> void:
	room_data = new_room_data
	if model_editor != null:
		model_editor.set_room_data(new_room_data)
	if api == null:
		return
	if active_object != null and room_data != null and room_data.has_object(active_object):
		set_active_object(active_object)
	else:
		clear_active_object()


func set_active_object(object_data: ObjectData) -> void:
	if object_data == null:
		clear_active_object()
		return
	if room_data != null and not room_data.has_object(object_data):
		clear_active_object()
		return

	if active_object != object_data and api.moving_part != null:
		api.cancel_move()

	active_object = object_data
	var model: ModelData = _get_model(active_object)
	if api.active_model != model:
		api.set_active_model(model)
		if model != null:
			api.set_selected_part(model)
	elif model != null and api.selected_part == null:
		api.set_selected_part(model)
	model_part_selected.emit(active_object, api.selected_part)


func clear_active_object() -> void:
	if api != null and api.moving_part != null:
		api.cancel_move()
	active_object = null
	if api != null:
		api.set_active_model(null)


func validate_active_model() -> void:
	if active_object == null:
		return
	if room_data == null or not room_data.has_object(active_object):
		clear_active_object()
		return

	var model: ModelData = _get_model(active_object)
	if model != api.active_model:
		api.set_active_model(model)
		if model != null:
			api.set_selected_part(model)


func get_builder() -> ObjectModelBuilder:
	return api


func get_active_model() -> ModelData:
	return api.active_model if api != null else null


func get_selected_part() -> ModelData:
	return api.selected_part if api != null else null


func has_model() -> bool:
	return _get_model(active_object) != null


func begin_model_create_mode(world_position: Vector2) -> bool:
	if not enabled or room_data == null or api == null:
		return false

	if api.moving_part != null:
		api.cancel_move()
	if model_editor != null:
		model_editor.close()
	if model_create_prompt != null:
		model_create_prompt.hide()

	# Model Create is its own workspace. Nothing is added to RoomData until a
	# later explicit object/model attachment operation.
	workspace_models.clear()
	workspace_positions.clear()
	workspace_selected_models.clear()
	workspace_hovered_model = null
	workspace_context_model = null
	model_clipboard = null
	model_create_auto_stack_on_top = false
	model_create_base_height_offset_px = 0.0

	edit_mode = EditMode.MODEL_CREATE
	model_create_world_position = world_position
	edit_mode_changed.emit(edit_mode)
	_start_model_create_preview(world_position)
	return true


func _start_model_create_preview(world_position: Vector2) -> bool:
	if api == null:
		return false

	var preview_model: ModelData = api.create_model("Model")
	if preview_model == null:
		return false

	preview_model.model_name = "Model"
	preview_model.local_position = Vector2.ZERO
	preview_model.local_rotation_degrees = 0.0
	preview_model.local_height_offset_px = 0.0
	model_create_base_height_offset_px = preview_model.local_height_offset_px
	model_create_auto_stack_on_top = true
	model_create_model = preview_model
	model_create_preview_position = world_position
	model_create_preview_active = true
	api.set_active_model(preview_model)
	api.set_selected_part(preview_model)
	_sync_model_renderer()
	_show_status("Model preview active. Left-click to place it.")
	return true


func update_model_create_preview(world_position: Vector2) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE or model_create_model == null:
		return false
	if not model_create_preview_active:
		return false

	model_create_preview_position = world_position
	model_create_world_position = world_position

	if free_attach_active:
		var hovered: ModelData = _get_workspace_model_at(world_position)
		if hovered == free_attach_source:
			hovered = null
		free_attach_target = hovered
		workspace_hovered_model = hovered
		if hovered != null:
			workspace_context_model = hovered
		_update_free_attach_vertical_preview()
	elif model_create_auto_stack_on_top:
		_update_model_create_top_stack_preview(world_position)

	_sync_model_renderer()
	return true


func update_model_create_hover(world_position: Vector2) -> void:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return

	model_create_world_position = world_position
	var hovered: ModelData = _get_workspace_model_at(world_position)
	workspace_hovered_model = hovered
	if hovered != null:
		workspace_context_model = hovered
	_sync_model_renderer()


func resolve_workspace_context_model(world_position: Vector2) -> ModelData:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return null

	model_create_world_position = world_position
	var resolved: ModelData = _get_workspace_model_at(world_position)
	if resolved != null:
		workspace_hovered_model = resolved
		workspace_context_model = resolved
		if not workspace_selected_models.has(resolved):
			workspace_selected_models.clear()
			workspace_selected_models.append(resolved)
		api.set_active_model(resolved)
		api.set_selected_part(resolved)
		_sync_model_renderer()
	return resolved


func set_workspace_context_model(model: ModelData) -> void:
	if model != null and not workspace_models.has(model):
		workspace_context_model = null
		return
	workspace_context_model = model


func copy_workspace_model() -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return false

	var source: ModelData = workspace_hovered_model
	if source == null and workspace_selected_models.size() == 1:
		source = workspace_selected_models[0]
	if source == null or not workspace_models.has(source):
		_show_status("No workspace model is selected to copy.")
		return false

	model_clipboard = source.duplicate(true) as ModelData
	if model_clipboard == null:
		_show_status("Could not copy model.")
		return false

	var position_value: Variant = workspace_positions.get(source, model_create_world_position)
	var source_position: Vector2 = position_value if position_value is Vector2 else model_create_world_position
	model_create_world_position = source_position
	_show_status("Copied model: %s. Left-click to paste a copy at the cursor." % source.model_name)
	return true


func paste_workspace_model(world_position: Vector2) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE or model_clipboard == null:
		return false

	var pasted: ModelData = model_clipboard.duplicate(true) as ModelData
	if pasted == null:
		_show_status("Could not paste model.")
		return false

	var paste_target: ModelData = _get_workspace_model_at(world_position)
	if paste_target != null and paste_target != pasted:
		pasted.local_height_offset_px += _get_workspace_model_top_height(paste_target)

	workspace_models.append(pasted)
	workspace_positions[pasted] = world_position
	workspace_selected_models.clear()
	workspace_selected_models.append(pasted)
	workspace_hovered_model = pasted
	model_create_world_position = world_position
	api.set_active_model(pasted)
	api.set_selected_part(pasted)
	_sync_model_renderer()
	_show_status("Pasted model: %s." % pasted.model_name)
	return true


func has_model_clipboard() -> bool:
	return enabled and model_clipboard != null


func handle_model_create_left_click(world_position: Vector2, additive_selection: bool = false) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return false

	model_create_world_position = world_position
	if free_attach_active:
		return _commit_free_attach(world_position)
	if model_create_preview_active:
		return place_model_create_preview(world_position)

	if model_clipboard != null:
		return paste_workspace_model(world_position)

	var hovered: ModelData = _get_workspace_model_at(world_position)
	if hovered != null:
		_select_workspace_model(hovered, additive_selection)
		return true

	model_create_prompt_position = world_position
	_popup_model_create_prompt()
	return true


func _update_model_create_top_stack_preview(world_position: Vector2) -> void:
	if not model_create_auto_stack_on_top or model_create_model == null:
		return

	model_create_model.local_height_offset_px = model_create_base_height_offset_px
	var target: ModelData = _get_workspace_model_at(world_position)
	if target == null or target == model_create_model:
		return

	model_create_model.local_height_offset_px += _get_workspace_model_top_height(target)

func place_model_create_preview(world_position: Vector2) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE or model_create_model == null:
		return false

	model_create_preview_position = world_position
	if model_create_auto_stack_on_top:
		_update_model_create_top_stack_preview(world_position)
	workspace_models.append(model_create_model)
	workspace_positions[model_create_model] = world_position

	workspace_selected_models.clear()
	workspace_selected_models.append(model_create_model)
	workspace_hovered_model = model_create_model
	workspace_context_model = model_create_model

	# The preview is now a fixed workspace model. A later empty click can ask
	# for another temporary ModelData without moving this one.
	model_create_model = null
	model_create_preview_active = false
	model_create_auto_stack_on_top = false
	model_create_base_height_offset_px = 0.0
	_sync_model_renderer()
	_show_status("Model placed. Click empty space to create another model.")
	return true


func move_model_create_preview_again(target_model: ModelData = null) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return false

	if model_create_model == null:
		var selected_root: ModelData = target_model
		if selected_root == null or not workspace_models.has(selected_root):
			selected_root = workspace_context_model
		if selected_root == null or not workspace_models.has(selected_root):
			selected_root = workspace_hovered_model
		if selected_root == null or not workspace_models.has(selected_root):
			if workspace_selected_models.is_empty():
				return false
			selected_root = workspace_selected_models[workspace_selected_models.size() - 1]

		var position_value: Variant = workspace_positions.get(selected_root, Vector2.ZERO)
		var selected_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		workspace_models.erase(selected_root)
		workspace_positions.erase(selected_root)
		workspace_selected_models.erase(selected_root)
		if workspace_hovered_model == selected_root:
			workspace_hovered_model = null
		workspace_context_model = null
		model_create_model = selected_root
		model_create_preview_position = selected_position
		model_create_world_position = selected_position
		model_create_base_height_offset_px = selected_root.local_height_offset_px
		model_create_auto_stack_on_top = false

	model_create_preview_active = true
	_sync_model_renderer()
	_show_status("Model is following the cursor again. Left-click to place it.")
	return true


func is_model_create_preview_active() -> bool:
	return enabled and edit_mode == EditMode.MODEL_CREATE and model_create_model != null and model_create_preview_active


func get_model_create_preview_model() -> ModelData:
	return model_create_model if edit_mode == EditMode.MODEL_CREATE else null


func _create_model_create_prompt() -> void:
	if host == null or not is_instance_valid(host):
		return
	if model_create_prompt != null:
		return

	model_create_prompt = ConfirmationDialog.new()
	model_create_prompt.name = "ModelCreatePrompt"
	model_create_prompt.title = "Create New Model"
	model_create_prompt.ok_button_text = "Create Model"
	model_create_prompt.cancel_button_text = "Cancel"
	model_create_prompt.size = Vector2i(360, 140)
	model_create_prompt.min_size = Vector2i(280, 120)
	model_create_prompt.canceled.connect(_on_model_create_prompt_cancelled)
	model_create_prompt.confirmed.connect(_on_model_create_prompt_confirmed)

	var label := Label.new()
	label.text = "Create a new model at the clicked empty position?"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	model_create_prompt.add_child(label)
	host.add_child(model_create_prompt)


func _popup_model_create_prompt() -> void:
	if model_create_prompt == null or host == null or not is_instance_valid(host):
		return

	var viewport_rect: Rect2 = host.get_viewport().get_visible_rect()
	var viewport_size: Vector2 = viewport_rect.size
	var desired_size := Vector2i(360, 140)
	var available_size := Vector2i(
		maxi(int(viewport_size.x) - 32, 1),
		maxi(int(viewport_size.y) - 32, 1))
	var safe_size := Vector2i(
		clampi(desired_size.x, mini(280, available_size.x), available_size.x),
		clampi(desired_size.y, mini(120, available_size.y), available_size.y))

	model_create_prompt.size = safe_size
	model_create_prompt.reset_size()
	# Use the parent-window clamped popup path so the dialog is centered within
	# the actual running viewport/window rather than the physical monitor.
	model_create_prompt.popup_centered_clamped(safe_size, 0.95)


func _on_model_create_prompt_confirmed() -> void:
	_start_model_create_preview(model_create_prompt_position)


func _on_model_create_prompt_cancelled() -> void:
	model_create_prompt_position = Vector2.ZERO


func _get_workspace_model_at(world_position: Vector2) -> ModelData:
	# Prefer screen-space picking so the visible elevated/top surface of an
	# isometric model is editable, not only its flat ground footprint.
	if model_renderer != null and host != null and is_instance_valid(host):
		var viewport := host.get_viewport()
		if viewport != null:
			var screen_pick: ModelData = model_renderer.pick_workspace_model_at_screen(viewport.get_mouse_position())
			if screen_pick != null:
				return screen_pick

	if workspace_context_model != null and workspace_models.has(workspace_context_model):
		var context_position_value: Variant = workspace_positions.get(workspace_context_model, Vector2.ZERO)
		var context_position: Vector2 = context_position_value if context_position_value is Vector2 else Vector2.ZERO
		if context_position.distance_to(world_position) <= 12.0:
			return workspace_context_model

	for model_index in range(workspace_models.size() - 1, -1, -1):
		var root: ModelData = workspace_models[model_index]
		if root == null:
			continue

		var parts: Array[ModelData] = root.get_all_parts_recursive(true)
		for part_index in range(parts.size() - 1, -1, -1):
			var part: ModelData = parts[part_index]
			if part == null or part.is_assembly_parent:
				continue

			var pose: Dictionary = api.get_world_pose(root, part)
			if not bool(pose.get("valid", false)):
				continue

			var root_position_value: Variant = workspace_positions.get(root, Vector2.ZERO)
			var root_position: Vector2 = root_position_value if root_position_value is Vector2 else Vector2.ZERO
			var pose_position_value: Variant = pose.get("position", Vector2.ZERO)
			var pose_position: Vector2 = pose_position_value if pose_position_value is Vector2 else Vector2.ZERO
			var part_position: Vector2 = root_position + pose_position
			var rotation_degrees: float = float(pose.get("rotation_degrees", 0.0))
			var polygon: PackedVector2Array = part.get_flat_footprint_polygon()
			var world_polygon: PackedVector2Array = PackedVector2Array()
			for point in polygon:
				world_polygon.append(part_position + point.rotated(deg_to_rad(rotation_degrees)))

			if world_polygon.size() >= 3 and Geometry2D.is_point_in_polygon(world_position, world_polygon):
				return root

	return null


func _select_workspace_model(model: ModelData, additive: bool) -> void:
	if model == null:
		return
	if not workspace_models.has(model):
		return

	if not additive:
		workspace_selected_models.clear()

	if workspace_selected_models.has(model):
		if additive:
			workspace_selected_models.erase(model)
	else:
		workspace_selected_models.append(model)

	workspace_hovered_model = model
	workspace_context_model = model
	api.set_active_model(model)
	api.set_selected_part(model)
	_sync_model_renderer()


func get_selected_workspace_model() -> ModelData:
	if workspace_selected_models.size() != 1:
		return null
	return workspace_selected_models[0]


func _get_workspace_context_model_for_asset_action() -> ModelData:
	if model_create_preview_active and model_create_model != null:
		return model_create_model
	if workspace_context_model != null and workspace_models.has(workspace_context_model):
		return workspace_context_model
	if workspace_hovered_model != null and workspace_models.has(workspace_hovered_model):
		return workspace_hovered_model
	if workspace_selected_models.size() == 1 and workspace_models.has(workspace_selected_models[0]):
		return workspace_selected_models[0]
	return null


func _create_model_save_dialog() -> void:
	if host == null or not is_instance_valid(host) or model_save_dialog != null:
		return

	model_save_dialog = ConfirmationDialog.new()
	model_save_dialog.name = "SaveWorkspaceModelDialog"
	model_save_dialog.title = "Save Model"
	model_save_dialog.ok_button_text = "Save"
	model_save_dialog.cancel_button_text = "Cancel"
	model_save_dialog.size = Vector2i(480, 170)
	model_save_dialog.min_size = Vector2i(360, 140)
	model_save_dialog.confirmed.connect(_on_model_save_confirmed)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	model_save_dialog.add_child(root_box)

	var label := Label.new()
	label.text = "Save the complete model, including all nested parts, to res://assets/baked_tres/model_data/"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(label)

	model_save_name_edit = LineEdit.new()
	model_save_name_edit.placeholder_text = "Model filename"
	root_box.add_child(model_save_name_edit)
	host.add_child(model_save_dialog)


func save_workspace_model(model: ModelData = null) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return false

	var target: ModelData = model
	if target == null:
		target = _get_workspace_context_model_for_asset_action()
	if target == null:
		_show_status("No model is available to save.")
		return false

	if model_save_dialog == null:
		_create_model_save_dialog()
	if model_save_dialog == null or model_save_name_edit == null:
		return false

	model_save_dialog.set_meta("workspace_model_to_save", target)
	model_save_name_edit.text = _sanitize_model_file_name(target.model_name)
	model_save_dialog.popup_centered()
	return true


func _on_model_save_confirmed() -> void:
	if model_save_dialog == null:
		return
	var target_value: Variant = model_save_dialog.get_meta("workspace_model_to_save", null)
	var target: ModelData = target_value as ModelData
	if target == null:
		_show_status("The model to save is no longer available.")
		return

	var file_base: String = _sanitize_model_file_name(model_save_name_edit.text if model_save_name_edit != null else target.model_name)
	if file_base.is_empty():
		_show_status("Invalid model filename.")
		return

	var absolute_dir: String = ProjectSettings.globalize_path(MODEL_SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var path: String = MODEL_SAVE_DIR + file_base + ".tres"
	var error: Error = ResourceSaver.save(target, path)
	if error != OK:
		_show_status("Failed to save model to %s (error %d)." % [path, error])
		return
	_show_status("Saved model to %s." % path)


func _get_saved_model_files() -> Array[String]:
	var result: Array[String] = []
	_collect_saved_model_files_recursive(MODEL_SAVE_DIR, result)
	result.sort()
	return result


func _collect_saved_model_files_recursive(directory_path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path: String = directory_path.trim_suffix("/") + "/" + file_name
			if directory.current_is_dir():
				_collect_saved_model_files_recursive(full_path, result)
			elif file_name.get_extension().to_lower() == "tres":
				var model_resource: ModelData = ResourceLoader.load(full_path) as ModelData
				if model_resource != null:
					result.append(full_path.trim_prefix(MODEL_SAVE_DIR))
		file_name = directory.get_next()
	directory.list_dir_end()


func _sanitize_model_file_name(value: String) -> String:
	var result: String = value.strip_edges()
	var invalid_characters: Array[String] = ["<", ">", ":", '"', "/", "\\", "|", "?", "*"]
	for character in invalid_characters:
		result = result.replace(character, "_")
	result = result.trim_suffix(".tres")
	return result.strip_edges()


func _populate_model_load_menu() -> void:
	model_load_files = _get_saved_model_files()
	if model_load_menu == null:
		return

	model_load_menu.clear()
	for index in model_load_files.size():
		var label: String = model_load_files[index].get_basename()
		model_load_menu.add_item(label, ACTION_LOAD_WORKSPACE_MODEL_BASE + index)

	if model_load_files.is_empty():
		model_load_menu.add_item("No saved models", ACTION_LOAD_WORKSPACE_MODEL_BASE)
		model_load_menu.set_item_disabled(0, true)


func _ensure_model_load_menu(menu: PopupMenu) -> void:
	if menu == null:
		return
	if model_load_menu == null:
		model_load_menu = PopupMenu.new()
		model_load_menu.name = "LoadWorkspaceModelMenu"
		model_load_menu.id_pressed.connect(_on_model_load_id_pressed)

	var current_parent: Node = model_load_menu.get_parent()
	if current_parent != menu:
		if current_parent != null and is_instance_valid(current_parent):
			model_load_menu.reparent(menu)
		else:
			menu.add_child(model_load_menu)


func _on_model_load_id_pressed(id: int) -> void:
	var file_index: int = id - ACTION_LOAD_WORKSPACE_MODEL_BASE
	if file_index < 0 or file_index >= model_load_files.size():
		return
	load_workspace_model_at(model_load_files[file_index], model_create_world_position)


func load_workspace_model_at(file_name: String, world_position: Vector2) -> ModelData:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return null
	if file_name.is_empty():
		return null

	var path: String = MODEL_SAVE_DIR + file_name
	var loaded: ModelData = ResourceLoader.load(path) as ModelData
	if loaded == null:
		_show_status("Could not load ModelData: %s" % file_name)
		return null

	var instance: ModelData = loaded.duplicate(true) as ModelData
	if instance == null:
		_show_status("Could not duplicate ModelData: %s" % file_name)
		return null

	# Workspace placement owns the root world position, so the loaded root is
	# normalized to the workspace origin without altering its child transforms.
	instance.local_position = Vector2.ZERO
	workspace_models.append(instance)
	workspace_positions[instance] = world_position
	workspace_selected_models.clear()
	workspace_selected_models.append(instance)
	workspace_hovered_model = instance
	workspace_context_model = instance
	model_create_world_position = world_position
	api.set_active_model(instance)
	api.set_selected_part(instance)
	_sync_model_renderer()
	_show_status("Loaded model: %s." % instance.model_name)
	return instance


func transpose_entire_model_into_object(model: ModelData = null) -> bool:
	return take_workspace_model_into_object(model, true)


## Creates a normal ObjectData from a workspace model and optionally keeps the
## complete ModelData tree as the object's primary visual representation.
##
## keep_as_model = true keeps a deep copy in ObjectData.object_model.
## keep_as_model = false bakes the model into the legacy ObjectData body fields.
func take_workspace_model_into_object(model: ModelData = null, keep_as_model: bool = true) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE or room_data == null:
		return false

	var target: ModelData = model
	if target == null:
		target = _get_workspace_context_model_for_asset_action()
	if target == null or not workspace_models.has(target):
		_show_status("Select or right-click a workspace model before taking it into an object.")
		return false

	var position_value: Variant = workspace_positions.get(target, model_create_world_position)
	var workspace_position: Vector2 = position_value if position_value is Vector2 else model_create_world_position
	var footprint_bounds: Rect2 = _get_workspace_model_footprint_bounds(target)
	var footprint_size: Vector2i = _get_workspace_model_footprint_size(target)
	if footprint_size.x < 1 or footprint_size.y < 1:
		footprint_size = Vector2i(1, 1)

	var object_position: Vector2 = workspace_position
	if footprint_bounds.size.x > EPSILON and footprint_bounds.size.y > EPSILON:
		object_position += footprint_bounds.get_center()

	var object_data := ObjectData.new()
	object_data.object_name = target.model_name if not target.model_name.is_empty() else "Object"
	object_data.description = target.description
	object_data.base_color = target.base_color
	object_data.position = workspace_position if keep_as_model else object_position
	object_data.size_px = footprint_size
	object_data.hp = 100.0
	object_data.carried_weight = 1.0
	object_data.height_px = maxf(target.get_top_height_px(), target.height_px)
	object_data.rotation_degrees = 0.0

	if keep_as_model:
		var model_copy: ModelData = target.duplicate(true) as ModelData
		if model_copy == null:
			_show_status("Could not duplicate the model for the new ObjectData.")
			return false
		object_data.object_model = model_copy
	else:
		_apply_model_as_legacy_body(object_data, target)

	if host != null and is_instance_valid(host) and host.has_method("_can_place_object"):
		var can_place_value: Variant = host.call("_can_place_object", object_data.position, footprint_size, object_data.rotation_degrees, null)
		if can_place_value is bool and not bool(can_place_value):
			_show_status("Cannot take model here: its occupied space overlaps another object.")
			return false

	room_data.add_object(object_data)
	workspace_models.erase(target)
	workspace_positions.erase(target)
	workspace_selected_models.erase(target)
	if workspace_hovered_model == target:
		workspace_hovered_model = null
	if workspace_context_model == target:
		workspace_context_model = null

	if host != null and is_instance_valid(host) and host.has_method("_select_object"):
		host.call("_select_object", object_data)
	else:
		active_object = object_data

	object_data.emit_changed()
	room_data.emit_changed()
	exit_model_mode()
	if keep_as_model:
		_show_status("Took %s into ObjectData as an As-Is Model and exited Model Create Mode." % object_data.object_name)
	else:
		_show_status("Took %s into ObjectData as its body and exited Model Create Mode." % object_data.object_name)
	return true


func take_workspace_model_as_body(model: ModelData = null) -> bool:
	return take_workspace_model_into_object(model, false)


func take_workspace_model_as_model(model: ModelData = null) -> bool:
	return take_workspace_model_into_object(model, true)


func _apply_model_as_legacy_body(object_data: ObjectData, target: ModelData) -> void:
	if object_data == null or target == null:
		return

	var leaves: Array[ModelData] = target.get_all_parts_recursive(false)
	if leaves.size() == 1 and leaves[0] != null:
		var part: ModelData = leaves[0]
		if part.flat_bottom_shape == ModelData.FlatBottomShape.ELLIPSE or part.body_type == ModelData.BodyType.CYLINDER or part.body_type == ModelData.BodyType.CONE:
			object_data.body_shape = ObjectData.BodyShape.CYLINDER
		elif part.has_corners and part.corner_style != ModelData.CornerStyle.SOLID_RECT:
			object_data.body_shape = ObjectData.BodyShape.ROUNDED_CORNERS
		else:
			object_data.body_shape = ObjectData.BodyShape.RECTANGULAR

		object_data.has_corners = part.has_corners
		object_data.curved_corners = part.corner_style == ModelData.CornerStyle.CURVED
		object_data.corner_radius_px = maxf(part.corner_radius_px, 0.0)
		match part.body_type:
			ModelData.BodyType.PYRAMID, ModelData.BodyType.CONE:
				object_data.top_render_style = ObjectData.TopRenderStyle.POINT_OUTWARD
			ModelData.BodyType.HYBRID:
				object_data.top_render_style = ObjectData.TopRenderStyle.FLAT
			_:
				object_data.top_render_style = ObjectData.TopRenderStyle.FLAT
		object_data.top_profile_height_px = maxf(part.top_profile_height_px, 0.0)
		object_data.top_profile_segments = clampi(part.corner_segments, 3, 32)
	else:
		# A multi-part assembly cannot be represented exactly by the legacy
		# single-body schema, so bake its aggregate footprint as a rectangle.
		object_data.body_shape = ObjectData.BodyShape.RECTANGULAR
		object_data.has_corners = false
		object_data.curved_corners = false
		object_data.corner_radius_px = 0.0
		object_data.top_render_style = ObjectData.TopRenderStyle.FLAT
		object_data.top_profile_height_px = 0.0
		object_data.top_profile_segments = 8


func _get_workspace_model_footprint_bounds(root: ModelData) -> Rect2:
	if root == null or api == null:
		return Rect2()

	var min_point: Vector2 = Vector2(INF, INF)
	var max_point: Vector2 = Vector2(-INF, -INF)
	var parts: Array[ModelData] = root.get_all_parts_recursive(false)
	for part in parts:
		if part == null:
			continue
		var pose: Dictionary = api.get_world_pose(root, part)
		if not bool(pose.get("valid", false)):
			continue
		var position_value: Variant = pose.get("position", Vector2.ZERO)
		var part_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var rotation_degrees: float = float(pose.get("rotation_degrees", 0.0))
		var radians: float = deg_to_rad(rotation_degrees)
		for point in part.get_flat_footprint_polygon():
			var world_point: Vector2 = part_position + point.rotated(radians)
			min_point.x = minf(min_point.x, world_point.x)
			min_point.y = minf(min_point.y, world_point.y)
			max_point.x = maxf(max_point.x, world_point.x)
			max_point.y = maxf(max_point.y, world_point.y)

	if not is_finite(min_point.x) or not is_finite(min_point.y) or not is_finite(max_point.x) or not is_finite(max_point.y):
		return Rect2()
	return Rect2(min_point, max_point - min_point)

func _get_workspace_model_footprint_size(root: ModelData) -> Vector2i:
	if root == null:
		return Vector2i(1, 1)

	var bounds: Rect2 = _get_workspace_model_footprint_bounds(root)

	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		var fallback_size: Vector2 = root.size_px
		return Vector2i(
			maxi(int(ceil(fallback_size.x)), 1),
			maxi(int(ceil(fallback_size.y)), 1)
		)

	return Vector2i(
		maxi(int(ceil(bounds.size.x)), 1),
		maxi(int(ceil(bounds.size.y)), 1)
	)

func combine_selected_workspace_models() -> ModelData:
	if api == null or workspace_selected_models.size() < 2:
		return null

	var positions: Dictionary = {}
	var parts: Array[ModelData] = []
	for model in workspace_selected_models:
		if model == null or not workspace_models.has(model):
			continue
		var position_value: Variant = workspace_positions.get(model, Vector2.ZERO)
		positions[model] = position_value if position_value is Vector2 else Vector2.ZERO
		parts.append(model)

	if parts.size() < 2:
		return null

	var combined: ModelData = api.combine_standalone_models(parts, positions, "Combined Model")
	if combined == null:
		return null

	var center: Vector2 = Vector2.ZERO
	for part in parts:
		var part_position: Variant = positions.get(part, Vector2.ZERO)
		if part_position is Vector2:
			center += part_position
	center /= float(parts.size())

	for part in parts:
		workspace_models.erase(part)
		workspace_positions.erase(part)

	workspace_models.append(combined)
	workspace_positions[combined] = center
	workspace_selected_models.clear()
	workspace_selected_models.append(combined)
	workspace_hovered_model = combined
	workspace_context_model = combined
	api.set_active_model(combined)
	api.set_selected_part(combined)
	_sync_model_renderer()
	_show_status("Combined models under parent: %s. This parent is the complete model." % combined.model_name)
	return combined


func begin_free_attach_workspace_model(source: ModelData = null) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return false

	var selected_source: ModelData = source
	if selected_source == null:
		selected_source = workspace_context_model
	if selected_source == null and workspace_selected_models.size() == 1:
		selected_source = workspace_selected_models[0]
	if selected_source == null or not workspace_models.has(selected_source):
		_show_status("Select a placed model first.")
		return false

	_create_free_attach_prompt(selected_source)
	return true


func _create_free_attach_prompt(source: ModelData) -> void:
	if host == null or not is_instance_valid(host):
		return

	if free_attach_prompt == null:
		free_attach_prompt = ConfirmationDialog.new()
		free_attach_prompt.name = "FreeAttachPrompt"
		free_attach_prompt.title = "Free Attach Model"
		free_attach_prompt.ok_button_text = "Start Free Attach"
		free_attach_prompt.cancel_button_text = "Cancel"
		free_attach_prompt.size = Vector2i(420, 190)
		free_attach_prompt.min_size = Vector2i(340, 160)

		var root_box := VBoxContainer.new()
		root_box.add_theme_constant_override("separation", 8)
		free_attach_prompt.add_child(root_box)

		var description := Label.new()
		description.text = "Choose how the selected model should behave while free-attaching. When Attach on top is enabled, the preview is vertically raised to sit on the target model's visible top surface."
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root_box.add_child(description)

		free_attach_prompt_check = CheckButton.new()
		free_attach_prompt_check.text = "Attach on top of target model"
		free_attach_prompt_check.button_pressed = true
		root_box.add_child(free_attach_prompt_check)

		host.add_child(free_attach_prompt)

	free_attach_prompt_check.button_pressed = true
	free_attach_prompt.set_meta("free_attach_source", source)
	if not free_attach_prompt.confirmed.is_connected(_on_free_attach_prompt_confirmed):
		free_attach_prompt.confirmed.connect(_on_free_attach_prompt_confirmed)
	if not free_attach_prompt.canceled.is_connected(_on_free_attach_prompt_cancelled):
		free_attach_prompt.canceled.connect(_on_free_attach_prompt_cancelled)

	free_attach_prompt.popup_centered_clamped(Vector2i(420, 190), 0.95)


func _on_free_attach_prompt_confirmed() -> void:
	if free_attach_prompt == null or free_attach_prompt_check == null:
		return
	var source_value: Variant = free_attach_prompt.get_meta("free_attach_source", null)
	var source: ModelData = source_value as ModelData
	if source == null or not workspace_models.has(source):
		_show_status("The selected workspace model is no longer available.")
		return

	var attach_on_top: bool = free_attach_prompt_check.button_pressed
	_begin_free_attach_workspace_model(source, attach_on_top)


func _on_free_attach_prompt_cancelled() -> void:
	if free_attach_prompt != null:
		free_attach_prompt.set_meta("free_attach_source", null)


func _begin_free_attach_workspace_model(source: ModelData, attach_on_top: bool) -> bool:
	var position_value: Variant = workspace_positions.get(source, Vector2.ZERO)
	free_attach_original_position = position_value if position_value is Vector2 else Vector2.ZERO
	free_attach_original_height_offset_px = source.local_height_offset_px
	free_attach_preview_position = free_attach_original_position
	free_attach_attach_on_top = attach_on_top
	free_attach_source = source
	free_attach_target = null
	free_attach_active = true
	model_create_auto_stack_on_top = false
	model_create_base_height_offset_px = source.local_height_offset_px

	workspace_models.erase(source)
	workspace_positions.erase(source)
	workspace_selected_models.erase(source)
	workspace_hovered_model = null
	workspace_context_model = null

	model_create_model = source
	model_create_preview_position = free_attach_original_position
	model_create_world_position = free_attach_original_position
	model_create_preview_active = true
	api.set_active_model(source)
	api.set_selected_part(source)
	_update_free_attach_vertical_preview()
	_sync_model_renderer()
	if attach_on_top:
		_show_status("Free Attach started. Move over a model; the preview will rise to its top surface.")
	else:
		_show_status("Free Attach started. Move over a model; the preview keeps its current height.")
	return true


func _update_free_attach_vertical_preview() -> void:
	if not free_attach_active or free_attach_source == null:
		return

	free_attach_source.local_height_offset_px = free_attach_original_height_offset_px
	if not free_attach_attach_on_top or free_attach_target == null:
		return

	var target_top_height: float = _get_workspace_model_top_height(free_attach_target)
	free_attach_source.local_height_offset_px = free_attach_original_height_offset_px + maxf(target_top_height, 0.0)


func _get_workspace_model_top_height(target: ModelData) -> float:
	if target == null or api == null:
		return 0.0

	var highest: float = 0.0
	var parts: Array[ModelData] = target.get_all_parts_recursive(true)
	for part in parts:
		if part == null:
			continue
		var pose: Dictionary = api.get_world_pose(target, part)
		if not bool(pose.get("valid", false)):
			continue
		var root_height: float = float(pose.get("base_height_px", 0.0))
		var top_height: float = root_height + maxf(part.height_px, 0.0)
		if part.body_type == ModelData.BodyType.HYBRID:
			top_height += maxf(part.top_profile_height_px, 0.0)
		highest = maxf(highest, top_height)

	return highest


func is_free_attach_active() -> bool:
	return enabled and edit_mode == EditMode.MODEL_CREATE and free_attach_active and model_create_model != null


func cancel_free_attach() -> bool:
	if not free_attach_active or free_attach_source == null:
		return false

	var source: ModelData = free_attach_source
	workspace_models.append(source)
	workspace_positions[source] = free_attach_original_position
	workspace_selected_models.clear()
	workspace_selected_models.append(source)
	workspace_hovered_model = source
	workspace_context_model = source
	source.local_height_offset_px = free_attach_original_height_offset_px

	free_attach_active = false
	free_attach_source = null
	free_attach_target = null
	free_attach_preview_position = Vector2.ZERO
	free_attach_attach_on_top = true
	free_attach_original_height_offset_px = 0.0
	model_create_model = null
	model_create_preview_active = false
	model_create_preview_position = Vector2.ZERO
	model_create_auto_stack_on_top = false
	model_create_base_height_offset_px = 0.0
	api.set_active_model(source)
	api.set_selected_part(source)
	_sync_model_renderer()
	_show_status("Free Attach cancelled. Model restored to its original position.")
	return true


func _commit_free_attach(world_position: Vector2) -> bool:
	if not free_attach_active or free_attach_source == null:
		return false

	model_create_preview_position = world_position
	free_attach_preview_position = world_position
	var target: ModelData = free_attach_target
	if target == null:
		target = _get_workspace_model_at(world_position)
	if target == null or not workspace_models.has(target):
		_show_status("Move over the model you want to attach to, then left-click again.")
		return true

	var source: ModelData = free_attach_source
	_update_free_attach_vertical_preview()
	var target_value: Variant = workspace_positions.get(target, Vector2.ZERO)
	var target_position: Vector2 = target_value if target_value is Vector2 else Vector2.ZERO
	var positions: Dictionary = {
		target: target_position,
		source: world_position,
	}

	var combined: ModelData = api.combine_standalone_models(
		[target, source],
		positions,
		"%s + %s Assembly" % [target.model_name, source.model_name])
	if combined == null:
		_show_status("The models could not be combined at this manual position.")
		return true

	var combined_position: Vector2 = (target_position + world_position) * 0.5
	workspace_models.erase(target)
	workspace_positions.erase(target)
	workspace_models.append(combined)
	workspace_positions[combined] = combined_position
	workspace_selected_models.clear()
	workspace_selected_models.append(combined)
	workspace_hovered_model = combined
	workspace_context_model = combined

	free_attach_active = false
	free_attach_source = null
	free_attach_target = null
	free_attach_preview_position = Vector2.ZERO
	free_attach_attach_on_top = true
	free_attach_original_height_offset_px = 0.0
	model_create_model = null
	model_create_preview_active = false
	model_create_preview_position = Vector2.ZERO
	model_create_auto_stack_on_top = false
	model_create_base_height_offset_px = 0.0
	api.set_active_model(combined)
	api.set_selected_part(combined)
	_sync_model_renderer()
	_show_status("Free-attached %s to %s and combined them into %s." % [source.model_name, target.model_name, combined.model_name])
	return true


func confirm_free_attach() -> bool:
	if not free_attach_active:
		return false
	return _commit_free_attach(model_create_preview_position)


func delete_workspace_model(model: ModelData = null) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE:
		return false

	var target: ModelData = model
	if target == null:
		target = workspace_context_model
	if target == null:
		target = workspace_hovered_model
	if target == null and workspace_selected_models.size() == 1:
		target = workspace_selected_models[0]
	if target == null or not workspace_models.has(target):
		_show_status("No workspace model is selected to delete.")
		return false

	var deleted_name: String = target.model_name
	workspace_models.erase(target)
	workspace_positions.erase(target)
	workspace_selected_models.erase(target)
	if workspace_hovered_model == target:
		workspace_hovered_model = null
	if workspace_context_model == target:
		workspace_context_model = null
	if api != null and api.active_model == target:
		api.set_active_model(null)
		api.set_selected_part(null)
	_sync_model_renderer()
	_show_status("Deleted model: %s." % deleted_name)
	return true


func get_nearby_workspace_attach_candidates(source: ModelData = null) -> Array:
	if api == null or not api.has_method("get_workspace_face_snap_candidates"):
		return []
	var selected_source: ModelData = source
	if selected_source == null:
		selected_source = workspace_context_model
	if selected_source == null and workspace_selected_models.size() == 1:
		selected_source = workspace_selected_models[0]
	if selected_source == null or not workspace_models.has(selected_source):
		return []
	var position_value: Variant = workspace_positions.get(selected_source, Vector2.ZERO)
	var source_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	return api.call("get_workspace_face_snap_candidates", selected_source, source_position, workspace_models, workspace_positions) as Array


func open_attach_nearby_model_prompt(source: ModelData = null) -> bool:
	if not enabled or edit_mode != EditMode.MODEL_CREATE or api == null:
		return false
	var selected_source: ModelData = source
	if selected_source == null:
		selected_source = workspace_context_model
	if selected_source == null and workspace_selected_models.size() == 1:
		selected_source = workspace_selected_models[0]
	if selected_source == null or not workspace_models.has(selected_source):
		_show_status("Select a workspace model first.")
		return false

	workspace_combine_candidates = get_nearby_workspace_attach_candidates(selected_source)
	if workspace_combine_candidates.is_empty():
		_show_status("No nearby model faces are within snap distance.")
		return false

	if workspace_combine_dialog == null:
		_create_workspace_combine_dialog()
	if workspace_combine_dialog == null or workspace_combine_choice == null:
		return false

	workspace_context_model = selected_source
	workspace_hovered_model = selected_source
	if not workspace_selected_models.has(selected_source):
		workspace_selected_models.clear()
		workspace_selected_models.append(selected_source)
	api.set_active_model(selected_source)
	api.set_selected_part(selected_source)

	workspace_combine_choice.clear()
	for candidate in workspace_combine_candidates:
		var source_face: int = int(candidate.get("source_face", 0))
		var target_face: int = int(candidate.get("target_face", 0))
		var target_model: ModelData = candidate.get("target") as ModelData
		var distance: float = float(candidate.get("distance_px", 0.0))
		var target_name: String = target_model.model_name if target_model != null else "Model"
		var source_face_name: String = str(api.call("get_attach_face_name", source_face)) if api.has_method("get_attach_face_name") else str(source_face)
		var target_face_name: String = str(api.call("get_attach_face_name", target_face)) if api.has_method("get_attach_face_name") else str(target_face)
		var label: String = "%s -> %s of %s (%.1f px)" % [source_face_name, target_face_name, target_name, distance]
		workspace_combine_choice.add_item(label)
	workspace_combine_choice.select(0)
	_sync_model_renderer()
	_popup_workspace_combine_dialog()
	return true


func _create_workspace_combine_dialog() -> void:
	if host == null or not is_instance_valid(host) or workspace_combine_dialog != null:
		return

	workspace_combine_dialog = ConfirmationDialog.new()
	workspace_combine_dialog.name = "WorkspaceModelCombineDialog"
	workspace_combine_dialog.title = "Attach Model Faces"
	workspace_combine_dialog.ok_button_text = "Attach + Combine"
	workspace_combine_dialog.cancel_button_text = "Cancel"
	workspace_combine_dialog.size = Vector2i(560, 220)
	workspace_combine_dialog.min_size = Vector2i(440, 190)
	workspace_combine_dialog.confirmed.connect(_on_workspace_combine_confirmed)
	workspace_combine_dialog.canceled.connect(_on_workspace_combine_cancelled)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	workspace_combine_dialog.add_child(root_box)

	var description := Label.new()
	description.text = "Choose which face of this model should snap to a nearby face. The two models will become children of one new ModelData assembly."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(description)

	workspace_combine_choice = OptionButton.new()
	workspace_combine_choice.custom_minimum_size.y = 32.0
	root_box.add_child(workspace_combine_choice)

	var note := Label.new()
	note.text = "Only face pairs already within the configured snap-distance threshold are listed."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(note)

	host.add_child(workspace_combine_dialog)


func _popup_workspace_combine_dialog() -> void:
	if workspace_combine_dialog == null or host == null or not is_instance_valid(host):
		return
	var viewport_size: Vector2 = host.get_viewport().get_visible_rect().size
	var available := Vector2i(
		maxi(int(viewport_size.x) - 32, 1),
		maxi(int(viewport_size.y) - 32, 1))
	var safe_size := Vector2i(
		clampi(560, mini(440, available.x), available.x),
		clampi(220, mini(190, available.y), available.y))
	workspace_combine_dialog.size = safe_size
	workspace_combine_dialog.reset_size()
	workspace_combine_dialog.popup_centered_clamped(safe_size, 0.95)


func _on_workspace_combine_confirmed() -> void:
	if workspace_combine_candidates.is_empty() or workspace_combine_choice == null:
		return
	var choice_index: int = workspace_combine_choice.selected
	if choice_index < 0 or choice_index >= workspace_combine_candidates.size():
		return

	var candidate: Dictionary = workspace_combine_candidates[choice_index]
	var source: ModelData = candidate.get("source") as ModelData
	var target: ModelData = candidate.get("target") as ModelData
	if source == null or target == null or not workspace_models.has(source) or not workspace_models.has(target):
		_show_status("The selected attach candidate is no longer available.")
		return

	var source_value: Variant = workspace_positions.get(source, Vector2.ZERO)
	var target_value: Variant = workspace_positions.get(target, Vector2.ZERO)
	var source_position: Vector2 = source_value if source_value is Vector2 else Vector2.ZERO
	var target_position: Vector2 = target_value if target_value is Vector2 else Vector2.ZERO

	if not api.has_method("combine_standalone_models_by_face_snap"):
		_show_status("Face-snap combine is unavailable in ObjectModelBuilder.")
		return

	var source_name: String = source.model_name
	var target_name: String = target.model_name
	var combined: ModelData = api.call(
		"combine_standalone_models_by_face_snap",
		source,
		source_position,
		target,
		target_position,
		candidate,
		"%s + %s Assembly" % [target_name, source_name]) as ModelData
	if combined == null:
		_show_status("The models could not be combined using that face pair.")
		return

	var combined_position: Vector2 = target_position + target.local_position
	workspace_models.erase(source)
	workspace_models.erase(target)
	workspace_positions.erase(source)
	workspace_positions.erase(target)
	workspace_models.append(combined)
	workspace_positions[combined] = combined_position
	workspace_selected_models.clear()
	workspace_selected_models.append(combined)
	workspace_hovered_model = combined
	workspace_context_model = combined
	api.set_active_model(combined)
	api.set_selected_part(combined)
	workspace_combine_candidates.clear()
	workspace_combine_dialog.hide()
	_sync_model_renderer()
	_show_status("Attached %s to %s and combined them into %s." % [source_name, target_name, combined.model_name])


func _on_workspace_combine_cancelled() -> void:
	workspace_combine_candidates.clear()


func sync_projection(projector: IsoWallRenderer) -> void:
	if projector == null or model_renderer == null:
		return
	model_renderer.set_view_from_projector(projector)
	_sync_model_renderer()


func _sync_model_renderer() -> void:
	if model_renderer == null:
		return
	if edit_mode == EditMode.MODEL_CREATE:
		model_renderer.visible = true
		model_renderer.set_model(null)
		model_renderer.set_ghost_preview(false)
		model_renderer.set_workspace_models(
			workspace_models,
			workspace_positions,
			workspace_selected_models,
			workspace_hovered_model)
		if model_create_model != null and model_create_preview_active:
			model_renderer.set_workspace_preview(model_create_model, model_create_preview_position, true)
		else:
			model_renderer.set_workspace_preview(null, Vector2.ZERO, false)
	else:
		model_renderer.visible = false
		model_renderer.clear_workspace_models()


func handle_model_create_click(world_position: Vector2) -> bool:
	return place_model_create_preview(world_position)


func begin_model_edit_mode(object_data: ObjectData) -> bool:
	if not _can_edit_object(object_data):
		return false

	active_object = object_data
	var model: ModelData = _get_model(object_data)
	if model == null:
		model = create_object_model(object_data, object_data.object_name + " Model")
		if model == null:
			return false

	var previous_part: ModelData = api.selected_part
	var can_keep_previous: bool = previous_part != null and api.contains_part(model, previous_part, true)
	api.set_active_model(model)
	if can_keep_previous:
		api.set_selected_part(previous_part)
	else:
		api.set_selected_part(model)
	edit_mode = EditMode.MODEL_EDIT
	edit_mode_changed.emit(edit_mode)
	model_part_selected.emit(active_object, api.selected_part)
	_sync_host_renderer()
	_show_status("Model edit mode: %s." % model.model_name)
	return true


func exit_model_mode() -> void:
	if free_attach_active:
		cancel_free_attach()
	if api != null and api.moving_part != null:
		api.cancel_move()
	if model_editor != null:
		model_editor.close()
	if free_attach_prompt != null:
		free_attach_prompt.hide()
	edit_mode = EditMode.NONE
	edit_mode_changed.emit(edit_mode)
	model_create_model = null
	model_create_preview_active = false
	model_create_preview_position = Vector2.ZERO
	workspace_models.clear()
	workspace_positions.clear()
	workspace_selected_models.clear()
	workspace_hovered_model = null
	workspace_context_model = null
	model_clipboard = null
	free_attach_active = false
	free_attach_source = null
	free_attach_target = null
	free_attach_preview_position = Vector2.ZERO
	free_attach_attach_on_top = true
	free_attach_original_height_offset_px = 0.0
	workspace_combine_candidates.clear()
	if workspace_combine_dialog != null:
		workspace_combine_dialog.hide()
	if model_renderer != null:
		model_renderer.clear_model()
		model_renderer.visible = false
	model_create_world_position = Vector2.ZERO
	model_create_auto_stack_on_top = false
	model_create_base_height_offset_px = 0.0


func is_model_create_mode_active() -> bool:
	return enabled and edit_mode == EditMode.MODEL_CREATE


func is_model_edit_mode_active() -> bool:
	return enabled and edit_mode == EditMode.MODEL_EDIT


func is_model_mode_active() -> bool:
	return enabled and edit_mode != EditMode.NONE


func create_object_model(object_data: ObjectData, model_name: String = "Model") -> ModelData:
	if not _can_edit_object(object_data):
		return null

	var existing: ModelData = _get_model(object_data)
	if existing != null:
		set_active_object(object_data)
		return existing

	var model: ModelData = api.create_model(model_name if not model_name.is_empty() else object_data.object_name + " Model")
	if model == null:
		return null

	if not api.build_model_on_object(object_data, model):
		return null

	active_object = object_data
	api.set_active_model(model)
	api.set_selected_part(model)
	_sync_host_renderer()
	model_changed.emit(object_data, model)
	return model


func attach_workspace_model_to_object(object_data: ObjectData, model: ModelData = null) -> bool:
	if not enabled or object_data == null:
		return false
	var target: ModelData = model
	if target == null:
		if workspace_selected_models.size() == 1:
			target = workspace_selected_models[0]
		else:
			target = null
	if target == null:
		return false
	var result: bool = api.build_model_on_object(object_data, target)
	if result:
		object_data.emit_changed()
		room_data.emit_changed()
	return result


## Load a saved ModelData asset and make it the primary visual body of an
## existing ObjectData. The previous legacy body remains stored as fallback
## metadata but is ignored by the custom-model renderers while this is assigned.
func insert_saved_model_into_object(
		object_data: ObjectData,
		file_name: String) -> bool:
	if not _can_edit_object(object_data):
		return false

	var clean_file_name: String = file_name.strip_edges()

	if clean_file_name.is_empty():
		_show_status("No model file was selected.")
		return false

	var model_path: String

	if clean_file_name.begins_with("res://"):
		model_path = clean_file_name
	else:
		model_path = "res://assets/baked_tres/model_data/" + clean_file_name

	var loaded_model: ModelData = ResourceLoader.load(model_path) as ModelData

	if loaded_model == null:
		_show_status("Could not load ModelData: %s" % model_path)
		return false

	var model_copy: ModelData = loaded_model.duplicate(true) as ModelData

	if model_copy == null:
		_show_status("Could not duplicate ModelData: %s" % model_path)
		return false

	# Replace the object's current model.
	# This makes the custom ModelData the primary representation.
	object_data.set_object_model(model_copy)

	# Use the model as the object's new footprint.
	var bounds: Rect2 = _calculate_model_footprint_bounds(model_copy)

	if bounds.size.x > 0.01 and bounds.size.y > 0.01:
		object_data.size_px = Vector2i(
			maxi(int(ceil(bounds.size.x)), 1),
			maxi(int(ceil(bounds.size.y)), 1)
		)
	else:
		object_data.size_px = Vector2i(
			maxi(int(ceil(model_copy.size_px.x)), 1),
			maxi(int(ceil(model_copy.size_px.y)), 1)
		)

	# Use model height as the object's effective height.
	object_data.height_px = maxf(
		model_copy.get_top_height_px(),
		model_copy.height_px
	)

	active_object = object_data
	api.set_active_model(model_copy)
	api.set_selected_part(model_copy)

	object_data.emit_changed()

	if room_data != null:
		room_data.emit_changed()

	_sync_model_renderer()
	_sync_host_renderer()

	model_changed.emit(object_data, model_copy)

	_show_status(
		"Inserted model '%s' into %s."
		% [model_copy.model_name, object_data.object_name]
	)

	return true
	
	
func _calculate_model_footprint_bounds(root: ModelData) -> Rect2:
	if root == null:
		return Rect2()

	var points: PackedVector2Array = PackedVector2Array()

	_collect_model_footprint_points(
		root,
		points,
		Vector2.ZERO,
		0.0
	)

	if points.is_empty():
		return Rect2()

	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]

	for point: Vector2 in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	return Rect2(
		min_point,
		max_point - min_point
	)
	
func _get_model_footprint_bounds(root: ModelData) -> Rect2:
	if root == null:
		return Rect2()

	var points: PackedVector2Array = PackedVector2Array()
	_collect_model_footprint_points(root, points, Vector2.ZERO, 0.0)

	if points.is_empty():
		return Rect2()

	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]

	for point: Vector2 in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	return Rect2(min_point, max_point - min_point)


func _collect_model_footprint_points(
		part: ModelData,
		points: PackedVector2Array,
		parent_position: Vector2,
		parent_rotation_degrees: float) -> void:
	if part == null:
		return

	var parent_radians: float = deg_to_rad(parent_rotation_degrees)

	var part_position: Vector2 = (
		parent_position
		+ part.local_position.rotated(parent_radians)
	)

	var part_rotation: float = (
		parent_rotation_degrees
		+ part.local_rotation_degrees
	)

	var polygon: PackedVector2Array = part.get_flat_footprint_polygon()

	if polygon.is_empty():
		var half_size: Vector2 = part.size_px * 0.5

		polygon = PackedVector2Array([
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y)
		])

	var rotation_radians: float = deg_to_rad(part_rotation)

	for point: Vector2 in polygon:
		points.append(
			part_position
			+ point.rotated(rotation_radians)
		)

	for child: ModelData in part.parts:
		_collect_model_footprint_points(
			child,
			points,
			part_position,
			part_rotation
		)


func clear_object_model(object_data: ObjectData) -> bool:
	if object_data == null:
		return false
	var model: ModelData = _get_model(object_data)
	if model == null:
		return false

	var result: bool = api.clear_object_model(object_data)
	if result and active_object == object_data:
		api.set_active_model(null)
		api.set_selected_part(null)
		_sync_host_renderer()
	return result


func create_model_part(
	body_type: ModelData.BodyType = ModelData.BodyType.RECTANGULAR,
	size_px: Vector2 = Vector2.ZERO,
	height_px: float = -1.0,
	model_name: String = "Model Part") -> ModelData:
	if api == null:
		return null
	return api.create_part(body_type, size_px, height_px, model_name)


func add_model_part(
	part: ModelData,
	local_position: Vector2 = Vector2.ZERO,
	local_height_offset_px: float = 0.0) -> bool:
	if active_object == null or api.active_model == null or part == null:
		return false
	return api.add_part(
		api.active_model,
		part,
		local_position,
		local_height_offset_px)


func remove_model_part(part: ModelData) -> bool:
	if api == null or api.active_model == null or part == null:
		return false
	return api.remove_part(api.active_model, part)


func select_active_model_root() -> ModelData:
	if not enabled or api == null or api.active_model == null:
		return null
	api.set_selected_part(api.active_model)
	if active_object != null:
		model_part_selected.emit(active_object, api.active_model)
	return api.active_model


func select_part_at(world_point: Vector2) -> ModelData:
	if not enabled or active_object == null or api.active_model == null:
		return null

	var part: ModelData = api.get_part_at_flat_position(
		api.active_model,
		world_point,
		true)
	if part == null:
		if edit_mode == EditMode.MODEL_EDIT:
			return select_active_model_root()
		return null

	api.set_selected_part(part)
	model_part_selected.emit(active_object, part)
	return part


func begin_move_at(world_point: Vector2) -> bool:
	if not enabled or active_object == null or api.active_model == null:
		return false

	var part: ModelData = select_part_at(world_point)
	if part == null or part == api.active_model:
		return false

	return api.begin_move_part(api.active_model, part)


func begin_move_selected() -> bool:
	if not enabled or active_object == null or api.active_model == null:
		return false
	var part: ModelData = api.selected_part
	if part == null or part == api.active_model:
		return false
	return api.begin_move_part(api.active_model, part)


func update_move_preview(world_point: Vector2, use_snapping: bool = true) -> Dictionary:
	if not enabled or api == null:
		return {}
	if api.moving_part == null:
		return {}
	return api.update_move_preview(world_point, use_snapping)


func get_move_preview() -> Dictionary:
	if api == null:
		return {}
	return api.get_move_preview()


func get_move_preview_footprint() -> PackedVector2Array:
	if api == null:
		return PackedVector2Array()
	return api.get_move_preview_footprint()


func get_snap_candidates_at(world_point: Vector2) -> Array:
	if not enabled or active_object == null or api.active_model == null:
		return []
	if api.moving_part == null:
		return []
	return api.get_snap_candidates(api.active_model, api.moving_part, world_point)


func get_best_snap_candidate_at(world_point: Vector2) -> Dictionary:
	if not enabled or active_object == null or api.active_model == null:
		return {}
	if api.moving_part == null:
		return {}
	return api.get_best_snap_candidate(api.active_model, api.moving_part, world_point)


func is_move_active() -> bool:
	return api != null and api.moving_part != null


func commit_move() -> bool:
	if api == null or api.moving_part == null:
		return false

	var preview: Dictionary = api.get_move_preview()
	var snap_type: ObjectModelBuilder.SnapType = ObjectModelBuilder.SnapType.NONE
	match int(preview.get("snap_type", ObjectModelBuilder.SnapType.NONE)):
		ObjectModelBuilder.SnapType.TOP:
			snap_type = ObjectModelBuilder.SnapType.TOP
		ObjectModelBuilder.SnapType.FRONT:
			snap_type = ObjectModelBuilder.SnapType.FRONT
		ObjectModelBuilder.SnapType.BACK:
			snap_type = ObjectModelBuilder.SnapType.BACK
		ObjectModelBuilder.SnapType.LEFT:
			snap_type = ObjectModelBuilder.SnapType.LEFT
		ObjectModelBuilder.SnapType.RIGHT:
			snap_type = ObjectModelBuilder.SnapType.RIGHT
	var target: ModelData = preview.get("target") as ModelData
	var result: bool = api.commit_move(snap_type, target)
	if result:
		_sync_host_renderer()
	return result


func commit_move_with_snap(snap_type: ObjectModelBuilder.SnapType, target: ModelData = null) -> bool:
	if api == null or api.moving_part == null:
		return false
	var result: bool = api.commit_move(snap_type, target)
	if result:
		_sync_host_renderer()
	return result


func cancel_move() -> void:
	if api == null:
		return
	api.cancel_move()
	_sync_host_renderer()


func detach_selected_part_and_begin_move() -> bool:
	if active_object == null or api.active_model == null or api.selected_part == null:
		return false
	var part: ModelData = api.selected_part
	if part == api.active_model:
		return false
	var result: bool = api.detach_part_and_begin_move(api.active_model, part)
	if result:
		_sync_host_renderer()
	return result


func combine_selected_part() -> ModelData:
	if active_object == null or api.active_model == null or api.selected_part == null:
		return null
	var part: ModelData = api.selected_part
	if part == api.active_model:
		return null

	var parent: ModelData = api.find_parent(api.active_model, part)
	if parent == null or parent.parts.size() < 2:
		return null

	var parts: Array[ModelData] = []
	for sibling in parent.parts:
		if sibling != null:
			parts.append(sibling)

	if parts.size() < 2:
		return null

	var combined: ModelData = api.combine_model(
		parent,
		parts,
		parent.model_name + " Assembly")
	if combined != null:
		api.set_selected_part(combined)
		_sync_host_renderer()
	return combined


func detach_selected_part() -> bool:
	if active_object == null or api.active_model == null or api.selected_part == null:
		return false
	var part: ModelData = api.selected_part
	if part == api.active_model:
		return false
	var result: bool = api.detach_part(api.active_model, part)
	if result:
		_sync_host_renderer()
	return result


func set_selected_part_textures(face: int, texture_set: ObjectFaceTextureData) -> bool:
	if api == null or api.selected_part == null:
		return false
	var result: bool = api.set_part_face_textures(api.selected_part, face, texture_set)
	if result:
		_sync_host_renderer()
	return result


func set_selected_part_top_texture_rotation(degrees: float) -> bool:
	if api == null or api.selected_part == null:
		return false
	var result: bool = api.set_part_top_texture_rotation(api.selected_part, degrees)
	if result:
		_sync_host_renderer()
	return result


func paint_selected_part_base_color(color: Color, enable_fallback: bool = true) -> bool:
	if api == null or api.selected_part == null:
		return false
	var result: bool = api.paint_part_base_color(api.selected_part, color, enable_fallback)
	if result:
		_sync_host_renderer()
	return result



func open_model_editor_for_part(part: ModelData = null) -> bool:
	if not enabled or model_editor == null or api == null:
		return false
	var target: ModelData = part
	if target == null:
		target = api.selected_part
	if target == null:
		target = api.active_model
	if target == null:
		return false

	if edit_mode == EditMode.MODEL_CREATE:
		var root: ModelData = _find_workspace_root_for_part(target)
		if root == null and workspace_models.has(target):
			root = target
		if root != null:
			workspace_context_model = root
			workspace_hovered_model = root
			if not workspace_selected_models.has(root):
				workspace_selected_models.clear()
				workspace_selected_models.append(root)
			api.set_active_model(root)
			api.set_selected_part(target)

	var editor_object: ObjectData = active_object
	return model_editor.open(editor_object, target)


func _find_workspace_root_for_part(part: ModelData) -> ModelData:
	if part == null:
		return null
	if workspace_models.has(part):
		return part
	for root in workspace_models:
		if root == null:
			continue
		if api != null and api.contains_part(root, part, true):
			return root
	return null


func _open_selected_model_editor() -> void:
	if api == null:
		return
	if not open_model_editor_for_part(api.selected_part):
		_show_status("No model part is available to edit.")


func populate_context_menu(menu: PopupMenu) -> void:
	if menu == null or api == null:
		return

	workspace_context_part_edit_targets.clear()

	if edit_mode == EditMode.MODEL_CREATE:
		if free_attach_active:
			menu.add_item("Free Attach Mode", -1)
			var free_info_index: int = menu.item_count - 1
			menu.set_item_disabled(free_info_index, true)
			menu.add_item("Edit Free-Attach Model", ACTION_EDIT_MODEL)
			if free_attach_target != null:
				menu.add_item("Confirm Free Attach + Combine", ACTION_CONFIRM_FREE_ATTACH)
			menu.add_item("Cancel Free Attach", ACTION_CANCEL_FREE_ATTACH)
			return

		menu.add_item("Model Create Mode", -1)
		var create_info_index: int = menu.item_count - 1
		menu.set_item_disabled(create_info_index, true)

		_ensure_model_load_menu(menu)
		_populate_model_load_menu()
		menu.add_submenu_node_item("Load Model Here", model_load_menu)

		if model_create_preview_active and model_create_model != null:
			menu.add_item("Edit Model Preview", ACTION_EDIT_MODEL)
			menu.add_item("Save Model Preview", ACTION_SAVE_WORKSPACE_MODEL)
			menu.add_item("Place Model Here", ACTION_CREATE_MODEL_AT_CURSOR)
		else:
			var context_model: ModelData = workspace_context_model
			if context_model == null:
				context_model = workspace_hovered_model
			if context_model == null and workspace_selected_models.size() == 1:
				context_model = workspace_selected_models[0]
			if context_model != null and workspace_models.has(context_model):
				menu.add_item("Edit Entire Model", ACTION_EDIT_MODEL)
				_append_workspace_part_edit_actions(menu, context_model)
				menu.add_item("Save Model", ACTION_SAVE_WORKSPACE_MODEL)
				menu.add_item("Copy Model", ACTION_COPY_MODEL)
				menu.add_item("Delete Model", ACTION_DELETE_WORKSPACE_MODEL)
				menu.add_separator()
				menu.add_item("Render Behind", ACTION_RENDER_BEHIND)
				menu.add_item("Render In Front", ACTION_RENDER_IN_FRONT)
				menu.add_item("Reset Render Order", ACTION_RESET_RENDER_ORDER)
				menu.add_item("Move Model", ACTION_MOVE_WORKSPACE_MODEL)
				menu.add_item("Free Attach Mode", ACTION_FREE_ATTACH_MODEL)
				var nearby_attach_candidates: Array = get_nearby_workspace_attach_candidates(context_model)
				if not nearby_attach_candidates.is_empty():
					menu.add_item("Attach to Nearby Model...", ACTION_ATTACH_NEARBY_MODEL)
			if workspace_selected_models.size() >= 2:
				menu.add_item(
					"Combine Selected Models (%d)" % workspace_selected_models.size(),
					ACTION_COMBINE_WORKSPACE_MODELS)
			menu.add_item("Create New Model", ACTION_CREATE_NEW_MODEL)

		menu.add_separator()
		menu.add_item("Exit Model Create Mode", ACTION_EXIT_MODEL_MODE)
		return

	if active_object == null:
		return

	var model: ModelData = _get_model(active_object)
	if model == null:
		menu.add_separator()
		menu.add_item("Insert Model", ACTION_CREATE_MODEL)
		return

	menu.add_separator()
	menu.add_item("Edit Model", ACTION_EDIT_MODEL)

	var part: ModelData = api.selected_part
	var part_name: String = part.model_name if part != null else model.model_name
	menu.add_item("Selected Part: %s" % part_name, -1)
	var part_info_index: int = menu.item_count - 1
	menu.set_item_disabled(part_info_index, true)

	if is_move_active():
		menu.add_separator()
		menu.add_item("Confirm Model Part Move", ACTION_CONFIRM_MOVE)
		menu.add_item("Cancel Model Part Move", ACTION_CANCEL_MOVE)
		_append_snap_actions(menu)
		return

	if part != null and part != model:
		menu.add_item("Move Model Part", ACTION_MOVE_PART)
		menu.add_item("Detach Part + Move", ACTION_DETACH_PART)
		if _can_combine_selected_part():
			menu.add_item("Combine Sibling Parts", ACTION_COMBINE_PARTS)
		menu.add_item("Set Part Textures", ACTION_EDIT_PART_TEXTURES)
		menu.add_item("Paint Part Base Color", ACTION_PAINT_PART)
		menu.add_item("Render Part Behind", ACTION_RENDER_BEHIND)
		menu.add_item("Render Part In Front", ACTION_RENDER_IN_FRONT)
		menu.add_item("Reset Part Render Order", ACTION_RESET_RENDER_ORDER)

	menu.add_item("Exit Model Edit Mode", ACTION_EXIT_MODEL_MODE)
	menu.add_item("Clear Custom Model", ACTION_CLEAR_MODEL)


func _append_workspace_part_edit_actions(menu: PopupMenu, root: ModelData) -> void:
	if menu == null or root == null:
		return

	var all_parts: Array[ModelData] = root.get_all_parts_recursive(false)
	if all_parts.is_empty():
		return

	menu.add_separator()
	menu.add_item("Edit Individual Parts", -1)
	var part_header_index: int = menu.item_count - 1
	menu.set_item_disabled(part_header_index, true)

	for part_index: int in range(all_parts.size()):
		var part: ModelData = all_parts[part_index]
		if part == null:
			continue
		var action_id: int = ACTION_EDIT_WORKSPACE_PART_BASE + workspace_context_part_edit_targets.size()
		workspace_context_part_edit_targets.append(part)
		var part_name: String = part.model_name
		if part_name.is_empty():
			part_name = "Unnamed Part"
		menu.add_item("Edit Part %d: %s" % [part_index + 1, part_name], action_id)


func _handle_workspace_part_edit_action(id: int) -> bool:
	var target_index: int = id - ACTION_EDIT_WORKSPACE_PART_BASE
	if target_index < 0 or target_index >= workspace_context_part_edit_targets.size():
		return false
	var target: ModelData = workspace_context_part_edit_targets[target_index]
	if target == null:
		return false
	if open_model_editor_for_part(target):
		_show_status("Editing model part: %s." % target.model_name)
	return true


func _get_context_render_order_target() -> ModelData:
	if edit_mode == EditMode.MODEL_CREATE:
		if workspace_context_model != null and workspace_models.has(workspace_context_model):
			return workspace_context_model
		if workspace_hovered_model != null and workspace_models.has(workspace_hovered_model):
			return workspace_hovered_model
		if workspace_selected_models.size() == 1 and workspace_models.has(workspace_selected_models[0]):
			return workspace_selected_models[0]
		return null

	if api != null and api.selected_part != null:
		return api.selected_part
	return api.active_model if api != null else null


func _adjust_context_render_order(delta: int) -> bool:
	var target: ModelData = _get_context_render_order_target()
	if target == null:
		return false
	target.render_order += delta
	target.emit_changed()
	_sync_model_renderer()
	_sync_host_renderer()
	if active_object != null:
		active_object.emit_changed()
	if room_data != null:
		room_data.emit_changed()
	_show_status("Render order for %s: %d." % [target.model_name, target.render_order])
	return true


func _reset_context_render_order() -> bool:
	var target: ModelData = _get_context_render_order_target()
	if target == null:
		return false
	target.render_order = 0
	target.emit_changed()
	_sync_model_renderer()
	_sync_host_renderer()
	if active_object != null:
		active_object.emit_changed()
	if room_data != null:
		room_data.emit_changed()
	_show_status("Render order reset for %s." % target.model_name)
	return true


func handle_context_action(id: int) -> bool:
	if not enabled or api == null:
		return false

	if id >= ACTION_EDIT_WORKSPACE_PART_BASE and id < ACTION_EDIT_WORKSPACE_PART_BASE + workspace_context_part_edit_targets.size():
		return _handle_workspace_part_edit_action(id)

	match id:
		ACTION_RENDER_BEHIND:
			_adjust_context_render_order(-1)
			return true

		ACTION_RENDER_IN_FRONT:
			_adjust_context_render_order(1)
			return true

		ACTION_RESET_RENDER_ORDER:
			_reset_context_render_order()
			return true

		ACTION_CREATE_MODEL_AT_CURSOR:
			if edit_mode == EditMode.MODEL_CREATE and model_create_model != null:
				place_model_create_preview(model_create_preview_position)
			return true

		ACTION_MOVE_MODEL_PREVIEW:
			if edit_mode == EditMode.MODEL_CREATE:
				move_model_create_preview_again(workspace_context_model)
			return true

		ACTION_MOVE_WORKSPACE_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				if move_model_create_preview_again(workspace_context_model):
					_show_status("Moving model. Left-click to place it at the cursor.")
			return true

		ACTION_ATTACH_NEARBY_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				open_attach_nearby_model_prompt(workspace_context_model)
			return true

		ACTION_FREE_ATTACH_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				begin_free_attach_workspace_model(workspace_context_model)
			return true

		ACTION_SAVE_WORKSPACE_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				save_workspace_model()
			return true

		ACTION_TRANSPOSE_WORKSPACE_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				transpose_entire_model_into_object()
			return true

		ACTION_COPY_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				copy_workspace_model()
			return true

		ACTION_DELETE_WORKSPACE_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				delete_workspace_model(workspace_context_model)
			return true

		ACTION_CONFIRM_FREE_ATTACH:
			if free_attach_active:
				confirm_free_attach()
			return true

		ACTION_CANCEL_FREE_ATTACH:
			cancel_free_attach()
			return true

		ACTION_COMBINE_WORKSPACE_MODELS:
			if edit_mode == EditMode.MODEL_CREATE:
				combine_selected_workspace_models()
			return true

		ACTION_CREATE_NEW_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				model_create_prompt_position = model_create_world_position
				_popup_model_create_prompt()
			return true

		ACTION_EXIT_MODEL_MODE:
			exit_model_mode()
			_show_status("Model editing mode exited.")
			return true

		ACTION_CREATE_MODEL:
			if active_object == null:
				return true
			if begin_model_edit_mode(active_object):
				_open_selected_model_editor()
				_show_status("Inserted a model into %s." % active_object.object_name)
			return true

		ACTION_EDIT_MODEL:
			if edit_mode == EditMode.MODEL_CREATE:
				var edit_target: ModelData = null
				if model_create_preview_active and model_create_model != null:
					edit_target = model_create_model
				else:
					edit_target = workspace_context_model
				if edit_target == null:
					edit_target = workspace_hovered_model
				if edit_target == null and workspace_selected_models.size() == 1:
					edit_target = workspace_selected_models[0]
				if edit_target != null and open_model_editor_for_part(edit_target):
					return true
				return true
			if active_object != null and begin_model_edit_mode(active_object):
				_open_selected_model_editor()
			return true

		ACTION_MOVE_PART:
			if begin_move_selected():
				_show_status("Dragging model part. Move it, then right-click to confirm or choose a snap.")
			return true

		ACTION_DETACH_PART:
			if detach_selected_part_and_begin_move():
				_show_status("Detached model part. Drag it away, then right-click to confirm.")
			return true

		ACTION_COMBINE_PARTS:
			var combined: ModelData = combine_selected_part()
			if combined != null:
				_show_status("Combined model parts into %s." % combined.model_name)
			return true

		ACTION_EDIT_PART_TEXTURES:
			if active_object != null and api.selected_part != null:
				part_texture_edit_requested.emit(active_object, api.selected_part)
				_show_status("Model-part texture editing requested for %s." % api.selected_part.model_name)
			return true

		ACTION_PAINT_PART:
			if active_object != null and api.selected_part != null:
				part_color_edit_requested.emit(active_object, api.selected_part)
				_show_status("Model-part color editing requested for %s." % api.selected_part.model_name)
			return true

		ACTION_CLEAR_MODEL:
			if active_object != null and clear_object_model(active_object):
				_show_status("Cleared custom model from %s. Legacy ISO geometry is now the fallback.")
			return true

		ACTION_CONFIRM_MOVE:
			if commit_move():
				_show_status("Model part move confirmed.")
			return true

		ACTION_CANCEL_MOVE:
			cancel_move()
			_show_status("Model part move cancelled.")
			return true

		ACTION_SNAP_TOP:
			return _commit_snap_action(ObjectModelBuilder.SnapType.TOP)
		ACTION_SNAP_FRONT:
			return _commit_snap_action(ObjectModelBuilder.SnapType.FRONT)
		ACTION_SNAP_BACK:
			return _commit_snap_action(ObjectModelBuilder.SnapType.BACK)
		ACTION_SNAP_LEFT:
			return _commit_snap_action(ObjectModelBuilder.SnapType.LEFT)
		ACTION_SNAP_RIGHT:
			return _commit_snap_action(ObjectModelBuilder.SnapType.RIGHT)

	return false


func _append_snap_actions(menu: PopupMenu) -> void:
	var candidates: Array = api.move_preview_candidates
	if candidates.is_empty():
		return

	var available: Dictionary = {}
	for candidate in candidates:
		if not bool(candidate.get("within_threshold", false)):
			continue
		var snap_type: int = int(candidate.get("snap_type", ObjectModelBuilder.SnapType.NONE))
		if available.has(snap_type):
			continue
		available[snap_type] = candidate

	if available.is_empty():
		return

	menu.add_separator()
	if available.has(ObjectModelBuilder.SnapType.TOP):
		menu.add_item("Snap to Top", ACTION_SNAP_TOP)
	if available.has(ObjectModelBuilder.SnapType.FRONT):
		menu.add_item("Snap to Front Side", ACTION_SNAP_FRONT)
	if available.has(ObjectModelBuilder.SnapType.BACK):
		menu.add_item("Snap to Back Side", ACTION_SNAP_BACK)
	if available.has(ObjectModelBuilder.SnapType.LEFT):
		menu.add_item("Snap to Left Side", ACTION_SNAP_LEFT)
	if available.has(ObjectModelBuilder.SnapType.RIGHT):
		menu.add_item("Snap to Right Side", ACTION_SNAP_RIGHT)


func _commit_snap_action(snap_type: ObjectModelBuilder.SnapType) -> bool:
	if api == null or api.moving_part == null:
		return true
	var candidate: Dictionary = _find_current_candidate(snap_type)
	if candidate.is_empty():
		return true
	var target: ModelData = candidate.get("target") as ModelData
	if commit_move_with_snap(snap_type, target):
		_show_status("Model part snapped to %s." % _snap_type_name(snap_type))
	return true


func _find_current_candidate(snap_type: ObjectModelBuilder.SnapType) -> Dictionary:
	for candidate in api.move_preview_candidates:
		if int(candidate.get("snap_type", ObjectModelBuilder.SnapType.NONE)) == int(snap_type):
			if bool(candidate.get("within_threshold", false)):
				return candidate
	return {}


func _can_combine_selected_part() -> bool:
	if api == null or api.active_model == null or api.selected_part == null:
		return false
	var parent: ModelData = api.find_parent(api.active_model, api.selected_part)
	return parent != null and parent.parts.size() >= 2


func _get_model(object_data: ObjectData) -> ModelData:
	if object_data == null or object_data.object_model == null:
		return null
	return object_data.object_model as ModelData


func _can_edit_object(object_data: ObjectData) -> bool:
	if not enabled or object_data == null:
		return false
	if room_data == null:
		return false
	return room_data.has_object(object_data)


func _sync_host_renderer() -> void:
	if host == null or not is_instance_valid(host):
		return
	if host.has_method("_sync_renderer"):
		host.call("_sync_renderer")


func _show_status(message: String) -> void:
	if host == null or not is_instance_valid(host):
		return
	if host.has_method("_show_status"):
		host.call("_show_status", message)


func _snap_type_name(snap_type: ObjectModelBuilder.SnapType) -> String:
	match snap_type:
		ObjectModelBuilder.SnapType.TOP:
			return "the top"
		ObjectModelBuilder.SnapType.FRONT:
			return "the front side"
		ObjectModelBuilder.SnapType.BACK:
			return "the back side"
		ObjectModelBuilder.SnapType.LEFT:
			return "the left side"
		ObjectModelBuilder.SnapType.RIGHT:
			return "the right side"
	return "the model"


func _on_model_editor_applied(part: ModelData) -> void:
	if part == null:
		return

	if edit_mode == EditMode.MODEL_CREATE:
		var root: ModelData = _find_workspace_root_for_part(part)
		if root != null:
			workspace_hovered_model = root
			workspace_context_model = root
			workspace_selected_models.clear()
			workspace_selected_models.append(root)
			api.set_active_model(root)
			api.set_selected_part(part)

	_sync_model_renderer()
	_sync_host_renderer()
	if active_object != null and room_data != null:
		active_object.emit_changed()
		room_data.emit_changed()
	model_changed.emit(active_object, api.active_model)


func _on_model_editor_cancelled(_part: ModelData) -> void:
	pass


func _on_api_model_changed(model: ModelData) -> void:
	if active_object == null or model == null:
		return
	_sync_host_renderer()
	model_changed.emit(active_object, model)


func _on_api_selection_changed(part: ModelData) -> void:
	if active_object == null:
		return
	model_part_selected.emit(active_object, part)


func _on_api_move_preview_changed(part: ModelData, preview: Dictionary) -> void:
	if active_object == null:
		return
	move_preview_changed.emit(active_object, part, preview)


func _on_api_snap_candidates_changed(part: ModelData, candidates: Array) -> void:
	if active_object == null:
		return
	snap_candidates_changed.emit(active_object, part, candidates)
