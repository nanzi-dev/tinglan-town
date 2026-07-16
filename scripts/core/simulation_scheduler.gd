class_name SimulationScheduler
extends RefCounted

const LOGIC_TICK_MINUTES := 10
const OFFSCREEN_TICK_MINUTES := 30
const MINUTES_PER_DAY := 1440
const SOCIAL_SLOTS_PER_DAY := MINUTES_PER_DAY / LOGIC_TICK_MINUTES
const MIN_SOCIAL_BATCHES_PER_DAY := 30
const MAX_SOCIAL_BATCHES_PER_DAY := 60
const INT64_MAX := 0x7fffffffffffffff
const UINT32_MAX := 0xffffffff

var social_batches_today: int = 0

var _rng: DeterministicRng
var _current_day_index: int = -1
var _daily_social_budget: int = 0
var _last_world_minute: int = -1
var _offscreen_ticks_this_logic := {}


func _init(seed_or_rng: Variant) -> void:
	if seed_or_rng is DeterministicRng:
		_rng = seed_or_rng
	else:
		var seed: int = seed_or_rng if typeof(seed_or_rng) == TYPE_INT else 0
		_rng = DeterministicRng.new(seed)


func advance_logic_tick(world_minute: Variant, offscreen_agent_ids: Variant) -> void:
	if typeof(world_minute) != TYPE_INT:
		return

	var minute: int = world_minute
	if (
		minute < 0
		or minute % LOGIC_TICK_MINUTES != 0
		or minute <= _last_world_minute
	):
		return

	@warning_ignore("integer_division")
	var day_index := minute / MINUTES_PER_DAY
	if day_index != _current_day_index:
		# Callers drive each logic tick; missed-day catch-up belongs outside this scheduler.
		_begin_day(day_index)

	_last_world_minute = minute
	_update_social_batches(minute)
	_update_offscreen_ticks(minute, offscreen_agent_ids)


func should_tick_offscreen(agent_id: Variant) -> bool:
	if typeof(agent_id) != TYPE_STRING:
		return false
	return _offscreen_ticks_this_logic.has(agent_id)


func to_dict() -> Dictionary:
	var offscreen_agent_ids := _offscreen_ticks_this_logic.keys()
	offscreen_agent_ids.sort()
	return {
		"rng_state": _rng.to_dict(),
		"current_day_index": _current_day_index,
		"daily_social_budget": _daily_social_budget,
		"last_world_minute": _last_world_minute,
		"social_batches_today": social_batches_today,
		"offscreen_agent_ids": offscreen_agent_ids,
	}


func restore(data: Dictionary) -> void:
	if not _is_valid_state(data):
		push_error("Invalid SimulationScheduler state.")
		return

	var rng_state: Dictionary = data["rng_state"]
	_rng.restore(rng_state)
	_current_day_index = int(data["current_day_index"])
	_daily_social_budget = int(data["daily_social_budget"])
	_last_world_minute = int(data["last_world_minute"])
	social_batches_today = int(data["social_batches_today"])
	_offscreen_ticks_this_logic.clear()
	for agent_id in data["offscreen_agent_ids"]:
		_offscreen_ticks_this_logic[agent_id] = true


func _begin_day(day_index: int) -> void:
	_current_day_index = day_index
	social_batches_today = 0
	_daily_social_budget = _rng.next_int(
		MIN_SOCIAL_BATCHES_PER_DAY,
		MAX_SOCIAL_BATCHES_PER_DAY,
	)


func _update_social_batches(world_minute: int) -> void:
	var minute_of_day := world_minute % MINUTES_PER_DAY
	@warning_ignore("integer_division")
	var slot_index := minute_of_day / LOGIC_TICK_MINUTES
	@warning_ignore("integer_division")
	social_batches_today = (
		(slot_index + 1) * _daily_social_budget / SOCIAL_SLOTS_PER_DAY
	)


func _update_offscreen_ticks(world_minute: int, offscreen_agent_ids: Variant) -> void:
	_offscreen_ticks_this_logic.clear()
	if (
		world_minute % OFFSCREEN_TICK_MINUTES != 0
		or typeof(offscreen_agent_ids) != TYPE_ARRAY
	):
		return

	for agent_id in offscreen_agent_ids:
		if typeof(agent_id) == TYPE_STRING and not agent_id.is_empty():
			_offscreen_ticks_this_logic[agent_id] = true


func _is_valid_state(data: Dictionary) -> bool:
	var required_fields := [
		"rng_state",
		"current_day_index",
		"daily_social_budget",
		"last_world_minute",
		"social_batches_today",
		"offscreen_agent_ids",
	]
	for field in required_fields:
		if not data.has(field):
			return false

	if (
		typeof(data["rng_state"]) != TYPE_DICTIONARY
		or not _is_valid_rng_state(data["rng_state"])
		or not _is_integer_in_range(data["current_day_index"], -1, INT64_MAX)
		or not _is_integer_in_range(
			data["daily_social_budget"],
			0,
			MAX_SOCIAL_BATCHES_PER_DAY,
		)
		or not _is_integer_in_range(data["last_world_minute"], -1, INT64_MAX)
		or not _is_integer_in_range(
			data["social_batches_today"],
			0,
			MAX_SOCIAL_BATCHES_PER_DAY,
		)
		or not _is_valid_offscreen_agent_ids(data["offscreen_agent_ids"])
	):
		return false

	var current_day_index := int(data["current_day_index"])
	var daily_social_budget := int(data["daily_social_budget"])
	var last_world_minute := int(data["last_world_minute"])
	var restored_social_batches := int(data["social_batches_today"])
	var offscreen_agent_ids: Array = data["offscreen_agent_ids"]
	if last_world_minute == -1:
		return (
			current_day_index == -1
			and daily_social_budget == 0
			and restored_social_batches == 0
			and offscreen_agent_ids.is_empty()
		)
	if (
		last_world_minute % LOGIC_TICK_MINUTES != 0
		or current_day_index < 0
		or daily_social_budget < MIN_SOCIAL_BATCHES_PER_DAY
		or restored_social_batches > daily_social_budget
		or (
			last_world_minute % OFFSCREEN_TICK_MINUTES != 0
			and not offscreen_agent_ids.is_empty()
		)
	):
		return false

	@warning_ignore("integer_division")
	var expected_day_index := last_world_minute / MINUTES_PER_DAY
	if current_day_index != expected_day_index:
		return false

	var minute_of_day := last_world_minute % MINUTES_PER_DAY
	@warning_ignore("integer_division")
	var slot_index := minute_of_day / LOGIC_TICK_MINUTES
	@warning_ignore("integer_division")
	var expected_social_batches := (
		(slot_index + 1) * daily_social_budget / SOCIAL_SLOTS_PER_DAY
	)
	return restored_social_batches == expected_social_batches


func _is_valid_rng_state(value: Dictionary) -> bool:
	if not value.has("state_hi") or not value.has("state_lo"):
		return false
	if (
		not _is_integer_in_range(value["state_hi"], 0, UINT32_MAX)
		or not _is_integer_in_range(value["state_lo"], 0, UINT32_MAX)
	):
		return false
	return int(value["state_hi"]) != 0 or int(value["state_lo"]) != 0


func _is_valid_offscreen_agent_ids(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false

	var seen_ids := {}
	for agent_id in value:
		if (
			typeof(agent_id) != TYPE_STRING
			or agent_id.is_empty()
			or seen_ids.has(agent_id)
		):
			return false
		seen_ids[agent_id] = true
	return true


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	return (
		not is_nan(value)
		and not is_inf(value)
		and floor(value) == value
		and value >= minimum
		and value <= maximum
	)
