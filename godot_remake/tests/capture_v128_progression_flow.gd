extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.current_day = 7
	GameState.military_merit = 18000
	GameState.nobility_merit = 6000
	GameState.affection = 100
	GameState.completed_daily_tasks = {"collect_magic_soul":true}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_progression()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v128_progression_flow.png")) == OK)
	print("CAPTURE v128 progression flow 700x550")
	get_tree().quit(0)