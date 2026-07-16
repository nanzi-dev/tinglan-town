extends GutTest

const SAVE_COORDINATOR_PATH := "res://scripts/core/save_coordinator.gd"
const INT64_MAX := 0x7fffffffffffffff
const INT64_MIN := -0x7fffffffffffffff - 1

var _save_dir: String


func before_each() -> void:
	_save_dir = "user://save_coordinator_tests/%d" % Time.get_ticks_usec()


func after_each() -> void:
	for file_name in [
		"checkpoint.json",
		"checkpoint.json.tmp",
		"checkpoint.json.bak",
		"events.jsonl",
	]:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_save_dir.path_join(file_name)),
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_dir))


func test_offline_catchup_is_capped_at_three_days() -> void:
	var coordinator_script = load(SAVE_COORDINATOR_PATH)
	assert_not_null(coordinator_script)
	if coordinator_script == null:
		return

	var coordinator = coordinator_script.new()
	var result: Dictionary = coordinator.calculate_catchup(
		0,
		10 * WorldClock.MINUTES_PER_DAY * 60,
	)

	assert_eq(result["capped_days"], 3)
	assert_eq(result["to_tick"], 3 * WorldClock.MINUTES_PER_DAY)


func test_offline_catchup_has_only_contract_fields_and_a_deterministic_digest() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new()

	var first: Dictionary = coordinator.calculate_catchup(30, 90)
	var second: Dictionary = coordinator.calculate_catchup(30, 90)
	var keys := first.keys()
	keys.sort()

	assert_eq(keys, [
		"capped_days",
		"from_tick",
		"key_events",
		"relationship_changes",
		"task_changes",
		"to_tick",
		"town_digest",
	])
	assert_eq(first, second)
	assert_eq(first["from_tick"], 30)
	assert_eq(first["to_tick"], 120)
	assert_eq(first["key_events"], [])
	assert_eq(first["task_changes"], [])
	assert_eq(first["relationship_changes"], [])
	assert_eq(first["town_digest"], "听澜镇在你离开期间平稳运行了90游戏分钟。")


func test_offline_catchup_rejects_negative_inputs() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new()

	assert_eq(coordinator.calculate_catchup(-1, 0), {})
	assert_eq(coordinator.calculate_catchup(0, -1), {})


func test_offline_catchup_caps_at_int64_max_without_overflowing() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new()
	var result: Dictionary = coordinator.calculate_catchup(INT64_MAX - 10, 90)

	assert_eq(result["from_tick"], INT64_MAX - 10)
	assert_eq(result["to_tick"], INT64_MAX)
	assert_eq(result["capped_days"], 0)
	assert_eq(result["town_digest"], "听澜镇在你离开期间平稳运行了10游戏分钟。")


func test_checkpoint_round_trip_preserves_nested_int64_without_tag_collisions() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	var precise_value := 9007199254740993
	var world_state := {
		"clock": {"total_minutes": precise_value},
		"scheduler": {
			"ticks": [
				INT64_MIN,
				-17,
				0,
				precise_value,
				INT64_MAX,
			],
		},
		"user_dictionary": {
			"type": "int64",
			"value": "9007199254740993",
		},
	}

	assert_eq(
		coordinator.save_checkpoint(world_state, precise_value, ["event-old"]),
		OK,
	)
	var recovered: Dictionary = coordinator.recover()

	assert_true(recovered["ok"])
	assert_eq(recovered["world_state"], world_state)
	assert_eq(recovered["last_event_sequence"], precise_value)
	assert_eq(recovered["processed_event_ids"], ["event-old"])
	assert_eq(
		typeof(recovered["world_state"]["clock"]["total_minutes"]),
		TYPE_INT,
	)
	for value in recovered["world_state"]["scheduler"]["ticks"]:
		assert_eq(typeof(value), TYPE_INT)


func test_checkpoint_rejects_unsupported_nested_value_without_replacing_previous_state() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	assert_eq(
		coordinator.save_checkpoint({"coins": 10}, 4, ["event-4"]),
		OK,
	)

	var save_error: Error = coordinator.save_checkpoint(
		{"nested": [{"unsupported": Vector2(1.0, 2.0)}]},
		5,
		["event-4", "event-5"],
	)
	var recovered: Dictionary = coordinator.recover()

	assert_ne(save_error, OK)
	assert_true(recovered["ok"])
	assert_eq(recovered["world_state"], {"coins": 10})
	assert_eq(recovered["last_event_sequence"], 4)
	assert_eq(recovered["processed_event_ids"], ["event-4"])


func test_checkpoint_rejects_non_finite_floats_without_replacing_previous_state() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	for invalid_float in [NAN, INF]:
		assert_eq(
			coordinator.save_checkpoint({"coins": 10}, 4, ["event-4"]),
			OK,
		)

		var save_error: Error = coordinator.save_checkpoint(
			{"nested": [{"invalid_float": invalid_float}]},
			5,
			["event-4", "event-5"],
		)
		var recovered: Dictionary = coordinator.recover()

		assert_ne(save_error, OK)
		assert_true(recovered["ok"])
		assert_eq(recovered["world_state"], {"coins": 10})
		assert_eq(recovered["last_event_sequence"], 4)
		assert_eq(recovered["processed_event_ids"], ["event-4"])


