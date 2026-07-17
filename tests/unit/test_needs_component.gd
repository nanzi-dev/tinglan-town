extends GutTest

const NEEDS_SCRIPT_PATH := "res://scripts/actors/needs_component.gd"


func test_paused_needs_do_not_change() -> void:
	var needs := _new_needs_component()
	if needs == null:
		return
	var before: Dictionary = needs.get_levels()

	needs.set_paused(true)
	needs.advance_minutes(90)

	assert_eq(needs.get_levels(), before)


func test_one_offscreen_tick_matches_three_logic_ticks() -> void:
	var aggregate := _new_needs_component()
	var incremental := _new_needs_component()
	if aggregate == null or incremental == null:
		return

	aggregate.advance_minutes(30)
	for tick in range(3):
		incremental.advance_minutes(10)

	var aggregate_levels: Dictionary = aggregate.get_levels()
	var incremental_levels: Dictionary = incremental.get_levels()
	assert_eq(aggregate_levels.keys(), incremental_levels.keys())
	for need_id in aggregate_levels:
		assert_almost_eq(
			aggregate_levels[need_id],
			incremental_levels[need_id],
			0.001,
			"Offscreen settlement differed for %s." % need_id,
		)


func test_serialized_needs_restore_levels_and_pause_state() -> void:
	var source := _new_needs_component()
	var restored := _new_needs_component()
	if source == null or restored == null:
		return
	source.advance_minutes(75)
	source.set_paused(true)
	var snapshot: Dictionary = source.to_dict()

	assert_true(restored.has_method("restore"))
	if not restored.has_method("restore"):
		return
	assert_true(restored.restore(snapshot))

	assert_eq(restored.get_levels(), snapshot["levels"])
	assert_true(restored.is_paused())


func _new_needs_component() -> Node:
	var script_exists := ResourceLoader.exists(NEEDS_SCRIPT_PATH)
	assert_true(script_exists)
	if not script_exists:
		return null
	var script := load(NEEDS_SCRIPT_PATH) as Script
	assert_not_null(script)
	if script == null:
		return null
	var component := script.new() as Node
	add_child_autoqfree(component)
	return component
