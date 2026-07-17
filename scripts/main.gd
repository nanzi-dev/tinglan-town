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

@onready var _memoria_client: MemoriaClient = $MemoriaClient
@onready var _memoria_health_timer: Timer = $MemoriaHealthTimer
@onready var _hud: TownHud = $HUD

var pending_event_queue: PendingEventQueue


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
	_memoria_client.connection_status_changed.connect(
		_on_memoria_connection_status_changed,
	)
	_memoria_health_timer.timeout.connect(_check_memoria_health)
	_on_memoria_connection_status_changed(
		_memoria_client.connection_status,
	)
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