func test_checkpoint_rejects_invalid_metadata_without_replacing_previous_state() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	for invalid_metadata in [
		{"last_event_sequence": -2, "processed_event_ids": []},
		{"last_event_sequence": 5, "processed_event_ids": [""]},
		{"last_event_sequence": 5, "processed_event_ids": ["duplicate", "duplicate"]},
		{"last_event_sequence": 5, "processed_event_ids": [123]},
	]:
		assert_eq(
			coordinator.save_checkpoint({"coins": 10}, 4, ["event-4"]),
			OK,
		)

		var save_error: Error = coordinator.save_checkpoint(
			{"coins": 999},
			invalid_metadata["last_event_sequence"],
			invalid_metadata["processed_event_ids"],
		)
		var recovered: Dictionary = coordinator.recover()

		assert_ne(save_error, OK)
		assert_true(recovered["ok"])
		assert_eq(recovered["world_state"], {"coins": 10})
		assert_eq(recovered["last_event_sequence"], 4)
		assert_eq(recovered["processed_event_ids"], ["event-4"])


func test_checkpoint_replace_failure_preserves_previous_recoverable_state() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	assert_eq(
		coordinator.save_checkpoint({"coins": 10}, 4, ["event-4"]),
		OK,
	)
	var backup_path := ProjectSettings.globalize_path(
		_save_dir.path_join("checkpoint.json.bak"),
	)
	assert_eq(DirAccess.make_dir_recursive_absolute(backup_path), OK)

	var save_error: Error = coordinator.save_checkpoint(
		{"coins": 999},
		5,
		["event-4", "event-5"],
	)
	var recovered: Dictionary = coordinator.recover()

	assert_ne(save_error, OK)
	assert_true(recovered["ok"])
	assert_eq(recovered["world_state"], {"coins": 10})
	assert_eq(recovered["last_event_sequence"], 4)
	assert_eq(recovered["processed_event_ids"], ["event-4"])
	assert_false(FileAccess.file_exists(
		_save_dir.path_join("checkpoint.json.tmp"),
	))


func test_checkpoint_failure_preserves_backup_when_it_is_only_recoverable_state() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	assert_eq(
		coordinator.save_checkpoint({"coins": 10}, 4, ["event-4"]),
		OK,
	)
	var checkpoint_path := ProjectSettings.globalize_path(
		_save_dir.path_join("checkpoint.json"),
	)
	var backup_path := ProjectSettings.globalize_path(
		_save_dir.path_join("checkpoint.json.bak"),
	)
	assert_eq(
		DirAccess.rename_absolute(checkpoint_path, backup_path),
		OK,
	)
	assert_eq(DirAccess.make_dir_recursive_absolute(checkpoint_path), OK)

	var save_error: Error = coordinator.save_checkpoint(
		{"coins": 999},
		5,
		["event-4", "event-5"],
	)
	var recovered: Dictionary = coordinator.recover()

	assert_ne(save_error, OK)
	assert_true(recovered["ok"])
	assert_eq(recovered["world_state"], {"coins": 10})
	assert_eq(recovered["last_event_sequence"], 4)
	assert_eq(recovered["processed_event_ids"], ["event-4"])
	assert_false(FileAccess.file_exists(
		_save_dir.path_join("checkpoint.json.tmp"),
	))


func test_recover_uses_backup_after_crash_between_atomic_renames() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	assert_eq(
		coordinator.save_checkpoint({"project_stage": 2}, 8, ["event-8"]),
		OK,
	)
	assert_eq(
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(
				_save_dir.path_join("checkpoint.json"),
			),
			ProjectSettings.globalize_path(
				_save_dir.path_join("checkpoint.json.bak"),
			),
		),
		OK,
	)
	var partial_file := FileAccess.open(
		_save_dir.path_join("checkpoint.json.tmp"),
		FileAccess.WRITE,
	)
	partial_file.store_string("{\"format\":")
	partial_file.close()

	var recovered: Dictionary = coordinator.recover()

	assert_true(recovered["ok"])
	assert_eq(recovered["world_state"], {"project_stage": 2})
	assert_eq(recovered["last_event_sequence"], 8)
	assert_eq(recovered["processed_event_ids"], ["event-8"])


func test_event_log_appends_one_json_object_per_line() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	assert_eq(coordinator.append_event({
		"sequence": 1,
		"event_id": "event-1",
		"reward_delta": 10,
	}), OK)
	assert_eq(coordinator.append_event({
		"sequence": 2,
		"event_id": "event-2",
		"reward_delta": 20,
	}), OK)

	var event_file := FileAccess.open(
		_save_dir.path_join("events.jsonl"),
		FileAccess.READ,
	)
	var lines := event_file.get_as_text().split("\n", false)
	event_file.close()

	assert_eq(lines.size(), 2)
	for line in lines:
		assert_eq(typeof(JSON.parse_string(line)), TYPE_DICTIONARY)


func test_event_log_rejects_invalid_or_unencodable_events_without_appending() -> void:
	var coordinator = load(SAVE_COORDINATOR_PATH).new(_save_dir)
	var event_path := _save_dir.path_join("events.jsonl")
	assert_eq(coordinator.append_event({
		"sequence": 1,
		"event_id": "valid-event",
		"precise_value": 9007199254740993,
	}), OK)
	var original_contents := _read_text_file(event_path)

	for invalid_event in [
		{"event_id": "missing-sequence"},
		{"sequence": "2", "event_id": "string-sequence"},
		{"sequence": -1, "event_id": "negative-sequence"},
		{"sequence": 2},
		{"sequence": 2, "event_id": 123},
		{"sequence": 2, "event_id": ""},
		{"sequence": 2, "event_id": "unsupported", "value": Vector2.ZERO},
		{"sequence": 2, "event_id": "not-finite", "value": NAN},
	]:
		assert_ne(coordinator.append_event(invalid_event), OK)
		assert_eq(_read_text_file(event_path), original_contents)


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var contents := file.get_as_text()
	file.close()
	return contents
