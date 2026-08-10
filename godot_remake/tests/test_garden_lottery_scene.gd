extends Node

const WorldService = preload("res://scripts/world_service.gd")


func _clear_inventory() -> void:
	GameState.inventory.clear()
	for _index in GameState.INVENTORY_SIZE:
		GameState.inventory.append({})


func _ready() -> void:
	var world := WorldService.new()
	assert(world.get_map("palace_garden").name == "后花园", "native palace garden map is missing")
	assert(world.get_map("lottery_room").name == "抽奖房", "native lottery room map is missing")
	assert(world.get_map("palace_garden").background.ends_with("image_1175.jpg"), "garden does not retain the palace bitmap")
	assert(world.can_travel("palace", "palace_garden") and world.can_travel("palace_garden", "palace"), "garden route is incomplete")
	assert(world.can_travel("lottery_room", "palace"), "lottery room cannot return to the palace")

	GameState.nobility_merit = 0
	assert(not GameState.can_enter_map("palace_garden"), "commoners can enter the noble garden")
	GameState.nobility_merit = 1000
	assert(GameState.can_enter_map("palace_garden"), "a Baron cannot enter the garden")

	GameState.current_map_id = "palace"
	GameState.story_flags = {
		"king_rescued":false,
		"princess_friend_gift_available":false,
		"maid_year_pig_available":true,
		"maid_combat_stone_available":true,
		"game_won":false,
	}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(main.interactive_actors.has("lottery_officer"), "palace lottery officer is missing")
	assert(main.interactive_actors.lottery_officer.texture.resource_path.ends_with("image_1147.png"), "lottery officer uses the wrong SWF actor")
	main._open_actor_dialogue("lottery_officer")
	assert(main.dialogue_panel.speaker_label.text == "抽奖官", "lottery officer dialogue did not open")
	assert(main.dialogue_panel.body_label.text.contains("28魔石"), "native lottery fee is missing from the briefing")
	main._handle_dialogue_action("enter_lottery_room")
	assert(GameState.current_map_id == "lottery_room", "lottery officer did not teleport to the draw room")
	assert(main.background.texture.resource_path.ends_with("image_1175.jpg"), "lottery room retained the wrong backdrop")
	var chest_count := 0
	for actor_id: String in main.interactive_actors:
		if actor_id.begins_with("lottery:"):
			chest_count += 1
			assert(main.interactive_actors[actor_id].texture.resource_path.ends_with("image_1213.png"), "lottery chest does not use native frame 1213")
	assert(chest_count == 8, "lottery room does not contain all eight original chests")

	_clear_inventory()
	GameState.pets.clear()
	GameState.next_pet_instance_id = 1
	GameState.magic_stones = 1000
	GameState.current_day = 1
	GameState.current_time_used = 0
	var equipment_reward := GameState.open_lottery_chest(0, 5, 4)
	assert(equipment_reward.success and equipment_reward.tier == 1 and equipment_reward.item_id == "lottery_bracelet", "2% tier equipment branch is incorrect")
	var equipment_entry: Dictionary = GameState.inventory[0]
	assert(equipment_entry.enhancement.quality_level == 4 and equipment_entry.enhancement.magic_soul_level == 9 and equipment_entry.enhancement.socket_count == 2, "top-tier equipment parameters are incorrect")
	assert(GameState.magic_stones == 972 and GameState.current_time_used == 2, "a chest did not consume 28 stones and 2 time")

	var lulu := GameState.open_lottery_chest(19, 0)
	assert(lulu.success and lulu.tier == 1 and lulu.pet_template_id == "lulu_pet", "噜噜幻兽 top-tier reward is missing")
	var tier_two := GameState.open_lottery_chest(20, 6)
	assert(tier_two.success and tier_two.tier == 2 and tier_two.item_id == "soul_king", "5% tier boundary or soul king reward is incorrect")
	var tier_three := GameState.open_lottery_chest(70, 2)
	assert(tier_three.success and tier_three.tier == 3 and tier_three.pet.quality_score == 1200.0, "38% tier or 12-star beast reward is incorrect")
	var tier_four := GameState.open_lottery_chest(450, 3)
	assert(tier_four.success and tier_four.tier == 4 and tier_four.item_id == "rose_bouquet_99", "55% tier boundary or 99-rose reward is incorrect")
	assert(GameState.magic_stones == 860 and GameState.current_time_used == 10, "five draws consumed the wrong total resources")

	GameState.current_map_id = "palace"
	main._apply_current_map()
	main._travel_to("palace_garden")
	assert(GameState.current_map_id == "palace_garden", "Baron garden route failed")
	for actor_id in ["maid", "princess", "maid_combat_stone"]:
		assert(main.interactive_actors.has(actor_id), "garden actor is missing: " + actor_id)
	assert(main.interactive_actors.maid.position == Vector2(251.5, 220.95), "maid 2 placement differs from the SWF")
	assert(main.interactive_actors.princess.position == Vector2(310.3, 169.45), "garden princess placement differs from the SWF")
	assert(main.interactive_actors.maid_combat_stone.position == Vector2(447.55, 219.95), "maid 1 placement differs from the SWF")

	_clear_inventory()
	GameState.magic_stones = 5000
	GameState.story_flags.maid_combat_stone_available = true
	var maid_trade := GameState.buy_maid_combat_stone()
	assert(maid_trade.success and GameState.magic_stones == 2200 and GameState.count_item("advanced_combat_stone") == 1, "daily maid stone trade is incorrect")
	assert(GameState.buy_maid_combat_stone().reason == "sold_out", "maid combat stone can be bought twice in one day")
	GameState.advance_day()
	assert(GameState.story_flags.maid_combat_stone_available, "daily maid stone did not reset on the next day")

	_clear_inventory()
	var saved_equipment := GameState.open_lottery_chest(0, 5, 4)
	assert(saved_equipment.success and GameState.inventory[0].enhancement.socket_count == 2, "save fixture did not create two-socket equipment")
	GameState.save_path = "user://test_garden_lottery_v17.json"
	assert(GameState.save_game(), "v17 lottery save failed")
	GameState.inventory[0] = {}
	assert(GameState.load_game(), "v17 lottery save could not be loaded")
	assert(GameState.inventory[0].enhancement.socket_count == 2, "lottery equipment sockets were lost after save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	print("PASS native garden gate and actors, four-tier lottery, eight chests, maid trade, and save v17")
	get_tree().quit(0)
