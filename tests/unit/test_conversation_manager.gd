extends GutTest

const MANAGER_SCRIPT_PATH := "res://scripts/services/conversation_manager.gd"


func test_context_uses_the_approved_conversation_contract() -> void:
	var manager: Variant = _manager()
	if manager == null:
		return
	var context: Dictionary = manager.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)

	for field in [
		"conversation_id",
		"participant_ids",
		"topic",
		"occasion",
		"player_listening",
		"join_status",
		"memoria_thread_id",
		"transcript",
	]:
		assert_true(context.has(field), "Missing ConversationContext.%s." % field)
	assert_false(context.get("player_listening", true))
	assert_eq(context.get("join_status", ""), "listening")
	assert_eq(context.get("memoria_thread_id", "missing"), "")


func test_player_cannot_speak_before_join_is_accepted() -> void:
	var manager: Variant = _manager()
	if manager == null:
		return
	var context: Dictionary = manager.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)

	manager.listen(context["conversation_id"])
	var result: Dictionary = manager.submit_player_text(
		context["conversation_id"],
		"我能帮忙吗？",
	)

	assert_false(result["accepted"])
	assert_eq(result["reason"], "join_required")


func test_join_state_only_follows_requested_then_resolved() -> void:
	var manager: Variant = _manager()
	if manager == null:
		return
	var context: Dictionary = manager.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)
	var conversation_id: String = context["conversation_id"]

	assert_eq(manager.get_join_state(conversation_id), "listening")
	var before_listening: Dictionary = manager.request_join(conversation_id)
	assert_false(before_listening["accepted"])
	if before_listening["accepted"]:
		return
	assert_eq(before_listening.get("reason", ""), "listen_required")
	assert_eq(manager.get_join_state(conversation_id), "listening")
	var premature: Dictionary = manager.resolve_join_request(
		conversation_id,
		{"accepted": true},
	)
	assert_false(premature["accepted"])
	assert_eq(premature["reason"], "invalid_transition")
	assert_eq(manager.get_join_state(conversation_id), "listening")

	assert_true(manager.listen(conversation_id)["accepted"])
	var request: Dictionary = manager.request_join(conversation_id)
	assert_true(request["accepted"])
	assert_eq(manager.get_join_state(conversation_id), "requested")
	var duplicate: Dictionary = manager.request_join(conversation_id)
	assert_false(duplicate["accepted"])
	assert_eq(duplicate["reason"], "invalid_transition")

	var resolution: Dictionary = manager.resolve_join_request(
		conversation_id,
		{
			"accepted": true,
			"source": "memoria",
			"response_text": "林汐向你点头，请你一起商量。",
		},
	)
	assert_true(resolution["accepted"])
	assert_eq(resolution["source"], "memoria")
	assert_eq(manager.get_join_state(conversation_id), "accepted")

	var repeated_resolution: Dictionary = manager.resolve_join_request(
		conversation_id,
		{"accepted": false},
	)
	assert_false(repeated_resolution["accepted"])
	assert_eq(repeated_resolution["reason"], "invalid_transition")
	assert_eq(manager.get_join_state(conversation_id), "accepted")


func test_transcript_keeps_npc_join_player_and_context_action_entries() -> void:
	var manager: Variant = _manager()
	if manager == null:
		return
	var context: Dictionary = manager.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)
	var conversation_id: String = context["conversation_id"]

	assert_true(manager.listen(conversation_id)["accepted"])
	assert_true(manager.request_join(conversation_id)["accepted"])
	var resolution: Dictionary = manager.resolve_join_request(
		conversation_id,
		{},
	)
	assert_true(resolution["accepted"])
	assert_eq(resolution["source"], "local")
	assert_true(
		manager.submit_player_text(conversation_id, "我能帮忙吗？")["accepted"],
	)
	var action: Dictionary = manager.submit_context_action(
		conversation_id,
		"offer_help",
	)
	assert_true(action["accepted"])
	assert_eq(action["action_id"], "offer_help")

	var transcript: Array = manager.get_transcript(conversation_id)
	assert_gte(transcript.size(), 6)
	assert_eq(transcript[0]["entry_type"], "npc_dialogue")
	assert_eq(transcript[1]["entry_type"], "npc_dialogue")
	assert_eq(transcript[2]["entry_type"], "join_request")
	assert_eq(transcript[3]["entry_type"], "join_response")
	assert_eq(transcript[4], {
		"entry_type": "player_dialogue",
		"speaker_id": "player",
		"speaker_name": "你",
		"text": "我能帮忙吗？",
	})
	assert_eq(transcript[5], {
		"entry_type": "context_action",
		"speaker_id": "player",
		"speaker_name": "你",
		"action_id": "offer_help",
		"text": "我可以帮忙。",
	})

	transcript[0]["text"] = "被外部改写"
	assert_ne(
		manager.get_transcript(conversation_id)[0]["text"],
		"被外部改写",
	)


func test_memoria_reply_uses_primary_participant_profile_and_updates_transcript() -> void:
	var manager: Variant = _manager()
	if manager == null:
		return
	var context: Dictionary = manager.start_npc_conversation(
		["lin-xi"],
		"临水茶馆",
	)
	var conversation_id: String = context["conversation_id"]
	var profile: Dictionary = manager.get_primary_participant_profile(
		conversation_id,
	)

	assert_eq(profile["character_id"], "lin-xi")
	assert_eq(profile["name"], "林汐")
	assert_eq(profile["role"], "茶馆掌柜")
	assert_true(manager.append_npc_reply(
		conversation_id,
		"lin-xi",
		"今天刚试了一壶春茶，你要尝尝吗？",
		"memoria",
	)["accepted"])

	var transcript: Array = manager.get_transcript(conversation_id)
	var reply: Dictionary = transcript[-1]
	assert_eq(reply["entry_type"], "npc_dialogue")
	assert_eq(reply["speaker_id"], "lin-xi")
	assert_eq(reply["speaker_name"], "林汐")
	assert_eq(reply["text"], "今天刚试了一壶春茶，你要尝尝吗？")
	assert_eq(reply["source"], "memoria")


func test_declined_join_keeps_player_from_speaking() -> void:
	var manager: Variant = _manager()
	if manager == null:
		return
	var context: Dictionary = manager.start_npc_conversation(
		["qiao-zhen", "xu-deng"],
		"议事厅",
	)
	var conversation_id: String = context["conversation_id"]

	assert_true(manager.listen(conversation_id)["accepted"])
	assert_true(manager.request_join(conversation_id)["accepted"])
	var resolution: Dictionary = manager.resolve_join_request(
		conversation_id,
		{
			"accepted": false,
			"source": "memoria",
			"response_text": "乔贞请你稍后再来。",
		},
	)

	assert_false(resolution["accepted"])
	assert_eq(resolution["reason"], "declined")
	assert_eq(resolution["state"], "declined")
	assert_eq(manager.get_join_state(conversation_id), "declined")
	var speech: Dictionary = manager.submit_player_text(
		conversation_id,
		"我先听着。",
	)
	assert_false(speech["accepted"])
	assert_eq(speech["reason"], "join_required")


func _manager() -> Variant:
	var script_exists := ResourceLoader.exists(MANAGER_SCRIPT_PATH)
	assert_true(script_exists, "ConversationManager script must exist.")
	if not script_exists:
		return null
	var manager_script := load(MANAGER_SCRIPT_PATH) as Script
	assert_not_null(manager_script)
	if manager_script == null:
		return null
	return manager_script.new()
