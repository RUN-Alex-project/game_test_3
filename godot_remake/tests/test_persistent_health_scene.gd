extends Node

const BattleSession = preload("res://scripts/battle_session.gd")


func _ready() -> void:
	var session := BattleSession.new("spider", {
		"max_hp":100,
		"current_hp":80,
		"attack":1,
		"defense":0,
		"dodge_percent":0,
		"battle_pets":[
			{"instance_id":101, "name":"第一幻兽", "current_hp":2, "max_hp":2, "attack":1, "defense":0},
			{"instance_id":102, "name":"第二幻兽", "current_hp":2, "max_hp":2, "attack":1, "defense":0},
		],
	}, 7)
	var first := session.perform_turn(1.0, 1.0, 1.0)
	assert(first.monster_target == "pet" and first.target_pet_id == 101, "enemy did not target the first deployed pet")
	assert(session.player_hp == 80 and session.pet_states[0].current_hp == 0, "first pet damage was not isolated from player HP")
	assert(first.pet_deaths == [101], "first pet death was not reported exactly once")
	var second := session.perform_turn(1.0, 1.0, 1.0)
	assert(second.monster_target == "pet" and second.target_pet_id == 102, "enemy did not move to the second deployed pet")
	assert(session.player_hp == 80 and session.pet_states[1].current_hp == 0, "second pet damage was not isolated from player HP")
	var third := session.perform_turn(1.0, 1.0, 1.0)
	assert(third.monster_target == "player" and session.player_hp < 80, "enemy did not target the player after both pets died")

	var first_id := int(GameState.pets[0].instance_id)
	var first_max_hp := int(GameState.pet_service.get_stats(GameState.pets[0]).max_hp)
	GameState.player_current_hp = 77
	GameState.commit_battle_health(33, [{"instance_id":first_id, "current_hp":1}])
	assert(GameState.player_current_hp == 33 and GameState.pets[0].current_hp == 1, "battle health did not persist into GameState")
	GameState.commit_battle_health(999999, [{"instance_id":first_id, "current_hp":999999}])
	assert(GameState.player_current_hp == GameState.get_player_stats().max_hp, "player HP was not clamped to maximum")
	assert(GameState.pets[0].current_hp == first_max_hp, "pet HP was not clamped to maximum")

	GameState.base_stats.luck = 100
	var pet_penalty := GameState.apply_pet_death_penalty([first_id, first_id])
	assert(pet_penalty.deaths == 1 and pet_penalty.luck_lost == 10 and GameState.base_stats.luck == 90, "pet death luck penalty or deduplication is incorrect")
	GameState.base_stats.luck = 10
	pet_penalty = GameState.apply_pet_death_penalty([first_id])
	assert(pet_penalty.forced_retreat and GameState.base_stats.luck == 0, "zero luck did not force retreat")

	GameState.base_stats.luck = 100
	GameState.experience = 1000
	GameState.player_current_hp = 10
	var player_penalty := GameState.apply_player_defeat_penalty()
	assert(player_penalty.luck_lost == 10 and player_penalty.experience_lost == 50, "player defeat penalty is incorrect")
	assert(GameState.base_stats.luck == 90 and GameState.experience == 950 and GameState.player_current_hp == 0, "player defeat state did not persist")

	var fruit_slot := _find_item("fruit")
	assert(fruit_slot >= 0, "starting fruit is missing")
	var fruit_before := GameState.count_item("fruit")
	assert(GameState.use_inventory_item(fruit_slot), "fruit could not heal a defeated player")
	assert(GameState.player_current_hp == GameState.get_player_stats().max_hp, "fruit did not fully heal the player")
	assert(GameState.count_item("fruit") == fruit_before - 1, "fruit was not consumed exactly once")
	assert(not GameState.use_inventory_item(_find_item("fruit")), "fruit was consumed while player HP was already full")

	GameState.player_current_hp = 1
	for pet_index in GameState.pets.size():
		GameState.pets[pet_index].current_hp = 0
	GameState.advance_day()
	assert(GameState.player_current_hp == 1, "new day should not heal the player directly")
	for pet in GameState.pets:
		assert(int(pet.current_hp) == int(GameState.pet_service.get_stats(pet).max_hp), "new day did not fully heal every pet")

	print("PASS persistent player/pet HP, target order, death penalties, fruit healing, and next-day pet recovery")
	get_tree().quit(0)


func _find_item(item_id: String) -> int:
	for index in GameState.inventory.size():
		if str(GameState.inventory[index].get("item_id", "")) == item_id:
			return index
	return -1
