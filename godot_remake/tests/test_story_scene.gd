extends Node


func _reset_story() -> void:
	GameState.story_flags = {
		"king_rescued": false,
		"princess_friend_gift_available": false,
		"maid_year_pig_available": true,
		"game_won": false,
	}
	GameState.last_princess_chat_day = 0


func _ready() -> void:
	_reset_story()
	GameState.level = 50
	GameState.current_day = 4
	assert(not GameState.can_enter_map("ice_border"), "snow border opened outside Friday before rescuing the king")
	GameState.current_day = 5
	assert(GameState.can_enter_map("ice_border"), "snow border did not open for the Friday raid")
	GameState.current_day = 6
	assert(not GameState.can_enter_map("ice_border"), "Friday access remained open on another weekday")

	GameState.nobility_merit = 0
	var rescue := GameState.rescue_king()
	assert(rescue.triggered and rescue.reward_type == "nobility_rank", "first king rescue did not trigger the rank reward")
	assert(GameState.get_nobility_rank().name == "王", "king rescue did not grant the King nobility rank")
	assert(GameState.can_enter_map("ice_border"), "rescuing the king did not permanently open the snow border")
	var stones_after_first_rescue := GameState.magic_stones
	assert(not GameState.rescue_king().triggered and GameState.magic_stones == stones_after_first_rescue, "king rescue reward could be claimed twice")

	_reset_story()
	GameState.nobility_merit = 100000
	var stones_before_high_rank_rescue := GameState.magic_stones
	var high_rank_rescue := GameState.rescue_king()
	assert(high_rank_rescue.reward_type == "magic_stones" and high_rank_rescue.magic_stones == 200000, "high-rank rescue reward is incorrect")
	assert(GameState.magic_stones == stones_before_high_rank_rescue + 200000, "high-rank rescue magic stones did not reach the wallet")

	_reset_story()
	GameState._initialize_pets()
	GameState.current_day = 9
	GameState.affection = 10
	var pets_before_chat := GameState.pets.size()
	var chat := GameState.chat_with_princess()
	assert(chat.success and chat.relationship_level == 2, "princess daily chat did not use the pre-chat relationship tier")
	assert(GameState.affection == 11 and GameState.pets.size() == pets_before_chat + 1, "princess chat did not add affection and the tier gift")
	assert(GameState.pets.back().template_id == "attack_defense_light" and GameState.pets.back().quality_score == 100.0, "relationship tier 2 did not grant a one-star attack-defense pet")
	assert(GameState.chat_with_princess().reason == "already_chatted", "princess could be chatted with twice on one day")

	GameState.current_day = 10
	GameState.affection = 49
	var crossing_chat := GameState.chat_with_princess()
	assert(crossing_chat.success and GameState.get_affection_rank().level == 4, "daily chat did not cross into the confidant tier")
	assert(GameState.story_flags.princess_friend_gift_available, "confidant gift did not unlock at relationship tier 4")
	var friend_gift := GameState.claim_princess_friend_gift()
	assert(friend_gift.success and GameState.pets.back().template_id == "year_pig", "confidant gift did not grant the year pig")
	assert(not GameState.claim_princess_friend_gift().success, "confidant year pig could be claimed twice")

	var maid_price_before := GameState.magic_stones
	var maid_trade := GameState.buy_maid_year_pig()
	assert(maid_trade.success and maid_trade.price == 5888, "maid year-pig trade failed")
	assert(GameState.magic_stones == maid_price_before - 5888, "maid trade charged the wrong number of magic stones")
	assert(not GameState.buy_maid_year_pig().success, "maid year pig could be bought twice")

	var previous_save_path := GameState.save_path
	GameState.save_path = "user://story_test_save.json"
	GameState.last_princess_chat_day = 10
	GameState.story_flags.king_rescued = true
	assert(GameState.save_game(), "story save v14 failed")
	_reset_story()
	assert(GameState.load_game(), "story save v14 could not be loaded")
	assert(GameState.story_flags.king_rescued and not GameState.story_flags.maid_year_pig_available, "story flags were not restored")
	assert(GameState.last_princess_chat_day == 10, "princess daily chat state was not restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.save_path = previous_save_path

	print("PASS king rescue, snow-border gate, princess chat gifts, maid trade, and story save v14")
	get_tree().quit(0)
