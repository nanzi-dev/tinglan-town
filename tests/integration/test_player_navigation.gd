extends GutTest

const TOWN_SCENE_PATH := "res://scenes/town/town.tscn"
const PLAYER_SCENE_PATH := "res://scenes/actors/player.tscn"

var _town: Node3D
var _player: CharacterBody3D


func before_each() -> void:
	var town_scene_exists := ResourceLoader.exists(TOWN_SCENE_PATH)
	assert_true(town_scene_exists)
	if not town_scene_exists:
		return
	var player_scene_exists := ResourceLoader.exists(PLAYER_SCENE_PATH)
	assert_true(player_scene_exists)
	if not player_scene_exists:
		return

	_town = (load(TOWN_SCENE_PATH) as PackedScene).instantiate()
	_player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	add_child_autoqfree(_town)
	add_child_autoqfree(_player)
	_player.global_position = Vector3(-12.0, 0.5, 0.0)
	await wait_process_frames(1)
	await wait_physics_frames(2)


func after_each() -> void:
	if InputMap.has_action("move_left"):
		Input.action_release("move_left")


func test_move_left_input_changes_player_velocity() -> void:
	if _player == null:
		return

	Input.action_press("move_left")
	_player.update_keyboard_velocity()

	assert_lt(_player.velocity.x, 0.0)
	assert_almost_eq(_player.velocity.z, 0.0, 0.0001)


func test_clicking_reachable_navigation_point_creates_a_path() -> void:
	if _player == null:
		return

	_player.command_move_to(Vector3(-12.0, 0.0, 10.0))

	assert_gt(_player.get_navigation_path().size(), 1)
	assert_eq(_player.get_requested_target(), Vector3(-12.0, 0.0, 10.0))
	assert_true(_player.get_projected_target().is_equal_approx(
		_player.get_requested_target(),
	))

	_player.command_move_to(Vector3(12.0, 0.0, 10.0))
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
