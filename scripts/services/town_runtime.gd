class_name TownRuntime
extends Node

const INITIAL_MINUTE := 7 * 60
const RUNTIME_SEED := 20260716
const NEARBY_SIMULATION_DISTANCE := 12.0
const OUTDOOR_TARGETS := {
	"shen-yan": Vector3(-15.0, 0.05, -5.0),
	"lin-xi": Vector3(-14.0, 0.05, 1.0),
	"zhou-he": Vector3(15.0, 0.05, 12.0),
	"lu-qiao": Vector3(15.0, 0.05, 5.0),
	"su-wan": Vector3(14.0, 0.05, -1.0),
	"gu-yun": Vector3(-17.0, 0.05, 6.0),
	"tang-yu": Vector3(16.0, 0.05, -4.0),
	"qiao-zhen": Vector3(-12.0, 0.05, 13.0),
	"he-miao": Vector3(-18.0, 0.05, 2.0),
	"xu-deng": Vector3(-15.0, 0.05, 10.0),
}

@export var town_path := NodePath("../Town")
@export var residents_path := NodePath("../Residents")
@export var player_path := NodePath("../Player")
@export var hud_path := NodePath("../HUD")
@export var resident_scene: PackedScene
@export var interaction_distance := 2.0

var _clock := WorldClock.new()
var _scheduler := SimulationScheduler.new(RUNTIME_SEED)
var _event_log := DomainEventLog.new()
var _task_board := TaskBoard.new(_event_log)
var _relationship_ledger := RelationshipLedger.new(_event_log)
var _conversation_manager := ConversationManager.new()
var _repository := ContentRepository.new()
var _residents: Dictionary = {}
var _location_names: Dictionary = {}
var _last_logic_tick := INITIAL_MINUTE
var _save_coordinator: SaveCoordinator
var _persistence_restore_unix_seconds := -1
var _last_catchup_result: Dictionary = {}

var _town: TownBuilder
var _residents_root: Node3D
var _player: CharacterBody3D
var _hud: TownHud


func _ready() -> void:
	_town = get_node_or_null(town_path) as TownBuilder
	_residents_root = get_node_or_null(residents_path) as Node3D
	_player = get_node_or_null(player_path) as CharacterBody3D
	_hud = get_node_or_null(hud_path) as TownHud
	if (
		_town == null
		or _residents_root == null
		or _player == null
		or _hud == null
		or resident_scene == null
		or not _repository.load_spring()
	):
		push_error("TownRuntime could not initialize the spring town.")
		set_process(false)
		set_process_unhandled_input(false)
		return

	_clock.advance_game_minutes(INITIAL_MINUTE)
	for location in _repository.locations:
		_location_names[location["location_id"]] = location["name"]
	_hud.configure_services(
		_task_board,
		_relationship_ledger,
		_conversation_manager,
	)
	if not _spawn_residents():
		push_error("TownRuntime could not configure all spring residents.")
		set_process(false)
		set_process_unhandled_input(false)
		return
	if not _restore_runtime_checkpoint():
		_scheduler.advance_logic_tick(
			_clock.total_minutes,
			_offscreen_ids(),
		)
	_update_hud()


func _process(delta: float) -> void:
	advance_real_seconds(delta)
	_update_interaction_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var resident := _nearest_resident()
	if resident == null:
		return
	var state := resident.get_schedule_state()
	var location_id := str(state.get("location_id", "town_outdoors"))
	_hud.start_npc_conversation(
		[resident.get_character_id()],
		str(_location_names.get(location_id, "听澜镇")),
	)
	get_viewport().set_input_as_handled()


func advance_real_seconds(seconds: float) -> void:
	var previous_minute := _clock.total_minutes
	_clock.advance_real_seconds(seconds)
	if _clock.total_minutes == previous_minute:
		return

	var next_tick := _last_logic_tick + SimulationScheduler.LOGIC_TICK_MINUTES
	while next_tick <= _clock.total_minutes:
		_run_logic_tick(next_tick)
		_last_logic_tick = next_tick
		next_tick += SimulationScheduler.LOGIC_TICK_MINUTES
	_update_hud()


func configure_persistence(
	save_directory: String,
	now_unix_seconds: int,
) -> void:
	if save_directory.is_empty() or now_unix_seconds < 0:
		_save_coordinator = null
		_persistence_restore_unix_seconds = -1
		return
	_save_coordinator = SaveCoordinator.new(save_directory)
	_persistence_restore_unix_seconds = now_unix_seconds


