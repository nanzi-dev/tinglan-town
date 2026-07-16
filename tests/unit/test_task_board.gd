extends GutTest


func test_domain_event_log_records_each_event_once_per_consumer() -> void:
	var event_log := DomainEventLog.new()

	assert_true(event_log.record_once("event-100", "task_board"))
	assert_true(event_log.has_event("event-100", "task_board"))
	assert_false(event_log.record_once("event-100", "task_board"))
	assert_true(event_log.record_once("event-100", "relationship_ledger"))
	assert_true(event_log.has_event("event-100", "relationship_ledger"))
	assert_true(event_log.record_once("default-event"))
	assert_true(event_log.has_event("default-event"))
	assert_false(event_log.record_once("", "task_board"))
	assert_false(event_log.record_once("event-101", ""))
	assert_false(event_log.record_once(100, "task_board"))
	assert_false(event_log.record_once("event-101", 100))
	assert_false(event_log.has_event("event-101", ""))


func test_duplicate_completion_event_rewards_only_once() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task(_accepted_herb_task()))

	var first := board.complete_task(
		"herb-01",
		"event-100",
		{"mint": 3},
	)
	var duplicate := board.complete_task(
		"herb-01",
		"event-100",
		{"mint": 3},
	)

	assert_eq(first.reward.coins, 80)
	assert_eq(duplicate.reward.coins, 0)
	assert_eq(board.task_status("herb-01"), "rewarded")


func test_complete_legal_status_chain_is_supported() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task({
		"task_id": "chain-01",
		"status": "draft",
		"reward": {"coins": 25},
		"completion_rules": [{
			"type": "has_item",
			"item_id": "seashell",
			"count": 2,
		}],
	}))

	for next_status in ["open", "accepted"]:
		assert_true(board.transition_task("chain-01", next_status))
		assert_eq(board.task_status("chain-01"), next_status)

	assert_eq(
		board.complete_task("chain-01", "chain-event", {"seashell": 2}),
		{"reward": {"coins": 25}},
	)
	assert_eq(board.task_status("chain-01"), "rewarded")


func test_completed_cannot_be_registered_or_entered_by_manual_transition() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task({
		"task_id": "accepted-01",
		"status": "accepted",
		"reward": {},
		"completion_rules": [],
	}))
	assert_false(board.add_task({
		"task_id": "completed-01",
		"status": "completed",
		"reward": {},
		"completion_rules": [],
	}))

	assert_false(board.transition_task("accepted-01", "completed"))
	assert_eq(board.task_status("accepted-01"), "accepted")
	assert_eq(board.task_status("completed-01"), "")


func test_all_stable_task_statuses_can_be_registered() -> void:
	var board := TaskBoard.new()

	for status in ["draft", "open", "accepted", "rewarded", "withdrawn", "expired"]:
		var task_id: String = "%s-01" % status
		assert_true(board.add_task({
			"task_id": task_id,
			"status": status,
			"reward": {},
			"completion_rules": [],
		}))
		assert_eq(board.task_status(task_id), status)


func test_withdrawn_and_expired_are_supported_terminal_branches() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task({
		"task_id": "withdraw-01",
		"status": "accepted",
		"reward": {},
		"completion_rules": [],
	}))
	assert_true(board.add_task({
		"task_id": "expire-01",
		"status": "open",
		"reward": {},
		"completion_rules": [],
	}))

	assert_true(board.transition_task("withdraw-01", "withdrawn"))
	assert_true(board.transition_task("expire-01", "expired"))
	assert_eq(board.task_status("withdraw-01"), "withdrawn")
	assert_eq(board.task_status("expire-01"), "expired")
	assert_false(board.transition_task("withdraw-01", "completed"))
	assert_false(board.transition_task("expire-01", "accepted"))


func test_illegal_status_transitions_are_rejected_without_state_changes() -> void:
	var board := TaskBoard.new()
	var cases := [
		{"task_id": "draft-01", "status": "draft", "target": "accepted"},
		{"task_id": "open-01", "status": "open", "target": "completed"},
		{"task_id": "accepted-01", "status": "accepted", "target": "rewarded"},
		{"task_id": "rewarded-01", "status": "rewarded", "target": "open"},
	]

	for case in cases:
		assert_true(board.add_task({
			"task_id": case["task_id"],
			"status": case["status"],
			"reward": {},
			"completion_rules": [],
		}))
		assert_false(board.transition_task(case["task_id"], case["target"]))
		assert_eq(board.task_status(case["task_id"]), case["status"])


func test_unsatisfied_completion_rule_does_not_change_state_or_consume_event() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task(_accepted_herb_task()))

	var rejected := board.complete_task(
		"herb-01",
		"event-100",
		{"mint": 2},
	)

	assert_eq(rejected, {"reward": {"coins": 0}})
	assert_eq(board.task_status("herb-01"), "accepted")

	var accepted := board.complete_task(
		"herb-01",
		"event-100",
		{"mint": 3},
	)
	assert_eq(accepted, {"reward": {"coins": 80}})
	assert_eq(board.task_status("herb-01"), "rewarded")


