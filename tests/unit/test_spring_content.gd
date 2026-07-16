extends GutTest

const CONTENT_REPOSITORY_PATH := "res://scripts/core/content_repository.gd"
const CONTENT_FILE_NAMES := [
	"characters.json",
	"schedules.json",
	"tasks.json",
	"locations.json",
	"community_project.json",
	"festival.json",
]
const OBJECTIVE_SCHEMA_CASES := [
	{"type": "collect_item", "fields": ["item_id", "count"]},
	{"type": "deliver_item", "fields": ["item_id", "count", "recipient_id"]},
	{"type": "visit_location", "fields": ["duration_minutes"]},
	{"type": "visit_marker", "fields": ["marker_id"]},
	{"type": "repair_object", "fields": ["object_id"]},
	{"type": "collect_evidence", "fields": ["evidence_id", "count"]},
	{"type": "find_object", "fields": ["object_id"]},
	{"type": "keep_appointment", "fields": ["character_id", "minute"]},
	{"type": "return_item_on_time", "fields": ["item_id"]},
	{"type": "prepare_festival_items", "fields": ["item_id", "count"]},
]
const COMPLETION_RULE_SCHEMA_CASES := [
	{"type": "inventory_count", "fields": ["item_id", "count"]},
	{"type": "delivered_to", "fields": ["character_id", "item_id", "count"]},
	{
		"type": "visited_location",
		"fields": ["location_id", "duration_minutes"],
	},
	{"type": "visited_marker", "fields": ["marker_id"]},
	{"type": "object_repaired", "fields": ["object_id"]},
	{"type": "evidence_count", "fields": ["evidence_id", "count"]},
	{"type": "object_found", "fields": ["object_id"]},
	{"type": "appointment_kept", "fields": ["character_id", "location_id"]},
	{"type": "item_returned", "fields": ["item_id", "location_id"]},
	{"type": "festival_item_count", "fields": ["item_id", "count"]},
]

var _fixture_dir: String


func before_each() -> void:
	_fixture_dir = "user://spring_content_tests/%d" % Time.get_ticks_usec()


func after_each() -> void:
	for file_name in CONTENT_FILE_NAMES:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_fixture_dir.path_join(file_name)),
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fixture_dir))


func test_spring_content_matches_the_approved_scope() -> void:
	var repository = _new_repository()
	if repository == null:
		return

	assert_true(repository.load_spring())
	assert_eq(repository.validation_errors, [])
	assert_eq(repository.characters.size(), 10)
	assert_eq(
		repository.locations.filter(
			func(item): return item["is_interior"],
		).size(),
		10,
	)
	assert_eq(repository.task_templates.size(), 20)
	assert_eq(
		repository.characters.filter(
			func(item): return item["romanceable"],
		).size(),
		2,
	)


