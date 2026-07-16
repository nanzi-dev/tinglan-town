class_name SaveCoordinator
extends RefCounted

const MAX_CATCHUP_DAYS := 3
const CHECKPOINT_FILE_NAME := "checkpoint.json"
const CHECKPOINT_TEMP_FILE_NAME := "checkpoint.json.tmp"
const CHECKPOINT_BACKUP_FILE_NAME := "checkpoint.json.bak"
const CHECKPOINT_FORMAT := "tinglan-checkpoint-v1"
const EVENT_LOG_FILE_NAME := "events.jsonl"
const EVENT_FORMAT := "tinglan-event-v1"
const INT64_MAX := 0x7fffffffffffffff

var _save_directory: String


func _init(save_directory: String = "") -> void:
	_save_directory = save_directory


func calculate_catchup(from_tick: int, elapsed_real_seconds: int) -> Dictionary:
	if from_tick < 0 or elapsed_real_seconds < 0:
		return {}
	var maximum_minutes := MAX_CATCHUP_DAYS * WorldClock.MINUTES_PER_DAY
	var elapsed_minutes := mini(elapsed_real_seconds, maximum_minutes)
	elapsed_minutes = mini(elapsed_minutes, INT64_MAX - from_tick)
	@warning_ignore("integer_division")
	var capped_days := elapsed_minutes / WorldClock.MINUTES_PER_DAY
	return {
		"from_tick": from_tick,
		"capped_days": capped_days,
		"to_tick": from_tick + elapsed_minutes,
		"key_events": [],
		"task_changes": [],
		"relationship_changes": [],
		"town_digest": "听澜镇在你离开期间平稳运行了%d游戏分钟。" % elapsed_minutes,
	}


func save_checkpoint(
	world_state: Dictionary,
	last_event_sequence: int,
	processed_event_ids: Array,
) -> Error:
	if (
		last_event_sequence < -1
		or not _is_valid_processed_event_ids(processed_event_ids)
	):
		return ERR_INVALID_DATA

	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_save_directory),
	)
	if directory_error != OK:
		return directory_error

	var checkpoint := {
		"world_state": world_state,
		"last_event_sequence": last_event_sequence,
		"processed_event_ids": processed_event_ids,
	}
	var encoded_checkpoint := _encode_value(checkpoint)
	if not encoded_checkpoint["ok"]:
		return ERR_INVALID_DATA
	var encoded := {
		"format": CHECKPOINT_FORMAT,
		"payload": encoded_checkpoint["value"],
	}
	var checkpoint_path := _save_directory.path_join(CHECKPOINT_FILE_NAME)
	var temporary_path := _save_directory.path_join(CHECKPOINT_TEMP_FILE_NAME)
	var backup_path := _save_directory.path_join(CHECKPOINT_BACKUP_FILE_NAME)
	var file := FileAccess.open(
		temporary_path,
		FileAccess.WRITE,
	)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(encoded))
	file.flush()
	file.close()
	var write_error := file.get_error()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return write_error

	var absolute_checkpoint_path := ProjectSettings.globalize_path(checkpoint_path)
	var absolute_temporary_path := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup_path := ProjectSettings.globalize_path(backup_path)
	var had_checkpoint := FileAccess.file_exists(checkpoint_path)
	var had_backup := FileAccess.file_exists(backup_path)
	if DirAccess.dir_exists_absolute(absolute_backup_path):
		DirAccess.remove_absolute(absolute_temporary_path)
		return ERR_ALREADY_EXISTS
	if had_backup:
		if had_checkpoint or not _read_checkpoint(backup_path)["ok"]:
			DirAccess.remove_absolute(absolute_temporary_path)
			return ERR_ALREADY_EXISTS

	if had_checkpoint:
		var backup_error := DirAccess.rename_absolute(
			absolute_checkpoint_path,
			absolute_backup_path,
		)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary_path)
			return backup_error

	var promote_error := DirAccess.rename_absolute(
		absolute_temporary_path,
		absolute_checkpoint_path,
	)
	if promote_error != OK:
		if had_checkpoint:
			DirAccess.rename_absolute(
				absolute_backup_path,
				absolute_checkpoint_path,
			)
		DirAccess.remove_absolute(absolute_temporary_path)
		return promote_error

	if had_checkpoint or had_backup:
		var cleanup_error := DirAccess.remove_absolute(absolute_backup_path)
		if cleanup_error != OK:
			return cleanup_error
	return write_error


