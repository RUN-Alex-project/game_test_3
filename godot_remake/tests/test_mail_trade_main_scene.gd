extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(main.adventurer_mail_panel != null)
	assert(main.adventurer_trade_panel != null)
	assert(not main.adventurer_mail_panel.visible, "mail must start hidden")
	assert(not main.adventurer_trade_panel.visible, "trade must start hidden")
	assert(not main.adventurer_roster_panel.visible, "roster must start hidden")
	GameState.current_day = 1
	main._open_actor_dialogue("daily_officer")
	assert(main.dialogue_panel.visible)
	assert(_has_choice(main, "\u5192\u9669\u8005\u516c\u544a\u677f"), "daily officer missing board choice")
	assert(_press_choice(main, "\u5192\u9669\u8005\u516c\u544a\u677f"))
	await get_tree().process_frame
	assert(main.adventurer_roster_panel.visible, "board did not open roster")
	main.adventurer_roster_panel.mail_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(main.adventurer_mail_panel.visible, "mail panel did not open")
	assert(not main.adventurer_roster_panel.visible, "roster should hide when mail opens")
	var mail_rect: Rect2 = main.adventurer_mail_panel.get_global_rect()
	assert(mail_rect.end.x <= 700.5 and mail_rect.end.y <= 550.5, "mail exceeds viewport %s" % str(mail_rect))
	main.adventurer_mail_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.adventurer_mail_panel.visible, "mail close failed")
	main._open_adventurer_board()
	await get_tree().process_frame
	main.adventurer_roster_panel.trade_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(main.adventurer_trade_panel.visible, "trade panel did not open")
	var trade_rect: Rect2 = main.adventurer_trade_panel.get_global_rect()
	assert(trade_rect.end.x <= 700.5 and trade_rect.end.y <= 550.5, "trade exceeds viewport %s" % str(trade_rect))
	var roses := GameState.count_item("rose")
	var gold := GameState.gold
	main.adventurer_trade_panel._buy_rose()
	await get_tree().process_frame
	assert(GameState.count_item("rose") == roses + 1, "buy from panel did not add rose")
	assert(GameState.gold == gold - 15, "buy from panel did not charge gold")
	main.adventurer_trade_panel.close_button.emit_signal("pressed")
	await get_tree().process_frame
	assert(not main.adventurer_trade_panel.visible, "trade close failed")
	print("PASS mail_trade_main: board opens mail/trade, hidden at start, close, buy consume")
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
