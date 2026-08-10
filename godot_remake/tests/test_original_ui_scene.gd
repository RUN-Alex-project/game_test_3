extends Node


func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	assert(GameState.PAGE_SIZE == 24, "inventory page size must match the original 6 by 4 grid")
	assert(main.inventory_panel.slots.size() == 24, "backpack did not build 24 visible slots")
	assert(main.player_status_card.size() >= 7, "player HUD card is incomplete")
	assert(main.pet_status_cards.size() == 2, "two pet HUD cards are required")
	assert(not main.footer_buttons.has("map"), "map must not be exposed as a footer panel button")
	assert(main.actor_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "full-screen actor layer blocks real mouse clicks")
	assert(main.navigation_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "full-screen navigation layer blocks real mouse clicks")

	var visible_exits := 0
	for button: Button in main.direction_buttons.values():
		if button.visible:
			visible_exits += 1
	assert(visible_exits >= 3, "city edge navigation buttons were not created")
	assert(main.interactive_actors.has("grocery"), "grocery merchant actor is missing")
	assert(main.interactive_actors.has("collector"), "collector actor is missing")
	assert(main.interactive_actors.has("warehouse"), "warehouse actor is missing")

	main._open_actor_dialogue("grocery")
	assert(main.dialogue_panel.visible, "clickable NPC did not open dialogue")
	assert(main.dialogue_panel.choices.get_child_count() == 3, "merchant dialogue choices are incomplete")
	main.dialogue_panel._choose("gold_sell")
	assert(not main.dialogue_panel.visible, "dialogue did not close after choosing an action")
	assert(main.gold_shop.visible and main.gold_shop.current_mode == "sell", "grocery sell view did not open")
	var gold_before := GameState.gold
	main.gold_shop._claim_sale()
	assert(GameState.gold == gold_before + 99_999_999_999, "grocery sell grant was not applied")

	main._open_actor_dialogue("collector")
	main.dialogue_panel._choose("stone_sell")
	assert(main.stone_shop.visible and main.stone_shop.current_mode == "sell", "collector sell view did not open")
	var stones_before := GameState.magic_stones
	main.stone_shop._claim_sale()
	assert(GameState.magic_stones == stones_before + 99_999_999_999, "collector sell grant was not applied")

	var described_item: Dictionary = {}
	for item: Dictionary in GameState.inventory:
		if not item.is_empty():
			described_item = item
			break
	assert(not described_item.is_empty(), "test inventory has no item to describe")
	main._show_item_description(described_item, main.inventory_panel)
	assert(main.item_tooltip_panel.visible, "item description panel did not open")
	assert(not main.item_tooltip_text.text.is_empty(), "item description text is empty")

	main._toggle_warehouse()
	assert(main.inventory_panel.visible and main.warehouse_panel.visible, "warehouse did not show both native storage windows")
	assert(main.warehouse_panel.slots.size() == 36, "warehouse page does not contain the original 6 by 6 grid")
	print("PASS original UI framework, descriptions, NPC dialogue, navigation, shops, and storage")
	get_tree().quit(0)

