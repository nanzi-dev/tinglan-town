class_name InventoryPanel
extends Control

signal close_requested

const THEME_FACTORY := preload("res://scripts/ui/theme_factory.gd")

@onready var _item_list: VBoxContainer = %ItemList
@onready var _empty_label: Label = %EmptyLabel
@onready var _close_button: Button = %CloseButton

var _items: Array[Dictionary] = []


func _ready() -> void:
	theme = THEME_FACTORY.new().create_theme()
	_close_button.pressed.connect(_on_close_pressed)
	_render_items()


func set_items(items: Array) -> void:
	_items.clear()
	for value in items:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = value
		if (
			typeof(item.get("item_id", null)) != TYPE_STRING
			or item["item_id"].is_empty()
			or typeof(item.get("name", null)) != TYPE_STRING
			or item["name"].is_empty()
			or typeof(item.get("count", null)) != TYPE_INT
			or item["count"] < 0
		):
			continue
		_items.append({
			"item_id": item["item_id"],
			"name": item["name"],
			"count": item["count"],
		})
	_render_items()


func get_visible_items() -> Array[Dictionary]:
	return _items.duplicate(true)


func _render_items() -> void:
	if not is_node_ready():
		return
	for child in _item_list.get_children():
		child.queue_free()
	_empty_label.visible = _items.is_empty()
	for item in _items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = item["name"]
		var count_label := Label.new()
		count_label.text = "× %d" % item["count"]
		row.add_child(name_label)
		row.add_child(count_label)
		_item_list.add_child(row)


func _on_close_pressed() -> void:
	visible = false
	close_requested.emit()
