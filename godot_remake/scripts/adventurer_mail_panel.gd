extends PanelContainer

signal message_changed(text: String)

var close_button: Button
var mail_list: ItemList
var detail_label: Label
var claim_button: Button
var _mail_ids: Array[String] = []


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
	title.text = "\u5192\u9669\u8005\u90ae\u4ef6"
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

	mail_list = ItemList.new()
	mail_list.position = Vector2(6, 30)
	mail_list.size = Vector2(140, 250)
	mail_list.item_selected.connect(_on_selected)
	root.add_child(mail_list)

	detail_label = Label.new()
	detail_label.position = Vector2(152, 30)
	detail_label.size = Vector2(204, 250)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.clip_text = true
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color("3d210f"))
	root.add_child(detail_label)

	claim_button = Button.new()
	claim_button.text = "\u9886\u53d6\u9644\u4ef6"
	claim_button.position = Vector2(6, 288)
	claim_button.size = Vector2(350, 24)
	claim_button.focus_mode = Control.FOCUS_NONE
	claim_button.pressed.connect(_claim_selected)
	root.add_child(claim_button)

	var hint := Label.new()
	hint.position = Vector2(8, 318)
	hint.size = Vector2(346, 24)
	hint.text = "\u80cc\u5305\u6ee1\u65f6\u9644\u4ef6\u4fdd\u7559\u5728\u90ae\u4ef6\u91cc\u3002"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color("5b2e16"))
	root.add_child(hint)

	GameState.social_changed.connect(_refresh)
	visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	_mail_ids.clear()
	mail_list.clear()
	for raw_mail: Variant in GameState.expansion_state.get("mailbox", []):
		if not raw_mail is Dictionary:
			continue
		var mail: Dictionary = raw_mail
		if str(mail.get("recipient", "")) != "player":
			continue
		if bool(mail.get("claimed", false)) or bool(mail.get("expired", false)):
			continue
		_mail_ids.append(str(mail.get("mail_id", "")))
		mail_list.add_item(str(mail.get("subject", mail.get("mail_id", ""))))
	if not _mail_ids.is_empty():
		mail_list.select(0)
		_render_detail(0)
	else:
		detail_label.text = "\u6ca1\u6709\u672a\u9886\u90ae\u4ef6\u3002"


func _on_selected(index: int) -> void:
	_render_detail(index)


func _render_detail(index: int) -> void:
	if index < 0 or index >= _mail_ids.size():
		detail_label.text = ""
		return
	var mail_id := _mail_ids[index]
	for raw_mail: Variant in GameState.expansion_state.get("mailbox", []):
		if not raw_mail is Dictionary:
			continue
		if str(raw_mail.get("mail_id", "")) != mail_id:
			continue
		var atts: Array = raw_mail.get("attachments", [])
		var att_text := "\u65e0"
		if not atts.is_empty() and atts[0] is Dictionary:
			att_text = "%s x%d" % [str(atts[0].get("item_id", "")), int(atts[0].get("quantity", 0))]
		detail_label.text = "%s\n%s\n%s\n\u9644\u4ef6 %s" % [
			str(raw_mail.get("subject", "")),
			str(raw_mail.get("sender_id", "")),
			str(raw_mail.get("body", "")),
			att_text,
		]
		return


func _claim_selected() -> void:
	if mail_list.get_selected_items().is_empty():
		if _mail_ids.is_empty():
			message_changed.emit("\u6ca1\u6709\u53ef\u9886\u90ae\u4ef6\u3002")
			return
		mail_list.select(0)
	var index: int = mail_list.get_selected_items()[0]
	if index < 0 or index >= _mail_ids.size():
		return
	var mail_id := _mail_ids[index]
	var result: Dictionary = GameState.claim_mail(mail_id, "ui_claim_mail:%s" % mail_id)
	if bool(result.get("replayed", false)):
		message_changed.emit("\u64cd\u4f5c\u5df2\u5904\u7406\uff0c\u672a\u91cd\u590d\u7ed3\u7b97\u3002")
	elif bool(result.get("success", false)):
		message_changed.emit("\u5df2\u9886\u53d6\u90ae\u4ef6\u3002")
	else:
		message_changed.emit("\u5931\u8d25\uff1a %s" % str(result.get("code", "ERR")))
	_refresh()
