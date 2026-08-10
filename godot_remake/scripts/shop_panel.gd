extends PanelContainer

signal message_changed(text: String)

var currency: String = "gold"
var shop_title: String = "杂货商"
var currency_label: Label


func _ready() -> void:
	position = Vector2(170, 120)
	size = Vector2(360, 382)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("5f5f5f")
	style.border_color = Color("202020")
	style.set_border_width_all(3)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = shop_title
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "—"
	close.pressed.connect(func() -> void: hide())
	header.add_child(close)

	currency_label = Label.new()
	root.add_child(currency_label)
	for item_id: String in GameState.item_database:
		var definition := GameState.get_item_definition(item_id)
		var price_key := "price_magic_stones" if currency == "magic_stones" else "price_gold"
		if not definition.has(price_key):
			continue
		root.add_child(_create_shop_row(item_id, definition, price_key))
	GameState.currency_changed.connect(_refresh_currency)
	_refresh_currency()


func _create_shop_row(item_id: String, definition: Dictionary, price_key: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 52)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(46, 46)
	icon.texture = load(str(definition.get("icon", "")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var description := Label.new()
	description.text = "%s\n%s" % [definition.get("name", item_id), definition.get("description", "")]
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	var buy := Button.new()
	buy.text = "购买\n%s" % _format_number(int(definition.get(price_key, 0)))
	buy.custom_minimum_size = Vector2(90, 46)
	buy.pressed.connect(_buy.bind(item_id))
	row.add_child(buy)
	return row


func _buy(item_id: String) -> void:
	var definition := GameState.get_item_definition(item_id)
	if GameState.buy_item(item_id, currency):
		message_changed.emit("购买成功：%s" % definition.get("name", item_id))
	else:
		message_changed.emit("购买失败：货币不足或背包已满")


func _refresh_currency() -> void:
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
