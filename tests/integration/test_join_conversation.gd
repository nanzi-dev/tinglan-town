extends GutTest

const CONVERSATION_SCENE_PATH := "res://scenes/ui/conversation_panel.tscn"
const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const NPC_SCENE_PATH := "res://scenes/actors/npc.tscn"


class FakeDialogueClient:
	extends MemoriaClient

	var payloads: Array[Dictionary] = []


	func request_dialogue_turn(payload: Dictionary) -> Error:
		payloads.append(payload.duplicate(true))
		return OK


func test_player_can_join_speak_offer_help_and_expand_transcript() -> void:
	var panel: Variant = await _spawn_scene(CONVERSATION_SCENE_PATH)
	if panel == null:
		return
	var manager := ConversationManager.new()
	var context := manager.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)
	var conversation_id: String = context["conversation_id"]

	panel.open_conversation(manager, conversation_id)

	assert_eq(panel.get_active_conversation_id(), conversation_id)
	assert_eq(_label(panel, "%ConversationTitleLabel").text, "听雨桥 · 林汐、沈砚")
	assert_eq(_label(panel, "%ConversationStateLabel").text, "旁听中")
	assert_false((_line_edit(panel, "%PlayerTextEdit")).editable)
	assert_true((_button(panel, "%JoinButton")).visible)

	assert_true(panel.request_join())
	assert_eq(manager.get_join_state(conversation_id), "accepted")
	assert_eq(_label(panel, "%ConversationStateLabel").text, "已加入")
	assert_true((_line_edit(panel, "%PlayerTextEdit")).editable)
	assert_false((_button(panel, "%JoinButton")).visible)

	_line_edit(panel, "%PlayerTextEdit").text = "我能帮忙吗？"
	assert_true(panel.submit_current_text())
	assert_true(panel.submit_offer_help())

	panel.set_transcript_expanded(true)

	assert_true((panel.get_node("%TranscriptPanel") as Control).visible)
	assert_eq(_button(panel, "%TranscriptToggleButton").text, "收起记录")
	var transcript_text := _all_control_text(panel.get_node("%TranscriptList"))
	assert_true(transcript_text.contains("近来经过听雨桥的人不少"))
	assert_true(transcript_text.contains("既然答应要管"))
	assert_true(transcript_text.contains("可以让我一起聊聊吗？"))
	assert_true(transcript_text.contains("我能帮忙吗？"))
	assert_true(transcript_text.contains("我可以帮忙。"))


func test_player_text_requests_memoria_and_displays_the_reply() -> void:
	var panel: Variant = await _spawn_scene(CONVERSATION_SCENE_PATH)
	if panel == null:
		return
	var manager := ConversationManager.new()
	var client := FakeDialogueClient.new()
	add_child_autoqfree(client)
	panel.configure_memoria_client(client)
	var context := manager.start_npc_conversation(
		["lin-xi"],
		"临水茶馆",
	)
	var conversation_id: String = context["conversation_id"]
	panel.open_conversation(manager, conversation_id)
	assert_true(panel.request_join())

	_line_edit(panel, "%PlayerTextEdit").text = "你好"
	assert_true(panel.submit_current_text())
	assert_eq(client.payloads.size(), 1)
	assert_eq(client.payloads[0]["character"]["character_id"], "lin-xi")
	assert_eq(client.payloads[0]["player_message"], "你好")
	assert_false(_line_edit(panel, "%PlayerTextEdit").editable)
	assert_true(
		_label(panel, "%FeedbackLabel").text.contains("等待林汐回应"),
	)

	var payload: Dictionary = client.payloads[0]
	client.dialogue_turn_completed.emit(
		payload["request_id"],
		{
			"ok": true,
			"request_id": payload["request_id"],
			"tick_id": payload["tick_id"],
			"character_id": "lin-xi",
			"dialogue": "你好。今天想喝点什么？",
			"source": "memoria",
			"fallback_reason": null,
		},
	)
	await wait_process_frames(1)

	assert_true(_line_edit(panel, "%PlayerTextEdit").editable)
	assert_true(
		_all_control_text(panel.get_node("%DialogueList")).contains(
			"林汐：你好。今天想喝点什么？",
		),
	)


func test_hud_opens_conversation_as_the_only_overlay() -> void:
	var hud: Variant = await _spawn_scene(HUD_SCENE_PATH)
	if hud == null:
		return

	var context: Dictionary = hud.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)
	var panel := hud.get_node("%ConversationPanel") as Control

	assert_not_null(panel)
	assert_false(context.is_empty())
	assert_true(panel.visible)
	assert_eq(
		panel.get_active_conversation_id(),
		context["conversation_id"],
	)
	assert_false((hud.get_node("%TaskBoardPanel") as Control).visible)
	assert_false((hud.get_node("%RelationshipPanel") as Control).visible)
	assert_false((hud.get_node("%InventoryPanel") as Control).visible)

	_button(panel, "%CloseButton").pressed.emit()

	assert_false(panel.visible)


func test_npc_scene_exposes_a_short_lived_speech_bubble() -> void:
	var npc: Variant = await _spawn_scene(NPC_SCENE_PATH)
	if npc == null:
		return
	var bubble: Variant = npc.get_node_or_null("%SpeechBubble")

	assert_not_null(bubble)
	if bubble == null:
		return
	assert_true(bubble.show_line("林汐", "先看看桥边的木料。"))
	assert_true(bubble.visible)
	assert_eq(bubble.get_speaker_name(), "林汐")
	assert_eq(bubble.get_line_text(), "先看看桥边的木料。")
	assert_true(bubble.text.contains("林汐"))
	assert_true(bubble.text.contains("先看看桥边的木料。"))

	bubble.hide_line()

	assert_false(bubble.visible)


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


func _line_edit(root: Node, path: String) -> LineEdit:
	var line_edit := root.get_node_or_null(path) as LineEdit
	assert_not_null(line_edit)
	return line_edit


func _button(root: Node, path: String) -> Button:
	var button := root.get_node_or_null(path) as Button
	assert_not_null(button)
	return button


func _all_control_text(root: Node) -> String:
	var parts: Array[String] = []
	_collect_control_text(root, parts)
	return "\n".join(parts)


func _collect_control_text(node: Node, parts: Array[String]) -> void:
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		_collect_control_text(child, parts)
