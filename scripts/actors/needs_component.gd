class_name NeedsComponent
extends Node

const DEFAULT_LEVELS := {
	"hunger": 20.0,
	"fatigue": 15.0,
	"social": 10.0,
}
const CHANGE_PER_MINUTE := {
	"hunger": 0.035,
	"fatigue": 0.025,
	"social": 0.02,
}

var _levels := DEFAULT_LEVELS.duplicate(true)
var _paused := false


func configure(initial_levels: Dictionary) -> bool:
	var next_levels := {}
	for need_id in DEFAULT_LEVELS:
		var value = initial_levels.get(need_id, DEFAULT_LEVELS[need_id])
		if not _is_finite_number(value):
			return false
		next_levels[need_id] = clampf(float(value), 0.0, 100.0)
	_levels = next_levels
	return true


func set_paused(value: bool) -> void:
	_paused = value


func is_paused() -> bool:
	return _paused


func advance_minutes(minutes: Variant) -> void:
	if _paused or not _is_finite_number(minutes):
		return
	var elapsed := float(minutes)
	if elapsed <= 0.0:
		return
	for need_id in CHANGE_PER_MINUTE:
		_levels[need_id] = clampf(
			_levels[need_id] + CHANGE_PER_MINUTE[need_id] * elapsed,
			0.0,
			100.0,
		)


func relieve(need_id: String, amount: Variant) -> bool:
	if (
		not _levels.has(need_id)
		or not _is_finite_number(amount)
		or float(amount) < 0.0
	):
		return false
	_levels[need_id] = maxf(_levels[need_id] - float(amount), 0.0)
	return true


func get_levels() -> Dictionary:
	return _levels.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"levels": _levels.duplicate(true),
		"paused": _paused,
	}


func restore(data: Dictionary) -> bool:
	var levels = data.get("levels", null)
	var paused = data.get("paused", null)
	if typeof(levels) != TYPE_DICTIONARY or typeof(paused) != TYPE_BOOL:
		return false

	var restored_levels := {}
	for need_id in DEFAULT_LEVELS:
		var value = levels.get(need_id, null)
		if (
			not _is_finite_number(value)
			or float(value) < 0.0
			or float(value) > 100.0
		):
			return false
		restored_levels[need_id] = float(value)

	_levels = restored_levels
	_paused = paused
	return true


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)
