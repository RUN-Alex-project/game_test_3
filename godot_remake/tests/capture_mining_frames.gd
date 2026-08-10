extends Node


func _capture_after_frames(path: String) -> void:
	for _frame in 4:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	assert(image.save_png(path) == OK, "failed to save capture: %s" % path)


func _ready() -> void:
	GameState.level = 10
	GameState.current_day = 1
	GameState.current_time_used = 0
	GameState.current_map_id = "thunder_mine"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture_after_frames(output_dir.path_join("thunder_mine.png"))
	GameState.mine_ore(10, 100)
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	main.gold_shop.open_mode("sell")
	await _capture_after_frames(output_dir.path_join("silver_ore_sale.png"))
	print("PASS captured thunder mine and ore sale at 700x550")
	get_tree().quit(0)
