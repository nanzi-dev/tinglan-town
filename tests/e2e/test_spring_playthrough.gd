extends GutTest

const TEST_SEED := 20260716
const TEST_DAYS := 14
const TEST_REQUEST_ID := "4dc92d6e-a264-4f9d-b7f6-e863fd763184"

var _save_dir: String


class FakeHttpRequest:
	extends Node

	signal request_completed(
		result: int,
		response_code: int,
		headers: PackedStringArray,
		body: PackedByteArray,
	)

	var requests: Array[Dictionary] = []
	var completions: Array[Dictionary] = []


	func request(
		url: String,
		headers: PackedStringArray = PackedStringArray(),
		method: HTTPClient.Method = HTTPClient.METHOD_GET,
		request_data: String = "",
	) -> Error:
		requests.append({
			"url": url,
			"headers": headers,
			"method": method,
			"body": request_data,
		})
		if not completions.is_empty():
			call_deferred("_complete", completions.pop_front())
		return OK


	func _complete(completion: Dictionary) -> void:
		request_completed.emit(
			completion.get("result", HTTPRequest.RESULT_SUCCESS),
			completion.get("response_code", 200),
			PackedStringArray(),
			JSON.stringify(completion.get("body", {})).to_utf8_buffer(),
		)


func before_each() -> void:
	_save_dir = "user://spring_playthrough_tests/%d" % Time.get_ticks_usec()


func after_each() -> void:
	for file_name in [
		"checkpoint.json",
		"checkpoint.json.tmp",
		"checkpoint.json.bak",
		"events.jsonl",
		"pending_memoria_events.json",
		"pending_memoria_events.json.tmp",
	]:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_save_dir.path_join(file_name)),
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_dir))