func test_spring_characters_match_the_approved_design() -> void:
	var repository = _loaded_repository()
	if repository == null:
		return

	var expected := {
		"shen-yan": {
			"name": "沈砚",
			"age": 29,
			"role": "书屋主人",
			"traits": ["克制", "敏锐", "重承诺"],
			"romanceable": true,
		},
		"lin-xi": {
			"name": "林汐",
			"age": 27,
			"role": "茶馆掌柜",
			"traits": ["温和", "好奇", "善调停"],
			"romanceable": true,
		},
		"zhou-he": {
			"name": "周禾",
			"age": 34,
			"role": "诊所医师",
			"traits": ["稳健", "直接", "有边界"],
			"romanceable": false,
		},
		"lu-qiao": {
			"name": "陆桥",
			"age": 42,
			"role": "木作匠人",
			"traits": ["务实", "固执", "重手艺"],
			"romanceable": false,
		},
		"su-wan": {
			"name": "苏晚",
			"age": 23,
			"role": "杂货铺店员",
			"traits": ["活泼", "细心", "怕冲突"],
			"romanceable": false,
		},
		"gu-yun": {
			"name": "顾云",
			"age": 31,
			"role": "渔人",
			"traits": ["寡言", "可靠", "念旧"],
			"romanceable": false,
		},
		"tang-yu": {
			"name": "唐雨",
			"age": 19,
			"role": "社区中心助理",
			"traits": ["热情", "理想化", "易分心"],
			"romanceable": false,
		},
		"qiao-zhen": {
			"name": "乔贞",
			"age": 56,
			"role": "居民代表",
			"traits": ["审慎", "公平", "记性好"],
			"romanceable": false,
		},
		"he-miao": {
			"name": "何苗",
			"age": 38,
			"role": "菜圃经营者",
			"traits": ["爽朗", "勤勉", "护短"],
			"romanceable": false,
		},
		"xu-deng": {
			"name": "徐灯",
			"age": 46,
			"role": "船夫",
			"traits": ["幽默", "观察入微", "避争执"],
			"romanceable": false,
		},
	}
	var by_id := {}
	for character in repository.characters:
		by_id[character["character_id"]] = character

	assert_eq(by_id.size(), expected.size())
	for character_id in expected:
		var character: Dictionary = by_id[character_id]
		for field in expected[character_id]:
			assert_eq(
				character[field],
				expected[character_id][field],
				"%s.%s differed from the approved design." % [
					character_id,
					field,
				],
			)
		assert_false(character["home_location_id"].is_empty())
		assert_eq(character["schedule_id"], character_id)
		assert_gt(character["capabilities"].size(), 0)
		assert_eq(typeof(character["personal_request"]), TYPE_DICTIONARY)


func test_locations_and_schedules_are_ready_for_later_tasks() -> void:
	var repository = _loaded_repository()
	if repository == null:
		return

	var expected_interior_ids := [
		"bookshop",
		"clinic",
		"community_center",
		"general_store",
		"gu_home",
		"player_home",
		"qiao_home",
		"shen_home",
		"tea_house",
		"workshop",
	]
	var interior_ids := []
	var location_ids := {}
	for location in repository.locations:
		location_ids[location["location_id"]] = true
		if location["is_interior"]:
			interior_ids.append(location["location_id"])
			assert_eq(typeof(location["dimensions"]), TYPE_DICTIONARY)
			assert_eq(typeof(location["floor_color"]), TYPE_STRING)
			assert_eq(typeof(location["wall_color"]), TYPE_STRING)
			assert_eq(typeof(location["furniture_layout"]), TYPE_ARRAY)
			assert_eq(typeof(location["interaction_points"]), TYPE_ARRAY)
	interior_ids.sort()

	assert_eq(repository.locations.size(), 11)
	assert_eq(interior_ids, expected_interior_ids)
	assert_true(location_ids.has("town_outdoors"))
	assert_false(
		repository.locations.filter(
			func(item): return item["location_id"] == "town_outdoors",
		)[0]["is_interior"],
	)
	assert_eq(repository.schedules.size(), 10)

	var character_ids := {}
	for character in repository.characters:
		character_ids[character["character_id"]] = character
	for schedule in repository.schedules:
		var character: Dictionary = character_ids[schedule["character_id"]]
		var scheduled_locations := []
		for entry in schedule["entries"]:
			assert_true(location_ids.has(entry["location_id"]))
			assert_lt(entry["start_minute"], entry["end_minute"])
			scheduled_locations.append(entry["location_id"])
		assert_true(scheduled_locations.has(character["home_location_id"]))
		assert_true(scheduled_locations.has(character["work_location_id"]))

	var expected_task_targets := {
		"workshop": "workshop_stool",
		"bookshop": "bookshop_bookcase",
		"town_outdoors": "dock_mooring_rope",
		"general_store": "missing_ledger_page",
	}
	for location in repository.locations:
		if not expected_task_targets.has(location["location_id"]):
			continue
		assert_true(location.has("task_targets"))
		if not location.has("task_targets"):
			continue
		assert_true(
			location["task_targets"].any(
				func(target):
					return (
						target["target_id"]
						== expected_task_targets[location["location_id"]]
						and target["target_type"] == "object"
					),
			),
		)