func append_event(event: Dictionary) -> Error:
	if not _is_valid_event(event):
		return ERR_INVALID_DATA
	var encoded_event := _encode_value(event)
	if not encoded_event["ok"]:
		return ERR_INVALID_DATA

	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_save_directory),
	)
	if directory_error != OK:
		return directory_error

	var event_path := _save_directory.path_join(EVENT_LOG_FILE_NAME)
	var mode := (
		FileAccess.READ_WRITE
		if FileAccess.file_exists(event_path)
		else FileAccess.WRITE_READ
	)
	var file := FileAccess.open(event_path, mode)
	if file == null:
		return FileAccess.get_open_error()

	var needs_separator := false
	if mode == FileAccess.READ_WRITE:
		var existing_text := file.get_as_text()
		var read_error := file.get_error()
		if read_error != OK:
			file.close()
			return read_error
		if not _parse_event_log_text(existing_text)["ok"]:
			file.close()
			return ERR_INVALID_DATA
		needs_separator = (
			not existing_text.is_empty()
			and not existing_text.ends_with("\n")
		)

	file.seek_end()
	if needs_separator:
		file.store_string("\n")
	file.store_line(JSON.stringify({
		"format": EVENT_FORMAT,
		"payload": encoded_event["value"],
	}))
	file.flush()
	file.close()
	return file.get_error()


func recover(event_projector: Callable = Callable()) -> Dictionary:
	var checkpoint := _recover_checkpoint()
	if not checkpoint["ok"]:
		return checkpoint

	var replay_read := _read_replay_events(checkpoint["last_event_sequence"])
	if not replay_read["ok"]:
		return _failed_replay(checkpoint)
	var events: Array = replay_read["events"]
	var world_state: Dictionary = checkpoint["world_state"].duplicate(true)
	var processed_event_ids: Array = checkpoint["processed_event_ids"].duplicate()
	var processed_lookup := {}
	for event_id in processed_event_ids:
		processed_lookup[event_id] = true
	var last_event_sequence: int = checkpoint["last_event_sequence"]

	for event in events:
		var sequence: int = event["sequence"]
		var event_id: String = event["event_id"]
		if processed_lookup.has(event_id):
			last_event_sequence = maxi(last_event_sequence, sequence)
			continue

		if not event_projector.is_valid():
			return _failed_replay(checkpoint)
		var candidate_state := world_state.duplicate(true)
		var applied = event_projector.call(candidate_state, event.duplicate(true))
		if typeof(applied) != TYPE_BOOL or not applied:
			return _failed_replay(checkpoint)

		world_state = candidate_state
		processed_lookup[event_id] = true
		processed_event_ids.append(event_id)
		last_event_sequence = maxi(last_event_sequence, sequence)

	return {
		"ok": true,
		"world_state": world_state,
		"last_event_sequence": last_event_sequence,
		"processed_event_ids": processed_event_ids,
	}


func _recover_checkpoint() -> Dictionary:
	for file_name in [CHECKPOINT_FILE_NAME, CHECKPOINT_BACKUP_FILE_NAME]:
		var checkpoint_path := _save_directory.path_join(file_name)
		if not FileAccess.file_exists(checkpoint_path):
			continue
		var recovered := _read_checkpoint(checkpoint_path)
		if recovered["ok"]:
			return recovered
	return _failed_recovery()


