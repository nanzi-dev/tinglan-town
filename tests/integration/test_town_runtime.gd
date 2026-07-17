extends GutTest

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const EXPECTED_RESIDENT_IDS := [
	"gu-yun",
	"he-miao",
	"lin-xi",
	"lu-qiao",
	"qiao-zhen",
	"shen-yan",
	"su-wan",
	"tang-yu",
	"xu-deng",
	"zhou-he",
]

var _save_directories: Array[String] = []


func before_each() -> void:
	_save_directories.clear()


func after_each() -> void:
	for save_directory in _save_directories:
		for file_name in [
			"checkpoint.json",
			"checkpoint.json.tmp",
			"checkpoint.json.bak",
			"events.jsonl",
			"pending_memoria_events.json",
			"pending_memoria_events.json.tmp",
		]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(
				save_directory.path_join(file_name),
			))
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(save_directory),
		)


func test_main_runtime_spawns_configured_residents_and_shares_hud_services() -> void:
	var main := await _spawn_main()
	if main == null:
		return
	var runtime = main.get_node_or_null("TownRuntime")
	var hud: TownHud = main.get_node_or_null("HUD") as TownHud

	assert_not_null(runtime)
	assert_not_null(hud)
	if runtime == null or hud == null:
		return

	var resident_ids: Array = runtime.get_resident_ids()
	resident_ids.sort()
	assert_eq(resident_ids, EXPECTED_RESIDENT_IDS)
	assert_eq(runtime.get_residents().size(), 10)
	for resident in runtime.get_residents():
		assert_ne(resident.get_character_id(), "")
		assert_ne(resident.get_display_name(), "")
		assert_false(resident.get_schedule_state().is_empty())

	assert_same(hud.get_task_board(), runtime.get_task_board())
	assert_same(
		hud.get_relationship_ledger(),
		runtime.get_relationship_ledger(),
	)
	assert_same(
		hud.get_conversation_manager(),
		runtime.get_conversation_manager(),
	)


func test_running_runtime_advances_clock_hud_schedule_and_needs() -> void:
	var main := await _spawn_main()
	if main == null:
		return
	var runtime = main.get_node_or_null("TownRuntime")
	var hud: TownHud = main.get_node_or_null("HUD") as TownHud
	var player := main.get_node_or_null("Player") as CharacterBody3D
	if runtime == null or hud == null or player == null:
		assert_not_null(runtime)
		assert_not_null(hud)
		assert_not_null(player)
		return

	hud.start_game()
	var resident = runtime.get_resident("shen-yan")
	assert_not_null(resident)
	if resident == null:
		return
	player.global_position = resident.global_position
	var hunger_before: float = resident.get_need_levels()["hunger"]

	runtime.advance_real_seconds(60.0)

	assert_eq(runtime.get_clock_snapshot()["total_minutes"], 480)
	assert_eq(runtime.get_clock_snapshot()["minute_of_day"], 480)
	assert_eq(
		(main.get_node("HUD/%DateTimeLabel") as Label).text,
		"春季第 1 日  08:00",
	)
	assert_eq(resident.get_schedule_state()["location_id"], "bookshop")
	assert_gt(resident.get_need_levels()["hunger"], hunger_before)


func test_interact_opens_conversation_with_nearest_runtime_resident() -> void:
	var main := await _spawn_main()
	if main == null:
		return
	var runtime = main.get_node_or_null("TownRuntime")
	var hud: TownHud = main.get_node_or_null("HUD") as TownHud
	var player := main.get_node_or_null("Player") as CharacterBody3D
	if runtime == null or hud == null or player == null:
		assert_not_null(runtime)
		assert_not_null(hud)
		assert_not_null(player)
		return

	hud.start_game()
	var resident = runtime.get_resident("lin-xi")
	assert_not_null(resident)
	if resident == null:
		return
	player.global_position = resident.global_position + Vector3(0.5, 0.0, 0.0)
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true

	runtime._unhandled_input(event)
	await wait_process_frames(1)

	var panel := main.get_node("HUD/%ConversationPanel") as ConversationPanel
	assert_true(panel.visible)
	var context: Dictionary = runtime.get_conversation_manager().get_context(
		panel.get_active_conversation_id(),
	)
	assert_eq(context["participant_ids"], ["lin-xi"])