func test_has_item_uses_exact_integer_comparison_above_two_to_the_53() -> void:
	var required_count := 9007199254740993
	var board := TaskBoard.new()
	assert_true(board.add_task({
		"task_id": "large-count",
		"status": "accepted",
		"reward": {"coins": 80},
		"completion_rules": [{
			"type": "has_item",
			"item_id": "mint",
			"count": required_count,
		}],
	}))

	assert_eq(
		board.complete_task(
			"large-count",
			"large-event",
			{"mint": required_count - 1},
		),
		{"reward": {"coins": 0}},
	)
	assert_eq(board.task_status("large-count"), "accepted")
	assert_eq(
		board.complete_task(
			"large-count",
			"large-event",
			{"mint": required_count},
		),
		{"reward": {"coins": 80}},
	)
	assert_eq(board.task_status("large-count"), "rewarded")


func test_has_item_inventory_count_must_be_a_nonnegative_integer() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task(_accepted_herb_task()))

	assert_eq(
		board.complete_task("herb-01", "event-100", {"mint": 3.0}),
		{"reward": {"coins": 0}},
	)
	assert_eq(board.task_status("herb-01"), "accepted")
	assert_eq(
		board.complete_task("herb-01", "event-100", {"mint": 3}),
		{"reward": {"coins": 80}},
	)


func test_zero_has_item_requirement_is_a_valid_nonnegative_count() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task({
		"task_id": "zero-count",
		"status": "accepted",
		"reward": {"coins": 5},
		"completion_rules": [{
			"type": "has_item",
			"item_id": "mint",
			"count": 0,
		}],
	}))

	assert_eq(
		board.complete_task("zero-count", "zero-event", {"mint": 0}),
		{"reward": {"coins": 5}},
	)


func test_zero_reward_preserves_each_reward_value_type() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task({
		"task_id": "typed-reward",
		"status": "accepted",
		"reward": {
			"coins": 80,
			"reputation": 2.5,
		},
		"completion_rules": [{
			"type": "has_item",
			"item_id": "mint",
			"count": 3,
		}],
	}))

	var result := board.complete_task(
		"typed-reward",
		"typed-event",
		{"mint": 2},
	)

	assert_eq(typeof(result.reward.coins), TYPE_INT)
	assert_eq(typeof(result.reward.reputation), TYPE_FLOAT)
	assert_eq(result.reward, {
		"coins": 0,
		"reputation": 0.0,
	})


func test_unknown_task_and_duplicate_task_id_are_rejected() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task(_accepted_herb_task()))
	assert_false(board.add_task(_accepted_herb_task()))

	assert_false(board.transition_task("missing", "open"))
	assert_eq(board.task_status("missing"), "")
	assert_eq(
		board.complete_task("missing", "event-404", {"mint": 3}),
		{"reward": {}},
	)
	assert_eq(board.task_status("herb-01"), "accepted")


func test_event_id_cannot_reward_two_different_tasks() -> void:
	var event_log := DomainEventLog.new()
	var board := TaskBoard.new(event_log)
	var first_task := _accepted_herb_task()
	var second_task := _accepted_herb_task()
	second_task["task_id"] = "herb-02"
	assert_true(board.add_task(first_task))
	assert_true(board.add_task(second_task))

	assert_eq(
		board.complete_task("herb-01", "shared-event", {"mint": 3}),
		{"reward": {"coins": 80}},
	)
	assert_eq(
		board.complete_task("herb-02", "shared-event", {"mint": 3}),
		{"reward": {"coins": 0}},
	)
	assert_eq(board.task_status("herb-02"), "accepted")


func test_shared_event_log_allows_task_and_relationship_consumers_once_each() -> void:
	var event_log := DomainEventLog.new()
	var board := TaskBoard.new(event_log)
	var ledger := RelationshipLedger.new(event_log)
	assert_true(board.add_task(_accepted_herb_task()))

	assert_eq(
		board.complete_task("herb-01", "shared-domain-event", {"mint": 3}),
		{"reward": {"coins": 80}},
	)
	assert_true(ledger.apply_change(
		"lin",
		5,
		5,
		0,
		"完成了采药委托",
		"shared-domain-event",
	))
	assert_eq(
		board.complete_task("herb-01", "shared-domain-event", {"mint": 3}),
		{"reward": {"coins": 0}},
	)
	assert_false(ledger.apply_change(
		"lin",
		5,
		5,
		0,
		"不应重复的关系变化",
		"shared-domain-event",
	))
	assert_true(event_log.has_event("shared-domain-event", "task_board"))
	assert_true(event_log.has_event("shared-domain-event", "relationship_ledger"))


func test_completion_result_reward_is_a_deep_copy() -> void:
	var board := TaskBoard.new()
	assert_true(board.add_task(_accepted_herb_task()))

	var first := board.complete_task("herb-01", "event-100", {"mint": 3})
	first.reward.erase("coins")

	assert_eq(
		board.complete_task("herb-01", "event-100", {"mint": 3}),
		{"reward": {"coins": 0}},
	)


func test_invalid_task_definition_is_rejected_without_partial_registration() -> void:
	var board := TaskBoard.new()

	assert_false(board.add_task({
		"task_id": "invalid-01",
		"status": "accepted",
		"reward": {"coins": 80},
		"completion_rules": [{
			"type": "unknown_rule",
		}],
	}))

	assert_eq(board.task_status("invalid-01"), "")


func _accepted_herb_task() -> Dictionary:
	return {
		"task_id": "herb-01",
		"status": "accepted",
		"reward": {"coins": 80},
		"completion_rules": [{
			"type": "has_item",
			"item_id": "mint",
			"count": 3,
		}],
	}
