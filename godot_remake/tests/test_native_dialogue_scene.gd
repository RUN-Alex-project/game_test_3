extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	main._open_actor_dialogue("grocery")
	assert(main.dialogue_panel.position == Vector2(200, 80), "dialogue does not use SWF show coordinates")
	assert(main.dialogue_panel.size.is_equal_approx(Vector2(362, 269.3)), "dialogue does not use shape834 bounds")
	assert(main.dialogue_panel.get_theme_stylebox("panel").bg_color == Color("ffcc99"), "dialogue does not use shape834 parchment color")
	assert(main.dialogue_panel.npc_portrait.position == Vector2(4, 4), "NPC portrait is not at the native placement")
	assert(main.dialogue_panel.npc_portrait.size == Vector2(64, 64), "NPC portrait is not the native 64x64 size")
	assert(main.dialogue_panel.npc_portrait.texture.resource_path.ends_with("dialogue_face_grocery.png"), "grocery did not use its SWF portrait")
	assert(main.dialogue_panel.player_portrait.position.is_equal_approx(Vector2(287.8, 153.5)), "player portrait is not at the native placement")
	assert(main.dialogue_panel.body_label.position.is_equal_approx(Vector2(78.5, 6.35)), "NPC body text is not at the native placement")
	assert(main.dialogue_panel.close_button.position.is_equal_approx(Vector2(338.5, 2)), "dialogue close control is not at the native placement")
	assert(main.dialogue_panel.choices.get_child_count() == 3, "grocery dialogue choices were not preserved")
	var first_choice: Button = main.dialogue_panel.choices.get_child(0)
	var second_choice: Button = main.dialogue_panel.choices.get_child(1)
	assert(first_choice.position.is_equal_approx(Vector2(5, 155.7)), "first answer is not at the SWF placement")
	assert(second_choice.position.is_equal_approx(Vector2(5, 171.7)), "answer pitch is not the native 16 pixels")
	assert(first_choice.size == Vector2(270, 16), "answer does not use the native 270x16 hit area")
	assert(first_choice.get_theme_stylebox("hover").bg_color == Color("ffcc66"), "answer hover does not use shape878 color")
	first_choice.emit_signal("pressed")
	assert(not main.dialogue_panel.visible and main.gold_shop.visible and main.gold_shop.current_mode == "buy", "native answer did not dispatch the existing shop action")

	main._open_actor_dialogue("stone_synthesizer")
	assert(main.dialogue_panel.choices.get_child_count() == 6, "six native answer rows were not retained")
	assert(main.dialogue_panel.choices.get_child(5).position.is_equal_approx(Vector2(5, 235.7)), "sixth answer is not at the native placement")
	assert(main.dialogue_panel.npc_portrait.texture.resource_path.ends_with("dialogue_face_stone_synthesizer.png"), "stone synthesizer portrait is incorrect")

	var princess_actions: Array[Dictionary] = [{"label":"离开", "action":"close"}]
	main.dialogue_panel.open_dialogue("公主", "你好。", princess_actions)
	assert(main.dialogue_panel.npc_portrait.texture.resource_path.ends_with("dialogue_face_princess.png"), "princess portrait is incorrect")
	main.dialogue_panel.close_button.emit_signal("pressed")
	assert(not main.dialogue_panel.visible, "native dialogue close control did not close the window")

	print("PASS native dialogue bounds, portraits, six answer rows, hover state, close, and action dispatch")
	get_tree().quit(0)
