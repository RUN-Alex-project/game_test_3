extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._update_player_animation(Vector2.ZERO, 4.0 / 12.0 + 0.001)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output := ProjectSettings.globalize_path("res://tests/artifacts/v117_native_player_idle.png")
	assert(image.save_png(output) == OK, "could not save v117 native player capture")
	print("CAPTURE v117_native_player_idle.png ", image.get_width(), "x", image.get_height())
	get_tree().quit(0)
