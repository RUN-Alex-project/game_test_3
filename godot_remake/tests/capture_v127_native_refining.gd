extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.equipment.weapon = GameState.create_item_entry("novice_sword")
	GameState.equipment.weapon.enhancement.quality_level = 4
	GameState.equipment.weapon.enhancement.magic_soul_level = 12
	GameState.equipment.weapon.enhancement.war_soul_active = true
	GameState.equipment.weapon.enhancement.heaven_soul_level = 2
	GameState.equipment.weapon.enhancement.earth_soul_level = 1
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_enhancement()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v127_native_refining.png")) == OK)
	print("CAPTURE v127 native refining 700x550")
	get_tree().quit(0)