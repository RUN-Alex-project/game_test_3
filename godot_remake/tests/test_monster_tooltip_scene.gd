extends Node


func _ready() -> void:
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var action_id := "battle:spider"
	var actor: TextureRect = main.interactive_actors[action_id]
	var actor_label: Label = main.actor_labels[action_id]
	assert(not actor_label.visible, "battle monster name remained permanently visible")

	main._actor_hover(actor, true, action_id)
	assert(main.monster_tooltip_panel.visible, "native monster tooltip did not appear")
	assert(main.monster_tooltip_panel.size == Vector2(123, 74), "monster tooltip is not the native 123x74 size")
	assert(main.monster_tooltip_panel.position == Vector2(27, 312), "monster tooltip did not follow the native target-relative placement")
	assert(main.monster_tooltip_text.text == "蜘蛛(45级)\n45战斗力\n经验增加900%", "monster tooltip content does not reflect native fields and current experience multiplier")
	assert(main._monster_tooltip_color(106, 100) == Color("333333"), "far stronger monster color is wrong")
	assert(main._monster_tooltip_color(104, 100) == Color("ff0000"), "slightly stronger monster color is wrong")
	assert(main._monster_tooltip_color(100, 100) == Color("ffffff"), "equal-power monster color is wrong")
	assert(main._monster_tooltip_color(99, 100) == Color("009933"), "weaker monster color is wrong")

	main._actor_hover(actor, false, action_id)
	assert(not main.monster_tooltip_panel.visible, "monster tooltip remained after rollout")
	assert(actor.modulate == Color.WHITE, "monster highlight remained after rollout")

	GameState.current_map_id = "thunder_continent"
	main._apply_current_map()
	var boss_action := "battle:thunder_boss_10"
	var boss_actor: TextureRect = main.interactive_actors[boss_action]
	main._actor_hover(boss_actor, true, boss_action)
	assert("10战斗力" in main.monster_tooltip_text.text, "boss tooltip ignored explicit combat_power")

	print("PASS native 123x74 monster hover tooltip, fields, colors, placement, and hidden battle labels")
	get_tree().quit(0)
