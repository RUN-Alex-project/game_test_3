extends Node


func _ready() -> void:
	GameState.quest_states = GameState.quest_service.default_states()
	GameState.unlocked_maps = {"dungeon_floor_2":false, "dungeon_floor_3":false}
	GameState.story_flags["king_rescued"] = false
	GameState.story_flags["game_won"] = false
	GameState.demon_campaign = GameState.default_demon_campaign()
	GameState.current_day = 1
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_quests()
	var panel = main.quest_panel
	assert(panel.visible, "quest entry did not open the unified ledger")
	assert(panel.position == Vector2(200, 80) and panel.size.is_equal_approx(Vector2(362, 269.3)), "quest ledger does not use native dialogue-sheet bounds")
	assert(panel.get_theme_stylebox("panel").bg_color == Color("ffcc99"), "quest ledger does not use native parchment fill")
	assert(panel.quest_cards.size() == 3, "quest ledger must show all three tracked quests without scrolling")
	var flow := GameState.get_main_flow_state()
	assert(flow.stage == "dungeon_1" and flow.target_map == "dungeon", "new-game main guide does not point to dungeon floor one")
	assert("营救国王" in panel.main_flow_label.text and "地下城一层" in panel.main_target_button.text, "main objective card is incomplete")
	panel._quest_action("dungeon_conquest")
	assert(GameState.quest_states.dungeon_conquest.status == "active", "dungeon quest could not be accepted from ledger")
	GameState.apply_victory_rewards({"monster_id":"dungeon_boss"})
	panel._refresh()
	assert(GameState.get_main_flow_state().stage == "dungeon_2", "floor-one victory did not advance main guide")
	GameState.apply_victory_rewards({"monster_id":"dungeon_boss_2"})
	panel._refresh()
	assert(GameState.get_main_flow_state().stage == "dungeon_3", "floor-two victory did not advance main guide")
	GameState.apply_victory_rewards({"monster_id":"dungeon_boss_3"})
	panel._refresh()
	assert(bool(GameState.story_flags.king_rescued), "floor-three victory did not rescue king")
	assert(GameState.get_main_flow_state().target_map == "demon_camp", "king rescue did not point main guide to final campaign")
	assert(GameState.quest_states.dungeon_conquest.status == "ready" and panel.quest_buttons.dungeon_conquest.text == "领取", "completed dungeon quest is not claimable")
	panel._quest_action("dungeon_conquest")
	assert(GameState.quest_states.dungeon_conquest.status == "completed", "quest reward could not be claimed from ledger")
	panel.close_button.emit_signal("pressed")
	assert(not panel.visible, "quest ledger close control failed")
	print("PASS compact three-quest ledger and main-flow guide from dungeon entry through king rescue")
	get_tree().quit(0)