extends Node


func _capture(viewport: Viewport, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var output := ProjectSettings.globalize_path("res://tests/artifacts/" + file_name)
	var error := image.save_png(output)
	assert(error == OK, "could not save " + file_name)
	print("CAPTURE ", file_name, " ", image.get_width(), "x", image.get_height())


func _ready() -> void:
	GameState.current_day = 6
	GameState.level = 60
	GameState.last_pk_race_day = 0
	GameState.pk_race_active = true
	GameState.current_map_id = "pk_arena"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _capture(get_viewport(), "v116_pk_native_boss.png")

	GameState.pk_race_active = false
	GameState.current_day = 31
	GameState.current_map_id = "thunder_continent"
	GameState.nobility_merit = 1000
	GameState.last_territory_challenge_day = 0
	GameState.pending_territory_challenge = ""
	GameState.player_current_hp = int(GameState.get_player_stats().get("max_hp", 1))
	main._apply_current_map()
	main._start_territory_challenge("thunder_continent")
	await get_tree().process_frame
	await _capture(get_viewport(), "v116_territory_native_boss.png")
	main.scene_battle_controller.cancel_battle()
	get_tree().quit(0)
