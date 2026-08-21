extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not main.interactive_actors.has("border_cmd"))
	assert(not main.border_command_panel.visible, "border panel must start hidden")
	main._open_marshal_dialogue()
	assert(_has_choice(main, "\u5357\u90e8\u57ce\u90a6"), "marshal missing south")
	assert(_press_choice(main, "\u5357\u90e8\u57ce\u90a6"))
	await get_tree().process_frame
	assert(GameState.current_map_id == "south_city_gate")
	assert(main.interactive_actors.has("border_cmd"))
	main._talk_border_npc("border_cmd")
	assert(_has_choice(main, "\u6307\u6325\u9762\u677f"))
	assert(_press_choice(main, "\u6307\u6325\u9762\u677f"))
	await get_tree().process_frame
	assert(main.border_command_panel.visible)
	var rect: Rect2 = main.border_command_panel.get_global_rect()
	assert(rect.end.x <= 700.5 and rect.end.y <= 550.5, "border panel exceeds viewport")
	main.border_command_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.border_command_panel.visible)
	main._open_actor_dialogue("grocery")
	assert(_choice_count(main) == 3)
	print("PASS south_border_main: marshal gate, panel hidden, grocery 3")
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
