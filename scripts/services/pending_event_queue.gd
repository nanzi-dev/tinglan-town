class_name PendingEventQueue
extends RefCounted

const FILE_NAME := "pending_memoria_events.json"
const TEMP_FILE_NAME := "pending_memoria_events.json.tmp"
const FORMAT := "tinglan-memoria-pending-v1"
const MAX_VALUE_DEPTH := 64
const EVENT_TYPES := {
	"encounter": true,
	"promise": true,
	"task_accepted": true,
	"task_completed": true,
	"project_vote": true,
	"relationship_changed": true,
	"conversation_joined": true,
}

var load_error: Error = OK

var _save_directory: String
var _events: Array[Dictionary] = []


func _init(save_directory: String = "") -> void:
	_save_directory = save_directory
	load_error = _load()


func enqueue(event: Dictionary) -> Error:
	if not _is_valid_event(event):
		return ERR_INVALID_DATA

	for queued_event in _events:
		if queued_event["event_id"] != event["event_id"]:
			continue
		if queued_event == event:
			return OK
		return ERR_ALREADY_EXISTS

	var candidate := _events.duplicate(true)
	candidate.append(event.duplicate(true))
	var persist_error := _persist(candidate)
	if persist_error != OK:
		return persist_error
	_events = candidate
	return OK


func acknowledge(event_ids: Array) -> Error:
	var acknowledged := {}
	for event_id in event_ids:
		if (
			typeof(event_id) != TYPE_STRING
			or event_id.is_empty()
			or acknowledged.has(event_id)
		):
			return ERR_INVALID_DATA
		acknowledged[event_id] = true

	var candidate: Array[Dictionary] = []
	for event in _events:
		if not acknowledged.has(event["event_id"]):
			candidate.append(event.duplicate(true))
	if candidate.size() == _events.size():
		return OK

	var persist_error := _persist(candidate)
	if persist_error != OK:
		return persist_error
	_events = candidate
	return OK


func pending_events() -> Array[Dictionary]:
	return _events.duplicate(true)


func _load() -> Error:
	if _save_directory.is_empty():
		return OK

	var path := _save_directory.path_join(FILE_NAME)
	if not FileAccess.file_exists(path):
		return OK
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return read_error

	var decoded = JSON.parse_string(text)
	if (
		typeof(decoded) != TYPE_DICTIONARY
		or decoded.get("format", "") != FORMAT
		or typeof(decoded.get("payload", null)) != TYPE_DICTIONARY
	):
		return ERR_INVALID_DATA
	var decoded_events := _decode_value(decoded["payload"])
	if (
		not decoded_events["ok"]
		or typeof(decoded_events["value"]) != TYPE_ARRAY
	):
		return ERR_INVALID_DATA

	var loaded: Array[Dictionary] = []
	var seen_ids := {}
	for value in decoded_events["value"]:
		if (
			not _is_valid_event(value)
			or seen_ids.has(value["event_id"])
		):
			return ERR_INVALID_DATA
		seen_ids[value["event_id"]] = true
		loaded.append(value.duplicate(true))
	_events = loaded
	return OK


func _persist(events: Array[Dictionary]) -> Error:
	if _save_directory.is_empty():
		return OK
	var encoded_events := _encode_value(events)
	if not encoded_events["ok"]:
		return ERR_INVALID_DATA

	var absolute_directory := ProjectSettings.globalize_path(_save_directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		absolute_directory,
	)
	if directory_error != OK:
		return directory_error

	var path := _save_directory.path_join(FILE_NAME)
	var temporary_path := _save_directory.path_join(TEMP_FILE_NAME)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"format": FORMAT,
		"payload": encoded_events["value"],
	}))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(temporary_path),
		)
		return write_error

	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temporary_path := ProjectSettings.globalize_path(
		temporary_path,
	)
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			DirAccess.remove_absolute(absolute_temporary_path)
			return remove_error
	var promote_error := DirAccess.rename_absolute(
		absolute_temporary_path,
		absolute_path,
	)
	if promote_error != OK:
		DirAccess.remove_absolute(absolute_temporary_path)
	return promote_error


