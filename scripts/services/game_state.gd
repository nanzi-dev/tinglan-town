class_name GameState
extends RefCounted

const MINUTES_PER_DAY := 1440
const TICKS_PER_DAY := (
	MINUTES_PER_DAY / SimulationScheduler.LOGIC_TICK_MINUTES
)
const RELATIONSHIP_DELTAS := [-2, -1, 1, 2]


func simulate_days(seed: int, days: int) -> Dictionary:
	var summary := _empty_summary(seed, days)
	if days <= 0:
		return summary

	var repository := ContentRepository.new()
	if not repository.load_spring():
		return summary

	var schedules_by_id := _items_by_id(
		repository.schedules,
		"schedule_id",
	)
	var agents := _build_agents(repository.characters, schedules_by_id)
	if agents.size() != repository.characters.size():
		_free_agents(agents)
		return summary

	var rng := DeterministicRng.new(seed)
	var scheduler := SimulationScheduler.new(rng)
	var agent_ids := _agent_ids(agents)
	var agent_indexes := _agent_indexes(agents)
	var tasks_by_issuer := _tasks_by_issuer(repository.task_templates)
	summary["unique_agents"] = agents.size()

	for day_index in range(days):
		var encountered_pairs := {}
		var assigned_work_tasks := {}
		for tick_index in range(TICKS_PER_DAY):
			var minute_of_day := (
				tick_index * SimulationScheduler.LOGIC_TICK_MINUTES
			)
			var world_minute := day_index * MINUTES_PER_DAY + minute_of_day
			scheduler.advance_logic_tick(world_minute, agent_ids)
			var occupants_by_location := _advance_agents(
				agents,
				scheduler,
				minute_of_day,
			)
			_record_task_changes(
				agents,
				assigned_work_tasks,
				tasks_by_issuer,
				repository.task_templates,
				rng,
				summary,
			)
			_record_encounters(
				day_index + 1,
				tick_index,
				occupants_by_location,
				encountered_pairs,
				agents,
				agent_indexes,
				rng,
				summary,
			)
		var daily_batches: Array = summary["social_batches_per_day"]
		daily_batches.append(scheduler.social_batches_today)
		summary["social_batches_per_day"] = daily_batches

	summary["final_agents"] = _final_agent_summaries(agents)
	_free_agents(agents)
	return summary


func _empty_summary(seed: int, days: int) -> Dictionary:
	return {
		"seed": seed,
		"days": days,
		"unique_agents": 0,
		"encounters": 0,
		"task_changes": 0,
		"relationship_changes": 0,
		"final_agents": [],
		"encounter_event_ids": [],
		"social_batches_per_day": [],
	}


func _build_agents(
	characters: Array,
	schedules_by_id: Dictionary,
) -> Array:
	var agents := []
	for character in characters:
		var schedule_id: String = character["schedule_id"]
		if not schedules_by_id.has(schedule_id):
			return agents
		var needs := NeedsComponent.new()
		var schedule := ScheduleComponent.new()
		if not schedule.configure(character, schedules_by_id[schedule_id]):
			needs.free()
			schedule.free()
			return agents
		agents.append({
			"character": character.duplicate(true),
			"needs": needs,
			"schedule": schedule,
			"state": schedule.state_at(0),
			"encounters": 0,
			"task_changes": 0,
			"last_task_id": "",
			"relationship_balance": 0,
		})
	return agents


func _advance_agents(
	agents: Array,
	scheduler: SimulationScheduler,
	minute_of_day: int,
) -> Dictionary:
	var occupants_by_location := {}
	for agent_index in range(agents.size()):
		var agent: Dictionary = agents[agent_index]
		var character: Dictionary = agent["character"]
		var schedule: ScheduleComponent = agent["schedule"]
		var state := schedule.state_at(minute_of_day)
		agent["state"] = state
		var character_id: String = character["character_id"]
		if scheduler.should_tick_offscreen(character_id):
			var needs: NeedsComponent = agent["needs"]
			needs.advance_minutes(
				SimulationScheduler.OFFSCREEN_TICK_MINUTES,
			)
		agents[agent_index] = agent

		var location_id: String = state["location_id"]
		var occupants: Array = occupants_by_location.get(location_id, [])
		occupants.append(character_id)
		occupants_by_location[location_id] = occupants
	return occupants_by_location


