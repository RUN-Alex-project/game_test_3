extends Node

const PetService = preload("res://scripts/pet_service.gd")


func _ready() -> void:
	var service := PetService.new()
	var research_config: Dictionary = service.config.research
	assert(int(service.config.inventory_capacity) == 100, "original pet inventory capacity is incorrect")
	assert(int(service.config.deployed_capacity) == 2, "deployed pet capacity is incorrect")
	assert(int(research_config.technology_level_cap) == 300, "modified research technology cap is incorrect")
	assert(int(research_config.production_rate_cap) == 6, "original research production cap is incorrect")

	var state := service.default_research_state()
	assert(state.technology_level == 10.0 and state.production_rate == 0, "research initial state is incorrect")
	for index in 10:
		state = service.fund_research(state)
	assert(state.technology_level == 20.0 and state.production_rate == 1, "level 20 production unlock is incorrect")
	assert(service.research_pet_quality(state) == 1500.0, "research pet score formula is incorrect")
	state = service.produce(state, 3)
	assert(state.stock == 3, "daily research production is incorrect")
	assert(service.production_task_cost(state) == 2, "first production task soul king cost is incorrect")
	var task_one := service.complete_production_task(state)
	assert(task_one.success and task_one.state.production_rate == 3, "first modified production task did not add 2")
	assert(service.production_task_cost(task_one.state) == 4, "second production task cost is incorrect")
	var task_two := service.complete_production_task(task_one.state)
	var task_three := service.complete_production_task(task_two.state)
	assert(task_two.state.production_rate == 5 and task_three.state.production_rate == 6, "production tasks did not clamp at original cap")
	assert(not service.complete_production_task(task_three.state).success, "production task exceeded rate cap")

	var limited_pet := service.create_pet("attack_defense_light", 1)
	var limited_result := service.grant_experience(limited_pet, 999999, 1)
	assert(limited_result.pet.level == 11, "pet exceeded player level plus 10")
	var main_pet := service.create_pet("attack_defense_light", 2, 1600.0)
	main_pet.level = 50
	var secondary_pet := service.create_pet("attack_defense_heavy", 3, 600.0)
	secondary_pet.base_attack = 20
	secondary_pet.growth_attack = 10
	assert(service.fusion_requirement(main_pet) == 550, "original fusion score requirement is incorrect")
	var fusion := service.fuse(main_pet, secondary_pet)
	assert(fusion.success and fusion.pet.level == 1 and fusion.pet.reincarnations == 1, "fusion did not reincarnate the main pet")
	assert(fusion.pet.base_attack == 19 and fusion.pet.growth_attack == 9, "fusion inheritance factors are incorrect")

	assert(GameState.pets.size() == 2 and GameState.pets[0].deployed and GameState.pets[1].deployed, "starting deployed pets are incorrect")
	var player_stats := GameState.get_player_stats()
	assert(player_stats.pet_attack == 13 and player_stats.pet_combat_power == 44, "deployed pet stats did not enter player combat power")
	GameState.research = service.fund_research(service.default_research_state(), 10.0)
	assert(GameState.advance_research_production(1) == 1, "integrated research production failed")
	var stones_before := GameState.magic_stones
	var purchase := GameState.buy_research_pet()
	assert(purchase.success and GameState.pets.size() == 3, "research pet purchase failed")
	assert(GameState.magic_stones == stones_before - 1000, "research pet price is incorrect")
	var research_pet_id := int(purchase.pet.instance_id)
	assert(not GameState.set_pet_deployed(research_pet_id, true), "third pet was deployed beyond capacity")
	assert(GameState.set_pet_deployed(int(GameState.pets[0].instance_id), false), "starting pet recall failed")
	assert(GameState.set_pet_deployed(research_pet_id, true), "research pet deployment failed")
	assert(GameState.train_pet_with_exp_ball(research_pet_id), "pet experience ball training failed")
	assert(GameState.pets[GameState.get_pet_index(research_pet_id)].level == 11, "experience ball ignored pet level limit")
	assert(GameState.set_pet_deployed(research_pet_id, false), "research pet recall failed")
	var main_id := int(GameState.pets[0].instance_id)
	GameState.pets[0].level = 50
	var integrated_fusion := GameState.fuse_pets(main_id, research_pet_id)
	assert(integrated_fusion.success and GameState.pets.size() == 2, "integrated fusion did not consume the secondary pet")
	assert(GameState.pets[GameState.get_pet_index(main_id)].reincarnations == 1, "integrated fusion did not preserve main pet identity")

	GameState.research = service.fund_research(service.default_research_state(), 10.0)
	assert(GameState.add_item("soul_king", 2), "soul king task fixture failed")
	var research_task := GameState.complete_research_production_task()
	assert(research_task.success and GameState.research.production_rate == 3, "integrated production task failed")
	assert(GameState.count_item("soul_king") == 0, "production task did not consume increasing soul king cost")
	var submitted_id := int(GameState.pets[1].instance_id)
	GameState.pets[1].deployed = false
	GameState.pets[1].quality_score = 1500.0
	var stones_before_submission := GameState.magic_stones
	var merit_before_submission := GameState.military_merit
	var submission := GameState.submit_pet_for_daily_task(submitted_id)
	assert(submission.success and submission.magic_stones == 10000, "15-star pet submission reward is incorrect")
	assert(GameState.magic_stones == stones_before_submission + 10000 and GameState.military_merit == merit_before_submission + 1000, "pet submission settlement is incorrect")
	assert(not GameState.submit_pet_for_daily_task(int(GameState.pets[0].instance_id)).success, "pet submission daily limit failed")
	print("PASS pet instances, level limits, deployment, fusion, research formulas, production +2, and purchase")
	get_tree().quit(0)
