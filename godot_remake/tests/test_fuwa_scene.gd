extends Node

const WorldService = preload("res://scripts/world_service.gd")
const CombatService = preload("res://scripts/combat_service.gd")


func _ready() -> void:
	var world := WorldService.new()
	assert(world.get_map("green_field").name == "草原", "grass event map was not restored")
	assert(world.get_map("green_field").background.ends_with("image_1097.jpg"), "grass background is not SWF bitmap 1097")
	assert(world.get_map("grass_reward").name == "草原2", "second grass event frame is missing")
	assert(world.get_map("treeheart_city").background.ends_with("image_1299.jpg"), "Treeheart City background is not SWF bitmap 1299")
	assert(world.get_map("avit_island").background.ends_with("image_1252.jpg"), "Avit Island background is not SWF bitmap 1252")
	assert(world.get_map("thunder_continent").background.ends_with("image_1066.jpg"), "Thunder Continent background is not SWF bitmap 1066")
	assert(world.get_map("desert").background.ends_with("image_1226.jpg"), "desert background is not SWF bitmap 1226")
	assert(world.get_map("dungeon").background.ends_with("image_1281.jpg") and world.get_map("dungeon_floor_2").background.ends_with("image_1287.jpg") and world.get_map("dungeon_floor_3").background.ends_with("image_1292.jpg"), "dungeon background sequence is incorrect")
	assert(world.get_map("pk_arena").background.ends_with("image_1294.jpg") and world.get_map("abyss_maze").background.ends_with("image_1268.jpg"), "PK arena or Abyss Maze background is incorrect")
	assert(not world.maps.has("spider_cave"), "invented spider cave still exists")
	assert(not world.can_travel("cassano_city", "green_field"), "grass event incorrectly remained a normal city exit")
	assert(world.can_travel("dungeon", "cassano_city"), "dungeon first floor does not return to Cassano")
	assert("spider" in world.encounters_for("dream_swamp"), "spider was not restored to Dream Swamp")
	assert("spider_queen" in world.encounters_for("avit_island"), "spider queen was not restored to Avit Island")

	var combat := CombatService.new(11)
	assert(combat.roll_drops("fuwa_beast", [0.49]) == ["war_soul_heart"], "Fuwa beast first exclusive reward is incorrect")
	assert(combat.roll_drops("fuwa_beast", [0.50]) == ["enhanced_moon_box"], "Fuwa beast second exclusive reward is incorrect")

	GameState.fuwa_event = GameState.default_fuwa_event()
	GameState.current_map_id = "thunder_continent"
	GameState.level = 100
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(main.interactive_actors.has("fuwa_messenger"), "Olympic messenger did not appear on the selected original map")
	assert(main.interactive_actors.fuwa_messenger.texture.resource_path.ends_with("image_1086.png"), "Olympic messenger artwork is not original")

	var start := GameState.start_fuwa_round()
	assert(start.success and GameState.current_map_id == "green_field", "Fuwa round did not enter grass")
	main._apply_current_map()
	assert(main.interactive_actors.has("battle:fuwa_beast"), "Thunderhorn Fang Beast is missing from grass")
	assert(main.interactive_actors["battle:fuwa_beast"].position == Vector2(483.55, 243), "Fuwa beast does not use the SWF placement")

	var story := GameState.apply_victory_rewards({"monster_id":"fuwa_beast"})
	assert(story.event == "fuwa_beast" and GameState.fuwa_event.beast_defeated, "Fuwa beast victory did not unlock grass 2")
	GameState.current_map_id = "grass_reward"
	main._apply_current_map()
	assert(main.interactive_actors.has("fuwa_reward"), "current Fuwa is missing from grass 2")
	assert(main.interactive_actors.fuwa_reward.texture.resource_path.ends_with("image_1101.png"), "first Fuwa artwork is incorrect")

	var first := GameState.claim_fuwa_reward(0)
	assert(first.success and first.fuwa_name == "贝贝" and first.item_id == "rose_bouquet_999", "first Fuwa reward is incorrect")
	assert(GameState.fuwa_event.found_count == 1 and GameState.current_map_id == "cassano_city", "first Fuwa round did not close correctly")
	assert(GameState.refresh_fuwa_messenger_for_new_day(2).is_empty(), "original one-in-nine no-messenger roll is missing")
	assert(GameState.refresh_fuwa_messenger_for_new_day(3) == "palace", "original map roll did not select the palace")

	for reward_index in [1, 2, 0, 1]:
		assert(GameState.start_fuwa_round().success, "later Fuwa round could not start")
		assert(GameState.complete_fuwa_beast_battle().triggered, "later Fuwa beast victory failed")
		var reward := GameState.claim_fuwa_reward(reward_index)
		assert(reward.success, "later Fuwa reward could not be claimed")
	assert(GameState.fuwa_event.found_count == 5 and GameState.current_map_id == "treeheart_city", "fifth Fuwa did not open Treeheart City")
	main._apply_current_map()
	assert(main.interactive_actors.has("fuwa_completion"), "final Olympic messenger is missing from Treeheart City")
	assert(main.actor_layer.get_child_count() >= 7, "Treeheart City is missing the five Fuwa decorations")

	var stones_before := GameState.magic_stones
	var vip_before := int(GameState.research.get("vip_level", 0))
	var completion := GameState.claim_fuwa_completion()
	assert(completion.success and GameState.magic_stones == stones_before + 100000, "Fuwa completion did not award 100,000 magic stones")
	assert(GameState.research.vip_level == vip_before + 1, "Fuwa completion did not raise research VIP")
	assert(completion.original_technology_cap == 150 and completion.effective_technology_cap == 300, "original reward or modified research cap is incorrect")
	assert(GameState.current_map_id == "cassano_city" and not GameState.claim_fuwa_completion().success, "Fuwa completion was repeatable")

	GameState.save_path = "user://test_fuwa_v16.json"
	assert(GameState.save_game(), "v16 Fuwa save failed")
	GameState.fuwa_event = GameState.default_fuwa_event()
	assert(GameState.load_game(), "v16 Fuwa save could not be loaded")
	assert(GameState.fuwa_event.found_count == 5 and GameState.fuwa_event.completion_claimed, "v16 Fuwa state was not restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	print("PASS original grass/Fuwa flow, exclusive beast reward, native spider placement, Treeheart completion, and save v16")
	get_tree().quit(0)
