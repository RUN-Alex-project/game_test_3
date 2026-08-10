extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.research = {"technology_level":88.8, "production_rate":4, "stock":26, "vip_level":3}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_research()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v129_native_research.png")) == OK)
	print("CAPTURE v129 native research 700x550")
	get_tree().quit(0)