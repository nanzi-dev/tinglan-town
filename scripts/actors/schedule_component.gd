class_name ScheduleComponent
extends Node

const MINUTES_PER_DAY := 1440

@export var actor_path := NodePath("..")
@export var navigation_agent_path := NodePath("../NavigationAgent3D")
@export var move_speed := 2.5

var _character := {}
var _schedule := {}
var _location_targets := {}
var _current_state := {}


func configure(character: Dictionary, schedule: Dictionary) -> bool:
	if not _is_valid_configuration(character, schedule):
		return false
	_character = character.duplicate(true)
	_schedule = schedule.duplicate(true)
	_current_state = state_at(0)
	return true


func state_at(minute_of_day: int) -> Dictionary:
	if _character.is_empty() or _schedule.is_empty():
		return {}
	var normalized_minute := posmod(minute_of_day, MINUTES_PER_DAY)
	for entry in _schedule["entries"]:
		if (
			normalized_minute >= entry["start_minute"]
			and normalized_minute < entry["end_minute"]
		):
			return {
				"location_id": entry["location_id"],
				"activity": entry["activity"],
			}
	return {
		"location_id": _character["home_location_id"],
		"activity": "sleep",
	}


func advance_to(minute_of_day: int) -> Dictionary:
	_current_state = state_at(minute_of_day)
	if _current_state.is_empty():
		return {}
	var location_id: String = _current_state["location_id"]
	if _location_targets.has(location_id):
		var navigation_agent := get_node_or_null(
			navigation_agent_path,
		) as NavigationAgent3D
		if navigation_agent != null:
			navigation_agent.target_position = _location_targets[location_id]
	return _current_state.duplicate(true)


func set_location_targets(location_targets: Dictionary) -> void:
	_location_targets = location_targets.duplicate(true)


func get_current_state() -> Dictionary:
	return _current_state.duplicate(true)


func get_character_id() -> String:
	return _character.get("character_id", "")


func _physics_process(_delta: float) -> void:
	if _current_state.is_empty():
		return
	var actor := get_node_or_null(actor_path) as CharacterBody3D
	var navigation_agent := get_node_or_null(
		navigation_agent_path,
	) as NavigationAgent3D
	if actor == null or navigation_agent == null:
		return
	if navigation_agent.is_navigation_finished():
		actor.velocity = Vector3.ZERO
		return
	var next_position := navigation_agent.get_next_path_position()
	var direction := actor.global_position.direction_to(next_position)
	direction.y = 0.0
	actor.velocity = (
		Vector3.ZERO
		if direction.is_zero_approx()
		else direction.normalized() * move_speed
	)
	actor.move_and_slide()


func _is_valid_configuration(
	character: Dictionary,
	schedule: Dictionary,
) -> bool:
	for field in [
		"character_id",
		"home_location_id",
		"work_location_id",
		"schedule_id",
	]:
		if (
			typeof(character.get(field, null)) != TYPE_STRING
			or character[field].is_empty()
		):
			return false
	for field in ["schedule_id", "character_id", "entries"]:
		if not schedule.has(field):
			return false
	if (
		schedule["schedule_id"] != character["schedule_id"]
		or schedule["character_id"] != character["character_id"]
		or typeof(schedule["entries"]) != TYPE_ARRAY
		or schedule["entries"].is_empty()
	):
		return false
	for entry in schedule["entries"]:
		if (
			typeof(entry) != TYPE_DICTIONARY
			or typeof(entry.get("start_minute", null)) != TYPE_INT
			or typeof(entry.get("end_minute", null)) != TYPE_INT
			or typeof(entry.get("location_id", null)) != TYPE_STRING
			or entry["location_id"].is_empty()
			or typeof(entry.get("activity", null)) != TYPE_STRING
			or entry["activity"].is_empty()
		):
			return false
	return true