func save_runtime_checkpoint(now_unix_seconds: int) -> Error:
	if _save_coordinator == null:
		return ERR_UNCONFIGURED
	if now_unix_seconds < 0:
		return ERR_INVALID_PARAMETER

	var resident_states := {}
	for character_id in _residents:
		var state := (_residents[character_id] as ResidentActor).to_dict()
		if state.is_empty():
			return ERR_INVALID_DATA
		resident_states[character_id] = state
	return _save_coordinator.save_checkpoint(
		{
			"clock": _clock.to_dict(),
			"scheduler": _scheduler.to_dict(),
			"last_logic_tick": _last_logic_tick,
			"saved_at_unix_seconds": now_unix_seconds,
			"residents": resident_states,
		},
		-1,
		[],
	)


func get_clock_snapshot() -> Dictionary:
	var snapshot := _clock.to_dict()
	snapshot["day"] = _clock.day
	snapshot["minute_of_day"] = _clock.minute_of_day
	return snapshot


func get_resident_ids() -> Array:
	return _residents.keys()


func get_residents() -> Array:
	return _residents.values()


func get_resident(character_id: String) -> ResidentActor:
	return _residents.get(character_id) as ResidentActor


func get_task_board() -> TaskBoard:
	return _task_board


func get_relationship_ledger() -> RelationshipLedger:
	return _relationship_ledger


func get_conversation_manager() -> ConversationManager:
	return _conversation_manager


func get_last_catchup_result() -> Dictionary:
	return _last_catchup_result.duplicate(true)


func get_scheduler_snapshot() -> Dictionary:
	return _scheduler.to_dict()


func _spawn_residents() -> bool:
	var schedules_by_id := {}
	for schedule in _repository.schedules:
		schedules_by_id[schedule["schedule_id"]] = schedule

	for character in _repository.characters:
		var schedule_id: String = character["schedule_id"]
		if not schedules_by_id.has(schedule_id):
			return false
		var resident := resident_scene.instantiate() as ResidentActor
		if resident == null:
			return false
		resident.name = str(character["character_id"]).to_pascal_case()
		_residents_root.add_child(resident)
		if not resident.configure(character, schedules_by_id[schedule_id]):
			resident.queue_free()
			return false
		var targets := _location_targets_for(character["character_id"])
		resident.set_location_targets(targets)
		var state := resident.advance_schedule(_clock.minute_of_day)
		var location_id := str(state.get(
			"location_id",
			character["home_location_id"],
		))
		resident.global_position = targets.get(
			location_id,
			Vector3.ZERO,
		)
		_residents[resident.get_character_id()] = resident
	return _residents.size() == _repository.characters.size()


func _restore_runtime_checkpoint() -> bool:
	if _save_coordinator == null:
		return false
	var recovered := _save_coordinator.recover()
	if not recovered.get("ok", false):
		return false
	var state: Dictionary = recovered["world_state"]
	if not _is_valid_runtime_state(state):
		return false

	_clock.restore(state["clock"])
	_scheduler.restore(state["scheduler"])
	_last_logic_tick = state["last_logic_tick"]
	for character_id in _residents:
		var resident := _residents[character_id] as ResidentActor
		if not resident.restore(
			state["residents"][character_id],
			_clock.minute_of_day,
		):
			return false

	var elapsed_real_seconds := maxi(
		0,
		_persistence_restore_unix_seconds
		- int(state["saved_at_unix_seconds"]),
	)
	_last_catchup_result = _save_coordinator.calculate_catchup(
		_clock.total_minutes,
		elapsed_real_seconds,
	)
	_apply_catchup(_last_catchup_result)
	return true


func _apply_catchup(catchup: Dictionary) -> void:
	if catchup.is_empty():
		return
	var target_tick: int = catchup["to_tick"]
	var elapsed_minutes := target_tick - _clock.total_minutes
	var was_paused := _clock.paused
	_clock.set_paused(false)
	_clock.advance_game_minutes(elapsed_minutes)
	_clock.set_paused(was_paused)

	var next_tick := (
		_last_logic_tick + SimulationScheduler.LOGIC_TICK_MINUTES
	)
	while next_tick <= target_tick:
		_run_logic_tick(next_tick)
		_last_logic_tick = next_tick
		next_tick += SimulationScheduler.LOGIC_TICK_MINUTES


