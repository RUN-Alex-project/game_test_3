extends Node


func _ready() -> void:
	GameState._initialize_inventory()
	GameState.pets.clear()
	GameState.research = {"technology_level":20.0, "production_rate":2, "stock":0, "vip_level":0}
	GameState.current_day = 7
	GameState.magic_stones = 1000000
	assert(GameState.add_item("soul_king", 3), "research task fixture failed")
	var day_result := GameState.advance_day()
	assert(GameState.current_day == 8, "research rollover fixture did not advance day")
	assert(int(day_result.research_produced) == 2 and int(GameState.research.stock) == 2, "daily research production is not automatic")
	assert(day_result.research_grew and is_equal_approx(float(GameState.research.technology_level), 22.0), "weekly ten-percent technology growth did not run")
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_research()
	var panel = main.research_panel
	assert(panel.visible, "research NPC did not open research window")
	assert(panel.position == Vector2(250, 180), "research window does not use sprite827 show position")
	assert(panel.size == Vector2(203, 183), "research window does not use shape823 bounds")
	assert(panel.get_theme_stylebox("panel").bg_color == Color("666666"), "research window does not use shape823 fill")
	assert(panel.close_button.position.is_equal_approx(Vector2(172.5, 6.95)), "research close placement drifted")
	assert(panel.buy_button.position == Vector2(155, 108), "research purchase placement drifted")
	assert(panel.fund_button.position.is_equal_approx(Vector2(136.5, 147.05)), "research funding placement drifted")
	assert("22.00" in panel.info_label.text and "2个/天" in panel.info_label.text, "research output summary is incomplete")
	panel._production_task()
	assert(int(GameState.research.production_rate) == 4 and GameState.count_item("soul_king") == 0, "production task did not consume materials and add two")
	var level_before := float(GameState.research.technology_level)
	panel._fund()
	assert(is_equal_approx(float(GameState.research.technology_level), level_before + 1.0), "research funding did not add one level")
	var stock_before := int(GameState.research.stock)
	var pet_count_before := GameState.pets.size()
	panel._buy_pet()
	assert(int(GameState.research.stock) == stock_before - 1 and GameState.pets.size() == pet_count_before + 1, "research pet purchase did not settle")
	assert(str(GameState.pets.back().template_id) == "strange_beast", "research produced the wrong pet type")
	panel.close_button.emit_signal("pressed")
	assert(not panel.visible, "research close control failed")
	print("PASS native sprite827 research window, automatic daily/weekly cycle, production task and pet purchase")
	get_tree().quit(0)