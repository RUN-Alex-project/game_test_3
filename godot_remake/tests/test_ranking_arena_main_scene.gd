extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(main.ranking_panel != null)
	assert(main.arena_panel != null)
	assert(main.arena_proxy != null)
	assert(not main.ranking_panel.visible, "ranking must start hidden")
	assert(not main.arena_panel.visible, "arena must start hidden")
	assert(not main.interactive_actors.has("arena_proxy"), "arena proxy must not be a city actor")
	assert(not main.interactive_actors.has("ranking_board"), "ranking is not a cassano actor")
	main._open_pk_officer_dialogue()
	assert(main.dialogue_panel.visible)
	assert(_has_choice(main, "\u5192\u9669\u8005\u6392\u884c\u699c"), "pk officer missing ranking")
	assert(_has_choice(main, "\u5f02\u6b65\u64c2\u53f0"), "pk officer missing arena")
	assert(_press_choice(main, "\u5192\u9669\u8005\u6392\u884c\u699c"))
	await get_tree().process_frame
	assert(main.ranking_panel.visible, "ranking panel did not open")
	var rank_rect: Rect2 = main.ranking_panel.get_global_rect()
	assert(rank_rect.end.x <= 700.5 and rank_rect.end.y <= 550.5, "ranking exceeds viewport %s" % str(rank_rect))
	main.ranking_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.ranking_panel.visible, "ranking close failed")
	main._open_pk_officer_dialogue()
	assert(_press_choice(main, "\u5f02\u6b65\u64c2\u53f0"))
	await get_tree().process_frame
	assert(main.arena_panel.visible, "arena panel did not open")
	var arena_rect: Rect2 = main.arena_panel.get_global_rect()
	assert(arena_rect.end.x <= 700.5 and arena_rect.end.y <= 550.5, "arena exceeds viewport %s" % str(arena_rect))
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.refresh_rankings()
	var score_before := int(GameState.expansion_state.get("rankings", {}).get("player_ratings", {}).get("arena_score", 0))
	var begun: Dictionary = GameState.begin_arena_match("npc_adv_tang_xue", "challenge", "ui_cancel_1")
	assert(bool(begun.get("success", false)), "begin for cancel test failed %s" % str(begun))
	assert(main.scene_battle_controller.engage(str(begun.get("monster_id", "")), main.arena_proxy), "arena proxy engage failed")
	main.scene_battle_controller.cancel_battle()
	await get_tree().process_frame
	var score_after := int(GameState.expansion_state.get("rankings", {}).get("player_ratings", {}).get("arena_score", 0))
	assert(score_after == score_before, "cancel settled arena score %d -> %d" % [score_before, score_after])
	assert(str(GameState.expansion_state.get("rankings", {}).get("active_match_id", "")) == "", "active match remains after cancel")
	main.arena_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.arena_panel.visible, "arena close failed")
	print("PASS ranking_arena_main: pk officer opens both panels, hidden at start, proxy not city actor, cancel no score")
	get_tree().quit(0)


func _has_choice(main: Node, label: String) -> bool:
	for child in main.dialogue_panel.choices.get_children():
		if child is Button and child.text == label:
			return true
	return false


func _press_choice(main: Node, label: String) -> bool:
	for child in main.dialogue_panel.choices.get_children():
		if child is Button and child.text == label:
			child.emit_signal("pressed")
			return true
	return false
