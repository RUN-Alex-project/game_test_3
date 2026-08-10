extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.learned_skills = {"flying_slash":2, "star_sword":1, "fighting_spirit":4, "love_power":1}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_skills()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550)
	assert(image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v126_native_skill_panel.png")) == OK)
	print("CAPTURE v126 native skill panel 700x550")
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)