func _read_replay_events(after_sequence: int) -> Dictionary:
	var event_path := _save_directory.path_join(EVENT_LOG_FILE_NAME)
	if not FileAccess.file_exists(event_path):
		return {"ok": true, "events": []}

	var file := FileAccess.open(event_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "events": []}
	var event_text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return {"ok": false, "events": []}

	var parsed_log := _parse_event_log_text(event_text)
	if not parsed_log["ok"]:
		return {"ok": false, "events": []}
	var events := []
	for event in parsed_log["events"]:
		if event["sequence"] > after_sequence:
			events.append(event)

	events.sort_custom(_event_less_than)
	return {"ok": true, "events": events}


func _parse_event_log_text(event_text: String) -> Dictionary:
	if event_text.is_empty():
		return {"ok": true, "events": []}
	var lines := event_text.split("\n", true)
	if lines[-1].is_empty():
		lines.remove_at(lines.size() - 1)

	var events := []
	for line in lines:
		if line.is_empty():
			return {"ok": false, "events": []}
		var parser := JSON.new()
		if parser.parse(line) != OK:
			return {"ok": false, "events": []}
		var parsed = parser.data
		if (
			typeof(parsed) != TYPE_DICTIONARY
			or parsed.get("format", "") != EVENT_FORMAT
			or typeof(parsed.get("payload", null)) != TYPE_DICTIONARY
		):
			return {"ok": false, "events": []}
		var decoded := _decode_value(parsed["payload"])
		if not decoded["ok"] or not _is_valid_event(decoded["value"]):
			return {"ok": false, "events": []}
		events.append(decoded["value"])
	return {"ok": true, "events": events}


func _event_less_than(first: Dictionary, second: Dictionary) -> bool:
	if first["sequence"] != second["sequence"]:
		return first["sequence"] < second["sequence"]
	return first["event_id"] < second["event_id"]


func _is_valid_event(event: Variant) -> bool:
	return (
		typeof(event) == TYPE_DICTIONARY
		and typeof(event.get("sequence", null)) == TYPE_INT
		and event["sequence"] >= 0
		and typeof(event.get("event_id", null)) == TYPE_STRING
		and not event["event_id"].is_empty()
	)


func _read_checkpoint(checkpoint_path: String) -> Dictionary:
	var file := FileAccess.open(checkpoint_path, FileAccess.READ)
	if file == null:
		return _failed_recovery()

	var checkpoint_text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return _failed_recovery()

	var parsed = JSON.parse_string(checkpoint_text)
	if (
		typeof(parsed) != TYPE_DICTIONARY
		or parsed.get("format", "") != CHECKPOINT_FORMAT
		or typeof(parsed.get("payload", null)) != TYPE_DICTIONARY
	):
		return _failed_recovery()

	var decoded := _decode_value(parsed["payload"])
	if not decoded["ok"] or typeof(decoded["value"]) != TYPE_DICTIONARY:
		return _failed_recovery()

	var checkpoint: Dictionary = decoded["value"]
	if (
		typeof(checkpoint.get("world_state", null)) != TYPE_DICTIONARY
		or typeof(checkpoint.get("last_event_sequence", null)) != TYPE_INT
		or checkpoint["last_event_sequence"] < -1
		or not _is_valid_processed_event_ids(
			checkpoint.get("processed_event_ids", null),
		)
	):
		return _failed_recovery()

	return {
		"ok": true,
		"world_state": checkpoint["world_state"],
		"last_event_sequence": checkpoint["last_event_sequence"],
		"processed_event_ids": checkpoint["processed_event_ids"],
	}