func _is_valid_event(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var event: Dictionary = value
	if (
		not _is_nonempty_string(event.get("event_id", null))
		or not _is_nonempty_string(event.get("request_id", null))
		or typeof(event.get("tick_id", null)) != TYPE_INT
		or event["tick_id"] < 0
		or not _is_nonempty_string(event.get("event_type", null))
		or not EVENT_TYPES.has(event["event_type"])
		or not _is_nonempty_string(event.get("source_action_id", null))
		or not _is_valid_participants(event.get("participants", null))
		or not _is_valid_world_time(event.get("world_time", null))
		or typeof(event.get("structured_result", null)) != TYPE_DICTIONARY
	):
		return false
	return _is_json_value(event, 0)


func _is_valid_participants(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return false
	for participant_id in value:
		if not _is_nonempty_string(participant_id):
			return false
	return true


func _is_valid_world_time(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	return (
		_is_nonempty_string(value.get("season", null))
		and typeof(value.get("day", null)) == TYPE_INT
		and value["day"] >= 1
		and typeof(value.get("minute", null)) == TYPE_INT
		and value["minute"] >= 0
		and value["minute"] < WorldClock.MINUTES_PER_DAY
	)


func _is_json_value(value: Variant, depth: int) -> bool:
	if depth > MAX_VALUE_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return not is_nan(value) and not is_inf(value)
		TYPE_ARRAY:
			for item in value:
				if not _is_json_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if (
					typeof(key) != TYPE_STRING
					or not _is_json_value(value[key], depth + 1)
				):
					return false
			return true
	return false


func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()


func _encode_value(value: Variant, depth: int = 0) -> Dictionary:
	if depth > MAX_VALUE_DEPTH:
		return _codec_failure()
	match typeof(value):
		TYPE_NIL:
			return _codec_success({"kind": "nil"})
		TYPE_BOOL:
			return _codec_success({"kind": "bool", "value": value})
		TYPE_INT:
			return _codec_success({"kind": "int64", "value": str(value)})
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return _codec_failure()
			return _codec_success({"kind": "float", "value": value})
		TYPE_STRING:
			return _codec_success({"kind": "string", "value": value})
		TYPE_ARRAY:
			var items := []
			for item in value:
				var encoded_item := _encode_value(item, depth + 1)
				if not encoded_item["ok"]:
					return _codec_failure()
				items.append(encoded_item["value"])
			return _codec_success({"kind": "array", "items": items})
		TYPE_DICTIONARY:
			var entries := []
			for key in value:
				if typeof(key) != TYPE_STRING:
					return _codec_failure()
				var encoded_value := _encode_value(value[key], depth + 1)
				if not encoded_value["ok"]:
					return _codec_failure()
				entries.append({
					"key": key,
					"value": encoded_value["value"],
				})
			return _codec_success({
				"kind": "dictionary",
				"entries": entries,
			})
	return _codec_failure()


func _decode_value(node: Dictionary, depth: int = 0) -> Dictionary:
	if depth > MAX_VALUE_DEPTH:
		return _codec_failure()
	var kind = node.get("kind", null)
	if typeof(kind) != TYPE_STRING:
		return _codec_failure()
	match kind:
		"nil":
			return _codec_success(null)
		"bool":
			if typeof(node.get("value", null)) == TYPE_BOOL:
				return _codec_success(node["value"])
		"int64":
			var text = node.get("value", null)
			if typeof(text) == TYPE_STRING and text.is_valid_int():
				var parsed: int = text.to_int()
				if str(parsed) == text:
					return _codec_success(parsed)
		"float":
			var number = node.get("value", null)
			if (
				typeof(number) == TYPE_FLOAT
				and not is_nan(number)
				and not is_inf(number)
			):
				return _codec_success(number)
		"string":
			if typeof(node.get("value", null)) == TYPE_STRING:
				return _codec_success(node["value"])
		"array":
			if typeof(node.get("items", null)) != TYPE_ARRAY:
				return _codec_failure()
			var decoded_items := []
			for item in node["items"]:
				if typeof(item) != TYPE_DICTIONARY:
					return _codec_failure()
				var decoded_item := _decode_value(item, depth + 1)
				if not decoded_item["ok"]:
					return _codec_failure()
				decoded_items.append(decoded_item["value"])
			return _codec_success(decoded_items)
		"dictionary":
			if typeof(node.get("entries", null)) != TYPE_ARRAY:
				return _codec_failure()
			var decoded_dictionary := {}
			for entry in node["entries"]:
				if (
					typeof(entry) != TYPE_DICTIONARY
					or not _is_nonempty_string(entry.get("key", null))
					or typeof(entry.get("value", null)) != TYPE_DICTIONARY
					or decoded_dictionary.has(entry["key"])
				):
					return _codec_failure()
				var decoded_entry := _decode_value(
					entry["value"],
					depth + 1,
				)
				if not decoded_entry["ok"]:
					return _codec_failure()
				decoded_dictionary[entry["key"]] = decoded_entry["value"]
			return _codec_success(decoded_dictionary)
	return _codec_failure()


func _codec_success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value}


func _codec_failure() -> Dictionary:
	return {"ok": false, "value": null}
