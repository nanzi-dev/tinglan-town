class_name IsometricCamera
extends Camera3D

@export var target_path: NodePath
@export_range(20.0, 50.0, 0.5) var pitch_degrees := 35.0
@export_range(-180.0, 180.0, 0.5) var yaw_degrees := 45.0
@export var distance := 34.0
@export var minimum_zoom := 20.0
@export var maximum_zoom := 42.0
@export var zoom_step := 2.0
@export var follow_bounds := Rect2(-18.0, -12.0, 36.0, 24.0)

var _target: Node3D


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = clampf(size, minimum_zoom, maximum_zoom)
	_target = get_node_or_null(target_path) as Node3D
	_update_transform()


func _process(_delta: float) -> void:
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		size = clampf(size - zoom_step, minimum_zoom, maximum_zoom)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		size = clampf(size + zoom_step, minimum_zoom, maximum_zoom)
		get_viewport().set_input_as_handled()


func _update_transform() -> void:
	var focus := Vector3.ZERO
	if _target != null:
		focus = _target.global_position
	focus.x = clampf(focus.x, follow_bounds.position.x, follow_bounds.end.x)
	focus.z = clampf(focus.z, follow_bounds.position.y, follow_bounds.end.y)
	focus.y = 0.0

	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees)
	var horizontal_distance := cos(pitch) * distance
	var offset := Vector3(
		sin(yaw) * horizontal_distance,
		sin(pitch) * distance,
		cos(yaw) * horizontal_distance,
	)
	global_position = focus + offset
	look_at(focus, Vector3.UP)
