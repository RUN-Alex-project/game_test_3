extends PanelContainer

signal message_changed(text: String)

var currency: String = "gold"
var shop_title: String = "杂货商"
var current_mode: String = "buy"
var currency_label: Label
var mode_content: Control
var title_label: Label
var close_button: Button
var buy_header: Button
var sell_header: Button
var buy_slots: Array[Control] = []
var sell_slots: Array[Control] = []


func _ready() -> void:
	GameState.currency_changed.connect(_refresh_currency)
	open_mode(current_mode)


func open_mode(mode: String) -> void:
	current_mode = "sell" if mode == "sell" else "buy"
	_rebuild_native_panel()
	_refresh_currency()
	show()


func _rebuild_native_panel() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buy_slots.clear()
	sell_slots.clear()
	buy_header = null
	sell_header = null
	currency_label = null
	var profile := _native_profile()
	position = profile.position
	size = profile.size
	custom_minimum_size = profile.size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_style()

	mode_content = Control.new()
	mode_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mode_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(mode_content)

	match str(profile.kind):
		"grocery":
			_build_grocery()
		"collection_shop":
			_build_collection_shop()
		"collector":
			_build_collector()


func _native_profile() -> Dictionary:
	if currency == "gold":
		return {"kind":"grocery", "position":Vector2(285, 90), "size":Vector2(333, 207)}
	if current_mode == "sell":
		return {"kind":"collector", "position":Vector2(260, 300), "size":Vector2(167, 207)}
	return {"kind":"collection_shop", "position":Vector2(285, 90), "size":Vector2(167, 207)}


func _apply_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("666666")
	style.border_color = Color("202020")
	style.set_border_width_all(2)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)


func _build_grocery() -> void:
	buy_header = _make_header_button("购买", Vector2(11.85, 11.35))
	buy_header.pressed.connect(_select_buy_mode)
	title_label = _make_title("杂货商", Vector2(70.5, 13.5), Vector2(92, 24), 15)
	sell_header = _make_header_button("出售", Vector2(173.8, 11.35))
	sell_header.pressed.connect(_claim_sale)
	_make_title("出售物品", Vector2(232.2, 14.8), Vector2(70, 24), 13)
	close_button = _make_close_button(Vector2(303.95, 6))
	currency_label = _make_currency_label(Vector2(170, 41.95), Vector2(152, 20), Color("ff9900"))
	_build_buy_grid(Vector2(4, 44), 12)
	_build_sale_grid(Vector2(166, 81), 12)


func _build_collection_shop() -> void:
	buy_header = _make_header_button("购买", Vector2(11.35, 12.05))
	buy_header.pressed.connect(_select_buy_mode)
	title_label = _make_title("收藏商店", Vector2(67.85, 13.8), Vector2(72, 24), 13)
	close_button = _make_close_button(Vector2(138.35, 5.95))
	currency_label = _make_currency_label(Vector2(4, 183), Vector2(132, 20), Color("00cc33"))
	_build_buy_grid(Vector2(4, 44), 16)


func _build_collector() -> void:
	sell_header = _make_header_button("出售", Vector2(9.5, 10.05))
	sell_header.pressed.connect(_claim_sale)
	title_label = _make_title("与收藏家交易", Vector2(51.5, 12.8), Vector2(90, 24), 12)
	close_button = _make_close_button(Vector2(141.55, 4.95))
	currency_label = _make_currency_label(Vector2(4, 65.35), Vector2(132, 20), Color("00cc33"))
	_build_sale_grid(Vector2(3, 81), 12)


func _make_header_button(label_text: String, button_position: Vector2) -> Button:
	var button := Button.new()
	button.text = label_text
	button.position = button_position
	button.size = Vector2(42, 24)
	button.custom_minimum_size = Vector2(42, 24)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var states := [
		["normal", Color("666666")],
		["hover", Color("999999")],
		["pressed", Color("333333")],
	]
	for state: Array in states:
		var style := StyleBoxFlat.new()
		style.bg_color = state[1]
		style.border_color = Color("202020")
		style.set_border_width_all(1)
		button.add_theme_stylebox_override(str(state[0]), style)
	mode_content.add_child(button)
	return button


