extends PanelContainer

signal item_focused(item: Dictionary, source_panel: Control)
signal item_unfocused

const SLOT_ORDER := ["helmet", "necklace", "bracelet", "armor", "weapon", "boots"]
const SLOT_NAMES := {
	"weapon": "武器",
	"helmet": "头盔",
	"necklace": "项链",
	"armor": "衣服",
	"bracelet": "手镯",
	"boots": "战靴",
}
const SLOT_POSITIONS := {
	"helmet": Vector2(173, 28),
	"necklace": Vector2(173, 92),
	"bracelet": Vector2(173, 156),
	"armor": Vector2(109, 220),
	"weapon": Vector2(45, 220),
	"boots": Vector2(173, 220),
}

var root_control: Control
var title_label: Label
var stats_label: Label
var detail_panel: PanelContainer
var detail_label: Label
var detail_button: Button
var slot_panels: Dictionary = {}
var slot_icons: Dictionary = {}
var slot_labels: Dictionary = {}
var war_soul_badge: TextureRect
var soul_set_badge: TextureRect


func _ready() -> void:
	position = Vector2(210, 85)
	size = Vector2(243, 289)
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

	_build_detail_panel()
	_build_stats()
	for slot_id: String in SLOT_ORDER:
		_build_slot(slot_id)
	_build_badges()

	GameState.equipment_changed.connect(_refresh)
	GameState.progression_changed.connect(_refresh)
	GameState.pets_changed.connect(_refresh)
	GameState.social_changed.connect(_refresh)
	_refresh()


func _build_stats() -> void:
	title_label = Label.new()
	title_label.text = "人物信息"
	title_label.position = Vector2(77, 5.3)
	title_label.size = Vector2(86, 25)
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("ff9900"))
	title_label.add_theme_color_override("font_shadow_color", Color("202020"))
	title_label.add_theme_constant_override("shadow_offset_x", 1)
	title_label.add_theme_constant_override("shadow_offset_y", 1)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(title_label)

	stats_label = Label.new()
	stats_label.position = Vector2(10, 28.7)
	stats_label.size = Vector2(170, 192.3)
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color("ff9900"))
	stats_label.add_theme_color_override("font_shadow_color", Color("202020"))
	stats_label.add_theme_constant_override("shadow_offset_x", 1)
	stats_label.add_theme_constant_override("shadow_offset_y", 1)
	stats_label.add_theme_constant_override("line_spacing", 0)
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(stats_label)

	detail_button = Button.new()
	detail_button.text = "详细"
	detail_button.position = Vector2(3, 224.4)
	detail_button.size = Vector2(42, 24)
	detail_button.custom_minimum_size = Vector2(42, 24)
	detail_button.focus_mode = Control.FOCUS_NONE
	detail_button.add_theme_font_size_override("font_size", 12)
	detail_button.add_theme_color_override("font_color", Color.WHITE)
	_apply_three_state_button(detail_button)
	detail_button.pressed.connect(_toggle_detail)
	root_control.add_child(detail_button)
	detail_button.size = Vector2(42, 24)


