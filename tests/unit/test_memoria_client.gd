extends GutTest

const MEMORIA_CLIENT_PATH := "res://scripts/services/memoria_client.gd"
const PENDING_EVENT_QUEUE_PATH := "res://scripts/services/pending_event_queue.gd"


class FakeHttpRequest:
	extends Node

	signal request_completed(
		result: int,
		response_code: int,
		headers: PackedStringArray,
		body: PackedByteArray,
	)

	var requests: Array[Dictionary] = []


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
		return OK


func test_retry_policy_matches_the_memoria_contract() -> void:
	assert_true(ResourceLoader.exists(MEMORIA_CLIENT_PATH))
	if not ResourceLoader.exists(MEMORIA_CLIENT_PATH):
		return

	var client_script = load(MEMORIA_CLIENT_PATH)
	assert_eq(client_script.RETRY_DELAYS, [0.5, 1.0, 2.0, 4.0])
	assert_eq(client_script.MAX_RETRY_ATTEMPTS, 4)


func test_unknown_candidate_marks_protocol_error_and_uses_local_fallback() -> void:
	assert_true(ResourceLoader.exists(MEMORIA_CLIENT_PATH))
	if not ResourceLoader.exists(MEMORIA_CLIENT_PATH):
		return

	var client = load(MEMORIA_CLIENT_PATH).new()
	add_child_autoqfree(client)
	var parsed: Dictionary = client.validate_agent_decision_response(
		{
			"request_id": "f65c57b7-9904-47a6-a7df-3c54d85aa9e3",
			"tick_id": 480,
			"decisions": [{
				"character_id": "shen-yan",
				"candidate_action_id": "invent-world-action",
				"source": "memoria",
			}],
		},
		{"shen-yan": ["repair_bridge", "drink_tea"]},
	)
	var resolved := AgentController.new().resolve_decision(
		[
			{"id": "repair_bridge", "utility": 0.9},
			{"id": "drink_tea", "utility": 0.4},
		],
		parsed.get("decisions", {}).get("shen-yan", {}),
	)

	assert_false(parsed["ok"])
	assert_eq(client.connection_status, "protocol_error")
	assert_eq(resolved["id"], "repair_bridge")
	assert_eq(resolved["source"], "local_fallback")


func test_valid_decision_strips_server_world_mutations() -> void:
	assert_true(ResourceLoader.exists(MEMORIA_CLIENT_PATH))
	if not ResourceLoader.exists(MEMORIA_CLIENT_PATH):
		return

	var client = load(MEMORIA_CLIENT_PATH).new()
	add_child_autoqfree(client)
	var parsed: Dictionary = client.validate_agent_decision_response(
		{
			"request_id": "322dfb91-ddd1-4037-a16d-38fcd11a9de7",
			"tick_id": 510,
			"decisions": [{
				"character_id": "lin-xi",
				"candidate_action_id": "offer_tea",
				"social_intent": "welcome",
				"dialogue_hint": "先请对方坐下。",
				"source": "memoria",
				"position": [999, 999, 999],
				"inventory": {"coins": 999999},
				"world_time": {"day": 99, "minute": 0},
			}],
		},
		{"lin-xi": ["offer_tea", "close_shop"]},
	)

	assert_true(parsed["ok"])
	var decision: Dictionary = parsed["decisions"]["lin-xi"]
	assert_eq(decision["candidate_action_id"], "offer_tea")
	assert_eq(decision["dialogue_hint"], "先请对方坐下。")
	assert_false(decision.has("position"))
	assert_false(decision.has("inventory"))
	assert_false(decision.has("world_time"))


func test_decision_response_accepts_integral_tick_from_json_wire() -> void:
	var client = load(MEMORIA_CLIENT_PATH).new()
	add_child_autoqfree(client)
	var wire_response: Dictionary = JSON.parse_string(JSON.stringify({
		"request_id": "322dfb91-ddd1-4037-a16d-38fcd11a9de7",
		"tick_id": 510,
		"decisions": [{
			"character_id": "lin-xi",
			"candidate_action_id": "offer_tea",
			"source": "memoria",
		}],
	}))

	var parsed: Dictionary = client.validate_agent_decision_response(
		wire_response,
		{"lin-xi": ["offer_tea"]},
		"322dfb91-ddd1-4037-a16d-38fcd11a9de7",
		510,
	)

	assert_true(parsed["ok"])
	assert_eq(parsed["tick_id"], 510)
	assert_eq(typeof(parsed["tick_id"]), TYPE_INT)


