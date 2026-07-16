extends GutTest

const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const TASK_BOARD_SCENE_PATH := "res://scenes/ui/task_board_panel.tscn"
const RELATIONSHIP_SCENE_PATH := "res://scenes/ui/relationship_panel.tscn"
const INVENTORY_SCENE_PATH := "res://scenes/ui/inventory_panel.tscn"
const THEME_SCRIPT_PATH := "res://scripts/ui/theme_factory.gd"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"


func test_hud_shows_world_status_task_summary_and_pause_state() -> void:
	var hud: Variant = await _spawn_scene(HUD_SCENE_PATH)
	if hud == null:
		return

	hud.update_status({
		"season": "春季",
		"day": 3,
		"minute_of_day": 570,
		"weather": "细雨",
		"memoria_status": "已连接",
		"interaction_prompt": "E  与林汐交谈",
		"task_summary": "采集春草 2/5",
	})

	assert_eq(_label(hud, "%DateTimeLabel").text, "春季第 3 日  09:30")
	assert_eq(_label(hud, "%WeatherLabel").text, "天气：细雨")
	assert_eq(_label(hud, "%MemoriaStatusLabel").text, "Memoria：已连接")
	assert_eq(_label(hud, "%InteractionPrompt").text, "E  与林汐交谈")
	assert_eq(_label(hud, "%TaskSummaryLabel").text, "当前任务：采集春草 2/5")
	var pause_panel := hud.get_node("%PausePanel") as PanelContainer
	assert_false(pause_panel.visible)
	assert_false(_label(hud, "%PauseBanner").visible)

	hud.set_paused(true)

	assert_true(pause_panel.visible)
	assert_true(_label(hud, "%PauseBanner").visible)
	assert_true(_label(hud, "%PauseBanner").is_visible_in_tree())
	assert_eq(_label(hud, "%PauseBanner").text, "游戏已暂停")

	var main: Variant = await _spawn_scene(MAIN_SCENE_PATH)
	if main != null:
		assert_not_null(main.get_node_or_null("HUD"))


func test_player_can_publish_structured_task_and_sees_target_error() -> void:
	var panel: Variant = await _spawn_scene(TASK_BOARD_SCENE_PATH)
	if panel == null:
		return
	var board := TaskBoard.new()
	panel.set_task_board(board)

	var task_type := panel.get_node("%TaskTypeOption") as OptionButton
	var target_id := panel.get_node("%TargetIdEdit") as LineEdit
	var target_count := panel.get_node("%TargetCountSpin") as SpinBox
	var location := panel.get_node("%LocationEdit") as LineEdit
	var deadline_days := panel.get_node("%DeadlineDaysSpin") as SpinBox
	var deadline_minute := panel.get_node("%DeadlineMinuteSpin") as SpinBox
	var reward_coins := panel.get_node("%RewardCoinsSpin") as SpinBox
	var completion_rule := panel.get_node("%CompletionRuleOption") as OptionButton
	var description := panel.get_node("%DescriptionEdit") as TextEdit

	assert_true(_select_option(task_type, "gather"))
	assert_true(_select_option(completion_rule, "inventory_count"))
	target_id.text = "spring_herb"
	target_count.value = 5
	location.text = "town_outdoors"
	deadline_days.value = 2
	deadline_minute.value = 1080
	reward_coins.value = 80
	description.text = "收集五份春草，送到镇上的公告板。"

	assert_true(panel.submit_current_form())
	var submitted: Dictionary = panel.get_last_submitted_task()
	assert_eq(submitted["source"], "player")
	assert_eq(submitted["status"], "open")
	assert_eq(submitted["task_type"], "gather")
	assert_eq(submitted["objective"], {
		"type": "collect_item",
		"item_id": "spring_herb",
		"count": 5,
	})
	assert_eq(submitted["location_id"], "town_outdoors")
	assert_eq(submitted["deadline"], {"days": 2, "minute": 1080})
	assert_eq(submitted["reward"], {"coins": 80})
	assert_eq(submitted["completion_rules"], [{
		"type": "inventory_count",
		"item_id": "spring_herb",
		"count": 5,
	}])
	assert_eq(submitted["description"], "收集五份春草，送到镇上的公告板。")
	assert_eq(board.task_status(submitted["task_id"]), "open")

	target_id.text = ""

	assert_false(panel.submit_current_form())
	assert_eq(
		panel.get_field_errors().get("target_id", ""),
		"请填写结构化目标",
	)
	var target_error := _label(panel, "%TargetErrorLabel")
	assert_true(target_error.visible)
	assert_eq(target_error.text, "请填写结构化目标")


