extends Node


func _capture_after_frames(path: String) -> void:
	for _frame in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	assert(image.save_png(path) == OK, "failed to save capture: %s" % path)


func _ready() -> void:
	GameState.story_flags = {
		"king_rescued":false,
		"princess_friend_gift_available":false,
		"maid_year_pig_available":true,
		"maid_combat_stone_available":true,
		"war_soul_quest_available":true,
		"war_soul_secret_unlocked":false,
		"game_won":false,
	}
	GameState.current_map_id = "desert"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture_after_frames(output_dir.path_join("war_soul_explorer.png"))

	GameState.current_map_id = "war_soul_seal_maze"
	GameState.war_soul_maze_active = true
	GameState.war_soul_guardian_revealed = false
	main._apply_current_map()
	await _capture_after_frames(output_dir.path_join("war_soul_maze_chest.png"))

	GameState.war_soul_guardian_revealed = true
	main._apply_current_map()
	await _capture_after_frames(output_dir.path_join("war_soul_maze_guardian.png"))
	print("PASS captured Gobi explorer and war-soul maze at 700x550")
	get_tree().quit(0)
