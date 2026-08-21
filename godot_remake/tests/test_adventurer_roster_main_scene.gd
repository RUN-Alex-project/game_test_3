extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(main.adventurer_roster_panel != null)
	assert(not main.adventurer_roster_panel.visible, "roster must start hidden")
	GameState.current_day = 1
	main._open_actor_dialogue("daily_officer")
	assert(main.dialogue_panel.visible)
	assert(_has_choice(main, "冒险者公告板"), "daily officer missing board choice")
	assert(_press_choice(main, "冒险者公告板"))
	await get_tree().process_frame
	assert(main.adventurer_roster_panel.visible, "board did not open roster")
	assert(not main.dialogue_panel.visible, "dialogue should hide when roster opens")
	var rect: Rect2 = main.adventurer_roster_panel.get_global_rect()
	assert(rect.end.x <= 700.5 and rect.end.y <= 550.5, "roster exceeds viewport %s" % str(rect))
	var roses := GameState.count_item("rose")
	main.adventurer_roster_panel._gift_rose()
	await get_tree().process_frame
	assert(GameState.count_item("rose") == roses - 1, "gift from panel did not consume rose")
	assert(not main.status_label.text.is_empty(), "gift did not set status")
	main.adventurer_roster_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.adventurer_roster_panel.visible, "close did not hide roster")
	GameState.current_map_id = "thunder_continent"
	main._apply_current_map()
	print("PASS adventurer_roster_main: daily officer board, hidden at start, close, gift consume, map visit")
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
