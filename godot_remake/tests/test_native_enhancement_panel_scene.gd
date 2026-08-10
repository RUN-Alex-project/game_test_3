extends Node


func _clear_inventory() -> void:
	for index in GameState.inventory.size():
		GameState.inventory[index] = {}


func _ready() -> void:
	_clear_inventory()
	GameState.equipment.weapon = GameState.create_item_entry("novice_sword")
	assert(GameState.add_item("enhanced_moon_box"), "quality material fixture failed")
	assert(GameState.add_item("magic_soul_crystal"), "magic-soul material fixture failed")
	assert(GameState.add_item("war_soul_crystal"), "war-soul material fixture failed")
	assert(GameState.add_item("war_soul_heart", 2), "soul-heart fixture failed")
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_enhancement()
	var panel = main.enhancement_panel
	assert(panel.visible, "blacksmith dialogue did not open refining window")
	assert(panel.position == Vector2(238, 375), "refining window does not use sprite662 show position")
	assert(panel.size == Vector2(191, 133), "refining window does not use shape653 bounds")
	assert(panel.get_theme_stylebox("panel").bg_color == Color("666666"), "refining window does not use shape653 fill")
	assert(panel.close_button.position.is_equal_approx(Vector2(160, 4.5)), "refining close button placement drifted")
	assert(panel.action_buttons.size() == 5, "refining flow is missing an operation")
	assert(panel.action_buttons.quality.position == Vector2(132, 31), "quality button placement drifted")
	assert(panel.action_buttons.earth.position == Vector2(132, 107), "earth-soul button placement drifted")
	assert(panel.equipment_icon.texture != null and not panel.equipment_label.text.is_empty(), "equipped item is not visible in refining window")
	assert(panel.perform_operation("quality"), "guaranteed quality refinement failed through native window")
	assert(panel.perform_operation("magic_soul"), "guaranteed magic-soul refinement failed through native window")
	assert(panel.perform_operation("war_soul", 0.1), "50-percent war-soul success branch failed through native window")
	assert(panel.perform_operation("heaven") and panel.perform_operation("earth"), "heaven/earth soul flow failed through native window")
	var enhancement: Dictionary = GameState.equipment.weapon.enhancement
	assert(int(enhancement.quality_level) == 1 and int(enhancement.magic_soul_level) == 1 and bool(enhancement.war_soul_active), "refining results were not persisted")
	assert(int(enhancement.heaven_soul_level) == 1 and int(enhancement.earth_soul_level) == 1, "soul levels were not persisted")
	panel.close_button.emit_signal("pressed")
	assert(not panel.visible, "native refining close button did not hide the window")
	print("PASS native sprite662 refining window and complete quality, magic-soul, war-soul, heaven/earth flow")
	get_tree().quit(0)