func test_spring_playthrough_survives_crash_and_memoria_recovery() -> void:
	var repository := ContentRepository.new()
	assert_true(repository.load_spring())

	var simulation := GameState.new().simulate_days(TEST_SEED, TEST_DAYS)
	assert_eq(simulation["seed"], TEST_SEED)
	assert_eq(simulation["days"], TEST_DAYS)
	assert_eq(simulation["unique_agents"], 10)
	assert_gt(simulation["encounters"], 0)
	assert_gt(simulation["task_changes"], 0)
	assert_gt(simulation["relationship_changes"], 0)

	var conversation_manager := ConversationManager.new()
	var conversation := conversation_manager.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)
	var conversation_id: String = conversation["conversation_id"]
	assert_true(conversation_manager.listen(conversation_id)["accepted"])
	assert_true(conversation_manager.request_join(conversation_id)["accepted"])
	var join_result := conversation_manager.resolve_join_request(conversation_id)
	assert_true(join_result["accepted"])
	assert_eq(join_result["source"], "local")
	assert_true(conversation_manager.submit_player_text(
		conversation_id,
		"我来发布修桥物资任务，也会参加施工。",
	)["accepted"])
	assert_true(conversation_manager.submit_context_action(
		conversation_id,
		"offer_help",
	)["accepted"])

	var event_log := DomainEventLog.new()
	var task_board := TaskBoard.new(event_log)
	var player_task := {
		"task_id": "player-task-bridge-timber",
		"source": "player",
		"status": "open",
		"accepted_by": "lu-qiao",
		"reward": {"coins": 80},
		"completion_rules": [{
			"type": "delivered_to",
			"character_id": "lu-qiao",
			"item_id": "repair_timber",
			"count": 5,
		}],
	}
	assert_true(task_board.add_task(player_task))
	assert_true(task_board.transition_task(
		player_task["task_id"],
		"accepted",
	))
	var task_event_id := "task-completed:player-task-bridge-timber"
	var task_result := task_board.complete_task(
		player_task["task_id"],
		task_event_id,
		{"facts": [player_task["completion_rules"][0].duplicate(true)]},
	)
	assert_eq(task_result["reward"], player_task["reward"])
	assert_eq(task_board.task_status(player_task["task_id"]), "rewarded")
	assert_eq(task_board.complete_task(
		player_task["task_id"],
		task_event_id,
		{"facts": [player_task["completion_rules"][0].duplicate(true)]},
	)["reward"], {"coins": 0})

	var relationship_ledger := RelationshipLedger.new(event_log)
	var relationship_event_id := "relationship:bridge-help:lin-xi"
	assert_true(relationship_ledger.apply_change(
		"lin-xi",
		35,
		30,
		0,
		"共同推进听雨桥修缮",
		relationship_event_id,
	))
	assert_false(relationship_ledger.apply_change(
		"lin-xi",
		35,
		30,
		0,
		"共同推进听雨桥修缮",
		relationship_event_id,
	))
	assert_eq(
		relationship_ledger.public_view("lin-xi")["recent_reasons"],
		["共同推进听雨桥修缮"],
	)

	var project := CommunityProject.new(
		repository.community_project,
		event_log,
	)
	assert_true(project.begin_collecting("project:bridge:collecting"))
	assert_true(project.contribute_resources(
		"project:bridge:resources",
		{"repair_timber": 30, "lime": 12},
		500,
	))
	var voters := [
		"lin-xi",
		"shen-yan",
		"zhou-he",
		"lu-qiao",
		"su-wan",
		"gu-yun",
	]
	for voter_id in voters:
		assert_true(project.submit_vote(
			"project:bridge:vote:%s" % voter_id,
			voter_id,
			"support",
		))
	assert_false(project.submit_vote(
		"project:bridge:vote:lin-xi",
		"lin-xi",
		"support",
	))
	assert_eq(project.current_stage(), "construction")
	assert_true(project.advance_construction_day(
		"project:bridge:construction:1",
	))
	assert_true(project.advance_construction_day(
		"project:bridge:construction:2",
	))
	assert_false(project.advance_construction_day(
		"project:bridge:construction:2",
	))
	assert_eq(project.current_stage(), "completed")

	var clock := WorldClock.new()
	clock.advance_game_minutes(
		11 * WorldClock.MINUTES_PER_DAY + 18 * 60,
	)
	assert_eq(clock.day, 12)
	assert_eq(clock.minute_of_day, 1080)

	var festival := FestivalManager.new(repository.festival, event_log)
	var festival_result := festival.trigger_if_due(
		"spring",
		clock.day,
		clock.minute_of_day,
		{
			"preparation_level": 80,
			"community_project_stage": project.current_stage(),
			"player_resident_promise_fulfillment": 100,
		},
	)
	assert_true(festival_result["triggered"])
	assert_true(festival_result["completed"])
	assert_eq(festival_result["branch_id"], "high")
	assert_eq(festival.trigger_if_due(
		"spring",
		clock.day,
		clock.minute_of_day,
		{
			"preparation_level": 80,
			"community_project_stage": project.current_stage(),
			"player_resident_promise_fulfillment": 100,
		},
	)["reason"], "already_completed")

	var pending_queue := PendingEventQueue.new(_save_dir)
	var social_events := [
		_social_event(
			"social:conversation-joined",
			"conversation_joined",
			["player", "lin-xi", "shen-yan"],
			clock.total_minutes,
		),
		_social_event(
			"social:task-completed",
			"task_completed",
			["player", "lu-qiao"],
			clock.total_minutes,
		),
		_social_event(
			"social:project-vote",
			"project_vote",
			["player", "lin-xi"],
			clock.total_minutes,
		),
		_social_event(
			"social:relationship-changed",
			"relationship_changed",
			["player", "lin-xi"],
			clock.total_minutes,
		),
	]
	for social_event in social_events:
		assert_eq(pending_queue.enqueue(social_event), OK)
		assert_eq(pending_queue.enqueue(social_event), OK)
	assert_eq(pending_queue.pending_events().size(), social_events.size())

	var unavailable_request := FakeHttpRequest.new()
	unavailable_request.completions.append({
		"result": HTTPRequest.RESULT_CANT_CONNECT,
		"response_code": 0,
	})
	var unavailable_client := MemoriaClient.new()
	unavailable_client.retry_delays.clear()
	unavailable_client.configure(
		"http://127.0.0.1:8000/api/v1",
		"test-token",
		pending_queue,
		unavailable_request,
		FakeHttpRequest.new(),
		"tinglan-world-01",
		"slot-01",
	)
	add_child_autoqfree(unavailable_client)
	assert_eq(unavailable_client.flush_pending_events(), OK)
	await wait_process_frames(3)
	assert_eq(unavailable_client.connection_status, "recoverable_error")
	assert_eq(pending_queue.pending_events().size(), social_events.size())

	var initial_effect_counts := {
		"reward": 1,
		"memory": 1,
		"task": 1,
		"project": 1,
	}
	var world_state := {
		"seed": TEST_SEED,
		"clock": clock.to_dict(),
		"conversation": {
			"join_state": conversation_manager.get_join_state(
				conversation_id,
			),
			"transcript": conversation_manager.get_transcript(
				conversation_id,
			),
		},
		"task": {
			"task_id": player_task["task_id"],
			"status": task_board.task_status(player_task["task_id"]),
			"reward": task_result["reward"],
		},
		"relationship": relationship_ledger.public_view("lin-xi"),
		"project": project.snapshot(),
		"festival": festival_result,
		"effect_counts": initial_effect_counts.duplicate(true),
		"effect_event_ids": {
			"reward": [task_event_id],
			"memory": [relationship_event_id],
			"task": [task_event_id],
			"project": ["project:bridge:construction:2"],
		},
		"simulation_hash": JSON.stringify(simulation).sha256_text(),
	}
	var coordinator := SaveCoordinator.new(_save_dir)
	assert_eq(coordinator.save_checkpoint(world_state, 0, []), OK)

	var replay_effects := [
		{
			"event_id": "replay:festival-reward",
			"effect_type": "reward",
		},
		{
			"event_id": "replay:festival-memory",
			"effect_type": "memory",
		},
		{
			"event_id": "replay:festival-task",
			"effect_type": "task",
		},
		{
			"event_id": "replay:project-completion",
			"effect_type": "project",
		},
	]
	var sequence := 0
	for replay_effect in replay_effects:
		for _duplicate_index in range(2):
			sequence += 1
			var event: Dictionary = replay_effect.duplicate(true)
			event["sequence"] = sequence
			assert_eq(coordinator.append_event(event), OK)

	unavailable_client.queue_free()
	await wait_process_frames(1)

	var restored_coordinator := SaveCoordinator.new(_save_dir)
	var recovered := restored_coordinator.recover(
		Callable(self, "_apply_recovery_effect"),
	)
	assert_true(recovered["ok"])
	assert_eq(recovered["last_event_sequence"], sequence)
	assert_eq(recovered["world_state"]["seed"], TEST_SEED)
	assert_eq(recovered["world_state"]["clock"], clock.to_dict())
	assert_eq(recovered["world_state"]["task"]["status"], "rewarded")
	assert_eq(recovered["world_state"]["project"]["stage"], "completed")
	assert_eq(recovered["world_state"]["festival"]["branch_id"], "high")
	for effect_type in initial_effect_counts:
		assert_eq(
			recovered["world_state"]["effect_counts"][effect_type],
			initial_effect_counts[effect_type] + 1,
		)
		assert_eq(
			recovered["world_state"]["effect_event_ids"][effect_type].size(),
			initial_effect_counts[effect_type] + 1,
		)

	var catchup := restored_coordinator.calculate_catchup(
		recovered["world_state"]["clock"]["total_minutes"],
		5 * WorldClock.MINUTES_PER_DAY * 60,
	)
	assert_eq(catchup["capped_days"], 3)
	assert_eq(
		catchup["to_tick"],
		clock.total_minutes + 3 * WorldClock.MINUTES_PER_DAY,
	)
	assert_false(catchup["town_digest"].is_empty())

	var restored_queue := PendingEventQueue.new(_save_dir)
	assert_eq(restored_queue.load_error, OK)
	assert_eq(restored_queue.pending_events().size(), social_events.size())
	var synchronization_results := []
	for social_event in social_events:
		synchronization_results.append({
			"event_id": social_event["event_id"],
			"duplicate": false,
			"projection": {},
		})
	var recovery_request := FakeHttpRequest.new()
	recovery_request.completions.append({
		"body": {
			"request_id": TEST_REQUEST_ID,
			"tick_id": clock.total_minutes,
			"results": synchronization_results,
		},
	})
	var restored_client := MemoriaClient.new()
	restored_client.retry_delays.clear()
	restored_client.configure(
		"http://127.0.0.1:8000/api/v1",
		"test-token",
		restored_queue,
		recovery_request,
		FakeHttpRequest.new(),
		"tinglan-world-01",
		"slot-01",
	)
	add_child_autoqfree(restored_client)
	assert_eq(restored_client.flush_pending_events(), OK)
	await wait_process_frames(3)

	assert_eq(restored_client.connection_status, "connected")
	assert_true(restored_queue.pending_events().is_empty())
	var synchronized_payload: Dictionary = JSON.parse_string(
		recovery_request.requests[0]["body"],
	)
	assert_eq(synchronized_payload["events"].size(), social_events.size())


