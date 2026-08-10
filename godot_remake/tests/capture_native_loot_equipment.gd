extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.inventory.fill({})
	GameState.loot_queue.clear()
	var token := "loot_equipment|field_weapon|100|4|12|2"
	GameState.queue_loot([token])
	assert(GameState.claim_loot(token), "capture equipment could not be claimed")
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	for _frame in 6:
		await get_tree().process_frame
	main._hide_all_panels()
	main._toggle_inventory()
	main._show_item_description(GameState.inventory[0], main.inventory_panel)
	for _frame in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	assert(image.save_png(output_dir.path_join("native_loot_equipment.png")) == OK, "failed to save native loot capture")
	print("PASS captured native random equipment and description at 700x550")
	get_tree().quit(0)