func _record_task_changes(
	agents: Array,
	assigned_work_tasks: Dictionary,
	tasks_by_issuer: Dictionary,
	all_tasks: Array,
	rng: DeterministicRng,
	summary: Dictionary,
) -> void:
	for agent_index in range(agents.size()):
		var agent: Dictionary = agents[agent_index]
		var character: Dictionary = agent["character"]
		var character_id: String = character["character_id"]
		if assigned_work_tasks.has(character_id):
			continue
		var state: Dictionary = agent["state"]
		if (
			state["location_id"] != character["work_location_id"]
			or state["activity"] == "sleep"
		):
			continue

		var eligible_tasks: Array = tasks_by_issuer.get(character_id, [])
		if eligible_tasks.is_empty():
			eligible_tasks = all_tasks
		var task_index := rng.next_int(0, eligible_tasks.size() - 1)
		var task: Dictionary = eligible_tasks[task_index]
		assigned_work_tasks[character_id] = true
		agent["task_changes"] = int(agent["task_changes"]) + 1
		agent["last_task_id"] = task["template_id"]
		agents[agent_index] = agent
		summary["task_changes"] = int(summary["task_changes"]) + 1


func _record_encounters(
	day_number: int,
	tick_index: int,
	occupants_by_location: Dictionary,
	encountered_pairs: Dictionary,
	agents: Array,
	agent_indexes: Dictionary,
	rng: DeterministicRng,
	summary: Dictionary,
) -> void:
	var location_ids := occupants_by_location.keys()
	location_ids.sort()
	for location_id in location_ids:
		var occupants: Array = occupants_by_location[location_id]
		occupants.sort()
		for first_offset in range(occupants.size()):
			for second_offset in range(first_offset + 1, occupants.size()):
				var first_id: String = occupants[first_offset]
				var second_id: String = occupants[second_offset]
				var pair_key := "%s:%s" % [first_id, second_id]
				if encountered_pairs.has(pair_key):
					continue
				encountered_pairs[pair_key] = true

				var event_id := "encounter:%d:%d:%s:%s" % [
					day_number,
					tick_index,
					first_id,
					second_id,
				]
				var event_ids: Array = summary["encounter_event_ids"]
				event_ids.append(event_id)
				summary["encounter_event_ids"] = event_ids
				summary["encounters"] = int(summary["encounters"]) + 1

				var delta_index := rng.next_int(
					0,
					RELATIONSHIP_DELTAS.size() - 1,
				)
				var relationship_delta: int = (
					RELATIONSHIP_DELTAS[delta_index]
				)
				_apply_relationship_change(
					agents,
					agent_indexes[first_id],
					relationship_delta,
				)
				_apply_relationship_change(
					agents,
					agent_indexes[second_id],
					relationship_delta,
				)
				summary["relationship_changes"] = (
					int(summary["relationship_changes"]) + 1
				)


func _apply_relationship_change(
	agents: Array,
	agent_index: int,
	delta: int,
) -> void:
	var agent: Dictionary = agents[agent_index]
	agent["encounters"] = int(agent["encounters"]) + 1
	agent["relationship_balance"] = (
		int(agent["relationship_balance"]) + delta
	)
	agents[agent_index] = agent


func _final_agent_summaries(agents: Array) -> Array:
	var final_agents := []
	for agent in agents:
		var character: Dictionary = agent["character"]
		var state: Dictionary = agent["state"]
		var needs: NeedsComponent = agent["needs"]
		final_agents.append({
			"character_id": character["character_id"],
			"location_id": state["location_id"],
			"activity": state["activity"],
			"needs": needs.get_levels(),
			"encounters": agent["encounters"],
			"task_changes": agent["task_changes"],
			"last_task_id": agent["last_task_id"],
			"relationship_balance": agent["relationship_balance"],
		})
	return final_agents


func _items_by_id(items: Array, id_field: String) -> Dictionary:
	var items_by_id := {}
	for item in items:
		items_by_id[item[id_field]] = item
	return items_by_id


func _tasks_by_issuer(tasks: Array) -> Dictionary:
	var result := {}
	for task in tasks:
		var issuer_id: String = task["issuer_id"]
		var issuer_tasks: Array = result.get(issuer_id, [])
		issuer_tasks.append(task)
		result[issuer_id] = issuer_tasks
	return result


func _agent_ids(agents: Array) -> Array:
	var ids := []
	for agent in agents:
		ids.append(agent["character"]["character_id"])
	ids.sort()
	return ids


func _agent_indexes(agents: Array) -> Dictionary:
	var indexes := {}
	for agent_index in range(agents.size()):
		indexes[agents[agent_index]["character"]["character_id"]] = agent_index
	return indexes


func _free_agents(agents: Array) -> void:
	for agent in agents:
		var needs: NeedsComponent = agent["needs"]
		var schedule: ScheduleComponent = agent["schedule"]
		needs.free()
		schedule.free()