func test_health_check_uses_a_separate_http_request() -> void:
	assert_true(ResourceLoader.exists(MEMORIA_CLIENT_PATH))
	assert_true(ResourceLoader.exists(PENDING_EVENT_QUEUE_PATH))
	if (
		not ResourceLoader.exists(MEMORIA_CLIENT_PATH)
		or not ResourceLoader.exists(PENDING_EVENT_QUEUE_PATH)
	):
		return

	var game_request := FakeHttpRequest.new()
	var health_request := FakeHttpRequest.new()
	var queue = load(PENDING_EVENT_QUEUE_PATH).new()
	var client = load(MEMORIA_CLIENT_PATH).new()
	client.configure(
		"http://127.0.0.1:8000/api/v1",
		"test-token",
		queue,
		game_request,
		health_request,
	)
	add_child_autoqfree(client)

	assert_eq(client.check_health(), OK)
	assert_eq(game_request.requests.size(), 0)
	assert_eq(health_request.requests.size(), 1)
	assert_eq(
		health_request.requests[0]["url"],
		"http://127.0.0.1:8000/api/v1/game/health",
	)
	assert_has(
		Array(health_request.requests[0]["headers"]),
		"Authorization: Bearer test-token",
	)


func test_board_task_response_accepts_withdrawn_and_strips_world_mutations() -> void:
	var client = load(MEMORIA_CLIENT_PATH).new()
	add_child_autoqfree(client)
	assert_true(client.has_method("validate_board_task_response"))
	if not client.has_method("validate_board_task_response"):
		return

	var parsed: Dictionary = client.validate_board_task_response(
		{
			"request_id": "1472a5a0-e99e-43a9-9792-408872c4e20b",
			"tick_id": 720,
			"task_id": "deliver-spring-tea",
			"responder_id": "lin-xi",
			"response": "withdrawn",
			"reason_code": "schedule_conflict",
			"dialogue_hint": "今晚来不及送到。",
			"source": "memoria",
			"fallback_reason": null,
			"inventory": {"tea": 999},
			"world_time": {"day": 99, "minute": 0},
		},
		["withdrawn"],
		"1472a5a0-e99e-43a9-9792-408872c4e20b",
		720,
		"deliver-spring-tea",
		"lin-xi",
	)

	assert_true(parsed["ok"])
	assert_eq(parsed["response"], "withdrawn")
	assert_eq(parsed["reason_code"], "schedule_conflict")
	assert_false(parsed.has("inventory"))
	assert_false(parsed.has("world_time"))


func test_board_task_response_posts_to_task_endpoint_and_emits_result() -> void:
	var game_request := FakeHttpRequest.new()
	var client = load(MEMORIA_CLIENT_PATH).new()
	client.configure(
		"http://127.0.0.1:8000/api/v1",
		"test-token",
		null,
		game_request,
		FakeHttpRequest.new(),
	)
	add_child_autoqfree(client)
	assert_true(client.has_method("request_board_task_response"))
	assert_true(client.has_signal("board_task_response_completed"))
	if (
		not client.has_method("request_board_task_response")
		or not client.has_signal("board_task_response_completed")
	):
		return

	var completed := []
	client.board_task_response_completed.connect(
		func(request_id: String, result: Dictionary) -> void:
			completed.append({
				"request_id": request_id,
				"result": result,
			}),
	)
	var payload := _board_task_payload()

	assert_eq(
		client.request_board_task_response(
			"deliver-spring-tea",
			payload,
		),
		OK,
	)
	assert_eq(game_request.requests.size(), 1)
	assert_eq(
		game_request.requests[0]["url"],
		"http://127.0.0.1:8000/api/v1/game/board-tasks/"
			+ "deliver-spring-tea/responses",
	)
	var parsed_payload: Dictionary = JSON.parse_string(
		game_request.requests[0]["body"],
	)
	assert_eq(parsed_payload["request_id"], payload["request_id"])
	assert_eq(int(parsed_payload["tick_id"]), payload["tick_id"])
	assert_eq(parsed_payload["world_id"], payload["world_id"])
	assert_eq(parsed_payload["save_id"], payload["save_id"])
	assert_eq(parsed_payload["responder_id"], payload["responder_id"])
	assert_eq(parsed_payload["task"]["task_id"], payload["task"]["task_id"])
	assert_eq(
		parsed_payload["allowed_responses"],
		payload["allowed_responses"],
	)

	var response_body := {
		"request_id": payload["request_id"],
		"tick_id": payload["tick_id"],
		"task_id": payload["task"]["task_id"],
		"responder_id": payload["responder_id"],
		"response": "withdrawn",
		"reason_code": "schedule_conflict",
		"dialogue_hint": "今晚来不及送到。",
		"source": "memoria",
		"fallback_reason": null,
	}
	game_request.request_completed.emit(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		JSON.stringify(response_body).to_utf8_buffer(),
	)
	await wait_process_frames(1)

	assert_eq(completed.size(), 1)
	assert_eq(completed[0]["request_id"], payload["request_id"])
	assert_true(completed[0]["result"]["ok"])
	assert_eq(completed[0]["result"]["response"], "withdrawn")
	assert_eq(client.connection_status, "connected")


