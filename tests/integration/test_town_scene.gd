extends GutTest

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


func test_town_has_three_identifiable_districts() -> void:
	var town := await _spawn_town()
	if town == null:
		return

	assert_eq(town.get_district_ids(), [
		"west_life",
		"central_market",
		"east_craft",
	])


func test_town_has_one_continuous_river_and_two_bridges() -> void:
	var town := await _spawn_town()
	if town == null:
		return

	assert_true(town.has_continuous_river())
	assert_gte(town.get_bridge_ids().size(), 2)
	assert_true(town.get_bridge_ids().has("tingyu_bridge"))


func test_town_exposes_ten_unique_stable_interior_entrances() -> void:
	var town := await _spawn_town()
	if town == null:
		return

	var entrance_ids: Array = town.get_entrance_ids()
	var unique_ids := {}
	for entrance_id in entrance_ids:
		unique_ids[entrance_id] = true

	assert_eq(entrance_ids.size(), 10)
	assert_eq(unique_ids.size(), 10)
	for expected_id in EXPECTED_ENTRANCE_IDS:
		assert_true(entrance_ids.has(expected_id), "Missing entrance %s." % expected_id)
		assert_not_null(town.get_entrance(expected_id))


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
