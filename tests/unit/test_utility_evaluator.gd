extends GutTest


func test_hunger_prefers_eating_over_chatting() -> void:
	var evaluator := UtilityEvaluator.new()
	var actions := [
		{"id": "eat", "base_utility": 0.2, "need_effects": {"hunger": -0.8}},
		{"id": "chat", "base_utility": 0.5, "need_effects": {"social": -0.4}},
	]

	var scores := evaluator.score_all(
		{"hunger": 0.95, "social": 0.2},
		actions,
		{},
	)

	assert_gt(scores["eat"], scores["chat"])


func test_score_uses_the_complete_fixed_formula() -> void:
	var evaluator := UtilityEvaluator.new()
	var actions := [{
		"id": "deliver",
		"base_utility": 0.2,
		"need_effects": {
			"hunger": -0.5,
			"energy": 0.25,
		},
		"schedule_fit": 0.3,
		"relationship_context": 0.4,
		"task_priority": 0.7,
		"travel_cost": 0.2,
		"risk_cost": 0.1,
	}]

	var scores := evaluator.score_all(
		{"hunger": 0.8, "energy": 0.4},
		actions,
		{},
	)

	assert_almost_eq(scores["deliver"], 1.6, 0.000001)


func test_missing_and_malformed_values_are_treated_as_zero() -> void:
	var evaluator := UtilityEvaluator.new()
	var actions := [
		{
			"id": "safe",
			"base_utility": "high",
			"need_effects": {
				"hunger": "lots",
				"unknown": -1.0,
			},
			"schedule_fit": NAN,
			"travel_cost": INF,
		},
		{"id": "empty"},
		{"base_utility": 99.0},
		"not-an-action",
	]

	var scores := evaluator.score_all(
		{"hunger": "urgent", "unknown": NAN},
		actions,
		{"safe": {"task_priority": false}},
	)

	assert_eq(scores, {"safe": 0.0, "empty": 0.0})


func test_same_inputs_produce_identical_scores() -> void:
	var evaluator := UtilityEvaluator.new()
	var needs := {"hunger": 0.6}
	var actions := [
		{"id": "rest", "base_utility": 0.3},
		{"id": "eat", "base_utility": 0.1, "need_effects": {"hunger": -0.5}},
	]
	var context := {
		"eat": {
			"schedule_fit": 0.2,
			"travel_cost": 0.1,
		},
	}

	assert_eq(
		evaluator.score_all(needs, actions, context),
		evaluator.score_all(needs, actions, context),
	)


func test_equal_scores_are_inserted_in_lexicographic_action_order() -> void:
	var evaluator := UtilityEvaluator.new()
	var actions := [
		{"id": "zeta", "base_utility": 0.5},
		{"id": "alpha", "base_utility": 0.5},
		{"id": "middle", "base_utility": 0.5},
	]
	var original_actions := actions.duplicate(true)

	var scores := evaluator.score_all({}, actions, {})

	assert_eq(scores.keys(), ["alpha", "middle", "zeta"])
	assert_eq(actions, original_actions)


func test_need_contribution_overflow_skips_the_entire_action() -> void:
	var evaluator := UtilityEvaluator.new()
	var actions := [
		{"id": "overflow", "need_effects": {"hunger": -1.0e308}},
		{"id": "safe", "base_utility": 0.5},
	]

	var scores := evaluator.score_all({"hunger": 1.0e308}, actions, {})

	assert_push_error("Utility score overflowed for action 'overflow'")
	assert_false(scores.has("overflow"))
	assert_eq(scores["safe"], 0.5)


func test_score_accumulation_overflow_skips_the_entire_action() -> void:
	var evaluator := UtilityEvaluator.new()
	var actions := [
		{
			"id": "overflow",
			"base_utility": 1.0e308,
			"schedule_fit": 1.0e308,
		},
		{"id": "safe", "base_utility": 0.5},
	]

	var scores := evaluator.score_all({}, actions, {})

	assert_push_error("Utility score overflowed for action 'overflow'")
	assert_false(scores.has("overflow"))
	assert_eq(scores["safe"], 0.5)


func test_duplicate_action_ids_are_rejected_independent_of_input_order() -> void:
	var evaluator := UtilityEvaluator.new()
	var first_order := [
		{"id": "conflict", "base_utility": 0.9},
		{"id": "safe", "base_utility": 0.5},
		{"id": "conflict", "base_utility": 0.1},
	]
	var second_order := [
		{"id": "conflict", "base_utility": 0.1},
		{"id": "safe", "base_utility": 0.5},
		{"id": "conflict", "base_utility": 0.9},
	]

	var first_scores := evaluator.score_all({}, first_order, {})
	assert_push_error("Duplicate action id 'conflict'")
	var second_scores := evaluator.score_all({}, second_order, {})
	assert_push_error("Duplicate action id 'conflict'")

	assert_eq(first_scores, {"safe": 0.5})
	assert_eq(second_scores, first_scores)


func test_need_effects_are_accumulated_in_lexicographic_need_order() -> void:
	var evaluator := UtilityEvaluator.new()
	var ascending_effects := {}
	ascending_effects["alpha"] = -1.0e308
	ascending_effects["middle"] = -1.0e308
	ascending_effects["zeta"] = 1.0e308
	var reverse_effects := {}
	reverse_effects["zeta"] = 1.0e308
	reverse_effects["middle"] = -1.0e308
	reverse_effects["alpha"] = -1.0e308
	var original_reverse_effects := reverse_effects.duplicate(true)
	var needs := {"alpha": 1.0, "middle": 1.0, "zeta": 1.0}

	var ascending_scores := evaluator.score_all(
		needs,
		[{"id": "overflow", "need_effects": ascending_effects}],
		{},
	)
	assert_push_error("Utility score overflowed for action 'overflow'")
	var reverse_scores := evaluator.score_all(
		needs,
		[{"id": "overflow", "need_effects": reverse_effects}],
		{},
	)

	assert_push_error("Utility score overflowed for action 'overflow'")
	assert_eq(ascending_scores, {})
	assert_eq(reverse_scores, ascending_scores)
	assert_eq(reverse_effects, original_reverse_effects)
