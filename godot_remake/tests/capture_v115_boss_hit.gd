extends Node


func _ready() -> void:
	GameState.level = 1
	GameState.current_map_id = "thunder_continent"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _frame in 8:
		await get_tree().process_frame

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._on_actor_input(click, "battle:thunder_boss_10")
	await get_tree().create_timer(0.20).timeout
	assert(main.scene_battle_controller.native_hit_active, "native Boss hit frame is not active in capture")
	assert(main.scene_battle_controller.last_target_hit_kind == "boss_native_shape", "capture did not reach shape133")
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("boss_native_hit.png")
	assert(image.save_png(output_path) == OK, "failed to save v1.15 Boss hit capture")
	print("PASS captured rasterized native Boss hit frame at 700x550")
	get_tree().quit(0)
