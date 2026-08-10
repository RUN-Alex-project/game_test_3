extends PanelContainer

signal message_changed(text: String)

const PETS_PER_PAGE := 4
const PET_PORTRAITS := {
	"attack_defense_light":"res://assets/extracted/images/image_0738.jpg",
	"attack_defense_heavy":"res://assets/extracted/images/image_0744.jpg",
	"strange_beast":"res://assets/extracted/images/image_0740.jpg",
	"year_pig":"res://assets/extracted/images/image_0748.jpg",
	"lulu_pet":"res://assets/extracted/images/image_0742.jpg",
	"holy_angel":"res://assets/extracted/images/image_0750.jpg",
}
const PET_DEFAULT_NAMES := {
	"attack_defense_light":"攻防型·轻甲",
	"attack_defense_heavy":"攻防型·重甲",
	"strange_beast":"奇异兽",
	"year_pig":"年猪",
	"lulu_pet":"噜噜幻兽",
	"holy_angel":"圣天使幻兽",
}

var root_control: Control
var row_panels: Array[Panel] = []
var row_icons: Array[TextureRect] = []
var row_labels: Array[Label] = []
var row_instance_ids: Array[int] = []
var current_page := 0
var selected_instance_id_value := 0

var deploy_button: Button
var detail_button: Button
var discard_button: Button
var previous_button: Button
var next_button: Button
var page_label: Label
var close_button: Button

var detail_panel: PanelContainer
var detail_info_label: Label
var detail_icon: TextureRect
var rename_button: Button
var rename_edit: LineEdit
var rename_confirm_button: Button
var train_button: Button
var submit_button: Button
var secondary_selector: OptionButton
var fusion_button: Button
var detail_status_label: Label
var detail_close_button: Button

var discard_confirmation: PanelContainer
var discard_question_label: Label
var discard_yes_button: Button
var discard_no_button: Button


func _ready() -> void:
	position = Vector2(0, 150)
	size = Vector2(213, 333)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("666666")
	panel_style.border_color = Color("202020")
	panel_style.set_border_width_all(2)
	panel_style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", panel_style)

	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root_control)

	for row_index in PETS_PER_PAGE:
		_build_pet_row(row_index)
	_build_navigation()
	_build_detail_panel()
	_build_discard_confirmation()

	GameState.pets_changed.connect(refresh)
	GameState.inventory_changed.connect(refresh)
	GameState.progression_changed.connect(refresh)
	refresh()


