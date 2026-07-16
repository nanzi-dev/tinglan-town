class_name PlayerController
extends CharacterBody3D

@export var move_speed := 6.0
@export var path_arrival_distance := 0.25
@export var navigation_tolerance := 0.06

@onready var _navigation_agent: NavigationAgent3D = $NavigationAgent3D

var _requested_target := Vector3.ZERO
var _projected_target := Vector3.ZERO
var _navigation_path := PackedVector3Array()
var _following_path := false


func _ready() -> void:
	_navigation_agent.path_desired_distance = 0.2
	_navigation_agent.target_desired_distance = path_arrival_distance


func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down",
	)
	if not input_vector.is_zero_approx():
		_following_path = false
		update_keyboard_velocity(input_vector)
	elif _following_path:
		_update_path_velocity()
	else:
		velocity = Vector3.ZERO
	_move_and_constrain_to_navigation()


func _unhandled_input(event: InputEvent) -> void:
	if not (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ray_origin := camera.project_ray_origin(event.position)
	var ray_direction := camera.project_ray_normal(event.position)
	var ground_hit = Plane(Vector3.UP, 0.0).intersects_ray(
		ray_origin,
		ray_direction,
	)
	if ground_hit != null:
		command_move_to(ground_hit)


func update_keyboard_velocity(
	input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down",
	),
) -> void:
	var direction := Vector3(input_vector.x, 0.0, input_vector.y)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	velocity = direction * move_speed


func command_move_to(target: Vector3) -> void:
	_requested_target = Vector3(target.x, 0.0, target.z)
	var navigation_map := get_world_3d().navigation_map
	_projected_target = NavigationServer3D.map_get_closest_point(
		navigation_map,
		_requested_target,
	)
	_navigation_path = NavigationServer3D.map_get_path(
		navigation_map,
		global_position,
		_projected_target,
		true,
	)
	_navigation_agent.target_position = _projected_target
	_following_path = _navigation_path.size() > 1


func get_navigation_path() -> PackedVector3Array:
	return _navigation_path.duplicate()


func get_requested_target() -> Vector3:
	return _requested_target


func get_projected_target() -> Vector3:
	return _projected_target


func _update_path_velocity() -> void:
	if _navigation_agent.is_navigation_finished():
		_following_path = false
		velocity = Vector3.ZERO
		return
	var next_position := _navigation_agent.get_next_path_position()
	var direction := global_position.direction_to(next_position)
	direction.y = 0.0
	if direction.is_zero_approx():
		velocity = Vector3.ZERO
		return
	velocity = direction.normalized() * move_speed


func _move_and_constrain_to_navigation() -> void:
	var requested_velocity := velocity
	var previous_position := global_position
	move_and_slide()
	var navigation_map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return
	if _is_on_navigation(navigation_map):
		return

	global_position = previous_position
	var accepted_velocity := Vector3.ZERO
	for axis_velocity in [
		Vector3(requested_velocity.x, 0.0, 0.0),
		Vector3(0.0, 0.0, requested_velocity.z),
	]:
		if axis_velocity.is_zero_approx():
			continue
		var axis_start := global_position
		velocity = axis_velocity
		move_and_slide()
		if _is_on_navigation(navigation_map):
			accepted_velocity += axis_velocity
		else:
			global_position = axis_start
	velocity = accepted_velocity


func _is_on_navigation(navigation_map: RID) -> bool:
	var closest_point := NavigationServer3D.map_get_closest_point(
		navigation_map,
		global_position,
	)
	var horizontal_distance := Vector2(
		closest_point.x,
		closest_point.z,
	).distance_to(Vector2(global_position.x, global_position.z))
	return horizontal_distance <= navigation_tolerance
