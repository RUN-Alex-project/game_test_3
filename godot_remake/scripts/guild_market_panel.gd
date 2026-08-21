extends PanelContainer

signal message_changed(text: String)

var close_button: Button
var tab_buttons: Array[Button] = []
var rows: ItemList
var confirm_button: Button
var status_label: Label
var _tab := "shelf"
var _busy := false


func _ready() -> void:
	position = Vector2(169, 90)
	size = Vector2(362, 378)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ffcc99")
	style.border_color = Color("805b3c")
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	var title := Label.new()
	title.text = "\u5546\u4f1a\u4e8b\u52a1"
	title.position = Vector2(8, 4)
	title.size = Vector2(220, 22)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("7a3200"))
	root.add_child(title)

	close_button = Button.new()
	close_button.name = "close_button"
	close_button.text = ""
	close_button.position = Vector2(338.5, 2)
	close_button.size = Vector2(21, 21)
	close_button.focus_mode = Control.FOCUS_NONE
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color("ff9900")
	close_style.border_color = Color("202020")
	close_style.set_border_width_all(2)
	close_style.corner_radius_top_left = 11
	close_style.corner_radius_top_right = 11
	close_style.corner_radius_bottom_left = 11
	close_style.corner_radius_bottom_right = 11
	for state_name in ["normal", "hover", "pressed"]:
		close_button.add_theme_stylebox_override(state_name, close_style)
	close_button.pressed.connect(hide)
	root.add_child(close_button)

	var labels: Array[String] = ["\u8d27\u67b6", "\u4ea4\u6613", "\u62cd\u5356", "\u8d26\u672c"]
	var tab_ids: Array[String] = ["shelf", "trade", "auction", "ledger"]
	for index in labels.size():
		var button := Button.new()
		button.text = labels[index]
		button.position = Vector2(6 + index * 88, 28)
		button.size = Vector2(84, 22)
		var tab_id := tab_ids[index]
		button.pressed.connect(func() -> void:
			_tab = tab_id
			_refresh()
		)
		root.add_child(button)
		tab_buttons.append(button)

	rows = ItemList.new()
	rows.position = Vector2(6, 54)
	rows.size = Vector2(350, 260)
	root.add_child(rows)

	confirm_button = Button.new()
	confirm_button.text = "\u786e\u8ba4"
	confirm_button.position = Vector2(6, 320)
	confirm_button.size = Vector2(80, 24)
	confirm_button.pressed.connect(_on_confirm)
	root.add_child(confirm_button)

	status_label = Label.new()
	status_label.position = Vector2(90, 322)
	status_label.size = Vector2(264, 48)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	visibility_changed.connect(_refresh)
	GameState.social_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	GameState.ensure_guild_catalog()
	rows.clear()
	_busy = false
	confirm_button.disabled = false
	var market: Dictionary = GameState.expansion_state.get("market", {})
	status_label.text = "rep %d lv %d gold %d" % [
		int(market.get("reputation", 0)),
		int(market.get("reputation_level", 1)),
		GameState.gold,
	]
	match _tab:
		"shelf":
			for raw_row: Variant in market.get("daily_catalog", []):
				if raw_row is Dictionary:
					rows.add_item("%s %s %d" % [
						str(raw_row.get("slot_type", "")),
						str(raw_row.get("item_id", "")),
						int(raw_row.get("price", 0)),
					])
		"trade":
			for raw_row: Variant in market.get("npc_offers", []):
				if raw_row is Dictionary:
					rows.add_item("%s %s %s %d" % [
						str(raw_row.get("offer_id", "")),
						str(raw_row.get("adventurer_id", "")),
						str(raw_row.get("item_id", "")),
						int(raw_row.get("price", 0)),
					])
		"auction":
			for raw_row: Variant in market.get("auction_listings", []):
				if raw_row is Dictionary:
					rows.add_item("%s %s %d %s" % [
						str(raw_row.get("listing_id", "")),
						str(raw_row.get("item_id", "")),
						int(raw_row.get("high_bid", 0)),
						str(raw_row.get("status", "")),
					])
		"ledger":
			for raw_row: Variant in market.get("ledger", []):
				if raw_row is Dictionary:
					rows.add_item("%s %s %d" % [
						str(raw_row.get("operation_id", "")),
						str(raw_row.get("reason", "")),
						int(raw_row.get("gold_delta", 0)),
					])
	if rows.item_count == 0:
		rows.add_item("empty")


func _on_confirm() -> void:
	if _busy:
		return
	_busy = true
	confirm_button.disabled = true
	var selected := rows.get_selected_items()
	if _tab == "trade" and not selected.is_empty():
		var text := rows.get_item_text(selected[0])
		var offer_id := text.get_slice(" ", 0)
		var result: Dictionary = GameState.accept_guild_offer(offer_id, "ui:%s" % offer_id)
		message_changed.emit(str(result.get("code", "")))
	_refresh()
	_busy = false
	confirm_button.disabled = false
