extends Node


func _ready() -> void:
	GameState.save_path = "user://test_savegame.json"
	if FileAccess.file_exists(GameState.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	var source: Dictionary = GameState.inventory[0].duplicate(true)
	var stack_count_before := _stack_count()
	assert(GameState.move_item(0, 3), "valid move rejected")
	assert(GameState.inventory[0].is_empty() and GameState.inventory[3] == source, "move was not atomic")

	var snapshot: Array = GameState.inventory.duplicate(true)
	assert(not GameState.move_item(99, 2), "invalid move accepted")
	assert(GameState.inventory == snapshot and _stack_count() == stack_count_before, "invalid drop lost an item")

	assert(GameState.move_item_between("inventory", 3, "warehouse", 0), "warehouse transfer failed")
	assert(GameState.inventory[3].is_empty() and GameState.warehouse[0] == source, "warehouse transfer was not atomic")
	assert(GameState.move_item_between("warehouse", 0, "inventory", 3), "warehouse return failed")

	var gold_before := GameState.gold
	var potion_before := int(GameState.inventory[1].get("quantity", 0))
	assert(GameState.buy_item("exp_potion", "gold"), "gold shop purchase failed")
	assert(GameState.gold == gold_before - 20_000, "gold shop charged the wrong amount")
	assert(int(GameState.inventory[1].get("quantity", 0)) == potion_before + 1, "purchased item was not stacked")

	assert(GameState.move_item_between("inventory", 2, "warehouse", 1), "warehouse save fixture failed")
	assert(GameState.equip_from_inventory(6), "equipment save fixture failed")
	GameState.equipment.weapon.enhancement.quality_level = 2
	GameState.equipment.weapon.enhancement.magic_soul_level = 3
	GameState.queue_loot(["enhanced_moon_box"])
	GameState.current_map_id = "dream_swamp"
	GameState.level = 4
	GameState.experience = 321
	GameState.military_merit = 456
	GameState.nobility_merit = 789
	GameState.affection = 123
	GameState.current_day = 8
	GameState.completed_daily_tasks = {"collect_magic_soul":true}
	GameState.quest_states["spider_crisis"] = {"status":"active", "progress":{"spider":2}}
	GameState.unlocked_maps["dungeon_floor_2"] = true
	GameState.learned_skills = {"flying_slash":2}
	GameState.pets[0].level = 7
	GameState.pets[0].quality_score = 12.5
	GameState.pets[0].current_hp = 9
	GameState.player_current_hp = 321
	GameState.research = {"technology_level":42.0, "production_rate":3, "stock":5, "vip_level":1}
	GameState.gold = 99_999_999_999
	GameState.magic_stones = 99_999_999_999
	assert(GameState.save_game(), "save failed")
	GameState.gold = 1
	GameState.magic_stones = 1
	GameState.inventory[3] = {}
	GameState.warehouse[1] = {}
	GameState.equipment.weapon = {}
	GameState.loot_queue.clear()
	GameState.pets.clear()
	GameState.research = {}
	GameState.current_map_id = "cassano_city"
	GameState.level = 1
	GameState.nobility_merit = 0
	GameState.affection = 0
	GameState.current_day = 1
	GameState.completed_daily_tasks.clear()
	GameState.quest_states.clear()
	GameState.unlocked_maps = {"dungeon_floor_2":false, "dungeon_floor_3":false}
	GameState.learned_skills.clear()
	assert(GameState.load_game(), "load failed")
	assert(GameState.gold == 99_999_999_999 and GameState.magic_stones == 99_999_999_999, "currency save failed")
	assert(GameState.inventory[3].get("item_id", "") == source.get("item_id", ""), "inventory save failed")
	assert(GameState.warehouse[1].get("item_id", "") == "rose", "warehouse save failed")
	assert(GameState.equipment.weapon.get("item_id", "") == "novice_sword", "equipment save failed")
	assert(GameState.equipment.weapon.enhancement.quality_level == 2 and GameState.equipment.weapon.enhancement.magic_soul_level == 3, "equipment enhancement save failed")
	assert(GameState.loot_queue == ["enhanced_moon_box"], "unclaimed loot save failed")
	assert(GameState.current_map_id == "dream_swamp", "map save failed")
	assert(GameState.level == 4 and GameState.experience == 321 and GameState.military_merit == 456, "progression save failed")
	assert(GameState.nobility_merit == 789 and GameState.affection == 123, "nobility or affection save failed")
	assert(GameState.current_day == 8 and GameState.completed_daily_tasks.get("collect_magic_soul", false), "daily task save failed")
	assert(GameState.quest_states.spider_crisis.status == "active" and GameState.quest_states.spider_crisis.progress.spider == 2, "quest state save failed")
	assert(GameState.can_enter_map("dungeon_floor_2") and not GameState.can_enter_map("dungeon_floor_3"), "dungeon unlock save failed")
	assert(GameState.learned_skills.flying_slash == 2, "learned skill save failed")
	assert(GameState.pets.size() == 2 and GameState.pets[0].level == 7 and GameState.pets[0].quality_score == 12.5, "pet instance save failed")
	assert(GameState.player_current_hp == 321 and GameState.pets[0].current_hp == 9, "v12 player or pet current HP save failed")
	assert(GameState.research.technology_level == 42.0 and GameState.research.production_rate == 3, "research state save failed")

	var legacy_payload := {
		"version": 3,
		"gold": GameState.gold,
		"magic_stones": GameState.magic_stones,
		"inventory": GameState.inventory,
		"warehouse": GameState.warehouse,
		"level": GameState.level,
		"experience": GameState.experience,
		"military_merit": GameState.military_merit,
		"current_map_id": "spider_cave",
		"equipment": {"weapon":"novice_sword", "armor":"", "boots":"", "necklace":""},
		"base_stats": GameState.base_stats,
		"loot_queue": GameState.loot_queue,
	}
	var legacy_file := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	assert(legacy_file != null, "legacy save fixture could not be written")
	legacy_file.store_string(JSON.stringify(legacy_payload))
	legacy_file.close()
	GameState.equipment.weapon = {}
	GameState.player_current_hp = 1
	assert(GameState.load_game(), "v3 save migration failed")
	assert(GameState.equipment.weapon.get("item_id", "") == "novice_sword", "v3 string equipment did not migrate to an instance")
	assert(GameState.equipment.weapon.enhancement.quality_level == 0, "v3 equipment migration produced invalid enhancement data")
	assert(GameState.pets.size() == 2 and GameState.research.technology_level == 10.0, "v3 save did not initialize pet and research defaults")
	assert(GameState.quest_states.spider_crisis.status == "available", "v3 save did not initialize quest defaults")
	assert(GameState.learned_skills.is_empty(), "v3 save did not initialize empty learned skills")
	assert(GameState.player_current_hp == GameState.get_player_stats().max_hp, "legacy save did not initialize full player HP")
	assert(GameState.current_map_id == "cassano_city", "obsolete spider cave save did not migrate to Cassano")

	assert(GameState.add_item("novice_sword", 2), "equipment instance setup failed")
	var sword_slots: Array[int] = []
	for index in GameState.inventory.size():
		if GameState.inventory[index].get("item_id", "") == "novice_sword":
			sword_slots.append(index)
	assert(sword_slots.size() == 2, "equipment instances were stacked during add")
	GameState.inventory[sword_slots[0]].enhancement.quality_level = 4
	GameState.inventory[sword_slots[1]].enhancement.quality_level = 7
	assert(GameState.move_item(sword_slots[0], sword_slots[1]), "equipment instance swap failed")
	assert(GameState.inventory[sword_slots[0]].quantity == 1 and GameState.inventory[sword_slots[1]].quantity == 1, "same equipment was stacked during drag")
	assert(GameState.inventory[sword_slots[0]].enhancement.quality_level == 7 and GameState.inventory[sword_slots[1]].enhancement.quality_level == 4, "equipment enhancement data was lost during drag")
	var plus_nine := GameState.create_item_entry("dungeon_plus9_sword")
	var plus_twelve := GameState.create_item_entry("dungeon_plus12_sword")
	assert(plus_nine.enhancement.quality_level == 1 and plus_nine.enhancement.magic_soul_level == 9, "dungeon +9 equipment preset is incorrect")
	assert(plus_twelve.enhancement.magic_soul_level == 12, "dungeon +12 equipment preset is incorrect")
	assert(GameState.add_item("rose_bouquet_999"), "999-rose bouquet fixture failed")
	var bouquet_slot := -1
	for index in GameState.inventory.size():
		if GameState.inventory[index].get("item_id", "") == "rose_bouquet_999":
			bouquet_slot = index
			break
	var roses_before_bundle := GameState.count_item("rose")
	assert(bouquet_slot >= 0 and GameState.use_inventory_item(bouquet_slot), "999-rose bouquet could not be unpacked")
	assert(GameState.count_item("rose") == roses_before_bundle + 999, "999-rose bouquet unpack quantity is incorrect")
	assert(GameState.add_item("lava_potion"), "lava potion fixture failed")
	var lava_slot := -1
	for index in GameState.inventory.size():
		if GameState.inventory[index].get("item_id", "") == "lava_potion":
			lava_slot = index
			break
	GameState.level = 10
	assert(lava_slot >= 0 and GameState.use_inventory_item(lava_slot), "lava potion could not be used")
	assert(GameState.level == 100 and GameState.count_item("lava_potion") == 0, "lava potion level effect is incorrect")

	for index in GameState.inventory.size():
		GameState.inventory[index] = {"item_id": "exp_potion", "quantity": 99}
	var full_snapshot: Array = GameState.inventory.duplicate(true)
	assert(not GameState.add_item("exp_potion", 1), "full inventory accepted an item")
	assert(GameState.inventory == full_snapshot, "failed add partially changed inventory")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	print("PASS inventory, pet/social/quest/skill instances, non-stackable drag, isolated v16 save, and v3 migration")
	get_tree().quit(0)


func _stack_count() -> int:
	var count := 0
	for item: Dictionary in GameState.inventory:
		if not item.is_empty():
			count += 1
	for item: Dictionary in GameState.warehouse:
		if not item.is_empty():
			count += 1
	return count
