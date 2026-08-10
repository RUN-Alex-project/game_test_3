extends Node

const WorldService = preload("res://scripts/world_service.gd")
const BattleSession = preload("res://scripts/battle_session.gd")


func _ready() -> void:
	var world := WorldService.new()
	assert(not world.can_travel("cassano_city", "green_field"), "event-only grass became a normal city exit")
	assert(not world.can_travel("cassano_city", "dungeon"), "map service allowed a non-adjacent teleport")
	assert(world.encounters_for("green_field") == ["fuwa_beast"], "grass event encounter is incorrect")
	assert("spider" in world.encounters_for("dream_swamp") and "spider_queen" in world.encounters_for("avit_island"), "native spider encounters are incorrect")
	assert(world.can_travel("ice_palace", "ice_border") and world.can_travel("ice_border", "ice_palace"), "ice border travel route is incomplete")
	assert(world.encounters_for("ice_border") == ["snow_warrior", "snow_cavalry", "snow_officer"], "ice border encounters are incorrect")
	assert(world.can_travel("cassano_city", "palace") and not world.can_travel("palace", "pk_arena") and world.can_travel("pk_arena", "cassano_city"), "native officer-only PK route is incorrect")
	assert(world.encounters_for("pk_arena") == ["pk_champion_60"] and world.encounters_for("pk_arena_2") == ["pk_champion_100"] and world.encounters_for("pk_arena_3") == ["pk_champion_130"], "three PK arena groups are incomplete")
	assert(world.can_travel("dungeon", "cassano_city") and world.can_travel("dungeon", "dungeon_floor_2") and world.can_travel("dungeon_floor_2", "dungeon_floor_3"), "dungeon floor graph is incomplete")
	assert(world.encounters_for("dungeon_floor_3") == ["dungeon_boss_3"], "dungeon floor three encounter is incorrect")

	var base := GameState.get_player_stats()
	assert(int(base.combat_power) == 288, "base combat power including two deployed pets is incorrect")
	assert(not GameState.equip_from_inventory(0), "skill book was accepted as equipment")
	assert(GameState.equip_from_inventory(6), "weapon equip failed")
	var weapon_stats := GameState.get_player_stats()
	assert(int(weapon_stats.attack) == 98 and int(weapon_stats.combat_power) == 388, "weapon stats are incorrect")
	assert(GameState.equip_from_inventory(7), "armor equip failed")
	var full_stats := GameState.get_player_stats()
	assert(int(full_stats.max_hp) == 670 and int(full_stats.defense) == 61, "armor stats are incorrect")
	assert(int(full_stats.combat_power) == 460, "equipped combat power is incorrect")

	assert(GameState.add_item("enhanced_moon_box"), "quality material setup failed")
	assert(GameState.add_item("magic_soul_crystal"), "magic soul material setup failed")
	assert(GameState.add_item("war_soul_crystal", 2), "war soul material setup failed")
	assert(GameState.add_item("war_soul_heart", 10), "soul material setup failed")
	assert(GameState.enhance_equipped("weapon", "quality").success, "integrated quality refining failed")
	assert(GameState.enhance_equipped("weapon", "magic_soul").success, "integrated magic soul failed")
	assert(not GameState.enhance_equipped("weapon", "war_soul", 0.50).success, "war soul boundary should fail")
	assert(GameState.enhance_equipped("weapon", "war_soul", 0.4999).success, "war soul success branch failed")
	for index in 5:
		assert(GameState.increase_equipped_soul("weapon", "heaven"), "heaven soul level %d failed" % (index + 1))
		assert(GameState.increase_equipped_soul("weapon", "earth"), "earth soul level %d failed" % (index + 1))
	assert(not GameState.increase_equipped_soul("weapon", "heaven"), "heaven soul exceeded its cap")
	assert(GameState.count_item("enhanced_moon_box") == 0, "quality material was not consumed")
	assert(GameState.count_item("magic_soul_crystal") == 0, "magic soul material was not consumed")
	assert(GameState.count_item("war_soul_crystal") == 0, "war soul attempts did not consume crystals")
	assert(GameState.count_item("war_soul_heart") == 0, "soul upgrades did not consume hearts")
	var enhanced_stats := GameState.get_player_stats()
	assert(int(enhanced_stats.attack) == 144, "quality, magic soul, or heaven soul attack integration is incorrect")
	assert(int(enhanced_stats.dodge_percent) == 20, "earth soul dodge integration is incorrect")
	assert(int(enhanced_stats.combat_power) == 583, "war soul and pet combat power integration is incorrect")
	var dodge_stats: Dictionary = enhanced_stats.duplicate(true)
	dodge_stats.battle_pets = []
	var dodge_battle := BattleSession.new("spider_queen", dodge_stats, 19)
	var dodge_turn := dodge_battle.perform_turn(1.0, 1.0, 0.19)
	assert(dodge_turn.dodged and dodge_turn.monster_damage == 0, "earth soul dodge did not prevent damage")

	var overpower := {"max_hp": 1000, "attack": 50000, "defense": 1000, "combat_power": 1}
	GameState.base_stats.luck = 0
	var battle := BattleSession.new("spider_queen", overpower, 7)
	var turn := battle.perform_turn(1.0, 1.0)
	assert(turn.finished and turn.victory and battle.monster_hp == 0, "battle victory state is incorrect")
	var rewards := battle.victory_payload([0.39, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.49])
	assert(rewards.experience == 30000 and rewards.military_merit == 10000, "battle reward payload is incorrect")
	assert(rewards.drops == ["advanced_fighting_spirit", "enhanced_moon_box"], "battle loot payload is incorrect")

	GameState.level = 1
	GameState.experience = 0
	GameState.military_merit = 0
	GameState.base_stats = {"max_hp": 550, "attack": 60, "defense": 30}
	GameState.apply_victory_rewards(rewards)
	assert(GameState.level == 8 and GameState.experience == 2000, "multi-level experience settlement is incorrect")
	assert(GameState.military_merit == 10000, "military merit settlement is incorrect")
	assert(GameState.get_military_rank().name == "少校", "boss merit did not promote the military rank")
	assert(GameState.pets[0].level == 6 and GameState.pets[1].level == 6, "deployed pets did not receive base monster experience")
	assert(GameState.add_item("enhanced_moon_box"), "defined battle drop could not enter inventory")
	print("PASS world graph, equipment enhancement stats, soul dodge, combat rewards, leveling, and loot pickup")
	get_tree().quit(0)
