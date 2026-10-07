class_name RoomBuilderContext
extends RefCounted

const SAVE_DIR := "res://assets/baked_tres/room_data/"
const SNAP_EPSILON := 0.1
const WALL_HIT_PADDING := 2.0
const MIN_WALL_LENGTH := 1.0

var host: Node2D

# Shared configuration copied from RoomBuilder exports.
var room_data: RoomData
var snap_size: float
var grid_visible: bool
var grid_size: float
var grid_line_color: Color
var grid_axis_color: Color
var snap_radius: float
var wall_hit_padding: float
var default_color: Color
var default_thickness: float
var default_line_width: float
var default_start_cap: WallSegment.CapStyle
var default_end_cap: WallSegment.CapStyle
var default_floor_color: Color
var floor_texture_tile_size: float
var ghost_alpha: float
var initial_render_mode: int
var iso_wall_height: float
var iso_projection_angle: float
var iso_view_quadrant: int
var DEBUG_MODE: bool
var debug_texture_directory: String
var debug_texture_tile_size: float
var renderer_switch_duration: float

const save_dir := SAVE_DIR
const snap_epsilon := SNAP_EPSILON
const wall_hit_padding_default := WALL_HIT_PADDING
const min_wall_length := MIN_WALL_LENGTH

# Floor/editor state.
var selected_floor: FloorSpace = null
var selected_floor_point := Vector2.ZERO
var floor_polygon: PackedVector2Array = PackedVector2Array()
var auto_floor_polygon: PackedVector2Array = PackedVector2Array()
var auto_floor_signature := ""
var suppressed_auto_floor_signatures := {}
var floor_appearance_snapshot := {}

# Editor state.
var state: int = RoomBuilderTypes.State.IDLE
var operation: int = RoomBuilderTypes.Operation.NEW
var start_point := Vector2.ZERO
var end_point := Vector2.ZERO
var pending_color := Color.WHITE
var pending_thickness: float = 24.0
var pending_line_width: float = 3.0
var pending_start_cap: WallSegment.CapStyle = WallSegment.CapStyle.FLAT
var pending_end_cap: WallSegment.CapStyle = WallSegment.CapStyle.FLAT
var selected_segment: WallSegment = null
var selected_point := Vector2.ZERO
var hovered_segment: WallSegment = null
var hovered_point := Vector2.ZERO
var mouse_preview_point := Vector2.ZERO
var has_mouse_preview := false
var editing_segment: WallSegment = null
var editing_end: int = -1
var has_branch_point := false
var branch_point := Vector2.ZERO
var has_snap_target := false
var snap_point := Vector2.ZERO
var snap_hits_body := false
var accepted_snap_hits_body := false
var last_clicked_point := Vector2.ZERO
var last_saved_name := "room1"

# Rendering references.
var grid_renderer: Node2D
var wall_renderer: WallRenderer
var iso_wall_renderer: IsoWallRenderer
var floor_renderer: FloorRenderer
var ghost_renderer: WallRenderer
var iso_ghost_renderer: IsoWallRenderer
var ghost_segment: WallSegment
var overlay: Node2D
var isometric_mode := true
var iso_view_mode: IsoWallRenderer.ViewMode = IsoWallRenderer.ViewMode.ISO3_ALL_WALLS
var renderer_tween: Tween

# UI references.
var ui: CanvasLayer
var status_label: Label
var context_menu: PopupMenu
var load_room_menu: PopupMenu
var wall_menu: PopupMenu
var start_dialog: ConfirmationDialog
var color_button: ColorPickerButton
var thickness_spin: SpinBox
var line_width_spin: SpinBox
var start_cap_button: OptionButton
var end_cap_button: OptionButton
var end_dialog: ConfirmationDialog
var snap_dialog: ConfirmationDialog
var rebuild_end_dialog: ConfirmationDialog
var rebuild_end_button: OptionButton
var style_dialog: ConfirmationDialog
var style_end_button: OptionButton
var style_cap_button: OptionButton
var repaint_dialog: ConfirmationDialog
var repaint_color_button: ColorPickerButton
var delete_dialog: ConfirmationDialog
var texture_dialog: ConfirmationDialog
var outside_texture_button: OptionButton
var inside_texture_button: OptionButton
var edit_outside_check: CheckButton
var edit_inside_check: CheckButton
var outside_texture_preview: TextureRect
var inside_texture_preview: TextureRect
var outside_filler_preview: ColorRect
var inside_filler_preview: ColorRect
var texture_snapshot := {}
var name_dialog: ConfirmationDialog
var name_edit: LineEdit
var floor_menu: PopupMenu
var auto_floor_dialog: ConfirmationDialog
var floor_confirm_dialog: ConfirmationDialog
var floor_appearance_dialog: ConfirmationDialog
var floor_color_button: ColorPickerButton
var floor_texture_button: OptionButton
var floor_texture_preview: TextureRect
var floor_texture_tile_spin: SpinBox

# Component references. Kept as Variants to avoid cyclic script dependencies.
var grid: Variant
var rendering: Variant
var input: Variant
var wall_ops: Variant
var editing: Variant
var texture: Variant
var floor_ops: Variant
var persistence: Variant
var ui_module: Variant
