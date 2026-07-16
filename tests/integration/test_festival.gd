extends GutTest

const FESTIVAL_SCRIPT_PATH := "res://scripts/core/festival_manager.gd"


func test_festival_triggers_only_on_spring_day_twelve_at_eighteen_hundred() -> void:
	var manager: Variant = _manager()
	if manager == null:
		return
	var context := _context(60, "voting", 50)

	var early: Dictionary = manager.trigger_if_due(
		"spring",
		12,
		1079,
		context,
	)
	assert_false(early["triggered"])
	assert_eq(early["reason"], "not_due")

	var result: Dictionary = manager.trigger_if_due(
		"spring",
		12,
		1080,
		context,
	)
	assert_true(result["triggered"])
	assert_true(result["completed"])

	var repeated: Dictionary = manager.trigger_if_due(
		"spring",
		12,
		1080,
		context,
	)
	assert_false(repeated["triggered"])
	assert_eq(repeated["reason"], "already_completed")


func test_low_medium_and_high_preparation_change_display_but_all_complete() -> void:
	var cases := [
		{
			"context": _context(0, "proposed", 0),
			"branch_id": "low",
			"decoration_level": "simple",
			"attendance": "small",
			"dialogue_tone": "improvised_but_warm",
		},
		{
			"context": _context(40, "voting", 50),
			"branch_id": "medium",
			"decoration_level": "complete",
			"attendance": "community",
			"dialogue_tone": "relaxed_and_festive",
		},
		{
			"context": _context(80, "completed", 100),
			"branch_id": "high",
			"decoration_level": "abundant",
			"attendance": "full_town",
			"dialogue_tone": "grateful_and_celebratory",
		},
	]

	for case in cases:
		var manager: Variant = _manager()
		if manager == null:
			return
		var result: Dictionary = manager.trigger_if_due(
			"spring",
			12,
			1080,
			case["context"],
		)

		assert_true(result["triggered"])
		assert_true(result["completed"])
		assert_eq(result["outcome"], "completed")
		assert_false(result["allows_failure"])
		assert_eq(result["branch_id"], case["branch_id"])
		assert_eq(
			result["display"],
			{
				"decoration_level": case["decoration_level"],
				"attendance": case["attendance"],
				"dialogue_tone": case["dialogue_tone"],
			},
		)
		assert_eq(
			result["completed_event"]["event_type"],
			"festival_completed",
		)
		assert_eq(
			result["completed_event"]["structured_result"]["branch_id"],
			case["branch_id"],
		)


func test_project_stage_and_promise_fulfillment_affect_outcome_score() -> void:
	var modest_manager: Variant = _manager()
	var strong_manager: Variant = _manager()
	if modest_manager == null or strong_manager == null:
		return

	var modest: Dictionary = modest_manager.trigger_if_due(
		"spring",
		12,
		1080,
		_context(60, "proposed", 0),
	)
	var strong: Dictionary = strong_manager.trigger_if_due(
		"spring",
		12,
		1080,
		_context(60, "completed", 100),
	)

	assert_lt(modest["outcome_score"], strong["outcome_score"])
	assert_eq(modest["factor_scores"]["preparation_level"], 60.0)
	assert_eq(modest["factor_scores"]["community_project_stage"], 0.0)
	assert_eq(strong["factor_scores"]["community_project_stage"], 100.0)
	assert_eq(
		strong["factor_scores"]["player_resident_promise_fulfillment"],
		100.0,
	)


func _context(
	preparation_level: int,
	project_stage: String,
	promise_fulfillment: int,
) -> Dictionary:
	return {
		"preparation_level": preparation_level,
		"community_project_stage": project_stage,
		"player_resident_promise_fulfillment": promise_fulfillment,
	}


func _manager() -> Variant:
	var script_exists := ResourceLoader.exists(FESTIVAL_SCRIPT_PATH)
	assert_true(script_exists, "FestivalManager script must exist.")
	if not script_exists:
		return null
	var manager_script := load(FESTIVAL_SCRIPT_PATH) as Script
	assert_not_null(manager_script)
	if manager_script == null:
		return null

	var repository := ContentRepository.new()
	assert_true(repository.load_spring())
	return manager_script.new(repository.festival, DomainEventLog.new())
