extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not main.interactive_actors.has("chapter_lin"), "chapter npc is not a cassano actor")
	assert(not main.interactive_actors.has("property_board"))
	main._open_actor_dialogue("grocery")
	assert(_choice_count(main) == 3, "grocery must stay 3 options")
	main._open_daily_officer_dialogue()
	assert(main.dialogue_panel.visible)
	assert(_has_choice(main, "\u6811\u5fc3\u90ca\u533a"), "daily officer missing treeheart")
	assert(_press_choice(main, "\u6811\u5fc3\u90ca\u533a"))
	await get_tree().process_frame
	assert(GameState.current_map_id == "treeheart_outskirts", "enter_treeheart failed")
	assert(main.interactive_actors.has("chapter_lin"))
	GameState.current_map_id = "treeheart_city"
	main._apply_current_map()
	await get_tree().process_frame
	var right: Button = main.direction_buttons.get("right")
	assert(right != null and right.visible)
	assert(str(right.target_map_id) == "treeheart_outskirts", "city right exit")
	GameState.current_map_id = "treeheart_outskirts"
	main._apply_current_map()
	main._travel_to("treeheart_core")
	assert("chapter_locked" in str(main.status_label.text), "locked core must speak")
	print("PASS treeheart_harbor_main: officer gate, city right exit, no cassano chapter actor, grocery 3")
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
