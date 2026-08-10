extends Node

const BattleSession = preload("res://scripts/battle_session.gd")
const CombatService = preload("res://scripts/combat_service.gd")
const WorldService = preload("res://scripts/world_service.gd")


func _reset_campaign() -> void:
	GameState.story_flags = {
		"king_rescued": true,
		"princess_friend_gift_available": false,
		"maid_year_pig_available": true,
		"game_won": false,
	}
	GameState.demon_campaign = GameState.default_demon_campaign()
	GameState.level = 50
	GameState.equipment = {"weapon": {}, "armor": {}, "boots": {}, "necklace": {}}


func _ready() -> void:
	_reset_campaign()
	var world := WorldService.new()
	assert(world.can_travel("ice_border", "demon_camp"), "snow border does not lead to the center army")
	assert(world.can_travel("demon_camp", "demon_left") and world.can_travel("demon_camp", "demon_right"), "center army does not branch to both wings")
	assert(world.can_travel("demon_camp", "demon_banner") and world.can_travel("demon_banner", "energy_tower"), "commander and energy route is incomplete")
	assert(world.can_travel("energy_tower", "demon_banner"), "energy tower does not return to commander flag")
	assert(world.encounters_for("demon_camp") == ["demon_guard", "demon_assault"], "center army distribution drifted")
	assert(world.encounters_for("demon_left") == ["demon_totem"], "left army distribution drifted")
	assert(world.encounters_for("demon_right") == ["demon_mystery"], "right army distribution drifted")
	assert(world.encounters_for("demon_banner") == ["demon_commander"], "commander distribution drifted")
	assert(world.get_map("ice_border").background.ends_with("image_1271.jpg"), "snow-border background is not the SWF bitmap")
	assert(world.get_map("demon_left").background.ends_with("image_1276.jpg"), "wing-army background is not the SWF bitmap")
	assert(world.get_map("demon_banner").background.ends_with("image_1278.jpg"), "commander background is not the SWF bitmap")
	assert(not GameState.can_enter_map("energy_tower"), "energy tower opened before the commander was defeated")

	var combat := CombatService.new(11)
	var raw_commander := combat.get_monster("demon_commander")
	assert(raw_commander.original_max_hp == 1000000 and raw_commander.original_attack_max == 200000, "original commander evidence data is missing")
	var all_buffs := GameState.final_campaign_modifiers("demon_commander")
	assert(all_buffs.attack == 1.5 and all_buffs.defense == 1.5 and all_buffs.max_hp == 1.5 and all_buffs.combat_power == 1.5, "the four army-wide 50 percent buffs are incomplete")
	var session := BattleSession.new("demon_commander", {"max_hp":9999999, "attack":9999999, "defense":9999999}, 7, all_buffs)
	assert(session.monster.max_hp == 1500000 and session.monster.attack == 6450 and session.monster.defense == 1715, "campaign buffs were not applied to battle stats")

	GameState.equipment.weapon = {"enhancement":{"war_soul_active":true}}
	assert(GameState.roll_final_campaign_drop("demon_assault", 0.249) == "war_soul_heart", "support army 25 percent war-soul-heart roll is wrong")
	assert(GameState.roll_final_campaign_drop("demon_assault", 0.25) == "war_soul_crystal", "support army fallback war-soul crystal is wrong")
	assert(GameState.roll_final_campaign_drop("demon_commander", 0.99) == "war_soul_heart", "commander did not guarantee a war-soul heart when war soul is active")
	GameState.equipment.weapon = {}
	assert(GameState.roll_final_campaign_drop("demon_assault", 0.0).is_empty(), "campaign loot dropped before war soul was active")

	var assault_result := GameState.resolve_final_campaign_victory("demon_assault")
	assert(assault_result.triggered and not GameState.demon_campaign.assault_alive, "assault victory was not persisted")
	assert(GameState.final_campaign_modifiers("demon_guard").attack == 1.0, "destroying assault did not remove the attack buff")
	var day_result := GameState.advance_day()
	assert(day_result.demon_army_revived and GameState.demon_campaign.assault_alive, "the demon energy did not revive destroyed armies at night")

	var commander_result := GameState.resolve_final_campaign_victory("demon_commander")
	assert(commander_result.triggered and GameState.can_enter_map("energy_tower"), "commander victory did not open the energy tower")
	var energy_result := GameState.resolve_final_campaign_victory("demon_energy")
	assert(energy_result.game_won and GameState.story_flags.game_won, "destroying demon energy did not enter the ending state")
	var post_win_day := GameState.advance_day()
	assert(not post_win_day.demon_army_revived and not GameState.demon_campaign.commander_alive, "armies revived after the final victory")

	var previous_save_path := GameState.save_path
	GameState.save_path = "user://final_campaign_test_save.json"
	assert(GameState.save_game(), "final campaign save v14 failed")
	_reset_campaign()
	assert(GameState.load_game(), "final campaign save v14 could not be loaded")
	assert(GameState.story_flags.game_won and not GameState.demon_campaign.commander_alive and not GameState.demon_campaign.energy_alive, "final campaign state was not restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.save_path = previous_save_path

	print("PASS exact six-stage final campaign graph, buffs, drops, resurrection, ending, and save v14")
	get_tree().quit(0)
