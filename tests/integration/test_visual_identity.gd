extends GutTest

const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const TASK_BOARD_SCENE_PATH := "res://scenes/ui/task_board_panel.tscn"
const CONVERSATION_SCENE_PATH := "res://scenes/ui/conversation_panel.tscn"
const RELATIONSHIP_SCENE_PATH := "res://scenes/ui/relationship_panel.tscn"
const KEY_ART_PATH := "res://assets/environments/tinglan_spring_key_art.png"
const PORTRAIT_SHEET_PATH := "res://assets/characters/resident_portraits.png"
const PAPER_TEXTURE_PATH := "res://assets/ui/paper_texture.png"
const PORTRAIT_ATLAS_PATH := "res://scripts/ui/resident_portrait_atlas.gd"

const RESIDENT_IDS := [
	"shen-yan",
	"lin-xi",
	"zhou-he",
	"lu-qiao",
	"su-wan",
	"gu-yun",
	"tang-yu",
	"qiao-zhen",
	"he-miao",
	"xu-deng",
]


func test_generated_visual_assets_have_production_dimensions() -> void:
	var key_art := load(KEY_ART_PATH) as Texture2D
	var portrait_sheet := load(PORTRAIT_SHEET_PATH) as Texture2D
	var paper_texture := load(PAPER_TEXTURE_PATH) as Texture2D

	assert_not_null(key_art)
	assert_not_null(portrait_sheet)
	assert_not_null(paper_texture)
	if key_art == null or portrait_sheet == null or paper_texture == null:
		return
	assert_almost_eq(
		float(key_art.get_width()) / float(key_art.get_height()),
		16.0 / 9.0,
		0.01,
	)
	assert_eq(
		Vector2i(portrait_sheet.get_width(), portrait_sheet.get_height()),
		Vector2i(2000, 800),
		"The portrait sheet must divide into ten exact 400 px cells.",
	)
	assert_eq(paper_texture.get_width(), paper_texture.get_height())
	assert_gte(paper_texture.get_width(), 1024)


func test_portrait_atlas_maps_all_residents_to_exact_cells() -> void:
	var exists := ResourceLoader.exists(PORTRAIT_ATLAS_PATH)
	assert_true(exists, "Missing resident portrait atlas helper.")
	if not exists:
		return
	var atlas_script := load(PORTRAIT_ATLAS_PATH) as Script
	var atlas: Variant = atlas_script.new()

	for index in range(RESIDENT_IDS.size()):
		var portrait := atlas.portrait_for(RESIDENT_IDS[index]) as AtlasTexture
		assert_not_null(portrait)
		if portrait == null:
			continue
		assert_eq(portrait.atlas.resource_path, PORTRAIT_SHEET_PATH)
		@warning_ignore("integer_division")
		var row := index / 5
		var column := index % 5
		assert_eq(
			portrait.region,
			Rect2(column * 400, row * 400, 400, 400),
		)
	assert_null(atlas.portrait_for("unknown-resident"))