func _build_pet_row(row_index: int) -> void:
	var row := Panel.new()
	row.position = Vector2(10, 12 + row_index * 70)
	row.size = Vector2(193, 69)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_input.bind(row_index))
	root_control.add_child(row)

	var icon := TextureRect.new()
	icon.position = Vector2(4, 4)
	icon.size = Vector2(60, 61)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var label := Label.new()
	label.position = Vector2(68.6, 6)
	label.size = Vector2(119, 57)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("ff9900"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	row_panels.append(row)
	row_icons.append(icon)
	row_labels.append(label)
	row_instance_ids.append(0)


func _build_navigation() -> void:
	previous_button = Button.new()
	previous_button.text = "◀"
	previous_button.position = Vector2(5, 300)
	previous_button.size = Vector2(24, 27)
	_style_page_button(previous_button)
	previous_button.pressed.connect(_change_page.bind(-1))
	root_control.add_child(previous_button)

	page_label = Label.new()
	page_label.position = Vector2(30, 305.4)
	page_label.size = Vector2(55, 21)
	page_label.add_theme_font_size_override("font_size", 12)
	page_label.add_theme_color_override("font_color", Color("ff9900"))
	page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(page_label)

	next_button = Button.new()
	next_button.text = "▶"
	next_button.position = Vector2(87, 298)
	next_button.size = Vector2(24, 27)
	_style_page_button(next_button)
	next_button.pressed.connect(_change_page.bind(1))
	root_control.add_child(next_button)

	discard_button = _make_native_button("丢弃", Vector2(117, 302), Vector2(42, 24))
	discard_button.pressed.connect(_show_discard_confirmation)
	detail_button = _make_native_button("详细", Vector2(164, 302), Vector2(42, 24))
	detail_button.pressed.connect(_show_detail)

	close_button = Button.new()
	close_button.text = ""
	close_button.position = Vector2(192, 0)
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
	close_button.add_theme_stylebox_override("normal", close_style)
	close_button.add_theme_stylebox_override("hover", close_style)
	close_button.add_theme_stylebox_override("pressed", close_style)
	close_button.pressed.connect(hide)
	root_control.add_child(close_button)

	deploy_button = _make_native_button("出征", Vector2(164.7, 18.55), Vector2(42, 24))
	deploy_button.pressed.connect(_toggle_deployment)
	deploy_button.hide()


func _build_detail_panel() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.position = Vector2(210, 0)
	detail_panel.size = Vector2(213, 333)
	detail_panel.custom_minimum_size = Vector2(213, 333)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("666666")
	style.border_color = Color("202020")
	style.set_border_width_all(2)
	style.set_content_margin_all(0)
	detail_panel.add_theme_stylebox_override("panel", style)
	root_control.add_child(detail_panel)

	var detail_root := Control.new()
	detail_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_panel.add_child(detail_root)

	detail_info_label = Label.new()
	detail_info_label.position = Vector2(5, 5)
	detail_info_label.size = Vector2(145, 105)
	detail_info_label.add_theme_font_size_override("font_size", 11)
	detail_info_label.add_theme_color_override("font_color", Color("ff9900"))
	detail_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_child(detail_info_label)

	detail_icon = TextureRect.new()
	detail_icon.position = Vector2(145, 5)
	detail_icon.size = Vector2(64, 64)
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_child(detail_icon)

	rename_button = _make_native_button("改名", Vector2(5, 113.35), Vector2(42, 24), detail_root)
	rename_button.pressed.connect(func() -> void: rename_edit.grab_focus())
	rename_edit = LineEdit.new()
	rename_edit.position = Vector2(5, 140)
	rename_edit.size = Vector2(154, 28)
	rename_edit.max_length = 6
	rename_edit.add_theme_font_size_override("font_size", 12)
	detail_root.add_child(rename_edit)
	rename_confirm_button = _make_native_button("确定", Vector2(164, 142), Vector2(42, 24), detail_root)
	rename_confirm_button.pressed.connect(_rename_selected)
	rename_edit.text_submitted.connect(func(_text: String) -> void: _rename_selected())

	train_button = _make_native_button("使用经验球", Vector2(5, 174), Vector2(96, 24), detail_root)
	train_button.pressed.connect(_train_selected)
	submit_button = _make_native_button("上交日常", Vector2(106, 174), Vector2(101, 24), detail_root)
	submit_button.pressed.connect(_submit_selected)

	secondary_selector = OptionButton.new()
	secondary_selector.position = Vector2(5, 204)
	secondary_selector.size = Vector2(202, 28)
	secondary_selector.add_theme_font_size_override("font_size", 11)
	detail_root.add_child(secondary_selector)
	fusion_button = _make_native_button("以所选幻兽进行幻化", Vector2(5, 236), Vector2(202, 24), detail_root)
	fusion_button.pressed.connect(_fuse_selected)

	detail_status_label = Label.new()
	detail_status_label.position = Vector2(5, 264)
	detail_status_label.size = Vector2(202, 34)
	detail_status_label.add_theme_font_size_override("font_size", 10)
	detail_status_label.add_theme_color_override("font_color", Color("fff0a0"))
	detail_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_child(detail_status_label)

	detail_close_button = _make_native_button("关闭", Vector2(160, 302), Vector2(46, 24), detail_root)
	detail_close_button.pressed.connect(detail_panel.hide)
	detail_panel.hide()


func _build_discard_confirmation() -> void:
	discard_confirmation = PanelContainer.new()
	discard_confirmation.position = Vector2(6, 93)
	discard_confirmation.size = Vector2(203, 123)
	discard_confirmation.custom_minimum_size = Vector2(203, 123)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("cc9933")
	style.border_color = Color("392614")
	style.set_border_width_all(2)
	style.set_content_margin_all(0)
	discard_confirmation.add_theme_stylebox_override("panel", style)
	root_control.add_child(discard_confirmation)
	var confirm_root := Control.new()
	confirm_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	discard_confirmation.add_child(confirm_root)
	discard_question_label = Label.new()
	discard_question_label.position = Vector2(10, 18)
	discard_question_label.size = Vector2(183, 48)
	discard_question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discard_question_label.add_theme_font_size_override("font_size", 13)
	discard_question_label.add_theme_color_override("font_color", Color("202020"))
	confirm_root.add_child(discard_question_label)
	discard_yes_button = _make_native_button("确定", Vector2(44, 79), Vector2(50, 25), confirm_root)
	discard_yes_button.pressed.connect(_confirm_discard)
	discard_no_button = _make_native_button("取消", Vector2(109, 79), Vector2(50, 25), confirm_root)
	discard_no_button.pressed.connect(discard_confirmation.hide)
	discard_confirmation.hide()


func _make_native_button(text_value: String, button_position: Vector2, button_size: Vector2, parent: Control = null) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = button_position
	button.size = button_size
	button.custom_minimum_size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color.WHITE)
	for state_data in [["normal", Color("666666")], ["hover", Color("999999")], ["pressed", Color("333333")]]:
		var state_style := StyleBoxFlat.new()
		state_style.bg_color = state_data[1]
		state_style.border_color = Color("202020")
		state_style.set_border_width_all(1)
		button.add_theme_stylebox_override(str(state_data[0]), state_style)
	var actual_parent: Control = root_control if parent == null else parent
	actual_parent.add_child(button)
	button.size = button_size
	return button


