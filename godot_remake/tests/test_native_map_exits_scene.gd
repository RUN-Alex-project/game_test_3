extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.level = 69
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var right: Button = main.direction_buttons["right"]
	var top: Button = main.direction_buttons["top"]
	var left: Button = main.direction_buttons["left"]
	var bottom: Button = main.direction_buttons["bottom"]
	assert(right.position.is_equal_approx(Vector2(654.5, 264.95)) and right.size.is_equal_approx(Vector2(41, 90)), "Avit exit does not match SWF root placement")
	assert(top.position.is_equal_approx(Vector2(211.05, 124.3)) and top.size.is_equal_approx(Vector2(90, 41)), "palace exit does not match SWF root placement")
	assert(left.position.is_equal_approx(Vector2(2.1, 264.95)) and left.size.is_equal_approx(Vector2(41, 90)), "Thunder exit does not match SWF root placement")
	assert(bottom.position.is_equal_approx(Vector2(391.05, 403.9)) and bottom.size.is_equal_approx(Vector2(90, 41)), "desert exit does not match SWF root placement")
	assert(right.target_map_id == "avit_island" and right.native_direction == "right", "right city exit target is not Avit Island")
	assert(left.target_map_id == "thunder_continent" and left.native_direction == "left", "left city exit target is not Thunder Continent")
	assert(top.target_map_id == "palace" and bottom.target_map_id == "desert", "vertical city exits are incorrect")
	assert(right.locked and not right.disabled, "level 70 Avit gate must be locked but still clickable so the block reason is shown")
	assert(right.destination == "亚维特岛" and right.travel_verb == "进入", "native edge label was not configured")

	left.emit_signal("pressed")
	assert(GameState.current_map_id == "thunder_continent", "native left edge did not travel to Thunder Continent")
	await get_tree().process_frame
	right = main.direction_buttons["right"]
	top = main.direction_buttons["top"]
	assert(right.target_map_id == "cassano_city" and right.position.is_equal_approx(Vector2(657.7, 219.5)), "Thunder return exit does not match frame 8")
	assert(top.target_map_id == "thunder_mine" and top.position.is_equal_approx(Vector2(206.8, 124.3)), "mine entrance does not match frame 8")
	assert(not main.direction_buttons["left"].visible, "unused Thunder left edge remained visible")

	print("PASS native SWF map-edge placements, labels, gates, and travel wiring")
	get_tree().quit(0)



