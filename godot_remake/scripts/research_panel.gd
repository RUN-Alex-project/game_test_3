extends PanelContainer

signal message_changed(text: String)

var root_control: Control
var info_label: Label
var material_label: Label
var fund_button: Button
var production_task_button: Button
var buy_button: Button
var close_button: Button


func _ready() -> void:
	# SWF sprite827 / shape823: show=(250,180), native bounds 203x183.
	position = Vector2(250, 180)
	size = Vector2(203, 183)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("666666")
	style.border_color = Color("202020")
	style.set_border_width_all(2)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)

	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root_control)

	var title := Label.new()
	title.text = "幻兽研究所"
	title.position = Vector2(61.85, 11.1)
	title.size = Vector2(111, 22)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("ff9900"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(title)
	close_button = _make_close_button(Vector2(172.5, 6.95))

	info_label = Label.new()
	info_label.position = Vector2(5, 37.65)
	info_label.size = Vector2(192, 68)
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color("fff0a0"))
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(info_label)

	production_task_button = _make_button("完成产量任务（+2）", Vector2(5, 108), Vector2(145, 24))
	production_task_button.pressed.connect(_production_task)
	buy_button = _make_button("购买", Vector2(155, 108), Vector2(42, 24))
	buy_button.pressed.connect(_buy_pet)

	material_label = Label.new()
	material_label.position = Vector2(5, 137)
	material_label.size = Vector2(128, 40)
	material_label.add_theme_font_size_override("font_size", 9)
	material_label.add_theme_color_override("font_color", Color.WHITE)
	material_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	material_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(material_label)
	fund_button = _make_button("资助", Vector2(136.5, 147.05), Vector2(60, 24))
	fund_button.pressed.connect(_fund)

	GameState.research_changed.connect(refresh)
	GameState.inventory_changed.connect(refresh)
	GameState.currency_changed.connect(refresh)
	GameState.time_changed.connect(refresh)
	refresh()


func _make_button(text_value: String, button_position: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = button_position
	button.size = button_size
	button.custom_minimum_size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color.WHITE)
	for state_data in [["normal", Color("666666")], ["hover", Color("999999")], ["pressed", Color("333333")], ["disabled", Color("505050")]]:
		var state_style := StyleBoxFlat.new()
		state_style.bg_color = state_data[1]
		state_style.border_color = Color("202020")
		state_style.set_border_width_all(1)
		button.add_theme_stylebox_override(str(state_data[0]), state_style)
	root_control.add_child(button)
	button.size = button_size
	return button


func _make_close_button(button_position: Vector2) -> Button:
	var button := Button.new()
	button.text = ""
	button.position = button_position
	button.size = Vector2(21, 21)
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ff9900")
	style.border_color = Color("202020")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 11
	style.corner_radius_top_right = 11
	style.corner_radius_bottom_left = 11
	style.corner_radius_bottom_right = 11
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(hide)
	root_control.add_child(button)
	return button


func _fund() -> void:
	message_changed.emit("研究所技术提升1级" if GameState.fund_pet_research() else "魔石不足或技术已达到300级")


func _production_task() -> void:
	var result := GameState.complete_research_production_task()
	if result.get("success", false):
		message_changed.emit("产量任务完成：日产量 +2")
	elif result.get("reason", "") == "rate_cap":
		message_changed.emit("日产量已经达到上限6")
	else:
		message_changed.emit("需要%d个灵魂王" % int(result.get("required", GameState.pet_service.production_task_cost(GameState.research))))


func _buy_pet() -> void:
	var result := GameState.buy_research_pet()
	if result.get("success", false):
		message_changed.emit("获得%.2f星奇异兽，消耗%d魔石" % [float(result.pet.quality_score) / 100.0, int(result.price)])
	else:
		message_changed.emit({"no_stock":"研究所没有库存", "pet_inventory_full":"幻兽仓已满", "not_enough_magic_stones":"魔石不足"}.get(str(result.get("reason", "")), "购买失败"))


func refresh() -> void:
	if not is_node_ready():
		return
	var state: Dictionary = GameState.research
	var level := float(state.get("technology_level", 0.0))
	var quality := GameState.pet_service.research_pet_quality(state) / 100.0
	var price := GameState.pet_service.research_pet_price(state)
	if level < 20.0:
		info_label.text = "技术等级：%.2f / 300\n技术20级前不能生产\n日产量：%d / 6　库存：%d / 100\n跨日自动生产，每7天技术自然增长10%%" % [level, int(state.get("production_rate", 0)), int(state.get("stock", 0))]
	else:
		info_label.text = "技术等级：%.2f / 300\n出产幻兽：%.2f星奇异兽\n售价：%d魔石　库存：%d个\n生产量：%d个/天　VIP：%d星" % [level, quality, price, int(state.get("stock", 0)), int(state.get("production_rate", 0)), int(state.get("vip_level", 0))]
	var required := GameState.pet_service.production_task_cost(state)
	material_label.text = "灵魂王：%d\n下次产量任务需要：%d个" % [GameState.count_item("soul_king"), required]
	buy_button.disabled = level < 20.0 or int(state.get("stock", 0)) <= 0
	production_task_button.disabled = int(state.get("production_rate", 0)) >= 6
	fund_button.disabled = level >= 300.0