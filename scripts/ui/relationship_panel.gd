class_name RelationshipPanel
extends Control

signal close_requested

const THEME_FACTORY := preload("res://scripts/ui/theme_factory.gd")
const PUBLIC_STAGE_LABELS := ["初识", "熟悉", "亲近", "戒备"]

@onready var _resident_list: ItemList = %ResidentList
@onready var _resident_name_label: Label = %ResidentNameLabel
@onready var _stage_label: Label = %StageLabel
@onready var _reason_list: VBoxContainer = %ReasonList
@onready var _close_button: Button = %CloseButton

var _profiles: Array[Dictionary] = []


func _ready() -> void:
	theme = THEME_FACTORY.new().create_theme()
	_resident_list.item_selected.connect(_on_resident_selected)
	_close_button.pressed.connect(_on_close_pressed)
	show_profile("尚未选择居民", {
		"label": "初识",
		"recent_reasons": [],
	})


func set_profiles(profiles: Array) -> void:
	_profiles.clear()
	_resident_list.clear()
	for value in profiles:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var profile: Dictionary = value
		var resident_name = profile.get("name", null)
		var public_view = profile.get("public_view", null)
		if (
			typeof(resident_name) != TYPE_STRING
			or resident_name.is_empty()
			or typeof(public_view) != TYPE_DICTIONARY
		):
			continue
		_profiles.append({
			"name": resident_name,
			"public_view": public_view.duplicate(true),
		})
		_resident_list.add_item(resident_name)
	if not _profiles.is_empty():
		_resident_list.select(0)
		show_profile(_profiles[0]["name"], _profiles[0]["public_view"])


func show_profile(resident_name: String, public_view: Dictionary) -> void:
	_resident_name_label.text = resident_name
	var stage_label := str(public_view.get("label", "初识"))
	if stage_label not in PUBLIC_STAGE_LABELS:
		stage_label = "初识"
	_stage_label.text = stage_label

	for child in _reason_list.get_children():
		child.free()
	var reasons = public_view.get("recent_reasons", [])
	if typeof(reasons) != TYPE_ARRAY:
		reasons = []
	var rendered_count := 0
	for reason in reasons:
		if (
			rendered_count >= 3
			or typeof(reason) != TYPE_STRING
			or reason.is_empty()
		):
			continue
		var reason_label := Label.new()
		reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason_label.text = "· %s" % reason
		_reason_list.add_child(reason_label)
		rendered_count += 1
	if rendered_count == 0:
		var empty_label := Label.new()
		empty_label.text = "暂无近期变化"
		_reason_list.add_child(empty_label)


func _on_resident_selected(index: int) -> void:
	if index < 0 or index >= _profiles.size():
		return
	show_profile(_profiles[index]["name"], _profiles[index]["public_view"])


func _on_close_pressed() -> void:
	visible = false
	close_requested.emit()
