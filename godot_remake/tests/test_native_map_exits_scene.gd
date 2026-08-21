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
	# 用户 2026-08-21 取消地图等级门槛：卡萨诺城四个出口不再有等级锁。
	# 「被门槛挡住的出口保持 locked 且不 disabled」这条规则改由
	# ui_audit/test_ui_map_exit_blocking_scene 用仍然存在的爵位门槛（后花园）验证。
	assert(GameState.map_entry_required_level("avit_island") == 1, "map level gates must be removed (Avit still gated)")
	assert(not right.locked and not right.disabled, "Avit exit must be open once level gates are removed")
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



