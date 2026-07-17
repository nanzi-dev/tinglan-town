class_name ResidentActor
extends CharacterBody3D

var _character: Dictionary = {}


func configure(character: Dictionary, schedule: Dictionary) -> bool:
	var needs := get_node_or_null("NeedsComponent") as NeedsComponent
	var schedule_component := (
		get_node_or_null("ScheduleComponent") as ScheduleComponent
	)
	if needs == null or schedule_component == null:
		return false
	if not schedule_component.configure(character, schedule):
		return false

	_character = character.duplicate(true)
	set_meta("character_id", get_character_id())
	set_meta("display_name", get_display_name())
	return true


func set_location_targets(location_targets: Dictionary) -> void:
	var schedule := get_node_or_null("ScheduleComponent") as ScheduleComponent
	if schedule != null:
		schedule.set_location_targets(location_targets)


func advance_schedule(minute_of_day: int) -> Dictionary:
	var schedule := get_node_or_null("ScheduleComponent") as ScheduleComponent
	if schedule == null:
		return {}
	return schedule.advance_to(minute_of_day)


func advance_needs(minutes: int) -> void:
	var needs := get_node_or_null("NeedsComponent") as NeedsComponent
	if needs != null:
		needs.advance_minutes(minutes)


func get_character_id() -> String:
	return str(_character.get("character_id", ""))


func get_display_name() -> String:
	return str(_character.get("name", ""))


func get_schedule_state() -> Dictionary:
	var schedule := get_node_or_null("ScheduleComponent") as ScheduleComponent
	return {} if schedule == null else schedule.get_current_state()


func get_need_levels() -> Dictionary:
	var needs := get_node_or_null("NeedsComponent") as NeedsComponent
	return {} if needs == null else needs.get_levels()


func to_dict() -> Dictionary:
	var needs := get_node_or_null("NeedsComponent") as NeedsComponent
	if needs == null:
		return {}
	return {
		"character_id": get_character_id(),
		"needs": needs.to_dict(),
	}


func restore(data: Dictionary, minute_of_day: int) -> bool:
	var needs := get_node_or_null("NeedsComponent") as NeedsComponent
	if (
		needs == null
		or data.get("character_id", null) != get_character_id()
		or typeof(data.get("needs", null)) != TYPE_DICTIONARY
		or not needs.restore(data["needs"])
	):
		return false
	return not advance_schedule(minute_of_day).is_empty()
