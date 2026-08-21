extends PanelContainer

signal message_changed(text: String)

var close_button: Button
var detail_label: Label
var buy_button: Button
var sell_button: Button
var selected_id: String = "npc_adv_lin_xia"


func _ready() -> void:
	position = Vector2(169, 90)
	size = Vector2(362, 350)
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
	title.text = "\u5192\u9669\u8005\u4ea4\u6613"
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
	for state in ["normal", "hover", "pressed"]:
		close_button.add_theme_stylebox_override(state, close_style)
	close_button.pressed.connect(hide)
	root.add_child(close_button)

	detail_label = Label.new()
	detail_label.position = Vector2(12, 32)
	detail_label.size = Vector2(338, 240)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 11)
	detail_label.add_theme_color_override("font_color", Color("3d210f"))
	root.add_child(detail_label)

	buy_button = Button.new()
	buy_button.text = "\u4e70\u5165\u73ab\u7470"
	buy_button.position = Vector2(6, 288)
	buy_button.size = Vector2(170, 24)
	buy_button.focus_mode = Control.FOCUS_NONE
	buy_button.pressed.connect(_buy_rose)
	root.add_child(buy_button)

	sell_button = Button.new()
	sell_button.text = "\u5356\u51fa\u73ab\u7470"
	sell_button.position = Vector2(186, 288)
	sell_button.size = Vector2(170, 24)
	sell_button.focus_mode = Control.FOCUS_NONE
	sell_button.pressed.connect(_sell_rose)
	root.add_child(sell_button)

	var hint := Label.new()
	hint.position = Vector2(8, 318)
	hint.size = Vector2(346, 24)
	hint.text = "\u4ef7\u683c\u8d70\u6570\u636e\uff0c\u5931\u8d25\u4e0d\u6539\u8d26\u672c\u3002"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color("5b2e16"))
	root.add_child(hint)

	GameState.social_changed.connect(_refresh)
	GameState.currency_changed.connect(_refresh)
	GameState.inventory_changed.connect(_refresh)
	visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	if selected_id.is_empty():
		selected_id = "npc_adv_lin_xia"
	var adv: Dictionary = GameState.expansion_state_service.adventurer_service.get_adventurer(selected_id)
	var ledger: Dictionary = GameState.expansion_state.get("economy", {}).get("adventurer_ledgers", {}).get(selected_id, {})
	var items: Dictionary = ledger.get("items", {})
	var roses := 0
	if items is Dictionary:
		roses = int((items.get("rose", {}) as Dictionary).get("quantity", 0))
	detail_label.text = "%s\nNPC \u91d1\u5e01 %d\nNPC \u73ab\u7470 %d\n\u73a9\u5bb6\u91d1\u5e01 %d\n\u73a9\u5bb6\u73ab\u7470 %d\n\u4e70\u5165\u4ef7 15 / \u5356\u51fa\u4ef7 10" % [
		str(adv.get("display_name", selected_id)),
		int(ledger.get("gold", 0)),
		roses,
		GameState.gold,
		GameState.count_item("rose"),
	]


func _buy_rose() -> void:
	var op := "ui_buy:%s:rose:d%d:%d" % [selected_id, GameState.current_day, GameState.count_item("rose")]
	var result: Dictionary = GameState.buy_from_adventurer(selected_id, "rose", 1, op)
	_emit_result(result, "\u5df2\u4e70\u5165\u73ab\u7470")


func _sell_rose() -> void:
	var op := "ui_sell:%s:rose:d%d:%d" % [selected_id, GameState.current_day, GameState.count_item("rose")]
	var result: Dictionary = GameState.sell_to_adventurer(selected_id, "rose", 1, op)
	_emit_result(result, "\u5df2\u5356\u51fa\u73ab\u7470")


func _emit_result(result: Dictionary, ok_text: String) -> void:
	if bool(result.get("replayed", false)):
		message_changed.emit("\u64cd\u4f5c\u5df2\u5904\u7406\uff0c\u672a\u91cd\u590d\u7ed3\u7b97\u3002")
		_refresh()
		return
	if bool(result.get("success", false)):
		message_changed.emit(ok_text)
	else:
		message_changed.emit("\u5931\u8d25\uff1a %s" % str(result.get("code", "ERR")))
	_refresh()
