extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not main.interactive_actors.has("ice_shen"))
	assert(not main.ice_codex_panel.visible, "ice panel must start hidden")
	main._open_research_dialogue()
	assert(_has_choice(main, "\u51b0\u539f\u8bd5\u70bc"), "research missing ice")
	assert(_press_choice(main, "\u51b0\u539f\u8bd5\u70bc"))
	await get_tree().process_frame
	assert(GameState.current_map_id == "ice_frontier")
	assert(main.interactive_actors.has("ice_shen"))
	main._talk_ice_npc("ice_shen")
	assert(_has_choice(main, "\u5143\u7d20\u56fe\u9274"))
	assert(_press_choice(main, "\u5143\u7d20\u56fe\u9274"))
	await get_tree().process_frame
	assert(main.ice_codex_panel.visible)
	var rect: Rect2 = main.ice_codex_panel.get_global_rect()
	assert(rect.end.x <= 700.5 and rect.end.y <= 550.5, "ice panel exceeds viewport")
	main.ice_codex_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.ice_codex_panel.visible)
	main._open_actor_dialogue("grocery")
	assert(_choice_count(main) == 3)
	print("PASS ice_element_main: research gate, panel hidden, grocery 3")
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
