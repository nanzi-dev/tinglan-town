extends GutTest

const INT64_MAX := 0x7fffffffffffffff


func test_one_real_second_advances_one_game_minute() -> void:
	var clock := WorldClock.new()

	clock.advance_real_seconds(1.0)

	assert_eq(clock.total_minutes, 1)
	assert_eq(clock.day, 1)
	assert_eq(clock.minute_of_day, 1)


func test_paused_clock_does_not_advance_minutes_or_remainder() -> void:
	var clock := WorldClock.new()
	clock.advance_real_seconds(0.5)
	clock.set_paused(true)

	clock.advance_real_seconds(10.0)
	clock.set_paused(false)
	clock.advance_real_seconds(0.5)

	assert_eq(clock.total_minutes, 1)


func test_1440_game_minutes_advances_to_next_day() -> void:
	var clock := WorldClock.new()

	clock.advance_game_minutes(WorldClock.MINUTES_PER_DAY)

	assert_eq(clock.total_minutes, WorldClock.MINUTES_PER_DAY)
	assert_eq(clock.day, 2)
	assert_eq(clock.minute_of_day, 0)


func test_fractional_real_seconds_accumulate_to_whole_minutes() -> void:
	var clock := WorldClock.new()

	clock.advance_real_seconds(0.5)
	assert_eq(clock.total_minutes, 0)

	clock.advance_real_seconds(0.5)
	assert_eq(clock.total_minutes, 1)


func test_to_dict_and_restore_preserve_deterministic_clock_state() -> void:
	var original := WorldClock.new()
	original.advance_game_minutes(61)
	original.advance_real_seconds(0.5)
	original.set_paused(true)

	var saved := original.to_dict()
	var restored := WorldClock.new()
	restored.restore(saved)

	assert_eq(saved["total_minutes"], 61)
	assert_eq(saved["paused"], true)
	assert_eq(restored.total_minutes, 61)
	assert_eq(restored.paused, true)

	restored.set_paused(false)
	restored.advance_real_seconds(0.5)
	assert_eq(restored.total_minutes, 62)


func test_json_round_trip_restores_clock_state_and_remainder() -> void:
	var original := WorldClock.new()
	original.advance_game_minutes(61)
	original.advance_real_seconds(0.5)
	original.set_paused(true)
	var saved := original.to_dict()
	var parsed = JSON.parse_string(JSON.stringify(saved))

	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	assert_eq(typeof(parsed["total_minutes"]), TYPE_FLOAT)

	var restored := WorldClock.new()
	restored.restore(parsed)
	assert_eq(restored.to_dict(), saved)

	restored.set_paused(false)
	restored.advance_real_seconds(0.5)
	assert_eq(restored.total_minutes, 62)


func test_negative_real_seconds_do_not_change_clock_state() -> void:
	var clock := WorldClock.new()
	clock.advance_real_seconds(0.5)
	var saved := clock.to_dict()

	clock.advance_real_seconds(-1.0)

	assert_push_error("Cannot advance by negative real seconds")
	assert_eq(clock.to_dict(), saved)


func test_non_finite_real_seconds_do_not_change_clock_state() -> void:
	for invalid_seconds in [NAN, INF]:
		var clock := WorldClock.new()
		clock.advance_real_seconds(0.5)
		var saved := clock.to_dict()

		clock.advance_real_seconds(invalid_seconds)

		assert_push_error("Cannot advance by non-finite real seconds")
		assert_eq(clock.to_dict(), saved)


func test_huge_finite_real_seconds_do_not_change_clock_state() -> void:
	var clock := WorldClock.new()
	clock.advance_game_minutes(10)
	clock.advance_real_seconds(0.5)
	var saved := clock.to_dict()

	clock.advance_real_seconds(1.0e300)

	assert_push_error("Cannot advance real seconds beyond int64 range")
	assert_eq(clock.to_dict(), saved)


