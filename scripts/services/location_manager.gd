class_name LocationManager
extends Node

signal entered_interior(location_id: String)
signal returned_outdoors

@export var town_path := NodePath("../Town")
@export var player_path := NodePath("../Player")
@export var interior_root_path := NodePath("../Interiors")
@export var interior_scene: PackedScene
@export var interaction_distance := 1.5

var _town: Node3D
var _player: CharacterBody3D
var _interior_root: Node3D
var _active_interior: Node3D
var _active_location_id := ""
var _saved_outdoor_position := Vector3.ZERO
var _has_saved_outdoor_position := false
var _repository := ContentRepository.new()
var _content_loaded := false


func _ready() -> void:
	_resolve_scene_nodes()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _active_interior != null:
		var exit_point := _active_interior.get_node_or_null(
			"ExteriorExit",
		) as Marker3D
		if (
			exit_point != null
			and _horizontal_distance(
				_player.global_position,
				exit_point.global_position,
			) <= interaction_distance
		):
			return_outdoors()
		return

	var nearest_entrance := _nearest_entrance()
	if nearest_entrance != null:
		enter_interior(nearest_entrance.get_meta("location_id", ""))


func enter_interior(requested_location_id: String) -> bool:
	if (
		not _resolve_scene_nodes()
		or interior_scene == null
		or _active_interior != null
	):
		return false
	var location := _find_interior_location(requested_location_id)
	if location.is_empty():
		return false

	var interior := interior_scene.instantiate() as Node3D
	if interior == null or not interior.has_method("build_from_location"):
		if interior != null:
			interior.free()
		return false
	if not interior.build_from_location(location):
		interior.free()
		return false

	_saved_outdoor_position = _player.global_position
	_has_saved_outdoor_position = true
	_interior_root.add_child(interior)
	_active_interior = interior
	_active_location_id = requested_location_id
	_set_town_available(false)
	_player.global_position = (
		interior.get_node("PlayerSpawn") as Marker3D
	).global_position
	entered_interior.emit(requested_location_id)
	return true


func return_outdoors() -> bool:
	if (
		not _resolve_scene_nodes()
		or not _has_saved_outdoor_position
		or _active_interior == null
	):
		return false

	var interior_navigation := _active_interior.get_node_or_null(
		"NavigationRegion3D",
	) as NavigationRegion3D
	if interior_navigation != null:
		interior_navigation.enabled = false
	_active_interior.queue_free()
	_active_interior = null
	_active_location_id = ""
	_set_town_available(true)
	_player.global_position = _saved_outdoor_position
	_has_saved_outdoor_position = false
	returned_outdoors.emit()
	return true


func get_active_interior() -> Node3D:
	return _active_interior


func get_active_location_id() -> String:
	return _active_location_id


func has_saved_outdoor_position() -> bool:
	return _has_saved_outdoor_position


func get_saved_outdoor_position() -> Vector3:
	return _saved_outdoor_position


func _resolve_scene_nodes() -> bool:
	if _town == null:
		_town = get_node_or_null(town_path) as Node3D
	if _player == null:
		_player = get_node_or_null(player_path) as CharacterBody3D
	if _interior_root == null:
		_interior_root = get_node_or_null(interior_root_path) as Node3D
	return _town != null and _player != null and _interior_root != null


func _find_interior_location(requested_location_id: String) -> Dictionary:
	if not _content_loaded:
		_content_loaded = _repository.load_spring()
	if not _content_loaded:
		return {}
	for location in _repository.locations:
		if (
			location.get("location_id", "") == requested_location_id
			and location.get("is_interior", false)
		):
			return location
	return {}


func _set_town_available(available: bool) -> void:
	_town.visible = available
	var navigation_region := _town.get_node_or_null(
		"NavigationRegion3D",
	) as NavigationRegion3D
	if navigation_region != null:
		navigation_region.enabled = available


func _nearest_entrance() -> Node3D:
	if not _resolve_scene_nodes() or not _town.has_method("get_entrance_ids"):
		return null
	var nearest: Node3D
	var nearest_distance := interaction_distance
	for entrance_id in _town.get_entrance_ids():
		var entrance := _town.get_entrance(entrance_id) as Node3D
		if entrance == null:
			continue
		var distance := _horizontal_distance(
			_player.global_position,
			entrance.global_position,
		)
		if distance <= nearest_distance:
			nearest = entrance
			nearest_distance = distance
	return nearest


func _horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))
