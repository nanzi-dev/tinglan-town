extends GutTest

var _save_dir: String


func before_each() -> void:
	_save_dir = "user://crash_recovery_tests/%d" % Time.get_ticks_usec()


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


func test_duplicate_logged_event_advances_each_domain_effect_once() -> void:
	var coordinator := SaveCoordinator.new(_save_dir)
	var checkpoint_state := {
		"coins": 100,
		"relationships": {"lin-xi": 20},
		"project_stage": 1,
	}
	assert_eq(coordinator.save_checkpoint(checkpoint_state, 0, []), OK)
	var event := {
		"sequence": 1,
		"event_id": "festival-approved",
		"reward_delta": 80,
		"relationship_delta": 5,
		"project_stage_delta": 1,
	}
	assert_eq(coordinator.append_event(event), OK)
	assert_eq(coordinator.append_event(event), OK)

	var recovered: Dictionary = coordinator.recover(
		Callable(self, "_apply_test_event"),
	)

	assert_true(recovered["ok"])
	assert_eq(recovered["world_state"]["coins"], 180)
	assert_eq(recovered["world_state"]["relationships"]["lin-xi"], 25)
	assert_eq(recovered["world_state"]["project_stage"], 2)
	assert_eq(recovered["last_event_sequence"], 1)
	assert_eq(recovered["processed_event_ids"], ["festival-approved"])


func test_failed_projection_rolls_back_replay_and_does_not_skip_to_later_events() -> void:
	var coordinator := SaveCoordinator.new(_save_dir)
	var checkpoint_state := {"applied_event_ids": []}
	assert_eq(coordinator.save_checkpoint(checkpoint_state, 0, []), OK)
	for event in [
		{"sequence": 1, "event_id": "event-1"},
		{"sequence": 2, "event_id": "event-2", "reject": true},
		{"sequence": 3, "event_id": "event-3"},
	]:
		assert_eq(coordinator.append_event(event), OK)

	var recovered: Dictionary = coordinator.recover(
		Callable(self, "_apply_event_unless_rejected"),
	)

	assert_false(recovered["ok"])
	assert_eq(recovered["world_state"], checkpoint_state)
	assert_eq(recovered["last_event_sequence"], 0)
	assert_eq(recovered["processed_event_ids"], [])


func test_corrupt_event_log_rolls_back_replay_instead_of_skipping_bad_lines() -> void:
	var coordinator := SaveCoordinator.new(_save_dir)
	var checkpoint_state := {"applied_event_ids": []}
	assert_eq(coordinator.save_checkpoint(checkpoint_state, 0, []), OK)
	assert_eq(coordinator.append_event({
		"sequence": 1,
		"event_id": "event-1",
	}), OK)
	var event_file := FileAccess.open(
		_save_dir.path_join("events.jsonl"),
		FileAccess.READ_WRITE,
	)
	event_file.seek_end()
	event_file.store_line("{corrupt")
	event_file.close()

	var recovered: Dictionary = coordinator.recover(
		Callable(self, "_apply_event_unless_rejected"),
	)

	assert_false(recovered["ok"])
	assert_eq(recovered["world_state"], checkpoint_state)
	assert_eq(recovered["last_event_sequence"], 0)
	assert_eq(recovered["processed_event_ids"], [])


func test_replay_filters_checkpointed_events_and_orders_new_events_deterministically() -> void:
	var coordinator := SaveCoordinator.new(_save_dir)
	var checkpoint_state := {"applied_event_ids": []}
	assert_eq(
		coordinator.save_checkpoint(checkpoint_state, 5, ["already-processed"]),
		OK,
	)
	for event in [
		{"sequence": 8, "event_id": "event-z"},
		{"sequence": 5, "event_id": "equal-sequence"},
		{"sequence": 6, "event_id": "event-b"},
		{"sequence": 4, "event_id": "lower-sequence"},
		{"sequence": 7, "event_id": "already-processed"},
		{"sequence": 6, "event_id": "event-a"},
	]:
		assert_eq(coordinator.append_event(event), OK)

	var recovered: Dictionary = coordinator.recover(
		Callable(self, "_apply_event_unless_rejected"),
	)

	assert_true(recovered["ok"])
	assert_eq(recovered["world_state"]["applied_event_ids"], [
		"event-a",
		"event-b",
		"event-z",
	])
	assert_eq(recovered["last_event_sequence"], 8)
	assert_eq(recovered["processed_event_ids"], [
		"already-processed",
		"event-a",
		"event-b",
		"event-z",
	])


func _apply_test_event(world_state: Dictionary, event: Dictionary) -> bool:
	for field in [
		"reward_delta",
		"relationship_delta",
		"project_stage_delta",
	]:
		if typeof(event.get(field, null)) != TYPE_INT:
			return false

	world_state["coins"] += event["reward_delta"]
	world_state["relationships"]["lin-xi"] += event["relationship_delta"]
	world_state["project_stage"] += event["project_stage_delta"]
	return true


func _apply_event_unless_rejected(
	world_state: Dictionary,
	event: Dictionary,
) -> bool:
	if event.get("reject", false):
		return false
	world_state["applied_event_ids"].append(event["event_id"])
	return true
