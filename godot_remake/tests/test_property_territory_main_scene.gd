extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(main.property_territory_panel != null)
	assert(not main.property_territory_panel.visible, "property panel must start hidden")
	assert(not main.interactive_actors.has("property_board"), "property board is not a cassano actor")
	main._open_actor_dialogue("territory:cassano_city")
	assert(main.dialogue_panel.visible)
	assert(_has_choice(main, "\u9886\u5730\u4e0e\u57ce\u5821"), "territory officer missing castle option")
	assert(_press_choice(main, "\u9886\u5730\u4e0e\u57ce\u5821"))
	await get_tree().process_frame
	assert(main.property_territory_panel.visible, "property panel did not open")
	var rect: Rect2 = main.property_territory_panel.get_global_rect()
	assert(rect.end.x <= 700.5 and rect.end.y <= 550.5, "property panel exceeds viewport %s" % str(rect))
	main.property_territory_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.property_territory_panel.visible, "property close failed")
	print("PASS property_territory_main: officer opens panel, hidden at start, not city actor")
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
