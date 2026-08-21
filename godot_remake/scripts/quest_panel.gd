extends PanelContainer

const WorldService = preload("res://scripts/world_service.gd")

signal message_changed(text: String)
signal navigation_requested(map_id: String)

var world_service := WorldService.new()
var root_control: Control
var main_flow_label: Label
var main_target_button: Button
var close_button: Button
var quest_cards: Dictionary = {}
var quest_labels: Dictionary = {}
var quest_buttons: Dictionary = {}
var footer_label: Label


func _ready() -> void:
	# Reuse the native dialogue sheet proportions for a compact, fixed three-quest ledger.
	position = Vector2(200, 80)
	size = Vector2(362, 269.3)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ffcc99")
	style.border_color = Color("805b3c")
	style.set_border_width_all(2)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)

	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root_control)

	var title := Label.new()
	title.text = "任务与主线"
	title.position = Vector2(8, 4)
	title.size = Vector2(120, 24)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("7a3200"))
	root_control.add_child(title)
	close_button = _make_close_button(Vector2(338.5, 2))

	var flow_panel := Panel.new()
	flow_panel.position = Vector2(5, 30)
	flow_panel.size = Vector2(352, 67)
	var flow_style := StyleBoxFlat.new()
	flow_style.bg_color = Color("ffcc66")
	flow_style.border_color = Color("9a5c2f")
	flow_style.set_border_width_all(1)
	flow_panel.add_theme_stylebox_override("panel", flow_style)
	root_control.add_child(flow_panel)
	main_flow_label = Label.new()
	main_flow_label.position = Vector2(6, 4)
	main_flow_label.size = Vector2(270, 58)
	main_flow_label.add_theme_font_size_override("font_size", 10)
	main_flow_label.add_theme_color_override("font_color", Color("3d210f"))
	main_flow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_flow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow_panel.add_child(main_flow_label)
	main_target_button = _make_button("查看路线", Vector2(278, 21), Vector2(68, 25), flow_panel)
	main_target_button.pressed.connect(_show_main_route)

	var quest_ids: Array[String] = ["dungeon_conquest", "border_raid", "spider_crisis"]
	for index in quest_ids.size():
		_build_quest_row(quest_ids[index], 102 + index * 48)
	footer_label = Label.new()
	footer_label.position = Vector2(8, 249)
	footer_label.size = Vector2(346, 17)
	footer_label.add_theme_font_size_override("font_size", 9)
	footer_label.add_theme_color_override("font_color", Color("5b2e16"))
	footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(footer_label)

	GameState.quests_changed.connect(_refresh)
	GameState.story_changed.connect(_refresh)
	GameState.time_changed.connect(_refresh)
	visibility_changed.connect(_refresh)
	_refresh()


func _build_quest_row(quest_id: String, y_position: float) -> void:
	var card := Panel.new()
	card.position = Vector2(5, y_position)
	card.size = Vector2(352, 44)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("e6ad73")
	style.border_color = Color("9a5c2f")
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)
	root_control.add_child(card)
	var label := Label.new()
	label.position = Vector2(5, 3)
	label.size = Vector2(272, 38)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("3d210f"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	var button := _make_button("接取", Vector2(282, 10), Vector2(64, 24), card)
	button.pressed.connect(_quest_action.bind(quest_id))
	quest_cards[quest_id] = card
	quest_labels[quest_id] = label
	quest_buttons[quest_id] = button


func _make_button(text_value: String, button_position: Vector2, button_size: Vector2, parent: Control) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = button_position
	button.size = button_size
	button.custom_minimum_size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color("3d210f"))
	for state_data in [["normal", Color("ffcc99")], ["hover", Color("ffcc66")], ["pressed", Color("ff9900")], ["disabled", Color("d2a477")]]:
		var state_style := StyleBoxFlat.new()
		state_style.bg_color = state_data[1]
		state_style.border_color = Color("805b3c")
		state_style.set_border_width_all(1)
		button.add_theme_stylebox_override(str(state_data[0]), state_style)
	parent.add_child(button)
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


func _status_name(status: String) -> String:
	return {"available":"可接取", "active":"进行中", "ready":"可领取", "completed":"已完成"}.get(status, "未知")


func _quest_action(quest_id: String) -> void:
	var status := str(GameState.quest_states.get(quest_id, {}).get("status", "available"))
	if status == "available":
		_accept(quest_id)
	elif status == "ready":
		_claim(quest_id)
	else:
		message_changed.emit("%s：%s" % [GameState.quest_service.quests[quest_id].name, _status_name(status)])


func _accept(quest_id: String) -> void:
	if GameState.accept_quest(quest_id):
		message_changed.emit("已接取：%s" % GameState.quest_service.quests[quest_id].name)
	else:
		message_changed.emit("任务当前无法接取")


func _claim(quest_id: String) -> void:
	var result := GameState.claim_quest(quest_id)
	if result.get("success", false):
		message_changed.emit("任务完成：%s" % GameState.quest_service.quests[quest_id].name)
	else:
		message_changed.emit("任务目标尚未完成")


func _show_main_route() -> void:
	var flow := GameState.get_main_flow_state()
	var route := world_service.shortest_route(GameState.current_map_id, str(flow.target_map))
	var names := world_service.route_names(route)
	var route_text := " → ".join(names) if not names.is_empty() else str(flow.target_name)
	if str(flow.target_map) == "dungeon" and GameState.current_map_id == "cassano_city":
		route_text += "（找日常任务官进入）"
	message_changed.emit("主线路线：%s" % route_text)
	navigation_requested.emit(str(flow.target_map))


func _refresh() -> void:
	if main_flow_label == null:
		return
	var flow := GameState.get_main_flow_state()
	main_flow_label.text = "主线 %d/%d　%s\n%s" % [int(flow.step), int(flow.total), str(flow.title), str(flow.objective)]
	main_target_button.text = "已通关" if str(flow.stage) == "complete" else "去%s" % str(flow.target_name)
	main_target_button.disabled = str(flow.stage) == "complete"
	var route := world_service.shortest_route(GameState.current_map_id, str(flow.target_map))
	main_target_button.tooltip_text = " → ".join(world_service.route_names(route))
	for quest_id: String in quest_cards:
		var definition: Dictionary = GameState.quest_service.quests[quest_id]
		var state: Dictionary = GameState.quest_states.get(quest_id, {"status":"available", "progress":{}})
		var status := str(state.get("status", "available"))
		var progress_lines := GameState.quest_service.progress_lines(GameState.quest_states, quest_id)
		var progress_text := "　".join(progress_lines)
		quest_labels[quest_id].text = "%s　[%s]\n%s" % [str(definition.get("name", quest_id)), _status_name(status), progress_text if status in ["active", "ready"] else str(definition.get("description", ""))]
		var button: Button = quest_buttons[quest_id]
		button.text = {"available":"接取", "active":"进行中", "ready":"领取", "completed":"已完成"}.get(status, "查看")
		button.disabled = status in ["active", "completed"]
	footer_label.text = "第%d天　主线完成度 %d/%d　%s" % [GameState.current_day, int(flow.step), int(flow.total), GameState.chapter_board_text()]