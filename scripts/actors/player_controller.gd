class_name PlayerController
extends CharacterBody3D

@export var move_speed := 6.0
@export var path_arrival_distance := 0.25
@export var navigation_tolerance := 0.05
@export var boundary_probe_distance := 2.0

@onready var _navigation_agent: NavigationAgent3D = $NavigationAgent3D

var _requested_target := Vector3.ZERO
var _projected_target := Vector3.ZERO
var _navigation_path := PackedVector3Array()
var _following_path := false


func _ready() -> void:
	_navigation_agent.path_desired_distance = 0.2
	_navigation_agent.target_desired_distance = path_arrival_distance


func _physics_process(delta: float) -> void:
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
	_move_and_constrain_to_navigation(delta)


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


func _move_and_constrain_to_navigation(delta: float) -> void:
	var requested_velocity := velocity
	var previous_position := global_position
	var horizontal_requested_velocity := Vector3(
		requested_velocity.x,
		0.0,
		requested_velocity.z,
	)
	var maximum_displacement := horizontal_requested_velocity.length() * delta
	move_and_slide()
	var moved_position := global_position
	var navigation_map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return
	if _is_on_navigation(navigation_map):
		var moved_displacement := global_position - previous_position
		moved_displacement.y = 0.0
		if _try_navigation_displacement(
			navigation_map,
			previous_position,
			moved_displacement,
			requested_velocity,
			maximum_displacement,
			delta,
		):
			return

	var closest_point := NavigationServer3D.map_get_closest_point(
		navigation_map,
		moved_position,
	)
	var projected_position := Vector3(
		closest_point.x,
		moved_position.y,
		closest_point.z,
	)
	var projected_displacement := projected_position - previous_position
	projected_displacement.y = 0.0
	var requested_direction := horizontal_requested_velocity.normalized()
	var probe_position := (
		previous_position + requested_direction * boundary_probe_distance
	)
	var probe_closest_point := NavigationServer3D.map_get_closest_point(
		navigation_map,
		probe_position,
	)
	var boundary_direction := probe_closest_point - previous_position
	boundary_direction.y = 0.0
	if not boundary_direction.is_zero_approx():
		boundary_direction = boundary_direction.normalized()
	if (
		not projected_displacement.is_zero_approx()
		and projected_displacement.length()
		<= maximum_displacement + navigation_tolerance
		and projected_displacement.dot(requested_velocity) > 0.0
		and projected_displacement.dot(boundary_direction) > 0.0
	):
		if _try_navigation_displacement(
			navigation_map,
			previous_position,
			projected_displacement,
			requested_velocity,
			maximum_displacement,
			delta,
		):
			return

	global_position = previous_position
	if boundary_direction.is_zero_approx():
		velocity = Vector3.ZERO
		return
	var slide_speed := requested_velocity.dot(boundary_direction)
	if slide_speed <= 0.0:
		velocity = Vector3.ZERO
		return

	var slide_displacement := boundary_direction * slide_speed * delta
	if _try_navigation_displacement(
		navigation_map,
		previous_position,
		slide_displacement,
		requested_velocity,
		maximum_displacement,
		delta,
	):
		return
	velocity = Vector3.ZERO


func _try_navigation_displacement(
	navigation_map: RID,
	previous_position: Vector3,
	candidate_displacement: Vector3,
	requested_velocity: Vector3,
	maximum_displacement: float,
	delta: float,
) -> bool:
	var accepted_displacement := candidate_displacement
	accepted_displacement.y = 0.0
	var candidate_position := previous_position + accepted_displacement
	var closest_point := NavigationServer3D.map_get_closest_point(
		navigation_map,
		candidate_position,
	)
	var navigation_offset := candidate_position - closest_point
	navigation_offset.y = 0.0
	var allowed_navigation_offset := maxf(
		navigation_tolerance - 0.0001,
		0.0,
	)
	if navigation_offset.length() > allowed_navigation_offset:
		candidate_position = Vector3(
			closest_point.x,
			previous_position.y,
			closest_point.z,
		)
		if not navigation_offset.is_zero_approx():
			candidate_position += (
				navigation_offset.normalized() * allowed_navigation_offset
			)
		accepted_displacement = candidate_position - previous_position
		accepted_displacement.y = 0.0
	if accepted_displacement.length() > maximum_displacement:
		accepted_displacement = (
			accepted_displacement.normalized() * maximum_displacement
		)
	if accepted_displacement.dot(requested_velocity) < 0.0:
		global_position = previous_position
		return false

	global_position = previous_position + accepted_displacement
	if not _is_on_navigation(navigation_map):
		global_position = previous_position
		return false
	velocity = accepted_displacement / delta
	return true


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
