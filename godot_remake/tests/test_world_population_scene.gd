extends Node

const CombatService = preload("res://scripts/combat_service.gd")
const WorldService = preload("res://scripts/world_service.gd")


func _ready() -> void:
	var world := WorldService.new()
	var expected_encounters := {
		"thunder_continent":["thunder_giant", "thunder_dragon", "thunder_boss_10", "territory_thunder_guard"],
		"desert":["desert_ice_swordsman", "desert_jack_lantern", "desert_typhon", "desert_boss_20", "territory_desert_guard"],
		"dream_swamp":["swamp_fanged_demon", "swamp_horned_lizard", "swamp_boss_30", "spider", "territory_swamp_guard"],
		"ice_palace":["ice_taya_dragon", "ice_death_knight", "ice_boss_50", "territory_ice_guard"],
		"avit_island":["avit_fish_demon", "avit_terror_beast", "avit_giant_axe", "avit_thorn_bug", "avit_boss_70", "spider_queen", "territory_avit_guard"],
		"volcano":["volcano_four_fang", "volcano_fire_woman", "volcano_scorpion", "volcano_boss_90"],
		"abyss_maze":["abyss_dark_messiah", "abyss_dark_grass", "abyss_sigh_knight", "abyss_boss_100"],
	}
	for map_id: String in expected_encounters:
		assert(world.encounters_for(map_id) == expected_encounters[map_id], "native encounter manifest is incomplete: " + map_id)

	var combat := CombatService.new(11)
	var native_levels := {
		"thunder_giant":1, "thunder_dragon":5,
		"desert_ice_swordsman":10, "desert_jack_lantern":15, "desert_typhon":25,
		"swamp_fanged_demon":35, "swamp_horned_lizard":45,
		"ice_taya_dragon":55, "ice_death_knight":65,
		"avit_fish_demon":70, "avit_terror_beast":75, "avit_giant_axe":80, "avit_thorn_bug":85,
		"volcano_four_fang":90, "volcano_fire_woman":95, "volcano_scorpion":100,
		"abyss_dark_messiah":110, "abyss_dark_grass":120, "abyss_sigh_knight":130,
	}
	for monster_id: String in native_levels:
		var monster := combat.get_monster(monster_id)
		assert(int(monster.level) == native_levels[monster_id] and int(monster.original_level) == native_levels[monster_id], "native level is incorrect: " + monster_id)
		assert(not bool(monster.is_boss) and int(monster.base_military_merit) == 0, "normal monster was treated as a boss: " + monster_id)
	assert(int(combat.get_monster("spider").level) == 45, "native spider level was not corrected")
	assert(int(combat.get_monster("spider_queen").level) == 80, "native spider queen level was not corrected")
	assert(combat.roll_drops("thunder_giant", [0.0252, 1.0], 0) == ["soul_crystal"], "native 2.5% x baoli soul-crystal drop is missing")
	assert(combat.roll_drops("thunder_giant", [0.0253, 1.0], 0).is_empty(), "native soul-crystal boundary must use roll < chance")
	assert(combat.roll_drops("abyss_sigh_knight", [1.0, 1.0], 0).is_empty(), "normal monsters must not use the obsolete soul-king/moon-box table")

	GameState.current_map_id = "thunder_continent"
	GameState.story_flags = {
		"king_rescued":false, "princess_friend_gift_available":false,
		"maid_year_pig_available":true, "maid_combat_stone_available":true,
		"war_soul_quest_available":false, "war_soul_secret_unlocked":false,
		"game_won":false,
	}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(main._world_monster_id_from_action("battle:thunder_giant@2") == "thunder_giant", "multi-instance monster key did not normalize")

	var expected_actors := {
		"thunder_continent":{
			"battle:thunder_giant@1":[Vector2(374.1,146.3), "image_0049.png"],
			"battle:thunder_dragon@1":[Vector2(539.7,96.55), "image_0051.png"],
			"battle:thunder_boss_10":[Vector2(543.1,386.55), "image_1072.png"],
			"battle:thunder_giant@2":[Vector2(398.45,365.25), "image_0049.png"],
		},
		"desert":{
			"battle:desert_ice_swordsman@1":[Vector2(546,90.55), "image_0053.png"],
			"battle:desert_jack_lantern@2":[Vector2(387.7,239.55), "image_0055.png"],
			"battle:desert_typhon@1":[Vector2(386.55,385.55), "image_0057.png"],
			"battle:desert_boss_20":[Vector2(539.7,385.55), "image_1072.png"],
		},
		"dream_swamp":{
			"battle:swamp_fanged_demon@1":[Vector2(444.2,198), "image_0059.png"],
			"battle:spider":[Vector2(27,371), "image_0063.png"],
			"battle:swamp_horned_lizard@2":[Vector2(515.3,387), "image_0061.png"],
			"battle:swamp_boss_30":[Vector2(191,371), "image_1072.png"],
		},
		"ice_palace":{
			"battle:ice_taya_dragon@1":[Vector2(328.85,366), "image_0065.png"],
			"battle:ice_death_knight@2":[Vector2(539.7,378.9), "image_0067.png"],
			"battle:ice_boss_50":[Vector2(543.5,96), "image_1072.png"],
		},
		"avit_island":{
			"battle:avit_fish_demon@1":[Vector2(305,339.55), "image_0069.png"],
			"battle:avit_terror_beast@1":[Vector2(203.9,87), "image_0071.png"],
			"battle:avit_giant_axe@1":[Vector2(361,115.15), "image_0073.png"],
			"battle:spider_queen":[Vector2(539.7,90), "image_0075.png"],
			"battle:avit_thorn_bug@1":[Vector2(457,243), "image_0077.png"],
		},
		"volcano":{
			"battle:volcano_four_fang@1":[Vector2(470,361.4), "image_0079.png"],
			"battle:volcano_fire_woman@2":[Vector2(318,210.85), "image_0081.png"],
			"battle:volcano_scorpion@1":[Vector2(539.7,91.3), "image_0083.png"],
			"battle:volcano_boss_90":[Vector2(379.45,91.3), "image_1072.png"],
		},
		"abyss_maze":{
			"battle:abyss_dark_messiah@2":[Vector2(505.2,97.3), "image_0085.png"],
			"battle:abyss_dark_grass@2":[Vector2(349,270.5), "image_0087.png"],
			"battle:abyss_sigh_knight@2":[Vector2(537.7,378.9), "image_0089.png"],
			"battle:abyss_boss_100":[Vector2(209.8,389.55), "image_1072.png"],
		},
	}
	for map_id: String in expected_actors:
		GameState.current_map_id = map_id
		main._apply_current_map()
		for action_id: String in expected_actors[map_id]:
			assert(main.interactive_actors.has(action_id), "native actor is missing: " + action_id)
			var expected: Array = expected_actors[map_id][action_id]
			assert(main.interactive_actors[action_id].position == expected[0], "native actor position is wrong: " + action_id)
			assert(main.interactive_actors[action_id].texture.resource_path.ends_with(expected[1]), "native actor frame is wrong: " + action_id)

	print("PASS 19 native normal-monster species, 29 world instances, levels, frames, positions, and drops")
	get_tree().quit(0)
