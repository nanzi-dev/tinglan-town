extends GutTest

const NPC_SCENE_PATH := "res://scenes/actors/npc.tscn"


func test_npc_scene_has_autonomous_components_without_collision() -> void:
	var scene_exists := ResourceLoader.exists(NPC_SCENE_PATH)
	assert_true(scene_exists)
	if not scene_exists:
		return

	var packed_scene := load(NPC_SCENE_PATH) as PackedScene
	assert_not_null(packed_scene)
	if packed_scene == null:
		return
	var npc := packed_scene.instantiate() as CharacterBody3D
	assert_not_null(npc)
	if npc == null:
		return
	add_child_autoqfree(npc)

	assert_not_null(npc.get_node_or_null("NeedsComponent") as NeedsComponent)
	assert_not_null(
		npc.get_node_or_null("ScheduleComponent") as ScheduleComponent,
	)
	assert_not_null(
		npc.get_node_or_null("NavigationAgent3D") as NavigationAgent3D,
	)
	assert_eq(npc.collision_layer, 0)
	assert_eq(npc.collision_mask, 0)
