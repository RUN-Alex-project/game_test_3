extends Node


func _ready() -> void:
	var slot_items := {
		"weapon": "novice_sword",
		"helmet": "lottery_helmet",
		"necklace": "lottery_necklace",
		"armor": "novice_armor",
		"bracelet": "lottery_bracelet",
		"boots": "lottery_boots",
	}
	for slot_id: String in slot_items:
		var item := GameState.create_item_entry(str(slot_items[slot_id]))
		item.enhancement.quality_level = 4
		item.enhancement.magic_soul_level = 12
		item.enhancement.socket_count = 2
		item.enhancement.war_soul_active = true
		item.enhancement.heaven_soul_level = 1
		GameState.equipment[slot_id] = item
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_equipment()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var closed_image := get_viewport().get_texture().get_image()
	assert(closed_image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v124_native_equipment.png")) == OK)
	main.equipment_panel.detail_button.emit_signal("pressed")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var detail_image := get_viewport().get_texture().get_image()
	assert(detail_image.save_png(ProjectSettings.globalize_path("res://tests/artifacts/v124_native_equipment_detail.png")) == OK)
	print("CAPTURE v124 native equipment ", detail_image.get_width(), "x", detail_image.get_height())
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)