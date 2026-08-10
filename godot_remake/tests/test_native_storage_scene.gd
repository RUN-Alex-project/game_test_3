extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	assert(main.inventory_panel.position == Vector2(453, 300), "backpack does not use SWF show_x/show_y")
	assert(main.inventory_panel.size == Vector2(247, 207), "backpack does not use shape566 bounds")
	assert(main.inventory_panel.slots.size() == 24, "backpack must expose the native 6x4 grid")
	assert(main.inventory_panel.slots[0].position == Vector2(4, 4), "first backpack slot is not at the native grid origin")
	assert(main.inventory_panel.slots[23].position == Vector2(204, 124), "last backpack slot is not at the native grid coordinate")
	assert(main.inventory_panel.slots[0].size == Vector2(36, 36), "backpack slot size does not preserve the 40-pixel pitch")
	assert(main.inventory_panel.title_label.position.is_equal_approx(Vector2(177.95, 172.4)), "backpack title is not at the SWF placement")
	assert(main.inventory_panel.close_button.position.is_equal_approx(Vector2(221.25, 172.15)), "backpack close control is not at the SWF placement")
	assert(main.inventory_panel.gold_label.position == Vector2(4, 165), "gold readout is not in the native footer")
	assert(main.inventory_panel.magic_stone_label.position.is_equal_approx(Vector2(4, 186.4)), "magic-stone readout is not in the native footer")
	assert(main.inventory_panel.get_theme_stylebox("panel").bg_color == Color("666666"), "backpack does not use shape566 gray")

	main._toggle_warehouse()
	assert(main.inventory_panel.visible and main.warehouse_panel.visible, "warehouse interaction did not show both native windows")
	assert(main.inventory_panel.position == Vector2(453, 300), "backpack moved away from its native position when warehouse opened")
	assert(main.warehouse_panel.position == Vector2(208, 220), "warehouse does not use SWF show_x/show_y")
	assert(main.warehouse_panel.size == Vector2(247, 287), "warehouse does not use shape562 bounds")
	assert(main.warehouse_panel.slots.size() == 36, "warehouse must expose the native 6x6 grid")
	assert(main.warehouse_panel.slots[0].position == Vector2(4, 44), "first warehouse slot is not at the native grid origin")
	assert(main.warehouse_panel.slots[35].position == Vector2(204, 244), "last warehouse slot is not at the native grid coordinate")
	assert(main.warehouse_panel.title_label.position.is_equal_approx(Vector2(102.3, 11.9)), "warehouse title is not at the SWF placement")
	assert(main.warehouse_panel.close_button.position.is_equal_approx(Vector2(220.4, 4.95)), "warehouse close control is not at the SWF placement")

	var old_page: int = main.inventory_panel.current_page
	main.inventory_panel.page_label.emit_signal("pressed")
	assert(main.inventory_panel.current_page != old_page, "legacy 48-slot save compatibility paging is not interactive")
	assert(main.inventory_panel.slots[0].slot_index == 24, "backpack second page did not bind the legacy overflow slots")
	main.inventory_panel.close_button.emit_signal("pressed")
	assert(not main.inventory_panel.visible, "native backpack close control did not close the window")

	print("PASS native backpack/warehouse bounds, grids, footer, close controls, and legacy paging")
	get_tree().quit(0)

