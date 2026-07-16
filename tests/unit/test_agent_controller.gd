extends GutTest


func test_unknown_memoria_action_uses_best_local_candidate() -> void:
	var controller := AgentController.new()
	var candidates := [
		{"id": "work", "utility": 0.9},
		{"id": "rest", "utility": 0.4},
	]

	var result := controller.resolve_decision(
		candidates,
		{"candidate_action_id": "invent-item"},
	)

	assert_eq(result.id, "work")
	assert_eq(result.source, "local_fallback")


func test_legal_memoria_action_is_selected_from_candidates() -> void:
	var controller := AgentController.new()
	var candidates := [
		{"id": "work", "utility": 0.9},
		{"id": "rest", "utility": 0.4},
	]

	var result := controller.resolve_decision(
		candidates,
		{"candidate_action_id": "rest"},
	)

	assert_eq(result.id, "rest")
	assert_eq(result.source, "memoria")


func test_missing_or_malformed_memoria_decision_uses_local_fallback() -> void:
	var controller := AgentController.new()
	var candidates := [
		{"id": "work", "utility": 0.9},
		{"id": "rest", "utility": 0.4},
	]
	var invalid_decisions: Array[Variant] = [
		null,
		{},
		{"candidate_action_id": ""},
		{"candidate_action_id": 17},
		"not-a-decision",
	]

	for invalid_decision in invalid_decisions:
		var result := controller.resolve_decision(candidates, invalid_decision)
		assert_eq(result.id, "work")
		assert_eq(result.source, "local_fallback")


func test_equal_local_utility_uses_lexicographically_smallest_id() -> void:
	var controller := AgentController.new()
	var candidates := [
		{"id": "work", "utility": 0.5},
		{"id": "chat", "utility": 0.5},
		{"id": "eat", "utility": 0.5},
	]

	var result := controller.resolve_decision(candidates, {})

	assert_eq(result.id, "chat")


func test_nearby_but_distinct_utility_still_selects_the_higher_value() -> void:
	var controller := AgentController.new()
	var candidates := [
		{"id": "zeta", "utility": 0.50000001},
		{"id": "alpha", "utility": 0.5},
	]

	var result := controller.resolve_decision(candidates, {})

	assert_eq(result.id, "zeta")


func test_result_is_a_deep_copy_and_does_not_pollute_candidates() -> void:
	var controller := AgentController.new()
	var candidates := [{
		"id": "work",
		"utility": 0.9,
		"metadata": {"location": "dock"},
	}]

	var result := controller.resolve_decision(candidates, {})
	result.metadata.location = "market"

	assert_false(candidates[0].has("source"))
	assert_eq(candidates[0].metadata.location, "dock")


func test_malformed_candidates_are_ignored_without_crashing() -> void:
	var controller := AgentController.new()
	var candidates := [
		"not-a-candidate",
		{"utility": 99.0},
		{"id": "", "utility": 99.0},
		{"id": "zeta", "utility": "high"},
		{"id": "alpha"},
	]

	var result := controller.resolve_decision(candidates, null)

	assert_eq(result.id, "alpha")
	assert_eq(controller.resolve_decision([], null), {})


func test_memoria_cannot_select_a_duplicate_candidate_id() -> void:
	var controller := AgentController.new()
	var first_order := [
		{"id": "conflict", "utility": 0.9},
		{"id": "safe", "utility": 0.5},
		{"id": "conflict", "utility": 0.1},
	]
	var second_order := [
		{"id": "conflict", "utility": 0.1},
		{"id": "safe", "utility": 0.5},
		{"id": "conflict", "utility": 0.9},
	]
	var memoria_decision := {"candidate_action_id": "conflict"}

	var first_result := controller.resolve_decision(first_order, memoria_decision)
	assert_push_error("Duplicate candidate id 'conflict'")
	var second_result := controller.resolve_decision(second_order, memoria_decision)
	assert_push_error("Duplicate candidate id 'conflict'")

	assert_eq(first_result, {"id": "safe", "utility": 0.5, "source": "local_fallback"})
	assert_eq(second_result, first_result)


func test_local_fallback_cannot_select_a_duplicate_candidate_id() -> void:
	var controller := AgentController.new()
	var first_order := [
		{"id": "conflict", "utility": 0.9},
		{"id": "safe", "utility": 0.5},
		{"id": "conflict", "utility": 0.8},
	]
	var second_order := [
		{"id": "conflict", "utility": 0.8},
		{"id": "safe", "utility": 0.5},
		{"id": "conflict", "utility": 0.9},
	]

	var first_result := controller.resolve_decision(first_order, {})
	assert_push_error("Duplicate candidate id 'conflict'")
	var second_result := controller.resolve_decision(second_order, {})
	assert_push_error("Duplicate candidate id 'conflict'")

	assert_eq(first_result.id, "safe")
	assert_eq(first_result.source, "local_fallback")
	assert_eq(second_result, first_result)
