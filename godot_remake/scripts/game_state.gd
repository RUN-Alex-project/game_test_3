extends Node

signal inventory_changed
signal currency_changed
signal progression_changed
signal equipment_changed
signal loot_changed
signal pets_changed
signal research_changed
signal social_changed
signal quests_changed
signal skills_changed
signal territory_changed
signal story_changed
signal time_changed

const PAGE_SIZE := 24
const INVENTORY_SIZE := 48
const WAREHOUSE_SIZE := 48
const DAY_TIME := 15
const SAVE_PATH := "user://savegame.json"
const ITEM_DATABASE_PATH := "res://data/items.json"
const EnhancementService = preload("res://scripts/enhancement_service.gd")
const PetService = preload("res://scripts/pet_service.gd")
const ProgressionService = preload("res://scripts/progression_service.gd")
const QuestService = preload("res://scripts/quest_service.gd")
const SkillService = preload("res://scripts/skill_service.gd")
const TerritoryService = preload("res://scripts/territory_service.gd")
const FINAL_CAMPAIGN_FLAG_BY_MONSTER := {
	"demon_assault":"assault_alive",
	"demon_guard":"guard_alive",
	"demon_mystery":"mystery_alive",
	"demon_totem":"totem_alive",
	"demon_commander":"commander_alive",
	"demon_energy":"energy_alive",
}
const FINAL_CAMPAIGN_SUPPORT_MONSTERS := ["demon_assault", "demon_guard", "demon_mystery", "demon_totem"]
const FUWA_NAMES := ["贝贝", "欢欢", "迎迎", "妮妮", "晶晶"]
const FUWA_REWARD_ITEM_IDS := ["rose_bouquet_999", "plasma_potion", "soul_king"]
const FUWA_MESSENGER_MAP_BY_ROLL := ["thunder_continent", "", "palace", "desert", "dream_swamp", "ice_palace", "avit_island", "volcano", "abyss_maze"]
const LOTTERY_COST := 28
const LOTTERY_EQUIPMENT_IDS := ["lottery_weapon", "lottery_helmet", "lottery_necklace", "lottery_armor", "lottery_bracelet", "lottery_boots"]
const MAP_LEVEL_REQUIREMENTS := {
	"thunder_continent":10,
	"thunder_mine":10,
	"desert":20,
	"dream_swamp":30,
	"ice_palace":50,
	"ice_border":50,
	"demon_camp":50,
	"demon_left":50,
	"demon_right":50,
	"demon_banner":50,
	"energy_tower":50,
	"avit_island":70,
	"volcano":90,
	"abyss_maze":100,
}

var item_database: Dictionary = {}
var inventory: Array[Dictionary] = []
var warehouse: Array[Dictionary] = []
var gold: int = 99_999_999_999
var magic_stones: int = 99_999_999_999
var level: int = 1
var experience: int = 0
var military_merit: int = 0
var nobility_merit: int = 0
var affection: int = 0
var current_day: int = 1
var current_time_used: int = 0
var completed_daily_tasks: Dictionary = {}
var current_map_id: String = "cassano_city"
var equipment: Dictionary = {"weapon": {}, "helmet": {}, "necklace": {}, "armor": {}, "bracelet": {}, "boots": {}}
var base_stats: Dictionary = {"max_hp": 550, "attack": 60, "defense": 30, "luck": 100}
var player_current_hp: int = 550
var player_current_stamina: int = 110
var loot_queue: Array[String] = []
var _next_claim_operation_id: int = 1  # v1.37 整改02：领取操作稳定身份（每次 claim_loot 递增）
var enhancement := EnhancementService.new()
var pet_service := PetService.new()
var progression_service := ProgressionService.new()
var quest_service := QuestService.new()
var skill_service := SkillService.new()
var territory_service := TerritoryService.new()
var save_path: String = SAVE_PATH
var pets: Array[Dictionary] = []
var next_pet_instance_id: int = 1
var research: Dictionary = {}
var quest_states: Dictionary = {}
var unlocked_maps: Dictionary = {"dungeon_floor_2":false, "dungeon_floor_3":false}
var learned_skills: Dictionary = {}
var last_princess_gift_day: int = 0
var last_princess_chat_day: int = 0
var last_military_salary_day: int = 0
var last_pk_race_day: int = 0
var pk_race_active: bool = false
var war_soul_maze_active: bool = false
var war_soul_guardian_revealed: bool = false
var owned_territory: String = ""
var last_territory_challenge_day: int = 0
var last_territory_reward_day: int = 0
var pending_territory_challenge: String = ""
var story_flags: Dictionary = {
	"king_rescued": false,
	"princess_friend_gift_available": false,
	"maid_year_pig_available": true,
	"maid_combat_stone_available": true,
	"war_soul_quest_available": false,
	"war_soul_secret_unlocked": false,
	"game_won": false,
}
var fuwa_event: Dictionary = {
	"found_count": 0,
	"round_active": false,
	"beast_defeated": false,
	"completion_claimed": false,
	"messenger_map": "thunder_continent",
}
var demon_campaign: Dictionary = {
	"assault_alive": true,
	"guard_alive": true,
	"mystery_alive": true,
	"totem_alive": true,
	"commander_alive": true,
	"energy_alive": true,
}
var relationship_rng := RandomNumberGenerator.new()
var campaign_rng := RandomNumberGenerator.new()
var mining_rng := RandomNumberGenerator.new()
var fuwa_rng := RandomNumberGenerator.new()
var lottery_rng := RandomNumberGenerator.new()


func _ready() -> void:
	relationship_rng.randomize()
	campaign_rng.randomize()
	mining_rng.randomize()
	fuwa_rng.randomize()
	lottery_rng.randomize()
	_load_item_database()
	_initialize_inventory()
	_initialize_pets()
	quest_states = quest_service.default_states()


