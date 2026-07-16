extends GutTest

const PROJECT_SCRIPT_PATH := "res://scripts/core/community_project.gd"


func test_resources_and_support_votes_advance_the_five_project_stages() -> void:
	var project: Variant = _project()
	if project == null:
		return

	assert_eq(project.current_stage(), "proposed")
	assert_true(project.begin_collecting("project-collecting"))
	assert_eq(project.current_stage(), "collecting")

	assert_true(project.contribute_resources(
		"project-contribution-1",
		{"repair_timber": 29, "lime": 12},
		499,
	))
	assert_eq(project.current_stage(), "collecting")
	assert_true(project.contribute_resources(
		"project-contribution-2",
		{"repair_timber": 1},
		1,
	))
	assert_eq(project.current_stage(), "voting")

	for index in range(1, 7):
		assert_true(project.submit_vote(
			"project-vote-%d" % index,
			"resident-%d" % index,
			"support",
		))
	assert_eq(project.current_stage(), "construction")
	assert_true(project.snapshot()["route_closed"])

	assert_true(project.advance_construction_day("construction-day-1"))
	assert_eq(project.current_stage(), "construction")
	assert_true(project.advance_construction_day("construction-day-2"))
	assert_eq(project.current_stage(), "completed")
	assert_false(project.snapshot()["route_closed"])


func test_duplicate_project_vote_event_and_repeat_voter_count_only_once() -> void:
	var project: Variant = _project_at_voting()
	if project == null:
		return

	assert_true(project.submit_vote("vote-lin-1", "lin-xi", "support"))
	assert_false(project.submit_vote("vote-lin-1", "lin-xi", "support"))
	assert_false(project.submit_vote("vote-lin-2", "lin-xi", "oppose"))

	var snapshot: Dictionary = project.snapshot()
	assert_eq(snapshot["votes"], {
		"support": 1,
		"oppose": 0,
		"abstain": 0,
	})
	assert_eq(snapshot["voter_count"], 1)
	assert_eq(project.current_stage(), "voting")


func test_local_vote_rule_uses_personality_relationship_evidence_and_resource_gap() -> void:
	var project: Variant = _project_at_voting()
	if project == null:
		return

	assert_eq(project.resolve_vote_candidate({
		"personality_weight": 0.2,
		"proposer_relationship": 0.1,
		"evidence_strength": 0.8,
		"resource_gap": 0.1,
	}), "support")
	assert_eq(project.resolve_vote_candidate({
		"personality_weight": -0.4,
		"proposer_relationship": -0.4,
		"evidence_strength": 0.1,
		"resource_gap": 0.8,
	}), "oppose")
	assert_eq(project.resolve_vote_candidate({
		"personality_weight": 0.0,
		"proposer_relationship": 0.0,
		"evidence_strength": 0.2,
		"resource_gap": 0.1,
	}), "abstain")


func test_memoria_may_choose_only_a_legal_vote_candidate() -> void:
	var project: Variant = _project_at_voting()
	if project == null:
		return
	var supportive_context := {
		"personality_weight": 0.2,
		"proposer_relationship": 0.2,
		"evidence_strength": 0.8,
		"resource_gap": 0.0,
	}

	assert_eq(
		project.resolve_vote_candidate(supportive_context, "oppose"),
		"oppose",
	)
	assert_eq(
		project.resolve_vote_candidate(supportive_context, "construction"),
		"support",
	)
	assert_false(project.submit_vote(
		"illegal-vote",
		"lin-xi",
		"construction",
	))
	assert_eq(project.current_stage(), "voting")


func _project_at_voting() -> Variant:
	var project: Variant = _project()
	if project == null:
		return null
	assert_true(project.begin_collecting("project-collecting"))
	assert_true(project.contribute_resources(
		"project-all-resources",
		{"repair_timber": 30, "lime": 12},
		500,
	))
	assert_eq(project.current_stage(), "voting")
	return project


func _project() -> Variant:
	var script_exists := ResourceLoader.exists(PROJECT_SCRIPT_PATH)
	assert_true(script_exists, "CommunityProject script must exist.")
	if not script_exists:
		return null
	var project_script := load(PROJECT_SCRIPT_PATH) as Script
	assert_not_null(project_script)
	if project_script == null:
		return null

	var repository := ContentRepository.new()
	assert_true(repository.load_spring())
	return project_script.new(repository.community_project, DomainEventLog.new())
