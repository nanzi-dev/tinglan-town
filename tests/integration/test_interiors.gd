extends GutTest

const INTERIOR_SCENE_PATH := "res://scenes/interiors/interior.tscn"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const EXPECTED_INTERIOR_IDS := [
	"player_home",
	"tea_house",
	"general_store",
	"clinic",
	"workshop",
	"bookshop",
	"community_center",
	"shen_home",
	"gu_home",
	"qiao_home",
]


func test_all_ten_interiors_are_built_from_location_content() -> void:
	var scene_exists := ResourceLoader.exists(INTERIOR_SCENE_PATH)
	assert_true(scene_exists)
	if not scene_exists:
		return

	var repository := ContentRepository.new()
	assert_true(repository.load_spring())
	var locations := _interior_locations_by_id(repository.locations)
	assert_eq(locations.size(), EXPECTED_INTERIOR_IDS.size())
	for location_id in EXPECTED_INTERIOR_IDS:
		assert_true(locations.has(location_id))

	var scene := load(INTERIOR_SCENE_PATH) as PackedScene
	assert_not_null(scene)
	if scene == null:
		return

	var built_ids := {}
	for location_id in EXPECTED_INTERIOR_IDS:
		var location: Dictionary = locations[location_id]
		var interior := scene.instantiate()
		add_child_autoqfree(interior)
		assert_true(interior.build_location(location_id))
		await wait_process_frames(1)

		assert_eq(interior.get_location_id(), location_id)
		assert_eq(interior.get_meta("purpose", ""), location["purpose"])
		assert_false(built_ids.has(interior.get_location_id()))
		built_ids[interior.get_location_id()] = true

		var spawn_point := interior.get_node_or_null("PlayerSpawn") as Marker3D
		assert_not_null(spawn_point)
		assert_true(spawn_point.is_in_group("interior_spawn"))

		var exterior_exit := interior.get_node_or_null("ExteriorExit") as Marker3D
		assert_not_null(exterior_exit)
		assert_true(exterior_exit.is_in_group("interior_exit"))
		assert_eq(
			exterior_exit.get_meta("interaction_id", ""),
			"return_outdoors",
		)

		_assert_room_geometry_matches_content(interior, location)
		_assert_furniture_matches_content(interior, location)
		_assert_interactions_match_content(interior, location)

	assert_eq(built_ids.size(), EXPECTED_INTERIOR_IDS.size())


func test_location_manager_restores_the_saved_outdoor_position() -> void:
	var main := await _spawn_main()
	if main == null:
		return
	var manager := main.get_node_or_null("LocationManager")
	var town := main.get_node_or_null("Town") as Node3D
	var player := main.get_node_or_null("Player") as CharacterBody3D
	assert_not_null(manager)
	assert_not_null(town)
	assert_not_null(player)
	if manager == null or town == null or player == null:
		return

	var outdoor_position := Vector3(-8.0, 0.05, 0.2)
	player.global_position = outdoor_position
	assert_true(manager.enter_interior("tea_house"))
	var active_interior = manager.get_active_interior()
	assert_not_null(active_interior)
	if active_interior == null:
		return

	assert_eq(manager.get_active_location_id(), "tea_house")
	assert_true(manager.has_saved_outdoor_position())
	assert_true(
		manager.get_saved_outdoor_position().is_equal_approx(outdoor_position),
	)
	assert_false(town.visible)
	assert_true(player.global_position.is_equal_approx(
		active_interior.get_node("PlayerSpawn").global_position,
	))

	assert_true(manager.return_outdoors())
	assert_eq(manager.get_active_location_id(), "")
	assert_null(manager.get_active_interior())
	assert_true(town.visible)
	assert_true(player.global_position.is_equal_approx(outdoor_position))


func test_returning_without_a_saved_outdoor_position_is_stable() -> void:
	var main := await _spawn_main()
	if main == null:
		return
	var manager := main.get_node_or_null("LocationManager")
	var town := main.get_node_or_null("Town") as Node3D
	var player := main.get_node_or_null("Player") as CharacterBody3D
	assert_not_null(manager)
	assert_not_null(town)
	assert_not_null(player)
	if manager == null or town == null or player == null:
		return

	var initial_position := player.global_position
	assert_false(manager.has_saved_outdoor_position())
	assert_false(manager.return_outdoors())
	assert_eq(manager.get_active_location_id(), "")
	assert_null(manager.get_active_interior())
	assert_true(town.visible)
	assert_true(player.global_position.is_equal_approx(initial_position))


