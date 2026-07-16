class_name WorldClock
extends RefCounted

const MINUTES_PER_DAY := 1440
const INT64_MAX := 0x7fffffffffffffff
const INT64_EXCLUSIVE_UPPER_BOUND_FLOAT := 9223372036854775808.0

var total_minutes: int = 0
var paused: bool = false
var day: int:
	get:
		@warning_ignore("integer_division")
		return total_minutes / MINUTES_PER_DAY + 1
var minute_of_day: int:
	get:
		return total_minutes % MINUTES_PER_DAY

var _real_seconds_remainder: float = 0.0


func advance_real_seconds(seconds: float) -> void:
	if is_nan(seconds) or is_inf(seconds):
		push_error("Cannot advance by non-finite real seconds.")
		return
	if seconds < 0.0:
		push_error("Cannot advance by negative real seconds.")
		return
	if paused:
		return

	var accumulated_seconds := _real_seconds_remainder + seconds
	if (
		is_nan(accumulated_seconds)
		or is_inf(accumulated_seconds)
		or accumulated_seconds >= INT64_EXCLUSIVE_UPPER_BOUND_FLOAT
	):
		push_error("Cannot advance real seconds beyond int64 range.")
		return

	var whole_minutes := int(floor(accumulated_seconds))
	if whole_minutes > INT64_MAX - total_minutes:
		push_error("Cannot advance real seconds beyond int64 range.")
		return

	_real_seconds_remainder = accumulated_seconds - whole_minutes
	total_minutes += whole_minutes


func advance_game_minutes(minutes: int) -> void:
	if minutes < 0:
		push_error("Cannot advance by negative game minutes.")
		return
	if minutes > INT64_MAX - total_minutes:
		push_error("Cannot advance game minutes beyond int64 range.")
		return
	if paused:
		return

	total_minutes += minutes


func set_paused(value: bool) -> void:
	paused = value


func to_dict() -> Dictionary:
	return {
		"total_minutes": total_minutes,
		"paused": paused,
		"real_seconds_remainder": _real_seconds_remainder,
	}


func restore(data: Dictionary) -> void:
	if (
		not data.has("total_minutes")
		or not data.has("paused")
		or not data.has("real_seconds_remainder")
	):
		push_error("Invalid WorldClock state: missing required fields.")
		return

	var restored_total_minutes = data["total_minutes"]
	var restored_paused = data["paused"]
	var restored_remainder = data["real_seconds_remainder"]
	var total_minutes_type := typeof(restored_total_minutes)
	var remainder_type := typeof(restored_remainder)
	if (
		(total_minutes_type != TYPE_INT and total_minutes_type != TYPE_FLOAT)
		or typeof(restored_paused) != TYPE_BOOL
		or (remainder_type != TYPE_INT and remainder_type != TYPE_FLOAT)
	):
		push_error("Invalid WorldClock state: fields have invalid types.")
		return

	var restored_total_minutes_int: int
	if total_minutes_type == TYPE_FLOAT:
		var restored_total_minutes_float: float = restored_total_minutes
		if (
			is_nan(restored_total_minutes_float)
			or is_inf(restored_total_minutes_float)
			or restored_total_minutes_float < 0.0
			or restored_total_minutes_float >= INT64_EXCLUSIVE_UPPER_BOUND_FLOAT
			or floor(restored_total_minutes_float) != restored_total_minutes_float
		):
			push_error("Invalid WorldClock state: fields are out of range.")
			return
		restored_total_minutes_int = int(restored_total_minutes_float)
	else:
		restored_total_minutes_int = restored_total_minutes

	var restored_remainder_float := float(restored_remainder)
	if (
		restored_total_minutes_int < 0
		or is_nan(restored_remainder_float)
		or is_inf(restored_remainder_float)
		or restored_remainder_float < 0.0
		or restored_remainder_float >= 1.0
	):
		push_error("Invalid WorldClock state: fields are out of range.")
		return

	total_minutes = restored_total_minutes_int
	paused = restored_paused
	_real_seconds_remainder = restored_remainder_float
