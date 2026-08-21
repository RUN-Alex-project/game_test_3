extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not main.pet_endgame_panel.visible, "pet panel must start hidden")
	main._open_research_dialogue()
	await get_tree().process_frame
	main._handle_dialogue_action("pet_endgame_board")
	await get_tree().process_frame
	assert(main.pet_endgame_panel.visible)
	var rect: Rect2 = main.pet_endgame_panel.get_global_rect()
	assert(Rect2(0, 0, 700, 550).encloses(rect) or Rect2(0, 0, 700, 550).intersects(rect))
	main.pet_endgame_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.pet_endgame_panel.visible)
	main._open_actor_dialogue("grocery")
	var n := 0
	for child in main.dialogue_panel.choices.get_children():
		if child is Button:
			n += 1
	assert(n == 3)
	print("PASS pet endgame main scene")
	get_tree().quit(0)
