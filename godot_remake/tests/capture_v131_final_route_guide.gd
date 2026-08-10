extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.story_flags["king_rescued"] = true
	GameState.story_flags["game_won"] = false
	GameState.demon_campaign = GameState.default_demon_campaign()
	GameState.demon_campaign.assault_alive = false
	GameState.demon_campaign.guard_alive = false
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_quests()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v131_final_route_guide.png")) == OK)
	print("CAPTURE v131 final route guide 700x550")
	get_tree().quit(0)