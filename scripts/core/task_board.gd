class_name TaskBoard
extends RefCounted

const EVENT_CONSUMER_ID := "task_board"
const VALID_STATUSES := [
	"draft",
	"open",
	"accepted",
	"completed",
	"rewarded",
	"withdrawn",
	"expired",
]
const REGISTERABLE_STATUSES := [
	"draft",
	"open",
	"accepted",
	"rewarded",
	"withdrawn",
	"expired",
]
const LEGAL_TRANSITIONS := {
	"draft": ["open"],
	"open": ["accepted", "expired"],
	"accepted": ["withdrawn"],
}
const STRUCTURED_RULE_FIELDS := {
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

var _event_log: DomainEventLog
var _tasks := {}


func _init(event_log: DomainEventLog = null) -> void:
	_event_log = event_log if event_log != null else DomainEventLog.new()


func add_task(task: Variant) -> bool:
	if typeof(task) != TYPE_DICTIONARY or not _is_valid_task(task):
		return false

	var task_id: String = task["task_id"]
	if _tasks.has(task_id):
		return false

	_tasks[task_id] = task.duplicate(true)
	return true


func add_task_template(template: Variant, status: String = "open") -> bool:
	if typeof(template) != TYPE_DICTIONARY:
		return false
	for field in ["template_id", "reward", "completion_rules"]:
		if not template.has(field):
			return false
	return add_task({
		"task_id": template["template_id"],
		"status": status,
		"reward": template["reward"],
		"completion_rules": template["completion_rules"],
	})


func transition_task(task_id: Variant, next_status: Variant) -> bool:
	if (
		typeof(task_id) != TYPE_STRING
		or typeof(next_status) != TYPE_STRING
		or not _tasks.has(task_id)
	):
		return false

	var task: Dictionary = _tasks[task_id]
	var current_status: String = task["status"]
	var allowed_statuses: Array = LEGAL_TRANSITIONS.get(current_status, [])
	if not allowed_statuses.has(next_status):
		return false

	task["status"] = next_status
	return true


func task_status(task_id: Variant) -> String:
	if typeof(task_id) != TYPE_STRING or not _tasks.has(task_id):
		return ""
	return _tasks[task_id]["status"]


func complete_task(
	task_id: Variant,
	event_id: Variant,
	inventory: Variant,
) -> Dictionary:
	if typeof(task_id) != TYPE_STRING or not _tasks.has(task_id):
		return _completion_result({})

	var task: Dictionary = _tasks[task_id]
	var zero_reward := _zero_reward(task["reward"])
	if task["status"] != "accepted":
		return _completion_result(zero_reward)
	if not _completion_rules_are_satisfied(task["completion_rules"], inventory):
		return _completion_result(zero_reward)
	if not _event_log.record_once(event_id, EVENT_CONSUMER_ID):
		return _completion_result(zero_reward)

	task["status"] = "completed"
	task["status"] = "rewarded"
	return _completion_result(task["reward"])


func _is_valid_task(task: Dictionary) -> bool:
	for field in ["task_id", "status", "reward", "completion_rules"]:
		if not task.has(field):
			return false

	if (
		typeof(task["task_id"]) != TYPE_STRING
		or task["task_id"].is_empty()
		or typeof(task["status"]) != TYPE_STRING
		or not REGISTERABLE_STATUSES.has(task["status"])
		or typeof(task["reward"]) != TYPE_DICTIONARY
		or not _is_valid_reward(task["reward"])
		or typeof(task["completion_rules"]) != TYPE_ARRAY
	):
		return false

	for rule in task["completion_rules"]:
		if not _is_valid_completion_rule(rule):
			return false
	return true


func _is_valid_reward(reward: Dictionary) -> bool:
	for reward_id in reward:
		if typeof(reward_id) != TYPE_STRING or reward_id.is_empty():
			return false
		var amount = reward[reward_id]
		if typeof(amount) != TYPE_INT and typeof(amount) != TYPE_FLOAT:
			return false
		if float(amount) < 0.0 or is_nan(float(amount)) or is_inf(float(amount)):
			return false
	return true


func _is_valid_completion_rule(rule: Variant) -> bool:
	if typeof(rule) != TYPE_DICTIONARY:
		return false
	var rule_type = rule.get("type", "")
	if rule_type == "has_item":
		return (
			_is_nonempty_string(rule.get("item_id", null))
			and _is_nonnegative_integer(rule.get("count", null))
		)
	if not STRUCTURED_RULE_FIELDS.has(rule_type):
		return false
	for field in STRUCTURED_RULE_FIELDS[rule_type]:
		if not rule.has(field):
			return false
		if field in ["count", "duration_minutes"]:
			if not _is_nonnegative_integer(rule[field]):
				return false
		elif not _is_nonempty_string(rule[field]):
			return false
	return true


func _completion_rules_are_satisfied(rules: Array, inventory: Variant) -> bool:
	if typeof(inventory) != TYPE_DICTIONARY:
		return false

	for rule in rules:
		if rule["type"] not in ["has_item", "inventory_count"]:
			return false
		var item_count = inventory.get(rule["item_id"], 0)
		if (
			typeof(item_count) != TYPE_INT
			or item_count < 0
			or item_count < rule["count"]
		):
			return false
	return true


func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()


func _is_nonnegative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


func _zero_reward(reward: Dictionary) -> Dictionary:
	var result := {}
	for reward_id in reward:
		var amount = reward[reward_id]
		result[reward_id] = 0.0 if typeof(amount) == TYPE_FLOAT else 0
	return result


func _completion_result(reward: Dictionary) -> Dictionary:
	return {"reward": reward.duplicate(true)}
