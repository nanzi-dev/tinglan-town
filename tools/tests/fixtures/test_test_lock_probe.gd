extends GutTest


func test_hold_test_lock() -> void:
	var role := OS.get_environment("TINGLAN_TEST_LOCK_PROBE_ROLE")
	assert_true(role == "first" or role == "second")
	if role != "first":
		return

	var marker := OS.get_environment("TINGLAN_TEST_LOCK_RUN_MARKER")
	assert_false(marker.is_empty())
	var marker_file := FileAccess.open(marker, FileAccess.WRITE)
	assert_not_null(marker_file)
	if marker_file == null:
		return
	marker_file.store_string("running\n")
	marker_file.close()

	OS.delay_msec(3000)

	marker_file = FileAccess.open(marker, FileAccess.WRITE)
	assert_not_null(marker_file)
	if marker_file == null:
		return
	marker_file.store_string("done\n")
	marker_file.close()
