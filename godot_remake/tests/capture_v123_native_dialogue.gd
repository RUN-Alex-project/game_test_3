extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._open_actor_dialogue("grocery")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var grocery_image := get_viewport().get_texture().get_image()
	var grocery_output := ProjectSettings.globalize_path("res://tests/artifacts/v123_native_dialogue_grocery.png")
	assert(grocery_image.save_png(grocery_output) == OK, "could not save grocery dialogue capture")
	var princess_actions: Array[Dictionary] = [
		{"label":"聊聊今天的事情", "action":"close"},
		{"label":"送一束玫瑰", "action":"close"},
		{"label":"离开", "action":"close"},
	]
	main.dialogue_panel.open_dialogue("公主", "今天能见到你，我很高兴。你想和我聊些什么？", princess_actions)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var princess_image := get_viewport().get_texture().get_image()
	var princess_output := ProjectSettings.globalize_path("res://tests/artifacts/v123_native_dialogue_princess.png")
	assert(princess_image.save_png(princess_output) == OK, "could not save princess dialogue capture")
	print("CAPTURE v123 native dialogue ", grocery_image.get_width(), "x", grocery_image.get_height())
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