func test_main_exit_restores_runtime_and_applies_elapsed_catchup() -> void:
	var save_directory := _new_save_directory()
	var first_main := await _spawn_persistent_main(save_directory, 1000)
	if first_main == null:
		return
	var first_runtime = first_main.get_node_or_null("TownRuntime")
	assert_not_null(first_runtime)
	if first_runtime == null:
		first_main.queue_free()
		await wait_process_frames(1)
		return
	first_runtime.advance_real_seconds(60.0)
	var saved_hunger: float = (
		first_runtime.get_resident("shen-yan").get_need_levels()["hunger"]
	)

	first_main.queue_free()
	await wait_process_frames(2)

	assert_true(FileAccess.file_exists(
		save_directory.path_join("checkpoint.json"),
	))
	var restored_main := await _spawn_persistent_main(save_directory, 1120)
	if restored_main == null:
		return
	var restored_runtime = restored_main.get_node_or_null("TownRuntime")
	assert_not_null(restored_runtime)
	if restored_runtime == null:
		restored_main.queue_free()
		await wait_process_frames(1)
		return
	assert_true(restored_runtime.has_method("get_last_catchup_result"))
	assert_true(restored_runtime.has_method("get_scheduler_snapshot"))
	if (
		not restored_runtime.has_method("get_last_catchup_result")
		or not restored_runtime.has_method("get_scheduler_snapshot")
	):
		restored_main.queue_free()
		await wait_process_frames(2)
		return

	assert_eq(restored_runtime.get_clock_snapshot()["total_minutes"], 600)
	assert_eq(restored_runtime.get_clock_snapshot()["minute_of_day"], 600)
	assert_eq(
		restored_runtime.get_last_catchup_result(),
		{
			"from_tick": 480,
			"capped_days": 0,
			"to_tick": 600,
			"key_events": [],
			"task_changes": [],
			"relationship_changes": [],
			"town_digest": "听澜镇在你离开期间平稳运行了120游戏分钟。",
		},
	)
	assert_eq(
		restored_runtime.get_scheduler_snapshot()["last_world_minute"],
		600,
	)
	assert_gt(
		restored_runtime.get_resident(
			"shen-yan",
		).get_need_levels()["hunger"],
		saved_hunger,
	)
	assert_eq(
		restored_runtime.get_resident(
			"shen-yan",
		).get_schedule_state()["location_id"],
		"bookshop",
	)

	restored_main.queue_free()
	await wait_process_frames(2)


func test_runtime_catchup_is_applied_for_at_most_three_game_days() -> void:
	var save_directory := _new_save_directory()
	var first_main := await _spawn_persistent_main(save_directory, 2000)
	if first_main == null:
		return
	var first_runtime = first_main.get_node_or_null("TownRuntime")
	assert_not_null(first_runtime)
	if first_runtime == null:
		first_main.queue_free()
		await wait_process_frames(1)
		return
	first_runtime.advance_real_seconds(60.0)
	first_main.queue_free()
	await wait_process_frames(2)

	var restored_main := await _spawn_persistent_main(
		save_directory,
		12_000,
	)
	if restored_main == null:
		return
	var restored_runtime = restored_main.get_node_or_null("TownRuntime")
	assert_not_null(restored_runtime)
	if restored_runtime == null:
		restored_main.queue_free()
		await wait_process_frames(1)
		return
	assert_true(restored_runtime.has_method("get_last_catchup_result"))
	assert_true(restored_runtime.has_method("get_scheduler_snapshot"))
	if (
		not restored_runtime.has_method("get_last_catchup_result")
		or not restored_runtime.has_method("get_scheduler_snapshot")
	):
		restored_main.queue_free()
		await wait_process_frames(2)
		return

	var catchup: Dictionary = restored_runtime.get_last_catchup_result()
	assert_eq(catchup["from_tick"], 480)
	assert_eq(catchup["capped_days"], 3)
	assert_eq(catchup["to_tick"], 4800)
	assert_eq(restored_runtime.get_clock_snapshot()["total_minutes"], 4800)
	assert_eq(
		restored_runtime.get_scheduler_snapshot()["last_world_minute"],
		4800,
	)

	restored_main.queue_free()
	await wait_process_frames(2)


func _spawn_main() -> Node3D:
	var exists := ResourceLoader.exists(MAIN_SCENE_PATH)
	assert_true(exists)
	if not exists:
		return null
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var main := packed.instantiate() as Node3D
	main.set("auto_check_memoria", false)
	main.set("enable_persistence", false)
	add_child_autoqfree(main)
	await wait_process_frames(2)
	await wait_physics_frames(1)
	return main


func _spawn_persistent_main(
	save_directory: String,
	now_unix_seconds: int,
) -> Node3D:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var main := packed.instantiate() as Node3D
	main.set("auto_check_memoria", false)
	main.set("enable_persistence", true)
	main.set("memoria_save_directory", save_directory)
	main.set("persistence_unix_seconds_override", now_unix_seconds)
	add_child(main)
	await wait_process_frames(2)
	await wait_physics_frames(1)
	return main


func _new_save_directory() -> String:
	var save_directory := "user://town_runtime_tests/%d" % (
		Time.get_ticks_usec()
	)
	_save_directories.append(save_directory)
	return save_directory
