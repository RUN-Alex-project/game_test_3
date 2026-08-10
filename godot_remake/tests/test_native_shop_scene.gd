extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	main.gold_shop.open_mode("buy")
	assert(main.gold_shop.position == Vector2(285, 90), "grocery does not use SWF show coordinates")
	assert(main.gold_shop.size == Vector2(333, 207), "grocery does not use shape573 bounds")
	assert(main.gold_shop.buy_header.position.is_equal_approx(Vector2(11.85, 11.35)), "grocery purchase header is not at the native placement")
	assert(main.gold_shop.sell_header.position.is_equal_approx(Vector2(173.8, 11.35)), "grocery sale header is not at the native placement")
	assert(main.gold_shop.close_button.position.is_equal_approx(Vector2(303.95, 6)), "grocery close control is not at the native placement")
	assert(main.gold_shop.buy_slots.size() == 12 and main.gold_shop.sell_slots.size() == 12, "grocery does not expose native 4x3 buy/sell areas")
	assert(main.gold_shop.buy_slots[0].position == Vector2(4, 44), "grocery purchase grid origin is incorrect")
	assert(main.gold_shop.sell_slots[0].position == Vector2(166, 81), "grocery sale grid origin is incorrect")

	var gold_before := GameState.gold
	main.gold_shop.sell_header.emit_signal("pressed")
	assert(GameState.gold == gold_before + 99_999_999_999, "native grocery sale header did not grant the configured gold")
	main.gold_shop.open_mode("sell")
	assert(main.gold_shop.current_mode == "sell" and main.gold_shop.size == Vector2(333, 207), "grocery sell action changed away from the native combined window")

	main.stone_shop.open_mode("buy")
	assert(main.stone_shop.position == Vector2(285, 90), "collection shop does not use SWF show coordinates")
	assert(main.stone_shop.size == Vector2(167, 207), "collection shop does not use shape610 bounds")
	assert(main.stone_shop.buy_slots.size() == 16, "collection shop does not expose its native 4x4 visible shop area")
	assert(main.stone_shop.title_label.text == "收藏商店", "collection shop identity was not preserved")
	assert(main.stone_shop.close_button.position.is_equal_approx(Vector2(138.35, 5.95)), "collection shop close control is not at the native placement")

	main.stone_shop.open_mode("sell")
	assert(main.stone_shop.position == Vector2(260, 300), "collector does not use SWF show coordinates")
	assert(main.stone_shop.size == Vector2(167, 207), "collector does not use shape646 bounds")
	assert(main.stone_shop.sell_slots.size() == 12, "collector does not expose the native 4x3 sale area")
	assert(main.stone_shop.sell_slots[0].position == Vector2(3, 81), "collector sale grid origin is incorrect")
	assert(main.stone_shop.title_label.text == "与收藏家交易", "collector sale identity was not preserved")
	assert(main.stone_shop.close_button.position.is_equal_approx(Vector2(141.55, 4.95)), "collector close control is not at the native placement")
	var stones_before := GameState.magic_stones
	main.stone_shop.sell_header.emit_signal("pressed")
	assert(GameState.magic_stones == stones_before + 99_999_999_999, "native collector sale header did not grant the configured magic stones")

	print("PASS native grocery, collection shop, collector sale grids, controls, and unlimited sale wiring")
	get_tree().quit(0)
