extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not main.interactive_actors.has("abyss_he"))
	assert(not main.abyss_board_panel.visible, "abyss panel must start hidden")
	GameState.story_flags["king_rescued"] = true
	GameState.seed_abyss_prereqs()
	main._open_king_dialogue()
	assert(_has_choice(main, "\u6df1\u6e0a\u7ec8\u5c40"), "king missing abyss")
	assert(_press_choice(main, "\u6df1\u6e0a\u7ec8\u5c40"))
	await get_tree().process_frame
	assert(GameState.current_map_id == "abyss_gate")
	assert(main.interactive_actors.has("abyss_he"))
	main._talk_abyss_npc("abyss_he")
	assert(_has_choice(main, "\u7ec8\u5c40\u9762\u677f"))
	assert(_press_choice(main, "\u7ec8\u5c40\u9762\u677f"))
	await get_tree().process_frame
	assert(main.abyss_board_panel.visible)
	var rect: Rect2 = main.abyss_board_panel.get_global_rect()
	assert(rect.end.x <= 700.5 and rect.end.y <= 550.5, "abyss panel exceeds viewport")
	main.abyss_board_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.abyss_board_panel.visible)
	main._open_actor_dialogue("grocery")
	assert(_choice_count(main) == 3)
	print("PASS abyss_finale_main: king gate, panel hidden, grocery 3")
	get_tree().quit(0)


func _choice_count(main: Node) -> int:
	var n := 0
	for child in main.dialogue_panel.choices.get_children():
		if child is Button:
			n += 1
	return n


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
