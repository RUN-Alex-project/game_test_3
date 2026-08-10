extends Node

const WorldService = preload("res://scripts/world_service.gd")
const ShopPanel = preload("res://scripts/shop_panel_original.gd")


func _clear_inventory() -> void:
	for index in GameState.inventory.size():
		GameState.inventory[index] = {}


func _find_ore(item_id: String) -> int:
	for index in GameState.inventory.size():
		if str(GameState.inventory[index].get("item_id", "")) == item_id:
			return index
	return -1


func _ready() -> void:
	var world := WorldService.new()
	assert(world.can_travel("thunder_continent", "thunder_mine"), "thunder continent does not lead to the original mine")
	assert(world.can_travel("thunder_mine", "thunder_continent"), "mine does not return to thunder continent")
	assert(world.get_map("thunder_mine").background.ends_with("image_1091.jpg"), "mine background is not the SWF bitmap 1091")

	_clear_inventory()
	GameState.current_day = 1
	GameState.current_time_used = 0
	GameState.gold = 0
	GameState.magic_stones = 0
	var gold_result := GameState.mine_ore(10, 101)
	assert(gold_result.success and gold_result.item_id == "gold_ore" and gold_result.quality == 10, "gold-ore boundary or quality rule drifted")
	assert(gold_result.time_remaining == 14 and GameState.current_time_used == 1, "mining did not spend exactly one time point")
	var gold_slot := _find_ore("gold_ore")
	assert(gold_slot >= 0 and int(GameState.inventory[gold_slot].ore_quality) == 10, "ore quality was not stored on the inventory instance")
	assert(GameState.ore_sale_value(GameState.inventory[gold_slot], "magic_stones") == 280, "quality-10 gold ore is not worth 280 magic stones")
	assert(GameState.ore_sale_value(GameState.inventory[gold_slot], "gold") == 0, "gold ore was accepted by the wrong merchant")

	var silver_result := GameState.mine_ore(3, 100)
	assert(silver_result.success and silver_result.item_id == "silver_ore" and silver_result.quality == 3, "silver-ore boundary drifted")
	var silver_slot := _find_ore("silver_ore")
	assert(GameState.ore_sale_value(GameState.inventory[silver_slot], "gold") == 30000, "silver ore quality price formula drifted")
	var silver_sale := GameState.sell_inventory_ore(silver_slot, "gold")
	assert(silver_sale.success and silver_sale.amount == 30000 and GameState.gold == 30000, "grocery did not buy silver ore atomically")
	var gold_sale := GameState.sell_inventory_ore(gold_slot, "magic_stones")
	assert(gold_sale.success and gold_sale.amount == 280 and GameState.magic_stones == 280, "collector did not buy gold ore atomically")

	GameState.spend_time(12)
	assert(GameState.current_day == 1 and GameState.remaining_time() == 1, "time advanced a day before reaching 15")
	var rollover := GameState.mine_ore(1, 0)
	assert(rollover.day_advanced and GameState.current_day == 2 and GameState.remaining_time() == 15, "fifteenth time point did not advance to the next day")

	GameState.current_map_id = "thunder_mine"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var mine_actor_count := 0
	for action_id: String in main.interactive_actors:
		if action_id.begins_with("mine:"):
			mine_actor_count += 1
	assert(mine_actor_count == 4, "the original four mine points are not present in scene")
	assert(main.time_box.text == "15", "footer did not show persisted remaining time")

	var shop := ShopPanel.new()
	shop.currency = "gold"
	add_child(shop)
	shop.open_mode("sell")
	assert(shop.current_mode == "sell", "grocery sell mode did not open")

	var previous_save_path := GameState.save_path
	GameState.current_time_used = 7
	GameState.save_path = "user://mining_test_save.json"
	assert(GameState.save_game(), "mining save v15 failed")
	GameState.current_time_used = 0
	_clear_inventory()
	assert(GameState.load_game(), "mining save v15 could not be loaded")
	assert(GameState.current_time_used == 7 and GameState.current_map_id == "thunder_mine", "mining time or map was not restored")
	var saved_ore_slot := _find_ore("silver_ore")
	assert(saved_ore_slot >= 0 and int(GameState.inventory[saved_ore_slot].ore_quality) == 1, "ore instance quality was lost in save normalization")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.save_path = previous_save_path

	print("PASS original mine map, four nodes, ore rolls, quality prices, time rollover, merchant sale, and save v15")
	get_tree().quit(0)