func test_dialogue_turn_posts_profile_and_emits_sanitized_reply() -> void:
	var game_request := FakeHttpRequest.new()
	var client = load(MEMORIA_CLIENT_PATH).new()
	client.configure(
		"http://127.0.0.1:8000/api/v1",
		"test-token",
		null,
		game_request,
		FakeHttpRequest.new(),
		"tinglan-world-01",
		"slot-01",
	)
	add_child_autoqfree(client)
	var completed := []
	client.dialogue_turn_completed.connect(
		func(request_id: String, result: Dictionary) -> void:
			completed.append({
				"request_id": request_id,
				"result": result,
			}),
	)
	var payload := _dialogue_payload()

	assert_eq(client.request_dialogue_turn(payload), OK)
	assert_eq(game_request.requests.size(), 1)
	assert_eq(
		game_request.requests[0]["url"],
		"http://127.0.0.1:8000/api/v1/game/dialogue-turns",
	)
	var parsed_payload: Dictionary = JSON.parse_string(
		game_request.requests[0]["body"],
	)
	assert_eq(parsed_payload["world_id"], "tinglan-world-01")
	assert_eq(parsed_payload["save_id"], "slot-01")
	assert_eq(parsed_payload["character"]["character_id"], "lin-xi")
	assert_eq(parsed_payload["player_message"], "你好")

	game_request.request_completed.emit(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		JSON.stringify({
			"request_id": payload["request_id"],
			"tick_id": payload["tick_id"],
			"character_id": "lin-xi",
			"dialogue": "你好。今天想喝点什么？",
			"source": "memoria",
			"fallback_reason": null,
			"inventory": {"coins": 999},
		}).to_utf8_buffer(),
	)
	await wait_process_frames(1)

	assert_eq(completed.size(), 1)
	assert_eq(completed[0]["request_id"], payload["request_id"])
	assert_true(completed[0]["result"]["ok"])
	assert_eq(
		completed[0]["result"]["dialogue"],
		"你好。今天想喝点什么？",
	)
	assert_false(completed[0]["result"].has("inventory"))
	assert_eq(client.connection_status, "connected")


func _dialogue_payload() -> Dictionary:
	return {
		"request_id": "da08f8a7-1fc3-4d72-8e58-3d3d13f1951c",
		"tick_id": 730,
		"location_name": "临水茶馆",
		"character": {
			"character_id": "lin-xi",
			"name": "林汐",
			"age": 27,
			"role": "茶馆掌柜",
			"traits": ["温和", "好奇", "善调停"],
			"personal_request": {
				"type": "gather",
				"topic": "寻找适合春茶的新鲜嫩叶",
			},
		},
		"history": [{
			"speaker_id": "lin-xi",
			"speaker_name": "林汐",
			"text": "近来经过临水茶馆的人不少。",
		}],
		"player_message": "你好",
	}


func _board_task_payload() -> Dictionary:
	return {
		"request_id": "1472a5a0-e99e-43a9-9792-408872c4e20b",
		"tick_id": 720,
		"world_id": "tinglan-world-01",
		"save_id": "slot-01",
		"responder_id": "lin-xi",
		"task": {
			"task_id": "deliver-spring-tea",
			"task_source": "player",
			"task_type": "delivery",
			"issuer_id": "player",
			"objective": {"kind": "deliver", "item_id": "spring-tea"},
			"location_id": "teahouse",
			"deadline_tick": 900,
			"reward": {"currency": 20},
			"completion_rules": [{"kind": "delivered", "amount": 1}],
			"description": "打烊前把春茶送到茶馆。",
			"status": "assigned",
			"assignee_ids": ["lin-xi"],
		},
		"allowed_responses": ["withdrawn"],
	}