func test_tasks_project_and_festival_match_the_approved_design() -> void:
	var repository = _loaded_repository()
	if repository == null:
		return

	var category_counts := {}
	for task in repository.task_templates:
		var category: String = task["category"]
		category_counts[category] = category_counts.get(category, 0) + 1
		for field in [
			"template_id",
			"issuer_id",
			"objective",
			"location_id",
			"deadline",
			"reward",
			"completion_rules",
			"description",
		]:
			assert_true(task.has(field), "%s lacks %s." % [task.get("template_id", "?"), field])

	assert_eq(category_counts, {
		"delivery": 4,
		"festival_preparation": 1,
		"gather": 5,
		"investigation": 2,
		"repair": 3,
		"social_promise": 2,
		"visit": 3,
	})
	assert_eq(repository.community_project["name"], "修复听雨桥")
	assert_eq(
		repository.community_project["stages"].map(
			func(stage): return stage["stage_id"],
		),
		["proposed", "collecting", "voting", "construction", "completed"],
	)
	assert_eq(repository.festival["name"], "上巳水灯会")
	assert_eq(repository.festival["season"], "spring")
	assert_eq(repository.festival["day"], 12)
	assert_eq(repository.festival["start_minute"], 1080)
	assert_eq(repository.festival["preparation_branches"].size(), 3)
	assert_eq(
		repository.festival["preparation_branches"].map(
			func(branch): return branch["branch_id"],
		),
		["low", "medium", "high"],
	)
	var festival_location: Dictionary = repository.locations.filter(
		func(location):
			return (
				location["location_id"]
				== repository.festival["location_id"]
			),
	)[0]
	assert_true(
		festival_location["interaction_points"].any(
			func(point):
				return (
					point["interaction_id"]
					== repository.festival["interaction_point_id"]
				),
		),
	)
	for branch in repository.festival["preparation_branches"]:
		for field in ["decoration_level", "attendance", "dialogue_tone"]:
			assert_false(branch["display"][field].is_empty())
	assert_true(repository.festival.has("outcome_contract"))
	if not repository.festival.has("outcome_contract"):
		return
	var outcome_contract: Dictionary = repository.festival["outcome_contract"]
	assert_eq(
		outcome_contract["factors"].map(
			func(factor): return factor["factor_id"],
		),
		[
			"preparation_level",
			"community_project_stage",
			"player_resident_promise_fulfillment",
		],
	)
	assert_eq(outcome_contract["combination"], "weighted_sum")
	assert_eq(outcome_contract["result_mode"], "display_variation_only")
	assert_false(outcome_contract["allows_failure"])


func test_delivery_completion_rules_match_objective_counts() -> void:
	var repository = _loaded_repository()
	if repository == null:
		return

	for task in repository.task_templates:
		if task["objective"]["type"] != "deliver_item":
			continue
		var rule: Dictionary = task["completion_rules"][0]
		assert_true(
			rule.has("count"),
			"%s delivery rule lacks count." % task["template_id"],
		)
		if rule.has("count"):
			assert_eq(rule["count"], task["objective"]["count"])


func test_validation_rejects_delivery_count_mismatch() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][8]["completion_rules"][0]["count"] = 3
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"task_templates[8].completion_rules[0].count: "
			+ "expected 2 to match objective.count, got 3"
		),
	])


func test_validation_rejects_invalid_task_numeric_ranges() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	var gather: Dictionary = tasks["task_templates"][0]
	gather["objective"]["count"] = -1
	gather["deadline"]["days"] = -2
	gather["deadline"]["minute"] = 2000
	gather["completion_rules"][0]["count"] = -1
	var visit: Dictionary = tasks["task_templates"][9]
	visit["objective"]["duration_minutes"] = 0
	visit["completion_rules"][0]["duration_minutes"] = 0
	tasks["task_templates"][17]["objective"]["minute"] = 2000
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"task_templates[0].objective.count: expected positive integer",
		"task_templates[0].deadline.days: expected non-negative integer",
		"task_templates[0].deadline.minute: expected integer in range 0..1440",
		(
			"task_templates[0].completion_rules[0].count: "
			+ "expected positive integer"
		),
		(
			"task_templates[9].objective.duration_minutes: "
			+ "expected positive integer"
		),
		(
			"task_templates[9].completion_rules[0].duration_minutes: "
			+ "expected positive integer"
		),
		"task_templates[17].objective.minute: expected integer in range 0..1440",
	])


