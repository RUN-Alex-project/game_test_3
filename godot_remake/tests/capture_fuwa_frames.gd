extends Node


func _capture_after_frames(path: String) -> void:
	for _frame in 5:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	assert(image.save_png(path) == OK, "failed to save capture: %s" % path)


func _ready() -> void:
	GameState.level = 100
	GameState.fuwa_event = GameState.default_fuwa_event()
	assert(GameState.start_fuwa_round().success, "capture Fuwa round could not start")
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture_after_frames(output_dir.path_join("fuwa_grass.png"))

	GameState.fuwa_event.beast_defeated = true
	GameState.current_map_id = "grass_reward"
	main._apply_current_map()
	await _capture_after_frames(output_dir.path_join("fuwa_grass_reward.png"))

	GameState.fuwa_event = {
		"found_count":5,
		"round_active":false,
		"beast_defeated":false,
		"completion_claimed":false,
		"messenger_map":"",
	}
	GameState.current_map_id = "treeheart_city"
	main._apply_current_map()
	await _capture_after_frames(output_dir.path_join("fuwa_treeheart.png"))
	print("PASS captured Fuwa grass, reward, and Treeheart frames at 700x550")
	get_tree().quit(0)
