class_name CommunityProject
extends RefCounted

const EVENT_CONSUMER_ID := "community_project"
const VALID_STAGE_IDS := [
	"proposed",
	"collecting",
	"voting",
	"construction",
	"completed",
]
const VALID_VOTE_CANDIDATES := ["support", "oppose", "abstain"]
const SUPPORT_SCORE_THRESHOLD := 0.5
const OPPOSE_SCORE_THRESHOLD := -0.5
const CONSTRUCTION_DAYS_REQUIRED := 2

var _definition: Dictionary
var _event_log: DomainEventLog
var _valid := false
var _stage_index := 0
var _materials := {}
var _funds := 0
var _votes := {
	"support": 0,
	"oppose": 0,
	"abstain": 0,
}
var _voters := {}
var _construction_days_elapsed := 0


func _init(
	definition: Variant,
	event_log: DomainEventLog = null,
) -> void:
	_event_log = event_log if event_log != null else DomainEventLog.new()
	if typeof(definition) != TYPE_DICTIONARY:
		return

	_definition = definition.duplicate(true)
	_valid = _has_valid_definition()
	if not _valid:
		return

	var thresholds: Dictionary = _definition["resource_thresholds"]
	for material_id in thresholds["materials"]:
		_materials[material_id] = 0


func current_stage() -> String:
	if not _valid:
		return ""
	return VALID_STAGE_IDS[_stage_index]


func begin_collecting(event_id: Variant) -> bool:
	if (
		current_stage() != "proposed"
		or not _is_nonempty_string(event_id)
		or not _event_log.record_once(event_id, EVENT_CONSUMER_ID)
	):
		return false
	_stage_index = 1
	return true


func contribute_resources(
	event_id: Variant,
	material_deltas: Variant,
	funds_delta: Variant,
) -> bool:
	if (
		current_stage() != "collecting"
		or not _is_nonempty_string(event_id)
		or typeof(material_deltas) != TYPE_DICTIONARY
		or not _is_nonnegative_integer(funds_delta)
	):
		return false

	var contribution: Dictionary = material_deltas
	var funds_amount := int(funds_delta)
	var has_contribution: bool = funds_amount > 0
	var next_materials := _materials.duplicate()
	for material_id in contribution:
		if (
			not _materials.has(material_id)
			or not _is_nonnegative_integer(contribution[material_id])
		):
			return false
		var amount: int = contribution[material_id]
		if amount > 0:
			has_contribution = true
		var next_amount: int = next_materials[material_id] + amount
		if next_amount < next_materials[material_id]:
			return false
		next_materials[material_id] = next_amount

	if not has_contribution:
		return false
	var next_funds: int = _funds + funds_amount
	if next_funds < _funds:
		return false
	if not _event_log.record_once(event_id, EVENT_CONSUMER_ID):
		return false

	_materials = next_materials
	_funds = next_funds
	if _resources_meet_thresholds():
		_stage_index = 2
	return true


func resolve_vote_candidate(
	context: Variant,
	memoria_candidate: Variant = "",
) -> String:
	if (
		typeof(memoria_candidate) == TYPE_STRING
		and VALID_VOTE_CANDIDATES.has(memoria_candidate)
	):
		return memoria_candidate
	if typeof(context) != TYPE_DICTIONARY:
		return "abstain"

	var vote_context: Dictionary = context
	for field in [
		"personality_weight",
		"proposer_relationship",
		"evidence_strength",
		"resource_gap",
	]:
		if not _is_finite_number(vote_context.get(field, null)):
			return "abstain"

	var score := (
		float(vote_context["personality_weight"])
		+ float(vote_context["proposer_relationship"])
		+ float(vote_context["evidence_strength"])
		- float(vote_context["resource_gap"])
	)
	if score >= SUPPORT_SCORE_THRESHOLD:
		return "support"
	if score <= OPPOSE_SCORE_THRESHOLD:
		return "oppose"
	return "abstain"


func submit_vote(
	event_id: Variant,
	npc_id: Variant,
	candidate: Variant,
) -> bool:
	if (
		current_stage() != "voting"
		or not _is_nonempty_string(event_id)
		or not _is_nonempty_string(npc_id)
		or typeof(candidate) != TYPE_STRING
		or not VALID_VOTE_CANDIDATES.has(candidate)
		or _voters.has(npc_id)
		or not _event_log.record_once(event_id, EVENT_CONSUMER_ID)
	):
		return false

	_voters[npc_id] = candidate
	_votes[candidate] += 1
	var support_threshold: int = (
		_definition["resource_thresholds"]["support_votes"]
	)
	if _votes["support"] >= support_threshold:
		_stage_index = 3
	return true


func advance_construction_day(event_id: Variant) -> bool:
	if (
		current_stage() != "construction"
		or not _is_nonempty_string(event_id)
		or not _event_log.record_once(event_id, EVENT_CONSUMER_ID)
	):
		return false

	_construction_days_elapsed += 1
	if _construction_days_elapsed >= CONSTRUCTION_DAYS_REQUIRED:
		_construction_days_elapsed = CONSTRUCTION_DAYS_REQUIRED
		_stage_index = 4
	return true


func snapshot() -> Dictionary:
	if not _valid:
		return {}
	return {
		"project_id": _definition["project_id"],
		"name": _definition["name"],
		"stage": current_stage(),
		"resources": {
			"materials": _materials.duplicate(true),
			"funds": _funds,
		},
		"resource_thresholds": (
			_definition["resource_thresholds"].duplicate(true)
		),
		"votes": _votes.duplicate(true),
		"voter_count": _voters.size(),
		"construction_days_elapsed": _construction_days_elapsed,
		"route_closed": current_stage() == "construction",
	}


func _resources_meet_thresholds() -> bool:
	var thresholds: Dictionary = _definition["resource_thresholds"]
	if _funds < thresholds["funds"]:
		return false
	for material_id in thresholds["materials"]:
		if _materials[material_id] < thresholds["materials"][material_id]:
			return false
	return true


func _has_valid_definition() -> bool:
	for field in [
		"project_id",
		"name",
		"resource_thresholds",
		"stages",
	]:
		if not _definition.has(field):
			return false
	if (
		not _is_nonempty_string(_definition["project_id"])
		or not _is_nonempty_string(_definition["name"])
		or typeof(_definition["resource_thresholds"]) != TYPE_DICTIONARY
		or typeof(_definition["stages"]) != TYPE_ARRAY
	):
		return false

	var stages: Array = _definition["stages"]
	if stages.size() != VALID_STAGE_IDS.size():
		return false
	for index in stages.size():
		if (
			typeof(stages[index]) != TYPE_DICTIONARY
			or stages[index].get("stage_id", "") != VALID_STAGE_IDS[index]
		):
			return false

	var thresholds: Dictionary = _definition["resource_thresholds"]
	if (
		typeof(thresholds.get("materials", null)) != TYPE_DICTIONARY
		or not _is_positive_integer(thresholds.get("funds", null))
		or not _is_positive_integer(thresholds.get("support_votes", null))
	):
		return false
	var materials: Dictionary = thresholds["materials"]
	if materials.is_empty():
		return false
	for material_id in materials:
		if (
			not _is_nonempty_string(material_id)
			or not _is_positive_integer(materials[material_id])
		):
			return false
	return true


func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()


func _is_nonnegative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


func _is_positive_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value > 0


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)
