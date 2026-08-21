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
	assert(not main.direction_buttons["bottom"].visible, "frame 8 has no desert arrow, bottom edge must stay hidden")

	# 原版补回的四条回城边，坐标全部来自同一个 character 1071 箭头实例的
	# PlaceObject2 矩阵（戈壁 frame16 d27、亚维特岛 frame19 d43、
	# 地下城二层 frame28 d27 继承、地下城三层 frame30 d8）。
	var native_returns := {
		"desert":{"direction":"top", "rect":Rect2(206.0, 124.3, 90.0, 41.0)},
		"avit_island":{"direction":"left", "rect":Rect2(2.0, 225.85, 41.0, 90.0)},
		"dungeon_floor_2":{"direction":"top", "rect":Rect2(206.0, 124.3, 90.0, 41.0)},
		"dungeon_floor_3":{"direction":"top", "rect":Rect2(206.0, 124.3, 90.0, 41.0)},
	}
	for map_id: String in native_returns:
		var expected: Dictionary = native_returns[map_id]
		GameState.current_map_id = map_id
		main._apply_current_map()
		await get_tree().process_frame
		var back: Button = main.direction_buttons[str(expected["direction"])]
		assert(back.visible and back.target_map_id == "cassano_city",
			"%s lost its native exit back to Cassano" % map_id)
		var expected_rect: Rect2 = expected["rect"]
		assert(back.position.is_equal_approx(expected_rect.position) and back.size.is_equal_approx(expected_rect.size),
			"%s return exit does not match its SWF arrow placement" % map_id)

	# 地下城下行链在原版是单向的：二层没有回一层、三层没有回二层的箭头。
	var upward := {"dungeon_floor_2":"dungeon", "dungeon_floor_3":"dungeon_floor_2"}
	for floor_id: String in upward:
		GameState.current_map_id = floor_id
		main._apply_current_map()
		await get_tree().process_frame
		for button: Button in main.direction_buttons.values():
			assert(not button.visible or button.target_map_id != str(upward[floor_id]),
				"%s regained the remake-only upward exit to %s" % [floor_id, upward[floor_id]])

	print("PASS native SWF map-edge placements, labels, gates, and travel wiring")
	get_tree().quit(0)