func test_hud_uses_key_art_for_title_pause_and_subtle_paper() -> void:
	var hud: Variant = await _spawn_scene(HUD_SCENE_PATH)
	if hud == null:
		return
	var title_screen := hud.get_node_or_null("%TitleScreen") as Control
	var title_art := hud.get_node_or_null("%TitleKeyArt") as TextureRect
	var title_name := hud.get_node_or_null("%TitleName") as Label
	var start_button := hud.get_node_or_null("%StartButton") as Button
	var pause_backdrop := hud.get_node_or_null("%PauseBackdrop") as TextureRect
	var paper_texture := hud.get_node_or_null("%PaperTexture") as TextureRect

	assert_not_null(title_screen)
	assert_not_null(title_art)
	assert_not_null(title_name)
	assert_not_null(start_button)
	assert_not_null(pause_backdrop)
	assert_not_null(paper_texture)
	if (
		title_screen == null
		or title_art == null
		or title_name == null
		or start_button == null
		or pause_backdrop == null
		or paper_texture == null
	):
		return

	assert_true(title_screen.visible)
	assert_eq(title_art.texture.resource_path, KEY_ART_PATH)
	assert_eq(title_art.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	assert_eq(title_name.text, "听澜镇")
	assert_eq(start_button.text, "进入听澜镇")
	assert_eq(pause_backdrop.texture.resource_path, KEY_ART_PATH)
	assert_false(pause_backdrop.visible)
	assert_eq(paper_texture.texture.resource_path, PAPER_TEXTURE_PATH)
	assert_eq(paper_texture.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_lte(paper_texture.modulate.a, 0.18)

	start_button.pressed.emit()
	await wait_process_frames(1)

	assert_false(title_screen.visible)

	hud.set_paused(true)

	assert_true(pause_backdrop.visible)


func test_conversation_and_relationship_panels_render_resident_portraits() -> void:
	var conversation: Variant = await _spawn_scene(CONVERSATION_SCENE_PATH)
	if conversation == null:
		return
	var manager := ConversationManager.new()
	var context := manager.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)
	assert_true(conversation.open_conversation(
		manager,
		context["conversation_id"],
	))
	var portrait_strip := (
		conversation.get_node_or_null("%ParticipantPortraits")
		as HBoxContainer
	)
	assert_not_null(portrait_strip)
	if portrait_strip != null:
		assert_eq(portrait_strip.get_child_count(), 2)
		for child in portrait_strip.get_children():
			assert_true(child is TextureRect)
			assert_not_null((child as TextureRect).texture)

	var relationships: Variant = await _spawn_scene(RELATIONSHIP_SCENE_PATH)
	if relationships == null:
		return
	relationships.set_profiles([{
		"character_id": "lin-xi",
		"name": "林汐",
		"public_view": {
			"label": "熟悉",
			"recent_reasons": ["一起查看过听雨桥"],
		},
	}])
	var resident_portrait := (
		relationships.get_node_or_null("%ResidentPortrait")
		as TextureRect
	)
	assert_not_null(resident_portrait)
	if resident_portrait != null:
		assert_not_null(resident_portrait.texture)
		if resident_portrait.texture is AtlasTexture:
			assert_eq(
				(resident_portrait.texture as AtlasTexture).region,
				Rect2(400, 0, 400, 400),
			)


func test_escape_closes_active_overlay_before_pausing_game() -> void:
	var hud: Variant = await _spawn_scene(HUD_SCENE_PATH)
	if hud == null:
		return
	if not hud.has_method("start_game"):
		fail_test("HUD must expose start_game for title-screen control.")
		return
	hud.start_game()
	var context: Dictionary = hud.start_npc_conversation(
		["lin-xi", "shen-yan"],
		"听雨桥",
	)
	assert_false(context.is_empty())
	var conversation := hud.get_node("%ConversationPanel") as Control
	assert_true(conversation.visible)

	var escape := InputEventAction.new()
	escape.action = "pause_game"
	escape.pressed = true
	hud._unhandled_input(escape)

	assert_false(conversation.visible)
	assert_false(get_tree().paused)
	assert_false((hud.get_node("%PausePanel") as Control).visible)


func test_task_board_fits_inside_small_window() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child_autoqfree(viewport)

	var packed := load(TASK_BOARD_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var panel := packed.instantiate() as Control
	viewport.add_child(panel)
	await wait_process_frames(2)

	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for path in [
		"Surface",
		"Surface/Margin/Main/Content/FormScroll",
		"Surface/Margin/Main/Content/Published",
	]:
		var control := panel.get_node(path) as Control
		assert_true(
			viewport_rect.encloses(control.get_global_rect()),
			"%s extends outside the 960x540 viewport: %s"
			% [path, control.get_global_rect()],
		)


func test_task_board_form_fields_keep_label_control_alignment() -> void:
	var panel: Variant = await _spawn_scene(TASK_BOARD_SCENE_PATH)
	if panel == null:
		return

	for pair in [
		["TaskTypeLabel", "%TaskTypeOption"],
		["TargetLabel", "%TargetIdEdit"],
		["TargetCountLabel", "%TargetCountSpin"],
		["LocationLabel", "%LocationEdit"],
		["DeadlineDaysLabel", "%DeadlineDaysSpin"],
		["DeadlineMinuteLabel", "%DeadlineMinuteSpin"],
		["RewardLabel", "%RewardCoinsSpin"],
		["CompletionRuleLabel", "%CompletionRuleOption"],
		["CompletionTargetLabel", "%CompletionTargetEdit"],
	]:
		var label := panel.find_child(pair[0], true, false) as Label
		var field := panel.get_node(pair[1]) as Control
		assert_almost_eq(
			label.get_rect().get_center().y,
			field.get_rect().get_center().y,
			1.0,
			"%s is not aligned with %s." % pair,
		)


func test_small_task_board_prioritizes_form_over_empty_published_list() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child_autoqfree(viewport)

	var packed := load(TASK_BOARD_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var panel := packed.instantiate() as Control
	viewport.add_child(panel)
	await wait_process_frames(2)

	var form_scroll := (
		panel.get_node("Surface/Margin/Main/Content/FormScroll")
		as ScrollContainer
	)
	var published := (
		panel.get_node("Surface/Margin/Main/Content/Published")
		as VBoxContainer
	)
	assert_gte(
		form_scroll.size.y,
		published.size.y * 2.0,
		"The compact task form should receive most of the available height.",
	)


func test_pause_backdrop_fully_obscures_live_world() -> void:
	var hud: Variant = await _spawn_scene(HUD_SCENE_PATH)
	if hud == null:
		return
	var pause_backdrop := hud.get_node("%PauseBackdrop") as TextureRect

	assert_eq(
		pause_backdrop.modulate.a,
		1.0,
		"The pause key art must not blend with the live 3D world.",
	)


func _spawn_scene(path: String) -> Variant:
	var exists := ResourceLoader.exists(path)
	assert_true(exists, "Missing scene %s." % path)
	if not exists:
		return null
	var packed := load(path) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var instance := packed.instantiate()
	add_child_autoqfree(instance)
	await wait_process_frames(1)
	return instance
