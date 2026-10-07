class_name RoomBuilderPersistence
extends RefCounted

## RoomData save operations and automatic texture-save path.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func on_save_confirmed() -> void:
	var file_name := ctx.name_edit.text.strip_edges().trim_suffix(".tres").validate_filename()
	if file_name.is_empty():
		ctx.ui_module.set_status("Save cancelled: the name can't be empty.")
		return

	if not DirAccess.dir_exists_absolute(ctx.save_dir):
		var dir_err := DirAccess.make_dir_recursive_absolute(ctx.save_dir)
		if dir_err != OK:
			ctx.ui_module.set_status("Couldn't create %s (error %d)." % [ctx.save_dir, dir_err])
			return

	var path := ctx.save_dir + file_name + ".tres"
	var err := ResourceSaver.save(ctx.room_data, path)
	if err == OK:
		ctx.last_saved_name = file_name
		ctx.ui_module.set_status("Saved %s" % path)
	else:
		ctx.ui_module.set_status("Save failed (error %d). Is res:// writable?" % err)


func get_saved_room_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(ctx.save_dir)
	if dir == null:
		return paths

	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() != "tres":
			continue
		paths.append(ctx.save_dir.path_join(file_name))

	paths.sort()
	return paths

func load_room(path: String) -> void:
	var loaded_resource: Resource = ResourceLoader.load(path)
	var loaded_room := loaded_resource as RoomData
	if loaded_room == null:
		ctx.ui_module.set_status("Load failed: %s is not a RoomData resource." % path)
		return

	ctx.host.set_room_data(loaded_room)
	ctx.last_saved_name = path.get_file().trim_suffix(".tres")
	ctx.ui_module.set_status("Loaded %s" % path)


# ---------------------------------------------------------------- Renderer / Iso views

func save_current_room_data() -> void:
	if ctx.room_data == null:
		return
	if not DirAccess.dir_exists_absolute(ctx.save_dir):
		var dir_err := DirAccess.make_dir_recursive_absolute(ctx.save_dir)
		if dir_err != OK:
			ctx.ui_module.set_status("Room texture changed, but save folder could not be created (error %d)." % dir_err)
			return

	var file_name := ctx.last_saved_name.strip_edges().trim_suffix(".tres").validate_filename()
	if file_name.is_empty():
		file_name = "room1"
		ctx.last_saved_name = file_name

	var path := ctx.save_dir + file_name + ".tres"
	var err := ResourceSaver.save(ctx.room_data, path)
	if err != OK:
		ctx.ui_module.set_status("RoomData updated, but automatic save failed (error %d)." % err)


# ---------------------------------------------------------------- Grid

func on_save_canceled() -> void:
	ctx.ui_module.set_status("Save cancelled.")

