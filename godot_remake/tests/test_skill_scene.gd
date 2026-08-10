extends Node

const SkillService = preload("res://scripts/skill_service.gd")
const BattleSession = preload("res://scripts/battle_session.gd")


func _ready() -> void:
	var service := SkillService.new()
	var learned := {}
	var basic := service.learn_result(learned, "skill_fighting_spirit")
	assert(basic.success and basic.learned.fighting_spirit == 1, "basic fighting spirit learning failed")
	assert(service.combat_power_percent(basic.learned) == 0.05, "basic fighting spirit bonus is incorrect")
	var advanced := service.learn_result(basic.learned, "advanced_fighting_spirit")
	assert(advanced.success and service.combat_power_percent(advanced.learned) == 0.35, "advanced fighting spirit bonus is incorrect")
	assert(not service.learn_result(advanced.learned, "skill_fighting_spirit").success, "lower-rank skill book downgraded a skill")
	learned = service.learn_result({}, "skill_flying_slash").learned
	assert(service.active_damage_multiplier(learned, "flying_slash") == 1.2, "basic flying slash damage is incorrect")
	learned = service.learn_result(learned, "advanced_flying_slash").learned
	assert(service.active_damage_multiplier(learned, "flying_slash") == 1.5, "advanced flying slash damage is incorrect")

	GameState.learned_skills.clear()
	var base_power := int(GameState.get_player_stats().combat_power)
	assert(GameState.add_item("skill_fighting_spirit"), "basic passive skill fixture failed")
	assert(GameState.learn_skill_from_item("skill_fighting_spirit").success, "integrated passive learning failed")
	assert(GameState.count_item("skill_fighting_spirit") == 0, "learned skill book was not consumed")
	assert(int(GameState.get_player_stats().combat_power) == base_power + roundi(base_power * 0.05), "passive skill combat power was not integrated")
	assert(GameState.add_item("advanced_fighting_spirit"), "advanced passive skill fixture failed")
	assert(GameState.learn_skill_from_item("advanced_fighting_spirit").success, "integrated advanced passive learning failed")
	assert(int(GameState.get_player_stats().skill_combat_power) == roundi(base_power * 0.35), "advanced passive combat power is incorrect")
	assert(GameState.learn_skill_from_item("skill_red").success, "starting active skill book could not be learned")

	var normal_battle := BattleSession.new("spider", {"max_hp":1000,"attack":100,"defense":100}, 1)
	var skill_battle := BattleSession.new("spider", {"max_hp":1000,"attack":100,"defense":100}, 1)
	var normal_turn := normal_battle.perform_turn(1.0, 1.0, 1.0)
	var skill_turn := skill_battle.perform_turn(1.0, 1.0, 1.0, 1.2)
	assert(skill_turn.player_damage > normal_turn.player_damage and skill_turn.skill_multiplier == 1.2, "active skill multiplier was not used in battle")
	print("PASS skill books, upgrade protection, passive combat power, and active battle damage")
	get_tree().quit(0)
