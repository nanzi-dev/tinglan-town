extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const DEFAULT_OUTPUT_DIRECTORY := "res://tests/visual/screenshots"

var _output_directory := DEFAULT_OUTPUT_DIRECTORY
var _viewport_size := Vector2i(1280, 720)
var _capture_viewport: SubViewport
var _failed := false


func _initialize() -> void:
	_parse_arguments()
	_run.call_deferred()


func _run() -> void:
	_capture_viewport = SubViewport.new()
	_capture_viewport.size = _viewport_size
	_capture_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS
	)
	root.add_child(_capture_viewport)
	await process_frame

	var main := MAIN_SCENE.instantiate()
	main.auto_check_memoria = false
	_capture_viewport.add_child(main)
	await _wait_for_render()

	var hud := main.get_node("HUD") as TownHud
	await _capture("title")

	hud.start_game()
	await _capture("gameplay")

	(hud.get_node("%TaskButton") as Button).pressed.emit()
	await _capture("task-board")

	hud.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)
	await _capture("conversation")

	(hud.get_node("%RelationshipButton") as Button).pressed.emit()
	await _capture("relationships")

	hud._hide_overlays()
	hud.set_paused(true)
	await _capture("pause")

	hud.set_paused(false)
	_capture_viewport.remove_child(main)
	main.queue_free()
	_capture_viewport.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _capture(state_name: String) -> void:
	await _wait_for_render()
	var image := _capture_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Unable to capture %s." % state_name)
		_failed = true
		return
	var directory := ProjectSettings.globalize_path(_output_directory)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_error("Unable to create screenshot directory: %s" % error_string(error))
		_failed = true
		return
	var file_name := "%dx%d-%s.png" % [
		_viewport_size.x,
		_viewport_size.y,
		state_name,
	]
	var output_path := _output_directory.path_join(file_name)
	error = image.save_png(output_path)
	if error != OK:
		push_error("Unable to save screenshot: %s" % error_string(error))
		_failed = true
		return
	print("Captured %s (%s)" % [output_path, image.get_size()])


func _wait_for_render() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _parse_arguments() -> void:
	var arguments := OS.get_cmdline_user_args()
	var index := 0
	while index < arguments.size():
		match arguments[index]:
			"--output":
				if index + 1 < arguments.size():
					_output_directory = arguments[index + 1]
					index += 1
			"--size":
				if index + 1 < arguments.size():
					var parts := arguments[index + 1].split("x")
					if parts.size() == 2:
						_viewport_size = Vector2i(
							int(parts[0]),
							int(parts[1]),
						)
					index += 1
		index += 1
