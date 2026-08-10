extends PanelContainer

signal message_changed(text: String)

var root_control: Control
var summary_label: Label
var military_progress_label: Label
var nobility_progress_label: Label
var affection_progress_label: Label
var task_label: Label
var salary_button: Button
var donation_small_button: Button
var donation_large_button: Button
var rose_small_button: Button
var rose_large_button: Button
var magic_task_button: Button
var soul_task_button: Button
var sunday_gift_button: Button
var close_button: Button


func _ready() -> void:
	# The SWF distributes these actions across marshal, prime minister and princess dialogue.
	# Keep them together in a compact right-side native-style flow sheet instead of a large modern form.
	position = Vector2(450, 215)
	size = Vector2(243, 289)
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
	title.text = "成长信息"
	title.position = Vector2(77, 5)
	title.size = Vector2(90, 23)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("ff9900"))
	root_control.add_child(title)
	close_button = _make_close_button(Vector2(216, 4))

	summary_label = _make_label(Vector2(8, 29), Vector2(226, 19), 10, Color("fff0a0"))
	military_progress_label = _make_label(Vector2(8, 51), Vector2(164, 35), 10, Color("ffcc66"))
	salary_button = _make_button("领军饷", Vector2(174, 56), Vector2(60, 23))
	salary_button.pressed.connect(_claim_salary)

	nobility_progress_label = _make_label(Vector2(8, 88), Vector2(226, 30), 10, Color("ffcc66"))
	donation_small_button = _make_button("捐75万", Vector2(8, 116), Vector2(110, 23))
	donation_large_button = _make_button("捐7500万", Vector2(124, 116), Vector2(110, 23))
	donation_small_button.pressed.connect(_donate.bind(750000))
	donation_large_button.pressed.connect(_donate.bind(75000000))

	affection_progress_label = _make_label(Vector2(8, 143), Vector2(226, 30), 10, Color("ff99cc"))
	rose_small_button = _make_button("赠99朵", Vector2(8, 171), Vector2(110, 23))
	rose_large_button = _make_button("赠999朵", Vector2(124, 171), Vector2(110, 23))
	rose_small_button.pressed.connect(_give_roses.bind(99))
	rose_large_button.pressed.connect(_give_roses.bind(999))

	magic_task_button = _make_button("交魔魂晶石", Vector2(8, 200), Vector2(110, 23))
	soul_task_button = _make_button("交灵魂王", Vector2(124, 200), Vector2(110, 23))
	magic_task_button.pressed.connect(_complete_task.bind("collect_magic_soul"))
	soul_task_button.pressed.connect(_complete_task.bind("collect_soul_king"))

	sunday_gift_button = _make_button("周日领取公主礼物", Vector2(8, 229), Vector2(226, 24))
	sunday_gift_button.pressed.connect(_claim_sunday_gift)
	task_label = _make_label(Vector2(8, 257), Vector2(226, 28), 9, Color.WHITE)

	GameState.progression_changed.connect(_refresh)
	GameState.inventory_changed.connect(_refresh)
	GameState.social_changed.connect(_refresh)
	GameState.currency_changed.connect(_refresh)
	_refresh()