func test_release_defines_linux_and_windows_export_targets() -> void:
	var presets_path := "res://export_presets.cfg"
	var export_script_path := "res://tools/export.sh"
	assert_true(
		FileAccess.file_exists(presets_path),
		"Release requires export_presets.cfg.",
	)
	assert_true(
		FileAccess.file_exists(export_script_path),
		"Release requires tools/export.sh.",
	)
	if (
		not FileAccess.file_exists(presets_path)
		or not FileAccess.file_exists(export_script_path)
	):
		return

	var config := ConfigFile.new()
	assert_eq(config.load(presets_path), OK)
	var preset_names := []
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.contains(".options"):
			preset_names.append(str(config.get_value(section, "name", "")))
	assert_has(preset_names, "Linux")
	assert_has(preset_names, "Windows")

	var export_script := FileAccess.get_file_as_string(export_script_path)
	assert_true(export_script.contains("--export-release Linux"))
	assert_true(export_script.contains("--export-release Windows"))


func _social_event(
	event_id: String,
	event_type: String,
	participants: Array,
	tick_id: int,
) -> Dictionary:
	return {
		"event_id": event_id,
		"request_id": TEST_REQUEST_ID,
		"tick_id": tick_id,
		"event_type": event_type,
		"participants": participants.duplicate(),
		"world_time": {
			"season": "spring",
			"day": 12,
			"minute": 1080,
		},
		"structured_result": {"source": "spring_playthrough"},
		"source_action_id": event_id,
	}


func _apply_recovery_effect(
	world_state: Dictionary,
	event: Dictionary,
) -> bool:
	var effect_type = event.get("effect_type", null)
	var event_id = event.get("event_id", null)
	if (
		typeof(effect_type) != TYPE_STRING
		or typeof(event_id) != TYPE_STRING
		or not world_state["effect_counts"].has(effect_type)
	):
		return false
	var event_ids: Array = world_state["effect_event_ids"][effect_type]
	if event_ids.has(event_id):
		return true
	event_ids.append(event_id)
	world_state["effect_counts"][effect_type] += 1
	return true
