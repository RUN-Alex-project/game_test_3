extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._hide_all_panels()
	main.gold_shop.open_mode("buy")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var grocery_image := get_viewport().get_texture().get_image()
	var grocery_output := ProjectSettings.globalize_path("res://tests/artifacts/v122_native_grocery.png")
	assert(grocery_image.save_png(grocery_output) == OK, "could not save v1.22 native grocery capture")
	main.gold_shop.hide()
	main.stone_shop.open_mode("sell")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var collector_image := get_viewport().get_texture().get_image()
	var collector_output := ProjectSettings.globalize_path("res://tests/artifacts/v122_native_collector.png")
	assert(collector_image.save_png(collector_output) == OK, "could not save v1.22 native collector capture")
	print("CAPTURE v122 native shops ", grocery_image.get_width(), "x", grocery_image.get_height())
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
