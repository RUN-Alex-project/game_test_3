extends Node

const BattleSession = preload("res://scripts/battle_session.gd")


func _ready() -> void:
	assert(GameState.pets.size() == 2, "starting pet pair is missing")
	assert(GameState.pets[0].deployed and GameState.pets[1].deployed, "starting pets must be deployed")
	assert(GameState.pets[0].combined and GameState.pets[1].combined, "new-game pets must start combined like the SWF")

	var first_id := int(GameState.pets[0].instance_id)
	var initial_stats := GameState.get_player_stats()
	assert(initial_stats.attack == 73 and initial_stats.defense == 43, "combined pets did not merge attack and defense into the player")
	assert(initial_stats.pet_attack == 13 and initial_stats.battle_pets.size() == 2, "combined pet summary is incorrect")
	var initial_pet_power := int(initial_stats.pet_combat_power)

	assert(GameState.set_pet_combined(first_id, false), "top-card separation failed")
	var separated_stats := GameState.get_player_stats()
	assert(separated_stats.attack == 65 and separated_stats.defense == 38, "separated pet still modified combat stats")
	assert(separated_stats.battle_pets.size() == 1, "separated pet remained a damage shield")
	assert(separated_stats.pet_combat_power == initial_pet_power, "deployed separated pet stopped contributing combat power")

	assert(GameState.set_pet_deployed(first_id, false), "combined pet recall failed")
	assert(not GameState.pets[GameState.get_pet_index(first_id)].combined, "recall did not clear combination state")
	assert(GameState.set_pet_deployed(first_id, true), "pet redeployment failed")
	assert(not GameState.pets[GameState.get_pet_index(first_id)].combined, "ordinary deployment must wait for the player to combine")
	assert(GameState.set_pet_combined(first_id, true), "recombined pet was rejected")
	var first_index := GameState.get_pet_index(first_id)
	var restored_hp := int(GameState.pets[first_index].current_hp)
	GameState.pets[first_index].current_hp = 0
	var dead_pet_stats := GameState.get_player_stats()
	assert(dead_pet_stats.attack == 65 and dead_pet_stats.defense == 38, "defeated combined pet still modified player combat stats")
	assert(dead_pet_stats.battle_pets.size() == 2, "defeated combined pet health was not preserved for battle state")
	GameState.pets[first_index].current_hp = restored_hp

	var shield_session := BattleSession.new("spider", {
		"max_hp":100,
		"current_hp":100,
		"attack":1,
		"defense":100,
		"dodge_percent":0,
		"battle_pets":[
			{"instance_id":501, "name":"合体幻兽", "current_hp":100, "max_hp":100, "attack":999, "defense":0},
		],
	}, 13)
	var shield_turn := shield_session.perform_turn(1.0, 1.0, 1.0)
	var expected_shield_damage: int = shield_session.combat.calculate_damage(int(shield_session.monster.attack), 100, 1.0)
	assert(shield_turn.pet_damage == 0 and shield_turn.pet_attacks.is_empty(), "combined pet still performed a duplicate independent attack")
	assert(shield_turn.monster_target == "pet" and shield_turn.target_pet_id == 501, "combined pet did not intercept the monster attack")
	assert(shield_turn.pet_damage_taken == expected_shield_damage, "shield damage did not use merged player defense")
	shield_session.pet_states[0].current_hp = 0
	shield_session.refresh_player_configuration({
		"max_hp":100,
		"current_hp":100,
		"attack":1,
		"defense":0,
		"dodge_percent":0,
		"battle_pets":[
			{"instance_id":501, "name":"defeated pet", "current_hp":0, "max_hp":100, "attack":999, "defense":0},
		],
	})
	assert(shield_session.player_stats.defense == 0 and shield_session._first_alive_pet_index() == -1, "live battle refresh kept defeated pet stats or shielding")

	assert(GameState.get_player_max_stamina() == 110 and GameState.player_current_stamina == 110, "level-one original stamina is not 110")
	GameState.learned_skills = {"flying_slash":1, "star_sword":1}
	assert(GameState.skill_stamina_cost("flying_slash") == 0, "basic flying slash should not consume stamina")
	assert(GameState.skill_stamina_cost("star_sword") == 10, "basic star sword stamina cost is incorrect")
	var stamina_result := GameState.try_use_skill_stamina("star_sword")
	assert(stamina_result.success and stamina_result.cost == 10 and GameState.player_current_stamina == 100, "star sword stamina was not consumed")
	GameState.learned_skills.flying_slash = 2
	GameState.learned_skills.star_sword = 2
	assert(GameState.skill_stamina_cost("flying_slash") == 5, "advanced flying slash stamina cost is incorrect")
	assert(GameState.skill_stamina_cost("star_sword") == 20, "advanced star sword stamina cost is incorrect")
	GameState.player_current_stamina = 0
	assert(not GameState.try_use_skill_stamina("star_sword").success, "skill was accepted without enough stamina")

	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(main.player_status_card.has("stamina_bar"), "player HUD did not restore the stamina row")
	assert(main.pet_status_cards.size() == 2, "two native pet cards are required")
	for card: Dictionary in main.pet_status_cards:
		assert(card.recall_button.text == "召回", "native pet recall button is missing")
		assert(card.combine_button.text == "解体", "combined starting pet did not expose the native separation action")
	assert(main.player_status_card.panel.position == Vector2(1, 4), "player card is not at the 4px top-safe-margin position")
	assert(main.pet_status_cards[0].panel.position == Vector2(198, 4), "first pet card is not at the 4px top-safe-margin position")
	assert(main.pet_status_cards[1].panel.position == Vector2(394, 4), "second pet card is not at the 4px top-safe-margin position")
	main.pet_status_cards[0].combine_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not GameState.pets[0].combined and main.pet_status_cards[0].combine_button.text == "合体", "HUD separation button was not wired to pet state")
	main.pet_status_cards[0].combine_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(GameState.pets[0].combined and main.pet_status_cards[0].combine_button.text == "解体", "HUD combination button was not wired to pet state")

	print("PASS native pet combine/separate HUD, merged combat, damage shielding, and stamina")
	get_tree().quit(0)
