class_name MemoriaClient
extends Node

signal connection_status_changed(status: String)
signal health_checked(status: String)
signal decision_batch_completed(request_id: String, result: Dictionary)
signal events_synchronized(event_ids: Array[String])

const RETRY_DELAYS := [0.5, 1.0, 2.0, 4.0]
const MAX_RETRY_ATTEMPTS := 4
const REQUEST_TIMEOUT_SECONDS := 3.0
const DEFAULT_BASE_URL := "http://127.0.0.1:8000/api/v1"
const DECISION_ENDPOINT := "/game/agent-decisions:batch"
const EVENT_ENDPOINT := "/game/social-events:batch"
const HEALTH_ENDPOINT := "/game/health"
const DECISION_FIELDS := [
	"character_id",
	"candidate_action_id",
	"social_intent",
	"target_character_id",
	"target_task_id",
	"reason_code",
	"dialogue_hint",
	"source",
	"fallback_reason",
]
const OPTIONAL_DECISION_FIELDS := [
	"social_intent",
	"target_character_id",
	"target_task_id",
	"reason_code",
	"dialogue_hint",
	"fallback_reason",
]

var retry_delays: Array[float] = [0.5, 1.0, 2.0, 4.0]
var connection_status := "local_mode"

var _base_url := ""
var _access_token := ""
var _world_id := ""
var _save_id := ""
var _pending_event_queue: RefCounted
var _game_request: Node
var _health_request: Node
var _active_operation: Dictionary = {}
var _queued_operations: Array[Dictionary] = []
var _health_in_flight := false
var _retry_generation := 0


func configure(
	base_url: String,
	access_token: String,
	pending_event_queue: RefCounted,
	game_request: Node = null,
	health_request: Node = null,
	world_id: String = "",
	save_id: String = "",
) -> void:
	_base_url = base_url.strip_edges().trim_suffix("/")
	_access_token = access_token.strip_edges()
	_pending_event_queue = pending_event_queue
	_game_request = game_request
	_health_request = health_request
	_world_id = world_id
	_save_id = save_id
	if is_inside_tree():
		_ensure_request_nodes()


func _ready() -> void:
	if _base_url.is_empty():
		_base_url = str(ProjectSettings.get_setting(
			"memoria/base_url",
			DEFAULT_BASE_URL,
		)).strip_edges().trim_suffix("/")
	if _access_token.is_empty():
		_access_token = OS.get_environment("MEMORIA_ACCESS_TOKEN").strip_edges()
	_ensure_request_nodes()


func request_agent_decisions(
	payload: Dictionary,
	legal_candidates_by_character: Dictionary,
) -> Error:
	if not _is_request_envelope(payload):
		return ERR_INVALID_DATA
	return _enqueue_operation({
		"kind": "decisions",
		"endpoint": DECISION_ENDPOINT,
		"method": HTTPClient.METHOD_POST,
		"payload": payload.duplicate(true),
		"legal_candidates": legal_candidates_by_character.duplicate(true),
		"retry_count": 0,
	})


func enqueue_social_event(event: Dictionary) -> Error:
	if _pending_event_queue == null:
		return ERR_UNCONFIGURED
	return _pending_event_queue.enqueue(event)


func flush_pending_events() -> Error:
	if _pending_event_queue == null:
		return ERR_UNCONFIGURED
	if not _active_operation.is_empty():
		return ERR_BUSY

	var pending: Array = _pending_event_queue.pending_events()
	if pending.is_empty():
		return OK
	var first: Dictionary = pending[0]
	var request_id = first.get("request_id", "")
	var tick_id = first.get("tick_id", -1)
	if (
		typeof(request_id) != TYPE_STRING
		or request_id.is_empty()
		or typeof(tick_id) != TYPE_INT
		or tick_id < 0
		or _world_id.is_empty()
		or _save_id.is_empty()
	):
		return ERR_INVALID_DATA

	var events := []
	var event_ids: Array[String] = []
	for event_value in pending:
		var event: Dictionary = event_value
		if (
			event.get("request_id", "") != request_id
			or event.get("tick_id", -1) != tick_id
		):
			continue
		events.append(event.duplicate(true))
		event_ids.append(event["event_id"])

	return _enqueue_operation({
		"kind": "events",
		"endpoint": EVENT_ENDPOINT,
		"method": HTTPClient.METHOD_POST,
		"payload": {
			"request_id": request_id,
			"tick_id": tick_id,
			"world_id": _world_id,
			"save_id": _save_id,
			"events": events,
		},
		"event_ids": event_ids,
		"retry_count": 0,
	})