func _assert_room_geometry_matches_content(
	interior: Node,
	location: Dictionary,
) -> void:
	var dimensions: Dictionary = location["dimensions"]
	var floor := interior.get_node_or_null("Room/Floor") as CSGBox3D
	assert_not_null(floor)
	if floor != null:
		assert_true(floor.size.is_equal_approx(Vector3(
			float(dimensions["width"]),
			0.2,
			float(dimensions["depth"]),
		)))
		assert_eq(
			(floor.material as StandardMaterial3D).albedo_color,
			Color(location["floor_color"]),
		)

	var walls := interior.get_node_or_null("Room/Walls")
	assert_not_null(walls)
	if walls == null:
		return
	assert_eq(walls.get_child_count(), 5)
	for wall in walls.get_children():
		assert_true(wall is CSGBox3D)
		assert_eq(
			(wall.material as StandardMaterial3D).albedo_color,
			Color(location["wall_color"]),
		)
		assert_almost_eq(
			(wall as CSGBox3D).size.y,
			float(dimensions["height"]),
			0.001,
		)


func _assert_furniture_matches_content(
	interior: Node,
	location: Dictionary,
) -> void:
	var furniture_root := interior.get_node_or_null("Furniture")
	assert_not_null(furniture_root)
	if furniture_root == null:
		return
	var expected_items: Array = location["furniture_layout"]
	assert_eq(furniture_root.get_child_count(), expected_items.size())
	for item in expected_items:
		var furniture := _child_with_meta(
			furniture_root,
			"furniture_id",
			item["furniture_id"],
		)
		assert_not_null(furniture)
		if furniture != null:
			assert_true(furniture.position.is_equal_approx(
				_content_position(location, item, 0.5),
			))


func _assert_interactions_match_content(
	interior: Node,
	location: Dictionary,
) -> void:
	var interactions_root := interior.get_node_or_null("InteractionPoints")
	assert_not_null(interactions_root)
	if interactions_root == null:
		return
	var expected_points: Array = location["interaction_points"]
	assert_gt(expected_points.size(), 0)
	assert_eq(interactions_root.get_child_count(), expected_points.size())
	for item in expected_points:
		var point := _child_with_meta(
			interactions_root,
			"interaction_id",
			item["interaction_id"],
		)
		assert_not_null(point)
		if point != null:
			assert_true(point.is_in_group("interior_interaction"))
			assert_eq(point.get_meta("purpose", ""), location["purpose"])
			assert_true(point.position.is_equal_approx(
				_content_position(location, item, 0.1),
			))


func _spawn_main() -> Node3D:
	var scene_exists := ResourceLoader.exists(MAIN_SCENE_PATH)
	assert_true(scene_exists)
	if not scene_exists:
		return null
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(scene)
	if scene == null:
		return null
	var main := scene.instantiate() as Node3D
	main.set("enable_persistence", false)
	add_child_autoqfree(main)
	await wait_process_frames(2)
	await wait_physics_frames(2)
	return main


func _interior_locations_by_id(locations: Array) -> Dictionary:
	var result := {}
	for location in locations:
		if location.get("is_interior", false):
			result[location["location_id"]] = location
	return result


func _child_with_meta(
	parent: Node,
	meta_name: String,
	expected_value: String,
) -> Node3D:
	for child in parent.get_children():
		if child.get_meta(meta_name, "") == expected_value:
			return child as Node3D
	return null


func _content_position(
	location: Dictionary,
	item: Dictionary,
	y_position: float,
) -> Vector3:
	var dimensions: Dictionary = location["dimensions"]
	return Vector3(
		float(item["x"]) - float(dimensions["width"]) * 0.5 + 0.5,
		y_position,
		float(item["z"]) - float(dimensions["depth"]) * 0.5 + 0.5,
	)
