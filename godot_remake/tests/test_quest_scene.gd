extends Node

const QuestService = preload("res://scripts/quest_service.gd")


func _ready() -> void:
	var service := QuestService.new()
	var states := service.default_states()
	assert(states.dungeon_conquest.status == "available", "default dungeon quest state is incorrect")
	var accepted := service.accept(states, "dungeon_conquest")
	assert(accepted.success and accepted.states.dungeon_conquest.status == "active", "quest acceptance failed")
	states = accepted.states
	for monster_id in ["dungeon_boss", "dungeon_boss_2"]:
		var update := service.record_kill(states, monster_id)
		assert(update.changed, "quest kill was not recorded")
		states = update.states
	assert(states.dungeon_conquest.status == "active", "dungeon quest completed too early")
	states = service.record_kill(states, "dungeon_boss_3").states
	assert(states.dungeon_conquest.status == "ready", "dungeon quest did not become ready")
	assert(service.progress_lines(states, "dungeon_conquest").size() == 3, "quest progress summary is incomplete")
	var claim := service.claim(states, "dungeon_conquest")
	assert(claim.success and claim.states.dungeon_conquest.status == "completed", "quest claim failed")
	assert(service.reset_daily(claim.states).dungeon_conquest.status == "available", "daily quest reset failed")
	states = service.accept(service.default_states(), "border_raid").states
	for monster_id in ["snow_warrior", "snow_cavalry", "snow_officer"]:
		states = service.record_kill(states, monster_id).states
	assert(states.border_raid.status == "ready", "ice border quest progress is incorrect")

	GameState.quest_states = service.default_states()
	GameState.unlocked_maps = {"dungeon_floor_2":false, "dungeon_floor_3":false}
	assert(not GameState.can_enter_map("dungeon_floor_2"), "dungeon floor two started unlocked")
	GameState.apply_victory_rewards({"monster_id":"dungeon_boss"})
	assert(GameState.can_enter_map("dungeon_floor_2") and not GameState.can_enter_map("dungeon_floor_3"), "floor one victory did not unlock floor two exclusively")
	GameState.apply_victory_rewards({"monster_id":"dungeon_boss_2"})
	assert(GameState.can_enter_map("dungeon_floor_3"), "floor two victory did not unlock floor three")
	assert(GameState.accept_quest("spider_crisis"), "integrated story quest acceptance failed")
	for index in 3:
		GameState.apply_victory_rewards({"monster_id":"spider"})
	GameState.apply_victory_rewards({"monster_id":"spider_queen"})
	assert(GameState.quest_states.spider_crisis.status == "ready", "integrated battle progress failed")
	var experience_before := GameState.experience
	assert(GameState.claim_quest("spider_crisis").success, "integrated quest claim failed")
	assert(GameState.experience == experience_before + 10000 or GameState.level > 1, "quest experience reward was not applied")
	print("PASS quest acceptance, kill progress, claim, daily reset, and battle integration")
	get_tree().quit(0)