func check_health() -> Error:
	_ensure_request_nodes()
	if _health_request == null:
		return ERR_UNCONFIGURED
	if _health_in_flight:
		return ERR_BUSY
	_health_in_flight = true
	var error: Error = _health_request.request(
		_base_url + HEALTH_ENDPOINT,
		_request_headers(),
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		_health_in_flight = false
		_set_connection_status("recoverable_error")
		health_checked.emit("recoverable_error")
	return error


func validate_agent_decision_response(
	response: Variant,
	legal_candidates_by_character: Dictionary,
	expected_request_id: String = "",
	expected_tick_id: int = -1,
) -> Dictionary:
	if typeof(response) != TYPE_DICTIONARY:
		return _protocol_failure()
	var request_id = response.get("request_id", null)
	var tick_id = response.get("tick_id", null)
	var decisions_value = response.get("decisions", null)
	if (
		not _is_nonempty_string(request_id)
		or typeof(tick_id) != TYPE_INT
		or tick_id < 0
		or typeof(decisions_value) != TYPE_ARRAY
		or (
			not expected_request_id.is_empty()
			and request_id != expected_request_id
		)
		or (expected_tick_id >= 0 and tick_id != expected_tick_id)
	):
		return _protocol_failure()

	var sanitized_decisions := {}
	for decision_value in decisions_value:
		if typeof(decision_value) != TYPE_DICTIONARY:
			return _protocol_failure()
		var decision: Dictionary = decision_value
		var character_id = decision.get("character_id", null)
		var candidate_action_id = decision.get("candidate_action_id", null)
		if (
			not _is_nonempty_string(character_id)
			or not _is_nonempty_string(candidate_action_id)
			or sanitized_decisions.has(character_id)
			or not legal_candidates_by_character.has(character_id)
			or not _legal_candidate_ids(
				legal_candidates_by_character[character_id],
			).has(candidate_action_id)
			or not _valid_optional_decision_fields(decision)
		):
			return _protocol_failure()

		var sanitized := {}
		for field in DECISION_FIELDS:
			if decision.has(field):
				sanitized[field] = decision[field]
		sanitized_decisions[character_id] = sanitized

	if sanitized_decisions.size() != legal_candidates_by_character.size():
		return _protocol_failure()
	_set_connection_status("connected")
	return {
		"ok": true,
		"request_id": request_id,
		"tick_id": tick_id,
		"decisions": sanitized_decisions,
	}


func _ensure_request_nodes() -> void:
	if _game_request == null:
		var request := HTTPRequest.new()
		request.timeout = REQUEST_TIMEOUT_SECONDS
		_game_request = request
	if _health_request == null:
		var request := HTTPRequest.new()
		request.timeout = REQUEST_TIMEOUT_SECONDS
		_health_request = request

	if _game_request.get_parent() == null:
		add_child(_game_request)
	if _health_request.get_parent() == null:
		add_child(_health_request)
	if not _game_request.request_completed.is_connected(
		_on_game_request_completed,
	):
		_game_request.request_completed.connect(_on_game_request_completed)
	if not _health_request.request_completed.is_connected(
		_on_health_request_completed,
	):
		_health_request.request_completed.connect(_on_health_request_completed)


func _enqueue_operation(operation: Dictionary) -> Error:
	_ensure_request_nodes()
	if _game_request == null:
		return ERR_UNCONFIGURED
	if not _active_operation.is_empty():
		_queued_operations.append(operation)
		return OK
	_active_operation = operation
	return _dispatch_active_operation()


func _dispatch_active_operation() -> Error:
	if _active_operation.is_empty():
		return ERR_DOES_NOT_EXIST
	_set_connection_status("connecting")
	var error: Error = _game_request.request(
		_base_url + _active_operation["endpoint"],
		_request_headers(),
		_active_operation["method"],
		JSON.stringify(_active_operation["payload"]),
	)
	if error != OK:
		_handle_transport_failure()
	return error


func _on_game_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if _active_operation.is_empty():
		return
	if (
		result != HTTPRequest.RESULT_SUCCESS
		or response_code < 200
		or response_code >= 300
	):
		_handle_transport_failure()
		return

	var response = JSON.parse_string(body.get_string_from_utf8())
	if typeof(response) != TYPE_DICTIONARY:
		_complete_protocol_failure()
		return

	match _active_operation["kind"]:
		"decisions":
			_complete_decision_operation(response)
		"events":
			_complete_event_operation(response)
		_:
			_complete_protocol_failure()


func _complete_decision_operation(response: Dictionary) -> void:
	var payload: Dictionary = _active_operation["payload"]
	var result := validate_agent_decision_response(
		response,
		_active_operation["legal_candidates"],
		payload["request_id"],
		payload["tick_id"],
	)
	decision_batch_completed.emit(payload["request_id"], result)
	_finish_active_operation()


func _complete_event_operation(response: Dictionary) -> void:
	var payload: Dictionary = _active_operation["payload"]
	var sent_event_ids: Array = _active_operation["event_ids"]
	var result_values = response.get("results", null)
	if (
		response.get("request_id", null) != payload["request_id"]
		or response.get("tick_id", null) != payload["tick_id"]
		or typeof(result_values) != TYPE_ARRAY
		or result_values.is_empty()
	):
		_complete_protocol_failure()
		return

	var acknowledged: Array[String] = []
	for result_value in result_values:
		if typeof(result_value) != TYPE_DICTIONARY:
			_complete_protocol_failure()
			return
		var event_id = result_value.get("event_id", null)
		if (
			not _is_nonempty_string(event_id)
			or not sent_event_ids.has(event_id)
			or acknowledged.has(event_id)
			or typeof(result_value.get("duplicate", null)) != TYPE_BOOL
			or typeof(result_value.get("projection", null)) != TYPE_DICTIONARY
		):
			_complete_protocol_failure()
			return
		acknowledged.append(event_id)

	var acknowledge_error: Error = _pending_event_queue.acknowledge(
		acknowledged,
	)
	if acknowledge_error != OK:
		_set_connection_status("recoverable_error")
		_finish_active_operation()
		return
	_set_connection_status("connected")
	events_synchronized.emit(acknowledged)
	_finish_active_operation()


func _complete_protocol_failure() -> void:
	var operation := _active_operation
	_set_connection_status("protocol_error")
	if operation.get("kind", "") == "decisions":
		decision_batch_completed.emit(
			operation["payload"]["request_id"],
			{
				"ok": false,
				"request_id": "",
				"tick_id": -1,
				"decisions": {},
			},
		)
	_finish_active_operation()


func _handle_transport_failure() -> void:
	if _active_operation.is_empty():
		return
	_set_connection_status("recoverable_error")
	var retry_count := int(_active_operation.get("retry_count", 0))
	if (
		retry_count >= MAX_RETRY_ATTEMPTS
		or retry_count >= retry_delays.size()
	):
		var operation := _active_operation
		if operation.get("kind", "") == "decisions":
			decision_batch_completed.emit(
				operation["payload"]["request_id"],
				{
					"ok": false,
					"request_id": "",
					"tick_id": -1,
					"decisions": {},
				},
			)
		_finish_active_operation()
		return

	var delay := retry_delays[retry_count]
	_active_operation["retry_count"] = retry_count + 1
	_retry_generation += 1
	_retry_after(delay, _retry_generation)


func _retry_after(delay: float, generation: int) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	else:
		await get_tree().process_frame
	if (
		generation == _retry_generation
		and not _active_operation.is_empty()
	):
		_dispatch_active_operation()


func _finish_active_operation() -> void:
	_retry_generation += 1
	_active_operation = {}
	if _queued_operations.is_empty():
		return
	_active_operation = _queued_operations.pop_front()
	_dispatch_active_operation()


func _on_health_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	_health_in_flight = false
	if (
		result != HTTPRequest.RESULT_SUCCESS
		or response_code < 200
		or response_code >= 300
	):
		_set_connection_status("recoverable_error")
		health_checked.emit("recoverable_error")
		return
	var response = JSON.parse_string(body.get_string_from_utf8())
	if (
		typeof(response) != TYPE_DICTIONARY
		or response.get("status", "") != "ok"
		or response.get("api_version", "") != "v1"
	):
		_set_connection_status("protocol_error")
		health_checked.emit("protocol_error")
		return
	_set_connection_status("connected")
	health_checked.emit("connected")


func _request_headers() -> PackedStringArray:
	var headers := PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
	])
	if not _access_token.is_empty():
		headers.append("Authorization: Bearer %s" % _access_token)
	return headers


