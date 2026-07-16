class_name ContentRepository
extends RefCounted

const CONTENT_FILES := [
	["characters.json", "characters", TYPE_ARRAY],
	["schedules.json", "schedules", TYPE_ARRAY],
	["tasks.json", "task_templates", TYPE_ARRAY],
	["locations.json", "locations", TYPE_ARRAY],
	["community_project.json", "community_project", TYPE_DICTIONARY],
	["festival.json", "festival", TYPE_DICTIONARY],
]
const REQUIRED_STAGE_IDS := [
	"proposed",
	"collecting",
	"voting",
	"construction",
	"completed",
]
const VALID_SPRING_DAY_TYPES := [
	"normal",
	"festival",
	"personal_event",
]
const REQUIRED_FESTIVAL_OUTCOME_FACTOR_IDS := [
	"preparation_level",
	"community_project_stage",
	"player_resident_promise_fulfillment",
]
const REQUIRED_TASK_CATEGORY_COUNTS := {
	"gather": 5,
	"delivery": 4,
	"visit": 3,
	"repair": 3,
	"investigation": 2,
	"social_promise": 2,
	"festival_preparation": 1,
}
const OBJECTIVE_REQUIRED_FIELDS := {
	"collect_item": ["item_id", "count"],
	"deliver_item": ["item_id", "count", "recipient_id"],
	"visit_location": ["duration_minutes"],
	"visit_marker": ["marker_id"],
	"repair_object": ["object_id"],
	"collect_evidence": ["evidence_id", "count"],
	"find_object": ["object_id"],
	"keep_appointment": ["character_id", "minute"],
	"return_item_on_time": ["item_id"],
	"prepare_festival_items": ["item_id", "count"],
}
const COMPLETION_RULE_REQUIRED_FIELDS := {
	"inventory_count": ["item_id", "count"],
	"delivered_to": ["character_id", "item_id", "count"],
	"visited_location": ["location_id", "duration_minutes"],
	"visited_marker": ["marker_id"],
	"object_repaired": ["object_id"],
	"evidence_count": ["evidence_id", "count"],
	"object_found": ["object_id"],
	"appointment_kept": ["character_id", "location_id"],
	"item_returned": ["item_id", "location_id"],
	"festival_item_count": ["item_id", "count"],
}
const OBJECTIVE_COMPLETION_RULE_TYPES := {
	"collect_item": "inventory_count",
	"deliver_item": "delivered_to",
	"visit_location": "visited_location",
	"visit_marker": "visited_marker",
	"repair_object": "object_repaired",
	"collect_evidence": "evidence_count",
	"find_object": "object_found",
	"keep_appointment": "appointment_kept",
	"return_item_on_time": "item_returned",
	"prepare_festival_items": "festival_item_count",
}

var characters: Array:
	get:
		return _characters.duplicate(true)
var schedules: Array:
	get:
		return _schedules.duplicate(true)
var task_templates: Array:
	get:
		return _task_templates.duplicate(true)
var locations: Array:
	get:
		return _locations.duplicate(true)
var community_project: Dictionary:
	get:
		return _community_project.duplicate(true)
var festival: Dictionary:
	get:
		return _festival.duplicate(true)
var validation_errors: Array:
	get:
		return _validation_errors.duplicate(true)

var _base_path: String
var _characters: Array = []
var _schedules: Array = []
var _task_templates: Array = []
var _locations: Array = []
var _community_project: Dictionary = {}
var _festival: Dictionary = {}
var _validation_errors: Array = []


func _init(base_path: String = "res://content/spring") -> void:
	_base_path = base_path


func load_spring() -> bool:
	var loaded := {}
	var errors := []
	for file_spec in CONTENT_FILES:
		var file_name: String = file_spec[0]
		var root_field: String = file_spec[1]
		var expected_type: int = file_spec[2]
		var path := _base_path.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("%s: unable to open file" % file_name)
			continue

		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		file.close()
		if parse_error != OK:
			errors.append(
				"%s:%d: invalid JSON: %s" % [
					file_name,
					parser.get_error_line(),
					parser.get_error_message(),
				],
			)
			continue
		if typeof(parser.data) != TYPE_DICTIONARY:
			errors.append("%s: root must be an object" % file_name)
			continue
		if not parser.data.has(root_field):
			errors.append("%s: missing field '%s'" % [file_name, root_field])
			continue
		if typeof(parser.data[root_field]) != expected_type:
			errors.append(
				"%s.%s: expected %s" % [
					file_name,
					root_field,
					type_string(expected_type),
				],
			)
			continue
		loaded[root_field] = parser.data[root_field]

	if not errors.is_empty():
		_validation_errors = errors.duplicate(true)
		return false

	_validate_content(loaded, errors)
	if not errors.is_empty():
		_validation_errors = errors.duplicate(true)
		return false

	_characters = loaded["characters"].duplicate(true)
	_schedules = loaded["schedules"].duplicate(true)
	_task_templates = loaded["task_templates"].duplicate(true)
	_locations = loaded["locations"].duplicate(true)
	_community_project = loaded["community_project"].duplicate(true)
	_festival = loaded["festival"].duplicate(true)
	_validation_errors = []
	return true


func _validate_content(content: Dictionary, errors: Array) -> void:
	var character_ids := _validate_characters(content["characters"], errors)
	var location_ids := _validate_locations(content["locations"], errors)
	_validate_character_locations(
		content["characters"],
		location_ids,
		errors,
	)
	var schedule_ids := _validate_schedules(
		content["schedules"],
		character_ids,
		location_ids,
		errors,
	)
	_validate_character_schedules(
		content["characters"],
		schedule_ids,
		errors,
	)
	_validate_tasks(
		content["task_templates"],
		character_ids,
		location_ids,
		errors,
	)
	_validate_community_project(
		content["community_project"],
		character_ids,
		location_ids,
		errors,
	)
	_validate_festival(content["festival"], location_ids, errors)


