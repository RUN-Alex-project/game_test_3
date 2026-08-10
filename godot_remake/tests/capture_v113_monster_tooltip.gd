extends Node


func _ready() -> void:
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _frame in 8:
		await get_tree().process_frame

	var action_id := "battle:spider"
	var actor: TextureRect = main.interactive_actors[action_id]
	main._actor_hover(actor, true, action_id)
	assert(main.monster_tooltip_panel.visible, "monster tooltip is not visible in capture")
	assert(main.monster_tooltip_panel.size == Vector2(123, 74), "monster tooltip capture size is wrong")
	for _frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("monster_native_hover.png")
	assert(image.save_png(output_path) == OK, "failed to save v1.13 monster tooltip capture")
	print("PASS captured native monster hover tooltip at 700x550")
	get_tree().quit(0)