func _is_request_envelope(payload: Dictionary) -> bool:
	return (
		_is_nonempty_string(payload.get("request_id", null))
		and typeof(payload.get("tick_id", null)) == TYPE_INT
		and payload["tick_id"] >= 0
		and _is_nonempty_string(payload.get("world_id", null))
		and _is_nonempty_string(payload.get("save_id", null))
	)


func _legal_candidate_ids(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for candidate in value:
		if _is_nonempty_string(candidate):
			result.append(candidate)
		elif (
			typeof(candidate) == TYPE_DICTIONARY
			and _is_nonempty_string(
				candidate.get("candidate_action_id", null),
			)
		):
			result.append(candidate["candidate_action_id"])
	return result


func _valid_optional_decision_fields(decision: Dictionary) -> bool:
	for field in OPTIONAL_DECISION_FIELDS:
		if not decision.has(field) or decision[field] == null:
			continue
		if not _is_nonempty_string(decision[field]):
			return false
	if decision.has("source") and not (
		decision["source"] == "memoria"
		or decision["source"] == "local_fallback"
	):
		return false
	return true


func _protocol_failure() -> Dictionary:
	_set_connection_status("protocol_error")
	return {
		"ok": false,
		"request_id": "",
		"tick_id": -1,
		"decisions": {},
	}


func _set_connection_status(status: String) -> void:
	if connection_status == status:
		return
	connection_status = status
	connection_status_changed.emit(status)


func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()