func test_validation_rejects_objective_completion_semantic_mismatches() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][0]["completion_rules"][0]["item_id"] = "tea_shoot"
	tasks["task_templates"][5]["completion_rules"][0]["character_id"] = "gu-yun"
	tasks["task_templates"][9]["completion_rules"][0]["location_id"] = "qiao_home"
	tasks["task_templates"][9]["completion_rules"][0]["duration_minutes"] = 31
	tasks["task_templates"][11]["objective"]["marker_id"] = "tingyu_bridge"
	tasks["task_templates"][15]["completion_rules"][0]["count"] = 2
	tasks["task_templates"][17]["completion_rules"][0]["character_id"] = "shen-yan"
	tasks["task_templates"][18]["completion_rules"][0]["item_id"] = "other_book"
	tasks["task_templates"][19]["completion_rules"][0]["count"] = 11
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"task_templates[0].completion_rules[0].item_id: expected "
			+ "spring_herb to match objective.item_id, got tea_shoot"
		),
		(
			"task_templates[5].completion_rules[0].character_id: expected "
			+ "qiao-zhen to match objective.recipient_id, got gu-yun"
		),
		(
			"task_templates[9].completion_rules[0].location_id: expected "
			+ "clinic to match task.location_id, got qiao_home"
		),
		(
			"task_templates[9].completion_rules[0].duration_minutes: expected "
			+ "30 to match objective.duration_minutes, got 31"
		),
		(
			"task_templates[11].completion_rules[0].marker_id: expected "
			+ "tingyu_bridge to match objective.marker_id, got south_bay_festival"
		),
		(
			"task_templates[15].completion_rules[0].count: expected "
			+ "3 to match objective.count, got 2"
		),
		(
			"task_templates[17].completion_rules[0].character_id: expected "
			+ "lin-xi to match objective.character_id, got shen-yan"
		),
		(
			"task_templates[18].completion_rules[0].item_id: expected "
			+ "annotated_old_book to match objective.item_id, got other_book"
		),
		(
			"task_templates[19].completion_rules[0].count: expected "
			+ "12 to match objective.count, got 11"
		),
	])


func test_validation_rejects_unknown_location_task_target() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][12]["objective"]["object_id"] = "unknown_stool"
	tasks["task_templates"][12]["completion_rules"][0]["object_id"] = (
		"unknown_stool"
	)
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"task_templates[12].objective.object_id: unknown task target "
			+ "'unknown_stool' for location 'workshop'"
		),
		(
			"task_templates[12].completion_rules[0].object_id: "
			+ "unknown task target 'unknown_stool' for location 'workshop'"
		),
	])


func test_validation_rejects_unknown_visit_marker_for_task_location() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][11]["objective"]["marker_id"] = "missing-point"
	tasks["task_templates"][11]["completion_rules"][0]["marker_id"] = (
		"missing-point"
	)
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"task_templates[11].objective.marker_id: unknown interaction point "
			+ "'missing-point' for location 'town_outdoors'"
		),
		(
			"task_templates[11].completion_rules[0].marker_id: "
			+ "unknown interaction point 'missing-point' "
			+ "for location 'town_outdoors'"
		),
	])


func test_validation_rejects_category_objective_type_mismatches() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][0]["category"] = "delivery"
	tasks["task_templates"][5]["category"] = "gather"
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"task_templates[0].objective.type: objective type 'collect_item' "
			+ "is not allowed for category 'delivery'"
		),
		(
			"task_templates[5].objective.type: objective type 'deliver_item' "
			+ "is not allowed for category 'gather'"
		),
	])


