extends Node

const SkillService = preload("res://scripts/skill_service.gd")


func _ready() -> void:
	var service := SkillService.new()
	assert(not service.unlock_relationship_skills({}, 99).has("love_power"), "love power unlocked below 100 affection")
	assert(int(service.unlock_relationship_skills({}, 100).love_power) == 1, "100 affection did not unlock rank 1 love power")
	assert(int(service.unlock_relationship_skills({}, 200).love_power) == 2, "200 affection did not unlock rank 2 love power")
	assert(is_equal_approx(service.utility_success_chance({"love_power":1}, "love_power"), 0.80), "rank 1 love power chance is incorrect")
	assert(is_equal_approx(service.utility_success_chance({"love_power":2}, "love_power"), 0.75), "rank 2 love power chance is incorrect")

	GameState._initialize_inventory()
	GameState._initialize_pets()
	GameState.learned_skills.clear()
	GameState.affection = 50
	GameState.base_stats.luck = 0
	GameState.last_princess_gift_day = 0
	assert(GameState.add_item("rose", 89), "relationship rose fixture failed")
	var first_unlock := GameState.give_roses(99)
	assert(first_unlock.success and GameState.affection == 100, "rank 1 relationship boundary was not reached")
	assert(int(GameState.learned_skills.get("love_power", 0)) == 1, "integrated rank 1 love power unlock failed")
	GameState.pets[0].current_hp = 0
	GameState.player_current_hp = 1
	var first_cast := GameState.use_love_power(0.7999)
	assert(first_cast.success and int(first_cast.luck) == 10 and int(GameState.base_stats.luck) == 10, "rank 1 love power effect is incorrect")
	assert(int(GameState.pets[0].current_hp) == int(GameState.pet_service.get_stats(GameState.pets[0]).max_hp), "love power did not fully heal pets")
	assert(GameState.player_current_hp == GameState.get_player_stats().max_hp, "love power did not fully heal the player")
	assert(not GameState.use_love_power(0.80).success, "rank 1 love power accepted its exclusive upper boundary")

	GameState.affection = 150
	assert(GameState.add_item("rose", 99), "rank 2 rose fixture failed")
	var second_unlock := GameState.give_roses(99)
	assert(second_unlock.success and GameState.affection == 200, "rank 2 relationship boundary was not reached")
	assert(int(GameState.learned_skills.get("love_power", 0)) == 2, "integrated rank 2 love power unlock failed")
	var second_cast := GameState.use_love_power(0.7499)
	assert(second_cast.success and int(second_cast.luck) == 20 and int(GameState.base_stats.luck) == 30, "rank 2 love power effect is incorrect")
	assert(not GameState.use_love_power(0.75).success, "rank 2 love power accepted its exclusive upper boundary")

	assert(GameState.princess_sunday_gift_item_id(1, false) == "advanced_exp_stone", "early relationship Sunday gift is incorrect")
	assert(GameState.princess_sunday_gift_item_id(3, false) == "advanced_combat_stone", "mid relationship Sunday gift is incorrect")
	assert(GameState.princess_sunday_gift_item_id(5, false) == "soul_king", "lover relationship Sunday gift is incorrect")
	assert(GameState.princess_sunday_gift_item_id(6, false) == "plasma_potion", "pre-war-soul final Sunday gift is incorrect")
	assert(GameState.princess_sunday_gift_item_id(6, true) == "war_soul_heart", "post-war-soul final Sunday gift is incorrect")

	GameState.current_day = 7
	GameState.affection = 100
	var sunday := GameState.claim_princess_sunday_gift()
	assert(sunday.success and sunday.item_id == "soul_king", "Sunday gift claim did not use the current relationship tier")
	assert(not GameState.claim_princess_sunday_gift().success, "Sunday gift could be claimed twice on one day")
	GameState.current_day = 8
	assert(GameState.claim_princess_sunday_gift().reason == "not_sunday", "weekday gift claim was accepted")
	GameState.current_day = 14
	GameState.affection = 200
	var final_gift := GameState.claim_princess_sunday_gift()
	assert(final_gift.success and final_gift.item_id == "plasma_potion", "final relationship Sunday gift is incorrect")
	var potion_slot := -1
	for index in GameState.inventory.size():
		if GameState.inventory[index].get("item_id", "") == "plasma_potion":
			potion_slot = index
			break
	assert(potion_slot >= 0 and GameState.use_inventory_item(potion_slot), "plasma potion could not be used")
	assert(int(GameState.base_stats.luck) == 100, "plasma potion did not set luck to 100")

	var previous_save_path := GameState.save_path
	GameState.save_path = "user://relationship_test_save.json"
	assert(GameState.save_game(), "relationship save v12 failed")
	GameState.base_stats.luck = 0
	GameState.last_princess_gift_day = 0
	GameState.learned_skills.clear()
	assert(GameState.load_game(), "relationship save v12 could not be loaded")
	assert(int(GameState.base_stats.luck) == 100, "saved luck was not restored")
	assert(GameState.last_princess_gift_day == 14, "Sunday gift claim state was not restored")
	assert(int(GameState.learned_skills.get("love_power", 0)) == 2, "relationship skill rank was not restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.save_path = previous_save_path
	print("PASS love power unlocks/effects, exact Sunday gifts, plasma potion, and save v12")
	get_tree().quit(0)
