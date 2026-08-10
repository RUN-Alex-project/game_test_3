extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.current_day = 5
	GameState.quest_states = GameState.quest_service.default_states()
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	assert(main.interactive_actors.has("daily_officer"), "original daily mission officer is missing from Cassano")
	var officer: TextureRect = main.interactive_actors["daily_officer"]
	assert(officer.texture.resource_path.ends_with("image_1076.png"), "daily mission officer does not use the original actor artwork")

	main._open_actor_dialogue("daily_officer")
	assert(main.dialogue_panel.visible, "daily mission officer dialogue did not open")
	assert(main.dialogue_panel.speaker_label.text == "日常任务官", "daily mission officer speaker is incorrect")
	assert(main.dialogue_panel.body_label.text.contains("雪域边境"), "Friday raid briefing is missing")
	main._handle_dialogue_action("quest_accept:border_raid")
	assert(GameState.quest_states["border_raid"].status == "active", "Friday border raid was not accepted")
	assert(main.quest_panel.visible, "accepted daily quest did not open the quest ledger")

	GameState.current_day = 6
	main._open_actor_dialogue("daily_officer")
	assert(main.dialogue_panel.body_label.text.contains("PK"), "Saturday PK briefing is missing")
	GameState.current_day = 7
	main._open_actor_dialogue("daily_officer")
	assert(main.dialogue_panel.body_label.text.contains("地下城"), "Sunday dungeon briefing is missing")
	main._handle_dialogue_action("enter_dungeon")
	assert(GameState.current_map_id == "dungeon", "Sunday officer did not enter dungeon floor one")
	assert(main.background.texture.resource_path.ends_with("image_1281.jpg"), "dungeon entry uses the wrong background")
	main._open_daily_help_dialogue()
	assert(main.dialogue_panel.body_label.text.contains("周一") and main.dialogue_panel.body_label.text.contains("周日"), "weekly mission overview is incomplete")

	print("PASS original daily mission officer artwork, weekday briefings, and quest entry")
	get_tree().quit(0)
