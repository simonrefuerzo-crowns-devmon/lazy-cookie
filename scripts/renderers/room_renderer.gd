extends Node2D
class_name RoomRenderer


@export_category("Room")
@export var room_data: RoomData


@export_category("Rendering")
@export var wall_z_index: int = 0
@export var visible_room: bool = true


@export_category("Isometric")
@export var isometric: bool = true
@export var wall_height: float = 96.0
@export_range(10.0, 45.0, 0.5)
var projection_angle: float = 30.0
@export_range(0, 3)
var view_quadrant: int = 0
@export var view_pivot: Vector2 = Vector2.ZERO


@export_category("Pixel Art")
@export_range(1, 16, 1)
var pixelation_rate: int = 2

@export_range(1, 8, 1)
var line_width_px: int = 1

@export_range(0.0, 1.0, 0.05)
var line_darkness: float = 0.35

@export var counter_iso_textures: bool = true
@export var pixelate_fills: bool = true

@export_category("Floor Pixel Art")
@export_range(1, 16, 1)
var floor_pixelation_rate: int = 2
@export_range(1, 8, 1)
var floor_outline_width_px: int = 1
@export_range(0.0, 1.0, 0.05)
var floor_outline_darkness: float = 0.35
@export var pixelate_floor_fills: bool = true
@export var pixelate_floor_textures: bool = true


var _wall_renderer: WallRenderer
var _floor_renderer: FloorRenderer
var _connected_room_data: RoomData


func _ready() -> void:
	_create_wall_renderer()
	_create_floor_renderer()
	_connect_room_data()
	_refresh()


func _exit_tree() -> void:
	_disconnect_room_data()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_renderer_visibility()


func _create_wall_renderer() -> void:
	if isometric:
		_wall_renderer = PixelWallRenderer.new()
	else:
		_wall_renderer = WallRenderer.new()

	_wall_renderer.name = "WallRenderer"
	_wall_renderer.z_index = wall_z_index

	add_child(_wall_renderer)

	_apply_renderer_settings()


func _create_floor_renderer() -> void:
	if isometric:
		_floor_renderer = PixelFloorRenderer.new()
	else:
		_floor_renderer = FloorRenderer.new()

	_floor_renderer.name = "FloorRenderer"
	_floor_renderer.z_index = wall_z_index - 1

	add_child(_floor_renderer)

	_apply_renderer_settings()


func _apply_renderer_settings() -> void:
	if _wall_renderer == null:
		return

	if _wall_renderer is IsoWallRenderer:
		var iso_renderer: IsoWallRenderer = (
			_wall_renderer as IsoWallRenderer
		)

		iso_renderer.wall_height = wall_height
		iso_renderer.projection_angle = projection_angle
		iso_renderer.view_quadrant = view_quadrant
		iso_renderer.view_pivot = view_pivot

	if _wall_renderer is PixelWallRenderer:
		var pixel_renderer: PixelWallRenderer = (
			_wall_renderer as PixelWallRenderer
		)

		pixel_renderer.pixelation_rate = pixelation_rate
		pixel_renderer.line_width_px = line_width_px
		pixel_renderer.line_darkness = line_darkness
		pixel_renderer.counter_iso_textures = counter_iso_textures
		pixel_renderer.pixelate_fills = pixelate_fills


	if _floor_renderer == null:
		return

	if _floor_renderer is PixelFloorRenderer:
		var pixel_floor_renderer: PixelFloorRenderer = (
			_floor_renderer as PixelFloorRenderer
		)

		pixel_floor_renderer.pixelation_rate = floor_pixelation_rate
		pixel_floor_renderer.outline_width_px = floor_outline_width_px
		pixel_floor_renderer.outline_darkness = floor_outline_darkness
		pixel_floor_renderer.pixelate_fills = pixelate_floor_fills
		pixel_floor_renderer.pixelate_textures = pixelate_floor_textures


func _connect_room_data() -> void:
	if _connected_room_data == room_data:
		return

	_disconnect_room_data()

	if room_data == null:
		return

	_connected_room_data = room_data

	if not _connected_room_data.changed.is_connected(
		_on_room_data_changed
	):
		_connected_room_data.changed.connect(
			_on_room_data_changed
		)


func _disconnect_room_data() -> void:
	if _connected_room_data == null:
		return

	if _connected_room_data.changed.is_connected(
		_on_room_data_changed
	):
		_connected_room_data.changed.disconnect(
			_on_room_data_changed
		)

	_connected_room_data = null


func _refresh() -> void:
	if _wall_renderer == null:
		return

	if room_data == null:
		_wall_renderer.set_segments([])
		if _floor_renderer != null:
			_floor_renderer.set_room(null)
		return

	_apply_renderer_settings()

	_wall_renderer.set_room(
		room_data
	)

	if _floor_renderer != null:
		_apply_floor_view()
		_floor_renderer.set_room(room_data)

	_update_renderer_visibility()


func _apply_floor_view() -> void:
	if _floor_renderer == null:
		return

	var projector: IsoWallRenderer = null
	if isometric and _wall_renderer is IsoWallRenderer:
		projector = _wall_renderer as IsoWallRenderer

	_floor_renderer.set_view(
		isometric,
		projector
	)


func _update_renderer_visibility() -> void:
	if _wall_renderer == null:
		return

	var room_visible := visible_room and visible

	_wall_renderer.visible = room_visible

	if _floor_renderer != null:
		_floor_renderer.visible = room_visible


func _on_room_data_changed() -> void:
	_refresh()


func set_room_data(value: RoomData) -> void:
	if room_data == value:
		return

	_disconnect_room_data()

	room_data = value

	_connect_room_data()
	_refresh()


func refresh() -> void:
	_connect_room_data()
	_refresh()
