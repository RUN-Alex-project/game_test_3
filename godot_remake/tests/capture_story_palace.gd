extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.current_day = 7
	GameState.story_flags = {
		"king_rescued": true,
		"princess_friend_gift_available": true,
		"maid_year_pig_available": true,
	}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._travel_to("palace")
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	main._open_actor_dialogue("prime_minister")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join("story_palace_prime_minister.png"))
	main._open_actor_dialogue("king")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join("story_palace_king.png"))
	get_tree().quit(0)