func test_validation_reports_schema_and_duplicate_errors_in_order() -> void:
	_prepare_fixture()
	var characters := _read_fixture_json("characters.json")
	characters["characters"].append(
		characters["characters"][4].duplicate(true),
	)
	characters["characters"][2].erase("name")
	characters["characters"][3]["age"] = "42"
	_write_fixture_json("characters.json", characters)

	var locations := _read_fixture_json("locations.json")
	locations["locations"][0]["dimensions"] = []
	_write_fixture_json("locations.json", locations)

	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][0]["objective"] = []
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"characters: expected 10 entries, got 11",
		"characters[2].name: missing required field",
		"characters[3].age: expected integer",
		"characters[10].character_id: duplicate id 'su-wan'",
		"locations[0].dimensions: expected object",
		"task_templates[0].objective: expected object",
	])


func test_validation_rejects_duplicate_task_template_ids() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][1]["template_id"] = (
		tasks["task_templates"][0]["template_id"]
	)
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"task_templates[1].template_id: duplicate id "
			+ "'gather-spring-herbs'"
		),
	])


func test_validation_requires_fields_for_every_objective_type() -> void:
	for schema in OBJECTIVE_SCHEMA_CASES:
		for field in schema["fields"]:
			_prepare_fixture()
			var tasks := _read_fixture_json("tasks.json")
			var task_index := _find_task_index_by_structured_type(
				tasks["task_templates"],
				"objective",
				schema["type"],
			)
			assert_gte(task_index, 0)
			tasks["task_templates"][task_index]["objective"].erase(field)
			_write_fixture_json("tasks.json", tasks)

			var repository = _new_repository(_fixture_dir)
			assert_false(repository.load_spring())
			assert_eq(repository.validation_errors, [
				"task_templates[%d].objective.%s: missing required field"
				% [task_index, field],
			])


func test_validation_requires_fields_for_every_completion_rule_type() -> void:
	for schema in COMPLETION_RULE_SCHEMA_CASES:
		for field in schema["fields"]:
			_prepare_fixture()
			var tasks := _read_fixture_json("tasks.json")
			var task_index := _find_task_index_by_structured_type(
				tasks["task_templates"],
				"completion_rules",
				schema["type"],
			)
			assert_gte(task_index, 0)
			tasks["task_templates"][task_index]["completion_rules"][0].erase(field)
			_write_fixture_json("tasks.json", tasks)

			var repository = _new_repository(_fixture_dir)
			assert_false(repository.load_spring())
			assert_eq(repository.validation_errors, [
				(
					"task_templates[%d].completion_rules[0].%s: "
					+ "missing required field"
				) % [task_index, field],
			])


func test_validation_rejects_unknown_task_object_types() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][0]["objective"]["type"] = "unknown_objective"
	tasks["task_templates"][0]["completion_rules"][0]["type"] = "unknown_rule"
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"task_templates[0].objective.type: unknown type 'unknown_objective'",
		(
			"task_templates[0].completion_rules[0].type: "
			+ "unknown type 'unknown_rule'"
		),
	])


func test_validation_rejects_unknown_completion_rule_location() -> void:
	_prepare_fixture()
	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][9]["completion_rules"][0]["location_id"] = (
		"missing-place"
	)
	_write_fixture_json("tasks.json", tasks)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"task_templates[9].completion_rules[0].location_id: "
			+ "unknown location 'missing-place'"
		),
	])


