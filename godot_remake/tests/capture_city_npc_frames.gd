extends Node


func _capture(path: String) -> void:
	for _frame in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	assert(image.save_png(path) == OK, "failed to save city capture")


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	main._hide_all_panels()
	await _capture(output_dir.path_join("city_npcs_native_layout.png"))
	main._open_actor_dialogue("experience_mentor")
	await _capture(output_dir.path_join("city_experience_mentor_dialogue.png"))
	print("PASS captured Cassano NPC native layout and mentor dialogue at 700x550")
	get_tree().quit(0)
