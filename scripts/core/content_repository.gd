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
const REQUIRED_TASK_CATEGORY_COUNTS := {
	"gather": 5,
	"delivery": 4,
	"visit": 3,
	"repair": 3,
	"investigation": 2,
	"social_promise": 2,
	"festival_preparation": 1,
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
		if not location_id.is_empty():
			ids[location_id] = true

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
				for entry_index in entries.size():
					_validate_schedule_entry(
						entries[entry_index],
						"%s.entries[%d]" % [path, entry_index],
						location_ids,
						errors,
					)
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
				character_ids,
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
				errors,
			)
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
	if (
		start_valid
		and (
			festival_value["start_minute"] < 0
			or festival_value["start_minute"] > 1440
		)
	):
		errors.append("festival.start_minute: expected minute from 0 to 1440")
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
	for index in branches.size():
		var path := "festival.preparation_branches[%d]" % index
		if typeof(branches[index]) != TYPE_DICTIONARY:
			errors.append("%s: expected object" % path)
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
		_validate_nonempty_string_field(branch, "branch_id", path, errors)
		_normalize_integer_field(
			branch,
			"minimum_preparation",
			path,
			errors,
		)
		_normalize_integer_field(
			branch,
			"maximum_preparation",
			path,
			errors,
		)
		if branch.has("display") and typeof(branch["display"]) != TYPE_DICTIONARY:
			errors.append("%s.display: expected object" % path)


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
	for field in ["days", "minute"]:
		_normalize_integer_field(deadline, field, path, errors)


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
	character_ids: Dictionary,
	errors: Array,
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected object" % path)
		return
	var object: Dictionary = value
	_require_fields(object, ["type"], path, errors)
	_validate_nonempty_string_field(object, "type", path, errors)
	for field in ["count", "duration_minutes", "minute"]:
		if object.has(field):
			_normalize_integer_field(object, field, path, errors)
	for field in ["character_id", "recipient_id"]:
		var character_id = object.get(field, null)
		if (
			typeof(character_id) == TYPE_STRING
			and not character_id.is_empty()
			and not character_ids.has(character_id)
		):
			errors.append(
				"%s.%s: unknown character '%s'"
				% [path, field, character_id],
			)


func _validate_completion_rules(
	value: Variant,
	path: String,
	character_ids: Dictionary,
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
			character_ids,
			errors,
		)


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
