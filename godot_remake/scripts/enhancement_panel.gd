extends PanelContainer

signal message_changed(text: String)

const SLOT_IDS := ["weapon", "helmet", "necklace", "armor", "bracelet", "boots"]
const SLOT_NAMES := ["武器", "头盔", "项链", "衣服", "手镯", "战靴"]
const ACTIONS := [
	["品质", "quality"],
	["魔魂", "magic_soul"],
	["战魂", "war_soul"],
	["天魂", "heaven"],
	["地魂", "earth"],
]

var root_control: Control
var slot_selector: OptionButton
var equipment_icon: TextureRect
var equipment_label: Label
var materials_label: Label
var stats_label: Label
var close_button: Button
var action_buttons: Dictionary = {}


func _ready() -> void:
	# SWF sprite662 / shape653: native refining window at (238, 375), 191x133.
	position = Vector2(238, 375)
	size = Vector2(191, 133)
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
	title.text = "装备精炼"
	title.position = Vector2(51.8, 8.8)
	title.size = Vector2(96, 21)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("ff9900"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(title)

	close_button = _make_close_button(Vector2(160, 4.5))

	slot_selector = OptionButton.new()
	slot_selector.position = Vector2(5, 33)
	slot_selector.size = Vector2(122, 25)
	slot_selector.add_theme_font_size_override("font_size", 11)
	for index in SLOT_IDS.size():
		slot_selector.add_item(SLOT_NAMES[index], index)
	slot_selector.item_selected.connect(func(_index: int) -> void: refresh())
	root_control.add_child(slot_selector)

	equipment_icon = TextureRect.new()
	equipment_icon.position = Vector2(5, 63)
	equipment_icon.size = Vector2(40, 40)
	equipment_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	equipment_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	equipment_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(equipment_icon)

	equipment_label = Label.new()
	equipment_label.position = Vector2(48, 59)
	equipment_label.size = Vector2(79, 24)
	equipment_label.add_theme_font_size_override("font_size", 10)
	equipment_label.add_theme_color_override("font_color", Color("fff0a0"))
	equipment_label.clip_text = true
	equipment_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(equipment_label)

	stats_label = Label.new()
	stats_label.position = Vector2(48, 78)
	stats_label.size = Vector2(79, 29)
	stats_label.add_theme_font_size_override("font_size", 9)
	stats_label.add_theme_color_override("font_color", Color.WHITE)
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(stats_label)

	materials_label = Label.new()
	materials_label.position = Vector2(5, 107)
	materials_label.size = Vector2(123, 22)
	materials_label.add_theme_font_size_override("font_size", 8)
	materials_label.add_theme_color_override("font_color", Color("ffcc66"))
	materials_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(materials_label)

	for action_index in ACTIONS.size():
		var action_data: Array = ACTIONS[action_index]
		var button := _make_action_button(str(action_data[0]), Vector2(132, 31 + action_index * 19))
		button.tooltip_text = _operation_tooltip(str(action_data[1]))
		button.pressed.connect(perform_operation.bind(str(action_data[1])))
		action_buttons[str(action_data[1])] = button

	GameState.equipment_changed.connect(refresh)
	GameState.inventory_changed.connect(refresh)
	refresh()


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


func _make_action_button(text_value: String, button_position: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = button_position
	button.size = Vector2(54, 18)
	button.custom_minimum_size = Vector2(54, 18)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color.WHITE)
	for state_data in [["normal", Color("666666")], ["hover", Color("999999")], ["pressed", Color("333333")]]:
		var state_style := StyleBoxFlat.new()
		state_style.bg_color = state_data[1]
		state_style.border_color = Color("202020")
		state_style.set_border_width_all(1)
		button.add_theme_stylebox_override(str(state_data[0]), state_style)
	root_control.add_child(button)
	button.size = Vector2(54, 18)
	return button


func _operation_tooltip(operation: String) -> String:
	return {
		"quality":"消耗月光宝盒增强版，品质精炼必定成功",
		"magic_soul":"消耗魔魂晶石，魔魂提升必定成功",
		"war_soul":"消耗战魂晶石，激活成功率50%",
		"heaven":"消耗战魂之心，天魂提升1级",
		"earth":"消耗战魂之心，地魂提升1级",
	}.get(operation, "")


func selected_slot() -> String:
	if slot_selector == null or slot_selector.selected < 0:
		return SLOT_IDS[0]
	return SLOT_IDS[slot_selector.selected]


func select_slot(equipment_slot: String) -> void:
	var index := SLOT_IDS.find(equipment_slot)
	if index >= 0:
		slot_selector.select(index)
		refresh()


func perform_operation(operation: String, forced_roll: float = -1.0) -> bool:
	var equipment_slot := selected_slot()
	if GameState.equipment.get(equipment_slot, {}).is_empty():
		message_changed.emit("请先在背包中双击装备并穿戴到对应栏位")
		return false
	if operation == "heaven" or operation == "earth":
		var success := GameState.increase_equipped_soul(equipment_slot, operation)
		message_changed.emit("%s提升成功" % ("天魂" if operation == "heaven" else "地魂") if success else "需要先激活战魂、准备战魂之心，且魂等级不能超过5级")
		return success
	var roll := randf() if forced_roll < 0.0 else forced_roll
	var result := GameState.enhance_equipped(equipment_slot, operation, roll)
	if result.get("success", false):
		message_changed.emit({"quality":"品质精炼成功", "magic_soul":"魔魂提升成功", "war_soul":"战魂激活成功"}.get(operation, "养成成功"))
	else:
		var reason := str(result.get("reason", ""))
		if reason == "missing_material":
			message_changed.emit("缺少养成材料")
		elif reason == "already_active":
			message_changed.emit("该装备已经激活战魂")
		elif operation == "war_soul":
			message_changed.emit("战魂激活失败，晶石已消耗")
		else:
			message_changed.emit("养成失败")
	return bool(result.get("success", false))


func refresh() -> void:
	if not is_node_ready():
		return
	var equipment_slot := selected_slot()
	var item: Dictionary = GameState.equipment.get(equipment_slot, {})
	if item.is_empty():
		equipment_icon.texture = null
		equipment_label.text = "%s：未装备" % SLOT_NAMES[SLOT_IDS.find(equipment_slot)]
		stats_label.text = "请在背包双击装备"
	else:
		var item_id := str(item.get("item_id", ""))
		var definition: Dictionary = GameState.get_item_definition(item_id)
		var icon_path := str(definition.get("icon", ""))
		equipment_icon.texture = load(icon_path) if not icon_path.is_empty() else null
		var instance: Dictionary = item.get("enhancement", {})
		equipment_label.text = str(definition.get("name", item_id))
		stats_label.text = "品质+%d 魔魂+%d\n战魂%s 天%d 地%d" % [int(instance.get("quality_level", 0)), int(instance.get("magic_soul_level", 0)), "已开" if bool(instance.get("war_soul_active", false)) else "未开", int(instance.get("heaven_soul_level", 0)), int(instance.get("earth_soul_level", 0))]
	materials_label.text = "月盒%d 魔晶%d 战晶%d 战心%d" % [GameState.count_item("enhanced_moon_box"), GameState.count_item("magic_soul_crystal"), GameState.count_item("war_soul_crystal"), GameState.count_item("war_soul_heart")]