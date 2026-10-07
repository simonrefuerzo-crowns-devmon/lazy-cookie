extends Camera2D
class_name RoomBuilderCamera


@export_group("Pan")
@export var pan_sensitivity: float = 1.0
@export var pan_smoothing: bool = true
@export_range(1.0, 60.0, 1.0)
var pan_smoothing_speed: float = 30.0


@export_group("Iso Pan")
@export var iso_pan_enabled: bool = true
@export_range(10.0, 45.0, 0.5)
var iso_projection_angle: float = 30.0

@export_range(0, 3)
var iso_view_quadrant: int = 0

@export_range(0.05, 1.5, 0.01)
var iso_quadrant_turn_duration: float = 0.35

@export_range(0.1, 3.0, 0.05)
var iso_pan_strength: float = 1.0


@export_group("Zoom")
@export var zoom_step: float = 1.15
@export var min_zoom: float = 0.25
@export var max_zoom: float = 4.0
@export var zoom_smoothing: bool = true
@export_range(1.0, 60.0, 1.0)
var zoom_smoothing_speed: float = 25.0


@export_group("Iso Zoom")
## Multiplies the zoom response while in Iso mode.
## 1.0 = same response as normal mode.
@export_range(0.25, 2.0, 0.05)
var iso_zoom_response: float = 1.0


var _panning: bool = false
var _target_position: Vector2
var _target_zoom: Vector2

var _isometric_mode: bool = false
var _iso_quadrant_tween: Tween
var _iso_quadrant_float: float = 0.0


func _ready() -> void:
	enabled = true

	_target_position = position
	_target_zoom = zoom
	_iso_quadrant_float = float(iso_view_quadrant)


func set_isometric_mode(
	enabled_iso: bool,
	projection_angle: float = 30.0,
	view_quadrant: int = 0
) -> void:
	_isometric_mode = enabled_iso
	iso_projection_angle = projection_angle
	iso_view_quadrant = posmod(view_quadrant, 4)
	_iso_quadrant_float = float(iso_view_quadrant)


func set_iso_view_quadrant(quadrant: int, animate: bool = true) -> void:
	var target_quadrant: int = posmod(quadrant, 4)
	var current_quadrant: int = posmod(iso_view_quadrant, 4)

	if not animate or current_quadrant == target_quadrant:
		iso_view_quadrant = target_quadrant
		_iso_quadrant_float = float(target_quadrant)
		return

	if _iso_quadrant_tween != null and _iso_quadrant_tween.is_valid():
		_iso_quadrant_tween.kill()

	var current_angle: float = _iso_quadrant_float
	var delta_quadrants: float = fposmod(
		float(target_quadrant) - current_angle + 2.0,
		4.0
	) - 2.0
	var resolved_target: float = current_angle + delta_quadrants

	_iso_quadrant_tween = create_tween()
	_iso_quadrant_tween.set_trans(Tween.TRANS_SINE)
	_iso_quadrant_tween.set_ease(Tween.EASE_IN_OUT)
	_iso_quadrant_tween.tween_property(
		self,
		"_iso_quadrant_float",
		resolved_target,
		maxf(iso_quadrant_turn_duration, 0.001)
	)
	_iso_quadrant_tween.finished.connect(
		_finish_iso_quadrant_turn.bind(target_quadrant),
		CONNECT_ONE_SHOT
	)


func _finish_iso_quadrant_turn(target_quadrant: int) -> void:
	iso_view_quadrant = target_quadrant
	_iso_quadrant_float = float(target_quadrant)


func get_iso_quadrant_float() -> float:
	return _iso_quadrant_float


func is_iso_quadrant_turning() -> bool:
	return _iso_quadrant_tween != null and _iso_quadrant_tween.is_valid()



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: int = (
			event as InputEventMouseButton
		).button_index

		var mouse_event: InputEventMouseButton = (
			event as InputEventMouseButton
		)

		# -----------------------------------------------
		# Middle mouse pan
		# -----------------------------------------------

		if mouse_button == MOUSE_BUTTON_MIDDLE:
			_panning = mouse_event.pressed
			get_viewport().set_input_as_handled()
			return

		# -----------------------------------------------
		# Wheel zoom
		# -----------------------------------------------

		if mouse_event.pressed:
			match mouse_button:

				MOUSE_BUTTON_WHEEL_UP:
					_zoom_at_mouse(zoom_step)
					get_viewport().set_input_as_handled()

				MOUSE_BUTTON_WHEEL_DOWN:
					_zoom_at_mouse(
						1.0 / zoom_step
					)
					get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _panning:
		var mouse_motion := (
			event as InputEventMouseMotion
		)

		var drag_delta: Vector2 = (
			mouse_motion.relative /
			maxf(_target_zoom.x, 0.0001)
		)

		var world_delta := drag_delta

		if _isometric_mode and iso_pan_enabled:
			world_delta = _adjust_iso_pan(
				drag_delta
			)

		_target_position -= (
			world_delta *
			pan_sensitivity
		)

		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:

	# -----------------------------------------------
	# Smooth position
	# -----------------------------------------------

	if pan_smoothing:
		var pan_weight := (
			1.0 -
			exp(-pan_smoothing_speed * delta)
		)

		position = position.lerp(
			_target_position,
			pan_weight
		)
	else:
		position = _target_position


	# -----------------------------------------------
	# Smooth zoom
	# -----------------------------------------------

	if zoom_smoothing:
		var zoom_weight := (
			1.0 -
			exp(-zoom_smoothing_speed * delta)
		)

		zoom = zoom.lerp(
			_target_zoom,
			zoom_weight
		)
	else:
		zoom = _target_zoom


