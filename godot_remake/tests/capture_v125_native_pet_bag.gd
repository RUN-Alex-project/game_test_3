extends Node


func _pet(template_id: String, instance_id: int, level: int, score: float) -> Dictionary:
	var pet: Dictionary = GameState.pet_service.create_pet(template_id, instance_id, score)
	pet.level = level
	pet.current_hp = int(GameState.pet_service.get_stats(pet).max_hp)
	return pet


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.pets.clear()
	GameState.pets.append(_pet("attack_defense_light", 5101, 22, 1850.0))
	GameState.pets.append(_pet("strange_beast", 5102, 19, 1300.0))
	GameState.pets.append(_pet("year_pig", 5103, 31, 2680.0))
	GameState.pets.append(_pet("holy_angel", 5104, 40, 3560.0))
	GameState.pets.append(_pet("lulu_pet", 5105, 25, 2210.0))
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_pets()
	main.pet_panel._select_row(0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var bag_image := get_viewport().get_texture().get_image()
	assert(bag_image.get_width() == 700 and bag_image.get_height() == 550)
	assert(bag_image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v125_native_pet_bag.png")) == OK)
	main.pet_panel._show_detail()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var detail_image := get_viewport().get_texture().get_image()
	assert(detail_image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v125_native_pet_detail.png")) == OK)
	print("CAPTURE v125 native pet bag and detail 700x550")
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)