class_name ConversationPanel
extends Control

signal close_requested

const THEME_FACTORY := preload("res://scripts/ui/theme_factory.gd")

@onready var _title_label: Label = %ConversationTitleLabel
@onready var _state_label: Label = %ConversationStateLabel
@onready var _dialogue_list: VBoxContainer = %DialogueList
@onready var _transcript_panel: Control = %TranscriptPanel
@onready var _transcript_list: VBoxContainer = %TranscriptList
@onready var _transcript_toggle_button: Button = %TranscriptToggleButton
@onready var _join_button: Button = %JoinButton
@onready var _player_text_edit: LineEdit = %PlayerTextEdit
@onready var _submit_button: Button = %SubmitButton
@onready var _offer_help_button: Button = %OfferHelpButton
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _close_button: Button = %CloseButton

var _manager: ConversationManager
var _active_conversation_id := ""
var _transcript_expanded := false


func _ready() -> void:
	theme = THEME_FACTORY.new().create_theme()
	_transcript_toggle_button.pressed.connect(_toggle_transcript)
	_join_button.pressed.connect(request_join)
	_submit_button.pressed.connect(submit_current_text)
	_offer_help_button.pressed.connect(submit_offer_help)
	_player_text_edit.text_submitted.connect(_on_text_submitted)
	_close_button.pressed.connect(_on_close_pressed)
	set_transcript_expanded(false)
	_refresh_controls()


func open_conversation(
	manager: ConversationManager,
	conversation_id: String,
) -> bool:
	if manager == null or manager.get_context(conversation_id).is_empty():
		return false
	_manager = manager
	_active_conversation_id = conversation_id
	_manager.listen(conversation_id)
	_feedback_label.text = ""
	visible = true
	_refresh_controls()
	_join_button.grab_focus()
	return true


func get_active_conversation_id() -> String:
	return _active_conversation_id


func request_join() -> bool:
	if _manager == null or _active_conversation_id.is_empty():
		return false
	var request := _manager.request_join(_active_conversation_id)
	if not request.get("accepted", false):
		_feedback_label.text = _reason_text(request.get("reason", ""))
		_refresh_controls()
		return false

	_state_label.text = "等待回应"
	var resolution := _manager.resolve_join_request(
		_active_conversation_id,
	)
	_feedback_label.text = str(resolution.get("response_text", ""))
	_refresh_controls()
	if resolution.get("accepted", false):
		_player_text_edit.grab_focus()
		return true
	return false


func submit_current_text() -> bool:
	if _manager == null or _active_conversation_id.is_empty():
		return false
	var result := _manager.submit_player_text(
		_active_conversation_id,
		_player_text_edit.text,
	)
	if not result.get("accepted", false):
		_feedback_label.text = _reason_text(result.get("reason", ""))
		return false
	_player_text_edit.clear()
	_feedback_label.text = ""
	_refresh_controls()
	_player_text_edit.grab_focus()
	return true


func submit_offer_help() -> bool:
	if _manager == null or _active_conversation_id.is_empty():
		return false
	var result := _manager.submit_context_action(
		_active_conversation_id,
		"offer_help",
	)
	if not result.get("accepted", false):
		_feedback_label.text = _reason_text(result.get("reason", ""))
		return false
	_feedback_label.text = "你表示愿意帮忙。"
	_refresh_controls()
	return true


func set_transcript_expanded(expanded: bool) -> void:
	_transcript_expanded = expanded
	if not is_node_ready():
		return
	_transcript_panel.visible = expanded
	_transcript_toggle_button.text = "收起记录" if expanded else "展开记录"
	if expanded:
		_refresh_transcript()


func _refresh_controls() -> void:
	if not is_node_ready():
		return
	var context := (
		_manager.get_context(_active_conversation_id)
		if _manager != null
		else {}
	)
	if context.is_empty():
		_title_label.text = "居民对话"
		_state_label.text = "尚未开始"
		_join_button.visible = false
		_set_composer_enabled(false)
		_clear_children(_dialogue_list)
		_clear_children(_transcript_list)
		return

	_title_label.text = "%s · %s" % [
		str(context.get("location_name", "镇上")),
		"、".join(_participant_names(context)),
	]
	var join_status := str(context.get("join_status", "listening"))
	_state_label.text = _state_text(join_status)
	_join_button.visible = join_status == "listening"
	_set_composer_enabled(join_status == "accepted")
	_refresh_dialogue()
	if _transcript_expanded:
		_refresh_transcript()


func _refresh_dialogue() -> void:
	_clear_children(_dialogue_list)
	if _manager == null:
		return
	var transcript := _manager.get_transcript(_active_conversation_id)
	var first_index := maxi(transcript.size() - 5, 0)
	for index in range(first_index, transcript.size()):
		_dialogue_list.add_child(_entry_label(transcript[index]))


func _refresh_transcript() -> void:
	_clear_children(_transcript_list)
	if _manager == null:
		return
	for entry in _manager.get_transcript(_active_conversation_id):
		_transcript_list.add_child(_entry_label(entry))


func _participant_names(context: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	var transcript: Array = context.get("transcript", [])
	for participant_id in context.get("participant_ids", []):
		var participant_name := str(participant_id)
		for entry in transcript:
			if entry.get("speaker_id", "") == participant_id:
				participant_name = str(
					entry.get("speaker_name", participant_name),
				)
				break
		names.append(participant_name)
	return names


func _entry_label(entry: Dictionary) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var speaker_name := str(entry.get("speaker_name", ""))
	var text := str(entry.get("text", ""))
	match str(entry.get("entry_type", "")):
		"join_request":
			label.text = "%s（申请加入）：%s" % [speaker_name, text]
		"context_action":
			label.text = "%s（提供帮助）：%s" % [speaker_name, text]
		_:
			label.text = "%s：%s" % [speaker_name, text]
	return label


func _set_composer_enabled(enabled: bool) -> void:
	_player_text_edit.editable = enabled
	_submit_button.disabled = not enabled
	_offer_help_button.disabled = not enabled


func _state_text(join_status: String) -> String:
	match join_status:
		"requested":
			return "等待回应"
		"accepted":
			return "已加入"
		"declined":
			return "暂未获准"
		_:
			return "旁听中"


func _reason_text(reason: String) -> String:
	match reason:
		"join_required":
			return "请先申请加入对话。"
		"empty_text":
			return "请输入想说的话。"
		"declined":
			return "这次加入请求没有获准。"
		"conversation_not_found":
			return "对话已经结束。"
		_:
			return "当前无法执行该操作。"


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.free()


func _toggle_transcript() -> void:
	set_transcript_expanded(not _transcript_expanded)


func _on_text_submitted(_text: String) -> void:
	submit_current_text()


func _on_close_pressed() -> void:
	visible = false
	close_requested.emit()