# ---------------------------------------------------------
# Normalized zoom
# ---------------------------------------------------------

func _zoom_at_mouse(multiplier: float) -> void:

	var old_zoom: Vector2 = _target_zoom

	# Optional Iso response normalization.
	var effective_multiplier := multiplier

	if _isometric_mode:
		effective_multiplier = _get_iso_zoom_multiplier(
			multiplier
		)

	_target_zoom *= effective_multiplier

	_target_zoom.x = clampf(
		_target_zoom.x,
		min_zoom,
		max_zoom
	)

	_target_zoom.y = clampf(
		_target_zoom.y,
		min_zoom,
		max_zoom
	)

	if is_equal_approx(
		_target_zoom.x,
		old_zoom.x
	):
		return


	# -----------------------------------------------------
	# NORMALIZED MOUSE PIVOT
	#
	# Do NOT use get_global_mouse_position() here.
	# That uses the current smoothed zoom.
	#
	# Instead calculate the world point under the mouse
	# directly from the target camera transform.
	# -----------------------------------------------------

	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	var mouse_screen: Vector2 = (
		get_viewport().get_mouse_position()
	)

	var screen_center := viewport_size * 0.5

	var mouse_offset_screen := (
		mouse_screen -
		screen_center
	)


	var old_zoom_x := maxf(
		old_zoom.x,
		0.0001
	)

	var old_zoom_y := maxf(
		old_zoom.y,
		0.0001
	)

	var world_mouse_before := (
		_target_position +
		Vector2(
			mouse_offset_screen.x / old_zoom_x,
			mouse_offset_screen.y / old_zoom_y
		)
	)


	# Where that same world point needs to be after zoom.
	var new_zoom_x := maxf(
		_target_zoom.x,
		0.0001
	)

	var new_zoom_y := maxf(
		_target_zoom.y,
		0.0001
	)

	_target_position = (
		world_mouse_before -
		Vector2(
			mouse_offset_screen.x / new_zoom_x,
			mouse_offset_screen.y / new_zoom_y
		)
	)


func _get_iso_zoom_multiplier(
	multiplier: float
) -> float:

	# Keep 1.0 as the neutral setting.
	#
	# Values below 1.0:
	# smoother / slower Iso zoom.
	#
	# Values above 1.0:
	# faster Iso zoom.

	if is_equal_approx(
		iso_zoom_response,
		1.0
	):
		return multiplier

	# Apply the response around 1.0.
	#
	# Example:
	# zoom_step = 1.15
	# response = 0.75
	#
	# gives:
	# pow(1.15, 0.75)

	var direction := 1.0

	if multiplier < 1.0:
		direction = -1.0
		multiplier = 1.0 / multiplier

	var adjusted := pow(
		multiplier,
		iso_zoom_response
	)

	if direction < 0.0:
		return 1.0 / adjusted

	return adjusted


# ---------------------------------------------------------
# Iso pan
# ---------------------------------------------------------

func _adjust_iso_pan(
	drag_delta: Vector2
) -> Vector2:

	var angle_rad: float = deg_to_rad(
		iso_projection_angle
	)

	var cos_angle := cos(angle_rad)
	var sin_angle := sin(angle_rad)

	cos_angle = maxf(
		absf(cos_angle),
		0.0001
	)

	sin_angle = maxf(
		absf(sin_angle),
		0.0001
	)


	# IsoWallRenderer:
	#
	# screen_x = (x - y) * cos(angle)
	# screen_y = (x + y) * sin(angle)

	var projected_x: float = (
		drag_delta.x /
		cos_angle
	)

	var projected_y: float = (
		drag_delta.y /
		sin_angle
	)


	var rotated_plan_delta := Vector2(
		(projected_x + projected_y) * 0.5,
		(projected_y - projected_x) * 0.5
	)


	var plan_delta := _inverse_iso_rotation(
		rotated_plan_delta
	)


	var compensated := _project_iso_delta(
		plan_delta
	)

	return (
		compensated *
		iso_pan_strength
	)


func _project_iso_delta(
	plan_delta: Vector2
) -> Vector2:

	var angle_rad := deg_to_rad(
		iso_projection_angle
	)

	var cos_angle := cos(angle_rad)
	var sin_angle := sin(angle_rad)

	var rotated := _iso_rotation(
		plan_delta
	)

	return Vector2(
		(rotated.x - rotated.y) *
		cos_angle,

		(rotated.x + rotated.y) *
		sin_angle
	)


func _iso_rotation(v: Vector2) -> Vector2:
	var angle_rad: float = _iso_quadrant_float * (PI * 0.5)
	var c: float = cos(angle_rad)
	var s: float = sin(angle_rad)
	return Vector2(
		v.x * c - v.y * s,
		v.x * s + v.y * c
	)


func _inverse_iso_rotation(v: Vector2) -> Vector2:
	var angle_rad: float = -_iso_quadrant_float * (PI * 0.5)
	var c: float = cos(angle_rad)
	var s: float = sin(angle_rad)
	return Vector2(
		v.x * c - v.y * s,
		v.x * s + v.y * c
	)
