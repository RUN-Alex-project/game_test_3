extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.level = 100
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._hide_all_panels()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output := ProjectSettings.globalize_path("res://tests/artifacts/v120_native_map_exits.png")
	assert(image.save_png(output) == OK, "could not save v1.20 native map-exit capture")
	print("CAPTURE v120_native_map_exits.png ", image.get_width(), "x", image.get_height())
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


