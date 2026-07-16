class_name DomainEventLog
extends RefCounted

var _event_ids := {}


func record_once(event_id: Variant, consumer_id: Variant = "default") -> bool:
	if (
		not _is_valid_id(event_id)
		or not _is_valid_id(consumer_id)
	):
		return false

	var consumer_events: Dictionary = _event_ids.get(consumer_id, {})
	if consumer_events.has(event_id):
		return false

	consumer_events[event_id] = true
	_event_ids[consumer_id] = consumer_events
	return true


func has_event(event_id: Variant, consumer_id: Variant = "default") -> bool:
	if not _is_valid_id(event_id) or not _is_valid_id(consumer_id):
		return false
	var consumer_events: Dictionary = _event_ids.get(consumer_id, {})
	return consumer_events.has(event_id)


func _is_valid_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()
