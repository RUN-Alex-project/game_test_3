extends Node


func _ready() -> void:
	GameState.learned_skills = {"flying_slash":2, "star_sword":1, "fighting_spirit":4, "love_power":1}
	GameState.pets.clear()
	var pet: Dictionary = GameState.pet_service.create_pet("attack_defense_light", 6201, 1800.0)
	pet.level = 12
	pet.current_hp = 1
	GameState.pets.append(pet)
	GameState.player_current_hp = 1

	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_skills()
	var panel = main.skill_panel
	assert(panel.visible, "skill footer did not open the native skill panel")
	assert(panel.position == Vector2(23, 220), "skill panel does not use sprite731 show position")
	assert(panel.size == Vector2(183, 253), "skill panel does not use shape697 bounds")
	assert(panel.get_theme_stylebox("panel").bg_color == Color("666666"), "skill panel does not use shape697 fill")
	assert(panel.row_panels.size() == 6, "native skill panel must contain six fixed rows")
	for row_index in 5:
		assert(panel.row_panels[row_index].position == Vector2(10, 5 + row_index * 40), "native skill row placement drifted")
	assert(panel.row_panels[5].position.is_equal_approx(Vector2(10, 207.6)), "love-power row placement drifted")
	assert(panel.close_button.position.is_equal_approx(Vector2(156.45, 2.95)), "native skill close button placement drifted")
	assert(panel.row_icons[0].texture.resource_path.ends_with("image_0698.jpg"), "flying-slash native icon is incorrect")
	assert(panel.row_icons[4].texture.resource_path.ends_with("image_0718.jpg"), "fighting-spirit native icon is incorrect")
	assert(panel.row_icons[5].texture.resource_path.ends_with("image_0726.png"), "love-power native icon is incorrect")
	assert("飞天连斩" in panel.row_labels[0].text and "150%" in panel.row_labels[0].text, "active skill rank/damage display is incomplete")
	assert(panel.row_labels[2].text == "未掌握" and panel.row_labels[3].text == "未掌握", "original reserved skill slots were not preserved")
	assert("斗志昂扬" in panel.row_labels[4].text and "+35%" in panel.row_labels[4].text, "passive skill display is incomplete")
	assert("爱的力量" in panel.row_labels[5].text and "80%" in panel.row_labels[5].text, "relationship skill display is incomplete")

	var max_hp := int(GameState.get_player_stats().max_hp)
	panel._use_love_power(0.0)
	assert(GameState.player_current_hp == max_hp, "love-power row did not heal the player")
	assert(int(GameState.pets[0].current_hp) == int(GameState.pet_service.get_stats(GameState.pets[0]).max_hp), "love-power row did not heal the pet")
	panel._activate_row(2)
	panel.close_button.emit_signal("pressed")
	assert(not panel.visible, "native skill close button did not hide the panel")
	print("PASS native 183x253 six-row skill panel, original icons, ranks, reserved slots, and love-power action")
	get_tree().quit(0)