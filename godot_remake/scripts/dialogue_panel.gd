extends PanelContainer

signal action_requested(action: String)

class NativeAnswerButton:
	extends Button

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO

const PORTRAIT_PATHS := {
	"公主":"res://assets/ui/dialogue_face_princess.png",
	"元帅":"res://assets/ui/dialogue_face_marshal.png",
	"首相":"res://assets/ui/dialogue_face_prime_minister.png",
	"地图占领报名官":"res://assets/ui/dialogue_face_territory.png",
	"宝石合成师":"res://assets/ui/dialogue_face_stone_synthesizer.png",
	"经验导师":"res://assets/ui/dialogue_face_experience_mentor.png",
	"抽奖官":"res://assets/ui/dialogue_face_lottery_officer.png",
	"幻兽幻化师":"res://assets/ui/dialogue_face_pet_master.png",
	"收藏商店":"res://assets/ui/dialogue_face_stone_shop.png",
	"收藏家":"res://assets/ui/dialogue_face_collector.png",
	"公主侍女":"res://assets/ui/dialogue_face_maid_1.png",
	"杂货商":"res://assets/ui/dialogue_face_grocery.png",
	"PK赛报名官":"res://assets/ui/dialogue_face_pk_officer.png",
	"装备锻造师":"res://assets/ui/dialogue_face_forger.png",
	"日常任务官":"res://assets/ui/dialogue_face_daily_officer.png",
	"幻兽研究所":"res://assets/ui/dialogue_face_research.png",
	"探险家":"res://assets/ui/dialogue_face_explorer.png",
	"2008奥运使者":"res://assets/ui/dialogue_face_olympic.png",
	"国王":"res://assets/ui/dialogue_face_king.png",
}

var speaker_label: Label
var body_label: Label
var choices: Control
var npc_portrait: TextureRect
var player_portrait: TextureRect
var close_button: Button


func _ready() -> void:
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

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	npc_portrait = TextureRect.new()
	npc_portrait.position = Vector2(4, 4)
	npc_portrait.size = Vector2(64, 64)
	npc_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	npc_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	npc_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(npc_portrait)

	speaker_label = Label.new()
	speaker_label.position = Vector2(4, 69)
	speaker_label.size = Vector2(68, 20)
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.add_theme_font_size_override("font_size", 11)
	speaker_label.add_theme_color_override("font_color", Color("663300"))
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(speaker_label)

	body_label = Label.new()
	body_label.position = Vector2(78.5, 6.35)
	body_label.size = Vector2(275, 143)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body_label.add_theme_font_size_override("font_size", 12)
	body_label.add_theme_color_override("font_color", Color.BLACK)
	body_label.add_theme_color_override("font_shadow_color", Color("fff0d8"))
	body_label.add_theme_constant_override("shadow_offset_x", 1)
	body_label.add_theme_constant_override("shadow_offset_y", 1)
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body_label)

	player_portrait = TextureRect.new()
	player_portrait.position = Vector2(287.8, 153.5)
	player_portrait.size = Vector2(64, 64)
	player_portrait.texture = load("res://assets/extracted/images/image_0875.jpg")
	player_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(player_portrait)

	choices = Control.new()
	choices.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	choices.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(choices)

	close_button = Button.new()
	close_button.position = Vector2(338.5, 2)
	close_button.size = Vector2(21, 21)
	close_button.custom_minimum_size = Vector2(21, 21)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "关闭"
	_apply_close_styles(close_button)
	close_button.pressed.connect(hide)
	root.add_child(close_button)


func open_dialogue(speaker: String, text: String, actions: Array[Dictionary]) -> void:
	speaker_label.text = speaker
	body_label.text = text
	npc_portrait.texture = load(_portrait_path(speaker))
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	for index in actions.size():
		var entry: Dictionary = actions[index]
		var button := _make_answer_button(str(entry.get("label", "继续")), index)
		button.pressed.connect(_choose.bind(str(entry.get("action", ""))))
		choices.add_child(button)
		button.size = Vector2(270, 16)
	AudioService.play("npc_dialogue")
	show()


func _portrait_path(speaker: String) -> String:
	if PORTRAIT_PATHS.has(speaker):
		return str(PORTRAIT_PATHS[speaker])
	if "地图占领" in speaker:
		return str(PORTRAIT_PATHS["地图占领报名官"])
	if "侍女" in speaker or "丫环" in speaker:
		return str(PORTRAIT_PATHS["公主侍女"])
	if "五福娃" in speaker or "奥运" in speaker:
		return str(PORTRAIT_PATHS["2008奥运使者"])
	if "探险家" in speaker:
		return str(PORTRAIT_PATHS["探险家"])
	if "PK" in speaker:
		return str(PORTRAIT_PATHS["PK赛报名官"])
	return "res://assets/extracted/images/image_0875.jpg"


func _make_answer_button(label_text: String, index: int) -> Button:
	var button := NativeAnswerButton.new()
	button.text = label_text
	button.position = Vector2(5, 155.7 + index * 16)
	button.size = Vector2(270, 16)
	button.custom_minimum_size = Vector2(270, 16)
	button.focus_mode = Control.FOCUS_NONE
	button.flat = false
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color.BLACK)
	button.add_theme_color_override("font_hover_color", Color.BLACK)
	button.add_theme_color_override("font_pressed_color", Color.BLACK)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.set_content_margin(SIDE_LEFT, 6)
	button.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("ffcc66")
	hover.set_content_margin(SIDE_LEFT, 6)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color("ff9900")
	pressed.set_content_margin(SIDE_LEFT, 6)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _apply_close_styles(button: Button) -> void:
	var states := [
		["normal", Color("333333")],
		["hover", Color("999999")],
		["pressed", Color("000000")],
	]
	for state: Array in states:
		var style := StyleBoxFlat.new()
		style.bg_color = state[1]
		style.border_color = Color("ff9900")
		style.set_border_width_all(4)
		style.corner_radius_top_left = 11
		style.corner_radius_top_right = 11
		style.corner_radius_bottom_left = 11
		style.corner_radius_bottom_right = 11
		button.add_theme_stylebox_override(str(state[0]), style)


func _choose(action: String) -> void:
	hide()
	action_requested.emit(action)
