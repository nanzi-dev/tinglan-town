extends GutTest

const MAIN_SCENE_PATH := "res://scenes/main.tscn"

var _main: Node3D
var _town: Node3D
var _player: CharacterBody3D
var _camera: Camera3D


func before_each() -> void:
	var main_scene_exists := ResourceLoader.exists(MAIN_SCENE_PATH)
	assert_true(main_scene_exists)
	if not main_scene_exists:
		return

	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	add_child_autoqfree(_main)
	_town = _main.get_node("Town")
	_player = _main.get_node("Player")
	_camera = _main.get_node("IsometricCamera")
	_player.global_position = Vector3(-12.0, 0.5, 0.0)
	await wait_process_frames(2)
	await wait_physics_frames(2)


func after_each() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		if InputMap.has_action(action):
			Input.action_release(action)


func test_move_left_input_changes_player_velocity() -> void:
	if _player == null:
		return

	Input.action_press("move_left")
	_player.update_keyboard_velocity()

	assert_lt(_player.velocity.x, 0.0)
	assert_almost_eq(_player.velocity.z, 0.0, 0.0001)


func test_clicking_reachable_navigation_point_creates_a_path() -> void:
	if _player == null or _camera == null:
		return

	var target := Vector3(-14.0, 0.0, 4.0)
	assert_true(_town.is_point_navigable(target))
	assert_false(_camera.is_position_behind(target))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = _camera.unproject_position(target)
	_player._unhandled_input(event)

	assert_gt(_player.get_navigation_path().size(), 1)
	assert_true(_player.get_requested_target().is_equal_approx(target))
	assert_true(_player.get_projected_target().is_equal_approx(
		_player.get_requested_target(),
	))

	_player.command_move_to(Vector3(14.0, 0.0, 4.0))
	assert_gt(_player.get_navigation_path().size(), 1)


func test_clicking_river_projects_target_to_nearest_reachable_point() -> void:
	if _player == null:
		return

	var river_target := Vector3(0.0, 0.0, 0.0)
	_player.command_move_to(river_target)
	var projected_target: Vector3 = _player.get_projected_target()

	assert_false(projected_target.is_equal_approx(river_target))
	assert_true(_town.is_point_navigable(projected_target))
	assert_gt(_player.get_navigation_path().size(), 1)

	var diagonal_river_target := Vector3(4.0, 0.0, 12.0)
	_player.command_move_to(diagonal_river_target)
	var diagonal_projected_target: Vector3 = _player.get_projected_target()

	assert_false(diagonal_projected_target.is_equal_approx(diagonal_river_target))
	assert_true(_town.is_point_navigable(diagonal_projected_target))
	assert_gt(_player.get_navigation_path().size(), 1)


func test_bridge_navigation_matches_the_real_deck_footprint() -> void:
	if _player == null or _town == null:
		return
	var bridge := _town.get_node_or_null("Bridges/TingyuBridge") as Node3D
	assert_not_null(bridge)
	if bridge == null:
		return
	var deck := bridge.get_node_or_null("Deck") as CSGBox3D
	assert_not_null(deck)
	if deck == null:
		return

	var bridge_center := deck.to_global(Vector3.ZERO)
	bridge_center.y = 0.0
	assert_true(_town.is_point_navigable(bridge_center))

	var nearby_visible_water := deck.to_global(Vector3(2.4, 0.0, 1.8))
	nearby_visible_water.y = 0.0
	assert_false(_town.is_point_navigable(nearby_visible_water))
	_player.command_move_to(nearby_visible_water)
	assert_false(_player.get_projected_target().is_equal_approx(nearby_visible_water))
	assert_true(_town.is_point_navigable(_player.get_projected_target()))


func test_keyboard_movement_cannot_enter_the_river() -> void:
	if _player == null or _town == null:
		return
	var river := _town.get_node_or_null("River/ContinuousRiver") as CSGBox3D
	assert_not_null(river)
	if river == null:
		return

	_player.global_position = Vector3(-5.0, 0.05, 0.0)
	Input.action_press("move_right")
	await wait_physics_frames(30)
	Input.action_release("move_right")

	var river_local_position := river.to_local(_player.global_position)
	assert_gte(absf(river_local_position.x), river.size.x * 0.5)
	assert_true(_town.is_point_navigable(_player.global_position))


func test_keyboard_movement_cannot_enter_a_building() -> void:
	if _player == null or _town == null:
		return
	var walls := _town.get_node_or_null(
		"Districts/WestLife/PlayerHome/Walls",
	) as CSGBox3D
	assert_not_null(walls)
	if walls == null:
		return

	_player.global_position = Vector3(
		walls.global_position.x,
		0.05,
		walls.global_position.z + walls.size.z * 0.5 + 1.0,
	)
	Input.action_press("move_up")
	await wait_physics_frames(25)
	Input.action_release("move_up")

	var walls_local_position := walls.to_local(_player.global_position)
	assert_gte(walls_local_position.z, walls.size.z * 0.5)
	assert_true(_town.is_point_navigable(_player.global_position))