func _is_valid_processed_event_ids(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var seen_ids := {}
	for event_id in value:
		if (
			typeof(event_id) != TYPE_STRING
			or event_id.is_empty()
			or seen_ids.has(event_id)
		):
			return false
		seen_ids[event_id] = true
	return true


const MAX_CODEC_DEPTH := 64


func _encode_value(value: Variant, depth: int = 0) -> Dictionary:
	if depth > MAX_CODEC_DEPTH:
		return _encode_failure()
	match typeof(value):
		TYPE_NIL:
			return _encode_success({"kind": "nil"})
		TYPE_BOOL:
			return _encode_success({"kind": "bool", "value": value})
		TYPE_INT:
			return _encode_success({"kind": "int64", "value": str(value)})
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return _encode_failure()
			return _encode_success({"kind": "float", "value": value})
		TYPE_STRING:
			return _encode_success({"kind": "string", "value": value})
		TYPE_ARRAY:
			var items := []
			for item in value:
				var encoded_item := _encode_value(item, depth + 1)
				if not encoded_item["ok"]:
					return _encode_failure()
				items.append(encoded_item["value"])
			return _encode_success({"kind": "array", "items": items})
		TYPE_DICTIONARY:
			var entries := []
			for key in value:
				var encoded_key := _encode_value(key, depth + 1)
				var encoded_entry_value := _encode_value(value[key], depth + 1)
				if not encoded_key["ok"] or not encoded_entry_value["ok"]:
					return _encode_failure()
				entries.append({
					"key": encoded_key["value"],
					"value": encoded_entry_value["value"],
				})
			return _encode_success({"kind": "dictionary", "entries": entries})
	return _encode_failure()


func _encode_success(value: Dictionary) -> Dictionary:
	return {"ok": true, "value": value}


func _encode_failure() -> Dictionary:
	return {"ok": false, "value": {}}


func _decode_value(node: Dictionary, depth: int = 0) -> Dictionary:
	if depth > MAX_CODEC_DEPTH:
		return _decode_failure()
	var kind = node.get("kind", null)
	if typeof(kind) != TYPE_STRING:
		return _decode_failure()

	match kind:
		"nil":
			return _decode_success(null)
		"bool":
			if typeof(node.get("value", null)) == TYPE_BOOL:
				return _decode_success(node["value"])
		"int64":
			var text = node.get("value", null)
			if typeof(text) == TYPE_STRING and text.is_valid_int():
				var parsed_integer: int = text.to_int()
				if str(parsed_integer) == text:
					return _decode_success(parsed_integer)
		"float":
			var number = node.get("value", null)
			if (
				typeof(number) == TYPE_FLOAT
				and not is_nan(number)
				and not is_inf(number)
			):
				return _decode_success(number)
		"string":
			if typeof(node.get("value", null)) == TYPE_STRING:
				return _decode_success(node["value"])
		"array":
			if typeof(node.get("items", null)) != TYPE_ARRAY:
				return _decode_failure()
			var decoded_items := []
			for item in node["items"]:
				if typeof(item) != TYPE_DICTIONARY:
					return _decode_failure()
				var decoded_item := _decode_value(item, depth + 1)
				if not decoded_item["ok"]:
					return _decode_failure()
				decoded_items.append(decoded_item["value"])
			return _decode_success(decoded_items)
		"dictionary":
			if typeof(node.get("entries", null)) != TYPE_ARRAY:
				return _decode_failure()
			var decoded_dictionary := {}
			for entry in node["entries"]:
				if (
					typeof(entry) != TYPE_DICTIONARY
					or typeof(entry.get("key", null)) != TYPE_DICTIONARY
					or typeof(entry.get("value", null)) != TYPE_DICTIONARY
				):
					return _decode_failure()
				var decoded_key := _decode_value(entry["key"], depth + 1)
				var decoded_entry_value := _decode_value(
					entry["value"],
					depth + 1,
				)
				if not decoded_key["ok"] or not decoded_entry_value["ok"]:
					return _decode_failure()
				decoded_dictionary[decoded_key["value"]] = decoded_entry_value["value"]
			return _decode_success(decoded_dictionary)
	return _decode_failure()


func _decode_success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value}


func _decode_failure() -> Dictionary:
	return {"ok": false, "value": null}


func _failed_recovery() -> Dictionary:
	return {
		"ok": false,
		"world_state": {},
		"last_event_sequence": -1,
		"processed_event_ids": [],
	}


func _failed_replay(checkpoint: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"world_state": checkpoint["world_state"].duplicate(true),
		"last_event_sequence": checkpoint["last_event_sequence"],
		"processed_event_ids": checkpoint["processed_event_ids"].duplicate(),
	}
