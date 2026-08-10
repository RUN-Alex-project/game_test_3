extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output := ProjectSettings.globalize_path("res://tests/artifacts/v119_native_footer.png")
	assert(image.save_png(output) == OK, "could not save v1.19 native footer capture")
	print("CAPTURE v119_native_footer.png ", image.get_width(), "x", image.get_height())
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
