extends Node

const WorldService = preload("res://scripts/world_service.gd")


func _reset_flow() -> void:
	GameState.quest_states = GameState.quest_service.default_states()
	GameState.unlocked_maps = {"dungeon_floor_2":false, "dungeon_floor_3":false}
	GameState.story_flags = {
		"king_rescued":false,
		"princess_friend_gift_available":false,
		"maid_year_pig_available":true,
		"maid_combat_stone_available":true,
		"war_soul_quest_available":false,
		"war_soul_secret_unlocked":false,
		"game_won":false,
	}
	GameState.demon_campaign = GameState.default_demon_campaign()
	GameState.current_map_id = "cassano_city"
	GameState.level = 130


func _win(monster_id: String) -> Dictionary:
	return GameState.apply_victory_rewards({"monster_id":monster_id, "experience":0, "military_merit":0, "nobility_merit":0})


func _ready() -> void:
	_reset_flow()
	var world := WorldService.new()
	var dungeon_route := world.shortest_route("cassano_city", "dungeon")
	assert(dungeon_route == ["cassano_city", "dungeon"], "NPC-entered dungeon is missing from route guidance")
	var final_route := world.shortest_route("cassano_city", "demon_banner")
	assert(final_route.front() == "cassano_city" and final_route.back() == "demon_banner", "final campaign route has wrong endpoints")
	assert("雪域边境" in world.route_names(final_route), "final campaign route does not pass through snow border")

	assert(GameState.accept_quest("dungeon_conquest"), "end-to-end flow could not accept dungeon quest")
	assert(GameState.get_main_flow_state().stage == "dungeon_1", "flow did not start at dungeon floor one")
	_win("dungeon_boss")
	assert(GameState.get_main_flow_state().stage == "dungeon_2" and GameState.can_enter_map("dungeon_floor_2"), "floor one did not unlock floor two")
	_win("dungeon_boss_2")
	assert(GameState.get_main_flow_state().stage == "dungeon_3" and GameState.can_enter_map("dungeon_floor_3"), "floor two did not unlock floor three")
	var rescue := _win("dungeon_boss_3")
	assert(rescue.get("triggered", false) and bool(GameState.story_flags.king_rescued), "floor three did not complete king rescue")
	assert(GameState.can_enter_map("demon_camp"), "king rescue did not unlock final campaign")

	var expected_stages := [
		["assault_alive", "demon_assault", "guard_alive"],
		["guard_alive", "demon_guard", "totem_alive"],
		["totem_alive", "demon_totem", "mystery_alive"],
		["mystery_alive", "demon_mystery", "commander"],
	]
	for expected: Array in expected_stages:
		assert(GameState.get_main_flow_state().stage == str(expected[0]), "main guide selected the wrong final-campaign target")
		var result := _win(str(expected[1]))
		assert(result.get("triggered", false), "final-campaign victory did not update story state")
		assert(GameState.get_main_flow_state().stage == str(expected[2]), "main guide did not advance after final-campaign victory")
	assert(not GameState.can_enter_map("energy_tower"), "energy tower opened before commander defeat")
	var commander := _win("demon_commander")
	assert(commander.get("triggered", false) and GameState.can_enter_map("energy_tower"), "commander victory did not unlock energy tower")
	assert(GameState.get_main_flow_state().stage == "energy", "main guide did not point to demon energy")
	var ending := _win("demon_energy")
	assert(ending.get("game_won", false) and bool(GameState.story_flags.game_won), "demon energy victory did not finish game")
	var completed := GameState.get_main_flow_state()
	assert(completed.stage == "complete" and int(completed.step) == int(completed.total), "main flow did not reach complete state")

	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(main.ending_panel.visible and "游戏结束" in main.ending_panel.report.text, "completed flow did not enter ending evaluation")
	print("PASS routed end-to-end main flow: three dungeon floors, king rescue, four armies, commander, energy and ending")
	get_tree().quit(0)