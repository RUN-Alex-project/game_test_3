extends Node


func _make_pet(template_id: String, instance_id: int, level: int, score: float) -> Dictionary:
	var pet: Dictionary = GameState.pet_service.create_pet(template_id, instance_id, score)
	pet.level = level
	pet.current_hp = int(GameState.pet_service.get_stats(pet).max_hp)
	return pet


func _ready() -> void:
	GameState.pets.clear()
	GameState.pets.append(_make_pet("attack_defense_light", 4101, 22, 1850.0))
	GameState.pets.append(_make_pet("strange_beast", 4102, 19, 1300.0))
	GameState.pets.append(_make_pet("year_pig", 4103, 31, 2680.0))
	GameState.pets.append(_make_pet("lulu_pet", 4104, 25, 2210.0))
	GameState.pets.append(_make_pet("holy_angel", 4105, 40, 3560.0))

	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_pets()
	var panel = main.pet_panel
	assert(panel.visible, "pet footer did not open the native pet bag")
	assert(panel.position == Vector2(0, 150), "pet bag does not use sprite787 show position")
	assert(panel.size == Vector2(213, 333), "pet bag does not use shape732 bounds")
	assert(panel.get_theme_stylebox("panel").bg_color == Color("666666"), "pet bag does not use shape732 fill")
	assert(panel.row_panels.size() == 4, "native pet bag must contain four fixed rows")
	for row_index in 4:
		assert(panel.row_panels[row_index].position == Vector2(10, 12 + row_index * 70), "pet row placement drifted")
		assert(panel.row_panels[row_index].size == Vector2(193, 69), "pet row size drifted")
	assert(panel.row_icons[0].texture.resource_path.ends_with("image_0738.jpg"), "first native pet portrait is incorrect")
	assert(panel.page_label.text == "1 / 2", "five pets did not create two native pages")
	assert(panel.previous_button.position == Vector2(5, 300), "previous page button placement drifted")
	assert(panel.next_button.position == Vector2(87, 298), "next page button placement drifted")
	assert(panel.discard_button.position == Vector2(117, 302), "discard button placement drifted")
	assert(panel.detail_button.position == Vector2(164, 302), "detail button placement drifted")

	panel._select_row(0)
	assert(panel.selected_instance_id() == 4101 and panel.deploy_button.visible, "row selection did not reveal deploy control")
	assert(panel.deploy_button.position.is_equal_approx(Vector2(164.7, 18.55)), "deploy overlay placement drifted")
	panel._toggle_deployment()
	assert(bool(GameState.pets[GameState.get_pet_index(4101)].deployed), "native deploy button did not deploy the pet")
	panel._show_discard_confirmation()
	assert(not panel.discard_confirmation.visible, "deployed pet incorrectly opened discard confirmation")

	panel._show_detail()
	assert(panel.detail_panel.visible, "detail button did not open native pet details")
	assert(panel.detail_panel.position == Vector2(210, 0) and panel.detail_panel.size == Vector2(213, 333), "detail panel does not match sprite775")
	panel.rename_edit.text = "测试幻兽七字"
	panel._rename_selected()
	assert(str(GameState.pets[GameState.get_pet_index(4101)].custom_name) == "测试幻兽七字".left(6), "native rename did not enforce six-character limit")

	panel._select_row(1)
	panel._show_discard_confirmation()
	assert(panel.discard_confirmation.visible, "discard button did not open native confirmation")
	assert(panel.discard_confirmation.position == Vector2(6, 93) and panel.discard_confirmation.size == Vector2(203, 123), "discard confirmation does not match sprite786")
	var count_before := GameState.pets.size()
	panel._confirm_discard()
	assert(GameState.pets.size() == count_before - 1 and GameState.get_pet_index(4102) < 0, "confirmed discard did not remove the selected pet")

	panel._change_page(1)
	assert(panel.current_page == 0, "page was not clamped after pet count dropped to four")
	print("PASS native 213x333 pet bag, four rows, original portraits, paging, deploy, details, rename, and guarded discard")
	get_tree().quit(0)