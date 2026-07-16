class_name TownHud
extends CanvasLayer

const THEME_FACTORY := preload("res://scripts/ui/theme_factory.gd")

@onready var _root: Control = $Root
@onready var _date_time_label: Label = %DateTimeLabel
@onready var _weather_label: Label = %WeatherLabel
@onready var _memoria_status_label: Label = %MemoriaStatusLabel
@onready var _interaction_prompt: Label = %InteractionPrompt
@onready var _task_summary_label: Label = %TaskSummaryLabel
@onready var _pause_panel: PanelContainer = %PausePanel
@onready var _pause_banner: Label = %PauseBanner
@onready var _task_board_panel: TaskBoardPanel = %TaskBoardPanel
@onready var _relationship_panel: RelationshipPanel = %RelationshipPanel
@onready var _inventory_panel: InventoryPanel = %InventoryPanel
@onready var _task_button: Button = %TaskButton
@onready var _relationship_button: Button = %RelationshipButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _quick_slot_one: Label = %QuickSlotOne
@onready var _quick_slot_two: Label = %QuickSlotTwo
@onready var _quick_slot_three: Label = %QuickSlotThree

var _paused := false
var _owns_tree_pause := false
var _task_board := TaskBoard.new()
var _relationship_ledger := RelationshipLedger.new()


func _ready() -> void:
	_root.theme = THEME_FACTORY.new().create_theme()
	_task_board_panel.set_task_board(_task_board)
	_task_button.pressed.connect(_show_task_board)
	_relationship_button.pressed.connect(_show_relationships)
	_inventory_button.pressed.connect(_show_inventory)
	_task_board_panel.close_requested.connect(_hide_overlays)
	_relationship_panel.close_requested.connect(_hide_overlays)
	_inventory_panel.close_requested.connect(_hide_overlays)
	_task_board_panel.task_published.connect(_on_task_published)
	update_status({
		"season": "春季",
		"day": 1,
		"minute_of_day": 420,
		"weather": "晴",
		"memoria_status": "本地模式",
		"interaction_prompt": "靠近居民或设施进行交互",
		"task_summary": "暂无进行中的任务",
	})
	set_inventory([])
	_load_initial_relationship_profiles()
	_hide_overlays()


func _exit_tree() -> void:
	if _owns_tree_pause and get_tree() != null:
		get_tree().paused = false


func update_status(status: Dictionary) -> void:
	var season := str(status.get("season", "春季"))
	var day := maxi(int(status.get("day", 1)), 1)
	var minute_of_day := clampi(int(status.get("minute_of_day", 0)), 0, 1439)
	@warning_ignore("integer_division")
	var hour := minute_of_day / 60
	var minute := minute_of_day % 60
	_date_time_label.text = "%s第 %d 日  %02d:%02d" % [
		season,
		day,
		hour,
		minute,
	]
	_weather_label.text = "天气：%s" % str(status.get("weather", "晴"))
	_memoria_status_label.text = "Memoria：%s" % str(
		status.get("memoria_status", "本地模式"),
	)
	_interaction_prompt.text = str(
		status.get("interaction_prompt", "暂无可交互目标"),
	)
	_task_summary_label.text = "当前任务：%s" % str(
		status.get("task_summary", "暂无进行中的任务"),
	)
	if status.has("paused"):
		set_paused(bool(status["paused"]))


func set_paused(value: bool) -> void:
	_paused = value
	_pause_panel.visible = value
	_pause_banner.visible = value
	_pause_banner.text = "游戏已暂停"


func set_inventory(items: Array) -> void:
	_inventory_panel.set_items(items)
	var quick_slots := [_quick_slot_one, _quick_slot_two, _quick_slot_three]
	for index in range(quick_slots.size()):
		var label: Label = quick_slots[index]
		if index < items.size() and typeof(items[index]) == TYPE_DICTIONARY:
			var item: Dictionary = items[index]
			label.text = "%s ×%d" % [
				str(item.get("name", "空位")),
				int(item.get("count", 0)),
			]
		else:
			label.text = "空位"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		_paused = not _paused
		set_paused(_paused)
		get_tree().paused = _paused
		_owns_tree_pause = _paused
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_tasks"):
		_show_task_board()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_inventory"):
		_show_inventory()
		get_viewport().set_input_as_handled()


func _show_task_board() -> void:
	_show_only(_task_board_panel)


func _show_relationships() -> void:
	_show_only(_relationship_panel)


func _show_inventory() -> void:
	_show_only(_inventory_panel)


func _show_only(panel: Control) -> void:
	for overlay in [
		_task_board_panel,
		_relationship_panel,
		_inventory_panel,
	]:
		overlay.visible = overlay == panel
	panel.grab_focus()


func _hide_overlays() -> void:
	_task_board_panel.visible = false
	_relationship_panel.visible = false
	_inventory_panel.visible = false


func _on_task_published(task: Dictionary) -> void:
	_task_summary_label.text = "当前任务：%s" % task["description"]


func _load_initial_relationship_profiles() -> void:
	var repository := ContentRepository.new()
	if not repository.load_spring():
		return
	var profiles := []
	for character in repository.characters:
		var character_id: String = character["character_id"]
		profiles.append({
			"name": character.get("name", character_id),
			"public_view": _relationship_ledger.public_view(character_id),
		})
	_relationship_panel.set_profiles(profiles)
