extends PanelContainer

signal message_changed(text: String)
signal mail_requested
signal trade_requested

var close_button: Button
var name_list: ItemList
var detail_label: Label
var gift_button: Button
var accept_button: Button
var claim_button: Button
var mail_button: Button
var trade_button: Button
var selected_id: String = ""
var _ids: Array[String] = []


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
	title.text = "\u5192\u9669\u8005\u516c\u544a\u677f"
	title.position = Vector2(8, 4)
	title.size = Vector2(200, 22)
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

	name_list = ItemList.new()
	name_list.position = Vector2(6, 30)
	name_list.size = Vector2(140, 250)
	name_list.item_selected.connect(_on_selected)
	root.add_child(name_list)

	detail_label = Label.new()
	detail_label.position = Vector2(152, 30)
	detail_label.size = Vector2(204, 250)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.clip_text = true
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color("3d210f"))
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(detail_label)

	gift_button = _make_button("\u9001\u793c(\u73ab\u7470)", Vector2(6, 288), Vector2(110, 24), root)
	accept_button = _make_button("\u63a5\u53d6\u59d4\u6258", Vector2(126, 288), Vector2(110, 24), root)
	claim_button = _make_button("\u9886\u53d6\u5956\u52b1", Vector2(246, 288), Vector2(110, 24), root)
	mail_button = _make_button("\u90ae\u4ef6", Vector2(6, 316), Vector2(170, 24), root)
	trade_button = _make_button("\u4ea4\u6613", Vector2(186, 316), Vector2(170, 24), root)
	gift_button.pressed.connect(_gift_rose)
	accept_button.pressed.connect(_accept_commission)
	claim_button.pressed.connect(_claim_commission)
	mail_button.pressed.connect(func() -> void: mail_requested.emit())
	trade_button.pressed.connect(func() -> void: trade_requested.emit())

	var hint := Label.new()
	hint.position = Vector2(8, 346)
	hint.size = Vector2(346, 24)
	hint.text = "\u5173\u7cfb\u53ea\u6539\u540d\u518c\u4e0e\u59d4\u6258\uff0c\u4e0d\u5f71\u54cd\u4e3b\u7ebf\u3002"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color("5b2e16"))
	root.add_child(hint)

	GameState.social_changed.connect(_refresh)
	visibility_changed.connect(_refresh)
	_refresh()


func _make_button(text_value: String, button_position: Vector2, button_size: Vector2, parent: Control) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = button_position
	button.size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 10)
	parent.add_child(button)
	return button


func _refresh() -> void:
	if not visible:
		return
	var svc = GameState.expansion_state_service.adventurer_service
	_ids = svc.all_ids()
	name_list.clear()
	for adv_id in _ids:
		var row: Dictionary = svc.get_adventurer(adv_id)
		name_list.add_item(str(row.get("display_name", adv_id)))
	if selected_id.is_empty() and not _ids.is_empty():
		selected_id = _ids[0]
	var idx := _ids.find(selected_id)
	if idx >= 0:
		name_list.select(idx)
	_render_detail()


func _on_selected(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	selected_id = _ids[index]
	_render_detail()


func _render_detail() -> void:
	if selected_id.is_empty():
		detail_label.text = ""
		return
	var adv: Dictionary = GameState.expansion_state_service.adventurer_service.get_adventurer(selected_id)
	var rel: Dictionary = GameState.expansion_state.get("relationships", {}).get(selected_id, {})
	var value := int(rel.get("value", 0))
	var stage: Dictionary = GameState.expansion_state_service.relationship_service.stage_for(value)
	var nxt: Dictionary = GameState.expansion_state_service.relationship_service.next_stage(value)
	var history: Array = rel.get("history", [])
	var last_three: Array = history.slice(maxi(0, history.size() - 3), history.size())
	var hist_text := ""
	for raw_event: Variant in last_three:
		if raw_event is Dictionary:
			hist_text += "\n%s %+d" % [str(raw_event.get("reason", "")), int(raw_event.get("delta", 0))]
	var comm: Dictionary = _commission_for(selected_id)
	var comm_line := "\u672c\u7248\u65e0\u59d4\u6258"
	if not comm.is_empty():
		var runtime: Dictionary = GameState.expansion_state.get("commission_state", {}).get(str(comm.get("id", "")), {})
		comm_line = "%s [%s]" % [str(comm.get("display_name", "")), str(runtime.get("status", "available"))]
	var next_line := "\u5df2\u8fbe\u6700\u9ad8\u9636\u6bb5"
	if not nxt.is_empty():
		next_line = "\u4e0b\u4e00\u9636\u6bb5 %s @ %d" % [str(nxt.get("name", "")), int(nxt.get("threshold", 0))]
	detail_label.text = "%s\n%s\n\u5173\u7cfb %d ( %s )\n%s\n\u59d4\u6258\uff1a %s\n\u6700\u8fd1\uff1a %s" % [
		str(adv.get("display_name", selected_id)),
		str(adv.get("role", "")),
		value,
		str(stage.get("name", "\u8ba4\u8bc6")),
		next_line,
		comm_line,
		hist_text if not hist_text.is_empty() else "\u65e0",
	]


func _commission_for(adv_id: String) -> Dictionary:
	var svc = GameState.expansion_state_service.commission_service
	for comm_id in svc.all_ids():
		var template: Dictionary = svc.get_template(comm_id)
		if str(template.get("adventurer_id", "")) == adv_id:
			return template
	return {}


func _gift_rose() -> void:
	if selected_id.is_empty():
		return
	var op := "ui_gift:%s:rose:d%d:n%d" % [
		selected_id,
		GameState.current_day,
		_history_size(selected_id),
	]
	var result: Dictionary = GameState.gift_adventurer(selected_id, "rose", op)
	_emit_result(result, "\u5df2\u9001\u51fa\u73ab\u7470")


func _accept_commission() -> void:
	var comm: Dictionary = _commission_for(selected_id)
	if comm.is_empty():
		message_changed.emit("\u6b64\u4eba\u672c\u7248\u6ca1\u6709\u59d4\u6258\u3002")
		return
	var comm_id := str(comm.get("id", ""))
	var result: Dictionary = GameState.accept_commission(comm_id, "ui_accept:%s" % comm_id)
	_emit_result(result, "\u5df2\u63a5\u53d6\u59d4\u6258")


func _claim_commission() -> void:
	var comm: Dictionary = _commission_for(selected_id)
	if comm.is_empty():
		message_changed.emit("\u6b64\u4eba\u672c\u7248\u6ca1\u6709\u59d4\u6258\u3002")
		return
	var comm_id := str(comm.get("id", ""))
	var result: Dictionary = GameState.claim_commission(comm_id, "ui_claim:%s" % comm_id)
	_emit_result(result, "\u5df2\u9886\u53d6\u59d4\u6258\u5956\u52b1")


func _history_size(adv_id: String) -> int:
	var rel: Variant = GameState.expansion_state.get("relationships", {}).get(adv_id, {})
	if rel is Dictionary:
		return (rel.get("history", []) as Array).size()
	return 0


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
