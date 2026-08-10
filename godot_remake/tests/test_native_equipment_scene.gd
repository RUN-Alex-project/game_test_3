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

	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_equipment()
	var panel = main.equipment_panel
	assert(panel.visible, "equipment footer did not open the character panel")
	assert(panel.position == Vector2(210, 85), "equipment panel does not use the SWF show position")
	assert(panel.size == Vector2(243, 289), "equipment panel does not use shape524 bounds")
	assert(panel.get_theme_stylebox("panel").bg_color == Color("666666"), "equipment panel does not use shape524 color")
	assert(panel.title_label.position.is_equal_approx(Vector2(77, 5.3)) and panel.title_label.text == "人物信息", "native character title placement drifted")
	assert(panel.stats_label.position.is_equal_approx(Vector2(10, 28.7)), "native character stats placement drifted")
	assert(panel.slot_panels.size() == 6, "native equipment panel must contain six slots")
	assert(panel.slot_panels.helmet.position == Vector2(173, 28), "helmet slot placement drifted")
	assert(panel.slot_panels.necklace.position == Vector2(173, 92), "necklace slot placement drifted")
	assert(panel.slot_panels.bracelet.position == Vector2(173, 156), "bracelet slot placement drifted")
	assert(panel.slot_panels.armor.position == Vector2(109, 220), "armor slot placement drifted")
	assert(panel.slot_panels.weapon.position == Vector2(45, 220), "weapon slot placement drifted")
	assert(panel.slot_panels.boots.position == Vector2(173, 220), "boots slot placement drifted")
	assert(panel.slot_icons.weapon.texture != null, "equipped weapon icon is not visible")
	assert(panel.detail_button.position.is_equal_approx(Vector2(3, 224.4)), "native detail button placement drifted")
	assert(not panel.detail_panel.visible, "combat detail should start collapsed")
	panel.detail_button.emit_signal("pressed")
	assert(panel.detail_panel.visible, "detail button did not reveal combat breakdown")
	assert(panel.detail_panel.position.is_equal_approx(Vector2(-179.05, 24.3)), "detail panel does not use sprite546 placement")
	assert(panel.detail_panel.size == Vector2(178, 231), "detail panel does not use shape544 bounds")
	assert(panel.detail_panel.get_theme_stylebox("panel").bg_color == Color("ffcc99"), "detail panel does not use shape544 color")
	assert("战斗力详细评定" in panel.detail_label.text and "总共战斗力" in panel.detail_label.text, "combat power detail content is incomplete")
	assert(panel.war_soul_badge.visible and panel.soul_set_badge.visible and panel.soul_set_badge.tooltip_text == "天魂套装", "native war/soul badges did not reflect equipped souls")
	panel._focus_slot("weapon")
	assert(main.item_tooltip_panel.visible and str(GameState.get_item_definition("novice_sword").get("name", "")) in main.item_tooltip_text.text, "equipped item did not open the existing item description")
	panel._unfocus_slot()
	assert(not main.item_tooltip_panel.visible, "equipped item description did not close")
	print("PASS native 243x289 character equipment panel, six slots, stats, soul badges, detail pane, and item descriptions")
	get_tree().quit(0)