func _validate_characters(items: Array, errors: Array) -> Dictionary:
	if items.size() != 10:
		errors.append(
			"characters: expected 10 entries, got %d" % items.size(),
		)

	var ids := {}
	var romanceable_count := 0
	for index in items.size():
		var path := "characters[%d]" % index
		if typeof(items[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % path)
			continue
		var character: Dictionary = items[index]
		_require_fields(
			character,
			[
				"character_id",
				"name",
				"age",
				"role",
				"traits",
				"romanceable",
				"home_location_id",
				"work_location_id",
				"schedule_id",
				"capabilities",
				"personal_request",
			],
			path,
			errors,
		)
		var character_id := _validate_id_field(
			character,
			"character_id",
			path,
			ids,
			errors,
		)
		for field in [
			"name",
			"role",
			"home_location_id",
			"work_location_id",
			"schedule_id",
		]:
			_validate_nonempty_string_field(character, field, path, errors)
		var age_valid := _normalize_integer_field(
			character,
			"age",
			path,
			errors,
		)
		_validate_string_array_field(
			character,
			"traits",
			path,
			errors,
		)
		_validate_string_array_field(
			character,
			"capabilities",
			path,
			errors,
		)
		var romanceable_valid := _validate_bool_field(
			character,
			"romanceable",
			path,
			errors,
		)
		if romanceable_valid and character["romanceable"]:
			romanceable_count += 1
			if age_valid and character["age"] < 18:
				errors.append(
					"%s.age: romanceable characters must be at least 18" % path,
				)
		if character.has("personal_request"):
			if typeof(character["personal_request"]) != TYPE_DICTIONARY:
				errors.append("%s.personal_request: expected object" % path)
			else:
				var request: Dictionary = character["personal_request"]
				_require_fields(
					request,
					["type", "topic"],
					"%s.personal_request" % path,
					errors,
				)
				_validate_nonempty_string_field(
					request,
					"type",
					"%s.personal_request" % path,
					errors,
				)
				_validate_nonempty_string_field(
					request,
					"topic",
					"%s.personal_request" % path,
					errors,
				)
		if not character_id.is_empty():
			ids[character_id] = true

	if romanceable_count != 2:
		errors.append(
			"characters: expected 2 romanceable entries, got %d"
			% romanceable_count,
		)
	return ids


func _validate_locations(items: Array, errors: Array) -> Dictionary:
	if items.size() != 11:
		errors.append(
			"locations: expected 11 entries, got %d" % items.size(),
		)

	var ids := {}
	var interior_count := 0
	for index in items.size():
		var path := "locations[%d]" % index
		if typeof(items[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % path)
			continue
		var location: Dictionary = items[index]
		_require_fields(
			location,
			[
				"location_id",
				"name",
				"is_interior",
				"purpose",
				"dimensions",
				"floor_color",
				"wall_color",
				"furniture_layout",
				"interaction_points",
			],
			path,
			errors,
		)
		var location_id := _validate_id_field(
			location,
			"location_id",
			path,
			ids,
			errors,
		)
		for field in ["name", "purpose", "floor_color", "wall_color"]:
			_validate_nonempty_string_field(location, field, path, errors)
		if _validate_bool_field(location, "is_interior", path, errors):
			if location["is_interior"]:
				interior_count += 1
		if location.has("dimensions"):
			if typeof(location["dimensions"]) != TYPE_DICTIONARY:
				errors.append("%s.dimensions: expected object" % path)
			else:
				var dimensions: Dictionary = location["dimensions"]
				_require_fields(
					dimensions,
					["width", "depth", "height"],
					"%s.dimensions" % path,
					errors,
				)
				for field in ["width", "depth", "height"]:
					if _normalize_integer_field(
						dimensions,
						field,
						"%s.dimensions" % path,
						errors,
					) and dimensions[field] <= 0:
						errors.append(
							"%s.dimensions.%s: expected positive integer"
							% [path, field],
						)
		_validate_layout_array(
			location,
			"furniture_layout",
			"furniture_id",
			path,
			errors,
		)
		_validate_layout_array(
			location,
			"interaction_points",
			"interaction_id",
			path,
			errors,
		)
		var task_target_ids := _validate_task_targets(
			location,
			path,
			errors,
		)
		if not location_id.is_empty():
			var interaction_point_ids := {}
			if typeof(location.get("interaction_points", null)) == TYPE_ARRAY:
				for point in location["interaction_points"]:
					if (
						typeof(point) == TYPE_DICTIONARY
						and typeof(point.get("interaction_id", null)) == TYPE_STRING
						and not point["interaction_id"].is_empty()
					):
						interaction_point_ids[point["interaction_id"]] = true
			ids[location_id] = {
				"interaction_point_ids": interaction_point_ids,
				"task_target_ids": task_target_ids,
			}

	if interior_count != 10:
		errors.append(
			"locations: expected 10 interiors, got %d" % interior_count,
		)
	return ids


func _validate_character_locations(
	items: Array,
	location_ids: Dictionary,
	errors: Array,
) -> void:
	for index in items.size():
		if typeof(items[index]) != TYPE_DICTIONARY:
			continue
		var character: Dictionary = items[index]
		for field in ["home_location_id", "work_location_id"]:
			var location_id = character.get(field, null)
			if (
				typeof(location_id) == TYPE_STRING
				and not location_id.is_empty()
				and not location_ids.has(location_id)
			):
				errors.append(
					"characters[%d].%s: unknown location '%s'"
					% [index, field, location_id],
				)


func _validate_schedules(
	items: Array,
	character_ids: Dictionary,
	location_ids: Dictionary,
	errors: Array,
) -> Dictionary:
	if items.size() != 10:
		errors.append(
			"schedules: expected 10 entries, got %d" % items.size(),
		)

	var ids := {}
	for index in items.size():
		var path := "schedules[%d]" % index
		if typeof(items[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % path)
			continue
		var schedule: Dictionary = items[index]
		_require_fields(
			schedule,
			["schedule_id", "character_id", "season", "day_type", "entries"],
			path,
			errors,
		)
		var schedule_id := _validate_id_field(
			schedule,
			"schedule_id",
			path,
			ids,
			errors,
		)
		for field in ["character_id", "season", "day_type"]:
			_validate_nonempty_string_field(schedule, field, path, errors)
		var season = schedule.get("season", null)
		if (
			typeof(season) == TYPE_STRING
			and not season.is_empty()
			and season != "spring"
		):
			errors.append(
				"%s.season: expected 'spring', got '%s'" % [path, season],
			)
		var day_type = schedule.get("day_type", null)
		if (
			typeof(day_type) == TYPE_STRING
			and not day_type.is_empty()
			and not VALID_SPRING_DAY_TYPES.has(day_type)
		):
			errors.append(
				(
					"%s.day_type: expected one of "
					+ "[normal, festival, personal_event], got '%s'"
				) % [path, day_type],
			)
		var character_id = schedule.get("character_id", null)
		if (
			typeof(character_id) == TYPE_STRING
			and not character_id.is_empty()
			and not character_ids.has(character_id)
		):
			errors.append(
				"%s.character_id: unknown character '%s'"
				% [path, character_id],
			)
		if schedule.has("entries"):
			if typeof(schedule["entries"]) != TYPE_ARRAY:
				errors.append("%s.entries: expected array" % path)
			else:
				var entries: Array = schedule["entries"]
				if entries.is_empty():
					errors.append("%s.entries: must not be empty" % path)
				var previous_end_minute = null
				for entry_index in entries.size():
					var entry_path := "%s.entries[%d]" % [path, entry_index]
					_validate_schedule_entry(
						entries[entry_index],
						entry_path,
						location_ids,
						errors,
					)
					if typeof(entries[entry_index]) != TYPE_DICTIONARY:
						previous_end_minute = null
						continue
					var entry: Dictionary = entries[entry_index]
					if (
						typeof(entry.get("start_minute", null)) != TYPE_INT
						or typeof(entry.get("end_minute", null)) != TYPE_INT
						or entry["start_minute"] < 0
						or entry["end_minute"] > 1440
						or entry["start_minute"] >= entry["end_minute"]
					):
						previous_end_minute = null
						continue
					if (
						previous_end_minute != null
						and entry["start_minute"] < previous_end_minute
					):
						errors.append(
							(
								"%s.start_minute: expected at least %d "
								+ "to preserve order without overlap, got %d"
							) % [
								entry_path,
								previous_end_minute,
								entry["start_minute"],
							],
						)
					previous_end_minute = entry["end_minute"]
		if not schedule_id.is_empty():
			ids[schedule_id] = character_id
	return ids


func _validate_schedule_entry(
	value: Variant,
	path: String,
	location_ids: Dictionary,
	errors: Array,
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected object" % path)
		return
	var entry: Dictionary = value
	_require_fields(
		entry,
		["start_minute", "end_minute", "location_id", "activity"],
		path,
		errors,
	)
	var start_valid := _normalize_integer_field(
		entry,
		"start_minute",
		path,
		errors,
	)
	var end_valid := _normalize_integer_field(
		entry,
		"end_minute",
		path,
		errors,
	)
	if (
		start_valid
		and end_valid
		and (
			entry["start_minute"] < 0
			or entry["end_minute"] > 1440
			or entry["start_minute"] >= entry["end_minute"]
		)
	):
		errors.append(
			"%s: expected 0 <= start_minute < end_minute <= 1440" % path,
		)
	for field in ["location_id", "activity"]:
		_validate_nonempty_string_field(entry, field, path, errors)
	var location_id = entry.get("location_id", null)
	if (
		typeof(location_id) == TYPE_STRING
		and not location_id.is_empty()
		and not location_ids.has(location_id)
	):
		errors.append(
			"%s.location_id: unknown location '%s'" % [path, location_id],
		)


func _validate_character_schedules(
	characters_value: Array,
	schedule_ids: Dictionary,
	errors: Array,
) -> void:
	for index in characters_value.size():
		if typeof(characters_value[index]) != TYPE_DICTIONARY:
			continue
		var character: Dictionary = characters_value[index]
		var schedule_id = character.get("schedule_id", null)
		if (
			typeof(schedule_id) != TYPE_STRING
			or schedule_id.is_empty()
		):
			continue
		if not schedule_ids.has(schedule_id):
			errors.append(
				"characters[%d].schedule_id: unknown schedule '%s'"
				% [index, schedule_id],
			)
			continue
		var character_id = character.get("character_id", null)
		if schedule_ids[schedule_id] != character_id:
			errors.append(
				"characters[%d].schedule_id: schedule '%s' belongs to '%s'"
				% [index, schedule_id, schedule_ids[schedule_id]],
			)


func _validate_tasks(
	items: Array,
	character_ids: Dictionary,
	location_ids: Dictionary,
	errors: Array,
) -> void:
	if items.size() != 20:
		errors.append(
			"task_templates: expected 20 entries, got %d" % items.size(),
		)

	var ids := {}
	var category_counts := {}
	for category in REQUIRED_TASK_CATEGORY_COUNTS:
		category_counts[category] = 0
	for index in items.size():
		var path := "task_templates[%d]" % index
		if typeof(items[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % path)
			continue
		var task: Dictionary = items[index]
		_require_fields(
			task,
			[
				"template_id",
				"category",
				"issuer_id",
				"objective",
				"location_id",
				"deadline",
				"reward",
				"completion_rules",
				"description",
			],
			path,
			errors,
		)
		var template_id := _validate_id_field(
			task,
			"template_id",
			path,
			ids,
			errors,
		)
		if not template_id.is_empty():
			ids[template_id] = true
		for field in [
			"category",
			"issuer_id",
			"location_id",
			"description",
		]:
			_validate_nonempty_string_field(task, field, path, errors)
		var category = task.get("category", null)
		if typeof(category) == TYPE_STRING and not category.is_empty():
			if not REQUIRED_TASK_CATEGORY_COUNTS.has(category):
				errors.append("%s.category: unknown category '%s'" % [path, category])
			else:
				category_counts[category] += 1
		var issuer_id = task.get("issuer_id", null)
		if (
			typeof(issuer_id) == TYPE_STRING
			and not issuer_id.is_empty()
			and not character_ids.has(issuer_id)
		):
			errors.append(
				"%s.issuer_id: unknown character '%s'" % [path, issuer_id],
			)
		var location_id = task.get("location_id", null)
		if (
			typeof(location_id) == TYPE_STRING
			and not location_id.is_empty()
			and not location_ids.has(location_id)
		):
			errors.append(
				"%s.location_id: unknown location '%s'" % [path, location_id],
			)
		if task.has("objective"):
			_validate_structured_object(
				task["objective"],
				"%s.objective" % path,
				OBJECTIVE_REQUIRED_FIELDS,
				character_ids,
				location_ids,
				errors,
			)
		if task.has("deadline"):
			_validate_deadline(task["deadline"], "%s.deadline" % path, errors)
		if task.has("reward"):
			_validate_reward(task["reward"], "%s.reward" % path, errors)
		if task.has("completion_rules"):
			_validate_completion_rules(
				task["completion_rules"],
				"%s.completion_rules" % path,
				character_ids,
				location_ids,
				errors,
			)
		_validate_task_target_references(
			task,
			path,
			location_ids,
			errors,
		)
		_validate_task_semantics(task, path, errors)
	for category in REQUIRED_TASK_CATEGORY_COUNTS:
		if category_counts[category] != REQUIRED_TASK_CATEGORY_COUNTS[category]:
			errors.append(
				"task_templates: expected %d '%s' entries, got %d"
				% [
					REQUIRED_TASK_CATEGORY_COUNTS[category],
					category,
					category_counts[category],
				],
			)


func _validate_community_project(
	project: Dictionary,
	character_ids: Dictionary,
	location_ids: Dictionary,
	errors: Array,
) -> void:
	_require_fields(
		project,
		[
			"project_id",
			"name",
			"proposer_id",
			"location_id",
			"resource_thresholds",
			"stages",
		],
		"community_project",
		errors,
	)
	for field in ["project_id", "name", "proposer_id", "location_id"]:
		_validate_nonempty_string_field(
			project,
			field,
			"community_project",
			errors,
		)
	var proposer_id = project.get("proposer_id", null)
	if (
		typeof(proposer_id) == TYPE_STRING
		and not proposer_id.is_empty()
		and not character_ids.has(proposer_id)
	):
		errors.append(
			"community_project.proposer_id: unknown character '%s'"
			% proposer_id,
		)
	var location_id = project.get("location_id", null)
	if (
		typeof(location_id) == TYPE_STRING
		and not location_id.is_empty()
		and not location_ids.has(location_id)
	):
		errors.append(
			"community_project.location_id: unknown location '%s'"
			% location_id,
		)
	if project.has("resource_thresholds"):
		_validate_project_thresholds(project["resource_thresholds"], errors)
	if not project.has("stages"):
		return
	if typeof(project["stages"]) != TYPE_ARRAY:
		errors.append("community_project.stages: expected array")
		return

	var stages: Array = project["stages"]
	if stages.size() != 5:
		errors.append(
			"community_project.stages: expected 5 stages, got %d"
			% stages.size(),
		)
	var actual_stage_ids := []
	var order_errors := []
	var stages_have_schema := true
	for index in stages.size():
		var path := "community_project.stages[%d]" % index
		if typeof(stages[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % path)
			stages_have_schema = false
			continue
		var stage: Dictionary = stages[index]
		_require_fields(stage, ["stage_id", "order", "summary"], path, errors)
		_validate_nonempty_string_field(stage, "stage_id", path, errors)
		_validate_nonempty_string_field(stage, "summary", path, errors)
		if not _normalize_integer_field(stage, "order", path, errors):
			stages_have_schema = false
		elif stage["order"] != index + 1:
			order_errors.append(
				"%s.order: expected %d, got %d"
				% [path, index + 1, stage["order"]],
			)
		actual_stage_ids.append(stage.get("stage_id", ""))
	if (
		stages.size() == REQUIRED_STAGE_IDS.size()
		and stages_have_schema
		and actual_stage_ids != REQUIRED_STAGE_IDS
	):
		errors.append(
			(
				"community_project.stages: expected ordered stages "
				+ "[proposed, collecting, voting, construction, completed]"
			),
		)
	else:
		errors.append_array(order_errors)


func _validate_festival(
	festival_value: Dictionary,
	location_ids: Dictionary,
	errors: Array,
) -> void:
	_require_fields(
		festival_value,
		[
			"festival_id",
			"name",
			"season",
			"day",
			"start_minute",
			"location_id",
			"interaction_point_id",
			"outcome_contract",
			"preparation_branches",
		],
		"festival",
		errors,
	)
	for field in [
		"festival_id",
		"name",
		"season",
		"location_id",
		"interaction_point_id",
	]:
		_validate_nonempty_string_field(
			festival_value,
			field,
			"festival",
			errors,
		)
	var day_valid := _normalize_integer_field(
		festival_value,
		"day",
		"festival",
		errors,
	)
	var start_valid := _normalize_integer_field(
		festival_value,
		"start_minute",
		"festival",
		errors,
	)
	if start_valid and festival_value["start_minute"] != 1080:
		errors.append(
			"festival.start_minute: expected 1080 (18:00), got %d"
			% festival_value["start_minute"],
		)
	var season = festival_value.get("season", null)
	if (
		typeof(season) == TYPE_STRING
		and day_valid
		and (season != "spring" or festival_value["day"] != 12)
	):
		errors.append(
			"festival: expected spring day 12, got %s day %d"
			% [season, festival_value["day"]],
		)
	var location_id = festival_value.get("location_id", null)
	if (
		typeof(location_id) == TYPE_STRING
		and not location_id.is_empty()
		and not location_ids.has(location_id)
	):
		errors.append(
			"festival.location_id: unknown location '%s'" % location_id,
		)
	var interaction_point_id = festival_value.get("interaction_point_id", null)
	if (
		typeof(location_id) == TYPE_STRING
		and not location_id.is_empty()
		and location_ids.has(location_id)
		and typeof(interaction_point_id) == TYPE_STRING
		and not interaction_point_id.is_empty()
		and not location_ids[location_id]["interaction_point_ids"].has(
			interaction_point_id,
		)
	):
		errors.append(
			(
				"festival.interaction_point_id: unknown interaction point "
				+ "'%s' for location '%s'"
			) % [interaction_point_id, location_id],
		)
	if festival_value.has("outcome_contract"):
		_validate_festival_outcome_contract(
			festival_value["outcome_contract"],
			errors,
		)
	if not festival_value.has("preparation_branches"):
		return
	if typeof(festival_value["preparation_branches"]) != TYPE_ARRAY:
		errors.append("festival.preparation_branches: expected array")
		return
	var branches: Array = festival_value["preparation_branches"]
	if branches.size() != 3:
		errors.append(
			"festival.preparation_branches: expected 3 entries, got %d"
			% branches.size(),
		)
	var branch_ids := []
	var seen_branch_ids := {}
	var branches_have_ids := true
	var previous_maximum = null
	for index in branches.size():
		var path := "festival.preparation_branches[%d]" % index
		if typeof(branches[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % path)
			branches_have_ids = false
			previous_maximum = null
			continue
		var branch: Dictionary = branches[index]
		_require_fields(
			branch,
			[
				"branch_id",
				"minimum_preparation",
				"maximum_preparation",
				"display",
			],
			path,
			errors,
		)
		if _validate_nonempty_string_field(branch, "branch_id", path, errors):
			var branch_id: String = branch["branch_id"]
			if seen_branch_ids.has(branch_id):
				errors.append(
					"%s.branch_id: duplicate id '%s'" % [path, branch_id],
				)
			else:
				seen_branch_ids[branch_id] = true
			branch_ids.append(branch_id)
		else:
			branches_have_ids = false
		var minimum_valid := _normalize_integer_field(
			branch,
			"minimum_preparation",
			path,
			errors,
		)
		var maximum_valid := _normalize_integer_field(
			branch,
			"maximum_preparation",
			path,
			errors,
		)
		if minimum_valid and maximum_valid:
			var minimum: int = branch["minimum_preparation"]
			var maximum: int = branch["maximum_preparation"]
			if minimum < 0 or maximum > 100 or minimum > maximum:
				errors.append(
					(
						"%s: expected 0 <= minimum_preparation "
						+ "<= maximum_preparation <= 100"
					) % path,
				)
			if index == 0 and minimum != 0:
				errors.append(
					"%s.minimum_preparation: expected 0, got %d"
					% [path, minimum],
				)
			elif previous_maximum != null and minimum != previous_maximum + 1:
				errors.append(
					(
						"%s.minimum_preparation: expected %d "
						+ "after previous maximum, got %d"
					) % [path, previous_maximum + 1, minimum],
				)
			if index == branches.size() - 1 and maximum != 100:
				errors.append(
					"%s.maximum_preparation: expected 100, got %d"
					% [path, maximum],
				)
			previous_maximum = maximum
		else:
			previous_maximum = null
		if branch.has("display"):
			if typeof(branch["display"]) != TYPE_DICTIONARY:
				errors.append("%s.display: expected object" % path)
			else:
				var display: Dictionary = branch["display"]
				_require_fields(
					display,
					["decoration_level", "attendance", "dialogue_tone"],
					"%s.display" % path,
					errors,
				)
				for field in [
					"decoration_level",
					"attendance",
					"dialogue_tone",
				]:
					_validate_nonempty_string_field(
						display,
						field,
						"%s.display" % path,
						errors,
					)
	if (
		branches.size() == 3
		and branches_have_ids
		and branch_ids != ["low", "medium", "high"]
	):
		errors.append(
			(
				"festival.preparation_branches: expected ordered branch ids "
				+ "[low, medium, high]"
			),
		)


func _validate_festival_outcome_contract(
	value: Variant,
	errors: Array,
) -> void:
	var path := "festival.outcome_contract"
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected object" % path)
		return
	var contract: Dictionary = value
	_require_fields(
		contract,
		["factors", "combination", "result_mode", "allows_failure"],
		path,
		errors,
	)
	if contract.has("factors"):
		if typeof(contract["factors"]) != TYPE_ARRAY:
			errors.append("%s.factors: expected array" % path)
		else:
			var factors: Array = contract["factors"]
			if factors.size() != REQUIRED_FESTIVAL_OUTCOME_FACTOR_IDS.size():
				errors.append(
					"%s.factors: expected 3 entries, got %d"
					% [path, factors.size()],
				)
			var factor_ids := []
			var factors_have_schema := true
			for index in factors.size():
				var factor_path := "%s.factors[%d]" % [path, index]
				if typeof(factors[index]) != TYPE_DICTIONARY:
					errors.append("%s: expected object" % factor_path)
					factors_have_schema = false
					continue
				var factor: Dictionary = factors[index]
				_require_fields(
					factor,
					["factor_id", "weight"],
					factor_path,
					errors,
				)
				if _validate_nonempty_string_field(
					factor,
					"factor_id",
					factor_path,
					errors,
				):
					factor_ids.append(factor["factor_id"])
				else:
					factors_have_schema = false
				if _normalize_integer_field(
					factor,
					"weight",
					factor_path,
					errors,
				) and factor["weight"] <= 0:
					errors.append(
						"%s.weight: expected positive integer" % factor_path,
					)
			if (
				factors.size() == REQUIRED_FESTIVAL_OUTCOME_FACTOR_IDS.size()
				and factors_have_schema
				and factor_ids != REQUIRED_FESTIVAL_OUTCOME_FACTOR_IDS
			):
				errors.append(
					(
						"%s.factors: expected ordered factors "
						+ "[preparation_level, community_project_stage, "
						+ "player_resident_promise_fulfillment]"
					) % path,
				)
	if _validate_nonempty_string_field(
		contract,
		"combination",
		path,
		errors,
	) and contract["combination"] != "weighted_sum":
		errors.append(
			"%s.combination: expected 'weighted_sum', got '%s'"
			% [path, contract["combination"]],
		)
	if _validate_nonempty_string_field(
		contract,
		"result_mode",
		path,
		errors,
	) and contract["result_mode"] != "display_variation_only":
		errors.append(
			"%s.result_mode: expected 'display_variation_only', got '%s'"
			% [path, contract["result_mode"]],
		)
	if _validate_bool_field(
		contract,
		"allows_failure",
		path,
		errors,
	) and contract["allows_failure"]:
		errors.append("%s.allows_failure: expected false" % path)


func _validate_project_thresholds(value: Variant, errors: Array) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("community_project.resource_thresholds: expected object")
		return
	var thresholds: Dictionary = value
	_require_fields(
		thresholds,
		["materials", "funds", "support_votes"],
		"community_project.resource_thresholds",
		errors,
	)
	for field in ["funds", "support_votes"]:
		if _normalize_integer_field(
			thresholds,
			field,
			"community_project.resource_thresholds",
			errors,
		) and thresholds[field] <= 0:
			errors.append(
				"community_project.resource_thresholds.%s: expected positive integer"
				% field,
			)
	if not thresholds.has("materials"):
		return
	if typeof(thresholds["materials"]) != TYPE_DICTIONARY:
		errors.append(
			"community_project.resource_thresholds.materials: expected object",
		)
		return
	var materials: Dictionary = thresholds["materials"]
	_require_fields(
		materials,
		["repair_timber", "lime"],
		"community_project.resource_thresholds.materials",
		errors,
	)
	for field in ["repair_timber", "lime"]:
		if _normalize_integer_field(
			materials,
			field,
			"community_project.resource_thresholds.materials",
			errors,
		) and materials[field] <= 0:
			errors.append(
				(
					"community_project.resource_thresholds.materials.%s: "
					+ "expected positive integer"
				) % field,
			)


func _validate_deadline(
	value: Variant,
	path: String,
	errors: Array,
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected object" % path)
		return
	var deadline: Dictionary = value
	_require_fields(deadline, ["days", "minute"], path, errors)
	if (
		_normalize_integer_field(deadline, "days", path, errors)
		and deadline["days"] < 0
	):
		errors.append("%s.days: expected non-negative integer" % path)
	if (
		_normalize_integer_field(deadline, "minute", path, errors)
		and (deadline["minute"] < 0 or deadline["minute"] > 1440)
	):
		errors.append("%s.minute: expected integer in range 0..1440" % path)


func _validate_reward(
	value: Variant,
	path: String,
	errors: Array,
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected object" % path)
		return
	var reward: Dictionary = value
	if reward.is_empty():
		errors.append("%s: must not be empty" % path)
	for reward_id in reward:
		if typeof(reward_id) != TYPE_STRING or reward_id.is_empty():
			errors.append("%s: reward ids must be non-empty strings" % path)
			continue
		var amount = reward[reward_id]
		if not _is_number(amount) or float(amount) < 0.0:
			errors.append("%s.%s: expected non-negative number" % [path, reward_id])
		elif typeof(amount) == TYPE_FLOAT and amount == floor(amount):
			reward[reward_id] = int(amount)


func _validate_structured_object(
	value: Variant,
	path: String,
	required_fields_by_type: Dictionary,
	character_ids: Dictionary,
	location_ids: Dictionary,
	errors: Array,
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected object" % path)
		return
	var object: Dictionary = value
	_require_fields(object, ["type"], path, errors)
	if not _validate_nonempty_string_field(object, "type", path, errors):
		return
	var type_id: String = object["type"]
	if not required_fields_by_type.has(type_id):
		errors.append("%s.type: unknown type '%s'" % [path, type_id])
		return
	_require_fields(object, required_fields_by_type[type_id], path, errors)
	for field in ["count", "duration_minutes", "minute"]:
		if not object.has(field):
			continue
		if not _normalize_integer_field(object, field, path, errors):
			continue
		if field in ["count", "duration_minutes"] and object[field] <= 0:
			errors.append("%s.%s: expected positive integer" % [path, field])
		elif field == "minute" and (
			object[field] < 0 or object[field] > 1440
		):
			errors.append("%s.minute: expected integer in range 0..1440" % path)
	for field in ["item_id", "evidence_id", "object_id", "marker_id"]:
		if object.has(field):
			_validate_nonempty_string_field(object, field, path, errors)
	for field in ["character_id", "recipient_id"]:
		if not object.has(field):
			continue
		if not _validate_nonempty_string_field(object, field, path, errors):
			continue
		var character_id = object.get(field, null)
		if not character_ids.has(character_id):
			errors.append(
				"%s.%s: unknown character '%s'"
				% [path, field, character_id],
			)
	if object.has("location_id"):
		if _validate_nonempty_string_field(
			object,
			"location_id",
			path,
			errors,
		):
			var location_id: String = object["location_id"]
			if not location_ids.has(location_id):
				errors.append(
					"%s.location_id: unknown location '%s'"
					% [path, location_id],
				)


func _validate_completion_rules(
	value: Variant,
	path: String,
	character_ids: Dictionary,
	location_ids: Dictionary,
	errors: Array,
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: expected array" % path)
		return
	var rules: Array = value
	if rules.is_empty():
		errors.append("%s: must not be empty" % path)
	for index in rules.size():
		_validate_structured_object(
			rules[index],
			"%s[%d]" % [path, index],
			COMPLETION_RULE_REQUIRED_FIELDS,
			character_ids,
			location_ids,
			errors,
		)


func _validate_task_semantics(
	task: Dictionary,
	path: String,
	errors: Array,
) -> void:
	if (
		typeof(task.get("objective", null)) != TYPE_DICTIONARY
		or typeof(task.get("completion_rules", null)) != TYPE_ARRAY
		or task["completion_rules"].is_empty()
	):
		return
	var objective: Dictionary = task["objective"]
	var objective_type = objective.get("type", "")
	if not OBJECTIVE_COMPLETION_RULE_TYPES.has(objective_type):
		return
	var expected_rule_type: String = OBJECTIVE_COMPLETION_RULE_TYPES[objective_type]
	for index in task["completion_rules"].size():
		if typeof(task["completion_rules"][index]) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = task["completion_rules"][index]
		var rule_type = rule.get("type", "")
		if not COMPLETION_RULE_REQUIRED_FIELDS.has(rule_type):
			continue
		var rule_path := "%s.completion_rules[%d]" % [path, index]
		if rule_type != expected_rule_type:
			errors.append(
				"%s.type: expected '%s' for objective type '%s', got '%s'"
				% [rule_path, expected_rule_type, objective_type, rule_type],
			)
			continue
		match objective_type:
			"collect_item":
				_compare_task_semantic_field(
					rule, rule_path, "item_id",
					objective, "objective", "item_id", errors,
				)
				_compare_task_semantic_field(
					rule, rule_path, "count",
					objective, "objective", "count", errors,
				)
			"deliver_item":
				_compare_task_semantic_field(
					rule, rule_path, "character_id",
					objective, "objective", "recipient_id", errors,
				)
				_compare_task_semantic_field(
					rule, rule_path, "item_id",
					objective, "objective", "item_id", errors,
				)
				_compare_task_semantic_field(
					rule, rule_path, "count",
					objective, "objective", "count", errors,
				)
			"visit_location":
				_compare_task_semantic_field(
					rule, rule_path, "location_id",
					task, "task", "location_id", errors,
				)
				_compare_task_semantic_field(
					rule, rule_path, "duration_minutes",
					objective, "objective", "duration_minutes", errors,
				)
			"visit_marker":
				_compare_task_semantic_field(
					rule, rule_path, "marker_id",
					objective, "objective", "marker_id", errors,
				)
			"repair_object":
				_compare_task_semantic_field(
					rule, rule_path, "object_id",
					objective, "objective", "object_id", errors,
				)
			"collect_evidence":
				_compare_task_semantic_field(
					rule, rule_path, "evidence_id",
					objective, "objective", "evidence_id", errors,
				)
				_compare_task_semantic_field(
					rule, rule_path, "count",
					objective, "objective", "count", errors,
				)
			"find_object":
				_compare_task_semantic_field(
					rule, rule_path, "object_id",
					objective, "objective", "object_id", errors,
				)
			"keep_appointment":
				_compare_task_semantic_field(
					rule, rule_path, "character_id",
					objective, "objective", "character_id", errors,
				)
				_compare_task_semantic_field(
					rule, rule_path, "location_id",
					task, "task", "location_id", errors,
				)
			"return_item_on_time":
				_compare_task_semantic_field(
					rule, rule_path, "item_id",
					objective, "objective", "item_id", errors,
				)
				_compare_task_semantic_field(
					rule, rule_path, "location_id",
					task, "task", "location_id", errors,
				)
			"prepare_festival_items":
				_compare_task_semantic_field(
					rule, rule_path, "item_id",
					objective, "objective", "item_id", errors,
				)
				_compare_task_semantic_field(
					rule, rule_path, "count",
					objective, "objective", "count", errors,
				)


func _compare_task_semantic_field(
	rule: Dictionary,
	rule_path: String,
	rule_field: String,
	source: Dictionary,
	source_path: String,
	source_field: String,
	errors: Array,
) -> void:
	if not rule.has(rule_field) or not source.has(source_field):
		return
	var field_error_prefix := "%s.%s:" % [rule_path, rule_field]
	for error in errors:
		if error.begins_with(field_error_prefix):
			return
	if typeof(rule[rule_field]) != typeof(source[source_field]):
		return
	if rule[rule_field] == source[source_field]:
		return
	errors.append(
		"%s.%s: expected %s to match %s.%s, got %s"
		% [
			rule_path,
			rule_field,
			source[source_field],
			source_path,
			source_field,
			rule[rule_field],
		],
	)


func _validate_task_target_references(
	task: Dictionary,
	path: String,
	location_ids: Dictionary,
	errors: Array,
) -> void:
	var location_id = task.get("location_id", null)
	if (
		typeof(location_id) != TYPE_STRING
		or location_id.is_empty()
		or not location_ids.has(location_id)
	):
		return
	var target_ids: Dictionary = location_ids[location_id]["task_target_ids"]
	var objective = task.get("objective", null)
	if typeof(objective) == TYPE_DICTIONARY and objective.get("type", "") in [
		"repair_object",
		"find_object",
	]:
		_validate_task_target_reference(
			objective,
			"object_id",
			"%s.objective" % path,
			location_id,
			target_ids,
			errors,
		)
	var rules = task.get("completion_rules", null)
	if typeof(rules) != TYPE_ARRAY:
		return
	for index in rules.size():
		if typeof(rules[index]) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rules[index]
		if rule.get("type", "") not in ["object_repaired", "object_found"]:
			continue
		_validate_task_target_reference(
			rule,
			"object_id",
			"%s.completion_rules[%d]" % [path, index],
			location_id,
			target_ids,
			errors,
		)


func _validate_task_target_reference(
	record: Dictionary,
	field: String,
	path: String,
	location_id: String,
	target_ids: Dictionary,
	errors: Array,
) -> void:
	var target_id = record.get(field, null)
	if (
		typeof(target_id) != TYPE_STRING
		or target_id.is_empty()
		or target_ids.has(target_id)
	):
		return
	errors.append(
		"%s.%s: unknown task target '%s' for location '%s'"
		% [path, field, target_id, location_id],
	)


func _validate_task_targets(
	location: Dictionary,
	path: String,
	errors: Array,
) -> Dictionary:
	var ids := {}
	if not location.has("task_targets"):
		return ids
	if typeof(location["task_targets"]) != TYPE_ARRAY:
		errors.append("%s.task_targets: expected array" % path)
		return ids
	var targets: Array = location["task_targets"]
	for index in targets.size():
		var target_path := "%s.task_targets[%d]" % [path, index]
		if typeof(targets[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % target_path)
			continue
		var target: Dictionary = targets[index]
		_require_fields(
			target,
			["target_id", "target_type"],
			target_path,
			errors,
		)
		if _validate_nonempty_string_field(
			target,
			"target_id",
			target_path,
			errors,
		):
			var target_id: String = target["target_id"]
			if ids.has(target_id):
				errors.append(
					"%s.target_id: duplicate id '%s'"
					% [target_path, target_id],
				)
			else:
				ids[target_id] = true
		if _validate_nonempty_string_field(
			target,
			"target_type",
			target_path,
			errors,
		) and target["target_type"] != "object":
			errors.append(
				"%s.target_type: expected 'object', got '%s'"
				% [target_path, target["target_type"]],
			)
	return ids


func _validate_layout_array(
	record: Dictionary,
	field: String,
	id_field: String,
	path: String,
	errors: Array,
) -> void:
	if not record.has(field):
		return
	if typeof(record[field]) != TYPE_ARRAY:
		errors.append("%s.%s: expected array" % [path, field])
		return
	var entries: Array = record[field]
	for index in entries.size():
		var entry_path := "%s.%s[%d]" % [path, field, index]
		if typeof(entries[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % entry_path)
			continue
		var entry: Dictionary = entries[index]
		_require_fields(entry, [id_field, "x", "z"], entry_path, errors)
		_validate_nonempty_string_field(entry, id_field, entry_path, errors)
		for coordinate in ["x", "z"]:
			_normalize_integer_field(entry, coordinate, entry_path, errors)


func _require_fields(
	record: Dictionary,
	fields: Array,
	path: String,
	errors: Array,
) -> void:
	for field in fields:
		if not record.has(field):
			errors.append("%s.%s: missing required field" % [path, field])


func _validate_id_field(
	record: Dictionary,
	field: String,
	path: String,
	seen: Dictionary,
	errors: Array,
) -> String:
	if not record.has(field):
		return ""
	var value = record[field]
	if typeof(value) != TYPE_STRING or value.is_empty():
		errors.append("%s.%s: expected non-empty string" % [path, field])
		return ""
	if seen.has(value):
		errors.append("%s.%s: duplicate id '%s'" % [path, field, value])
	return value


func _validate_nonempty_string_field(
	record: Dictionary,
	field: String,
	path: String,
	errors: Array,
) -> bool:
	if not record.has(field):
		return false
	var value = record[field]
	if typeof(value) != TYPE_STRING or value.is_empty():
		errors.append("%s.%s: expected non-empty string" % [path, field])
		return false
	return true


func _validate_bool_field(
	record: Dictionary,
	field: String,
	path: String,
	errors: Array,
) -> bool:
	if not record.has(field):
		return false
	if typeof(record[field]) != TYPE_BOOL:
		errors.append("%s.%s: expected boolean" % [path, field])
		return false
	return true


func _validate_string_array_field(
	record: Dictionary,
	field: String,
	path: String,
	errors: Array,
) -> bool:
	if not record.has(field):
		return false
	if typeof(record[field]) != TYPE_ARRAY:
		errors.append("%s.%s: expected array" % [path, field])
		return false
	var values: Array = record[field]
	if values.is_empty():
		errors.append("%s.%s: must not be empty" % [path, field])
		return false
	for index in values.size():
		if typeof(values[index]) != TYPE_STRING or values[index].is_empty():
			errors.append(
				"%s.%s[%d]: expected non-empty string" % [path, field, index],
			)
	return true


func _normalize_integer_field(
	record: Dictionary,
	field: String,
	path: String,
	errors: Array,
) -> bool:
	if not record.has(field):
		return false
	var value = record[field]
	if typeof(value) == TYPE_INT:
		return true
	if (
		typeof(value) == TYPE_FLOAT
		and not is_nan(value)
		and not is_inf(value)
		and value == floor(value)
	):
		record[field] = int(value)
		return true
	errors.append("%s.%s: expected integer" % [path, field])
	return false


func _is_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and not is_nan(float(value))
		and not is_inf(float(value))
	)
