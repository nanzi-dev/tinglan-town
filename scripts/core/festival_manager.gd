class_name FestivalManager
extends RefCounted

const EVENT_CONSUMER_ID := "festival_manager"
const PROJECT_STAGE_SCORES := {
	"proposed": 0.0,
	"collecting": 25.0,
	"voting": 50.0,
	"construction": 75.0,
	"completed": 100.0,
}

var _definition: Dictionary
var _event_log: DomainEventLog
var _valid := false
var _completed := false
var _completed_result := {}


func _init(
	definition: Variant,
	event_log: DomainEventLog = null,
) -> void:
	_event_log = event_log if event_log != null else DomainEventLog.new()
	if typeof(definition) != TYPE_DICTIONARY:
		return
	_definition = definition.duplicate(true)
	_valid = _has_valid_definition()


func trigger_if_due(
	season: Variant,
	day: Variant,
	minute: Variant,
	context: Variant,
) -> Dictionary:
	if _completed:
		return _not_triggered("already_completed")
	if not _valid:
		return _not_triggered("invalid_definition")
	if (
		season != _definition["season"]
		or day != _definition["day"]
		or minute != _definition["start_minute"]
	):
		return _not_triggered("not_due")
	if typeof(context) != TYPE_DICTIONARY:
		return _not_triggered("invalid_context")

	var factor_scores := _factor_scores(context)
	if factor_scores.is_empty():
		return _not_triggered("invalid_context")
	var branch := _branch_for(factor_scores["preparation_level"])
	if branch.is_empty():
		return _not_triggered("invalid_context")

	var event_id := "festival:%s:%s:%d" % [
		_definition["festival_id"],
		_definition["season"],
		_definition["day"],
	]
	if not _event_log.record_once(event_id, EVENT_CONSUMER_ID):
		_completed = true
		return _not_triggered("already_completed")

	var outcome_score := _weighted_outcome_score(factor_scores)
	var display: Dictionary = branch["display"].duplicate(true)
	var structured_result := {
		"festival_id": _definition["festival_id"],
		"branch_id": branch["branch_id"],
		"display": display.duplicate(true),
		"outcome": "completed",
		"outcome_score": outcome_score,
		"factor_scores": factor_scores.duplicate(true),
	}
	var completed_event := {
		"event_id": event_id,
		"event_scope": "local_domain",
		"event_type": "festival_completed",
		"participants": ["player"],
		"world_time": {
			"season": season,
			"day": day,
			"minute": minute,
		},
		"structured_result": structured_result,
		"source_action_id": "festival_schedule",
	}
	_completed_result = {
		"triggered": true,
		"completed": true,
		"outcome": "completed",
		"allows_failure": false,
		"branch_id": branch["branch_id"],
		"display": display,
		"outcome_score": outcome_score,
		"factor_scores": factor_scores,
		"completed_event": completed_event,
	}
	_completed = true
	return _completed_result.duplicate(true)


func completed_result() -> Dictionary:
	return _completed_result.duplicate(true)


func _factor_scores(context: Dictionary) -> Dictionary:
	var preparation = context.get("preparation_level", null)
	var project_stage = context.get("community_project_stage", null)
	var promise_fulfillment = context.get(
		"player_resident_promise_fulfillment",
		null,
	)
	if (
		not _is_percentage(preparation)
		or typeof(project_stage) != TYPE_STRING
		or not PROJECT_STAGE_SCORES.has(project_stage)
		or not _is_percentage(promise_fulfillment)
	):
		return {}
	return {
		"preparation_level": float(preparation),
		"community_project_stage": PROJECT_STAGE_SCORES[project_stage],
		"player_resident_promise_fulfillment": float(promise_fulfillment),
	}


func _branch_for(preparation_level: float) -> Dictionary:
	for branch in _definition["preparation_branches"]:
		if (
			preparation_level >= float(branch["minimum_preparation"])
			and preparation_level <= float(branch["maximum_preparation"])
		):
			return branch
	return {}


func _weighted_outcome_score(factor_scores: Dictionary) -> float:
	var weighted_total := 0.0
	var total_weight := 0.0
	for factor in _definition["outcome_contract"]["factors"]:
		var factor_id: String = factor["factor_id"]
		var weight := float(factor["weight"])
		weighted_total += factor_scores[factor_id] * weight
		total_weight += weight
	if total_weight <= 0.0:
		return 0.0
	return weighted_total / total_weight


func _not_triggered(reason: String) -> Dictionary:
	return {
		"triggered": false,
		"completed": _completed,
		"reason": reason,
	}


func _has_valid_definition() -> bool:
	for field in [
		"festival_id",
		"season",
		"day",
		"start_minute",
		"outcome_contract",
		"preparation_branches",
	]:
		if not _definition.has(field):
			return false
	if (
		not _is_nonempty_string(_definition["festival_id"])
		or not _is_nonempty_string(_definition["season"])
		or not _is_positive_integer(_definition["day"])
		or not _is_nonnegative_integer(_definition["start_minute"])
		or typeof(_definition["outcome_contract"]) != TYPE_DICTIONARY
		or typeof(_definition["preparation_branches"]) != TYPE_ARRAY
	):
		return false

	var branches: Array = _definition["preparation_branches"]
	if branches.is_empty():
		return false
	for branch in branches:
		if (
			typeof(branch) != TYPE_DICTIONARY
			or not _is_nonempty_string(branch.get("branch_id", null))
			or not _is_nonnegative_integer(
				branch.get("minimum_preparation", null),
			)
			or not _is_nonnegative_integer(
				branch.get("maximum_preparation", null),
			)
			or branch["minimum_preparation"] > branch["maximum_preparation"]
			or typeof(branch.get("display", null)) != TYPE_DICTIONARY
		):
			return false

	var contract: Dictionary = _definition["outcome_contract"]
	if typeof(contract.get("factors", null)) != TYPE_ARRAY:
		return false
	var seen_factors := {}
	for factor in contract["factors"]:
		if (
			typeof(factor) != TYPE_DICTIONARY
			or not _is_nonempty_string(factor.get("factor_id", null))
			or not _is_positive_integer(factor.get("weight", null))
		):
			return false
		seen_factors[factor["factor_id"]] = true
	for factor_id in [
		"preparation_level",
		"community_project_stage",
		"player_resident_promise_fulfillment",
	]:
		if not seen_factors.has(factor_id):
			return false
	return true


func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()


func _is_nonnegative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


func _is_positive_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value > 0


func _is_percentage(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return (
		not is_nan(number)
		and not is_inf(number)
		and number >= 0.0
		and number <= 100.0
	)
