class_name DeterministicRng
extends RefCounted

const INT64_MAX := 0x7fffffffffffffff
const INT64_MIN := -0x7fffffffffffffff - 1
const NONZERO_STATE := 0x2545f4914f6cdd1d
const UINT32_MAX := 0xffffffff

var _state: int


func _init(seed: int) -> void:
	_state = _normalize_state(seed)


func next_int(minimum: int, maximum: int) -> int:
	if minimum > maximum:
		push_error("Minimum must not exceed maximum.")
		return minimum

	if minimum == INT64_MIN and maximum == INT64_MAX:
		return _next_state()

	var range_size := maximum - minimum + 1
	if range_size == INT64_MIN:
		return minimum + _next_uniform_63()
	if range_size < 0:
		var excluded_value := minimum - 1 if minimum > INT64_MIN else maximum + 1
		var candidate := _next_state() ^ excluded_value
		while candidate < minimum or candidate > maximum:
			candidate = _next_state() ^ excluded_value
		return candidate

	var rejection_size := ((INT64_MAX % range_size) + 1) % range_size
	var maximum_acceptable := INT64_MAX - rejection_size
	var sample := _next_uniform_63()
	while sample > maximum_acceptable:
		sample = _next_uniform_63()
	return minimum + sample % range_size


func to_dict() -> Dictionary:
	return {
		"state_hi": _logical_right_shift(_state, 32),
		"state_lo": _state & UINT32_MAX,
	}


func restore(data: Dictionary) -> void:
	if not data.has("state_hi") or not data.has("state_lo"):
		push_error("Invalid DeterministicRng state: missing required fields.")
		return

	var restored_state_hi = data["state_hi"]
	var restored_state_lo = data["state_lo"]
	if not _is_valid_state_half(restored_state_hi) or not _is_valid_state_half(restored_state_lo):
		push_error("Invalid DeterministicRng state: fields are out of range.")
		return

	var state_hi := int(data["state_hi"])
	var state_lo := int(data["state_lo"])
	if state_hi == 0 and state_lo == 0:
		push_error("Invalid DeterministicRng state: state must be nonzero.")
		return

	_state = (state_hi << 32) | state_lo


func _next_state() -> int:
	var value := _state
	value ^= value << 13
	value ^= _logical_right_shift(value, 7)
	value ^= value << 17
	_state = _normalize_state(value)
	return _state


func _next_uniform_63() -> int:
	var sample := _next_state()
	while sample >= 0:
		sample = _next_state()
	return sample ^ INT64_MIN


func _logical_right_shift(value: int, amount: int) -> int:
	assert(amount > 0 and amount < 64)
	var mask := INT64_MAX >> (amount - 1)
	return (value >> amount) & mask


func _is_valid_state_half(value: Variant) -> bool:
	var value_type := typeof(value)
	if value_type == TYPE_INT:
		return value >= 0 and value <= UINT32_MAX
	if value_type != TYPE_FLOAT:
		return false

	return (
		not is_nan(value)
		and not is_inf(value)
		and value >= 0.0
		and value <= UINT32_MAX
		and floor(value) == value
	)


func _normalize_state(value: int) -> int:
	if value == 0:
		return NONZERO_STATE
	return value