func _build_slot(slot_id: String) -> void:
	var slot := PanelContainer.new()
	slot.position = SLOT_POSITIONS[slot_id]
	slot.size = Vector2(64, 64)
	slot.custom_minimum_size = Vector2(64, 64)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color("666666")
	slot_style.border_color = Color("292929")
	slot_style.set_border_width_all(2)
	slot_style.set_content_margin_all(0)
	slot.add_theme_stylebox_override("panel", slot_style)
	root_control.add_child(slot)
	slot.size = Vector2(64, 64)

	var icon := TextureRect.new()
	icon.position = Vector2(4, 4)
	icon.size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)

	var label := Label.new()
	label.position = Vector2(2, 21)
	label.size = Vector2(60, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("ff9900"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)

	slot.mouse_entered.connect(_focus_slot.bind(slot_id))
	slot.mouse_exited.connect(_unfocus_slot)
	slot_panels[slot_id] = slot
	slot_icons[slot_id] = icon
	slot_labels[slot_id] = label


func _build_detail_panel() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.position = Vector2(-179.05, 24.3)
	detail_panel.size = Vector2(178, 231)
	detail_panel.custom_minimum_size = Vector2(178, 231)
	detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color("ffcc99")
	detail_style.border_color = Color("805b3c")
	detail_style.set_border_width_all(2)
	detail_style.set_content_margin_all(0)
	detail_panel.add_theme_stylebox_override("panel", detail_style)
	root_control.add_child(detail_panel)

	detail_label = Label.new()
	detail_label.position = Vector2(5, 4)
	detail_label.size = Vector2(169, 223)
	detail_label.add_theme_font_size_override("font_size", 11)
	detail_label.add_theme_color_override("font_color", Color.BLACK)
	detail_label.add_theme_constant_override("line_spacing", 0)
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.add_child(detail_label)
	detail_panel.hide()


func _build_badges() -> void:
	war_soul_badge = _make_badge(Vector2(210.4, 5.8), "res://assets/extracted/images/image_0553.jpg")
	war_soul_badge.tooltip_text = "战魂等级"
	soul_set_badge = _make_badge(Vector2(182.85, 5.8), "res://assets/extracted/images/image_0556.jpg")


func _make_badge(badge_position: Vector2, texture_path: String) -> TextureRect:
	var badge := TextureRect.new()
	badge.position = badge_position
	badge.size = Vector2(20, 20)
	badge.texture = load(texture_path)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	root_control.add_child(badge)
	return badge


func _apply_three_state_button(button: Button) -> void:
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


func _refresh() -> void:
	if not is_node_ready():
		return
	var stats: Dictionary = GameState.get_player_stats()
	var military: Dictionary = GameState.get_military_rank()
	var nobility: Dictionary = GameState.get_nobility_rank()
	var affection: Dictionary = GameState.get_affection_rank()
	stats_label.text = "魔域玩家\n等级：%d级\n爵位：%s　军衔：%s\n与公主关系：%s\n生命值：%d/%d\n体力值：%d/%d\n经验值：%d/%d\n攻击力：%d\n防御力：%d\n闪避：%d%%\n幸运值：%d\n战斗力：%d" % [
		GameState.level,
		str(nobility.get("name", "平民")),
		str(military.get("name", "无军衔")),
		str(affection.get("name", "未认识")),
		int(stats.get("current_hp", 0)),
		int(stats.get("max_hp", 0)),
		GameState.player_current_stamina,
		GameState.get_player_max_stamina(),
		GameState.experience,
		GameState.experience_to_next_level(),
		int(stats.get("attack", 0)),
		int(stats.get("defense", 0)),
		int(stats.get("dodge_percent", 0)),
		int(stats.get("luck", 0)),
		int(stats.get("combat_power", 0)),
	]

	var quality_total := 0
	var magic_total := 0
	var socket_total := 0
	var war_soul_count := 0
	var all_equipped := true
	var all_heaven := true
	var all_earth := true
	for slot_id: String in SLOT_ORDER:
		var item: Dictionary = GameState.equipment.get(slot_id, {})
		var icon: TextureRect = slot_icons[slot_id]
		var label: Label = slot_labels[slot_id]
		if item.is_empty():
			icon.texture = null
			label.text = SLOT_NAMES[slot_id]
			all_equipped = false
			all_heaven = false
			all_earth = false
			continue
		var definition: Dictionary = GameState.get_item_definition(str(item.get("item_id", "")))
		var icon_path := str(definition.get("icon", ""))
		icon.texture = load(icon_path) if not icon_path.is_empty() else null
		label.text = ""
		var instance: Dictionary = item.get("enhancement", {})
		quality_total += int(instance.get("quality_level", 0))
		magic_total += int(instance.get("magic_soul_level", 0))
		socket_total += int(instance.get("socket_count", 0))
		if bool(instance.get("war_soul_active", false)):
			war_soul_count += 1
		if int(instance.get("heaven_soul_level", 0)) <= 0:
			all_heaven = false
		if int(instance.get("earth_soul_level", 0)) <= 0:
			all_earth = false

	war_soul_badge.visible = war_soul_count > 0
	soul_set_badge.visible = all_equipped and (all_heaven or all_earth)
	if soul_set_badge.visible:
		if all_heaven:
			soul_set_badge.texture = load("res://assets/extracted/images/image_0556.jpg")
			soul_set_badge.tooltip_text = "天魂套装"
		else:
			soul_set_badge.texture = load("res://assets/extracted/images/image_0558.jpg")
			soul_set_badge.tooltip_text = "地魂套装"

	var rank_power := int(military.get("combat_power", 0))
	var nobility_power := int(nobility.get("combat_power", 0))
	detail_label.text = "　　战斗力详细评定\n　条件　　　　战斗力加成\n人物等级　%d　+%d\n出征幻兽　　　+%d\n装备全身　　　+%d\n装备品质 %d　　已计入\n魔魂等级 %d　　已计入\n装备洞数 %d　　属性记录\n战魂装备 %d　　已计入\n军衔 %s　+%d\n爵位 %s　+%d\n技能　　　　　+%d\n总共战斗力　　%d" % [
		GameState.level,
		GameState.level,
		int(stats.get("pet_combat_power", 0)),
		int(stats.get("equipment_combat_power", 0)),
		quality_total,
		magic_total,
		socket_total,
		war_soul_count,
		str(military.get("name", "无军衔")),
		rank_power,
		str(nobility.get("name", "平民")),
		nobility_power,
		int(stats.get("skill_combat_power", 0)),
		int(stats.get("combat_power", 0)),
	]


func _toggle_detail() -> void:
	detail_panel.visible = not detail_panel.visible


func _focus_slot(slot_id: String) -> void:
	var item: Dictionary = GameState.equipment.get(slot_id, {})
	if not item.is_empty():
		item_focused.emit(item, self)


func _unfocus_slot() -> void:
	item_unfocused.emit()