func test_validation_rejects_unknown_references_and_domain_rules() -> void:
	_prepare_fixture()
	var characters := _read_fixture_json("characters.json")
	characters["characters"][0]["age"] = 17
	_write_fixture_json("characters.json", characters)

	var schedules := _read_fixture_json("schedules.json")
	schedules["schedules"][0]["entries"][0]["location_id"] = "missing-place"
	_write_fixture_json("schedules.json", schedules)

	var tasks := _read_fixture_json("tasks.json")
	tasks["task_templates"][0]["issuer_id"] = "missing-person"
	tasks["task_templates"][1]["location_id"] = "missing-place"
	_write_fixture_json("tasks.json", tasks)

	var project := _read_fixture_json("community_project.json")
	project["community_project"]["stages"].pop_back()
	_write_fixture_json("community_project.json", project)

	var festival := _read_fixture_json("festival.json")
	festival["festival"]["season"] = "summer"
	festival["festival"]["day"] = 11
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"characters[0].age: romanceable characters must be at least 18",
		"schedules[0].entries[0].location_id: unknown location 'missing-place'",
		"task_templates[0].issuer_id: unknown character 'missing-person'",
		"task_templates[1].location_id: unknown location 'missing-place'",
		"community_project.stages: expected 5 stages, got 4",
		"festival: expected spring day 12, got summer day 11",
	])


func test_validation_rejects_unknown_character_schedule() -> void:
	_prepare_fixture()
	var characters := _read_fixture_json("characters.json")
	characters["characters"][0]["schedule_id"] = "missing-schedule"
	_write_fixture_json("characters.json", characters)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"characters[0].schedule_id: unknown schedule 'missing-schedule'",
	])


func test_validation_rejects_invalid_spring_schedule_enums() -> void:
	_prepare_fixture()
	var schedules := _read_fixture_json("schedules.json")
	schedules["schedules"][0]["season"] = "winter"
	schedules["schedules"][1]["day_type"] = "weekly_market"
	_write_fixture_json("schedules.json", schedules)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"schedules[0].season: expected 'spring', got 'winter'",
		(
			"schedules[1].day_type: expected one of "
			+ "[normal, festival, personal_event], got 'weekly_market'"
		),
	])


func test_validation_rejects_overlapping_schedule_entries() -> void:
	_prepare_fixture()
	var schedules := _read_fixture_json("schedules.json")
	schedules["schedules"][0]["entries"][1]["start_minute"] = 420
	_write_fixture_json("schedules.json", schedules)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"schedules[0].entries[1].start_minute: expected at least 480 "
			+ "to preserve order without overlap, got 420"
		),
	])


func test_validation_requires_festival_to_start_at_1800() -> void:
	_prepare_fixture()
	var festival := _read_fixture_json("festival.json")
	festival["festival"]["start_minute"] = 1020
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"festival.start_minute: expected 1080 (18:00), got 1020",
	])


func test_validation_requires_festival_outcome_contract_fields() -> void:
	_prepare_fixture()
	var festival := _read_fixture_json("festival.json")
	festival["festival"]["outcome_contract"].erase("combination")
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"festival.outcome_contract.combination: missing required field",
	])


func test_validation_rejects_wrong_festival_outcome_contract_types() -> void:
	_prepare_fixture()
	var festival := _read_fixture_json("festival.json")
	festival["festival"]["outcome_contract"]["factors"] = {}
	festival["festival"]["outcome_contract"]["allows_failure"] = "false"
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"festival.outcome_contract.factors: expected array",
		"festival.outcome_contract.allows_failure: expected boolean",
	])


func test_validation_rejects_illegal_festival_outcome_contract_values() -> void:
	_prepare_fixture()
	var festival := _read_fixture_json("festival.json")
	var contract: Dictionary = festival["festival"]["outcome_contract"]
	contract["factors"][0]["factor_id"] = "weather"
	contract["factors"][0]["weight"] = 0
	contract["combination"] = "first_match"
	contract["result_mode"] = "success_or_failure"
	contract["allows_failure"] = true
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"festival.outcome_contract.factors[0].weight: "
			+ "expected positive integer"
		),
		(
			"festival.outcome_contract.factors: expected ordered factors "
			+ "[preparation_level, community_project_stage, "
			+ "player_resident_promise_fulfillment]"
		),
		(
			"festival.outcome_contract.combination: expected "
			+ "'weighted_sum', got 'first_match'"
		),
		(
			"festival.outcome_contract.result_mode: expected "
			+ "'display_variation_only', got 'success_or_failure'"
		),
		"festival.outcome_contract.allows_failure: expected false",
	])


