class_name UtilityEvaluator
extends RefCounted

const POSITIVE_MODIFIERS := [
	"schedule_fit",
	"relationship_context",
	"task_priority",
]
const COST_MODIFIERS := [
	"travel_cost",
	"risk_cost",
]


func score_all(needs: Variant, actions: Variant, context: Variant) -> Dictionary:
	if typeof(actions) != TYPE_ARRAY:
		return {}

	var needs_data: Dictionary = needs if typeof(needs) == TYPE_DICTIONARY else {}
	var context_data: Dictionary = context if typeof(context) == TYPE_DICTIONARY else {}
	var scores := {}
	var valid_actions: Array[Dictionary] = []
	var action_id_counts := {}

	for action_value in actions:
		if typeof(action_value) != TYPE_DICTIONARY:
			continue

		var action: Dictionary = action_value
		var action_id = action.get("id", "")
		if typeof(action_id) != TYPE_STRING or action_id.is_empty():
			continue
		action_id_counts[action_id] = int(action_id_counts.get(action_id, 0)) + 1

	var duplicate_action_ids: Array[String] = []
	for action_id in action_id_counts:
		if action_id_counts[action_id] > 1:
			duplicate_action_ids.append(action_id)
	duplicate_action_ids.sort()
	for action_id in duplicate_action_ids:
		push_error("Duplicate action id '%s'." % action_id)

	for action_value in actions:
		if typeof(action_value) != TYPE_DICTIONARY:
			continue

		var action: Dictionary = action_value
		var action_id = action.get("id", "")
		if (
			typeof(action_id) != TYPE_STRING
			or action_id.is_empty()
			or action_id_counts[action_id] != 1
		):
			continue
		valid_actions.append(action)

	valid_actions.sort_custom(_action_id_before)
	for action in valid_actions:
		var action_id: String = action["id"]
		var score := _number_or_zero(action.get("base_utility", 0.0))
		var action_overflowed := false
		var need_effects = action.get("need_effects", {})
		if typeof(need_effects) == TYPE_DICTIONARY:
			var need_ids: Array = need_effects.keys()
			need_ids.sort_custom(_need_id_before)
			for need_id in need_ids:
				var urgency := _number_or_zero(needs_data.get(need_id, 0.0))
				var effect := _number_or_zero(need_effects[need_id])
				var contribution := urgency * -effect
				if not _score_result_is_finite(contribution, action_id):
					action_overflowed = true
					break
				var next_score := score + contribution
				if not _score_result_is_finite(next_score, action_id):
					action_overflowed = true
					break
				score = next_score
		if action_overflowed:
			continue

		for field in POSITIVE_MODIFIERS:
			var next_score := (
				score + _modifier_for_action(action, context_data, action_id, field)
			)
			if not _score_result_is_finite(next_score, action_id):
				action_overflowed = true
				break
			score = next_score
		if action_overflowed:
			continue

		for field in COST_MODIFIERS:
			var next_score := (
				score - _modifier_for_action(action, context_data, action_id, field)
			)
			if not _score_result_is_finite(next_score, action_id):
				action_overflowed = true
				break
			score = next_score
		if action_overflowed:
			continue

		scores[action_id] = score

	return scores


func _score_result_is_finite(value: float, action_id: String) -> bool:
	if not is_nan(value) and not is_inf(value):
		return true
	push_error("Utility score overflowed for action '%s'." % action_id)
	return false


func _action_id_before(left: Dictionary, right: Dictionary) -> bool:
	return left["id"] < right["id"]


func _need_id_before(left: Variant, right: Variant) -> bool:
	var left_id := str(left)
	var right_id := str(right)
	if left_id == right_id:
		return typeof(left) < typeof(right)
	return left_id < right_id


func _modifier_for_action(
	action: Dictionary,
	context: Dictionary,
	action_id: String,
	field: String,
) -> float:
	var value = action.get(field, 0.0)
	var action_context = context.get(action_id, {})
	if typeof(action_context) == TYPE_DICTIONARY and action_context.has(field):
		value = action_context[field]
	elif context.has(field):
		var field_context = context[field]
		if typeof(field_context) == TYPE_DICTIONARY:
			value = field_context.get(action_id, value)
		else:
			value = field_context
	return _number_or_zero(value)


func _number_or_zero(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0

	var number := float(value)
	if is_nan(number) or is_inf(number):
		return 0.0
	return number
