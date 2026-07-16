class_name ConversationManager
extends RefCounted

const LOCAL_DIALOGUE := {
	"shen-yan": [
		"这件事不能只凭印象，先把来龙去脉理清吧。",
		"既然答应要管，就该把能做的事说清楚。",
	],
	"lin-xi": [
		"近来经过%s的人不少，大家都在留意这里。",
		"先听听彼此看见了什么，再商量怎么做。",
	],
	"zhou-he": [
		"先确认实际情况，别急着下结论。",
		"能处理的今天处理，不能处理的记清风险。",
	],
	"lu-qiao": [
		"手艺上的事不能含糊，哪里松了就得查哪里。",
		"先看材料和工序，光说担心没有用。",
	],
	"su-wan": [
		"我听见的消息不少，不过还是得一件件核对。",
		"要是能把话说明白，事情就没那么难办。",
	],
	"gu-yun": [
		"水路和岸上的动静不一样，得多看一会儿。",
		"先把该做的做了，剩下的再慢慢说。",
	],
	"tang-yu": [
		"要是大家一起想办法，事情一定能往前走。",
		"我先把要做的都记下来，免得漏掉。",
	],
	"qiao-zhen": [
		"牵涉大家的事，理由和次序都要留得清楚。",
		"先让每个人把话说完，再作判断。",
	],
	"he-miao": [
		"能搭把手就别干站着，先看看缺什么。",
		"事情摊开来说，总能找到肯出力的人。",
	],
	"xu-deng": [
		"镇上的风声总比船走得快，真假却得慢慢看。",
		"别把话说死，先留条能转身的路。",
	],
}

const LOCAL_JOIN_RESPONSES := {
	"shen-yan": "沈砚略作思量，点头请你加入。",
	"lin-xi": "林汐侧身让出位置，请你一起商量。",
	"zhou-he": "周禾请你先听完情况，再一起判断。",
	"lu-qiao": "陆桥点点头，让你直接说能做什么。",
	"su-wan": "苏晚松了口气，欢迎你一起想办法。",
	"gu-yun": "顾云向旁边让了一步，示意你继续听。",
	"tang-yu": "唐雨立刻招呼你加入，还给你留了位置。",
	"qiao-zhen": "乔贞请你先听完各方说法，再发表意见。",
	"he-miao": "何苗爽快地点头，问你愿意搭哪把手。",
	"xu-deng": "徐灯笑着招呼你靠近些，别漏了前因后果。",
}

var _conversations := {}
var _next_conversation_sequence := 0
var _character_names := {}


func _init() -> void:
	var repository := ContentRepository.new()
	if not repository.load_spring():
		return
	for character in repository.characters:
		_character_names[character["character_id"]] = character["name"]


func start_npc_conversation(
	participant_ids: Array,
	location_name: String,
) -> Dictionary:
	_next_conversation_sequence += 1
	var conversation_id := "conversation-%04d" % _next_conversation_sequence
	var context := {
		"conversation_id": conversation_id,
		"participant_ids": participant_ids.duplicate(),
		"topic": (
			"%s近况" % location_name
			if not location_name.is_empty()
			else "镇中近况"
		),
		"occasion": "npc_chat",
		"player_listening": false,
		"join_status": "listening",
		"memoria_thread_id": "",
		"transcript": [],
		"location_name": location_name,
	}
	for index in range(participant_ids.size()):
		var participant_id := str(participant_ids[index])
		_append_entry(context, {
			"entry_type": "npc_dialogue",
			"speaker_id": participant_id,
			"speaker_name": _speaker_name(participant_id),
			"text": _local_npc_line(
				participant_id,
				index,
				location_name,
			),
		})
	_conversations[conversation_id] = context
	return context.duplicate(true)


func listen(conversation_id: String) -> Dictionary:
	if not _conversations.has(conversation_id):
		return {"accepted": false, "reason": "conversation_not_found"}
	var conversation: Dictionary = _conversations[conversation_id]
	conversation["player_listening"] = true
	return {"accepted": true, "state": "listening"}


func request_join(conversation_id: String) -> Dictionary:
	if not _conversations.has(conversation_id):
		return {"accepted": false, "reason": "conversation_not_found"}
	var conversation: Dictionary = _conversations[conversation_id]
	if not conversation.get("player_listening", false):
		return {"accepted": false, "reason": "listen_required"}
	if conversation["join_status"] != "listening":
		return {"accepted": false, "reason": "invalid_transition"}

	conversation["join_status"] = "requested"
	_append_entry(conversation, {
		"entry_type": "join_request",
		"speaker_id": "player",
		"speaker_name": "你",
		"text": "可以让我一起聊聊吗？",
	})
	return {"accepted": true, "state": "requested"}


