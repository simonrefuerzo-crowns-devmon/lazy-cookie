extends Node2D
class_name RoomRenderer


@export_category("Room")
@export var room_data: RoomData


@export_category("Rendering")
@export var wall_z_index: int = 0
@export var visible_room: bool = true


@export_category("Isometric")
@export var isometric: bool = true:
	set(value):
		if isometric == value:
			return
		isometric = value
		_rebuild_renderers()

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


@export_category("Object Pixel Art")
## Pixel size used by PixelObjectRenderer.
@export_range(1, 16, 1)
var object_pixelation_rate: int = 2

## Pixel outline width in pixel cells.
@export_range(1, 8, 1)
var object_line_width_px: int = 1

## Darkness applied to object pixel outlines.
@export_range(0.0, 1.0, 0.05)
var object_line_darkness: float = 0.35

## PixelObjectRenderer rasterizes object fills when enabled.
@export var pixelate_object_fills: bool = true


@export_category("Object Isometric")
## Z layer used by the ISO object renderer.
## Objects render above walls and floors.
@export var object_z_index_offset: int = 1

## Render the ISO objects contained by ObjectData.contained_objects when supported.
@export var render_contained_objects: bool = false


@export_category("Baking")
## Bake the pixel look into textures instead of redrawing every cell.
@export var bake_pixel_art: bool = true

## Draw cheap vector renders during smooth turns, then bake once settled.
## Used by PixelWallRenderer and PixelFloorRenderer.
@export var vector_while_turning: bool = true

@export_range(0.02, 1.0, 0.01)
var view_settle_time: float = 0.12


var _wall_renderer: WallRenderer
var _floor_renderer: FloorRenderer

## Regular top-down object renderer.
## PixelObjectRenderer is used for the regular/non-isometric pass.
var _object_renderer: ObjectRenderer

## Existing isometric object renderer.
var _iso_object_renderer: IsoObjectRenderer

var _connected_room_data: RoomData


func _ready() -> void:
	_rebuild_renderers()
	_connect_room_data()
	_refresh()


func _exit_tree() -> void:
	_disconnect_room_data()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_renderer_visibility()


# -------------------------------------------------------------------------
# Renderer construction
# -------------------------------------------------------------------------

func _rebuild_renderers() -> void:
	_disconnect_renderers()

	_create_wall_renderer()
	_create_floor_renderer()
	_create_object_renderer()
	_create_iso_object_renderer()

	_apply_renderer_settings()
	_refresh()


func _disconnect_renderers() -> void:
	_wall_renderer = null
	_floor_renderer = null
	_object_renderer = null
	_iso_object_renderer = null

	for child in get_children():
		if child is WallRenderer \
		or child is FloorRenderer \
		or child is ObjectRenderer \
		or child is IsoObjectRenderer:
			child.queue_free()


func _create_wall_renderer() -> void:
	if isometric:
		_wall_renderer = PixelWallRenderer.new()
	else:
		_wall_renderer = WallRenderer.new()

	_wall_renderer.name = "WallRenderer"
	_wall_renderer.z_index = wall_z_index

	add_child(_wall_renderer)

	_apply_wall_renderer_settings()


func _create_floor_renderer() -> void:
	if isometric:
		_floor_renderer = PixelFloorRenderer.new()
	else:
		_floor_renderer = FloorRenderer.new()

	_floor_renderer.name = "FloorRenderer"
	_floor_renderer.z_index = wall_z_index - 1

	add_child(_floor_renderer)

	_apply_floor_renderer_settings()


func _create_object_renderer() -> void:
	# PixelObjectRenderer is the regular top-down/world-space renderer.
	# It is deliberately separate from IsoObjectRenderer because its geometry
	# is not projected isometrically.
	_object_renderer = PixelObjectRenderer.new()
	_object_renderer.name = "PixelObjectRenderer"
	_object_renderer.z_index = wall_z_index + 1

	add_child(_object_renderer)


