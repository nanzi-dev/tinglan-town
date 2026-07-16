extends GutTest

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const TOWN_SCENE_PATH := "res://scenes/town/town.tscn"
const EXPECTED_ENTRANCE_IDS := [
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
const EXPECTED_INPUT_KEYS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E, KEY_ENTER],
	"open_tasks": [KEY_J],
	"open_inventory": [KEY_I],
	"pause_game": [KEY_ESCAPE],
}


func test_town_has_three_identifiable_districts() -> void:
	var town := await _spawn_town()
	if town == null:
		return

	var districts := town.get_node_or_null("Districts")
	assert_not_null(districts)
	if districts == null:
		return
	var district_ids: Array[String] = []
	for district in districts.get_children():
		assert_true(district.is_in_group("town_district"))
		var district_id := str(district.get_meta("district_id", ""))
		assert_ne(district_id, "")
		district_ids.append(district_id)
	district_ids.sort()

	assert_eq(districts.get_child_count(), 3)
	assert_eq(district_ids, [
		"central_market",
		"east_craft",
		"west_life",
	])


func test_town_has_one_continuous_river_and_two_bridges() -> void:
	var town := await _spawn_town()
	if town == null:
		return

	assert_true(town.has_continuous_river())
	var river := town.get_node_or_null("River/ContinuousRiver") as CSGBox3D
	assert_not_null(river)
	if river != null:
		assert_true(river.is_in_group("river"))
		assert_true(river.get_meta("continuous", false))
		assert_eq(river.get_meta("flow", ""), "northwest_to_southeast")

	var bridges := town.get_node_or_null("Bridges")
	assert_not_null(bridges)
	if bridges == null:
		return
	var bridge_ids: Array[String] = []
	for bridge in bridges.get_children():
		assert_true(bridge.is_in_group("town_bridge"))
		var bridge_id := str(bridge.get_meta("bridge_id", ""))
		assert_ne(bridge_id, "")
		bridge_ids.append(bridge_id)
		assert_true(bridge.get_node_or_null("Deck") is CSGBox3D)
	bridge_ids.sort()

	assert_gte(bridges.get_child_count(), 2)
	assert_eq(bridge_ids, ["south_market_bridge", "tingyu_bridge"])


func test_town_exposes_ten_unique_stable_interior_entrances() -> void:
	var town := await _spawn_town()
	if town == null:
		return

	var entrances := town.get_node_or_null("Entrances")
	assert_not_null(entrances)
	if entrances == null:
		return
	var entrance_ids: Array[String] = []
	var unique_ids := {}
	for entrance in entrances.get_children():
		assert_true(entrance is Marker3D)
		assert_true(entrance.is_in_group("interior_entrance"))
		var entrance_id := str(entrance.get_meta("entrance_id", ""))
		assert_ne(entrance_id, "")
		entrance_ids.append(entrance_id)
		unique_ids[entrance_id] = true
		assert_same(town.get_entrance(entrance_id), entrance)

	assert_eq(entrances.get_child_count(), 10)
	assert_eq(unique_ids.size(), 10)
	for expected_id in EXPECTED_ENTRANCE_IDS:
		assert_true(entrance_ids.has(expected_id), "Missing entrance %s." % expected_id)


func test_town_navigation_region_is_runtime_generated_and_ready() -> void:
	var town := await _spawn_town()
	if town == null:
		return

	assert_true(town.is_navigation_ready())
	var navigation_region: NavigationRegion3D = town.get_navigation_region()
	assert_not_null(navigation_region)
	if navigation_region == null:
		return
	assert_not_null(navigation_region.navigation_mesh)
	assert_gt(navigation_region.navigation_mesh.get_polygon_count(), 0)


func test_project_input_actions_have_exact_required_key_bindings() -> void:
	for action in EXPECTED_INPUT_KEYS:
		assert_true(InputMap.has_action(action), "Missing input action %s." % action)
		assert_eq(
			_action_keycodes(action),
			EXPECTED_INPUT_KEYS[action],
			"Unexpected key bindings for %s." % action,
		)


func test_main_camera_is_orthogonal_at_35_degrees_and_clamps_zoom() -> void:
	var main := await _spawn_main()
	if main == null:
		return
	var camera := main.get_node_or_null("IsometricCamera") as Camera3D
	assert_not_null(camera)
	if camera == null:
		return

	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	var forward := -camera.global_transform.basis.z.normalized()
	var downward_pitch := rad_to_deg(asin(clampf(-forward.y, -1.0, 1.0)))
	assert_almost_eq(downward_pitch, 35.0, 0.5)

	var initial_size := camera.size
	camera._unhandled_input(_mouse_wheel_event(MOUSE_BUTTON_WHEEL_UP))
	assert_lt(camera.size, initial_size)
	for index in range(30):
		camera._unhandled_input(_mouse_wheel_event(MOUSE_BUTTON_WHEEL_UP))
	assert_almost_eq(camera.size, camera.minimum_zoom, 0.001)
	for index in range(40):
		camera._unhandled_input(_mouse_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	assert_almost_eq(camera.size, camera.maximum_zoom, 0.001)


func _spawn_town() -> Node:
	var scene_exists := ResourceLoader.exists(TOWN_SCENE_PATH)
	assert_true(scene_exists)
	if not scene_exists:
		return null
	var scene := load(TOWN_SCENE_PATH) as PackedScene
	assert_not_null(scene)
	if scene == null:
		return null
	var town := scene.instantiate()
	add_child_autoqfree(town)
	await wait_process_frames(1)
	await wait_physics_frames(1)
	return town


func _spawn_main() -> Node:
	var scene_exists := ResourceLoader.exists(MAIN_SCENE_PATH)
	assert_true(scene_exists)
	if not scene_exists:
		return null
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(scene)
	if scene == null:
		return null
	var main := scene.instantiate()
	add_child_autoqfree(main)
	await wait_process_frames(2)
	await wait_physics_frames(2)
	return main


func _action_keycodes(action: String) -> Array[int]:
	var keycodes: Array[int] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keycode: Key = event.physical_keycode
			if keycode == KEY_NONE:
				keycode = event.keycode
			keycodes.append(keycode)
	keycodes.sort()
	return keycodes


func _mouse_wheel_event(button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	return event
