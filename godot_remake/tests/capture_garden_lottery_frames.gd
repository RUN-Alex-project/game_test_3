extends Node


func _capture_after_frames(path: String) -> void:
	for _frame in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	assert(image.save_png(path) == OK, "failed to save capture: %s" % path)


func _ready() -> void:
	GameState.nobility_merit = 1000
	GameState.current_map_id = "palace_garden"
	GameState.story_flags = {
		"king_rescued":true,
		"princess_friend_gift_available":false,
		"maid_year_pig_available":true,
		"maid_combat_stone_available":true,
		"game_won":false,
	}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture_after_frames(output_dir.path_join("palace_garden.png"))

	GameState.current_map_id = "lottery_room"
	main._apply_current_map()
	await _capture_after_frames(output_dir.path_join("lottery_room.png"))
	print("PASS captured palace garden and lottery room at 700x550")
	get_tree().quit(0)