func test_real_seconds_overflow_does_not_partially_apply_remainder() -> void:
	var clock := WorldClock.new()
	clock.restore({
		"total_minutes": INT64_MAX,
		"paused": false,
		"real_seconds_remainder": 0.5,
	})
	var saved := clock.to_dict()

	clock.advance_real_seconds(0.5)

	assert_push_error("Cannot advance real seconds beyond int64 range")
	assert_eq(clock.to_dict(), saved)


func test_negative_game_minutes_do_not_change_clock_state() -> void:
	var clock := WorldClock.new()
	clock.advance_game_minutes(10)
	clock.advance_real_seconds(0.5)
	var saved := clock.to_dict()

	clock.advance_game_minutes(-3)

	assert_push_error("Cannot advance by negative game minutes")
	assert_eq(clock.to_dict(), saved)


func test_game_minutes_overflow_does_not_change_clock_state() -> void:
	var clock := WorldClock.new()
	clock.restore({
		"total_minutes": INT64_MAX - 1,
		"paused": false,
		"real_seconds_remainder": 0.5,
	})
	var saved := clock.to_dict()

	clock.advance_game_minutes(2)

	assert_push_error("Cannot advance game minutes beyond int64 range")
	assert_eq(clock.to_dict(), saved)


func test_restore_rejects_missing_fields_without_partial_application() -> void:
	var clock := WorldClock.new()
	clock.advance_game_minutes(61)
	clock.advance_real_seconds(0.5)
	clock.set_paused(true)
	var saved := clock.to_dict()

	clock.restore({
		"total_minutes": 5,
		"paused": false,
	})

	assert_push_error("Invalid WorldClock state")
	assert_eq(clock.to_dict(), saved)


func test_restore_rejects_wrong_field_types_without_partial_application() -> void:
	var clock := WorldClock.new()
	clock.advance_game_minutes(61)
	clock.advance_real_seconds(0.5)
	clock.set_paused(true)
	var saved := clock.to_dict()
	var invalid_states: Array[Dictionary] = [
		{
			"total_minutes": "12",
			"paused": false,
			"real_seconds_remainder": 0.25,
		},
		{
			"total_minutes": 12,
			"paused": 1,
			"real_seconds_remainder": 0.25,
		},
		{
			"total_minutes": 12,
			"paused": false,
			"real_seconds_remainder": "0.25",
		},
	]

	for invalid_state in invalid_states:
		clock.restore(invalid_state)
		assert_push_error("Invalid WorldClock state")
		assert_eq(clock.to_dict(), saved)
		clock.restore(saved)


func test_restore_rejects_out_of_range_values_without_partial_application() -> void:
	var clock := WorldClock.new()
	clock.advance_game_minutes(61)
	clock.advance_real_seconds(0.5)
	clock.set_paused(true)
	var saved := clock.to_dict()
	var invalid_states: Array[Dictionary] = [
		{
			"total_minutes": -1,
			"paused": false,
			"real_seconds_remainder": 0.25,
		},
		{
			"total_minutes": -1.0,
			"paused": false,
			"real_seconds_remainder": 0.25,
		},
		{
			"total_minutes": 12.5,
			"paused": false,
			"real_seconds_remainder": 0.25,
		},
		{
			"total_minutes": NAN,
			"paused": false,
			"real_seconds_remainder": 0.25,
		},
		{
			"total_minutes": INF,
			"paused": false,
			"real_seconds_remainder": 0.25,
		},
		{
			"total_minutes": 9223372036854775808.0,
			"paused": false,
			"real_seconds_remainder": 0.25,
		},
		{
			"total_minutes": 12,
			"paused": false,
			"real_seconds_remainder": -0.01,
		},
		{
			"total_minutes": 12,
			"paused": false,
			"real_seconds_remainder": 1.0,
		},
		{
			"total_minutes": 12,
			"paused": false,
			"real_seconds_remainder": NAN,
		},
		{
			"total_minutes": 12,
			"paused": false,
			"real_seconds_remainder": INF,
		},
	]

	for invalid_state in invalid_states:
		clock.restore(invalid_state)
		assert_push_error("Invalid WorldClock state")
		assert_eq(clock.to_dict(), saved)
		clock.restore(saved)
