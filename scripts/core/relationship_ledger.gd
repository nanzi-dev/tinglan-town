class_name RelationshipLedger
extends RefCounted

const EVENT_CONSUMER_ID := "relationship_ledger"
const STAGE_LABELS := {
	"guarded": "戒备",
	"close": "亲近",
	"familiar": "熟悉",
	"acquainted": "初识",
}

var _event_log: DomainEventLog
var _relationships := {}


func _init(event_log: DomainEventLog = null) -> void:
	_event_log = event_log if event_log != null else DomainEventLog.new()


func apply_change(
	npc_id: Variant,
	affinity_delta: Variant,
	trust_delta: Variant,
	guard_delta: Variant,
	reason: Variant,
	event_id: Variant,
) -> bool:
	if (
		typeof(npc_id) != TYPE_STRING
		or npc_id.is_empty()
		or not _is_finite_number(affinity_delta)
		or not _is_finite_number(trust_delta)
		or not _is_finite_number(guard_delta)
		or typeof(reason) != TYPE_STRING
		or reason.is_empty()
		or typeof(event_id) != TYPE_STRING
		or event_id.is_empty()
	):
		return false

	var relationship: Dictionary = _relationships.get(npc_id, {
		"affinity": 0.0,
		"trust": 0.0,
		"guard": 0.0,
		"recent_reasons": [],
	})
	var next_affinity: float = relationship["affinity"] + float(affinity_delta)
	var next_trust: float = relationship["trust"] + float(trust_delta)
	var next_guard: float = relationship["guard"] + float(guard_delta)
	if (
		not _is_finite_number(next_affinity)
		or not _is_finite_number(next_trust)
		or not _is_finite_number(next_guard)
		or not _event_log.record_once(event_id, EVENT_CONSUMER_ID)
	):
		return false

	relationship["affinity"] = next_affinity
	relationship["trust"] = next_trust
	relationship["guard"] = next_guard
	relationship["recent_reasons"].push_front(reason)
	if relationship["recent_reasons"].size() > 3:
		relationship["recent_reasons"].resize(3)
	_relationships[npc_id] = relationship
	return true


func public_view(npc_id: Variant) -> Dictionary:
	var relationship: Dictionary = _relationships.get(npc_id, {
		"affinity": 0.0,
		"trust": 0.0,
		"guard": 0.0,
		"recent_reasons": [],
	})
	var stage := _stage_for(relationship)
	return {
		"stage": stage,
		"label": STAGE_LABELS[stage],
		"recent_reasons": relationship["recent_reasons"].duplicate(),
	}


func _stage_for(relationship: Dictionary) -> String:
	if relationship["guard"] >= 45.0:
		return "guarded"
	if relationship["trust"] >= 65.0 and relationship["affinity"] >= 60.0:
		return "close"
	if relationship["trust"] >= 30.0 or relationship["affinity"] >= 35.0:
		return "familiar"
	return "acquainted"


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)