func _is_valid_runtime_state(state: Dictionary) -> bool:
	if (
		typeof(state.get("clock", null)) != TYPE_DICTIONARY
		or typeof(state.get("scheduler", null)) != TYPE_DICTIONARY
		or typeof(state.get("last_logic_tick", null)) != TYPE_INT
		or typeof(state.get("saved_at_unix_seconds", null)) != TYPE_INT
		or state["saved_at_unix_seconds"] < 0
		or typeof(state.get("residents", null)) != TYPE_DICTIONARY
	):
		return false

	var candidate_clock := WorldClock.new()
	candidate_clock.restore(state["clock"])
	if candidate_clock.to_dict() != state["clock"]:
		return false
	var candidate_scheduler := SimulationScheduler.new(RUNTIME_SEED)
	candidate_scheduler.restore(state["scheduler"])
	if candidate_scheduler.to_dict() != state["scheduler"]:
		return false

	var last_logic_tick: int = state["last_logic_tick"]
	if (
		last_logic_tick < INITIAL_MINUTE
		or last_logic_tick % SimulationScheduler.LOGIC_TICK_MINUTES != 0
		or last_logic_tick > candidate_clock.total_minutes
		or last_logic_tick != candidate_scheduler.to_dict()["last_world_minute"]
	):
		return false

	var resident_states: Dictionary = state["residents"]
	if resident_states.size() != _residents.size():
		return false
	for character_id in _residents:
		var resident_state = resident_states.get(character_id, null)
		if (
			typeof(resident_state) != TYPE_DICTIONARY
			or resident_state.get("character_id", null) != character_id
			or typeof(resident_state.get("needs", null)) != TYPE_DICTIONARY
		):
			return false
		var candidate_needs := NeedsComponent.new()
		var valid_needs := candidate_needs.restore(
			resident_state["needs"],
		)
		candidate_needs.free()
		if not valid_needs:
			return false
	return true


func _location_targets_for(character_id: String) -> Dictionary:
	var targets := {
		"town_outdoors": OUTDOOR_TARGETS.get(
			character_id,
			Vector3(-15.0, 0.05, 0.0),
		),
	}
	for entrance_id in _town.get_entrance_ids():
		var entrance := _town.get_entrance(entrance_id)
		if entrance != null:
			targets[entrance_id] = entrance.global_position
	return targets


func _run_logic_tick(world_minute: int) -> void:
	var offscreen_ids := _offscreen_ids()
	_scheduler.advance_logic_tick(world_minute, offscreen_ids)
	for resident_value in _residents.values():
		var resident := resident_value as ResidentActor
		resident.advance_schedule(world_minute % WorldClock.MINUTES_PER_DAY)
		if offscreen_ids.has(resident.get_character_id()):
			if _scheduler.should_tick_offscreen(resident.get_character_id()):
				resident.advance_needs(
					SimulationScheduler.OFFSCREEN_TICK_MINUTES,
				)
		else:
			resident.advance_needs(
				SimulationScheduler.LOGIC_TICK_MINUTES,
			)


func _offscreen_ids() -> Array:
	var result := []
	if _player == null:
		return result
	for resident_value in _residents.values():
		var resident := resident_value as ResidentActor
		if _horizontal_distance(
			resident.global_position,
			_player.global_position,
		) > NEARBY_SIMULATION_DISTANCE:
			result.append(resident.get_character_id())
	return result


func _nearest_resident() -> ResidentActor:
	var nearest: ResidentActor
	var nearest_distance := interaction_distance
	for resident_value in _residents.values():
		var resident := resident_value as ResidentActor
		var distance := _horizontal_distance(
			resident.global_position,
			_player.global_position,
		)
		if distance <= nearest_distance:
			nearest = resident
			nearest_distance = distance
	return nearest


func _update_hud() -> void:
	_hud.set_world_time(_clock.day, _clock.minute_of_day)


func _update_interaction_prompt() -> void:
	var resident := _nearest_resident()
	if resident == null:
		_hud.set_interaction_prompt("靠近居民或设施进行交互")
	else:
		_hud.set_interaction_prompt(
			"E  与%s交谈" % resident.get_display_name(),
		)


func _horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))
