extends Node

var main: Node = null

func _ready() -> void:
	# One non-deployed pet so a real deploy success can fire.
	GameState.pets.clear()
	GameState.pets.append(GameState.pet_service.create_pet("attack_defense_light", 4101, 1850.0))
	main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. z_index: status above panels + bottom bar
	assert(main.status_label.z_index == 60, "status_label z_index not 60: %d" % main.status_label.z_index)
	assert(main.bottom_bar.z_index == 55, "bottom_bar z_index not 55")
	assert(main.status_label.z_index > main.inventory_panel.z_index, "status z not above inventory panel")
	print("LAYER status z=%d inventory z=%d bottom_bar z=%d" % [main.status_label.z_index, main.inventory_panel.z_index, main.bottom_bar.z_index])

	# 2. Open inventory via REAL footer button route (背包 -> _toggle_inventory)
	main.footer_buttons["背包"].emit_signal("pressed")
	await get_tree().process_frame
	assert(main.inventory_panel.visible, "real footer 背包 route did not open inventory")
	var inv_rect: Rect2 = main.inventory_panel.get_global_rect()
	var st_rect: Rect2 = main.status_label.get_global_rect()
	print("OVERLAP inv=%s status=%s intersects=%s" % [str(inv_rect), str(st_rect), str(inv_rect.intersects(st_rect))])
	assert(inv_rect.intersects(st_rect), "inventory does not overlap status area (z fix untestable)")
	assert(main.status_label.z_index > main.inventory_panel.z_index, "status not above inventory when open")

	# 3. Open pet panel via REAL footer button (幻兽 -> _toggle_pets, exclusive: hides inventory)
	main.footer_buttons["幻兽"].emit_signal("pressed")
	await get_tree().process_frame
	assert(main.pet_panel.visible, "real footer 幻兽 route did not open pet panel")
	assert(not main.inventory_panel.visible, "exclusive toggle did not hide inventory")

	# 4. REAL error: click detail with no selection -> "请先选择一只幻兽"
	main.status_label.text = ""
	main.pet_panel.detail_button.emit_signal("pressed")
	await get_tree().process_frame
	assert("请先选择一只幻兽" in main.status_label.text, "real detail-without-select did not show error: %s" % main.status_label.text)
	print("PET_ERROR (real) status=%s" % main.status_label.text)

	# 5. REAL success: select row 0 + deploy -> production flow replaces the stale error
	main.pet_panel._select_row(0)
	assert(main.pet_panel.selected_instance_id() == 4101, "row select did not set instance id")
	main.pet_panel.deploy_button.emit_signal("pressed")
	await get_tree().process_frame
	assert("请先选择一只幻兽" not in main.status_label.text, "real deploy success did not clear stale error: %s" % main.status_label.text)
	assert("出征" in main.status_label.text, "real deploy did not produce success status: %s" % main.status_label.text)
	print("PET_SUCCESS (real) status=%s" % main.status_label.text)

	# 6. Close pet panel via REAL close button -> status still visible
	main.pet_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.pet_panel.visible, "real close_button did not hide pet panel")
	assert(main.status_label.visible, "status not visible after closing panel")
	print("CLOSED status=%s" % main.status_label.text)

	print("PASS status prompt layer (real routes): footer open, real error, real success replaces, close, visible")
	get_tree().quit(0)