func test_relationship_panel_only_renders_public_stage_and_three_reasons() -> void:
	var panel: Variant = await _spawn_scene(RELATIONSHIP_SCENE_PATH)
	if panel == null:
		return
	var ledger := RelationshipLedger.new()
	for index in range(1, 5):
		assert_true(ledger.apply_change(
			"lin-xi",
			20,
			20,
			0,
			"共同完成了约定%s" % ["一", "二", "三", "四"][index - 1],
			"relationship-event-%d" % index,
		))
	var public_view := ledger.public_view("lin-xi")
	public_view["affinity"] = 80
	public_view["trust"] = 80
	public_view["guard"] = 0

	panel.show_profile("林汐", public_view)

	assert_eq(_label(panel, "%ResidentNameLabel").text, "林汐")
	assert_true(
		_label(panel, "%StageLabel").text in ["初识", "熟悉", "亲近", "戒备"],
	)
	var reasons := panel.get_node("%ReasonList") as VBoxContainer
	assert_eq(reasons.get_child_count(), 3)
	var rendered_text := _all_control_text(panel)
	assert_false(rendered_text.contains("affinity"))
	assert_false(rendered_text.contains("trust"))
	assert_false(rendered_text.contains("guard"))
	assert_false(rendered_text.contains("80"))


func test_inventory_and_theme_expose_readable_keyboard_controls() -> void:
	var panel: Variant = await _spawn_scene(INVENTORY_SCENE_PATH)
	if panel == null:
		return
	panel.set_items([
		{"item_id": "spring_herb", "name": "春草", "count": 5},
		{"item_id": "river_stone", "name": "河石", "count": 2},
	])

	assert_eq(panel.get_visible_items(), [
		{"item_id": "spring_herb", "name": "春草", "count": 5},
		{"item_id": "river_stone", "name": "河石", "count": 2},
	])
	assert_true(_all_control_text(panel).contains("春草"))
	assert_true(_all_control_text(panel).contains("5"))

	assert_true(ResourceLoader.exists(THEME_SCRIPT_PATH))
	if not ResourceLoader.exists(THEME_SCRIPT_PATH):
		return
	var theme_script := load(THEME_SCRIPT_PATH) as Script
	var factory: Variant = theme_script.new()
	var tokens: Dictionary = factory.get_tokens()
	assert_eq(tokens["ink"], Color("21302d"))
	assert_eq(tokens["paper"], Color("f4f1e8"))
	assert_gte(
		factory.contrast_ratio(tokens["ink"], tokens["paper"]),
		4.5,
	)

	for scene_path in [
		HUD_SCENE_PATH,
		TASK_BOARD_SCENE_PATH,
		RELATIONSHIP_SCENE_PATH,
		INVENTORY_SCENE_PATH,
	]:
		var control: Variant = await _spawn_scene(scene_path)
		if control == null:
			continue
		var buttons := _descendants_of_type(control, "Button")
		assert_gt(buttons.size(), 0)
		for button in buttons:
			assert_gte(button.custom_minimum_size.y, 44.0)
			assert_eq(button.focus_mode, Control.FOCUS_ALL)


func _spawn_scene(path: String) -> Variant:
	var exists := ResourceLoader.exists(path)
	assert_true(exists, "Missing scene %s." % path)
	if not exists:
		return null
	var packed := load(path) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var instance := packed.instantiate()
	add_child_autoqfree(instance)
	await wait_process_frames(1)
	return instance


func _label(root: Node, path: String) -> Label:
	var label := root.get_node_or_null(path) as Label
	assert_not_null(label)
	return label


func _select_option(option: OptionButton, metadata: String) -> bool:
	for index in range(option.item_count):
		if option.get_item_metadata(index) == metadata:
			option.select(index)
			return true
	return false


func _all_control_text(root: Node) -> String:
	var parts: Array[String] = []
	_collect_control_text(root, parts)
	return "\n".join(parts)


func _collect_control_text(node: Node, parts: Array[String]) -> void:
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	elif node is LineEdit:
		parts.append((node as LineEdit).text)
	elif node is TextEdit:
		parts.append((node as TextEdit).text)
	for child in node.get_children():
		_collect_control_text(child, parts)


func _descendants_of_type(root: Node, class_name_value: String) -> Array:
	var result := []
	_collect_descendants_of_type(root, class_name_value, result)
	return result


func _collect_descendants_of_type(
	node: Node,
	class_name_value: String,
	result: Array,
) -> void:
	if node.is_class(class_name_value):
		result.append(node)
	for child in node.get_children():
		_collect_descendants_of_type(child, class_name_value, result)