func test_keyboard_movement_slides_along_a_building_navigation_boundary() -> void:
	if _player == null or _town == null:
		return
	var walls := _town.get_node_or_null(
		"Districts/WestLife/PlayerHome/Walls",
	) as CSGBox3D
	assert_not_null(walls)
	if walls == null:
		return

	var start := Vector3(
		walls.global_position.x,
		0.05,
		walls.global_position.z + walls.size.z * 0.5 + 0.7,
	)
	_player.global_position = start
	assert_true(_town.is_point_navigable(start))

	Input.action_press("move_up")
	Input.action_press("move_right")
	await wait_physics_frames(30)
	Input.action_release("move_up")
	Input.action_release("move_right")

	var walls_local_position := walls.to_local(_player.global_position)
	assert_gte(
		walls_local_position.z,
		walls.size.z * 0.5 + 0.45,
		"Sliding must preserve the navigation agent's building margin.",
	)
	assert_true(_town.is_point_navigable(_player.global_position))
	var tangential_distance := _player.global_position.x - start.x
	assert_gt(
		tangential_distance,
		1.5,
		"Diagonal input must retain its legal tangential movement.",
	)
	assert_lt(
		tangential_distance,
		2.3,
		"Boundary sliding must not boost diagonal input to full axis speed.",
	)


func test_keyboard_movement_slides_along_the_rotated_riverbank() -> void:
	if _player == null or _town == null:
		return
	var river := _town.get_node_or_null("River/ContinuousRiver") as CSGBox3D
	assert_not_null(river)
	if river == null:
		return

	var start := Vector3(-10.0, 0.05, -14.5)
	_player.global_position = start
	assert_true(_town.is_point_navigable(start))

	var samples: Array[Vector3] = []
	Input.action_press("move_right")
	Input.action_press("move_up")
	for frame in range(32):
		await wait_physics_frames(1)
		var sample := _player.global_position
		samples.append(sample)
		assert_true(
			_town.is_point_navigable(sample),
			"Player left navigation on physics frame %d." % frame,
		)
		var river_local_position := river.to_local(sample)
		assert_gte(
			absf(river_local_position.x),
			river.size.x * 0.5,
			"Player entered the visible river on physics frame %d." % frame,
		)
	Input.action_release("move_right")
	Input.action_release("move_up")
	assert_gt(
		samples[-1].z,
		-17.9,
		"The riverbank regression must stop before the town map boundary.",
	)

	var angle := deg_to_rad(18.0)
	var expected_tangent := Vector3(-sin(angle), 0.0, -cos(angle))
	var boundary_progress := (
		samples[-1] - samples[11]
	).dot(expected_tangent)
	assert_gt(
		boundary_progress,
		1.0,
		"Movement must keep its legal tangent after reaching the riverbank.",
	)

	var tail_progress := (
		samples[-1] - samples[-9]
	).dot(expected_tangent)
	assert_gt(
		tail_progress,
		0.25,
		"Movement must not freeze after settling on the riverbank.",
	)

	var tail_distance := 0.0
	for index in range(samples.size() - 8, samples.size()):
		var tangential_step := (
			samples[index] - samples[index - 1]
		).dot(expected_tangent)
		assert_gte(
			tangential_step,
			-0.02,
			"Riverbank sliding must not visibly reverse between frames.",
		)
		tail_distance += absf(tangential_step)
	assert_lt(
		tail_distance - absf(tail_progress),
		0.12,
		"Riverbank sliding must not oscillate back and forth.",
	)


func test_keyboard_movement_can_cross_the_real_bridge() -> void:
	if _player == null or _town == null:
		return
	var deck := _town.get_node_or_null(
		"Bridges/SouthMarketBridge/Deck",
	) as CSGBox3D
	assert_not_null(deck)
	if deck == null:
		return

	var start := deck.to_global(Vector3(-3.5, 0.0, 0.0))
	start.y = 0.05
	_player.global_position = start
	for index in range(23):
		await _hold_action_for_frames("move_right", 3)
		await _hold_action_for_frames("move_up", 1)

	var deck_local_position := deck.to_local(_player.global_position)
	assert_gt(deck_local_position.x, 2.5)
	assert_lt(absf(deck_local_position.z), deck.size.z * 0.5)
	assert_true(_town.is_point_navigable(_player.global_position))


func _hold_action_for_frames(action: String, frames: int) -> void:
	Input.action_press(action)
	await wait_physics_frames(frames)
	Input.action_release(action)
