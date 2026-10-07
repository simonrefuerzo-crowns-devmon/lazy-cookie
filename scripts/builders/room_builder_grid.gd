# Construction grid: viewport bounds, isometric projection, and visibility.
class_name RoomBuilderGrid
extends RefCounted

## Construction grid functionality.
var ctx: RoomBuilderContext

func _init(context: RoomBuilderContext) -> void:
	ctx = context

func setup() -> void:
	create_grid_renderer()

func create_grid_renderer() -> void:
	ctx.grid_renderer = Node2D.new()
	ctx.grid_renderer.name = "GridRenderer"
	ctx.grid_renderer.z_index = -10
	ctx.grid_renderer.draw.connect(draw_grid)
	ctx.host.add_child(ctx.grid_renderer)
	ctx.grid_renderer.visible = ctx.grid_visible
	ctx.grid_renderer.queue_redraw()

func draw_grid() -> void:
	if not ctx.grid_visible:
		return

	var spacing: float = ctx.grid_size
	if spacing <= 0.0:
		spacing = ctx.snap_size
	if spacing <= 0.0:
		spacing = 16.0

	var viewport_size: Vector2 = ctx.host.get_viewport_rect().size
	var canvas_inverse: Transform2D = ctx.host.get_viewport().get_canvas_transform().affine_inverse()
	var screen_corners := [
		Vector2.ZERO,
		Vector2(viewport_size.x, 0.0),
		Vector2(0.0, viewport_size.y),
		viewport_size,
	]

	var world_corners: Array[Vector2] = []
	for screen_point in screen_corners:
		world_corners.append(canvas_inverse * screen_point)

	var min_x := world_corners[0].x
	var max_x := world_corners[0].x
	var min_y := world_corners[0].y
	var max_y := world_corners[0].y
	for point in world_corners:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)

	var padding := spacing * 4.0
	min_x = floorf((min_x - padding) / spacing) * spacing
	max_x = ceilf((max_x + padding) / spacing) * spacing
	min_y = floorf((min_y - padding) / spacing) * spacing
	max_y = ceilf((max_y + padding) / spacing) * spacing

	var max_grid_lines := 2000
	var x_count := int(roundf((max_x - min_x) / spacing)) + 1
	var y_count := int(roundf((max_y - min_y) / spacing)) + 1
	if x_count > max_grid_lines or y_count > max_grid_lines:
		return

	var grid_x := min_x
	while grid_x <= max_x + 0.01:
		draw_grid_line(Vector2(grid_x, min_y), Vector2(grid_x, max_y), is_zero_approx(grid_x))
		grid_x += spacing

	var grid_y := min_y
	while grid_y <= max_y + 0.01:
		draw_grid_line(Vector2(min_x, grid_y), Vector2(max_x, grid_y), is_zero_approx(grid_y))
		grid_y += spacing

func draw_grid_line(start_plan: Vector2, end_plan: Vector2, is_axis: bool) -> void:
	var start_screen := start_plan
	var end_screen := end_plan
	if ctx.isometric_mode and ctx.iso_wall_renderer != null:
		start_screen = ctx.iso_wall_renderer.project_point(start_plan, 0.0)
		end_screen = ctx.iso_wall_renderer.project_point(end_plan, 0.0)

	ctx.grid_renderer.draw_line(
		start_screen,
		end_screen,
		ctx.grid_axis_color if is_axis else ctx.grid_line_color,
		1.0,
		true
	)

func toggle_grid() -> void:
	ctx.grid_visible = not ctx.grid_visible
	if ctx.grid_renderer != null:
		ctx.grid_renderer.visible = ctx.grid_visible
		ctx.grid_renderer.queue_redraw()
		
		if ctx.grid_visible:
			ctx.ui_module.set_status("Grid turned on. Grid snapping is unchanged.")
		else:
			ctx.ui_module.set_status("Grid turned off. Grid snapping is unchanged.")

	ctx.ui_module.update_context_menu_grid_item()

