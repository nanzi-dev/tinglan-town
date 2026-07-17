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
