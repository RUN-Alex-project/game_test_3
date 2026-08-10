extends Node

const CombatService = preload("res://scripts/combat_service.gd")


func _ready() -> void:
	var combat := CombatService.new(23)
	assert(is_equal_approx(combat.loot_multiplier_from_luck(0), 1.01), "native baoli at zero luck is wrong")
	assert(is_equal_approx(combat.loot_multiplier_from_luck(100), 2.01), "native baoli at 100 luck is wrong")
	assert(combat.victory_rewards("thunder_giant", 100).gold == 2533, "normal monster native gold formula is wrong")
	assert(combat.victory_rewards("abyss_boss_100", 100).gold == 1000, "normal BOSS native gold is wrong")
	assert(combat.victory_rewards("spider", 100).gold == 0, "spider incorrectly used generic gold")

	var spider_all := combat.roll_drops("spider", [0.0,0.0,0.0,0.0,0.0], 0)
	assert(spider_all == ["skill_fighting_spirit","skill_flying_slash","skill_star_sword","soul_crystal","moon_box"], "spider native independent drops are incomplete")
	assert(combat.roll_drops("spider", [1.0,1.0,1.0,1.0,1.0], 0).is_empty(), "spider failure boundaries are wrong")
	var queen_all := combat.roll_drops("spider_queen", [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0], 0)
	assert(queen_all == ["advanced_fighting_spirit","advanced_star_sword","advanced_flying_slash","soul_crystal","soul_king","illusion_heart","magic_soul_heart","enhanced_moon_box"], "queen native drop table is incomplete")
	assert(not "enhanced_moon_box" in combat.roll_drops("spider_queen", [1.0,1.0,1.0,1.0,1.0,1.0,1.0,0.50], 0), "enhanced moon box 50 percent boundary is wrong")

	var normal_rolls: Array[float] = [0.0252,0.249,0.29,0.50,1.0,1.0,0.50,0.99,0.04,0.99,0.999]
	var normal_drops := combat.roll_drops("thunder_giant", normal_rolls, 0)
	assert(normal_drops == ["soul_crystal","loot_equipment|field_boots|1|1|9|1"], "normal monster crystal/equipment algorithm is wrong")
	assert(combat.roll_drops("thunder_giant", [0.0253,0.25], 0).is_empty(), "normal monster exact probability boundaries are wrong")

	var boss_rolls: Array[float] = [0.49,0.099,0.499,0.699,0.74,0.999,0.24,0.81,0.0]
	var boss_drops := combat.roll_drops("abyss_boss_100", boss_rolls, 0, true)
	assert(boss_drops == ["soul_crystal","soul_king","enhanced_moon_box","loot_equipment|field_weapon|100|3|9|2"], "normal BOSS native drops or equipment attributes are wrong")
	assert(combat.roll_drops("abyss_boss_100", [0.51,1.0,0.50,1.0,1.0,0.0,1.0,0.0,0.0], 0, true)[0] == "war_soul_crystal", "war-soul crystal branch is wrong")

	GameState.inventory.fill({})
	GameState.loot_queue.clear()
	var token := "loot_equipment|field_weapon|100|4|12|2"
	GameState.queue_loot([token])
	assert(GameState.loot_queue == [token] and GameState.get_item_definition(token).name == "100级野外武器", "equipment loot token did not enter the queue")
	assert(GameState.claim_loot(token), "equipment loot token could not be claimed")
	var entry: Dictionary = GameState.inventory[0]
	assert(entry.item_id == "field_weapon" and entry.drop_level == 100, "claimed equipment identity or level is wrong")
	assert(entry.enhancement.quality_level == 4 and entry.enhancement.magic_soul_level == 12 and entry.enhancement.socket_count == 2, "claimed equipment instance attributes were lost")

	var previous_save_path := GameState.save_path
	GameState.save_path = "user://native_loot_v20_test.json"
	var queued_token := "loot_equipment|field_boots|125|3|9|1"
	GameState.queue_loot([queued_token])
	assert(GameState.save_game(), "native loot v20 save failed")
	GameState.inventory.fill({})
	GameState.loot_queue.clear()
	assert(GameState.load_game(), "native loot v20 save could not be loaded")
	entry = GameState.inventory[0]
	assert(entry.item_id == "field_weapon" and entry.drop_level == 100 and entry.enhancement.magic_soul_level == 12, "claimed random equipment did not survive save/load")
	assert(GameState.loot_queue == [queued_token] and GameState.get_item_definition(queued_token).name == "125级野外战靴", "unclaimed random equipment did not survive save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.save_path = previous_save_path

	print("PASS native baoli, spider/queen drops, normal/BOSS loot, gold, equipment instances, and v20 saves")
	get_tree().quit(0)