func _style_page_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color("202020"))
	for state_data in [["normal", Color("ff9900")], ["hover", Color("ffff00")], ["pressed", Color("ff9900")]]:
		var state_style := StyleBoxFlat.new()
		state_style.bg_color = state_data[1]
		state_style.border_color = Color("202020")
		state_style.set_border_width_all(1)
		button.add_theme_stylebox_override(str(state_data[0]), state_style)


func selected_instance_id() -> int:
	return selected_instance_id_value


func _selected_secondary_id() -> int:
	if secondary_selector.item_count == 0 or secondary_selector.selected < 0:
		return 0
	return secondary_selector.get_item_id(secondary_selector.selected)


func _on_row_input(event: InputEvent, row_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_row(row_index)


func _select_row(row_index: int) -> void:
	if row_index < 0 or row_index >= row_instance_ids.size() or row_instance_ids[row_index] <= 0:
		return
	selected_instance_id_value = row_instance_ids[row_index]
	deploy_button.position = Vector2(164.7, 18.55 + row_index * 70)
	deploy_button.show()
	deploy_button.move_to_front()
	_refresh_row_styles()
	_refresh_detail()


func _change_page(delta: int) -> void:
	var page_count := maxi(1, ceili(float(GameState.pets.size()) / float(PETS_PER_PAGE)))
	current_page = clampi(current_page + delta, 0, page_count - 1)
	selected_instance_id_value = 0
	refresh()


func _toggle_deployment() -> void:
	var pet_index := GameState.get_pet_index(selected_instance_id_value)
	if pet_index < 0:
		return
	var should_deploy := not bool(GameState.pets[pet_index].get("deployed", false))
	var success := GameState.set_pet_deployed(selected_instance_id_value, should_deploy)
	if success:
		message_changed.emit("出征成功" if should_deploy else "召回成功")
	else:
		message_changed.emit("最多只能同时出征两只幻兽")


func _show_detail() -> void:
	if selected_instance_id_value <= 0:
		message_changed.emit("请先选择一只幻兽")
		return
	_refresh_detail()
	detail_panel.show()
	detail_panel.move_to_front()


func _rename_selected() -> void:
	var result := GameState.rename_pet(selected_instance_id_value, rename_edit.text)
	if result.get("success", false):
		rename_edit.text = str(result.name)
		message_changed.emit("幻兽改名成功：%s" % str(result.name))
	else:
		message_changed.emit("幻兽名字不能为空")


func _show_discard_confirmation() -> void:
	var pet_index := GameState.get_pet_index(selected_instance_id_value)
	if pet_index < 0:
		message_changed.emit("请先选择一只幻兽")
		return
	if bool(GameState.pets[pet_index].get("deployed", false)):
		message_changed.emit("出征中的幻兽不能丢弃，请先召回")
		return
	discard_question_label.text = "确定丢弃\n%s？" % _pet_name(GameState.pets[pet_index])
	discard_confirmation.show()
	discard_confirmation.move_to_front()


func _confirm_discard() -> void:
	var result := GameState.discard_pet(selected_instance_id_value)
	discard_confirmation.hide()
	if result.get("success", false):
		selected_instance_id_value = 0
		detail_panel.hide()
		message_changed.emit("幻兽已丢弃")
	else:
		message_changed.emit("出征中的幻兽不能丢弃")


func _train_selected() -> void:
	var success := GameState.train_pet_with_exp_ball(selected_instance_id_value)
	_set_detail_message("幻兽获得 27,000 经验" if success else "需要经验球，且幻兽未达到等级上限")


func _submit_selected() -> void:
	var result := GameState.submit_pet_for_daily_task(selected_instance_id_value)
	if result.get("success", false):
		_set_detail_message("上交成功：魔石 +%d，军功 +1,000" % int(result.magic_stones))
		return
	var message: String = {"already_completed":"今天已经完成上交任务", "deployed":"请先召回该幻兽", "score_too_low":"幻兽至少需要 20 星"}.get(str(result.get("reason", "")), "无法上交该幻兽")
	_set_detail_message(message)


func _fuse_selected() -> void:
	var result := GameState.fuse_pets(selected_instance_id_value, _selected_secondary_id())
	if result.get("success", false):
		_set_detail_message("幻化成功：主幻兽转世次数 +1")
		return
	var message: String = {"same_pet":"主副幻兽不能相同", "deployed":"请先召回参与幻化的幻兽", "main_level":"主幻兽必须达到 50 级", "secondary_score":"副幻兽评分不足", "missing_exp_ball":"缺少满经验球"}.get(str(result.get("reason", "")), "无法进行幻化")
	_set_detail_message(message)


func _set_detail_message(text_value: String) -> void:
	detail_status_label.text = text_value
	message_changed.emit(text_value)


func _pet_name(pet: Dictionary) -> String:
	var template_id := str(pet.get("template_id", ""))
	var custom_name := str(pet.get("custom_name", "")).strip_edges()
	var definition: Dictionary = GameState.pet_service.pet_database.get(template_id, {})
	if custom_name.is_empty() or custom_name == str(definition.get("name", "")):
		return str(PET_DEFAULT_NAMES.get(template_id, custom_name if not custom_name.is_empty() else "幻兽"))
	return custom_name


func _pet_portrait(pet: Dictionary) -> Texture2D:
	var path := str(PET_PORTRAITS.get(str(pet.get("template_id", "")), "res://assets/extracted/images/image_0746.jpg"))
	return load(path)


func _refresh_row_styles() -> void:
	for row_index in row_panels.size():
		var style := StyleBoxFlat.new()
		style.bg_color = Color("666666")
		style.border_color = Color("ffcc33") if row_instance_ids[row_index] == selected_instance_id_value else Color("2a2a2a")
		style.set_border_width_all(2 if row_instance_ids[row_index] == selected_instance_id_value else 1)
		row_panels[row_index].add_theme_stylebox_override("panel", style)


func _refresh_detail() -> void:
	var pet_index := GameState.get_pet_index(selected_instance_id_value)
	if pet_index < 0:
		detail_panel.hide()
		return
	var pet: Dictionary = GameState.pets[pet_index]
	var stats: Dictionary = GameState.pet_service.get_stats(pet)
	detail_icon.texture = _pet_portrait(pet)
	detail_info_label.text = "%s\n等级：%d　转世：%d\n星级：%.2f 星\n生命：%d/%d\n攻击：%d　防御：%d\n战斗力：%d%s" % [_pet_name(pet), int(pet.level), int(pet.reincarnations), float(pet.quality_score) / 100.0, int(pet.get("current_hp", stats.max_hp)), int(stats.max_hp), int(stats.attack), int(stats.defense), int(stats.combat_power), "　[出征]" if bool(pet.deployed) else ""]
	rename_edit.text = _pet_name(pet)
	secondary_selector.clear()
	for candidate: Dictionary in GameState.pets:
		if int(candidate.instance_id) == selected_instance_id_value:
			continue
		secondary_selector.add_item("%s　Lv.%d　%.2f星" % [_pet_name(candidate), int(candidate.level), float(candidate.quality_score) / 100.0], int(candidate.instance_id))


func refresh() -> void:
	if not is_node_ready():
		return
	var page_count := maxi(1, ceili(float(GameState.pets.size()) / float(PETS_PER_PAGE)))
	current_page = clampi(current_page, 0, page_count - 1)
	page_label.text = "%d / %d" % [current_page + 1, page_count]
	previous_button.disabled = current_page <= 0
	next_button.disabled = current_page >= page_count - 1
	var start_index := current_page * PETS_PER_PAGE
	var selection_visible := false
	for row_index in PETS_PER_PAGE:
		var pet_index := start_index + row_index
		if pet_index >= GameState.pets.size():
			row_instance_ids[row_index] = 0
			row_icons[row_index].texture = null
			row_labels[row_index].text = ""
			row_panels[row_index].mouse_filter = Control.MOUSE_FILTER_IGNORE
			continue
		var pet: Dictionary = GameState.pets[pet_index]
		row_instance_ids[row_index] = int(pet.instance_id)
		row_panels[row_index].mouse_filter = Control.MOUSE_FILTER_STOP
		row_icons[row_index].texture = _pet_portrait(pet)
		row_labels[row_index].text = "%s\nLv.%d　%.2f星\n%s" % [_pet_name(pet), int(pet.level), float(pet.quality_score) / 100.0, "出征中" if bool(pet.deployed) else "休息中"]
		if row_instance_ids[row_index] == selected_instance_id_value:
			selection_visible = true
			deploy_button.position = Vector2(164.7, 18.55 + row_index * 70)
	if not selection_visible:
		selected_instance_id_value = 0
		deploy_button.hide()
	else:
		var selected_index := GameState.get_pet_index(selected_instance_id_value)
		deploy_button.text = "召回" if selected_index >= 0 and bool(GameState.pets[selected_index].deployed) else "出征"
		deploy_button.show()
	_refresh_row_styles()
	_refresh_detail()