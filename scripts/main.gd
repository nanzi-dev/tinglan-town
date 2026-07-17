extends Node3D

const DEFAULT_SAVE_DIRECTORY := "user://saves/slot-01"
const DEFAULT_WORLD_ID := "tinglan-world-01"
const DEFAULT_SAVE_ID := "slot-01"
const MEMORIA_STATUS_LABELS := {
	"local_mode": "本地模式",
	"connecting": "连接中",
	"connected": "已连接",
	"recoverable_error": "可恢复错误",
	"protocol_error": "协议错误",
}

@export var memoria_save_directory := DEFAULT_SAVE_DIRECTORY
@export var memoria_world_id := DEFAULT_WORLD_ID
@export var memoria_save_id := DEFAULT_SAVE_ID
@export var auto_check_memoria := true
@export var enable_persistence := true
@export var persistence_unix_seconds_override := -1

@onready var _memoria_client: MemoriaClient = $MemoriaClient
@onready var _memoria_health_timer: Timer = $MemoriaHealthTimer
@onready var _hud: TownHud = $HUD

var pending_event_queue: PendingEventQueue


func _enter_tree() -> void:
	var runtime := get_node_or_null("TownRuntime") as TownRuntime
	if enable_persistence and runtime != null:
		runtime.configure_persistence(
			memoria_save_directory,
			_current_unix_seconds(),
		)
	if not tree_exiting.is_connected(_save_runtime_checkpoint):
		tree_exiting.connect(_save_runtime_checkpoint)


func _ready() -> void:
	pending_event_queue = PendingEventQueue.new(memoria_save_directory)
	_memoria_client.configure(
		str(ProjectSettings.get_setting(
			"memoria/base_url",
			MemoriaClient.DEFAULT_BASE_URL,
		)),
		OS.get_environment("MEMORIA_ACCESS_TOKEN"),
		pending_event_queue,
		null,
		null,
		memoria_world_id,
		memoria_save_id,
	)
	_hud.configure_memoria_client(_memoria_client)
	_memoria_client.connection_status_changed.connect(
		_on_memoria_connection_status_changed,
	)
	_memoria_health_timer.timeout.connect(_check_memoria_health)
	_on_memoria_connection_status_changed(
		_memoria_client.connection_status,
	)
	_flush_pending_events()
	if auto_check_memoria:
		_memoria_health_timer.start()
		_check_memoria_health()
	_hud.show_title_screen()


func _check_memoria_health() -> void:
	var error := _memoria_client.check_health()
	if error != OK and error != ERR_BUSY:
		_on_memoria_connection_status_changed("recoverable_error")


func _on_memoria_connection_status_changed(status: String) -> void:
	_hud.set_memoria_status(
		MEMORIA_STATUS_LABELS.get(status, "状态未知"),
	)
	if status == "connected":
		_flush_pending_events.call_deferred()


func _flush_pending_events() -> void:
	_memoria_client.flush_pending_events()


func _save_runtime_checkpoint() -> void:
	if not enable_persistence:
		return
	var runtime := get_node_or_null("TownRuntime") as TownRuntime
	if runtime != null:
		runtime.save_runtime_checkpoint(_current_unix_seconds())


func _current_unix_seconds() -> int:
	if persistence_unix_seconds_override >= 0:
		return persistence_unix_seconds_override
	return int(floor(Time.get_unix_time_from_system()))