func _create_iso_object_renderer() -> void:
	if not isometric:
		return

	_iso_object_renderer = IsoObjectRenderer.new()
	_iso_object_renderer.name = "IsoObjectRenderer"
	_iso_object_renderer.z_index = wall_z_index + object_z_index_offset
	_iso_object_renderer.render_contained_objects = render_contained_objects

	add_child(_iso_object_renderer)


# -------------------------------------------------------------------------
# Renderer settings
# -------------------------------------------------------------------------

func _apply_renderer_settings() -> void:
	_apply_wall_renderer_settings()
	_apply_floor_renderer_settings()
	_apply_object_renderer_settings()
	_apply_iso_object_renderer_settings()


func _apply_wall_renderer_settings() -> void:
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
		pixel_renderer.bake_enabled = bake_pixel_art
		pixel_renderer.vector_while_turning = vector_while_turning
		pixel_renderer.view_settle_time = view_settle_time


func _apply_floor_renderer_settings() -> void:
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
		pixel_floor_renderer.bake_enabled = bake_pixel_art
		pixel_floor_renderer.vector_while_turning = vector_while_turning
		pixel_floor_renderer.view_settle_time = view_settle_time

func _apply_object_renderer_settings() -> void:
	if _object_renderer == null:
		return

	_object_renderer.render_contained_objects = render_contained_objects

	if _object_renderer is PixelObjectRenderer:
		var pixel_object_renderer: PixelObjectRenderer = (
			_object_renderer as PixelObjectRenderer
		)

		pixel_object_renderer.pixelation_rate = object_pixelation_rate
		pixel_object_renderer.line_width_px = object_line_width_px
		pixel_object_renderer.line_darkness = object_line_darkness
		pixel_object_renderer.pixelate_fills = pixelate_object_fills
		pixel_object_renderer.bake_enabled = bake_pixel_art


func _apply_iso_object_renderer_settings() -> void:
	if _iso_object_renderer == null:
		return

	if _wall_renderer == null:
		return

	if not (_wall_renderer is IsoWallRenderer):
		return

	var projector: IsoWallRenderer = (
		_wall_renderer as IsoWallRenderer
	)

	_iso_object_renderer.render_contained_objects = (
		render_contained_objects
	)

	_iso_object_renderer.set_view_from_projector(
		projector
	)


# -------------------------------------------------------------------------
# Room data
# -------------------------------------------------------------------------

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


# -------------------------------------------------------------------------
# Refresh
# -------------------------------------------------------------------------

func _refresh() -> void:
	if _wall_renderer == null:
		return

	if room_data == null:
		_wall_renderer.set_room(null)

		if _floor_renderer != null:
			_floor_renderer.set_room(null)

		if _object_renderer != null:
			_object_renderer.set_room(null)

		if _iso_object_renderer != null:
			_iso_object_renderer.set_room(null)

		return

	_apply_renderer_settings()

	_wall_renderer.set_room(room_data)

	_apply_floor_view()

	if _floor_renderer != null:
		_floor_renderer.set_room(room_data)

	if _object_renderer != null:
		_object_renderer.set_room(room_data)

	if _iso_object_renderer != null:
		_apply_iso_object_renderer_settings()
		
		if _iso_object_renderer != null:
			_iso_object_renderer.set_room(room_data)

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


# -------------------------------------------------------------------------
# Visibility
# -------------------------------------------------------------------------

func _update_renderer_visibility() -> void:
	if _wall_renderer == null:
		return

	var room_visible: bool = (
		visible_room
		and visible
	)

	_wall_renderer.visible = room_visible

	if _floor_renderer != null:
		_floor_renderer.visible = room_visible

	# PixelObjectRenderer is the regular top-down object pass.
	# It must not be displayed simultaneously with the ISO object renderer.
	if _object_renderer != null:
		_object_renderer.visible = (
			room_visible
			and not isometric
		)

	if _iso_object_renderer != null:
		_iso_object_renderer.visible = (
			room_visible
			and isometric
		)


# -------------------------------------------------------------------------
# Change notification
# -------------------------------------------------------------------------

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
