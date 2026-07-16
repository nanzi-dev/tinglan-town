extends GutTest

const INT64_MAX := 0x7fffffffffffffff
const INT64_MIN := -0x7fffffffffffffff - 1
const UINT32_MAX := 0xffffffff


func test_same_seed_produces_same_sequence() -> void:
	var first := DeterministicRng.new(123456789)
	var second := DeterministicRng.new(123456789)

	for index in range(32):
		assert_eq(
			first.next_int(-1000, 1000),
			second.next_int(-1000, 1000),
			"Sequence differed at index %d." % index,
		)


func test_restore_continues_the_exact_sequence() -> void:
	var original := DeterministicRng.new(987654321)
	for index in range(7):
		original.next_int(-50, 50)

	var saved := original.to_dict()
	var restored := DeterministicRng.new(1)
	restored.restore(saved)

	assert_eq(restored.to_dict(), saved)
	for index in range(32):
		assert_eq(
			restored.next_int(-50, 50),
			original.next_int(-50, 50),
			"Restored sequence differed at index %d." % index,
		)


func test_json_round_trip_preserves_exact_state_and_sequence() -> void:
	var original := DeterministicRng.new(0x7fffffffffffffed)
	var saved := original.to_dict()

	assert_true(saved.has("state_hi"))
	assert_true(saved.has("state_lo"))
	assert_false(saved.has("state"))
	assert_eq(typeof(saved["state_hi"]), TYPE_INT)
	assert_eq(typeof(saved["state_lo"]), TYPE_INT)

	var parsed = JSON.parse_string(JSON.stringify(saved))
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	assert_eq(typeof(parsed["state_hi"]), TYPE_FLOAT)
	assert_eq(typeof(parsed["state_lo"]), TYPE_FLOAT)

	var restored := DeterministicRng.new(1)
	restored.restore(parsed)
	assert_eq(restored.to_dict(), saved)

	for index in range(32):
		assert_eq(
			restored.next_int(-1000, 1000),
			original.next_int(-1000, 1000),
			"JSON-restored sequence differed at index %d." % index,
		)


func test_restore_rejects_invalid_halves_without_changing_state() -> void:
	var invalid_states: Array[Dictionary] = [
		{"state_lo": 1},
		{"state_hi": 1},
		{"state_hi": "1", "state_lo": 1},
		{"state_hi": 1, "state_lo": false},
		{"state_hi": NAN, "state_lo": 1},
		{"state_hi": 1, "state_lo": INF},
		{"state_hi": 1.5, "state_lo": 1},
		{"state_hi": 1, "state_lo": 1.5},
		{"state_hi": -1, "state_lo": 1},
		{"state_hi": 1, "state_lo": -1},
		{"state_hi": UINT32_MAX + 1, "state_lo": 1},
		{"state_hi": 1, "state_lo": UINT32_MAX + 1},
		{"state_hi": 0, "state_lo": 0},
	]

	for invalid_state in invalid_states:
		var rng := DeterministicRng.new(42)
		var saved := rng.to_dict()

		rng.restore(invalid_state)

		assert_push_error("Invalid DeterministicRng state")
		assert_eq(rng.to_dict(), saved)


func test_next_int_is_inclusive_and_stays_within_range() -> void:
	var rng := DeterministicRng.new(42)
	var saw_minimum := false
	var saw_maximum := false

	for index in range(256):
		var binary_value := rng.next_int(0, 1)
		assert_true(binary_value >= 0 and binary_value <= 1)
		saw_minimum = saw_minimum or binary_value == 0
		saw_maximum = saw_maximum or binary_value == 1

	for index in range(256):
		var signed_value := rng.next_int(-3, 4)
		assert_true(signed_value >= -3 and signed_value <= 4)

	assert_true(saw_minimum)
	assert_true(saw_maximum)
	assert_eq(rng.next_int(7, 7), 7)


func test_next_int_uses_rejection_sampling_for_non_power_of_two_span() -> void:
	var rng := DeterministicRng.new(42)

	assert_eq(rng.next_int(0, 4611686018427387904), 2308845766745129663)


func test_non_power_of_two_span_rejects_sample_above_acceptable_limit() -> void:
	var rng := DeterministicRng.new(4)

	assert_eq(rng.next_int(0, 4611686018427387904), 310720750336478072)
	assert_eq(rng.to_dict(), {
		"state_hi": 2219828960,
		"state_lo": 1277561720,
	})


func test_next_int_supports_exactly_two_to_the_63_values() -> void:
	var rng := DeterministicRng.new(42)
	var zero_rng := DeterministicRng.new(-435785325752590207)

	assert_eq(rng.next_int(0, INT64_MAX), 2308845766745129663)
	assert_eq(zero_rng.next_int(0, INT64_MAX), 0)


func test_next_int_supports_ranges_wider_than_two_to_the_63_values() -> void:
	var lower_side_rng := DeterministicRng.new(42)
	var upper_side_rng := DeterministicRng.new(42)

	assert_eq(
		lower_side_rng.next_int(INT64_MIN, 0),
		-6914526270109646146,
	)
	assert_eq(
		upper_side_rng.next_int(-1, INT64_MAX),
		6914526270109646145,
	)


func test_next_int_full_signed_range_has_a_deterministic_special_case() -> void:
	var rng := DeterministicRng.new(314159)

	assert_eq(
		rng.next_int(INT64_MIN, INT64_MAX),
		334970046507385,
	)


func test_next_int_rejects_an_invalid_range_without_advancing_state() -> void:
	var rng := DeterministicRng.new(42)
	var saved := rng.to_dict()

	var result := rng.next_int(9, 3)

	assert_push_error("Minimum must not exceed maximum")
	assert_eq(result, 9)
	assert_eq(rng.to_dict(), saved)


func test_zero_seed_maps_to_nonzero_progressing_state() -> void:
	var rng := DeterministicRng.new(0)
	var initial_state := rng.to_dict()

	rng.next_int(-100, 100)
	var advanced_state := rng.to_dict()

	assert_false(
		int(initial_state.get("state_hi", 0)) == 0
		and int(initial_state.get("state_lo", 0)) == 0
	)
	assert_false(
		int(advanced_state.get("state_hi", 0)) == 0
		and int(advanced_state.get("state_lo", 0)) == 0
	)
	assert_ne(advanced_state, initial_state)
