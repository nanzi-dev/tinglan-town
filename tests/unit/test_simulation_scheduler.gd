extends GutTest


func test_default_tick_intervals_are_ten_and_thirty_minutes() -> void:
	assert_eq(SimulationScheduler.LOGIC_TICK_MINUTES, 10)
	assert_eq(SimulationScheduler.OFFSCREEN_TICK_MINUTES, 30)


func test_offscreen_agents_use_thirty_minute_ticks() -> void:
	var scheduler := SimulationScheduler.new(37)

	scheduler.advance_logic_tick(10, ["agent-a"])
	assert_false(scheduler.should_tick_offscreen("agent-a"))

	scheduler.advance_logic_tick(30, ["agent-a"])
	assert_true(scheduler.should_tick_offscreen("agent-a"))
	assert_false(scheduler.should_tick_offscreen("agent-b"))


func test_social_batches_stay_within_daily_budget() -> void:
	var scheduler := SimulationScheduler.new(37)

	for tick in range(144):
		scheduler.advance_logic_tick(tick * 10, [])

	assert_between(scheduler.social_batches_today, 30, 60)


func test_same_seed_produces_the_same_daily_social_schedule() -> void:
	var first := SimulationScheduler.new(37)
	var second := SimulationScheduler.new(37)

	for tick in range(144):
		first.advance_logic_tick(tick * 10, [])
		second.advance_logic_tick(tick * 10, [])
		assert_eq(
			first.social_batches_today,
			second.social_batches_today,
			"Social schedule differed at tick %d." % tick,
		)


func test_new_day_resets_and_generates_a_deterministic_budget() -> void:
	var first := SimulationScheduler.new(37)
	var second := SimulationScheduler.new(37)

	for tick in range(144):
		first.advance_logic_tick(tick * 10, [])
		second.advance_logic_tick(tick * 10, [])
	var first_day_batches := first.social_batches_today
	assert_between(first_day_batches, 30, 60)

	first.advance_logic_tick(1440, [])
	second.advance_logic_tick(1440, [])
	assert_eq(first.social_batches_today, 0)
	assert_eq(second.social_batches_today, 0)

	for tick in range(145, 288):
		first.advance_logic_tick(tick * 10, [])
		second.advance_logic_tick(tick * 10, [])

	assert_between(first.social_batches_today, 30, 60)
	assert_eq(first.social_batches_today, second.social_batches_today)


func test_duplicate_and_out_of_order_ticks_do_not_change_state() -> void:
	var scheduler := SimulationScheduler.new(37)
	scheduler.advance_logic_tick(300, ["agent-a"])
	var batches_after_tick := scheduler.social_batches_today
	assert_true(scheduler.should_tick_offscreen("agent-a"))

	scheduler.advance_logic_tick(300, ["agent-b"])
	assert_eq(scheduler.social_batches_today, batches_after_tick)
	assert_true(scheduler.should_tick_offscreen("agent-a"))
	assert_false(scheduler.should_tick_offscreen("agent-b"))

	scheduler.advance_logic_tick(290, ["agent-b"])
	assert_eq(scheduler.social_batches_today, batches_after_tick)
	assert_true(scheduler.should_tick_offscreen("agent-a"))
	assert_false(scheduler.should_tick_offscreen("agent-b"))


func test_malformed_tick_arguments_are_ignored_without_crashing() -> void:
	var scheduler := SimulationScheduler.new(37)

	scheduler.advance_logic_tick("ten", ["agent-a"])
	scheduler.advance_logic_tick(-10, ["agent-a"])
	scheduler.advance_logic_tick(15, ["agent-a"])

	assert_eq(scheduler.social_batches_today, 0)
	assert_false(scheduler.should_tick_offscreen("agent-a"))
	assert_false(scheduler.should_tick_offscreen(17))


func test_injected_rng_is_consumed_continuously_across_days() -> void:
	var shared_rng := DeterministicRng.new(37)
	var expected_rng := DeterministicRng.new(37)
	var scheduler := SimulationScheduler.new(shared_rng)

	scheduler.advance_logic_tick(0, [])
	expected_rng.next_int(30, 60)
	assert_eq(shared_rng.to_dict(), expected_rng.to_dict())

	scheduler.advance_logic_tick(1440, [])
	expected_rng.next_int(30, 60)
	assert_eq(shared_rng.to_dict(), expected_rng.to_dict())


func test_restored_state_continues_deterministically_across_day_boundary() -> void:
	var uninterrupted := SimulationScheduler.new(37)
	var checkpointed := SimulationScheduler.new(37)
	for tick in range(120):
		uninterrupted.advance_logic_tick(tick * 10, [])
		checkpointed.advance_logic_tick(tick * 10, [])

	var saved: Dictionary = checkpointed.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored := SimulationScheduler.new(999)
	restored.restore(parsed)

	assert_eq(restored.to_dict(), saved)
	for tick in range(120, 170):
		uninterrupted.advance_logic_tick(tick * 10, [])
		restored.advance_logic_tick(tick * 10, [])
		assert_eq(
			restored.to_dict(),
			uninterrupted.to_dict(),
			"Restored scheduler differed at tick %d." % tick,
		)


func test_restore_rejects_missing_state_without_partial_application() -> void:
	var scheduler := SimulationScheduler.new(37)
	scheduler.advance_logic_tick(300, ["agent-a"])
	var saved: Dictionary = scheduler.to_dict()

	scheduler.restore({})

	assert_push_error("Invalid SimulationScheduler state")
	assert_eq(scheduler.to_dict(), saved)
	assert_true(scheduler.should_tick_offscreen("agent-a"))


func test_restore_preserves_offscreen_state_for_duplicate_ticks() -> void:
	var original := SimulationScheduler.new(37)
	original.advance_logic_tick(300, ["agent-b", "agent-a"])

	var restored := SimulationScheduler.new(999)
	restored.restore(original.to_dict())
	restored.advance_logic_tick(300, ["agent-c"])

	assert_true(restored.should_tick_offscreen("agent-a"))
	assert_true(restored.should_tick_offscreen("agent-b"))
	assert_false(restored.should_tick_offscreen("agent-c"))


func test_restore_rejects_offscreen_agents_in_uninitialized_state_atomically() -> void:
	var shared_rng := DeterministicRng.new(37)
	var scheduler := SimulationScheduler.new(shared_rng)
	scheduler.advance_logic_tick(300, ["agent-a"])
	var original_state := scheduler.to_dict()
	var original_rng_state := shared_rng.to_dict()
	var forged_state := SimulationScheduler.new(91).to_dict()
	forged_state["offscreen_agent_ids"] = ["forged-agent"]

	scheduler.restore(forged_state)

	assert_push_error("Invalid SimulationScheduler state")
	assert_eq(scheduler.to_dict(), original_state)
	assert_eq(shared_rng.to_dict(), original_rng_state)


func test_restore_rejects_offscreen_agents_between_tick_boundaries_atomically() -> void:
	var shared_rng := DeterministicRng.new(37)
	var scheduler := SimulationScheduler.new(shared_rng)
	scheduler.advance_logic_tick(300, ["agent-a"])
	var original_state := scheduler.to_dict()
	var original_rng_state := shared_rng.to_dict()
	var source := SimulationScheduler.new(91)
	source.advance_logic_tick(10, [])
	var forged_state := source.to_dict()
	forged_state["offscreen_agent_ids"] = ["forged-agent"]

	scheduler.restore(forged_state)

	assert_push_error("Invalid SimulationScheduler state")
	assert_eq(scheduler.to_dict(), original_state)
	assert_eq(shared_rng.to_dict(), original_rng_state)