func resolve_join_request(
	conversation_id: String,
	decision: Dictionary = {},
) -> Dictionary:
	if not _conversations.has(conversation_id):
		return {"accepted": false, "reason": "conversation_not_found"}
	var conversation: Dictionary = _conversations[conversation_id]
	if conversation["join_status"] != "requested":
		return {"accepted": false, "reason": "invalid_transition"}

	var source := str(decision.get("source", "local"))
	var has_external_decision := typeof(decision.get("accepted")) == TYPE_BOOL
	if not has_external_decision:
		source = "local"
	var accepted := (
		bool(decision["accepted"])
		if has_external_decision
		else _local_join_allowed(conversation)
	)
	var respondent_id := _primary_respondent_id(conversation)
	var response_text := str(decision.get("response_text", "")).strip_edges()
	if response_text.is_empty():
		response_text = _local_join_response(respondent_id, accepted)

	conversation["join_status"] = "accepted" if accepted else "declined"
	_append_entry(conversation, {
		"entry_type": "join_response",
		"speaker_id": respondent_id,
		"speaker_name": _speaker_name(respondent_id),
		"text": response_text,
		"source": source,
		"accepted": accepted,
	})
	return {
		"accepted": accepted,
		"reason": "" if accepted else "declined",
		"state": conversation["join_status"],
		"source": source,
		"response_text": response_text,
	}


func submit_player_text(
	conversation_id: String,
	text: String,
) -> Dictionary:
	if not _conversations.has(conversation_id):
		return {"accepted": false, "reason": "conversation_not_found"}
	var conversation: Dictionary = _conversations[conversation_id]
	if conversation["join_status"] != "accepted":
		return {"accepted": false, "reason": "join_required"}
	var normalized_text := text.strip_edges()
	if normalized_text.is_empty():
		return {"accepted": false, "reason": "empty_text"}
	_append_entry(conversation, {
		"entry_type": "player_dialogue",
		"speaker_id": "player",
		"speaker_name": "你",
		"text": normalized_text,
	})
	return {"accepted": true, "reason": "", "text": normalized_text}


func submit_context_action(
	conversation_id: String,
	action_id: String,
) -> Dictionary:
	if not _conversations.has(conversation_id):
		return {"accepted": false, "reason": "conversation_not_found"}
	var conversation: Dictionary = _conversations[conversation_id]
	if conversation["join_status"] != "accepted":
		return {"accepted": false, "reason": "join_required"}
	if action_id != "offer_help":
		return {"accepted": false, "reason": "unknown_action"}

	_append_entry(conversation, {
		"entry_type": "context_action",
		"speaker_id": "player",
		"speaker_name": "你",
		"action_id": action_id,
		"text": "我可以帮忙。",
	})
	return {
		"accepted": true,
		"reason": "",
		"action_id": action_id,
	}


func get_join_state(conversation_id: String) -> String:
	if not _conversations.has(conversation_id):
		return ""
	return str(_conversations[conversation_id]["join_status"])


func get_context(conversation_id: String) -> Dictionary:
	if not _conversations.has(conversation_id):
		return {}
	return (_conversations[conversation_id] as Dictionary).duplicate(true)


func get_transcript(conversation_id: String) -> Array:
	if not _conversations.has(conversation_id):
		return []
	var conversation: Dictionary = _conversations[conversation_id]
	return (conversation["transcript"] as Array).duplicate(true)


func _append_entry(conversation: Dictionary, entry: Dictionary) -> void:
	var transcript: Array = conversation["transcript"]
	transcript.append(entry)


func _local_npc_line(
	character_id: String,
	index: int,
	location_name: String,
) -> String:
	var lines: Array = LOCAL_DIALOGUE.get(character_id, [
		"这件事值得仔细商量。",
		"先把眼前的情况说清楚吧。",
	])
	var line := str(lines[index % lines.size()])
	if line.contains("%s"):
		return line % (
			location_name if not location_name.is_empty() else "镇上"
		)
	return line


func _local_join_allowed(conversation: Dictionary) -> bool:
	return not (conversation["participant_ids"] as Array).is_empty()


func _local_join_response(
	respondent_id: String,
	accepted: bool,
) -> String:
	if accepted:
		return str(LOCAL_JOIN_RESPONSES.get(
			respondent_id,
			"对方点点头，请你一起加入。",
		))
	return "%s婉拒了这次加入请求。" % _speaker_name(respondent_id)


func _primary_respondent_id(conversation: Dictionary) -> String:
	var participant_ids: Array = conversation["participant_ids"]
	if participant_ids.is_empty():
		return ""
	return str(participant_ids[0])


func _speaker_name(character_id: String) -> String:
	return str(_character_names.get(character_id, character_id))
