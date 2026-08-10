extends Node


func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	assert(main.bottom_bar.position == Vector2(0, 512), "footer is not at the SWF root position")
	assert(main.bottom_bar.size == Vector2(700, 38), "footer does not preserve the native stage width")
	assert(main.day_label.position == Vector2(5.2, 4.0), "day label is not aligned to sprite908")
	assert(main.time_box.position == Vector2(185.7, 6.0), "remaining-time box is not aligned to sprite908")
	assert(main.music_toggle.position == Vector2(245.7, 4.0), "music control is not at the root placement")
	assert(main.trash_button.position == Vector2(301.05, 1.65), "trash target is not at the root placement")

	var expected_positions := {
		"背包":Vector2(378.0, 0.0),
		"装备":Vector2(441.7, 0.0),
		"幻兽":Vector2(505.2, 0.0),
		"技能":Vector2(568.7, 0.0),
		"VIP":Vector2(631.7, 0.0),
	}
	for button_name: String in expected_positions:
		var button: Button = main.footer_buttons[button_name]
		assert(button.position == expected_positions[button_name], "%s footer button root position is incorrect" % button_name)
		assert(button.size == Vector2(62, 32), "%s footer button does not use the native 62x32 bounds" % button_name)
		assert(button.get_theme_stylebox("normal").bg_color == Color("ff6600"), "%s normal color is not the SWF value" % button_name)
		assert(button.get_theme_stylebox("hover").bg_color == Color("ffcc33"), "%s hover color is not the SWF value" % button_name)
		assert(button.get_theme_stylebox("pressed").bg_color == Color("ff9900"), "%s pressed color is not the SWF value" % button_name)

	assert("星期一" in main.day_label.text, "weekday did not use the native Chinese name")
	# P1: inventory starts hidden; footer 背包 toggles open then closed.
	assert(not main.inventory_panel.visible, "inventory must be hidden at startup")
	main.footer_buttons["背包"].emit_signal("pressed")
	assert(main.inventory_panel.visible, "native backpack button did not open the backpack")
	main.footer_buttons["背包"].emit_signal("pressed")
	assert(not main.inventory_panel.visible, "native backpack button did not close the backpack")
	main.trash_button.emit_signal("pressed")
	assert("垃圾箱" in main.status_label.text, "native trash target did not expose its hint")
	main.music_toggle.button_pressed = false
	assert(AudioServer.is_bus_mute(0), "native music checkbox did not mute audio")
	main.music_toggle.button_pressed = true
	assert(not AudioServer.is_bus_mute(0), "native music checkbox did not restore audio")

	print("PASS native fixed footer layout, colors, controls, weekday, and panel wiring")
	get_tree().quit(0)