func _load_item_database() -> void:
	var file := FileAccess.open(ITEM_DATABASE_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取物品数据库：%s" % ITEM_DATABASE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("物品数据库格式错误")
		return
	for definition: Dictionary in parsed:
		item_database[definition.get("id", "")] = definition


func _initialize_inventory() -> void:
	inventory.clear()
	for index in INVENTORY_SIZE:
		inventory.append({})
	warehouse.clear()
	for index in WAREHOUSE_SIZE:
		warehouse.append({})
	_set_starting_item(0, "skill_red", 1)
	_set_starting_item(1, "exp_potion", 10)
	_set_starting_item(2, "rose", 10)
	_set_starting_item(4, "skill_green", 1)
	_set_starting_item(5, "exp_ball", 10)
	_set_starting_item(6, "novice_sword", 1)
	_set_starting_item(7, "novice_armor", 1)
	_set_starting_item(8, "fruit", 10)


func _initialize_pets() -> void:
	# 与 _default_pets_dto 同源（load 缺失 pets 时也走同一默认构造）
	var default_dto := _default_pets_dto()
	pets = default_dto.pets
	next_pet_instance_id = int(default_dto.next_pet_instance_id)
	research = default_dto.research


## 纯构造：默认幻兽组（不读写任何全局状态，load/save 共用）
func _default_pets_dto() -> Dictionary:
	var result: Array[Dictionary] = []
	var next_id := 1
	for template_id: String in ["attack_defense_light", "attack_defense_heavy"]:
		var pet := pet_service.create_pet(template_id, next_id)
		if not pet.is_empty():
			pet.deployed = true
			pet.combined = true
			result.append(pet)
			next_id += 1
	return {"pets": result, "next_pet_instance_id": next_id, "research": pet_service.default_research_state()}


func _add_pet_instance(template_id: String, quality_score: float = -1.0) -> bool:
	if pets.size() >= int(pet_service.config.get("inventory_capacity", 100)):
		return false
	var pet := pet_service.create_pet(template_id, next_pet_instance_id, quality_score)
	if pet.is_empty():
		return false
	next_pet_instance_id += 1
	pets.append(pet)
	return true


func _set_starting_item(slot_index: int, item_id: String, quantity: int) -> void:
	inventory[slot_index] = create_item_entry(item_id, quantity)


func create_item_entry(item_id: String, quantity: int = 1) -> Dictionary:
	var entry := {"item_id": item_id, "quantity": quantity}
	if get_item_definition(item_id).get("category", "") == "equipment":
		entry["quantity"] = 1
		entry["enhancement"] = _create_equipment_enhancement(item_id)
	return entry


func _create_equipment_enhancement(item_id: String) -> Dictionary:
	var instance := enhancement.create_equipment_instance(item_id)
	var definition := get_item_definition(item_id)
	instance.quality_level = maxi(0, int(definition.get("preset_quality_level", 0)))
	instance.magic_soul_level = maxi(0, int(definition.get("preset_magic_soul_level", 0)))
	instance.socket_count = maxi(0, int(definition.get("preset_socket_count", 0)))
	return instance


func _insert_lottery_equipment(quality_level: int, magic_soul_level: int, socket_count: int, forced_equipment_choice: int = -1) -> Dictionary:
	var empty_slot := -1
	for index in inventory.size():
		if inventory[index].is_empty():
			empty_slot = index
			break
	if empty_slot < 0:
		return {"success":false, "reason":"inventory_full"}
	var equipment_choice := clampi(forced_equipment_choice, 0, LOTTERY_EQUIPMENT_IDS.size() - 1) if forced_equipment_choice >= 0 else lottery_rng.randi_range(0, LOTTERY_EQUIPMENT_IDS.size() - 1)
	var item_id: String = str(LOTTERY_EQUIPMENT_IDS[equipment_choice])
	var entry := create_item_entry(item_id)
	entry.enhancement.quality_level = quality_level
	entry.enhancement.magic_soul_level = magic_soul_level
	entry.enhancement.socket_count = socket_count
	inventory[empty_slot] = entry
	inventory_changed.emit()
	return {"success":true, "reward_kind":"item", "item_id":item_id, "equipment_choice":equipment_choice, "quality_level":quality_level, "magic_soul_level":magic_soul_level, "socket_count":socket_count}


func get_container(container_name: String) -> Array[Dictionary]:
	return warehouse if container_name == "warehouse" else inventory


func get_slot(slot_index: int, container_name: String = "inventory") -> Dictionary:
	var container := get_container(container_name)
	if slot_index < 0 or slot_index >= container.size():
		return {}
	return container[slot_index]


func get_item_definition(item_id: String) -> Dictionary:
	var loot_equipment := _parse_loot_equipment_token(item_id)
	if not loot_equipment.is_empty():
		var definition: Dictionary = item_database.get(str(loot_equipment.item_id), {}).duplicate(true)
		if definition.is_empty():
			return {}
		definition.name = "%d级%s" % [int(loot_equipment.item_level), str(definition.get("name", "装备"))]
		definition.description = "%s\n野外掉落：品质+%d，魔魂+%d，洞数%d。" % [str(definition.get("description", "")), int(loot_equipment.quality_level), int(loot_equipment.magic_soul_level), int(loot_equipment.socket_count)]
		return definition
	return item_database.get(item_id, {})


func _parse_loot_equipment_token(token: String) -> Dictionary:
	if not token.begins_with("loot_equipment|"):
		return {}
	var parts := token.split("|")
	if parts.size() != 6 or not item_database.has(parts[1]):
		return {}
	if str(item_database[parts[1]].get("category", "")) != "equipment":
		return {}
	return {
		"item_id":parts[1],
		"item_level":clampi(int(parts[2]), 1, 125),
		"quality_level":clampi(int(parts[3]), 0, 4),
		"magic_soul_level":clampi(int(parts[4]), 0, 12),
		"socket_count":clampi(int(parts[5]), 0, 2),
	}


func move_item(source_index: int, target_index: int) -> bool:
	return move_item_between("inventory", source_index, "inventory", target_index)


func move_item_between(source_name: String, source_index: int, target_name: String, target_index: int) -> bool:
	var source_container := get_container(source_name)
	var target_container := get_container(target_name)
	if source_name == target_name and source_index == target_index:
		return false
	if source_index < 0 or source_index >= source_container.size():
		return false
	if target_index < 0 or target_index >= target_container.size():
		return false
	if source_container[source_index].is_empty():
		return false

	# Dragging never mutates the source. A valid drop commits both sides together.
	var source_item: Dictionary = source_container[source_index]
	var target_item: Dictionary = target_container[target_index]
	var source_definition: Dictionary = get_item_definition(str(source_item.get("item_id", "")))
	var can_stack: bool = str(source_definition.get("category", "")) not in ["equipment", "ore"]
	if can_stack and not target_item.is_empty() and target_item.get("item_id") == source_item.get("item_id"):
		var combined := int(source_item.get("quantity", 1)) + int(target_item.get("quantity", 1))
		if combined <= 99:
			target_item["quantity"] = combined
			source_container[source_index] = {}
		else:
			target_item["quantity"] = 99
			source_item["quantity"] = combined - 99
	else:
		source_container[source_index] = target_item
		target_container[target_index] = source_item
	inventory_changed.emit()
	return true


func add_item(item_id: String, quantity: int = 1) -> bool:
	if not item_database.has(item_id) or quantity <= 0:
		return false
	var working: Array[Dictionary] = []
	for item: Dictionary in inventory:
		working.append(item.duplicate(true))
	if get_item_definition(item_id).get("category", "") == "equipment":
		var empty_slots: Array[int] = []
		for index in working.size():
			if working[index].is_empty():
				empty_slots.append(index)
		if empty_slots.size() < quantity:
			return false
		for item_index in quantity:
			working[empty_slots[item_index]] = create_item_entry(item_id)
		inventory = working
		inventory_changed.emit()
		return true
	var remaining := quantity
	for item: Dictionary in working:
		if item.get("item_id", "") == item_id and int(item.get("quantity", 1)) < 99:
			var accepted := mini(99 - int(item.get("quantity", 1)), remaining)
			item["quantity"] = int(item.get("quantity", 1)) + accepted
			remaining -= accepted
			if remaining == 0:
				inventory = working
				inventory_changed.emit()
				return true
	for index in working.size():
		if working[index].is_empty():
			var accepted := mini(99, remaining)
			working[index] = {"item_id": item_id, "quantity": accepted}
			remaining -= accepted
			if remaining == 0:
				inventory = working
				inventory_changed.emit()
				return true
	return false


func add_ore_instance(item_id: String, quality: int) -> bool:
	if str(get_item_definition(item_id).get("category", "")) != "ore":
		return false
	for index in inventory.size():
		if inventory[index].is_empty():
			inventory[index] = {"item_id":item_id, "quantity":1, "ore_quality":clampi(quality, 1, 10)}
			inventory_changed.emit()
			return true
	return false


func mine_ore(forced_quality: int = -1, forced_ore_roll: int = -1) -> Dictionary:
	var quality := clampi(forced_quality, 1, 10) if forced_quality >= 0 else mining_rng.randi_range(1, 10)
	var ore_roll := clampi(forced_ore_roll, 0, 199) if forced_ore_roll >= 0 else mining_rng.randi_range(0, 199)
	var item_id := "gold_ore" if ore_roll > 100 else "silver_ore"
	var added := add_ore_instance(item_id, quality)
	var time_result := spend_time(1)
	return {
		"success":added,
		"reason":"" if added else "inventory_full",
		"item_id":item_id,
		"quality":quality,
		"ore_roll":ore_roll,
		"time_remaining":remaining_time(),
		"day_advanced":bool(time_result.get("day_advanced", false)),
	}


func remaining_time() -> int:
	return DAY_TIME - current_time_used


func spend_time(amount: int) -> Dictionary:
	var safe_amount := maxi(0, amount)
	var day_results: Array[Dictionary] = []
	current_time_used += safe_amount
	while current_time_used >= DAY_TIME:
		current_time_used -= DAY_TIME
		var remainder := current_time_used
		day_results.append(advance_day())
		current_time_used = remainder
	time_changed.emit()
	return {
		"spent":safe_amount,
		"day_advanced":not day_results.is_empty(),
		"days_advanced":day_results.size(),
		"remaining":remaining_time(),
		"day_results":day_results,
	}


func ore_sale_value(item: Dictionary, currency: String) -> int:
	var item_id := str(item.get("item_id", ""))
	if str(get_item_definition(item_id).get("category", "")) != "ore":
		return 0
	var quality := clampi(int(item.get("ore_quality", 1)), 1, 10)
	if item_id == "silver_ore" and currency == "gold":
		return 500000 if quality == 10 else quality * 10000
	if item_id == "gold_ore" and currency == "magic_stones":
		return 280 if quality == 10 else quality * 10
	return 0


func sell_inventory_ore(slot_index: int, currency: String) -> Dictionary:
	if slot_index < 0 or slot_index >= inventory.size() or inventory[slot_index].is_empty():
		return {"success":false, "reason":"missing_item"}
	var item := inventory[slot_index].duplicate(true)
	var amount := ore_sale_value(item, currency)
	if amount <= 0:
		return {"success":false, "reason":"wrong_merchant"}
	const MAX_SIGNED_INT := 9_223_372_036_854_775_807
	var current_value := magic_stones if currency == "magic_stones" else gold
	if current_value > MAX_SIGNED_INT - amount:
		return {"success":false, "reason":"currency_overflow"}
	inventory[slot_index] = {}
	if currency == "magic_stones":
		magic_stones += amount
	else:
		gold += amount
	inventory_changed.emit()
	currency_changed.emit()
	return {"success":true, "item":item, "amount":amount, "currency":currency}


func buy_item(item_id: String, currency: String = "gold") -> bool:
	var definition := get_item_definition(item_id)
	if definition.is_empty():
		return false
	var price_key := "price_magic_stones" if currency == "magic_stones" else "price_gold"
	var price := int(definition.get(price_key, -1))
	if price < 0:
		return false
	if currency == "magic_stones":
		if magic_stones < price or not add_item(item_id):
			return false
		magic_stones -= price
	else:
		if gold < price or not add_item(item_id):
			return false
		gold -= price
	currency_changed.emit()
	return true


func claim_merchant_sale(currency: String) -> Dictionary:
	const SALE_GRANT := 99_999_999_999
	const MAX_SIGNED_INT := 9_223_372_036_854_775_807
	if currency == "magic_stones":
		if magic_stones > MAX_SIGNED_INT - SALE_GRANT:
			return {"success":false, "reason":"currency_overflow"}
		magic_stones += SALE_GRANT
	else:
		if gold > MAX_SIGNED_INT - SALE_GRANT:
			return {"success":false, "reason":"currency_overflow"}
		gold += SALE_GRANT
	currency_changed.emit()
	return {"success":true, "currency":currency, "amount":SALE_GRANT}


func count_item(item_id: String) -> int:
	var total := 0
	for item: Dictionary in inventory:
		if item.get("item_id", "") == item_id:
			total += int(item.get("quantity", 1))
	return total


func consume_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0 or count_item(item_id) < quantity:
		return false
	var working: Array[Dictionary] = []
	for item: Dictionary in inventory:
		working.append(item.duplicate(true))
	var remaining := quantity
	for index in working.size():
		if working[index].get("item_id", "") != item_id:
			continue
		var take := mini(remaining, int(working[index].get("quantity", 1)))
		working[index]["quantity"] = int(working[index].get("quantity", 1)) - take
		remaining -= take
		if int(working[index].quantity) <= 0:
			working[index] = {}
		if remaining == 0:
			break
	inventory = working
	inventory_changed.emit()
	return true


func exchange_first_inventory_equipment_for_exp_balls() -> Dictionary:
	for slot_index in inventory.size():
		var entry: Dictionary = inventory[slot_index]
		if entry.is_empty():
			continue
		var item_id := str(entry.get("item_id", ""))
		var definition := get_item_definition(item_id)
		if str(definition.get("category", "")) != "equipment":
			continue
		var instance: Dictionary = entry.get("enhancement", _create_equipment_enhancement(item_id))
		var quality := clampi(int(instance.get("quality_level", 0)), 0, 4)
		var sockets := clampi(int(instance.get("socket_count", 0)), 0, 2)
		var magic_soul := maxi(0, int(instance.get("magic_soul_level", 0)))
		var exp_balls := quality
		if sockets == 1:
			exp_balls += 2
		elif sockets >= 2:
			exp_balls += 5
		if magic_soul >= 12:
			exp_balls += 2
		elif magic_soul >= 9:
			exp_balls += 1
		if exp_balls <= 0:
			continue
		var snapshot: Array[Dictionary] = []
		for item: Dictionary in inventory:
			snapshot.append(item.duplicate(true))
		inventory[slot_index] = {}
		if not add_item("exp_ball", exp_balls):
			inventory = snapshot
			inventory_changed.emit()
			return {"success":false, "reason":"inventory_full"}
		return {"success":true, "item_id":item_id, "item_name":str(definition.get("name", item_id)), "exp_balls":exp_balls}
	return {"success":false, "reason":"no_eligible_equipment"}


func synthesize_stone(recipe_id: String) -> Dictionary:
	var recipes := {
		"soul_king":"soul_crystal",
		"magic_soul_heart":"magic_soul_crystal",
		"illusion_heart":"illusion_crystal",
		"advanced_exp_stone":"intermediate_exp_stone",
		"advanced_combat_stone":"intermediate_combat_stone",
	}
	var material_id := str(recipes.get(recipe_id, ""))
	if material_id.is_empty() or count_item(material_id) < 20:
		return {"success":false, "reason":"materials", "material_id":material_id}
	var snapshot: Array[Dictionary] = []
	for item: Dictionary in inventory:
		snapshot.append(item.duplicate(true))
	if not consume_item(material_id, 20) or not add_item(recipe_id, 1):
		inventory = snapshot
		inventory_changed.emit()
		return {"success":false, "reason":"inventory_full", "material_id":material_id}
	return {"success":true, "item_id":recipe_id, "material_id":material_id}


func use_inventory_item(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= inventory.size() or inventory[slot_index].is_empty():
		return false
	var item_id := str(inventory[slot_index].get("item_id", ""))
	var definition := get_item_definition(item_id)
	var effect := str(definition.get("use_effect", ""))
	if effect.is_empty():
		return false
	if effect == "skill_book":
		return learn_skill_from_item(item_id).get("success", false)
	if effect == "rose_bundle":
		var amount := int(definition.get("amount", 0))
		if amount <= 0:
			return false
		var working_inventory: Array[Dictionary] = []
		for item: Dictionary in inventory:
			working_inventory.append(item.duplicate(true))
		working_inventory[slot_index] = {}
		var old_inventory := inventory
		inventory = working_inventory
		if not add_item("rose", amount):
			inventory = old_inventory
			inventory_changed.emit()
			return false
		return true
	if effect == "full_heal":
		var maximum_hp := int(get_player_stats().get("max_hp", 1))
		if player_current_hp >= maximum_hp or not consume_item(item_id, 1):
			return false
		player_current_hp = maximum_hp
		AudioService.play("potion")
		progression_changed.emit()
		return true
	if effect == "level_to":
		var target_level := int(definition.get("amount", level))
		if level >= target_level or not consume_item(item_id, 1):
			return false
		while level < target_level:
			level += 1
			base_stats.max_hp = int(base_stats.max_hp) + 20
			base_stats.attack = int(base_stats.attack) + 5
			base_stats.defense = int(base_stats.defense) + 3
		experience = 0
		AudioService.play("potion")
		progression_changed.emit()
		return true
	if effect == "luck_to":
		var target_luck := int(definition.get("amount", 0))
		if target_luck <= int(base_stats.get("luck", 0)) or not consume_item(item_id, 1):
			return false
		base_stats.luck = target_luck
		AudioService.play("potion")
		progression_changed.emit()
		return true
	return false


func learn_skill_from_item(item_id: String) -> Dictionary:
	if count_item(item_id) < 1:
		return {"success":false, "reason":"missing_book"}
	var result := skill_service.learn_result(learned_skills, item_id)
	if not result.get("success", false):
		return result
	if not consume_item(item_id, 1):
		return {"success":false, "reason":"missing_book"}
	learned_skills = result.learned
	AudioService.play("learn_skill")
	skills_changed.emit()
	progression_changed.emit()
	return result


func enhance_equipped(equipment_slot: String, operation: String, roll: float = 0.0) -> Dictionary:
	if not equipment.has(equipment_slot) or equipment[equipment_slot].is_empty():
		return {"success": false, "reason": "empty_slot"}
	var material_id := enhancement.material_for(operation)
	if material_id.is_empty() or count_item(material_id) < 1:
		return {"success": false, "reason": "missing_material"}
	var item: Dictionary = equipment[equipment_slot].duplicate(true)
	var instance: Dictionary = item.get("enhancement", enhancement.create_equipment_instance(str(item.get("item_id", ""))))
	if operation == "war_soul" and instance.get("war_soul_active", false):
		return {"success": false, "reason": "already_active"}
	if not consume_item(material_id):
		return {"success": false, "reason": "missing_material"}
	var result: Dictionary
	match operation:
		"quality": result = enhancement.refine_quality(instance)
		"magic_soul": result = enhancement.upgrade_magic_soul(instance)
		"war_soul": result = enhancement.activate_war_soul(instance, roll)
		_: return {"success": false, "reason": "unknown_operation"}
	item["enhancement"] = result.equipment
	equipment[equipment_slot] = item
	equipment_changed.emit()
	AudioService.play("refine_success" if result.get("success", false) else "refine_fail")
	return result


func increase_equipped_soul(equipment_slot: String, soul: String) -> bool:
	if not equipment.has(equipment_slot) or equipment[equipment_slot].is_empty():
		return false
	if soul != "heaven" and soul != "earth":
		return false
	var item: Dictionary = equipment[equipment_slot].duplicate(true)
	var instance: Dictionary = item.get("enhancement", enhancement.create_equipment_instance(str(item.get("item_id", ""))))
	if not bool(instance.get("war_soul_active", false)):
		return false
	var field_name := "heaven_soul_level" if soul == "heaven" else "earth_soul_level"
	if int(instance.get(field_name, 0)) >= int(enhancement.config.get("soul_level_cap", 5)):
		return false
	var material_id := enhancement.material_for("%s_soul" % soul)
	if material_id.is_empty() or not consume_item(material_id):
		return false
	var heaven_level := int(instance.get("heaven_soul_level", 0)) + (1 if soul == "heaven" else 0)
	var earth_level := int(instance.get("earth_soul_level", 0)) + (1 if soul == "earth" else 0)
	item["enhancement"] = enhancement.set_soul_levels(instance, heaven_level, earth_level)
	equipment[equipment_slot] = item
	equipment_changed.emit()
	return true


func get_pet_index(instance_id: int) -> int:
	for index in pets.size():
		if int(pets[index].get("instance_id", 0)) == instance_id:
			return index
	return -1


func rename_pet(instance_id: int, new_name: String) -> Dictionary:
	var pet_index := get_pet_index(instance_id)
	if pet_index < 0:
		return {"success":false, "reason":"missing_pet"}
	var cleaned_name := new_name.strip_edges()
	if cleaned_name.is_empty():
		return {"success":false, "reason":"empty_name"}
	cleaned_name = cleaned_name.left(6)
	pets[pet_index].custom_name = cleaned_name
	pets_changed.emit()
	return {"success":true, "name":cleaned_name}


func discard_pet(instance_id: int) -> Dictionary:
	var pet_index := get_pet_index(instance_id)
	if pet_index < 0:
		return {"success":false, "reason":"missing_pet"}
	if bool(pets[pet_index].get("deployed", false)):
		return {"success":false, "reason":"deployed"}
	pets.remove_at(pet_index)
	pets_changed.emit()
	return {"success":true}


func set_pet_deployed(instance_id: int, deployed: bool) -> bool:
	var pet_index := get_pet_index(instance_id)
	if pet_index < 0:
		return false
	if bool(pets[pet_index].get("deployed", false)) == deployed:
		return true
	if deployed:
		var deployed_count := 0
		for pet: Dictionary in pets:
			if bool(pet.get("deployed", false)):
				deployed_count += 1
		if deployed_count >= int(pet_service.config.get("deployed_capacity", 2)):
			return false
	pets[pet_index].deployed = deployed
	if not deployed:
		pets[pet_index].combined = false
	pets_changed.emit()
	AudioService.play("summon_pet")
	return true


func set_pet_combined(instance_id: int, combined: bool) -> bool:
	var pet_index := get_pet_index(instance_id)
	if pet_index < 0 or not bool(pets[pet_index].get("deployed", false)):
		return false
	if bool(pets[pet_index].get("combined", false)) == combined:
		return true
	pets[pet_index].combined = combined
	pets_changed.emit()
	return true


func get_player_max_stamina() -> int:
	# SWF sprite932: base_tl=100, cz_tl=10 and mtl=base_tl+cz_tl*dj.
	return 100 + 10 * maxi(1, level)


func skill_stamina_cost(skill_id: String) -> int:
	var rank := maxi(0, int(learned_skills.get(skill_id, 0)))
	match skill_id:
		"flying_slash":
			return 5 if rank >= 2 else 0
		"star_sword":
			return 20 if rank >= 2 else 10
		_:
			return 0


func try_use_skill_stamina(skill_id: String) -> Dictionary:
	var cost := skill_stamina_cost(skill_id)
	if player_current_stamina < cost:
		return {"success":false, "cost":cost, "remaining":player_current_stamina}
	player_current_stamina -= cost
	if cost > 0:
		progression_changed.emit()
	return {"success":true, "cost":cost, "remaining":player_current_stamina}


func train_pet_with_exp_ball(instance_id: int) -> bool:
	var pet_index := get_pet_index(instance_id)
	if pet_index < 0 or count_item("exp_ball") < 1:
		return false
	var result: Dictionary = pet_service.grant_experience(pets[pet_index], 27000, level)
	if result.pet == pets[pet_index]:
		return false
	if not consume_item("exp_ball"):
		return false
	pets[pet_index] = result.pet
	pets_changed.emit()
	return true


func fuse_pets(main_instance_id: int, secondary_instance_id: int) -> Dictionary:
	var main_index := get_pet_index(main_instance_id)
	var secondary_index := get_pet_index(secondary_instance_id)
	if main_index < 0 or secondary_index < 0:
		return {"success":false, "reason":"missing_pet"}
	if count_item("exp_ball") < 1:
		return {"success":false, "reason":"missing_exp_ball"}
	var result: Dictionary = pet_service.fuse(pets[main_index], pets[secondary_index])
	if not result.get("success", false):
		return result
	if not consume_item("exp_ball"):
		return {"success":false, "reason":"missing_exp_ball"}
	var main_id := int(pets[main_index].instance_id)
	var secondary_id := int(pets[secondary_index].instance_id)
	pets.remove_at(secondary_index)
	main_index = get_pet_index(main_id)
	var fused_pet: Dictionary = result.pet
	fused_pet.instance_id = main_id
	pets[main_index] = fused_pet
	pets_changed.emit()
	return {"success":true, "pet":fused_pet, "consumed_instance_id":secondary_id}


func fund_pet_research() -> bool:
	var research_config: Dictionary = pet_service.config.get("research", {})
	var cap := float(research_config.get("technology_level_cap", 300.0))
	if float(research.get("technology_level", 0.0)) >= cap:
		return false
	var cost := int(research_config.get("funding_magic_stones_per_level", 10000))
	if magic_stones < cost:
		return false
	magic_stones -= cost
	research = pet_service.fund_research(research, 1.0)
	currency_changed.emit()
	research_changed.emit()
	return true


func advance_pet_research_week() -> bool:
	var previous_level := float(research.get("technology_level", 0.0))
	research = pet_service.advance_week(research)
	research_changed.emit()
	return not is_equal_approx(previous_level, float(research.technology_level))


func advance_research_production(days: int = 1) -> int:
	var previous_stock := int(research.get("stock", 0))
	research = pet_service.produce(research, days)
	research_changed.emit()
	return int(research.stock) - previous_stock


func complete_research_production_task() -> Dictionary:
	var cost := pet_service.production_task_cost(research)
	if count_item("soul_king") < cost:
		return {"success":false, "reason":"missing_soul_king", "required":cost}
	var result: Dictionary = pet_service.complete_production_task(research)
	if not result.get("success", false):
		return result
	if not consume_item("soul_king", cost):
		return {"success":false, "reason":"missing_soul_king", "required":cost}
	research = result.state
	_add_player_experience(int(result.get("experience_reward", 0)))
	research_changed.emit()
	progression_changed.emit()
	return result


func buy_research_pet() -> Dictionary:
	if int(research.get("stock", 0)) <= 0:
		return {"success":false, "reason":"no_stock"}
	if pets.size() >= int(pet_service.config.get("inventory_capacity", 100)):
		return {"success":false, "reason":"pet_inventory_full"}
	var price := pet_service.research_pet_price(research)
	if magic_stones < price:
		return {"success":false, "reason":"not_enough_magic_stones", "price":price}
	var quality := pet_service.research_pet_quality(research)
	if not _add_pet_instance("strange_beast", quality):
		return {"success":false, "reason":"pet_inventory_full"}
	magic_stones -= price
	research.stock = int(research.stock) - 1
	currency_changed.emit()
	pets_changed.emit()
	research_changed.emit()
	return {"success":true, "pet":pets.back(), "price":price}


func get_military_rank() -> Dictionary:
	return progression_service.tier_for("military", military_merit)


func get_nobility_rank() -> Dictionary:
	return progression_service.tier_for("nobility", nobility_merit)


func get_affection_rank() -> Dictionary:
	return progression_service.tier_for("affection", affection)


func donate_gold_for_nobility(requested_gold: int) -> Dictionary:
	var result := progression_service.donation_result(gold, requested_gold)
	var gold_cost := int(result.get("gold_cost", 0))
	var merit_gain := int(result.get("nobility_merit", 0))
	if gold_cost <= 0 or merit_gain <= 0:
		return {"success":false, "reason":"insufficient_gold"}
	gold -= gold_cost
	nobility_merit += merit_gain
	currency_changed.emit()
	progression_changed.emit()
	social_changed.emit()
	return {"success":true, "gold_cost":gold_cost, "nobility_merit":merit_gain}


func give_roses(rose_count: int) -> Dictionary:
	var affection_gain := progression_service.rose_affection(rose_count)
	if affection_gain <= 0:
		return {"success":false, "reason":"invalid_bundle"}
	if not consume_item("rose", rose_count):
		return {"success":false, "reason":"missing_roses", "required":rose_count}
	var previous_relationship_level := int(get_affection_rank().get("level", 0))
	affection += affection_gain
	var skill_changed := _refresh_relationship_skills()
	_refresh_princess_friend_gift(previous_relationship_level)
	AudioService.play("send_flower")
	progression_changed.emit()
	social_changed.emit()
	if skill_changed:
		skills_changed.emit()
	return {"success":true, "affection":affection_gain, "love_power_rank":int(learned_skills.get("love_power", 0))}


func _refresh_princess_friend_gift(previous_relationship_level: int) -> void:
	var current_relationship_level := int(get_affection_rank().get("level", 0))
	if previous_relationship_level < 4 and current_relationship_level >= 4:
		story_flags["princess_friend_gift_available"] = true
		story_changed.emit()


func chat_with_princess() -> Dictionary:
	if last_princess_chat_day == current_day:
		return {"success":false, "reason":"already_chatted"}
	var relationship_level := int(get_affection_rank().get("level", 0))
	var pet_template_id := ""
	var pet_quality := -1.0
	match relationship_level:
		2:
			pet_template_id = "attack_defense_light"
			pet_quality = 100.0
		3:
			pet_template_id = "strange_beast"
			pet_quality = 0.0
		4:
			pet_template_id = "strange_beast"
			pet_quality = 1200.0
		5, 6:
			pet_template_id = "strange_beast"
			pet_quality = 1900.0
	if not pet_template_id.is_empty() and pets.size() >= int(pet_service.config.get("inventory_capacity", 100)):
		return {"success":false, "reason":"pet_inventory_full"}
	if not pet_template_id.is_empty() and not _add_pet_instance(pet_template_id, pet_quality):
		return {"success":false, "reason":"pet_inventory_full"}
	var previous_relationship_level := relationship_level
	affection += 1
	last_princess_chat_day = current_day
	var skill_changed := _refresh_relationship_skills()
	_refresh_princess_friend_gift(previous_relationship_level)
	progression_changed.emit()
	social_changed.emit()
	if not pet_template_id.is_empty():
		pets_changed.emit()
	if skill_changed:
		skills_changed.emit()
	return {
		"success":true,
		"affection":1,
		"relationship_level":relationship_level,
		"pet_template_id":pet_template_id,
		"pet_quality":pet_quality,
	}


func claim_princess_friend_gift() -> Dictionary:
	if int(get_affection_rank().get("level", 0)) < 4:
		return {"success":false, "reason":"relationship_too_low"}
	if not bool(story_flags.get("princess_friend_gift_available", false)):
		return {"success":false, "reason":"already_claimed"}
	if not _add_pet_instance("year_pig", 1900.0):
		return {"success":false, "reason":"pet_inventory_full"}
	story_flags["princess_friend_gift_available"] = false
	pets_changed.emit()
	story_changed.emit()
	return {"success":true, "pet_template_id":"year_pig", "pet":pets.back()}


func buy_maid_year_pig() -> Dictionary:
	const PRICE := 5888
	if not bool(story_flags.get("maid_year_pig_available", true)):
		return {"success":false, "reason":"sold_out", "price":PRICE}
	if magic_stones < PRICE:
		return {"success":false, "reason":"not_enough_magic_stones", "price":PRICE}
	if not _add_pet_instance("year_pig", 1900.0):
		return {"success":false, "reason":"pet_inventory_full", "price":PRICE}
	magic_stones -= PRICE
	story_flags["maid_year_pig_available"] = false
	currency_changed.emit()
	pets_changed.emit()
	story_changed.emit()
	return {"success":true, "price":PRICE, "pet_template_id":"year_pig", "pet":pets.back()}


func buy_maid_combat_stone() -> Dictionary:
	const PRICE := 2800
	if not bool(story_flags.get("maid_combat_stone_available", true)):
		return {"success":false, "reason":"sold_out", "price":PRICE}
	if magic_stones < PRICE:
		return {"success":false, "reason":"not_enough_magic_stones", "price":PRICE}
	if not add_item("advanced_combat_stone"):
		return {"success":false, "reason":"inventory_full", "price":PRICE}
	magic_stones -= PRICE
	story_flags["maid_combat_stone_available"] = false
	currency_changed.emit()
	story_changed.emit()
	return {"success":true, "price":PRICE, "item_id":"advanced_combat_stone"}


func open_lottery_chest(forced_roll: int = -1, forced_choice: int = -1, forced_equipment_choice: int = -1, forced_magic_soul: int = -1) -> Dictionary:
	if magic_stones < LOTTERY_COST:
		return {"success":false, "reason":"not_enough_magic_stones", "cost":LOTTERY_COST}
	magic_stones -= LOTTERY_COST
	currency_changed.emit()
	var time_result := spend_time(2)
	var roll := clampi(forced_roll, 0, 999) if forced_roll >= 0 else lottery_rng.randi_range(0, 999)
	var tier := 4
	var choice_count := 4
	if roll < 20:
		tier = 1
		choice_count = 6
	elif roll < 70:
		tier = 2
		choice_count = 7
	elif roll < 450:
		tier = 3
		choice_count = 5
	var choice := clampi(forced_choice, 0, choice_count - 1) if forced_choice >= 0 else lottery_rng.randi_range(0, choice_count - 1)
	var reward := {"success":true, "reward_kind":"item", "item_id":"", "tier":tier, "roll":roll, "choice":choice}
	match tier:
		1:
			match choice:
				0: reward = _lottery_pet_reward("lulu_pet")
				1: reward = _lottery_item_reward("enhanced_moon_box")
				2: reward = _lottery_item_reward("plasma_potion")
				3: reward = _lottery_item_reward("advanced_fighting_spirit")
				4: reward = _lottery_item_reward("rose_bouquet_999")
				5: reward = _insert_lottery_equipment(4, 9, 2, forced_equipment_choice)
		2:
			match choice:
				0: reward = _lottery_pet_reward("holy_angel")
				1: reward = _insert_lottery_equipment(4, 12, 1, forced_equipment_choice)
				2: reward = _lottery_item_reward("skill_flying_slash")
				3: reward = _lottery_item_reward("skill_fighting_spirit")
				4: reward = _lottery_item_reward("advanced_star_sword")
				5: reward = _lottery_item_reward("skill_flying_slash")
				6: reward = _lottery_item_reward("soul_king")
		3:
			match choice:
				0: reward = _lottery_pet_reward("strange_beast", 800.0)
				1: reward = _insert_lottery_equipment(4, 0, 0, forced_equipment_choice)
				2: reward = _lottery_pet_reward("strange_beast", 1200.0)
				3: reward = _lottery_item_reward("illusion_heart")
				4: reward = _lottery_item_reward("magic_soul_heart")
		4:
			match choice:
				0: reward = _lottery_item_reward("exp_ball")
				1:
					var magic_soul := clampi(forced_magic_soul, 0, 8) if forced_magic_soul >= 0 else lottery_rng.randi_range(0, 8)
					reward = _insert_lottery_equipment(3, magic_soul, 0, forced_equipment_choice)
				2: reward = _lottery_item_reward("soul_crystal")
				3: reward = _lottery_item_reward("rose_bouquet_99")
	reward["tier"] = tier
	reward["roll"] = roll
	reward["choice"] = choice
	reward["cost"] = LOTTERY_COST
	reward["time_result"] = time_result
	return reward


func _lottery_item_reward(item_id: String) -> Dictionary:
	if not add_item(item_id):
		return {"success":false, "reason":"inventory_full", "reward_kind":"item", "item_id":item_id}
	return {"success":true, "reward_kind":"item", "item_id":item_id}


func _lottery_pet_reward(template_id: String, quality_score: float = -1.0) -> Dictionary:
	if not _add_pet_instance(template_id, quality_score):
		return {"success":false, "reason":"pet_inventory_full", "reward_kind":"pet", "pet_template_id":template_id}
	pets_changed.emit()
	return {"success":true, "reward_kind":"pet", "pet_template_id":template_id, "pet":pets.back()}


func _refresh_relationship_skills(play_sound: bool = true) -> bool:
	var updated := skill_service.unlock_relationship_skills(learned_skills, affection)
	if updated == learned_skills:
		return false
	learned_skills = updated
	if play_sound:
		AudioService.play("learn_skill")
	return true


func use_love_power(roll: float = -1.0) -> Dictionary:
	var rank := int(learned_skills.get("love_power", 0))
	if rank <= 0:
		return {"success":false, "reason":"not_learned"}
	var chance := skill_service.utility_success_chance(learned_skills, "love_power")
	var actual_roll := relationship_rng.randf() if roll < 0.0 else roll
	if actual_roll >= chance:
		return {"success":false, "reason":"failed_roll", "chance":chance}
	var luck_bonus := skill_service.utility_luck_bonus(learned_skills, "love_power")
	base_stats.luck = int(base_stats.get("luck", 0)) + luck_bonus
	player_current_hp = int(get_player_stats().get("max_hp", 1))
	for index in pets.size():
		pets[index].current_hp = int(pet_service.get_stats(pets[index]).max_hp)
	AudioService.play("potion")
	pets_changed.emit()
	progression_changed.emit()
	return {"success":true, "rank":rank, "chance":chance, "luck":luck_bonus}


func _has_active_war_soul() -> bool:
	for item: Dictionary in equipment.values():
		if not item.is_empty() and bool(item.get("enhancement", {}).get("war_soul_active", false)):
			return true
	return false


func princess_sunday_gift_item_id(relationship_level: int = -1, war_soul_open: Variant = null) -> String:
	var tier := int(get_affection_rank().get("level", 0)) if relationship_level < 0 else relationship_level
	if tier <= 2:
		return "advanced_exp_stone"
	if tier <= 4:
		return "advanced_combat_stone"
	if tier == 5:
		return "soul_king"
	var opened := _has_active_war_soul() if war_soul_open == null else bool(war_soul_open)
	return "war_soul_heart" if opened else "plasma_potion"


func claim_princess_sunday_gift() -> Dictionary:
	if current_day % 7 != 0:
		return {"success":false, "reason":"not_sunday"}
	if int(get_affection_rank().get("level", 0)) <= 0:
		return {"success":false, "reason":"princess_not_met"}
	if last_princess_gift_day == current_day:
		return {"success":false, "reason":"already_claimed"}
	var item_id := princess_sunday_gift_item_id()
	if not add_item(item_id, 1):
		return {"success":false, "reason":"inventory_full", "item_id":item_id}
	last_princess_gift_day = current_day
	AudioService.play("open")
	social_changed.emit()
	return {"success":true, "item_id":item_id}


func claim_military_salary() -> Dictionary:
	if current_day % 7 != 0:
		return {"success":false, "reason":"not_sunday"}
	var rank := get_military_rank()
	if int(rank.get("level", 0)) <= 0:
		return {"success":false, "reason":"no_rank"}
	if last_military_salary_day == current_day:
		return {"success":false, "reason":"already_claimed"}
	var reward := 999999999
	magic_stones += reward
	last_military_salary_day = current_day
	currency_changed.emit()
	social_changed.emit()
	return {"success":true, "magic_stones":reward, "rank_name":str(rank.get("name", ""))}


func register_pk_race() -> Dictionary:
	if current_day % 7 != 6:
		return {"success":false, "reason":"not_saturday"}
	if last_pk_race_day == current_day:
		return {"success":false, "reason":"already_entered"}
	var map_id := "pk_arena" if level <= 60 else ("pk_arena_2" if level <= 100 else "pk_arena_3")
	last_pk_race_day = current_day
	pk_race_active = true
	current_map_id = map_id
	story_changed.emit()
	return {"success":true, "map_id":map_id, "group":1 if level <= 60 else (2 if level <= 100 else 3)}


func finish_pk_race(_victory: bool = false) -> void:
	pk_race_active = false
	story_changed.emit()


func has_full_extreme_quality_set() -> bool:
	for equipment_slot: String in ["weapon", "helmet", "necklace", "armor", "bracelet", "boots"]:
		var item: Dictionary = equipment.get(equipment_slot, {})
		if item.is_empty() or int(item.get("enhancement", {}).get("quality_level", 0)) < 4:
			return false
	return true


func try_unlock_war_soul_quest() -> bool:
	if bool(story_flags.get("war_soul_secret_unlocked", false)) or bool(story_flags.get("war_soul_quest_available", false)):
		return false
	if not has_full_extreme_quality_set():
		return false
	story_flags["war_soul_quest_available"] = true
	story_changed.emit()
	return true


func enter_war_soul_maze() -> Dictionary:
	if bool(story_flags.get("war_soul_secret_unlocked", false)):
		return {"success":false, "reason":"already_completed"}
	if not bool(story_flags.get("war_soul_quest_available", false)):
		return {"success":false, "reason":"quest_locked"}
	if magic_stones < 50000:
		return {"success":false, "reason":"not_enough_stones"}
	magic_stones -= 50000
	var time_result := spend_time(15)
	war_soul_maze_active = true
	war_soul_guardian_revealed = false
	current_map_id = "war_soul_seal_maze"
	currency_changed.emit()
	story_changed.emit()
	return {
		"success":true, "cost":50000, "map_id":current_map_id,
		"day_advanced":bool(time_result.get("day_advanced", false)),
		"days_advanced":int(time_result.get("days_advanced", 0)),
	}


func reveal_war_soul_guardian() -> bool:
	if current_map_id != "war_soul_seal_maze" or not war_soul_maze_active or bool(story_flags.get("war_soul_secret_unlocked", false)):
		return false
	war_soul_guardian_revealed = true
	story_changed.emit()
	return true


func complete_war_soul_secret() -> Dictionary:
	if not war_soul_maze_active or not bool(story_flags.get("war_soul_quest_available", false)):
		return {"triggered":false, "reason":"quest_inactive"}
	story_flags["war_soul_quest_available"] = false
	story_flags["war_soul_secret_unlocked"] = true
	war_soul_maze_active = false
	war_soul_guardian_revealed = false
	story_changed.emit()
	return {
		"triggered":true,
		"event":"war_soul_secret",
		"message":"获得了战魂之心，终于找到了战魂的秘密。",
	}


func leave_war_soul_maze() -> void:
	war_soul_maze_active = false
	war_soul_guardian_revealed = false
	story_changed.emit()


func complete_daily_task(task_id: String) -> Dictionary:
	if bool(completed_daily_tasks.get(task_id, false)):
		return {"success":false, "reason":"already_completed"}
	var task := progression_service.daily_task(task_id)
	if task.is_empty():
		return {"success":false, "reason":"unknown_task"}
	var item_id := str(task.get("item_id", ""))
	var quantity := int(task.get("quantity", 1))
	if not consume_item(item_id, quantity):
		return {"success":false, "reason":"missing_item", "item_id":item_id, "required":quantity}
	var merit_gain := int(task.get("nobility_merit", 0))
	var military_gain := int(task.get("military_merit", 0))
	nobility_merit += merit_gain
	military_merit += military_gain
	completed_daily_tasks[task_id] = true
	progression_changed.emit()
	social_changed.emit()
	return {"success":true, "nobility_merit":merit_gain, "military_merit":military_gain}


func submit_pet_for_daily_task(instance_id: int) -> Dictionary:
	if bool(completed_daily_tasks.get("submit_pet", false)):
		return {"success":false, "reason":"already_completed"}
	var pet_index := get_pet_index(instance_id)
	if pet_index < 0:
		return {"success":false, "reason":"missing_pet"}
	var pet: Dictionary = pets[pet_index]
	if bool(pet.get("deployed", false)):
		return {"success":false, "reason":"deployed"}
	var stars := float(pet.get("quality_score", 0.0)) / 100.0
	var stone_reward := 0
	if stars >= 30.0:
		stone_reward = 50000
	elif stars >= 15.0:
		stone_reward = 10000
	elif stars >= 10.0:
		stone_reward = 5000
	else:
		return {"success":false, "reason":"score_too_low", "required_stars":10}
	pets.remove_at(pet_index)
	magic_stones += stone_reward
	military_merit += 1000
	completed_daily_tasks["submit_pet"] = true
	pets_changed.emit()
	currency_changed.emit()
	progression_changed.emit()
	social_changed.emit()
	return {"success":true, "magic_stones":stone_reward, "military_merit":1000}


func default_demon_campaign() -> Dictionary:
	# 单一默认源：SAVE_SCHEMA_DEFAULTS（杜绝与 load/save 默认漂移）
	return (SAVE_SCHEMA_DEFAULTS["demon_campaign"] as Dictionary).duplicate(true)


func is_final_campaign_monster(monster_id: String) -> bool:
	return FINAL_CAMPAIGN_FLAG_BY_MONSTER.has(monster_id)


func is_final_campaign_enemy_alive(monster_id: String) -> bool:
	var flag_id := str(FINAL_CAMPAIGN_FLAG_BY_MONSTER.get(monster_id, ""))
	return not flag_id.is_empty() and bool(demon_campaign.get(flag_id, true)) and not bool(story_flags.get("game_won", false))


func final_campaign_modifiers(monster_id: String) -> Dictionary:
	if not is_final_campaign_monster(monster_id):
		return {}
	return {
		"attack": 1.5 if bool(demon_campaign.get("assault_alive", true)) else 1.0,
		"defense": 1.5 if bool(demon_campaign.get("guard_alive", true)) else 1.0,
		"max_hp": 1.5 if bool(demon_campaign.get("mystery_alive", true)) else 1.0,
		"combat_power": 1.5 if bool(demon_campaign.get("totem_alive", true)) else 1.0,
	}


func battle_modifiers(monster_id: String) -> Dictionary:
	if monster_id == "nameless_war_soul_keeper":
		var effective_level := maxi(50, level)
		var stat_scale := float(effective_level) / 50.0
		return {
			"level":stat_scale,
			"max_hp":stat_scale,
			"attack":stat_scale,
			"defense":stat_scale,
			"combat_power":float(100 + effective_level) / 150.0,
		}
	return final_campaign_modifiers(monster_id)


func roll_final_campaign_drop(monster_id: String, forced_roll: float = -1.0) -> String:
	if not _has_active_war_soul():
		return ""
	if monster_id == "demon_commander":
		return "war_soul_heart"
	if not FINAL_CAMPAIGN_SUPPORT_MONSTERS.has(monster_id):
		return ""
	var actual_roll := campaign_rng.randf() if forced_roll < 0.0 else forced_roll
	return "war_soul_heart" if actual_roll < 0.25 else "war_soul_crystal"


func resolve_final_campaign_victory(monster_id: String) -> Dictionary:
	var flag_id := str(FINAL_CAMPAIGN_FLAG_BY_MONSTER.get(monster_id, ""))
	if flag_id.is_empty():
		return {}
	if not bool(demon_campaign.get(flag_id, true)):
		return {"triggered":false, "event":"final_campaign", "reason":"already_defeated"}
	demon_campaign[flag_id] = false
	var messages := {
		"demon_assault":"魔军突击队已经被消灭，所有魔军的攻击力下降50%。",
		"demon_guard":"魔军守卫军已经被消灭，所有魔军的防御力下降50%。",
		"demon_mystery":"魔军神秘部队已经被消灭，所有魔军的生命值下降50%。",
		"demon_totem":"魔军图腾兽已经被消灭，所有魔军的战斗力下降50%。",
		"demon_commander":"魔军主帅已经被消灭！现在可以进入能量塔禁地，摧毁魔的能量。",
		"demon_energy":"魔的能量已经被摧毁，魔族大军彻底败退。游戏主线胜利！",
	}
	if monster_id == "demon_energy":
		story_flags["game_won"] = true
	story_changed.emit()
	return {
		"triggered":true,
		"event":"final_campaign",
		"monster_id":monster_id,
		"message":str(messages.get(monster_id, "")),
		"game_won":bool(story_flags.get("game_won", false)),
	}


func default_fuwa_event() -> Dictionary:
	# 单一默认源：SAVE_SCHEMA_DEFAULTS（杜绝与 load/save 默认漂移）
	return (SAVE_SCHEMA_DEFAULTS["fuwa_event"] as Dictionary).duplicate(true)


func normalize_fuwa_event(raw_state: Dictionary) -> Dictionary:
	var state := default_fuwa_event()
	state.found_count = clampi(int(raw_state.get("found_count", 0)), 0, FUWA_NAMES.size())
	state.round_active = bool(raw_state.get("round_active", false)) and int(state.found_count) < FUWA_NAMES.size()
	state.beast_defeated = bool(raw_state.get("beast_defeated", false)) and bool(state.round_active)
	state.completion_claimed = bool(raw_state.get("completion_claimed", false))
	var messenger_map := str(raw_state.get("messenger_map", state.messenger_map))
	state.messenger_map = messenger_map if messenger_map in FUWA_MESSENGER_MAP_BY_ROLL else ""
	if bool(state.round_active) or int(state.found_count) >= FUWA_NAMES.size():
		state.messenger_map = ""
	return state


func current_fuwa_name() -> String:
	var index := clampi(int(fuwa_event.get("found_count", 0)), 0, FUWA_NAMES.size() - 1)
	return str(FUWA_NAMES[index])


func current_fuwa_image_path() -> String:
	var paths := [
		"res://assets/extracted/images/image_1101.png",
		"res://assets/extracted/images/image_1104.png",
		"res://assets/extracted/images/image_1106.png",
		"res://assets/extracted/images/image_1108.png",
		"res://assets/extracted/images/image_1110.png",
	]
	var index := clampi(int(fuwa_event.get("found_count", 0)), 0, paths.size() - 1)
	return str(paths[index])


func should_show_fuwa_messenger(map_id: String) -> bool:
	return int(fuwa_event.get("found_count", 0)) < FUWA_NAMES.size() \
		and not bool(fuwa_event.get("round_active", false)) \
		and str(fuwa_event.get("messenger_map", "")) == map_id


func start_fuwa_round() -> Dictionary:
	if int(fuwa_event.get("found_count", 0)) >= FUWA_NAMES.size():
		return {"success":false, "reason":"all_found"}
	if bool(fuwa_event.get("round_active", false)):
		return {"success":false, "reason":"already_active"}
	fuwa_event.round_active = true
	fuwa_event.beast_defeated = false
	fuwa_event.messenger_map = ""
	current_map_id = "green_field"
	story_changed.emit()
	return {"success":true, "map_id":current_map_id, "fuwa_name":current_fuwa_name()}


func complete_fuwa_beast_battle() -> Dictionary:
	if not bool(fuwa_event.get("round_active", false)):
		return {"triggered":false, "reason":"round_not_active"}
	fuwa_event.beast_defeated = true
	story_changed.emit()
	return {
		"triggered":true,
		"event":"fuwa_beast",
		"message":"你击败了挡道的雷角风牙兽，前往草原2寻找福娃。",
	}


func claim_fuwa_reward(forced_reward_index: int = -1) -> Dictionary:
	if not bool(fuwa_event.get("round_active", false)) or not bool(fuwa_event.get("beast_defeated", false)):
		return {"success":false, "reason":"beast_not_defeated"}
	var reward_index := clampi(forced_reward_index, 0, FUWA_REWARD_ITEM_IDS.size() - 1) if forced_reward_index >= 0 else fuwa_rng.randi_range(0, FUWA_REWARD_ITEM_IDS.size() - 1)
	var item_id := str(FUWA_REWARD_ITEM_IDS[reward_index])
	if not add_item(item_id, 1):
		return {"success":false, "reason":"inventory_full", "item_id":item_id}
	var found_name := current_fuwa_name()
	fuwa_event.found_count = mini(FUWA_NAMES.size(), int(fuwa_event.get("found_count", 0)) + 1)
	fuwa_event.round_active = false
	fuwa_event.beast_defeated = false
	fuwa_event.messenger_map = ""
	var all_found := int(fuwa_event.found_count) >= FUWA_NAMES.size()
	current_map_id = "treeheart_city" if all_found else "cassano_city"
	story_changed.emit()
	return {
		"success":true,
		"item_id":item_id,
		"fuwa_name":found_name,
		"found_count":int(fuwa_event.found_count),
		"all_found":all_found,
		"next_map_id":current_map_id,
	}


func claim_fuwa_completion() -> Dictionary:
	if int(fuwa_event.get("found_count", 0)) < FUWA_NAMES.size():
		return {"success":false, "reason":"not_complete"}
	if bool(fuwa_event.get("completion_claimed", false)):
		return {"success":false, "reason":"already_claimed"}
	fuwa_event.completion_claimed = true
	magic_stones += 100000
	research.vip_level = int(research.get("vip_level", 0)) + 1
	current_map_id = "cassano_city"
	currency_changed.emit()
	research_changed.emit()
	story_changed.emit()
	return {
		"success":true,
		"magic_stones":100000,
		"vip_level":int(research.vip_level),
		"original_technology_cap":150,
		"effective_technology_cap":int(pet_service.config.get("research", {}).get("technology_level_cap", 300)),
		"next_map_id":current_map_id,
	}


func refresh_fuwa_messenger_for_new_day(forced_roll: int = -1) -> String:
	if int(fuwa_event.get("found_count", 0)) >= FUWA_NAMES.size() or bool(fuwa_event.get("round_active", false)):
		fuwa_event.messenger_map = ""
		return ""
	var roll := clampi(forced_roll, 1, 9) if forced_roll >= 1 else fuwa_rng.randi_range(1, 9)
	fuwa_event.messenger_map = str(FUWA_MESSENGER_MAP_BY_ROLL[roll - 1])
	story_changed.emit()
	return str(fuwa_event.messenger_map)

func advance_day() -> Dictionary:
	current_day += 1
	current_time_used = 0
	completed_daily_tasks.clear()
	var previous_research_stock := int(research.get("stock", 0))
	var previous_research_level := float(research.get("technology_level", 0.0))
	research = pet_service.produce(research, 1)
	if (current_day - 1) % 7 == 0:
		research = pet_service.advance_week(research)
	var research_produced := int(research.get("stock", 0)) - previous_research_stock
	var research_grew := not is_equal_approx(previous_research_level, float(research.get("technology_level", 0.0)))
	if research_produced > 0 or research_grew:
		research_changed.emit()
	story_flags["maid_combat_stone_available"] = true
	pk_race_active = false
	quest_states = quest_service.reset_daily(quest_states)
	refresh_fuwa_messenger_for_new_day()
	for index in pets.size():
		pets[index].current_hp = int(pet_service.get_stats(pets[index]).max_hp)
	var revived := false
	if bool(story_flags.get("king_rescued", false)) and not bool(story_flags.get("game_won", false)):
		for flag_id: String in demon_campaign:
			if not bool(demon_campaign.get(flag_id, true)):
				revived = true
				break
	if revived:
		demon_campaign = default_demon_campaign()
		story_changed.emit()
	pets_changed.emit()
	social_changed.emit()
	quests_changed.emit()
	time_changed.emit()
	return {
		"demon_army_revived":revived,
		"message":"黑夜到来时，魔的能量将所有死亡的魔族军队复活了。" if revived else "",
		"research_produced":research_produced,
		"research_grew":research_grew,
	}


func get_main_flow_state() -> Dictionary:
	var total_steps := 9
	if bool(story_flags.get("game_won", false)):
		return {"step":total_steps, "total":total_steps, "stage":"complete", "title":"主线已经完成", "objective":"魔的能量已经被摧毁，可以查看游戏结束评价。", "target_map":"energy_tower", "target_name":"能量塔禁地"}
	if not bool(story_flags.get("king_rescued", false)):
		if not bool(unlocked_maps.get("dungeon_floor_2", false)):
			return {"step":0, "total":total_steps, "stage":"dungeon_1", "title":"营救国王（一）", "objective":"从卡萨诺城的日常任务官进入地下城，击败一层首领。建议先在大陆提升等级与装备。", "target_map":"dungeon", "target_name":"地下城一层"}
		if not bool(unlocked_maps.get("dungeon_floor_3", false)):
			return {"step":1, "total":total_steps, "stage":"dungeon_2", "title":"营救国王（二）", "objective":"从地下城一层右侧进入二层，击败地下城二层首领。", "target_map":"dungeon_floor_2", "target_name":"地下城二层"}
		return {"step":2, "total":total_steps, "stage":"dungeon_3", "title":"营救国王（三）", "objective":"进入地下城三层并击败最后的首领，救出国王。", "target_map":"dungeon_floor_3", "target_name":"地下城三层"}
	var army_steps := [
		["assault_alive", "demon_camp", "魔军中军", "削弱魔军攻击", "击败魔军突击队，移除全军50%攻击增益。"],
		["guard_alive", "demon_camp", "魔军中军", "削弱魔军防御", "击败魔军守卫军，移除全军50%防御增益。"],
		["totem_alive", "demon_left", "魔左军阵地", "摧毁魔军图腾", "击败魔军图腾兽，移除全军50%战斗力增益。"],
		["mystery_alive", "demon_right", "魔右军阵地", "消灭神秘部队", "击败魔军神秘部队，移除全军50%生命增益。"],
	]
	var completed_armies := 0
	for entry: Array in army_steps:
		if not bool(demon_campaign.get(str(entry[0]), true)):
			completed_armies += 1
	for entry: Array in army_steps:
		if bool(demon_campaign.get(str(entry[0]), true)):
			return {"step":3 + completed_armies, "total":total_steps, "stage":str(entry[0]), "title":str(entry[3]), "objective":str(entry[4]), "target_map":str(entry[1]), "target_name":str(entry[2])}
	if bool(demon_campaign.get("commander_alive", true)):
		return {"step":7, "total":total_steps, "stage":"commander", "title":"决战魔军主帅", "objective":"四支增援部队已经清除。前往魔军帅旗击败魔军主帅。", "target_map":"demon_banner", "target_name":"魔军帅旗"}
	return {"step":8, "total":total_steps, "stage":"energy", "title":"摧毁魔的能量", "objective":"从魔军帅旗右侧进入能量塔禁地，摧毁魔的能量并完成主线。", "target_map":"energy_tower", "target_name":"能量塔禁地"}


func accept_quest(quest_id: String) -> bool:
	var result := quest_service.accept(quest_states, quest_id)
	if not result.get("success", false):
		return false
	quest_states = result.states
	quests_changed.emit()
	return true


func can_enter_map(map_id: String) -> bool:
	if map_id == "palace_garden" and int(get_nobility_rank().get("level", 0)) <= 0:
		return false
	if unlocked_maps.has(map_id) and not bool(unlocked_maps.get(map_id, false)):
		return false
	if map_id == "ice_border" and current_day % 7 != 5 and not bool(story_flags.get("king_rescued", false)):
		return false
	if map_id in ["demon_camp", "demon_left", "demon_right", "demon_banner"] and not bool(story_flags.get("king_rescued", false)):
		return false
	if map_id == "energy_tower" and bool(demon_campaign.get("commander_alive", true)):
		return false
	return level >= int(MAP_LEVEL_REQUIREMENTS.get(map_id, 1))


func rescue_king() -> Dictionary:
	if bool(story_flags.get("king_rescued", false)):
		return {"triggered":false, "reason":"already_rescued"}
	story_flags["king_rescued"] = true
	var result := {"triggered":true, "event":"king_rescue", "reward_type":"", "magic_stones":0, "rank_name":""}
	if int(get_nobility_rank().get("level", 0)) < 6:
		nobility_merit = maxi(nobility_merit, 100000)
		result.reward_type = "nobility_rank"
		result.rank_name = str(get_nobility_rank().get("name", "王"))
	else:
		magic_stones += 200000
		result.reward_type = "magic_stones"
		result.magic_stones = 200000
		currency_changed.emit()
	progression_changed.emit()
	social_changed.emit()
	story_changed.emit()
	return result


func map_entry_required_level(map_id: String) -> int:
	return int(MAP_LEVEL_REQUIREMENTS.get(map_id, 1))


func map_entry_availability_rule(map_id: String) -> String:
	if map_id == "palace_garden":
		return "nobility_rank_gt_0"
	if map_id == "dungeon_floor_2":
		return "unlocked_map:dungeon_floor_2"
	if map_id == "dungeon_floor_3":
		return "unlocked_map:dungeon_floor_3"
	if map_id == "ice_border":
		return "friday_or_king_rescued"
	if map_id in ["demon_camp", "demon_left", "demon_right", "demon_banner"]:
		return "king_rescued"
	if map_id == "energy_tower":
		return "commander_defeated"
	return "level_only"


func get_territory(map_id: String) -> Dictionary:
	return territory_service.get_territory(map_id)


func territory_challenge_status(map_id: String) -> Dictionary:
	var territory := get_territory(map_id)
	if territory.is_empty():
		return {"available":false, "reason":"not_territory"}
	var required_level := int(territory.get("required_nobility_level", 0))
	var current_rank_level := int(get_nobility_rank().get("level", 0))
	if current_rank_level < required_level:
		return {"available":false, "reason":"rank_too_low", "required_rank_name":str(territory.get("required_rank_name", ""))}
	if last_territory_challenge_day == current_day:
		return {"available":false, "reason":"already_challenged"}
	if not pending_territory_challenge.is_empty():
		return {"available":false, "reason":"challenge_in_progress"}
	return {"available":true}


func begin_territory_challenge(map_id: String) -> Dictionary:
	if current_map_id != map_id:
		return {"success":false, "reason":"wrong_map"}
	var status := territory_challenge_status(map_id)
	if not bool(status.get("available", false)):
		return {"success":false, "reason":str(status.get("reason", "unavailable")), "required_rank_name":str(status.get("required_rank_name", ""))}
	pending_territory_challenge = map_id
	last_territory_challenge_day = current_day
	territory_changed.emit()
	return {"success":true, "challenger_id":str(get_territory(map_id).get("challenger_id", ""))}


func resolve_territory_challenge(monster_id: String, victory: bool) -> Dictionary:
	var map_id := territory_service.map_for_challenger(monster_id)
	if map_id.is_empty() or pending_territory_challenge != map_id:
		return {"resolved":false}
	pending_territory_challenge = ""
	if victory:
		owned_territory = map_id
	territory_changed.emit()
	return {"resolved":true, "victory":victory, "map_id":map_id, "owned_territory":owned_territory}


func claim_territory_reward(map_id: String) -> Dictionary:
	if owned_territory != map_id:
		return {"success":false, "reason":"not_owner"}
	if last_territory_reward_day == current_day:
		return {"success":false, "reason":"already_claimed"}
	var reward_ids := territory_service.reward_item_ids(map_id)
	if reward_ids.is_empty():
		return {"success":false, "reason":"no_reward"}
	for item_id: String in reward_ids:
		if not item_database.has(item_id):
			return {"success":false, "reason":"invalid_reward"}
	queue_loot(reward_ids)
	last_territory_reward_day = current_day
	territory_changed.emit()
	return {"success":true, "item_ids":reward_ids}


func claim_quest(quest_id: String) -> Dictionary:
	var result := quest_service.claim(quest_states, quest_id)
	if not result.get("success", false):
		return {"success":false, "reason":"not_ready"}
	quest_states = result.states
	var rewards: Dictionary = result.get("rewards", {})
	_add_player_experience(int(rewards.get("experience", 0)))
	military_merit += int(rewards.get("military_merit", 0))
	nobility_merit += int(rewards.get("nobility_merit", 0))
	gold += int(rewards.get("gold", 0))
	magic_stones += int(rewards.get("magic_stones", 0))
	var reward_item := str(rewards.get("item_id", ""))
	if not reward_item.is_empty():
		var reward_quantity := int(rewards.get("quantity", 1))
		for item_index in reward_quantity:
			loot_queue.append(reward_item)
		loot_changed.emit()
	progression_changed.emit()
	currency_changed.emit()
	quests_changed.emit()
	return {"success":true, "rewards":rewards}


func equip_from_inventory(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= inventory.size() or inventory[slot_index].is_empty():
		return false
	var item := inventory[slot_index]
	if int(item.get("quantity", 1)) != 1:
		return false
	var definition := get_item_definition(str(item.get("item_id", "")))
	if definition.get("category", "") != "equipment":
		return false
	var equipment_slot := str(definition.get("equipment_slot", ""))
	if not equipment.has(equipment_slot):
		return false
	var previous_item: Dictionary = equipment[equipment_slot]
	equipment[equipment_slot] = item.duplicate(true)
	inventory[slot_index] = previous_item.duplicate(true) if not previous_item.is_empty() else {}
	inventory_changed.emit()
	equipment_changed.emit()
	AudioService.play("equip")
	return true


func get_player_stats() -> Dictionary:
	var stats := base_stats.duplicate(true)
	var equipment_power := 0
	for equipment_slot: String in equipment:
		var item: Dictionary = equipment[equipment_slot]
		if item.is_empty():
			continue
		var item_id := str(item.get("item_id", ""))
		var definition := get_item_definition(item_id)
		var instance: Dictionary = item.get("enhancement", enhancement.create_equipment_instance(item_id))
		var multiplier := enhancement.stat_multiplier(instance)
		for stat_name in ["max_hp", "attack", "defense"]:
			stats[stat_name] = int(stats.get(stat_name, 0)) + roundi(int(definition.get(stat_name, 0)) * multiplier)
		var soul_bonuses := enhancement.soul_bonuses(instance)
		var war_soul_power_multiplier := 1.0 + float(enhancement.war_soul_combat_power_percent(instance)) / 100.0
		equipment_power += roundi(int(definition.get("combat_power", 0)) * multiplier * war_soul_power_multiplier)
		stats["heaven_attack_percent"] = int(stats.get("heaven_attack_percent", 0)) + int(soul_bonuses.attack_percent)
		stats["dodge_percent"] = int(stats.get("dodge_percent", 0)) + int(soul_bonuses.dodge_percent)
	stats["attack"] = roundi(int(stats.attack) * (1.0 + float(stats.get("heaven_attack_percent", 0)) / 100.0))
	stats["dodge_percent"] = mini(95, int(stats.get("dodge_percent", 0)))
	stats["pet_attack"] = 0
	stats["pet_defense"] = 0
	stats["pet_max_hp"] = 0
	stats["pet_combat_power"] = 0
	stats["battle_pets"] = []
	for pet: Dictionary in pets:
		if not bool(pet.get("deployed", false)):
			continue
		var pet_stats := pet_service.get_stats(pet)
		var pet_max_hp := int(pet_stats.max_hp)
		var pet_current_hp := clampi(int(pet.get("current_hp", pet_max_hp)), 0, pet_max_hp)
		if pet_current_hp > 0:
			stats.pet_combat_power = int(stats.pet_combat_power) + int(pet_stats.combat_power)
		if not bool(pet.get("combined", false)):
			continue
		stats.battle_pets.append({
			"instance_id":int(pet.get("instance_id", 0)),
			"name":str(pet.get("custom_name", "幻兽")),
			"current_hp":pet_current_hp,
			"max_hp":pet_max_hp,
			"attack":int(pet_stats.attack),
			"defense":int(pet_stats.defense),
		})
		if pet_current_hp <= 0:
			continue
		stats.pet_attack = int(stats.pet_attack) + int(pet_stats.attack)
		stats.pet_defense = int(stats.pet_defense) + int(pet_stats.defense)
		stats.pet_max_hp = int(stats.pet_max_hp) + pet_max_hp
		stats.attack = int(stats.attack) + int(pet_stats.attack)
		stats.defense = int(stats.defense) + int(pet_stats.defense)
	stats["current_hp"] = clampi(player_current_hp, 0, maxi(1, int(stats.max_hp)))
	stats["rank_combat_power"] = progression_service.combat_power_bonus(military_merit, nobility_merit)
	var combat_power_before_skills := int(stats.attack) * 2 + int(stats.defense) + int(int(stats.max_hp) / 10) + equipment_power + int(stats.pet_combat_power) + int(stats.rank_combat_power)
	stats["equipment_combat_power"] = equipment_power
	stats["skill_combat_power_percent"] = skill_service.combat_power_percent(learned_skills)
	stats["skill_combat_power"] = roundi(float(combat_power_before_skills) * float(stats.skill_combat_power_percent))
	stats["combat_power"] = combat_power_before_skills + int(stats.skill_combat_power)
	return stats


func commit_battle_health(next_player_hp: int, battle_pet_states: Array) -> void:
	var maximum_player_hp := maxi(1, int(get_player_stats().get("max_hp", 1)))
	var normalized_player_hp := clampi(next_player_hp, 0, maximum_player_hp)
	var player_changed := normalized_player_hp != player_current_hp
	player_current_hp = normalized_player_hp
	var pets_changed_now := false
	for raw_state: Variant in battle_pet_states:
		if not raw_state is Dictionary:
			continue
		var pet_index := get_pet_index(int(raw_state.get("instance_id", 0)))
		if pet_index < 0:
			continue
		var maximum_pet_hp := maxi(1, int(pet_service.get_stats(pets[pet_index]).max_hp))
		var normalized_pet_hp := clampi(int(raw_state.get("current_hp", maximum_pet_hp)), 0, maximum_pet_hp)
		if int(pets[pet_index].get("current_hp", maximum_pet_hp)) != normalized_pet_hp:
			pets[pet_index].current_hp = normalized_pet_hp
			pets_changed_now = true
	if player_changed:
		progression_changed.emit()
	if pets_changed_now:
		pets_changed.emit()


func apply_pet_death_penalty(instance_ids: Array) -> Dictionary:
	var unique_ids: Dictionary = {}
	for raw_id: Variant in instance_ids:
		var instance_id := int(raw_id)
		if instance_id > 0:
			unique_ids[instance_id] = true
	var deaths := unique_ids.size()
	if deaths <= 0:
		return {"deaths":0, "luck_lost":0, "forced_retreat":false}
	var previous_luck := maxi(0, int(base_stats.get("luck", 0)))
	base_stats.luck = maxi(0, previous_luck - deaths * 10)
	var luck_lost := previous_luck - int(base_stats.luck)
	progression_changed.emit()
	social_changed.emit()
	return {"deaths":deaths, "luck_lost":luck_lost, "forced_retreat":int(base_stats.luck) <= 0}


func apply_player_defeat_penalty() -> Dictionary:
	var previous_luck := maxi(0, int(base_stats.get("luck", 0)))
	base_stats.luck = maxi(0, previous_luck - 10)
	var experience_lost := roundi(float(experience) * 0.05)
	experience = maxi(0, experience - experience_lost)
	player_current_hp = 0
	progression_changed.emit()
	social_changed.emit()
	return {"luck_lost":previous_luck - int(base_stats.luck), "experience_lost":experience_lost}


func restore_player_health() -> bool:
	var maximum_hp := maxi(1, int(get_player_stats().get("max_hp", 1)))
	if player_current_hp >= maximum_hp:
		return false
	player_current_hp = maximum_hp
	progression_changed.emit()
	return true

func apply_victory_rewards(rewards: Dictionary) -> Dictionary:
	_add_player_experience(int(rewards.get("experience", 0)))
	military_merit += int(rewards.get("military_merit", 0))
	nobility_merit += int(rewards.get("nobility_merit", 0))
	gold += int(rewards.get("gold", 0))
	magic_stones += int(rewards.get("magic_stones", 0))
	if int(rewards.get("gold", 0)) != 0 or int(rewards.get("magic_stones", 0)) != 0:
		currency_changed.emit()
	var quest_result := quest_service.record_kill(quest_states, str(rewards.get("monster_id", "")))
	if quest_result.get("changed", false):
		quest_states = quest_result.states
		quests_changed.emit()
	var story_result: Dictionary = {}
	match str(rewards.get("monster_id", "")):
		"dungeon_boss": unlocked_maps["dungeon_floor_2"] = true
		"dungeon_boss_2": unlocked_maps["dungeon_floor_3"] = true
		"dungeon_boss_3": story_result = rescue_king()
		"fuwa_beast": story_result = complete_fuwa_beast_battle()
		"nameless_war_soul_keeper": story_result = complete_war_soul_secret()
		"demon_assault", "demon_guard", "demon_mystery", "demon_totem", "demon_commander", "demon_energy":
			story_result = resolve_final_campaign_victory(str(rewards.get("monster_id", "")))
	var pet_experience := int(rewards.get("pet_experience", 0))
	var any_pet_changed := false
	if pet_experience > 0:
		for index in pets.size():
			if not bool(pets[index].get("deployed", false)):
				continue
			var pet_result: Dictionary = pet_service.grant_experience(pets[index], pet_experience, level)
			if pet_result.pet != pets[index]:
				pets[index] = pet_result.pet
				any_pet_changed = true
	progression_changed.emit()
	if any_pet_changed:
		pets_changed.emit()
	return story_result


func _add_player_experience(amount: int) -> void:
	experience += maxi(0, amount)
	var leveled_up := false
	while experience >= experience_to_next_level():
		experience -= experience_to_next_level()
		level += 1
		base_stats.max_hp = int(base_stats.max_hp) + 20
		base_stats.attack = int(base_stats.attack) + 5
		base_stats.defense = int(base_stats.defense) + 3
		leveled_up = true
	if leveled_up:
		player_current_hp = int(get_player_stats().get("max_hp", 1))
		player_current_stamina = get_player_max_stamina()
		# v1.37：升级反馈（唯一反馈通道；声音=升级.wav 导出名一致，声音由事件内部播放）。
		FeedbackService.emit("level_up", {"sound_name": "level_up", "level": level})


func experience_to_next_level() -> int:
	return level * 1000


func queue_loot(item_ids: Array) -> void:
	for item_id: Variant in item_ids:
		var normalized := str(item_id)
		if item_database.has(normalized) or not _parse_loot_equipment_token(normalized).is_empty():
			loot_queue.append(normalized)
	loot_changed.emit()


func claim_loot(item_id: String) -> bool:
	var loot_index := loot_queue.find(item_id)
	if loot_index < 0:
		return false
	# v1.37 整改02：每次真实领取创建稳定的 claim_operation_id（同一次领取操作的重复回调
	# 携带相同 ID，第二次被 FEEDBACK_DUPLICATE_EVENT 拒绝；两次独立领取产生不同 ID）。
	var claim_operation_id := _next_claim_operation_id
	_next_claim_operation_id += 1
	var loot_equipment := _parse_loot_equipment_token(item_id)
	if loot_equipment.is_empty():
		if not add_item(item_id):
			# v1.37：背包满领取失败反馈（队列物品不删除，顺序校验保证 reward_queued 已先行）。
			FeedbackService.emit("loot_claim_failed", {"item_id": item_id, "claim_operation_id": claim_operation_id})
			return false
	else:
		var empty_slot := -1
		for index in inventory.size():
			if inventory[index].is_empty():
				empty_slot = index
				break
		if empty_slot < 0:
			FeedbackService.emit("loot_claim_failed", {"item_id": item_id, "claim_operation_id": claim_operation_id})
			return false
		var entry := create_item_entry(str(loot_equipment.item_id))
		entry["drop_level"] = int(loot_equipment.item_level)
		entry.enhancement.quality_level = int(loot_equipment.quality_level)
		entry.enhancement.magic_soul_level = int(loot_equipment.magic_soul_level)
		entry.enhancement.socket_count = int(loot_equipment.socket_count)
		inventory[empty_slot] = entry
		inventory_changed.emit()
	loot_queue.remove_at(loot_index)
	loot_changed.emit()
	# v1.37：领取成功反馈（只在真实 claim_loot 成功后产生，携带稳定 operation ID）。
	FeedbackService.emit("loot_claimed", {"item_id": item_id, "claim_operation_id": claim_operation_id})
	return true

## v1.40 可恢复事务式保存：stale 清理 -> 写 .tmp -> flush -> 读回完整 schema 校验 + DTO 深比较 ->
## 备份旧档 -> 原子替换 -> 失败恢复旧档。每个 rename/remove 检查返回值。
## 固定装备槽位（DTO 构造与保存共用，不遍历运行时 equipment 变量）
const EQUIPMENT_SLOTS := ["weapon", "helmet", "necklace", "armor", "bracelet", "boots"]

const SAVE_SCHEMA_KEYS := ["version", "gold", "magic_stones", "inventory", "warehouse", "level",
	"experience", "military_merit", "nobility_merit", "affection", "current_day", "current_time_used",
	"completed_daily_tasks", "current_map_id", "equipment", "base_stats", "player_current_hp",
	"player_current_stamina", "loot_queue", "pets", "next_pet_instance_id", "research", "quest_states",
	"unlocked_maps", "learned_skills", "last_princess_gift_day", "last_princess_chat_day",
	"last_military_salary_day", "last_pk_race_day", "pk_race_active", "war_soul_maze_active",
	"war_soul_guardian_revealed", "story_flags", "fuwa_event", "demon_campaign", "owned_territory",
	"last_territory_challenge_day", "last_territory_reward_day"]

## 固定 schema 默认值（不使用当前运行中 GameState 值作为旧档默认）。
## 内部默认（story_flags/fuwa_event/demon_campaign/unlocked_maps/equipment 槽位）全部集中于此，
## default_demon_campaign()/default_fuwa_event() 也从本表派生，杜绝两处默认漂移。
const SAVE_SCHEMA_DEFAULTS := {
	"version": 21, "gold": 0, "magic_stones": 0, "inventory": [], "warehouse": [],
	"level": 1, "experience": 0, "military_merit": 0, "nobility_merit": 0, "affection": 0,
	"current_day": 1, "current_time_used": 0, "completed_daily_tasks": {}, "current_map_id": "cassano_city",
	"equipment": {"weapon": {}, "helmet": {}, "necklace": {}, "armor": {}, "bracelet": {}, "boots": {}},
	"base_stats": {"max_hp": 100, "attack": 10, "defense": 5, "luck": 0},
	"player_current_hp": 100, "player_current_stamina": 100, "loot_queue": [], "pets": [],
	"next_pet_instance_id": 1, "research": {}, "quest_states": {},
	"unlocked_maps": {"dungeon_floor_2": false, "dungeon_floor_3": false},
	"learned_skills": {}, "last_princess_gift_day": 0, "last_princess_chat_day": 0,
	"last_military_salary_day": 0, "last_pk_race_day": 0, "pk_race_active": false,
	"war_soul_maze_active": false, "war_soul_guardian_revealed": false,
	"story_flags": {"king_rescued": false, "princess_friend_gift_available": false,
		"maid_year_pig_available": true, "maid_combat_stone_available": true,
		"war_soul_quest_available": false, "war_soul_secret_unlocked": false, "game_won": false},
	"fuwa_event": {"found_count": 0, "round_active": false, "beast_defeated": false,
		"completion_claimed": false, "messenger_map": "thunder_continent"},
	"demon_campaign": {"assault_alive": true, "guard_alive": true, "mystery_alive": true,
		"totem_alive": true, "commander_alive": true, "energy_alive": true},
	"owned_territory": "",
	"last_territory_challenge_day": 0, "last_territory_reward_day": 0,
}

## IO 故障注入钩子（测试可注入故障点；生产为空字符串=正常）
var _save_fault_inject: String = ""

func set_save_fault_inject(fault: String) -> void:
	_save_fault_inject = fault

func save_game() -> bool:
	# P0-1 可恢复事务式保存：所有 IO 操作检查返回值
	var payload := _build_save_payload()
	var json_str := JSON.stringify(payload, "\t")
	var tmp_path := save_path + ".tmp"
	var bak_path := save_path + ".bak"
	var global_tmp := ProjectSettings.globalize_path(tmp_path)
	var global_save := ProjectSettings.globalize_path(save_path)
	var global_bak := ProjectSettings.globalize_path(bak_path)
	# 0. 恢复状态机（不盲删 .bak，所有清理检查返回值）
	if not _recover_save_state(global_save, global_tmp, global_bak):
		return false
	if _save_fault_inject == "tmp_open_fail":
		return false
	# 1. 写 .tmp + flush + get_error 检查
	var tmp_file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp_file == null:
		return false
	if _save_fault_inject == "write_fail":
		tmp_file.close()
		if DirAccess.remove_absolute(global_tmp) != OK:
			push_warning("save_game: write_fail 清理 tmp 失败")
		return false
	tmp_file.store_string(json_str)
	tmp_file.flush()
	if tmp_file.get_error() != OK:  # IO 错误检查
		tmp_file.close()
		if DirAccess.remove_absolute(global_tmp) != OK:
			push_warning("save_game: flush 错误后清理 tmp 失败")
		return false
	tmp_file.close()
	# 2. 读回 schema 校验 + 文本深比较
	if _save_fault_inject == "verify_fail":
		if DirAccess.remove_absolute(global_tmp) != OK:
			push_warning("save_game: verify_fail 清理 tmp 失败")
		return false
	var vf := FileAccess.open(tmp_path, FileAccess.READ)
	if vf == null:
		if DirAccess.remove_absolute(global_tmp) != OK:
			push_warning("save_game: 读回失败后清理 tmp 失败")
		return false
	var vt := vf.get_as_text()
	vf.close()
	if not _validate_save_schema(JSON.parse_string(vt)) or vt != json_str:
		if DirAccess.remove_absolute(global_tmp) != OK:
			push_warning("save_game: 校验失败后清理 tmp 失败")
		return false
	# 3. 备份旧档
	var had_old := FileAccess.file_exists(save_path)
	if had_old:
		if _save_fault_inject == "backup_fail":
			if DirAccess.remove_absolute(global_tmp) != OK:
				push_warning("save_game: backup_fail 清理 tmp 失败")
			return false
		if DirAccess.rename_absolute(global_save, global_bak) != OK:
			if DirAccess.remove_absolute(global_tmp) != OK:
				push_warning("save_game: 备份失败后清理 tmp 失败")
			return false
	# 4. 可恢复替换
	if _save_fault_inject == "replace_fail":
		if had_old:
			if DirAccess.rename_absolute(global_bak, global_save) != OK:
				push_warning("save_game: replace_fail 恢复 bak 失败")
		if DirAccess.remove_absolute(global_tmp) != OK:
			push_warning("save_game: replace_fail 清理 tmp 失败")
		return false
	if DirAccess.rename_absolute(global_tmp, global_save) != OK:
		if had_old:
			if DirAccess.rename_absolute(global_bak, global_save) != OK:
				push_warning("save_game: 替换+恢复均失败")
		return false
	# 5. 清理 .bak（cleanup_fail 不返回成功）
	if had_old:
		if _save_fault_inject == "cleanup_fail":
			push_warning("save_game: cleanup_fail，.bak 残留")
			return false
		if DirAccess.remove_absolute(global_bak) != OK:
			push_warning("save_game: 清理 .bak 失败")
			return false
	return true


func _recover_save_state(gs: String, gt: String, gb: String) -> bool:
	# P0-1 完整状态矩阵：所有清理操作检查返回值，只有全部成功才返回 true。
	# 有效判定使用 _is_authoritative_save（合法版本 + 核心身份字段 + 完整语义），
	# 空对象 {} / 缺 version / 缺核心字段的文件一律视为无效，不能挡住真实 bak 恢复。
	var fv := _is_authoritative_save(save_path)
	var bv := _is_authoritative_save(save_path + ".bak")
	var tv := _is_authoritative_save(save_path + ".tmp")
	# 情况 1：正式档有效 -> 清理 stale .tmp/.bak（检查返回值）
	if fv:
		if FileAccess.file_exists(save_path + ".tmp"):
			if DirAccess.remove_absolute(gt) != OK:
				push_warning("save_game: 恢复状态机清理 .tmp 失败")
				return false
		if FileAccess.file_exists(save_path + ".bak"):
			if DirAccess.remove_absolute(gb) != OK:
				push_warning("save_game: 恢复状态机清理 .bak 失败")
				return false
		return true
	# 情况 2：正式档缺失/损坏 + .bak 有效 -> 恢复 .bak
	if bv:
		# 损坏的正式档可能存在，先删除再恢复（Windows rename 不覆盖）
		if FileAccess.file_exists(save_path):
			if DirAccess.remove_absolute(gs) != OK:
				push_warning("save_game: 恢复 bak 前删除损坏 final 失败")
				return false
		if DirAccess.rename_absolute(gb, gs) != OK:
			push_warning("save_game: 恢复 .bak 失败")
			return false
		if FileAccess.file_exists(save_path + ".tmp"):
			if DirAccess.remove_absolute(gt) != OK:
				push_warning("save_game: 恢复 bak 后清理 .tmp 失败")
				return false
		return true
	# 情况 3：正式档缺失/损坏 + .bak 缺失/损坏 + .tmp 有效
	if tv:
		# 损坏的正式档可能存在，先删除再提交 tmp（Windows rename 不覆盖）
		if FileAccess.file_exists(save_path):
			if DirAccess.remove_absolute(gs) != OK:
				push_warning("save_game: 提交 tmp 前删除损坏 final 失败")
				return false
		if DirAccess.rename_absolute(gt, gs) != OK:
			push_warning("save_game: 提交 .tmp 失败")
			return false
		# 损坏 .bak 若存在必须一并删除：否则后续正常保存 rename(final->bak) 时
		# 目标路径已存在（Windows rename 不覆盖），备份必然失败。
		if FileAccess.file_exists(save_path + ".bak"):
			if DirAccess.remove_absolute(gb) != OK:
				push_warning("save_game: 提交 tmp 后删除损坏 bak 失败")
				return false
		return true
	# 情况 4：三档都缺失 -> 全新存档
	if not FileAccess.file_exists(save_path) and not FileAccess.file_exists(save_path + ".bak") and not FileAccess.file_exists(save_path + ".tmp"):
		return true
	# 情况 5：正式档与 .bak 都损坏 -> 禁止覆盖
	push_warning("save_game: 正式档与 .bak 都损坏，禁止覆盖")
	return false


## 权威正式档判定：合法版本 + 核心身份字段 + 完整语义校验。
## 与 load_game 的宽松迁移校验不同——事务恢复中判定"足以作为权威正式档的文件"，
## 必须至少含 version（1..21）与核心身份字段（gold/level，任何真实存档均具备），
## 空对象 {} 或残缺文件不得被判有效（否则会掩盖真实 bak 并导致唯一恢复源被删除）。
## 注意：不要求 current_map_id 等迁移字段——v1 时代旧档可能缺失，缺了也只按可迁移旧档处理。
func _is_authoritative_save(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var t := f.get_as_text()
	f.close()
	# 快速预检：有效 JSON 存档必须以 { 开头（避免解析 "corrupt"/"stale" 产生 ERROR 日志）
	if t.is_empty() or not t.begins_with("{"):
		return false
	var parsed: Variant = JSON.parse_string(t)
	if not parsed is Dictionary:
		return false
	var d: Dictionary = parsed
	# 核心身份：version 必须存在且 1..21
	if not d.has("version"):
		return false
	var version_value: Variant = d.get("version")
	if not (version_value is int or version_value is float):
		return false
	if int(version_value) < 1 or int(version_value) > 21:
		return false
	# 核心身份字段（任一缺失即不足以作为权威正式档）
	for core_key: String in ["gold", "level"]:
		if not d.has(core_key):
			return false
	# 完整语义校验（存在字段的类型/范围）
	return _validate_save_schema_lenient(d)


func _build_save_payload() -> Dictionary:
	return {
		"version": 21, "gold": gold, "magic_stones": magic_stones,
		"inventory": inventory, "warehouse": warehouse, "level": level,
		"experience": experience, "military_merit": military_merit,
		"nobility_merit": nobility_merit, "affection": affection,
		"current_day": current_day, "current_time_used": current_time_used,
		"completed_daily_tasks": completed_daily_tasks, "current_map_id": current_map_id,
		"equipment": equipment, "base_stats": base_stats,
		"player_current_hp": player_current_hp, "player_current_stamina": player_current_stamina,
		"loot_queue": loot_queue, "pets": pets, "next_pet_instance_id": next_pet_instance_id,
		"research": research, "quest_states": quest_states, "unlocked_maps": unlocked_maps,
		"learned_skills": learned_skills, "last_princess_gift_day": last_princess_gift_day,
		"last_princess_chat_day": last_princess_chat_day,
		"last_military_salary_day": last_military_salary_day,
		"last_pk_race_day": last_pk_race_day, "pk_race_active": pk_race_active,
		"war_soul_maze_active": war_soul_maze_active,
		"war_soul_guardian_revealed": war_soul_guardian_revealed,
		"story_flags": story_flags, "fuwa_event": fuwa_event,
		"demon_campaign": demon_campaign, "owned_territory": owned_territory,
		"last_territory_challenge_day": last_territory_challenge_day,
		"last_territory_reward_day": last_territory_reward_day,
	}




func _validate_save_schema(parsed: Variant) -> bool:
	# P0-2：38 字段完整类型 + 范围校验（用于 save_game 临时文件严格校验）
	return _validate_save_schema_impl(parsed, true)

func _validate_save_schema_lenient(parsed: Variant) -> bool:
	# P0-2：宽松校验（用于 load_game，允许旧版存档缺失字段，只校验存在字段的类型）
	return _validate_save_schema_impl(parsed, false)

## 整数严格校验：只允许 int，或数值恰为整数的 float（1.0 允许，1.5/21.9 拒绝，不静默截断）
func _is_integer_like(v: Variant) -> bool:
	if v is int:
		return true
	if v is float:
		return v == floorf(v)
	return false


func _validate_save_schema_impl(parsed: Variant, strict: bool) -> bool:
	if not parsed is Dictionary:
		return false
	var d: Dictionary = parsed
	# 严格模式：键完整性（save_game 临时文件必须有全部 38 键）
	if strict:
		for key: String in SAVE_SCHEMA_KEYS:
			if not d.has(key):
				return false
	# 数值字段：整数严格校验（1.5/21.9 拒绝，不 int() 静默截断）+ 明确范围规则
	var int_fields := ["version", "gold", "magic_stones", "level", "experience",
		"military_merit", "nobility_merit", "affection", "current_day", "current_time_used",
		"player_current_hp", "player_current_stamina", "next_pet_instance_id",
		"last_princess_gift_day", "last_princess_chat_day", "last_military_salary_day",
		"last_pk_race_day", "last_territory_challenge_day", "last_territory_reward_day"]
	for field: String in int_fields:
		if not d.has(field):
			continue
		var v: Variant = d.get(field)
		if not _is_integer_like(v):
			return false  # 小数（非整数值）拒绝：gold=1.5 / version=21.5 等
	# 范围规则（存在字段必须满足；负数/越界一律拒绝，不 clamp 不截断）
	if d.has("version"):
		var version_i := int(d.get("version"))
		if version_i < 1 or version_i > 21:
			return false  # 宽松模式：version 1..21 允许（支持旧版迁移）；严格模式由调用方检查 == 21
	for nonneg_field: String in ["gold", "magic_stones", "experience", "military_merit",
		"nobility_merit", "affection", "player_current_hp", "player_current_stamina",
		"last_princess_gift_day", "last_princess_chat_day", "last_military_salary_day",
		"last_pk_race_day", "last_territory_challenge_day", "last_territory_reward_day"]:
		if d.has(nonneg_field) and int(d.get(nonneg_field)) < 0:
			return false  # 负金币/负魔石/负经验/负体力/负生命等拒绝
	if d.has("level") and int(d.get("level")) < 1: return false
	if d.has("current_day") and int(d.get("current_day")) < 1: return false
	if d.has("current_time_used") and (int(d.get("current_time_used")) < 0 or int(d.get("current_time_used")) >= DAY_TIME):
		return false  # 越界日期时间拒绝
	if d.has("next_pet_instance_id") and int(d.get("next_pet_instance_id")) < 1: return false
	# String/Bool/Array/Dictionary 类型校验（只校验存在的字段）
	if d.has("current_map_id") and not d.get("current_map_id") is String: return false
	if d.has("owned_territory") and not d.get("owned_territory") is String: return false
	for bfield: String in ["pk_race_active", "war_soul_maze_active", "war_soul_guardian_revealed"]:
		if d.has(bfield) and not d.get(bfield) is bool: return false
	for afield: String in ["inventory", "warehouse", "loot_queue", "pets"]:
		if d.has(afield) and not d.get(afield) is Array: return false
	for dfield: String in ["completed_daily_tasks", "equipment", "base_stats", "research",
		"quest_states", "unlocked_maps", "learned_skills", "story_flags", "fuwa_event",
		"demon_campaign"]:
		if d.has(dfield) and not d.get(dfield) is Dictionary: return false
	if d.has("inventory") and (d.get("inventory") as Array).size() > INVENTORY_SIZE: return false
	if d.has("warehouse") and (d.get("warehouse") as Array).size() > WAREHOUSE_SIZE: return false
	return true


func _deep_compare_save(read_back: Dictionary, payload: Dictionary) -> bool:
	# DTO 深比较：读回 JSON 文本与原始 payload JSON 文本完全一致
	return JSON.stringify(read_back, "\t") == JSON.stringify(payload, "\t")



func _normalize_item(raw_item: Dictionary) -> Dictionary:
	var item_id := str(raw_item.get("item_id", ""))
	if item_id.is_empty() or not item_database.has(item_id):
		return {}
	var normalized := {"item_id": item_id, "quantity": maxi(1, int(raw_item.get("quantity", 1)))}
	var category := str(get_item_definition(item_id).get("category", ""))
	if category == "ore":
		normalized["quantity"] = 1
		normalized["ore_quality"] = clampi(int(raw_item.get("ore_quality", 1)), 1, 10)
	if category == "equipment":
		normalized["quantity"] = 1
		normalized["drop_level"] = clampi(int(raw_item.get("drop_level", 1)), 1, 125)
		var raw_enhancement: Variant = raw_item.get("enhancement", {})
		var instance := _create_equipment_enhancement(item_id)
		if raw_enhancement is Dictionary:
			for field_name in ["quality_level", "magic_soul_level", "heaven_soul_level", "earth_soul_level", "socket_count"]:
				instance[field_name] = maxi(0, int(raw_enhancement.get(field_name, instance[field_name])))
			instance.war_soul_active = bool(raw_enhancement.get("war_soul_active", false))
		normalized["enhancement"] = instance
	return normalized


func _normalize_container(raw_items: Array, target_size: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in target_size:
		if index < raw_items.size() and raw_items[index] is Dictionary and not raw_items[index].is_empty():
			result.append(_normalize_item(raw_items[index]))
		else:
			result.append({})
	return result


## 纯构造：从存档解析 pets/next_pet_instance_id/research（不读写全局状态）。
## 三个字段独立迁移——pets 缺失只回退默认幻兽组，不连带丢弃独立存在的 research/next_pet_instance_id。
## 返回 {"pets": Array, "next_pet_instance_id": int, "research": Dictionary}。供 load_game DTO 阶段使用。
func _build_pets_dto(parsed: Dictionary) -> Dictionary:
	# pets 独立迁移：缺失/无效 → 默认幻兽组；否则逐宠规范化
	var result: Array[Dictionary] = []
	var loaded_pets: Variant = parsed.get("pets", null)
	if loaded_pets is Array and loaded_pets.size() <= int(pet_service.config.get("inventory_capacity", 100)):
		var used_ids: Dictionary = {}
		var deployed_count := 0
		var legacy_combined_default := int(parsed.get("version", 0)) < 21
		for raw_pet: Variant in loaded_pets:
			if not raw_pet is Dictionary:
				continue
			var pet := pet_service.normalize_pet(raw_pet)
			if legacy_combined_default and not raw_pet.has("combined") and bool(pet.get("deployed", false)):
				pet.combined = true
			if pet.is_empty():
				continue
			var instance_id := int(pet.instance_id)
			if used_ids.has(instance_id):
				continue
			used_ids[instance_id] = true
			if bool(pet.deployed):
				deployed_count += 1
				if deployed_count > int(pet_service.config.get("deployed_capacity", 2)):
					pet.deployed = false
					pet.combined = false
			result.append(pet)
	if result.is_empty() and (loaded_pets == null or not (loaded_pets is Array)):
		# pets 字段缺失/顶层无效：回退默认幻兽组（仅 pets 回退，不影响 research/next_pet_instance_id）
		result = _default_pets_dto().pets
	# next_pet_instance_id 独立迁移：由宠物最高实例 ID + 存档值推导（完全不读运行状态）
	var highest_id := 0
	for pet: Dictionary in result:
		highest_id = maxi(highest_id, int(pet.instance_id))
	var saved_next: Variant = parsed.get("next_pet_instance_id", null)
	var next_id := highest_id + 1
	if saved_next != null and _is_integer_like(saved_next) and int(saved_next) >= 1:
		next_id = maxi(next_id, int(saved_next))
	# research 独立迁移：缺失/无效 → 默认研究状态
	var loaded_research: Variant = parsed.get("research", null)
	var research_dto := pet_service.default_research_state()
	if loaded_research is Dictionary:
		research_dto = pet_service.normalize_research(loaded_research)
	return {"pets": result, "next_pet_instance_id": next_id, "research": research_dto}


## 纯计算：由 DTO 的 base_stats/equipment 计算最大 HP（不读全局状态）。
## 与 get_player_stats 的 max_hp 部分一致（宠物/技能不增加 max_hp）。
func _compute_max_hp_from_dto(dto_base_stats: Dictionary, dto_equipment: Dictionary) -> int:
	var maximum := maxi(1, int(dto_base_stats.get("max_hp", 1)))
	for equipment_slot: String in EQUIPMENT_SLOTS:
		var item: Dictionary = dto_equipment.get(equipment_slot, {})
		if item.is_empty():
			continue
		var item_id := str(item.get("item_id", ""))
		var definition := get_item_definition(item_id)
		var instance: Dictionary = item.get("enhancement", enhancement.create_equipment_instance(item_id))
		var multiplier := enhancement.stat_multiplier(instance)
		maximum += roundi(int(definition.get("max_hp", 0)) * multiplier)
	return maxi(1, maximum)

func load_game() -> bool:
	# v1.40 整改：先完整解析+校验+纯构造 DTO，全部通过后一次性提交内存状态。
	# 校验失败时全局状态完全不变（内存不变）。
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false  # 顶层类型错误：内存不变
	var p: Dictionary = parsed
	# 宽松 schema 校验（存在字段的类型/范围；"gold":"abc" 被拒绝）
	if not _validate_save_schema_lenient(p):
		return false
	# 版本校验：version 必须存在且 1..21（空 {} 或缺 version 的文件不是存档）
	if not p.has("version"):
		return false
	var version_value: Variant = p.get("version")
	if not (version_value is int or version_value is float) or int(version_value) < 1 or int(version_value) > 21:
		return false
	# 核心身份字段（与 _is_authoritative_save 同判据，防止 {} 等残缺文件通过）
	for core_key: String in ["gold", "level"]:
		if not p.has(core_key):
			return false
	# DTO 纯构造（只读 p + 只读配置表/服务；不读不写运行中全局状态）
	var dto := _build_load_dto(p)
	if dto.is_empty():
		return false  # 字段完整性失败：内存不变
	# DTO 键完整性：38 个持久键必须齐全（pets/research/next_pet_instance_id 已进 DTO）
	for key: String in SAVE_SCHEMA_KEYS:
		if not dto.has(key):
			return false
	# ========== 全部校验通过：一次性提交内存（纯赋值，无计算无中间读取）==========
	_commit_load_dto(dto)
	return true


## DTO 纯构造：只读存档 p 与只读配置表/服务，返回 38 键完整 DTO；
## 任何字段完整性失败返回 {}（调用方保持内存不变）。
func _build_load_dto(p: Dictionary) -> Dictionary:
	var loaded_inventory: Variant = p.get("inventory", [])
	if not loaded_inventory is Array or loaded_inventory.size() > INVENTORY_SIZE:
		return {}
	var loaded_warehouse: Variant = p.get("warehouse", [])
	if not loaded_warehouse is Array or loaded_warehouse.size() > WAREHOUSE_SIZE:
		return {}
	var loaded_player_hp: Variant = p.get("player_current_hp", null)
	var loaded_player_stamina: Variant = p.get("player_current_stamina", null)
	# 默认值统一取自 SAVE_SCHEMA_DEFAULTS（可变容器深拷贝，杜绝 {} 字面量）
	var dto := {}
	for key: String in SAVE_SCHEMA_KEYS:
		var default_value: Variant = SAVE_SCHEMA_DEFAULTS[key]
		if default_value is Dictionary or default_value is Array:
			dto[key] = default_value.duplicate(true)
		else:
			dto[key] = default_value
	# 标量（clamp 语义与原 load 一致）
	dto["gold"] = int(p.get("gold", SAVE_SCHEMA_DEFAULTS["gold"]))
	dto["magic_stones"] = int(p.get("magic_stones", SAVE_SCHEMA_DEFAULTS["magic_stones"]))
	dto["level"] = maxi(1, int(p.get("level", SAVE_SCHEMA_DEFAULTS["level"])))
	dto["experience"] = maxi(0, int(p.get("experience", SAVE_SCHEMA_DEFAULTS["experience"])))
	dto["military_merit"] = maxi(0, int(p.get("military_merit", SAVE_SCHEMA_DEFAULTS["military_merit"])))
	dto["nobility_merit"] = maxi(0, int(p.get("nobility_merit", SAVE_SCHEMA_DEFAULTS["nobility_merit"])))
	dto["affection"] = maxi(0, int(p.get("affection", SAVE_SCHEMA_DEFAULTS["affection"])))
	dto["current_day"] = maxi(1, int(p.get("current_day", SAVE_SCHEMA_DEFAULTS["current_day"])))
	dto["current_time_used"] = clampi(int(p.get("current_time_used", SAVE_SCHEMA_DEFAULTS["current_time_used"])), 0, DAY_TIME - 1)
	# completed_daily_tasks
	var loaded_daily_tasks: Variant = p.get("completed_daily_tasks", SAVE_SCHEMA_DEFAULTS["completed_daily_tasks"])
	if loaded_daily_tasks is Dictionary:
		dto["completed_daily_tasks"] = loaded_daily_tasks.duplicate(true)
	# 地图（spider_cave 迁移）
	var loaded_map_id := str(p.get("current_map_id", SAVE_SCHEMA_DEFAULTS["current_map_id"]))
	if loaded_map_id == "spider_cave":
		loaded_map_id = "cassano_city"
	dto["current_map_id"] = loaded_map_id
	# 装备（固定槽位 EQUIPMENT_SLOTS，不遍历运行时 equipment）
	var loaded_equipment: Variant = p.get("equipment", SAVE_SCHEMA_DEFAULTS["equipment"])
	if loaded_equipment is Dictionary:
		for equipment_slot: String in EQUIPMENT_SLOTS:
			var raw_equipped: Variant = loaded_equipment.get(equipment_slot, {})
			if raw_equipped is Dictionary:
				dto["equipment"][equipment_slot] = _normalize_item(raw_equipped)
			elif raw_equipped is String and not raw_equipped.is_empty():
				dto["equipment"][equipment_slot] = create_item_entry(raw_equipped)
			else:
				dto["equipment"][equipment_slot] = {}
	# 基础属性
	var loaded_stats: Variant = p.get("base_stats", SAVE_SCHEMA_DEFAULTS["base_stats"])
	if loaded_stats is Dictionary:
		for stat_name: String in ["max_hp", "attack", "defense", "luck"]:
			dto["base_stats"][stat_name] = int(loaded_stats.get(stat_name, dto["base_stats"][stat_name]))
	# 掉落队列
	var loaded_loot: Variant = p.get("loot_queue", [])
	if loaded_loot is Array:
		var validated_loot: Array[String] = []
		for item_id: Variant in loaded_loot:
			var normalized_loot := str(item_id)
			if item_database.has(normalized_loot) or not _parse_loot_equipment_token(normalized_loot).is_empty():
				validated_loot.append(normalized_loot)
		dto["loot_queue"] = validated_loot
	# story_flags（内部默认集中定义于 SAVE_SCHEMA_DEFAULTS）
	var loaded_story_flags: Variant = p.get("story_flags", {})
	if loaded_story_flags is Dictionary:
		for story_flag_id: String in dto["story_flags"]:
			dto["story_flags"][story_flag_id] = bool(loaded_story_flags.get(story_flag_id, dto["story_flags"][story_flag_id]))
	# fuwa_event / demon_campaign（纯 normalize）
	var loaded_fuwa_event: Variant = p.get("fuwa_event", {})
	dto["fuwa_event"] = normalize_fuwa_event(loaded_fuwa_event if loaded_fuwa_event is Dictionary else {})
	var loaded_demon_campaign: Variant = p.get("demon_campaign", {})
	if loaded_demon_campaign is Dictionary:
		for campaign_flag_id: String in dto["demon_campaign"]:
			dto["demon_campaign"][campaign_flag_id] = bool(loaded_demon_campaign.get(campaign_flag_id, dto["demon_campaign"][campaign_flag_id]))
	# 其余标量（默认统一取自 SAVE_SCHEMA_DEFAULTS）
	dto["owned_territory"] = str(p.get("owned_territory", SAVE_SCHEMA_DEFAULTS["owned_territory"]))
	if not str(dto["owned_territory"]).is_empty() and get_territory(str(dto["owned_territory"])).is_empty():
		dto["owned_territory"] = str(SAVE_SCHEMA_DEFAULTS["owned_territory"])
	dto["last_territory_challenge_day"] = maxi(0, int(p.get("last_territory_challenge_day", SAVE_SCHEMA_DEFAULTS["last_territory_challenge_day"])))
	dto["last_territory_reward_day"] = maxi(0, int(p.get("last_territory_reward_day", SAVE_SCHEMA_DEFAULTS["last_territory_reward_day"])))
	dto["last_princess_gift_day"] = maxi(0, int(p.get("last_princess_gift_day", SAVE_SCHEMA_DEFAULTS["last_princess_gift_day"])))
	dto["last_princess_chat_day"] = maxi(0, int(p.get("last_princess_chat_day", SAVE_SCHEMA_DEFAULTS["last_princess_chat_day"])))
	dto["last_military_salary_day"] = maxi(0, int(p.get("last_military_salary_day", SAVE_SCHEMA_DEFAULTS["last_military_salary_day"])))
	dto["last_pk_race_day"] = maxi(0, int(p.get("last_pk_race_day", SAVE_SCHEMA_DEFAULTS["last_pk_race_day"])))
	dto["pk_race_active"] = bool(p.get("pk_race_active", SAVE_SCHEMA_DEFAULTS["pk_race_active"]))
	dto["war_soul_maze_active"] = bool(p.get("war_soul_maze_active", SAVE_SCHEMA_DEFAULTS["war_soul_maze_active"]))
	dto["war_soul_guardian_revealed"] = bool(p.get("war_soul_guardian_revealed", SAVE_SCHEMA_DEFAULTS["war_soul_guardian_revealed"]))
	# quest_states / unlocked_maps / learned_skills
	var loaded_quests: Variant = p.get("quest_states", {})
	dto["quest_states"] = quest_service.normalize_states(loaded_quests if loaded_quests is Dictionary else {})
	var loaded_unlocked_maps: Variant = p.get("unlocked_maps", {})
	if loaded_unlocked_maps is Dictionary:
		for locked_map_id: String in dto["unlocked_maps"]:
			dto["unlocked_maps"][locked_map_id] = bool(loaded_unlocked_maps.get(locked_map_id, dto["unlocked_maps"][locked_map_id]))
	var loaded_skills: Variant = p.get("learned_skills", {})
	dto["learned_skills"] = skill_service.normalize_learned(loaded_skills if loaded_skills is Dictionary else {})
	# 关系技能刷新（原 _refresh_relationship_skills 的纯调用版：只读 DTO 内值）
	dto["learned_skills"] = skill_service.unlock_relationship_skills(dto["learned_skills"], int(dto["affection"]))
	# pets / next_pet_instance_id / research（纯构造）
	var pets_dto := _build_pets_dto(p)
	dto["pets"] = pets_dto.pets
	dto["next_pet_instance_id"] = int(pets_dto.next_pet_instance_id)
	dto["research"] = pets_dto.research
	# 地图安全校正（用 DTO 内值计算，不依赖已提交的全局状态）
	var final_map := str(dto["current_map_id"])
	if final_map in ["green_field", "grass_reward", "treeheart_city"] and not bool(dto["fuwa_event"].get("round_active", false)) and int(dto["fuwa_event"].get("found_count", 0)) < FUWA_NAMES.size():
		final_map = "cassano_city"
	if final_map in ["pk_arena", "pk_arena_2", "pk_arena_3"] and not bool(dto["pk_race_active"]):
		final_map = "cassano_city"
	if final_map == "war_soul_seal_maze" and (not bool(dto["war_soul_maze_active"]) or bool(dto["story_flags"].get("war_soul_secret_unlocked", false))):
		final_map = "cassano_city"
		dto["war_soul_maze_active"] = false
		dto["war_soul_guardian_revealed"] = false
	dto["current_map_id"] = final_map
	# HP/体力（用 DTO 内 base_stats/equipment/level 纯计算；缺失时填满，语义与原实现一致）
	var dto_max_hp := _compute_max_hp_from_dto(dto["base_stats"], dto["equipment"])
	dto["player_current_hp"] = dto_max_hp if loaded_player_hp == null else clampi(int(loaded_player_hp), 0, dto_max_hp)
	var dto_max_stamina := 100 + 10 * maxi(1, int(dto["level"]))
	dto["player_current_stamina"] = dto_max_stamina if loaded_player_stamina == null else clampi(int(loaded_player_stamina), 0, dto_max_stamina)
	# inventory/warehouse 规范化（固定容器尺寸）
	dto["inventory"] = _normalize_container(loaded_inventory, INVENTORY_SIZE)
	dto["warehouse"] = _normalize_container(loaded_warehouse, WAREHOUSE_SIZE)
	return dto


## 一次性提交：纯赋值序列，不包含任何计算与条件读取（所有派生值已在 DTO 阶段算好）。
func _commit_load_dto(dto: Dictionary) -> void:
	gold = int(dto["gold"])
	magic_stones = int(dto["magic_stones"])
	level = int(dto["level"])
	experience = int(dto["experience"])
	military_merit = int(dto["military_merit"])
	nobility_merit = int(dto["nobility_merit"])
	affection = int(dto["affection"])
	current_day = int(dto["current_day"])
	current_time_used = int(dto["current_time_used"])
	completed_daily_tasks = dto["completed_daily_tasks"]
	current_map_id = str(dto["current_map_id"])
	player_current_hp = int(dto["player_current_hp"])
	player_current_stamina = int(dto["player_current_stamina"])
	equipment = dto["equipment"]
	base_stats = dto["base_stats"]
	loot_queue.clear()
	for loot_id: String in dto["loot_queue"]:
		loot_queue.append(loot_id)
	story_flags = dto["story_flags"]
	fuwa_event = dto["fuwa_event"]
	demon_campaign = dto["demon_campaign"]
	owned_territory = str(dto["owned_territory"])
	last_territory_challenge_day = int(dto["last_territory_challenge_day"])
	last_territory_reward_day = int(dto["last_territory_reward_day"])
	last_princess_gift_day = int(dto["last_princess_gift_day"])
	last_princess_chat_day = int(dto["last_princess_chat_day"])
	last_military_salary_day = int(dto["last_military_salary_day"])
	last_pk_race_day = int(dto["last_pk_race_day"])
	pk_race_active = bool(dto["pk_race_active"])
	war_soul_maze_active = bool(dto["war_soul_maze_active"])
	war_soul_guardian_revealed = bool(dto["war_soul_guardian_revealed"])
	quest_states = dto["quest_states"]
	unlocked_maps = dto["unlocked_maps"]
	learned_skills = dto["learned_skills"]
	research = dto["research"]
	# 幻兽（DTO 纯构造结果，一次性写入）
	pets = dto["pets"]
	# P0-2 拒签整改：精确赋值 DTO 计算值，不读取读档前运行状态（同一存档加载结果与加载前状态无关）
	next_pet_instance_id = int(dto["next_pet_instance_id"])
	inventory = dto["inventory"]
	warehouse = dto["warehouse"]
	pending_territory_challenge = ""
	# 信号
	inventory_changed.emit()
	currency_changed.emit()
	progression_changed.emit()
	equipment_changed.emit()
	loot_changed.emit()
	pets_changed.emit()
	research_changed.emit()
	social_changed.emit()
	quests_changed.emit()
	skills_changed.emit()
	territory_changed.emit()
	story_changed.emit()
	time_changed.emit()
