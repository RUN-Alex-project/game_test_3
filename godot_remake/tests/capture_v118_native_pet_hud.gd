extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var combined_image := get_viewport().get_texture().get_image()
	var combined_output := ProjectSettings.globalize_path("res://tests/artifacts/v118_native_pet_hud_combined.png")
	assert(combined_image.save_png(combined_output) == OK, "could not save combined pet HUD capture")

	var first_id := int(GameState.pets[0].instance_id)
	assert(GameState.set_pet_combined(first_id, false), "could not separate first pet for capture")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var split_image := get_viewport().get_texture().get_image()
	var split_output := ProjectSettings.globalize_path("res://tests/artifacts/v118_native_pet_hud_split.png")
	assert(split_image.save_png(split_output) == OK, "could not save split pet HUD capture")
	print("CAPTURE v118 pet HUD ", combined_image.get_width(), "x", combined_image.get_height())
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
