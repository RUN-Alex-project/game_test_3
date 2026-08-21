extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(main.guild_market_panel != null)
	assert(not main.guild_market_panel.visible, "guild market must start hidden")
	assert(not main.interactive_actors.has("guild_market"), "guild market is not a cassano actor")
	main._open_actor_dialogue("collector")
	assert(main.dialogue_panel.visible)
	assert(_has_choice(main, "\u5546\u4f1a\u4e8b\u52a1"), "collector missing guild market")
	assert(_press_choice(main, "\u5546\u4f1a\u4e8b\u52a1"))
	await get_tree().process_frame
	assert(main.guild_market_panel.visible, "guild panel did not open")
	var rect: Rect2 = main.guild_market_panel.get_global_rect()
	assert(rect.end.x <= 700.5 and rect.end.y <= 550.5, "guild panel exceeds viewport %s" % str(rect))
	main.guild_market_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.guild_market_panel.visible, "guild close failed")
	main._open_pk_officer_dialogue()
	assert(_has_choice(main, "\u5546\u4f1a\u4e8b\u52a1"), "pk officer missing guild market")
	print("PASS market_auction_main: collector/pk open guild panel, hidden at start, not city actor")
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
