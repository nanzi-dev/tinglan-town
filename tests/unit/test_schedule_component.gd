extends GutTest

const SCHEDULE_SCRIPT_PATH := "res://scripts/actors/schedule_component.gd"


func test_each_resident_has_work_home_and_no_empty_schedule_ticks() -> void:
	var script_exists := ResourceLoader.exists(SCHEDULE_SCRIPT_PATH)
	assert_true(script_exists)
	if not script_exists:
		return
	var script := load(SCHEDULE_SCRIPT_PATH) as Script
	assert_not_null(script)
	if script == null:
		return

	var repository := ContentRepository.new()
	assert_true(repository.load_spring())
	var schedules := _items_by_id(repository.schedules, "schedule_id")
	assert_eq(repository.characters.size(), 10)
	for character in repository.characters:
		var schedule_id: String = character["schedule_id"]
		assert_true(schedules.has(schedule_id))
		if not schedules.has(schedule_id):
			continue
		var component: Variant = script.new()
		add_child_autoqfree(component)
		assert_true(component.configure(character, schedules[schedule_id]))

		for work_minute in [540, 900]:
			var work_state: Dictionary = component.state_at(work_minute)
			assert_eq(
				work_state["location_id"],
				character["work_location_id"],
				"%s missed work at minute %d."
				% [character["character_id"], work_minute],
			)
		for sleep_minute in [0, 1380]:
			var sleep_state: Dictionary = component.state_at(sleep_minute)
			assert_eq(
				sleep_state["location_id"],
				character["home_location_id"],
				"%s was not home at minute %d."
				% [character["character_id"], sleep_minute],
			)
			assert_eq(sleep_state["activity"], "sleep")

		for tick in range(144):
			var state: Dictionary = component.state_at(tick * 10)
			assert_ne(
				state.get("location_id", ""),
				"",
				"%s had no location at tick %d."
				% [character["character_id"], tick],
			)


func _items_by_id(items: Array, id_field: String) -> Dictionary:
	var result := {}
	for item in items:
		result[item[id_field]] = item
	return result
