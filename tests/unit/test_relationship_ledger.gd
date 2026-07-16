extends GutTest


func test_unknown_npc_has_a_reasonable_initial_public_view() -> void:
	var ledger := RelationshipLedger.new()

	assert_eq(ledger.public_view("lin"), {
		"stage": "acquainted",
		"label": "初识",
		"recent_reasons": [],
	})


func test_public_view_never_exposes_relationship_numbers() -> void:
	var ledger := RelationshipLedger.new()
	assert_true(ledger.apply_change(
		"lin",
		20,
		10,
		5,
		"帮忙修好了渔网",
		"event-1",
	))

	var view := ledger.public_view("lin")

	assert_false(view.has("affinity"))
	assert_false(view.has("trust"))
	assert_false(view.has("guard"))
	assert_eq(view.size(), 3)
	for allowed_key in ["stage", "label", "recent_reasons"]:
		assert_true(view.has(allowed_key))


func test_acquainted_stage_uses_initial_and_below_threshold_values() -> void:
	var ledger := RelationshipLedger.new()
	assert_true(ledger.apply_change(
		"lin",
		34,
		29,
		44,
		"第一次认真交谈",
		"event-1",
	))

	assert_eq(ledger.public_view("lin")["stage"], "acquainted")
	assert_eq(ledger.public_view("lin")["label"], "初识")


func test_familiar_stage_uses_trust_or_affinity_threshold() -> void:
	var ledger := RelationshipLedger.new()
	assert_true(ledger.apply_change(
		"trust-threshold",
		0,
		30,
		0,
		"按时赴约",
		"event-1",
	))
	assert_true(ledger.apply_change(
		"affinity-threshold",
		35,
		0,
		0,
		"分享了点心",
		"event-2",
	))

	assert_eq(ledger.public_view("trust-threshold")["stage"], "familiar")
	assert_eq(ledger.public_view("trust-threshold")["label"], "熟悉")
	assert_eq(ledger.public_view("affinity-threshold")["stage"], "familiar")
	assert_eq(ledger.public_view("affinity-threshold")["label"], "熟悉")


func test_close_stage_requires_both_trust_and_affinity_thresholds() -> void:
	var ledger := RelationshipLedger.new()
	assert_true(ledger.apply_change(
		"close",
		60,
		65,
		0,
		"共同守住了码头",
		"event-1",
	))
	assert_true(ledger.apply_change(
		"trust-only",
		59,
		65,
		0,
		"仍需更多了解",
		"event-2",
	))
	assert_true(ledger.apply_change(
		"affinity-only",
		60,
		64,
		0,
		"仍需建立信任",
		"event-3",
	))

	assert_eq(ledger.public_view("close")["stage"], "close")
	assert_eq(ledger.public_view("close")["label"], "亲近")
	assert_eq(ledger.public_view("trust-only")["stage"], "familiar")
	assert_eq(ledger.public_view("affinity-only")["stage"], "familiar")


func test_guarded_stage_has_priority_over_close_and_familiar() -> void:
	var ledger := RelationshipLedger.new()
	assert_true(ledger.apply_change(
		"lin",
		100,
		100,
		45,
		"发现隐瞒了重要消息",
		"event-1",
	))

	assert_eq(ledger.public_view("lin")["stage"], "guarded")
	assert_eq(ledger.public_view("lin")["label"], "戒备")


func test_public_view_keeps_only_three_most_recent_reasons_newest_first() -> void:
	var ledger := RelationshipLedger.new()

	for index in range(1, 5):
		assert_true(ledger.apply_change(
			"lin",
			1,
			0,
			0,
			"原因%d" % index,
			"event-%d" % index,
		))

	assert_eq(
		ledger.public_view("lin")["recent_reasons"],
		["原因4", "原因3", "原因2"],
	)


func test_duplicate_event_does_not_repeat_values_or_reason() -> void:
	var ledger := RelationshipLedger.new()
	assert_true(ledger.apply_change(
		"lin",
		0,
		0,
		30,
		"产生了一次误会",
		"event-1",
	))

	assert_false(ledger.apply_change(
		"lin",
		0,
		0,
		30,
		"产生了一次误会",
		"event-1",
	))

	var view := ledger.public_view("lin")
	assert_eq(view["stage"], "acquainted")
	assert_eq(view["recent_reasons"], ["产生了一次误会"])


func test_overflow_rejection_preserves_state_reason_and_event_id() -> void:
	var cases := [
		{
			"npc_id": "affinity-overflow",
			"base": [1.0e308, 0.0, 0.0],
			"overflow": [1.0e308, 0.0, 0.0],
			"recovery": [-1.0e308, 0.0, 0.0],
		},
		{
			"npc_id": "trust-overflow",
			"base": [0.0, 1.0e308, 0.0],
			"overflow": [0.0, 1.0e308, 0.0],
			"recovery": [0.0, -1.0e308, 0.0],
		},
		{
			"npc_id": "guard-overflow",
			"base": [0.0, 0.0, 1.0e308],
			"overflow": [0.0, 0.0, 1.0e308],
			"recovery": [0.0, 0.0, -1.0e308],
		},
	]

	for case in cases:
		var event_log := DomainEventLog.new()
		var ledger := RelationshipLedger.new(event_log)
		var base: Array = case["base"]
		var overflow: Array = case["overflow"]
		var recovery: Array = case["recovery"]
		assert_true(ledger.apply_change(
			case["npc_id"],
			base[0],
			base[1],
			base[2],
			"初始巨大变化",
			"base-event",
		))
		var view_before_overflow := ledger.public_view(case["npc_id"])

		assert_false(ledger.apply_change(
			case["npc_id"],
			overflow[0],
			overflow[1],
			overflow[2],
			"不应记录的溢出变化",
			"retry-event",
		))

		assert_eq(ledger.public_view(case["npc_id"]), view_before_overflow)
		assert_false(event_log.has_event("retry-event", "relationship_ledger"))
		assert_true(ledger.apply_change(
			case["npc_id"],
			recovery[0],
			recovery[1],
			recovery[2],
			"溢出后合法恢复",
			"retry-event",
		))
		assert_eq(
			ledger.public_view(case["npc_id"])["recent_reasons"],
			["溢出后合法恢复", "初始巨大变化"],
		)


func test_invalid_change_is_rejected_without_creating_partial_state() -> void:
	var ledger := RelationshipLedger.new()

	assert_false(ledger.apply_change(
		"lin",
		NAN,
		0,
		0,
		"无效变化",
		"event-1",
	))
	assert_false(ledger.apply_change(
		"lin",
		1,
		0,
		0,
		"",
		"event-2",
	))
	assert_false(ledger.apply_change(
		"lin",
		1,
		0,
		0,
		"缺少事件",
		"",
	))

	assert_eq(ledger.public_view("lin"), {
		"stage": "acquainted",
		"label": "初识",
		"recent_reasons": [],
	})
