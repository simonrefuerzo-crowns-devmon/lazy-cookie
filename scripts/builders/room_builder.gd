# room_builder.gd
class_name RoomBuilder
extends Node2D

const State = RoomBuilderTypes.State
const Operation = RoomBuilderTypes.Operation

@export var room_data: RoomData
@export var snap_size: float = 4.0
@export var grid_visible: bool = true ## Shows/hides the construction grid.
@export var grid_size: float = 4.0 ## Grid spacing in pixels. Defaults to snap_size when <= 0.
@export var grid_line_color: Color = Color(1.0, 1.0, 1.0, 0.08)
@export var grid_axis_color: Color = Color(1.0, 1.0, 1.0, 0.16)
@export var snap_radius: float = 10.0
@export var wall_hit_padding: float = 2.0
@export var default_color: Color = Color.WHITE
@export var default_thickness: float = 24.0
@export var default_line_width: float = 3.0
@export var default_start_cap: WallSegment.CapStyle = WallSegment.CapStyle.FLAT
@export var default_end_cap: WallSegment.CapStyle = WallSegment.CapStyle.FLAT
@export var default_floor_color: Color = Color(0.72, 0.72, 0.72, 1.0)
@export_range(8.0, 1024.0, 1.0) var floor_texture_tile_size: float = 64.0
@export_range(0.1, 1.0) var ghost_alpha: float = 0.45

@export_category("Rendering")
@export_enum("Wall Render", "Iso Wall Render") var initial_render_mode: int = 1
@export_range(0.0, 256.0, 1.0) var iso_wall_height: float = 96.0
@export_range(10.0, 45.0, 0.5) var iso_projection_angle: float = 30.0
@export_range(0, 3) var iso_view_quadrant: int = 0

@export_category("Debug")
@export var DEBUG_MODE: bool = true
@export var debug_texture_directory: String = "res://assets/textures/wall_texture/"
@export_range(8.0, 256.0, 1.0) var debug_texture_tile_size: float = 32.0
@export_range(0.05, 1.0, 0.01) var renderer_switch_duration: float = 0.22

var _ctx: RoomBuilderContext
var _grid: RoomBuilderGrid
var _rendering: RoomBuilderRendering
var _input: RoomBuilderInput
var _wall_ops: RoomBuilderWallOps
var _editing: RoomBuilderEditing
var _texture: RoomBuilderTextureEditing
var _persistence: RoomBuilderPersistence
var _floor_ops: RoomBuilderFloorOps
var _ui: RoomBuilderUI

func _ready() -> void:
	_ctx = _make_context()
	_create_modules()
	if _ctx.room_data == null:
		_ctx.room_data = RoomData.new()
		room_data = _ctx.room_data
	if not _ctx.DEBUG_MODE:
		return

	_ctx.pending_color = default_color
	_ctx.pending_thickness = default_thickness
	_ctx.pending_line_width = default_line_width
	_ctx.pending_start_cap = default_start_cap
	_ctx.pending_end_cap = default_end_cap
	_ctx.isometric_mode = initial_render_mode == 1

	if not _ctx.room_data.changed.is_connected(rebuild_walls):
		_ctx.room_data.changed.connect(rebuild_walls)

	_grid.setup()
	_rendering.setup()
	_ui.setup()
	rebuild_walls()
	_set_status("Left click an empty area to start a wall. Click an existing wall to edit it. Right click an open area for renderer / Iso views. Right click a wall or floor for editing.")
	_floor_ops.prompt_for_new_enclosures()

func set_room_data(new_room_data: RoomData) -> void:
	if new_room_data == null or _ctx == null:
		return

	if _ctx.room_data != null and _ctx.room_data.changed.is_connected(rebuild_walls):
		_ctx.room_data.changed.disconnect(rebuild_walls)

	room_data = new_room_data
	_ctx.room_data = new_room_data
	_ctx.selected_segment = null
	_ctx.selected_point = Vector2.ZERO
	_ctx.selected_floor = null
	_ctx.selected_floor_point = Vector2.ZERO
	_ctx.suppressed_auto_floor_signatures.clear()
	_ctx.auto_floor_polygon = PackedVector2Array()
	_ctx.auto_floor_signature = ""
	_ctx.floor_polygon = PackedVector2Array()
	_ctx.state = RoomBuilderTypes.State.IDLE
	_ctx.operation = RoomBuilderTypes.Operation.NEW
	_ctx.editing_segment = null
	_ctx.editing_end = -1
	_ctx.has_snap_target = false
	_ctx.snap_hits_body = false
	_ctx.accepted_snap_hits_body = false
	_rendering.clear_ghost()

	new_room_data.changed.connect(rebuild_walls)
	rebuild_walls()
	_ctx.overlay.queue_redraw()

func _make_context() -> RoomBuilderContext:
	var context := RoomBuilderContext.new()
	context.host = self
	context.room_data = room_data
	context.snap_size = snap_size
	context.grid_visible = grid_visible
	context.grid_size = grid_size
	context.grid_line_color = grid_line_color
	context.grid_axis_color = grid_axis_color
	context.snap_radius = snap_radius
	context.wall_hit_padding = wall_hit_padding
	context.default_color = default_color
	context.default_thickness = default_thickness
	context.default_line_width = default_line_width
	context.default_start_cap = default_start_cap
	context.default_end_cap = default_end_cap
	context.default_floor_color = default_floor_color
	context.floor_texture_tile_size = floor_texture_tile_size
	context.ghost_alpha = ghost_alpha
	context.initial_render_mode = initial_render_mode
	context.iso_wall_height = iso_wall_height
	context.iso_projection_angle = iso_projection_angle
	context.iso_view_quadrant = iso_view_quadrant
	context.DEBUG_MODE = DEBUG_MODE
	context.debug_texture_directory = debug_texture_directory
	context.debug_texture_tile_size = debug_texture_tile_size
	context.renderer_switch_duration = renderer_switch_duration
	return context

func _create_modules() -> void:
	# Composition root: every RoomBuilder responsibility is owned by a focused module.
	_grid = RoomBuilderGrid.new(_ctx)
	_rendering = RoomBuilderRendering.new(_ctx)
	_input = RoomBuilderInput.new(_ctx)
	_wall_ops = RoomBuilderWallOps.new(_ctx)
	_editing = RoomBuilderEditing.new(_ctx)
	_texture = RoomBuilderTextureEditing.new(_ctx)
	_persistence = RoomBuilderPersistence.new(_ctx)
	_floor_ops = RoomBuilderFloorOps.new(_ctx)
	_ui = RoomBuilderUI.new(_ctx)

	_ctx.grid = _grid
	_ctx.rendering = _rendering
	_ctx.input = _input
	_ctx.wall_ops = _wall_ops
	_ctx.editing = _editing
	_ctx.texture = _texture
	_ctx.floor_ops = _floor_ops
	_ctx.persistence = _persistence
	_ctx.ui_module = _ui

func _process(delta: float) -> void:
	_input.process(delta)

func _unhandled_input(event: InputEvent) -> void:
	_input.unhandled_input(event)

func rebuild_walls() -> void:
	_rendering.rebuild_walls()

func _update_ghost() -> void:
	_rendering.update_ghost()

func _get_mouse_point() -> Vector2:
	return _input.get_mouse_point()

func _clear_ghost_renderer() -> void:
	_rendering.clear_ghost()

func _set_status(message: String) -> void:
	_ui.set_status(message)