func test_validation_rejects_unknown_festival_interaction_point() -> void:
	_prepare_fixture()
	var festival := _read_fixture_json("festival.json")
	festival["festival"]["interaction_point_id"] = "missing-point"
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"festival.interaction_point_id: unknown interaction point "
			+ "'missing-point' for location 'town_outdoors'"
		),
	])


func test_validation_rejects_duplicate_or_nonstandard_festival_branch_ids() -> void:
	_prepare_fixture()
	var festival := _read_fixture_json("festival.json")
	festival["festival"]["preparation_branches"][0]["branch_id"] = "medium"
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"festival.preparation_branches[1].branch_id: "
			+ "duplicate id 'medium'"
		),
		(
			"festival.preparation_branches: expected ordered branch ids "
			+ "[low, medium, high]"
		),
	])


func test_validation_rejects_festival_branch_range_gaps_and_bad_bounds() -> void:
	_prepare_fixture()
	var festival := _read_fixture_json("festival.json")
	var branches: Array = festival["festival"]["preparation_branches"]
	branches[0]["minimum_preparation"] = 1
	branches[1]["minimum_preparation"] = 41
	branches[2]["maximum_preparation"] = 99
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"festival.preparation_branches[0].minimum_preparation: "
			+ "expected 0, got 1"
		),
		(
			"festival.preparation_branches[1].minimum_preparation: "
			+ "expected 40 after previous maximum, got 41"
		),
		(
			"festival.preparation_branches[2].maximum_preparation: "
			+ "expected 100, got 99"
		),
	])


func test_validation_requires_complete_nonempty_festival_branch_display() -> void:
	_prepare_fixture()
	var festival := _read_fixture_json("festival.json")
	var branches: Array = festival["festival"]["preparation_branches"]
	branches[0]["display"].erase("attendance")
	branches[1]["display"]["dialogue_tone"] = ""
	_write_fixture_json("festival.json", festival)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"festival.preparation_branches[0].display.attendance: "
			+ "missing required field"
		),
		(
			"festival.preparation_branches[1].display.dialogue_tone: "
			+ "expected non-empty string"
		),
	])


func test_validation_rejects_wrong_project_stage_order() -> void:
	_prepare_fixture()
	var project := _read_fixture_json("community_project.json")
	var stages: Array = project["community_project"]["stages"]
	var second_stage = stages[1]
	stages[1] = stages[2]
	stages[2] = second_stage
	_write_fixture_json("community_project.json", project)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		(
			"community_project.stages: expected ordered stages "
			+ "[proposed, collecting, voting, construction, completed]"
		),
	])


func test_validation_rejects_wrong_project_stage_order_number() -> void:
	_prepare_fixture()
	var project := _read_fixture_json("community_project.json")
	project["community_project"]["stages"][0]["order"] = 5
	_write_fixture_json("community_project.json", project)

	var repository = _new_repository(_fixture_dir)
	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors, [
		"community_project.stages[0].order: expected 1, got 5",
	])


func test_malformed_json_failure_is_atomic_and_alias_safe() -> void:
	_prepare_fixture()
	var repository = _new_repository(_fixture_dir)
	assert_true(repository.load_spring())

	var exposed_characters: Array = repository.characters
	exposed_characters[0]["name"] = "外部改动"
	var changed_characters := _read_fixture_json("characters.json")
	changed_characters["characters"][0]["name"] = "半加载数据"
	_write_fixture_json("characters.json", changed_characters)
	_write_fixture_text("schedules.json", "{\n  \"schedules\": [")

	assert_false(repository.load_spring())
	assert_eq(repository.validation_errors.size(), 1)
	assert_true(
		repository.validation_errors[0].begins_with("schedules.json:"),
	)
	assert_true(
		repository.validation_errors[0].contains(": invalid JSON:"),
	)
	assert_eq(repository.characters[0]["name"], "沈砚")

	var exposed_errors: Array = repository.validation_errors
	exposed_errors.clear()
	assert_eq(repository.validation_errors.size(), 1)