func _make_label(label_position: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(label)
	return label


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


func _progress_text(category: String, points: int) -> String:
	var next := GameState.progression_service.next_tier(category, points)
	if next.is_empty():
		return "已达最高等级"
	return "距%s还需%s" % [str(next.name), _format_number(int(next.threshold) - points)]


func _refresh() -> void:
	if summary_label == null:
		return
	var military := GameState.get_military_rank()
	var nobility := GameState.get_nobility_rank()
	var affection_rank := GameState.get_affection_rank()
	var stats := GameState.get_player_stats()
	summary_label.text = "军衔 %s　爵位 %s　关系 %s　战力+%d" % [military.name, nobility.name, affection_rank.name, int(stats.rank_combat_power)]
	military_progress_label.text = "军功 %s　%s\n军衔战斗力 +%d" % [_format_number(GameState.military_merit), _progress_text("military", GameState.military_merit), int(military.combat_power)]
	nobility_progress_label.text = "功勋 %s　%s　爵位战力+%d" % [_format_number(GameState.nobility_merit), _progress_text("nobility", GameState.nobility_merit), int(nobility.combat_power)]
	affection_progress_label.text = "公主亲密度 %s　%s（玫瑰×10）" % [_format_number(GameState.affection), _progress_text("affection", GameState.affection)]
	task_label.text = "第%d天　魔晶任务%s　灵魂王任务%s　玫瑰%d" % [GameState.current_day, "已完成" if GameState.completed_daily_tasks.get("collect_magic_soul", false) else "未完成", "已完成" if GameState.completed_daily_tasks.get("collect_soul_king", false) else "未完成", GameState.count_item("rose")]
	salary_button.disabled = GameState.current_day % 7 != 0 or int(military.level) <= 0 or GameState.last_military_salary_day == GameState.current_day
	magic_task_button.disabled = bool(GameState.completed_daily_tasks.get("collect_magic_soul", false))
	soul_task_button.disabled = bool(GameState.completed_daily_tasks.get("collect_soul_king", false))
	var gift_item_id := GameState.princess_sunday_gift_item_id()
	var gift_name := str(GameState.get_item_definition(gift_item_id).get("name", gift_item_id))
	sunday_gift_button.text = "周日礼物：%s" % gift_name
	sunday_gift_button.disabled = GameState.current_day % 7 != 0 or int(affection_rank.level) <= 0 or GameState.last_princess_gift_day == GameState.current_day


func _claim_salary() -> void:
	var result := GameState.claim_military_salary()
	if result.get("success", false):
		message_changed.emit("领取%s军饷：魔石 +%s" % [str(result.rank_name), _format_number(int(result.magic_stones))])
	else:
		message_changed.emit({"not_sunday":"只有周日可以领取军饷", "no_rank":"获得军衔后才能领取军饷", "already_claimed":"今天已经领取军饷"}.get(str(result.get("reason", "")), "无法领取军饷"))


func _donate(amount: int) -> void:
	var result := GameState.donate_gold_for_nobility(amount)
	if result.get("success", false):
		message_changed.emit("捐献成功：消耗%s金币，功勋 +%s" % [_format_number(int(result.gold_cost)), _format_number(int(result.nobility_merit))])
	else:
		message_changed.emit("金币不足750,000，无法兑换功勋")


func _give_roses(count: int) -> void:
	var result := GameState.give_roses(count)
	if result.get("success", false):
		message_changed.emit("赠送%s朵玫瑰，亲密度 +%d" % [_format_number(count), int(result.affection)])
	else:
		message_changed.emit("玫瑰不足：需要%s朵" % _format_number(count))


func _complete_task(task_id: String) -> void:
	var result := GameState.complete_daily_task(task_id)
	if result.get("success", false):
		message_changed.emit("每日功勋任务完成：功勋 +%s" % _format_number(int(result.nobility_merit)))
	elif result.get("reason", "") == "already_completed":
		message_changed.emit("今天已经完成过这个任务")
	else:
		message_changed.emit("缺少任务物品")


func _claim_sunday_gift() -> void:
	var result := GameState.claim_princess_sunday_gift()
	if result.get("success", false):
		message_changed.emit("公主赠送了：%s" % GameState.get_item_definition(result.item_id).get("name", result.item_id))
	elif result.get("reason", "") == "inventory_full":
		message_changed.emit("背包已满，礼物尚未领取")
	elif result.get("reason", "") == "already_claimed":
		message_changed.emit("今天已经领取过公主礼物")
	else:
		message_changed.emit("只有认识公主后的周日才能领取礼物")


func _format_number(value: int) -> String:
	var digits := str(value)
	var output := ""
	while digits.length() > 3:
		output = "," + digits.right(3) + output
		digits = digits.left(digits.length() - 3)
	return digits + output