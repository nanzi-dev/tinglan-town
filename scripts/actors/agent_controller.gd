class_name AgentController
extends RefCounted


func resolve_decision(candidates: Variant, memoria_decision: Variant) -> Dictionary:
	var valid_candidates := _valid_candidates(candidates)
	if valid_candidates.is_empty():
		return {}

	var memoria_action_id := _memoria_action_id(memoria_decision)
	if not memoria_action_id.is_empty():
		for candidate in valid_candidates:
			if candidate["id"] == memoria_action_id:
				return _copy_with_source(candidate, "memoria")

	var best_candidate: Dictionary = valid_candidates[0]
	var best_utility := _utility(best_candidate)
	for index in range(1, valid_candidates.size()):
		var candidate: Dictionary = valid_candidates[index]
		var candidate_utility := _utility(candidate)
		if (
			candidate_utility > best_utility
			or (
				candidate_utility == best_utility
				and candidate["id"] < best_candidate["id"]
			)
		):
			best_candidate = candidate
			best_utility = candidate_utility

	return _copy_with_source(best_candidate, "local_fallback")


func _valid_candidates(candidates: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(candidates) != TYPE_ARRAY:
		return result

	var candidate_id_counts := {}
	for candidate_value in candidates:
		if typeof(candidate_value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = candidate_value
		var candidate_id = candidate.get("id", "")
		if typeof(candidate_id) != TYPE_STRING or candidate_id.is_empty():
			continue
		candidate_id_counts[candidate_id] = (
			int(candidate_id_counts.get(candidate_id, 0)) + 1
		)

	var duplicate_candidate_ids: Array[String] = []
	for candidate_id in candidate_id_counts:
		if candidate_id_counts[candidate_id] > 1:
			duplicate_candidate_ids.append(candidate_id)
	duplicate_candidate_ids.sort()
	for candidate_id in duplicate_candidate_ids:
		push_error("Duplicate candidate id '%s'." % candidate_id)

	for candidate_value in candidates:
		if typeof(candidate_value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = candidate_value
		var candidate_id = candidate.get("id", "")
		if (
			typeof(candidate_id) != TYPE_STRING
			or candidate_id.is_empty()
			or candidate_id_counts[candidate_id] != 1
		):
			continue
		result.append(candidate)
	return result


func _memoria_action_id(memoria_decision: Variant) -> String:
	if typeof(memoria_decision) != TYPE_DICTIONARY:
		return ""

	var candidate_action_id = memoria_decision.get("candidate_action_id", "")
	if typeof(candidate_action_id) != TYPE_STRING:
		return ""
	return candidate_action_id


func _utility(candidate: Dictionary) -> float:
	var value = candidate.get("utility", 0.0)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0

	var utility := float(value)
	if is_nan(utility) or is_inf(utility):
		return 0.0
	return utility


func _copy_with_source(candidate: Dictionary, source: String) -> Dictionary:
	var result := candidate.duplicate(true)
	result["source"] = source
	return result
