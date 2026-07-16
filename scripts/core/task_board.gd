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
	if typeof(rule) != TYPE_DICTIONARY or rule.get("type", "") != "has_item":
		return false
	return (
			typeof(rule.get("item_id", null)) == TYPE_STRING
			and not rule["item_id"].is_empty()
			and typeof(rule.get("count", null)) == TYPE_INT
			and rule["count"] >= 0
		)


func _completion_rules_are_satisfied(rules: Array, inventory: Variant) -> bool:
	if typeof(inventory) != TYPE_DICTIONARY:
		return false

	for rule in rules:
		var item_count = inventory.get(rule["item_id"], 0)
		if (
			typeof(item_count) != TYPE_INT
			or item_count < 0
			or item_count < rule["count"]
		):
			return false
	return true


func _zero_reward(reward: Dictionary) -> Dictionary:
	var result := {}
	for reward_id in reward:
		var amount = reward[reward_id]
		result[reward_id] = 0.0 if typeof(amount) == TYPE_FLOAT else 0
	return result


func _completion_result(reward: Dictionary) -> Dictionary:
	return {"reward": reward.duplicate(true)}
