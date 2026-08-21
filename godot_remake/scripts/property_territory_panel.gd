extends PanelContainer

signal message_changed(text: String)

var close_button: Button
var tab_buttons: Array[Button] = []
var rows: ItemList
var confirm_button: Button
var status_label: Label
var _tab := "overview"
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
	title.text = "\u9886\u5730\u4e0e\u57ce\u5821"
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

	var labels: Array[String] = [
		"\u603b\u89c8", "\u9886\u5730", "\u57ce\u5821", "\u59d4\u4efb",
		"\u4ed3\u50a8", "\u4e8b\u4ef6", "\u8d26\u672c",
	]
	var tab_ids: Array[String] = ["overview", "lands", "castle", "assign", "store", "events", "ledger"]
	for index in labels.size():
		var button := Button.new()
		button.text = labels[index]
		button.position = Vector2(4 + index * 51, 28)
		button.size = Vector2(50, 22)
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
	GameState.territory_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	rows.clear()
	_busy = false
	confirm_button.disabled = false
	var props: Dictionary = GameState.expansion_state.get("properties", {})
	var econ: Dictionary = GameState.expansion_state.get("territory_economy", {})
	status_label.text = "lv %d gold %d contrib %d owned %s" % [
		int(props.get("castle_level", 1)),
		GameState.gold,
		int(econ.get("contribution", 0)),
		GameState.owned_territory,
	]
	match _tab:
		"overview":
			rows.add_item("castle %d cap %d" % [
				int(props.get("castle_level", 1)),
				int(GameState.expansion_state_service.property_service.warehouse_cap(props)),
			])
			rows.add_item("owned %s" % GameState.owned_territory)
			rows.add_item("contribution %d" % int(econ.get("contribution", 0)))
		"lands":
			var territories: Dictionary = econ.get("territories", {})
			for map_id in territories.keys():
				var row: Variant = territories[map_id]
				if row is Dictionary:
					rows.add_item("%s locked=%s event=%s" % [
						str(map_id),
						str(row.get("locked", false)),
						str(row.get("pending_event_id", "")),
					])
		"castle":
			rows.add_item("upgrade to %d" % (int(props.get("castle_level", 1)) + 1))
		"assign":
			for raw_row: Variant in props.get("assignments", []):
				if raw_row is Dictionary:
					rows.add_item("%s %s %s %s" % [
						str(raw_row.get("assignment_id", "")),
						str(raw_row.get("adventurer_id", "")),
						str(raw_row.get("post_id", "")),
						str(raw_row.get("status", "")),
					])
			if rows.item_count == 0:
				rows.add_item("empty")
		"store":
			rows.add_item("castle_gold %d" % int(props.get("castle_gold", 0)))
			var warehouse: Dictionary = props.get("warehouse", {})
			for item_id in warehouse.keys():
				rows.add_item("%s %d" % [str(item_id), int(warehouse.get(item_id, 0))])
		"events":
			var territories2: Dictionary = econ.get("territories", {})
			for map_id in territories2.keys():
				var row: Variant = territories2[map_id]
				if row is Dictionary and not str(row.get("pending_event_id", "")).is_empty():
					rows.add_item("%s %s resolved=%s" % [
						str(map_id),
						str(row.get("pending_event_id", "")),
						str(row.get("event_resolved", false)),
					])
		"ledger":
			for raw_row: Variant in econ.get("ledger", []):
				if raw_row is Dictionary:
					rows.add_item("%s %s %d" % [
						str(raw_row.get("operation_id", "")),
						str(raw_row.get("reason", "")),
						int(raw_row.get("qty_delta", 0)),
					])
	if rows.item_count == 0:
		rows.add_item("empty")


func _on_confirm() -> void:
	if _busy:
		return
	_busy = true
	confirm_button.disabled = true
	if _tab == "castle":
		var result: Dictionary = GameState.upgrade_castle("ui:castle")
		message_changed.emit(str(result.get("code", "")))
	elif _tab == "events":
		var selected := rows.get_selected_items()
		if not selected.is_empty():
			var text := rows.get_item_text(selected[0])
			var map_id := text.get_slice(" ", 0)
			var result: Dictionary = GameState.resolve_territory_event(map_id, "handle", "ui:event:%s" % map_id)
			message_changed.emit(str(result.get("code", "")))
	_refresh()
	_busy = false
	confirm_button.disabled = false
