extends GutTest


func test_project_name_is_tides_of_tinglan() -> void:
	assert_eq(
		ProjectSettings.get_setting("application/config/name"),
		"Tides of Tinglan",
	)


func test_main_scene_exists() -> void:
	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene"))
	assert_true(ResourceLoader.exists(main_scene_path))
