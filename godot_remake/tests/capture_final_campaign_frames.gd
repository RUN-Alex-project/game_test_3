extends Node


func _capture_after_frames(path: String) -> void:
	for _frame in 4:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 700 and image.get_height() == 550, "capture viewport is not 700x550")
	assert(image.save_png(path) == OK, "failed to save capture: %s" % path)


func _ready() -> void:
	GameState.level = 2000
	GameState.current_map_id = "demon_camp"
	GameState.story_flags = {
		"king_rescued": true,
		"princess_friend_gift_available": false,
		"maid_year_pig_available": true,
		"game_won": false,
	}
	GameState.demon_campaign = GameState.default_demon_campaign()
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var output_dir := ProjectSettings.globalize_path("res://tests/artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture_after_frames(output_dir.path_join("final_campaign_center.png"))
	main._travel_to("demon_left")
	await _capture_after_frames(output_dir.path_join("final_campaign_left.png"))
	main._travel_to("demon_camp")
	main._travel_to("demon_right")
	await _capture_after_frames(output_dir.path_join("final_campaign_right.png"))
	main._travel_to("demon_camp")
	main._travel_to("demon_banner")
	await _capture_after_frames(output_dir.path_join("final_campaign_banner.png"))
	GameState.demon_campaign.commander_alive = false
	main._travel_to("energy_tower")
	await _capture_after_frames(output_dir.path_join("final_campaign_energy_tower.png"))
	GameState.story_flags.game_won = true
	main._show_ending()
	await _capture_after_frames(output_dir.path_join("final_campaign_ending.png"))
	print("PASS captured corrected final campaign and ending at 700x550")
	get_tree().quit(0)
