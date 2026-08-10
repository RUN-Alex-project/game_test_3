extends Node


func _capture_after_frames(path: String) -> void:
	for _frame in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	assert(image.save_png(path) == OK, "failed to save capture: %s" % path)


func _ready() -> void:
	GameState.current_day = 6
	GameState.level = 60
	GameState.current_map_id = "pk_arena"
	GameState.pk_race_active = true
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture_after_frames(output_dir.path_join("pk_arena_60.png"))

	GameState.current_map_id = "pk_arena_2"
	main._apply_current_map()
	await _capture_after_frames(output_dir.path_join("pk_arena_100.png"))

	GameState.current_map_id = "pk_arena_3"
	main._apply_current_map()
	await _capture_after_frames(output_dir.path_join("pk_arena_130.png"))
	print("PASS captured three native PK arenas at 700x550")
	get_tree().quit(0)
