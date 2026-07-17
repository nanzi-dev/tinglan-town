class_name TaskBoardPanel
extends Control

signal close_requested
signal task_published(task: Dictionary)

const THEME_FACTORY := preload("res://scripts/ui/theme_factory.gd")
const COMPACT_LAYOUT_WIDTH := 1100.0
const TASK_TYPES := [
	{"id": "gather", "label": "采集", "objective_type": "collect_item"},
	{"id": "delivery", "label": "递送", "objective_type": "deliver_item"},
	{"id": "visit", "label": "探访", "objective_type": "visit_location"},
	{"id": "repair", "label": "修缮", "objective_type": "repair_object"},
	{"id": "investigate", "label": "调查", "objective_type": "gather_evidence"},
	{"id": "social", "label": "社交承诺", "objective_type": "keep_appointment"},
	{"id": "festival", "label": "节庆准备", "objective_type": "festival_prepare"},
]
const COMPLETION_RULES := [
	{"id": "inventory_count", "label": "持有指定物品"},
	{"id": "delivered_to", "label": "交付给指定居民"},
	{"id": "visited_location", "label": "在地点停留"},
	{"id": "visited_marker", "label": "到达指定标记"},
	{"id": "object_repaired", "label": "修复指定对象"},
	{"id": "evidence_count", "label": "收集指定证据"},
	{"id": "object_found", "label": "找到指定对象"},
	{"id": "appointment_kept", "label": "按时赴约"},
	{"id": "item_returned", "label": "归还指定物品"},
	{"id": "festival_item_count", "label": "提交节庆物资"},
]

@onready var _task_type_option: OptionButton = %TaskTypeOption
@onready var _target_id_edit: LineEdit = %TargetIdEdit
@onready var _target_count_spin: SpinBox = %TargetCountSpin
@onready var _location_edit: LineEdit = %LocationEdit
@onready var _deadline_days_spin: SpinBox = %DeadlineDaysSpin
@onready var _deadline_minute_spin: SpinBox = %DeadlineMinuteSpin
@onready var _reward_coins_spin: SpinBox = %RewardCoinsSpin
@onready var _completion_rule_option: OptionButton = %CompletionRuleOption
@onready var _completion_target_edit: LineEdit = %CompletionTargetEdit
@onready var _description_edit: TextEdit = %DescriptionEdit
@onready var _target_error_label: Label = %TargetErrorLabel
@onready var _location_error_label: Label = %LocationErrorLabel
@onready var _description_error_label: Label = %DescriptionErrorLabel
@onready var _form_error_label: Label = %FormErrorLabel
@onready var _published_task_list: VBoxContainer = %PublishedTaskList
@onready var _empty_task_label: Label = %EmptyTaskLabel
@onready var _submit_button: Button = %SubmitButton
@onready var _close_button: Button = %CloseButton
@onready var _content: BoxContainer = $Surface/Margin/Main/Content
@onready var _form_scroll: ScrollContainer = (
	$Surface/Margin/Main/Content/FormScroll
)
@onready var _column_separator: VSeparator = (
	$Surface/Margin/Main/Content/ColumnSeparator
)
@onready var _published: VBoxContainer = (
	$Surface/Margin/Main/Content/Published
)

var _board := TaskBoard.new()
var _field_errors := {}
var _last_submitted_task := {}
var _task_sequence := 0


func _ready() -> void:
	theme = THEME_FACTORY.new().create_theme()
	_populate_option(_task_type_option, TASK_TYPES)
	_populate_option(_completion_rule_option, COMPLETION_RULES)
	_submit_button.pressed.connect(submit_current_form)
	_close_button.pressed.connect(_on_close_pressed)
	resized.connect(_update_responsive_layout)
	_update_responsive_layout()
	_clear_errors()


func set_task_board(board: TaskBoard) -> void:
	if board != null:
		_board = board


func submit_current_form() -> bool:
	_clear_errors()
	var target_id := _target_id_edit.text.strip_edges()
	var location_id := _location_edit.text.strip_edges()
	var description := _description_edit.text.strip_edges()
	if target_id.is_empty():
		_set_field_error("target_id", "请填写结构化目标")
	if location_id.is_empty():
		_set_field_error("location_id", "请填写任务地点")
	if description.is_empty():
		_set_field_error("description", "请填写任务说明")
	if not _field_errors.is_empty():
		return false

	var task_type_id := _selected_metadata(_task_type_option)
	var objective_type := _objective_type_for(task_type_id)
	var completion_rule_id := _selected_metadata(_completion_rule_option)
	var target_count := maxi(int(_target_count_spin.value), 1)
	var task := {
		"task_id": _next_task_id(),
		"source": "player",
		"status": "open",
		"task_type": task_type_id,
		"objective": _build_objective(
			objective_type,
			target_id,
			target_count,
			location_id,
		),
		"location_id": location_id,
		"deadline": {
			"days": int(_deadline_days_spin.value),
			"minute": int(_deadline_minute_spin.value),
		},
		"reward": {"coins": int(_reward_coins_spin.value)},
		"completion_rules": [_build_completion_rule(
			completion_rule_id,
			target_id,
			target_count,
			location_id,
			_completion_target_edit.text.strip_edges(),
		)],
		"description": description,
	}
	if not _board.add_task(task):
		_form_error_label.text = "任务未能发布，请检查结构化字段"
		_form_error_label.visible = true
		return false

	_last_submitted_task = task.duplicate(true)
	_append_task_summary(task)
	task_published.emit(task.duplicate(true))
	return true


