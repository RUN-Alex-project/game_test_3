extends PanelContainer

signal message_changed(text: String)

const ROW_SKILLS := ["flying_slash", "star_sword", "", "", "fighting_spirit", "love_power"]
const ROW_ICONS := [
	"res://assets/extracted/images/image_0698.jpg",
	"res://assets/extracted/images/image_0703.jpg",
	"res://assets/extracted/images/image_0708.jpg",
	"res://assets/extracted/images/image_0713.jpg",
	"res://assets/extracted/images/image_0718.jpg",
	"res://assets/extracted/images/image_0726.png",
]
const SKILL_NAMES := {
	"flying_slash":"飞天连斩",
	"star_sword":"星魔剑",
	"fighting_spirit":"斗志昂扬",
	"love_power":"爱的力量",
}

var root_control: Control
var row_panels: Array[Panel] = []
var row_icons: Array[TextureRect] = []
var row_labels: Array[Label] = []
var close_button: Button


func _ready() -> void:
	position = Vector2(23, 220)
	size = Vector2(183, 253)
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

	for row_index in ROW_SKILLS.size():
		_build_skill_row(row_index)
	_build_close_button()
	GameState.skills_changed.connect(_refresh)
	GameState.inventory_changed.connect(_refresh)
	_refresh()


func _build_skill_row(row_index: int) -> void:
	var row := Panel.new()
	row.position = Vector2(10, 207.6 if row_index == 5 else 5 + row_index * 40)
	row.size = Vector2(165, 40)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_input.bind(row_index))
	root_control.add_child(row)

	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0, 0, 0, 0)
	row_style.border_color = Color("3a3a3a")
	row_style.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", row_style)

	var icon := TextureRect.new()
	icon.position = Vector2(0, 0)
	icon.size = Vector2(40, 40)
	icon.texture = load(ROW_ICONS[row_index])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var label := Label.new()
	label.position = Vector2(46.55, 2)
	label.size = Vector2(116, 37)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	row.mouse_entered.connect(_set_row_hover.bind(row_index, true))
	row.mouse_exited.connect(_set_row_hover.bind(row_index, false))
	row_panels.append(row)
	row_icons.append(icon)
	row_labels.append(label)


func _build_close_button() -> void:
	close_button = Button.new()
	close_button.text = ""
	close_button.position = Vector2(156.45, 2.95)
	close_button.size = Vector2(21, 21)
	close_button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ff9900")
	style.border_color = Color("202020")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 11
	style.corner_radius_top_right = 11
	style.corner_radius_bottom_left = 11
	style.corner_radius_bottom_right = 11
	close_button.add_theme_stylebox_override("normal", style)
	close_button.add_theme_stylebox_override("hover", style)
	close_button.add_theme_stylebox_override("pressed", style)
	close_button.pressed.connect(hide)
	root_control.add_child(close_button)


func _set_row_hover(row_index: int, hovered: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("777777") if hovered else Color(0, 0, 0, 0)
	style.border_color = Color("ff9900") if hovered else Color("3a3a3a")
	style.set_border_width_all(1)
	row_panels[row_index].add_theme_stylebox_override("panel", style)


func _on_row_input(event: InputEvent, row_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_activate_row(row_index)


func _activate_row(row_index: int) -> void:
	if row_index < 0 or row_index >= ROW_SKILLS.size():
		return
	var skill_id := str(ROW_SKILLS[row_index])
	if skill_id.is_empty():
		message_changed.emit("这个技能栏位尚未开放")
		return
	var rank := int(GameState.learned_skills.get(skill_id, 0))
	if rank <= 0:
		message_changed.emit("尚未掌握%s；请在背包中双击对应技能书" % SKILL_NAMES[skill_id])
		return
	if skill_id == "love_power":
		_use_love_power()
		return
	message_changed.emit(_skill_description(skill_id, rank).replace("\n", "　"))


func _skill_description(skill_id: String, rank: int) -> String:
	match skill_id:
		"flying_slash", "star_sword":
			var multiplier := GameState.skill_service.active_damage_multiplier(GameState.learned_skills, skill_id) * 100.0
			return "%s\n%d级　伤害 %.0f%%" % [SKILL_NAMES[skill_id], rank, multiplier]
		"fighting_spirit":
			var percent := GameState.skill_service.combat_power_percent(GameState.learned_skills) * 100.0
			return "%s\n%d级　战斗力 +%.0f%%" % [SKILL_NAMES[skill_id], rank, percent]
		"love_power":
			var chance := GameState.skill_service.utility_success_chance(GameState.learned_skills, skill_id) * 100.0
			var luck := GameState.skill_service.utility_luck_bonus(GameState.learned_skills, skill_id)
			return "%s\n%d级　成功 %.0f%% / 幸运 +%d" % [SKILL_NAMES[skill_id], rank, chance, luck]
	return "未掌握"


func _use_love_power(roll: float = -1.0) -> void:
	var result := GameState.use_love_power(roll)
	if result.get("success", false):
		message_changed.emit("爱的力量生效：人物与幻兽生命回满，幸运 +%d" % int(result.luck))
	else:
		message_changed.emit("爱的力量本次没有生效（成功率 %.0f%%）" % (float(result.get("chance", 0.0)) * 100.0))


func _refresh() -> void:
	if not is_node_ready():
		return
	for row_index in ROW_SKILLS.size():
		var skill_id := str(ROW_SKILLS[row_index])
		if skill_id.is_empty():
			row_labels[row_index].text = "未掌握"
			row_labels[row_index].add_theme_color_override("font_color", Color("b8b8b8"))
			row_panels[row_index].tooltip_text = "原版保留技能栏位"
			continue
		var rank := int(GameState.learned_skills.get(skill_id, 0))
		if rank <= 0:
			row_labels[row_index].text = "%s\n未掌握" % SKILL_NAMES[skill_id]
			row_labels[row_index].add_theme_color_override("font_color", Color("b8b8b8"))
			row_panels[row_index].tooltip_text = "请在背包中双击对应技能书"
		else:
			row_labels[row_index].text = _skill_description(skill_id, rank)
			row_labels[row_index].add_theme_color_override("font_color", Color("fff0a0"))
			row_panels[row_index].tooltip_text = "点击查看" if skill_id != "love_power" else "点击施放爱的力量"