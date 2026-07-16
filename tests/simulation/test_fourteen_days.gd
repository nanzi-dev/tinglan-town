extends GutTest

const GAME_STATE_SCRIPT_PATH := "res://scripts/services/game_state.gd"
const GOLDEN_FIXTURE_PATH := (
	"res://tests/fixtures/fourteen_day_seed_20260716.json"
)
const TEST_SEED := 20260716
const TEST_DAYS := 14


func test_fourteen_days_are_reproducible_and_match_the_golden_summary() -> void:
	var script_exists := ResourceLoader.exists(GAME_STATE_SCRIPT_PATH)
	assert_true(script_exists)
	if not script_exists:
		return
	var script := load(GAME_STATE_SCRIPT_PATH) as Script
	assert_not_null(script)
	if script == null:
		return

	var first: Dictionary = script.new().simulate_days(TEST_SEED, TEST_DAYS)
	var second: Dictionary = script.new().simulate_days(TEST_SEED, TEST_DAYS)
	assert_eq(
		JSON.stringify(first).sha256_text(),
		JSON.stringify(second).sha256_text(),
	)
	assert_eq(first["seed"], TEST_SEED)
	assert_eq(first["days"], TEST_DAYS)
	assert_eq(first["unique_agents"], 10)
	assert_gt(first["encounters"], 0)
	assert_gt(first["task_changes"], 0)
	assert_gt(first["relationship_changes"], 0)
	assert_eq(first["final_agents"].size(), 10)
	assert_gt(first["encounter_event_ids"].size(), 0)
	assert_true(
		first["encounter_event_ids"][0].begins_with("encounter:"),
	)
	for batch_count in first["social_batches_per_day"]:
		assert_between(batch_count, 30, 60)

	var fixture_exists := ResourceLoader.exists(GOLDEN_FIXTURE_PATH)
	assert_true(fixture_exists)
	if not fixture_exists:
		return
	var fixture: Dictionary = _load_json_fixture(GOLDEN_FIXTURE_PATH)
	var serialized_first: Dictionary = JSON.parse_string(
		JSON.stringify(first),
	)
	assert_eq(serialized_first, fixture)


func _load_json_fixture(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
