extends GutTest

const MEMORIA_CLIENT_PATH := "res://scripts/services/memoria_client.gd"
const PENDING_EVENT_QUEUE_PATH := "res://scripts/services/pending_event_queue.gd"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"

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
	_save_dir = "user://memoria_degraded_tests/%d" % Time.get_ticks_usec()


func after_each() -> void:
	for file_name in [
		"pending_memoria_events.json",
		"pending_memoria_events.json.tmp",
	]:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_save_dir.path_join(file_name)),
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_dir))


func test_unavailable_memoria_keeps_local_play_and_resumes_only_pending_events() -> void:
	assert_true(ResourceLoader.exists(MEMORIA_CLIENT_PATH))
	assert_true(ResourceLoader.exists(PENDING_EVENT_QUEUE_PATH))
	if (
		not ResourceLoader.exists(MEMORIA_CLIENT_PATH)
		or not ResourceLoader.exists(PENDING_EVENT_QUEUE_PATH)
	):
		return

	var queue_script = load(PENDING_EVENT_QUEUE_PATH)
	var client_script = load(MEMORIA_CLIENT_PATH)
	var queue = queue_script.new(_save_dir)
	var event_a := _social_event(
		"event-a",
		"9b5fbc2c-04cf-4578-8d83-64b6f99336d0",
		720,
	)
	var event_b := _social_event(
		"event-b",
		"9b5fbc2c-04cf-4578-8d83-64b6f99336d0",
		720,
	)
	assert_eq(queue.enqueue(event_a), OK)
	assert_eq(queue.enqueue(event_a), OK)
	assert_eq(queue.enqueue(event_b), OK)
	assert_eq(queue.pending_events().size(), 2)

	var unavailable_request := FakeHttpRequest.new()
	unavailable_request.completions.append({
		"result": HTTPRequest.RESULT_CANT_CONNECT,
		"response_code": 0,
	})
	var client = client_script.new()
	client.retry_delays.clear()
	client.configure(
		"http://127.0.0.1:8000/api/v1",
		"test-token",
		queue,
		unavailable_request,
		FakeHttpRequest.new(),
		"tinglan-world-01",
		"slot-01",
	)
	add_child_autoqfree(client)

	var started_at := Time.get_ticks_usec()
	assert_eq(client.flush_pending_events(), OK)
	var returned_in_usec := Time.get_ticks_usec() - started_at
	var local_decision := AgentController.new().resolve_decision(
		[
			{"id": "continue_work", "utility": 0.8},
			{"id": "wait_for_service", "utility": -1.0},
		],
		{},
	)
	await wait_process_frames(3)

	assert_lt(returned_in_usec, 50_000)
	assert_eq(local_decision["id"], "continue_work")
	assert_eq(local_decision["source"], "local_fallback")
	assert_eq(client.connection_status, "recoverable_error")
	assert_eq(queue.pending_events().size(), 2)
	assert_eq(unavailable_request.requests.size(), 1)

	var recovery_response := {
		"request_id": event_a["request_id"],
		"tick_id": event_a["tick_id"],
		"results": [{
			"event_id": event_a["event_id"],
			"duplicate": false,
			"projection": {},
		}],
	}
	unavailable_request.completions.append({"body": recovery_response})
	assert_eq(client.flush_pending_events(), OK)
	await wait_process_frames(3)

	assert_eq(queue.pending_events(), [event_b])
	var recovery_payload: Dictionary = JSON.parse_string(
		unavailable_request.requests[1]["body"],
	)
	assert_eq(recovery_payload["events"].size(), 2)

	client.queue_free()
	await wait_process_frames(1)
	var reloaded_queue = queue_script.new(_save_dir)
	var queue_path := _save_dir.path_join("pending_memoria_events.json")
	assert_true(FileAccess.file_exists(queue_path))
	assert_eq(
		reloaded_queue.load_error,
		OK,
		_read_text(queue_path),
	)
	assert_eq(reloaded_queue.pending_events(), [event_b])

	var restored_request := FakeHttpRequest.new()
	restored_request.completions.append({
		"body": {
			"request_id": event_b["request_id"],
			"tick_id": event_b["tick_id"],
			"results": [{
				"event_id": event_b["event_id"],
				"duplicate": false,
				"projection": {},
			}],
		},
	})
	var restored_client = client_script.new()
	restored_client.retry_delays.clear()
	restored_client.configure(
		"http://127.0.0.1:8000/api/v1",
		"test-token",
		reloaded_queue,
		restored_request,
		FakeHttpRequest.new(),
		"tinglan-world-01",
		"slot-01",
	)
	add_child_autoqfree(restored_client)
	assert_eq(restored_client.flush_pending_events(), OK)
	await wait_process_frames(3)

	var restored_payload: Dictionary = JSON.parse_string(
		restored_request.requests[0]["body"],
	)
	assert_eq(restored_payload["events"].map(
		func(event: Dictionary) -> String: return event["event_id"],
	), ["event-b"])
	assert_true(reloaded_queue.pending_events().is_empty())
	assert_eq(restored_client.connection_status, "connected")


func test_main_scene_reports_memoria_connection_status_in_the_hud() -> void:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var main := packed.instantiate()
	main.set("auto_check_memoria", false)
	add_child_autoqfree(main)
	await wait_process_frames(1)

	var client := main.get_node_or_null("MemoriaClient") as MemoriaClient
	assert_not_null(client)
	if client == null:
		return
	client.connection_status_changed.emit("recoverable_error")
	await wait_process_frames(1)

	var status_label := main.get_node_or_null(
		"HUD/%MemoriaStatusLabel",
	) as Label
	assert_not_null(status_label)
	if status_label != null:
		assert_eq(status_label.text, "Memoria：可恢复错误")


func _social_event(
	event_id: String,
	request_id: String,
	tick_id: int,
) -> Dictionary:
	return {
		"event_id": event_id,
		"request_id": request_id,
		"tick_id": tick_id,
		"event_type": "relationship_changed",
		"participants": ["shen-yan", "lin-xi"],
		"world_time": {
			"season": "spring",
			"day": 1,
			"minute": tick_id % WorldClock.MINUTES_PER_DAY,
		},
		"structured_result": {
			"character_id_a": "shen-yan",
			"character_id_b": "lin-xi",
			"affinity_delta": 1,
		},
		"source_action_id": "talk:shen-yan:lin-xi",
	}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