func _make_title(label_text: String, label_position: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.position = label_position
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("00ff33"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_content.add_child(label)
	return label


func _make_close_button(button_position: Vector2) -> Button:
	var button := Button.new()
	button.position = button_position
	button.size = Vector2(21, 21)
	button.custom_minimum_size = Vector2(21, 21)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "关闭"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var states := [
		["normal", Color("333333")],
		["hover", Color("999999")],
		["pressed", Color("000000")],
	]
	for state: Array in states:
		var style := StyleBoxFlat.new()
		style.bg_color = state[1]
		style.border_color = Color("ff9900")
		style.set_border_width_all(4)
		style.corner_radius_top_left = 11
		style.corner_radius_top_right = 11
		style.corner_radius_bottom_left = 11
		style.corner_radius_bottom_right = 11
		button.add_theme_stylebox_override(str(state[0]), style)
	button.pressed.connect(hide)
	mode_content.add_child(button)
	return button


func _make_currency_label(label_position: Vector2, label_size: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_content.add_child(label)
	return label


func _build_buy_grid(origin: Vector2, cell_count: int) -> void:
	var price_key := "price_magic_stones" if currency == "magic_stones" else "price_gold"
	var shop_items: Array[String] = []
	for item_id: String in GameState.item_database:
		var definition := GameState.get_item_definition(item_id)
		if definition.has(price_key):
			shop_items.append(item_id)
	for local_index in cell_count:
		var slot_position := origin + Vector2((local_index % 4) * 40, (local_index / 4) * 40)
		var slot: Control
		if local_index < shop_items.size():
			var item_id := shop_items[local_index]
			var definition := GameState.get_item_definition(item_id)
			var button := _make_item_button(slot_position)
			button.icon = load(str(definition.get("icon", "")))
			button.tooltip_text = "%s\n价格：%s %s\n%s" % [
				str(definition.get("name", item_id)),
				_format_number(int(definition.get(price_key, 0))),
				"魔石" if currency == "magic_stones" else "金币",
				str(definition.get("description", "")),
			]
			button.pressed.connect(_buy.bind(item_id))
			slot = button
		else:
			slot = _make_empty_slot(slot_position)
		buy_slots.append(slot)


func _build_sale_grid(origin: Vector2, cell_count: int) -> void:
	var eligible: Array[Dictionary] = []
	for inventory_index in GameState.inventory.size():
		var item: Dictionary = GameState.inventory[inventory_index]
		var value := GameState.ore_sale_value(item, currency)
		if value > 0:
			eligible.append({"index":inventory_index, "item":item, "value":value})
	for local_index in cell_count:
		var slot_position := origin + Vector2((local_index % 4) * 40, (local_index / 4) * 40)
		var slot: Control
		if local_index < eligible.size():
			var entry: Dictionary = eligible[local_index]
			var item: Dictionary = entry.item
			var definition := GameState.get_item_definition(str(item.get("item_id", "")))
			var button := _make_item_button(slot_position)
			button.icon = load(str(definition.get("icon", "")))
			button.tooltip_text = "%s　品质%d\n出售：%s %s" % [
				str(definition.get("name", "矿石")),
				int(item.get("ore_quality", 1)),
				_format_number(int(entry.value)),
				"魔石" if currency == "magic_stones" else "金币",
			]
			button.pressed.connect(_sell_ore.bind(int(entry.index)))
			slot = button
		else:
			slot = _make_empty_slot(slot_position)
		sell_slots.append(slot)


func _make_item_button(button_position: Vector2) -> Button:
	var button := Button.new()
	button.position = button_position
	button.size = Vector2(36, 36)
	button.custom_minimum_size = Vector2(36, 36)
	button.expand_icon = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_slot_styles(button)
	mode_content.add_child(button)
	return button


func _make_empty_slot(slot_position: Vector2) -> Panel:
	var slot := Panel.new()
	slot.position = slot_position
	slot.size = Vector2(36, 36)
	slot.custom_minimum_size = Vector2(36, 36)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("333333")
	style.border_color = Color("999999")
	style.set_border_width_all(2)
	slot.add_theme_stylebox_override("panel", style)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_content.add_child(slot)
	return slot


func _apply_slot_styles(button: Button) -> void:
	var states := [
		["normal", Color("333333"), Color("999999")],
		["hover", Color("555555"), Color("ffcc33")],
		["pressed", Color("111111"), Color("ff9900")],
	]
	for state: Array in states:
		var style := StyleBoxFlat.new()
		style.bg_color = state[1]
		style.border_color = state[2]
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(str(state[0]), style)


func _select_buy_mode() -> void:
	current_mode = "buy"


func _buy(item_id: String) -> void:
	var definition := GameState.get_item_definition(item_id)
	if GameState.buy_item(item_id, currency):
		message_changed.emit("已购买：%s" % definition.get("name", item_id))
	else:
		message_changed.emit("金币或魔石不足，或者背包已满。")


func _sell_ore(slot_index: int) -> void:
	var result := GameState.sell_inventory_ore(slot_index, currency)
	if bool(result.get("success", false)):
		message_changed.emit("矿石出售完成，获得 %s %s" % [_format_number(int(result.get("amount", 0))), "魔石" if currency == "magic_stones" else "金币"])
		open_mode(current_mode)
	else:
		message_changed.emit("这件物品不能卖给当前商人。")


func _claim_sale() -> void:
	var result := GameState.claim_merchant_sale(currency)
	if result.get("success", false):
		message_changed.emit("交易完成，获得 %s %s" % [_format_number(int(result.amount)), "魔石" if currency == "magic_stones" else "金币"])
	else:
		message_changed.emit("数值已经接近上限，无法继续增加。")


func _refresh_currency() -> void:
	if currency_label == null:
		return
	var value := GameState.magic_stones if currency == "magic_stones" else GameState.gold
	var unit := "魔石" if currency == "magic_stones" else "金币"
	currency_label.text = "%s：%s" % [unit, _format_number(value)]


func _format_number(value: int) -> String:
	var digits := str(value)
	var output := ""
	while digits.length() > 3:
		output = "," + digits.right(3) + output
		digits = digits.left(digits.length() - 3)
	return digits + output

