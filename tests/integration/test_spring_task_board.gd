extends GutTest


func test_all_spring_task_templates_register_with_task_board() -> void:
	var repository := ContentRepository.new()
	assert_true(repository.load_spring())

	var board := TaskBoard.new()
	var accepted := 0
	for template in repository.task_templates:
		if board.add_task_template(template):
			accepted += 1

	assert_eq(accepted, 20)
