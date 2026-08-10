extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.quest_states = GameState.quest_service.default_states()
	GameState.quest_states.dungeon_conquest = {"status":"active", "progress":{"dungeon_boss":1}}
	GameState.unlocked_maps = {"dungeon_floor_2":true, "dungeon_floor_3":false}
	GameState.story_flags["king_rescued"] = false
	GameState.story_flags["game_won"] = false
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_quests()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v130_quest_flow_guide.png")) == OK)
	print("CAPTURE v130 quest flow guide 700x550")
	get_tree().quit(0)