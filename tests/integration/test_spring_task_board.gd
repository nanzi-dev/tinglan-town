extends GutTest


func test_all_spring_task_templates_complete_and_reward_through_task_board() -> void:
	var repository := ContentRepository.new()
	assert_true(repository.load_spring())

	var board := TaskBoard.new()
	var accepted := 0
	var rewarded := 0
	var completed_rule_types := {}
	for template in repository.task_templates:
		if board.add_task_template(template, "accepted"):
			accepted += 1
		else:
			continue
		var rule: Dictionary = template["completion_rules"][0]
		var result := board.complete_task(
			template["template_id"],
			"spring-task-event-%s" % template["template_id"],
			{"facts": [rule.duplicate(true)]},
		)
		if result["reward"] == template["reward"]:
			rewarded += 1
			completed_rule_types[rule["type"]] = true
		assert_eq(board.task_status(template["template_id"]), "rewarded")

	assert_eq(accepted, 20)
	assert_eq(rewarded, 20)
	assert_eq(completed_rule_types.keys().size(), 10)
