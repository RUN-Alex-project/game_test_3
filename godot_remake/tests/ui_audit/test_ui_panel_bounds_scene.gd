extends Node

var main: Node = null
var vp: Rect2 = Rect2(0, 0, 700, 550)
var exceed: int = 0

func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# Open every panel, verify its global_rect stays inside the 700x550 viewport.
	await _check("inventory", main.inventory_panel, "show")
	await _check("warehouse", main.warehouse_panel, "show")
	await _check("gold_shop", main.gold_shop, "buy")
	await _check("stone_shop", main.stone_shop, "buy")
	await _check("equipment", main.equipment_panel, "show")
	await _check("enhancement", main.enhancement_panel, "show")
	await _check("pet", main.pet_panel, "show")
	await _check("research", main.research_panel, "show")
	await _check("progression", main.progression_panel, "show")
	await _check("quest", main.quest_panel, "show")
	await _check("skill", main.skill_panel, "show")

	assert(exceed == 0, "one or more panels exceed viewport")
	print("PANEL_BOUNDS exceed=%d (all 11 panels within 700x550)" % exceed)

	# Close buttons: panels that have one must hide when it is pressed.
	await _assert_close("inventory", main.inventory_panel)
	await _assert_close("warehouse", main.warehouse_panel)
	await _assert_close("gold_shop", main.gold_shop)
	await _assert_close("stone_shop", main.stone_shop)
	await _assert_close("enhancement", main.enhancement_panel)
	await _assert_close("pet", main.pet_panel)
	await _assert_close("research", main.research_panel)
	await _assert_close("progression", main.progression_panel)
	await _assert_close("quest", main.quest_panel)
	await _assert_close("skill", main.skill_panel)

	# equipment has no close button (closed via toggle) - verify toggle hides it
	main._toggle_equipment()
	await get_tree().process_frame
	assert(main.equipment_panel.visible, "equipment toggle did not open")
	main._toggle_equipment()
	await get_tree().process_frame
	assert(not main.equipment_panel.visible, "equipment toggle did not close")
	print("EQUIPMENT toggle open/close works")

	# Pet detail requires selection (detail_button -> "请先选择一只幻兽")
	main.pet_panel.show()
	await get_tree().process_frame
	main.pet_panel.detail_button.emit_signal("pressed")
	await get_tree().process_frame
	assert("请先选择一只幻兽" in main.status_label.text, "pet detail did not require selection: %s" % main.status_label.text)
	print("PET_DETAIL requires selection: %s" % main.status_label.text)

	# Inventory pagination: cycle page advances when there are 2+ pages
	main._hide_all_panels()
	for _i in 30:
		GameState.inventory.append({"item_id":"rose","quantity":1})
	main.inventory_panel.show()
	await get_tree().process_frame
	var page0: int = main.inventory_panel.current_page
	var pc0: int = main.inventory_panel._page_count()
	assert(pc0 >= 2, "test setup did not create 2 pages: pc=%d" % pc0)
	main.inventory_panel.page_label.emit_signal("pressed")
	await get_tree().process_frame
	var page1: int = main.inventory_panel.current_page
	assert(page1 != page0, "page cycle did not advance: %d -> %d" % [page0, page1])
	# cycling page_count-1 more times returns to the start page (total pc0 cycles)
	for _i in pc0 - 1:
		main.inventory_panel.page_label.emit_signal("pressed")
		await get_tree().process_frame
	assert(main.inventory_panel.current_page == page0, "page cycle did not wrap back to %d: %d" % [page0, main.inventory_panel.current_page])
	print("PAGINATION pages=%d page0=%d page1=%d wrapped=%d" % [pc0, page0, page1, main.inventory_panel.current_page])

	print("PASS panel bounds, close buttons, pet-select-before-detail, pagination")
	get_tree().quit(0)

func _check(name: String, panel: Control, mode: String) -> void:
	if mode == "show":
		panel.show()
	elif mode == "buy":
		panel.open_mode("buy")
	await get_tree().process_frame
	assert(panel.visible, "%s panel did not open" % name)
	var r: Rect2 = panel.get_global_rect()
	print("PANEL %s rect=%s" % [name, str(r)])
	if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > vp.size.x + 0.5 or r.end.y > vp.size.y + 0.5:
		exceed += 1
		push_error("PANEL_EXCEED %s %s vp=%s" % [name, str(r), str(vp)])
	main._hide_all_panels()

func _assert_close(name: String, panel: Control) -> void:
	panel.show()
	await get_tree().process_frame
	assert(panel.visible, "%s not open before close" % name)
	assert(panel.has_node("close_button") or _has_close(panel), "%s has no close_button" % name)
	panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not panel.visible, "%s close_button did not hide panel" % name)

func _has_close(panel: Control) -> bool:
	return panel.get("close_button") != null