func get_last_submitted_task() -> Dictionary:
	return _last_submitted_task.duplicate(true)


func get_field_errors() -> Dictionary:
	return _field_errors.duplicate()


func _update_responsive_layout() -> void:
	var compact := size.x < COMPACT_LAYOUT_WIDTH
	_content.vertical = compact
	_form_scroll.custom_minimum_size.x = 0.0 if compact else 650.0
	_published.size_flags_vertical = (
		Control.SIZE_FILL if compact else Control.SIZE_EXPAND_FILL
	)
	_published.custom_minimum_size = (
		Vector2.ZERO if compact else Vector2(330.0, 0.0)
	)
	_column_separator.visible = not compact


func _populate_option(option: OptionButton, options: Array) -> void:
	option.clear()
	for item in options:
		option.add_item(item["label"])
		option.set_item_metadata(option.item_count - 1, item["id"])


func _selected_metadata(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _objective_type_for(task_type_id: String) -> String:
	for item in TASK_TYPES:
		if item["id"] == task_type_id:
			return item["objective_type"]
	return "collect_item"


func _build_objective(
	objective_type: String,
	target_id: String,
	target_count: int,
	location_id: String,
) -> Dictionary:
	var objective := {"type": objective_type}
	match objective_type:
		"collect_item", "festival_prepare":
			objective["item_id"] = target_id
			objective["count"] = target_count
		"deliver_item":
			objective["item_id"] = target_id
			objective["count"] = target_count
			objective["recipient_id"] = _completion_target_edit.text.strip_edges()
		"visit_location":
			objective["location_id"] = location_id
			objective["duration_minutes"] = target_count
		"repair_object":
			objective["object_id"] = target_id
		"gather_evidence":
			objective["evidence_id"] = target_id
			objective["count"] = target_count
		"keep_appointment":
			objective["character_id"] = target_id
			objective["location_id"] = location_id
	return objective


func _build_completion_rule(
	rule_type: String,
	target_id: String,
	target_count: int,
	location_id: String,
	completion_target: String,
) -> Dictionary:
	match rule_type:
		"delivered_to":
			return {
				"type": rule_type,
				"character_id": (
					completion_target if not completion_target.is_empty() else target_id
				),
				"item_id": target_id,
				"count": target_count,
			}
		"visited_location":
			return {
				"type": rule_type,
				"location_id": location_id,
				"duration_minutes": target_count,
			}
		"visited_marker":
			return {"type": rule_type, "marker_id": target_id}
		"object_repaired":
			return {"type": rule_type, "object_id": target_id}
		"evidence_count":
			return {
				"type": rule_type,
				"evidence_id": target_id,
				"count": target_count,
			}
		"object_found":
			return {"type": rule_type, "object_id": target_id}
		"appointment_kept":
			return {
				"type": rule_type,
				"character_id": target_id,
				"location_id": location_id,
			}
		"item_returned":
			return {
				"type": rule_type,
				"item_id": target_id,
				"location_id": location_id,
			}
		"festival_item_count":
			return {
				"type": rule_type,
				"item_id": target_id,
				"count": target_count,
			}
		_:
			return {
				"type": "inventory_count",
				"item_id": target_id,
				"count": target_count,
			}


func _next_task_id() -> String:
	while true:
		_task_sequence += 1
		var task_id := "player-task-%04d" % _task_sequence
		if _board.task_status(task_id).is_empty():
			return task_id
	return ""


func _append_task_summary(task: Dictionary) -> void:
	_empty_task_label.visible = false
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = "%s · %s · %d 文" % [
		task["description"],
		task["location_id"],
		task["reward"]["coins"],
	]
	_published_task_list.add_child(summary)


func _clear_errors() -> void:
	_field_errors.clear()
	for label in [
		_target_error_label,
		_location_error_label,
		_description_error_label,
		_form_error_label,
	]:
		label.text = ""
		label.visible = label in [
			_target_error_label,
			_location_error_label,
		]


func _set_field_error(field_id: String, message: String) -> void:
	_field_errors[field_id] = message
	var label: Label
	match field_id:
		"target_id":
			label = _target_error_label
		"location_id":
			label = _location_error_label
		_:
			label = _description_error_label
	label.text = message
	label.visible = true


func _on_close_pressed() -> void:
	visible = false
	close_requested.emit()