func test_validation_failure_preserves_the_last_successful_snapshot() -> void:
	_prepare_fixture()
	var repository = _new_repository(_fixture_dir)
	assert_true(repository.load_spring())

	var exposed_tasks: Array = repository.task_templates
	exposed_tasks[0]["issuer_id"] = "external-change"
	var changed_characters := _read_fixture_json("characters.json")
	changed_characters["characters"][0]["name"] = "半加载数据"
	_write_fixture_json("characters.json", changed_characters)
	var changed_tasks := _read_fixture_json("tasks.json")
	changed_tasks["task_templates"][0]["issuer_id"] = "missing-person"
	_write_fixture_json("tasks.json", changed_tasks)

	assert_false(repository.load_spring())
	assert_true(
		repository.validation_errors.has(
			"task_templates[0].issuer_id: unknown character 'missing-person'",
		),
	)
	assert_eq(repository.characters[0]["name"], "沈砚")
	assert_eq(repository.task_templates[0]["issuer_id"], "zhou-he")


func test_all_public_content_values_are_deep_copy_snapshots() -> void:
	var repository = _loaded_repository()
	if repository == null:
		return

	var exposed_schedules: Array = repository.schedules
	var exposed_locations: Array = repository.locations
	var exposed_project: Dictionary = repository.community_project
	var exposed_festival: Dictionary = repository.festival
	exposed_schedules[0]["entries"][0]["location_id"] = "external-change"
	exposed_locations[0]["dimensions"]["width"] = 999
	exposed_project["stages"][0]["stage_id"] = "external-change"
	exposed_festival["preparation_branches"][0]["branch_id"] = "external-change"

	assert_eq(
		repository.schedules[0]["entries"][0]["location_id"],
		"shen_home",
	)
	assert_eq(repository.locations[0]["dimensions"]["width"], 8)
	assert_eq(
		repository.community_project["stages"][0]["stage_id"],
		"proposed",
	)
	assert_eq(
		repository.festival["preparation_branches"][0]["branch_id"],
		"low",
	)


func _new_repository(base_path: String = "res://content/spring"):
	var repository_script = load(CONTENT_REPOSITORY_PATH)
	assert_not_null(
		repository_script,
		"ContentRepository script must exist.",
	)
	if repository_script == null:
		return null
	return repository_script.new(base_path)


func _loaded_repository():
	var repository = _new_repository()
	if repository == null:
		return null
	var loaded: bool = repository.load_spring()
	assert_true(loaded)
	if not loaded:
		return null
	return repository


func _prepare_fixture() -> void:
	assert_eq(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_fixture_dir),
		),
		OK,
	)
	for file_name in CONTENT_FILE_NAMES:
		var source := FileAccess.open(
			"res://content/spring".path_join(file_name),
			FileAccess.READ,
		)
		assert_not_null(source)
		if source == null:
			continue
		var contents := source.get_as_text()
		source.close()
		var destination := FileAccess.open(
			_fixture_dir.path_join(file_name),
			FileAccess.WRITE,
		)
		assert_not_null(destination)
		if destination == null:
			continue
		destination.store_string(contents)
		destination.close()


func _read_fixture_json(file_name: String) -> Dictionary:
	var file := FileAccess.open(
		_fixture_dir.path_join(file_name),
		FileAccess.READ,
	)
	assert_not_null(file)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	return parsed


func _write_fixture_json(file_name: String, value: Dictionary) -> void:
	var file := FileAccess.open(
		_fixture_dir.path_join(file_name),
		FileAccess.WRITE,
	)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(JSON.stringify(value, "  "))
	file.close()


func _write_fixture_text(file_name: String, text: String) -> void:
	var file := FileAccess.open(
		_fixture_dir.path_join(file_name),
		FileAccess.WRITE,
	)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _find_task_index_by_structured_type(
	tasks: Array,
	field: String,
	type_id: String,
) -> int:
	for index in tasks.size():
		if field == "objective":
			if tasks[index]["objective"]["type"] == type_id:
				return index
		elif tasks[index]["completion_rules"][0]["type"] == type_id:
			return index
	return -1
