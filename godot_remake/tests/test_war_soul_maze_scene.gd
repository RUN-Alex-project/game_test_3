extends Node

const BattleSession = preload("res://scripts/battle_session.gd")
const CombatService = preload("res://scripts/combat_service.gd")
const WorldService = preload("res://scripts/world_service.gd")


func _set_extreme_quality_set(last_quality: int = 4) -> void:
	var slots := ["weapon", "helmet", "necklace", "armor", "bracelet", "boots"]
	for index in slots.size():
		var item_id: String = str(GameState.LOTTERY_EQUIPMENT_IDS[index])
		var item := GameState.create_item_entry(item_id)
		item.enhancement.quality_level = last_quality if index == slots.size() - 1 else 4
		GameState.equipment[slots[index]] = item


func _ready() -> void:
	var world := WorldService.new()
	var maze := world.get_map("war_soul_seal_maze")
	assert(maze.name == "战魂封印谜宫", "native war-soul maze map is missing")
	assert(maze.background.ends_with("image_1297.jpg"), "war-soul maze background differs from SWF frame 34")
	assert(int(maze.spawn[0]) == 190 and int(maze.spawn[1]) == 245 and maze.exits.is_empty(), "war-soul maze spawn or no-exit structure is incorrect")
	assert(world.encounters_for("war_soul_seal_maze") == ["nameless_war_soul_keeper"], "war-soul guardian encounter is incorrect")

	GameState.story_flags = {
		"king_rescued":false,
		"princess_friend_gift_available":false,
		"maid_year_pig_available":true,
		"maid_combat_stone_available":true,
		"war_soul_quest_available":false,
		"war_soul_secret_unlocked":false,
		"game_won":false,
	}
	_set_extreme_quality_set(3)
	assert(not GameState.has_full_extreme_quality_set(), "five extreme pieces incorrectly unlocked the quest")
	assert(not GameState.try_unlock_war_soul_quest(), "incomplete extreme set started the quest")
	_set_extreme_quality_set(4)
	assert(GameState.has_full_extreme_quality_set() and GameState.try_unlock_war_soul_quest(), "six extreme pieces did not start the quest")
	assert(not GameState.try_unlock_war_soul_quest(), "war-soul quest was started twice")

	GameState.current_map_id = "desert"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(main.interactive_actors.has("war_soul_explorer"), "quest explorer is missing from the Gobi")
	assert(main.interactive_actors.war_soul_explorer.position == Vector2(18, 325.1), "explorer placement differs from the SWF")

	GameState.magic_stones = 49999
	GameState.current_day = 3
	GameState.current_time_used = 4
	var poor := GameState.enter_war_soul_maze()
	assert(not poor.success and poor.reason == "not_enough_stones", "maze entry ignored the 50,000-stone fee")
	assert(GameState.current_map_id == "desert" and GameState.current_day == 3 and GameState.current_time_used == 4, "failed maze entry changed time or map")

	GameState.magic_stones = 80000
	var entered := GameState.enter_war_soul_maze()
	assert(entered.success and GameState.magic_stones == 30000, "maze trip charged the wrong fee")
	assert(GameState.current_day == 4 and GameState.current_time_used == 4 and entered.day_advanced, "maze trip did not consume one full day")
	assert(GameState.current_map_id == "war_soul_seal_maze" and GameState.war_soul_maze_active, "maze trip did not activate the hidden map")
	main._apply_current_map()
	assert(main.background.texture.resource_path.ends_with("image_1297.jpg"), "main scene did not render the maze bitmap")
	assert(main.interactive_actors.has("war_soul_chest") and not main.interactive_actors.has("battle:nameless_war_soul_keeper"), "guardian appeared before opening the chest")
	assert(main.interactive_actors.war_soul_chest.position == Vector2(649.95, 217.95), "sealed chest placement differs from the SWF")
	main._reveal_war_soul_guardian()
	assert(GameState.war_soul_guardian_revealed, "sealed chest did not reveal the guardian")
	assert(main.interactive_actors.has("battle:nameless_war_soul_keeper"), "nameless guardian actor is missing")
	assert(main.interactive_actors["battle:nameless_war_soul_keeper"].position == Vector2(505.2, 175.95), "nameless guardian placement differs from the SWF")
	assert(main.interactive_actors["battle:nameless_war_soul_keeper"].texture.resource_path.ends_with("image_0101.png"), "nameless guardian uses the wrong original frame")

	GameState.level = 40
	var low_session := BattleSession.new("nameless_war_soul_keeper", GameState.get_player_stats(), 7, GameState.battle_modifiers("nameless_war_soul_keeper"))
	assert(low_session.monster.level == 50 and low_session.monster.combat_power == 150, "guardian minimum level or combat power is incorrect")
	GameState.level = 100
	var high_session := BattleSession.new("nameless_war_soul_keeper", GameState.get_player_stats(), 7, GameState.battle_modifiers("nameless_war_soul_keeper"))
	assert(high_session.monster.level == 100 and high_session.monster.combat_power == 200, "guardian did not follow player level above 50")

	var combat := CombatService.new(7)
	assert(combat.victory_rewards("nameless_war_soul_keeper").experience == 0, "nameless guardian received an invented experience reward")
	assert(combat.roll_drops("nameless_war_soul_keeper", [0.99]) == ["war_soul_heart"], "nameless guardian did not guarantee one war-soul heart")
	var story_result := GameState.apply_victory_rewards(combat.victory_rewards("nameless_war_soul_keeper"))
	assert(story_result.triggered and story_result.event == "war_soul_secret", "guardian victory did not complete the war-soul secret")
	assert(GameState.story_flags.war_soul_secret_unlocked and not GameState.story_flags.war_soul_quest_available, "war-soul quest flags did not close permanently")
	main._on_scene_battle_finished("nameless_war_soul_keeper", true)
	assert(GameState.current_map_id == "cassano_city" and not GameState.war_soul_maze_active, "guardian victory did not return to Cassano")
	GameState.current_map_id = "desert"
	main._apply_current_map()
	assert(not main.interactive_actors.has("war_soul_explorer"), "explorer remained after the secret was found")

	GameState.story_flags.war_soul_secret_unlocked = false
	GameState.story_flags.war_soul_quest_available = true
	GameState.current_map_id = "war_soul_seal_maze"
	GameState.war_soul_maze_active = true
	GameState.war_soul_guardian_revealed = true
	GameState.save_path = "user://test_war_soul_maze_v19.json"
	assert(GameState.save_game(), "war-soul v19 save failed")
	GameState.current_map_id = "cassano_city"
	GameState.war_soul_maze_active = false
	GameState.war_soul_guardian_revealed = false
	assert(GameState.load_game(), "war-soul v19 save could not be loaded")
	assert(GameState.current_map_id == "war_soul_seal_maze" and GameState.war_soul_maze_active and GameState.war_soul_guardian_revealed, "active maze state was not restored")
	GameState.war_soul_maze_active = false
	assert(GameState.save_game(), "inactive maze migration fixture failed")
	assert(GameState.load_game() and GameState.current_map_id == "cassano_city", "inactive maze save did not migrate safely to Cassano")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))

	print("PASS native war-soul quest, extreme set gate, paid trip, guardian, reward, and save v19")
	get_tree().quit(0)
