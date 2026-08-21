extends Control

const InventoryPanel = preload("res://scripts/inventory_panel.gd")
const ShopPanel = preload("res://scripts/shop_panel_original.gd")
const EquipmentPanel = preload("res://scripts/equipment_panel.gd")
const EnhancementPanel = preload("res://scripts/enhancement_panel.gd")
const PetPanel = preload("res://scripts/pet_panel.gd")
const ResearchPanel = preload("res://scripts/research_panel.gd")
const ProgressionPanel = preload("res://scripts/progression_panel.gd")
const QuestPanel = preload("res://scripts/quest_panel.gd")
const SkillPanel = preload("res://scripts/skill_panel.gd")
const SceneBattleController = preload("res://scripts/scene_battle_controller.gd")
const CombatService = preload("res://scripts/combat_service.gd")
const DialoguePanel = preload("res://scripts/dialogue_panel.gd")
const WorldService = preload("res://scripts/world_service.gd")
const EndingPanel = preload("res://scripts/ending_panel.gd")
const NativeExitButton = preload("res://scripts/native_exit_button.gd")
const AdventurerRosterPanel = preload("res://scripts/adventurer_roster_panel.gd")
const AdventurerMailPanel = preload("res://scripts/adventurer_mail_panel.gd")
const AdventurerTradePanel = preload("res://scripts/adventurer_trade_panel.gd")
const RankingPanel = preload("res://scripts/ranking_panel.gd")
const ArenaPanel = preload("res://scripts/arena_panel.gd")
const GuildMarketPanel = preload("res://scripts/guild_market_panel.gd")
const PropertyTerritoryPanel = preload("res://scripts/property_territory_panel.gd")
const BorderCommandPanel = preload("res://scripts/border_command_panel.gd")
const IceCodexPanel = preload("res://scripts/ice_codex_panel.gd")
const AbyssBoardPanel = preload("res://scripts/abyss_board_panel.gd")
const ChallengeBoardPanel = preload("res://scripts/challenge_board_panel.gd")
const PetEndgamePanel = preload("res://scripts/pet_endgame_panel.gd")
const SeasonBoardPanel = preload("res://scripts/season_board_panel.gd")

var player: TextureRect
var background: TextureRect
var actor_layer: Control
var navigation_layer: Control
var location_label: Label
var inventory_panel: PanelContainer
var warehouse_panel: PanelContainer
var gold_shop: PanelContainer
var stone_shop: PanelContainer
var equipment_panel: PanelContainer
var enhancement_panel: PanelContainer
var pet_panel: PanelContainer
var research_panel: PanelContainer
var progression_panel: PanelContainer
var quest_panel: PanelContainer
var skill_panel: PanelContainer
var scene_battle_controller: Control
var dialogue_panel: PanelContainer
var ending_panel: Panel
var adventurer_roster_panel: PanelContainer
var adventurer_mail_panel: PanelContainer
var adventurer_trade_panel: PanelContainer
var ranking_panel: PanelContainer
var arena_panel: PanelContainer
var guild_market_panel: PanelContainer
var property_territory_panel: PanelContainer
var border_command_panel: PanelContainer
var ice_codex_panel: PanelContainer
var abyss_board_panel: PanelContainer
var challenge_board_panel: PanelContainer
var pet_endgame_panel: PanelContainer
var season_board_panel: PanelContainer
var arena_proxy: TextureRect
var item_tooltip_panel: PanelContainer
var item_tooltip_text: RichTextLabel
var monster_tooltip_panel: Panel
var monster_tooltip_text: Label
var status_label: Label
var day_label: Label
var time_box: Label
var bottom_bar: Panel
var music_toggle: CheckBox
var trash_button: Button
var player_status_card: Dictionary = {}
var pet_status_cards: Array[Dictionary] = []
var direction_buttons: Dictionary = {}
var footer_buttons: Dictionary = {}
var interactive_actors: Dictionary = {}
var actor_labels: Dictionary = {}
var world := WorldService.new()
var combat := CombatService.new()
var player_idle_frames: Array[Texture2D] = []
var player_walk_frames: Dictionary = {}
var player_animation_elapsed: float = 0.0
var player_animation_index: int = 0
var player_animation_clip: String = "idle"
var player_facing: String = "down"
var current_player_hp: int = -1


func _ready() -> void:
	_build_world()
	_build_navigation()
	_build_hud()
	_build_status_line()
	_build_bottom_bar()
	_build_item_tooltip()
	_build_monster_tooltip()
	_build_panels()
	_apply_current_map()
	_connect_state_signals()
	_refresh_status_cards()
	status_label.text = "点击场景中的人物或怪物进行交互，方向键移动，F5保存，F9读取。"
	if bool(GameState.story_flags.get("game_won", false)):
		_show_ending()


	# v1.41 第四轮拒签整改：主场景 ready 完成稳定标记（exe 冒烟以此为主场景启动证据）
	print("APP_READY:main_original")

func _build_world() -> void:
	background = TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://assets/extracted/images/image_1114.jpg")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	actor_layer = Control.new()
	actor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 演员层抬到边缘出口按钮之上：navigation_layer 是更晚添加的兄弟节点，
	# 默认会压住演员并抢走点击。全世界有 13 处出口命中区与演员贴图重叠，
	# 其中鱼妖/提风/巨杰士等怪被覆盖 87%~100%，不抬层就完全点不到，
	# 而怪是唯一的玩家经验来源。HUD 用 49~60 的 z_index，故此处取 1 不会盖住 HUD。
	actor_layer.z_index = 1
	add_child(actor_layer)
	player = TextureRect.new()
	var idle_a: Texture2D = load("res://assets/extracted/images/image_0455.png")
	var idle_b: Texture2D = load("res://assets/extracted/images/image_0457.png")
	var down_a: Texture2D = load("res://assets/extracted/images/image_0465.png")
	var down_b: Texture2D = load("res://assets/extracted/images/image_0467.png")
	var up_a: Texture2D = load("res://assets/extracted/images/image_0470.png")
	var up_b: Texture2D = load("res://assets/extracted/images/image_0472.png")
	var left_a: Texture2D = load("res://assets/extracted/images/image_0475.png")
	var left_mid: Texture2D = load("res://assets/extracted/images/image_0477.png")
	var left_b: Texture2D = load("res://assets/extracted/images/image_0479.png")
	var right_a: Texture2D = load("res://assets/extracted/images/image_0482.png")
	var right_mid: Texture2D = load("res://assets/extracted/images/image_0484.png")
	var right_b: Texture2D = load("res://assets/extracted/images/image_0486.png")
	# Native clips run at 12 fps. Repeated entries preserve the exact frame holds:
	# idle/down/up = 4+4 frames; left/right = 4+1+4+1 frames.
	player_idle_frames = [idle_a, idle_a, idle_a, idle_a, idle_b, idle_b, idle_b, idle_b]
	player_walk_frames = {
		"down":[down_a, down_a, down_a, down_a, down_b, down_b, down_b, down_b],
		"up":[up_a, up_a, up_a, up_a, up_b, up_b, up_b, up_b],
		"left":[left_a, left_a, left_a, left_a, left_mid, left_b, left_b, left_b, left_b, left_mid],
		"right":[right_a, right_a, right_a, right_a, right_mid, right_b, right_b, right_b, right_b, right_mid],
	}
	player.texture = player_idle_frames[0]
	player.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player.position = Vector2(310, 270)
	player.size = Vector2(82, 150)
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(player)


func _build_navigation() -> void:
	navigation_layer = Control.new()
	navigation_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	navigation_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(navigation_layer)
	for direction: String in ["top", "bottom", "left", "right"]:
		var button := NativeExitButton.new()
		button.name = "NativeExit" + direction.capitalize()
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		navigation_layer.add_child(button)
		direction_buttons[direction] = button
		button.hide()

func _build_hud() -> void:
	# Top HUD safe margin = 4px: cards sit 4px below the viewport top so the
	# panel border, title glyphs and portrait are never flush with the window edge.
	player_status_card = _build_player_status_card(Vector2(1, 4))
	pet_status_cards.append(_build_pet_status_card(0, Vector2(198, 4)))
	pet_status_cards.append(_build_pet_status_card(1, Vector2(394, 4)))
	var location_panel := _make_hud_panel(Vector2(590.5, 4), Vector2(108.5, 72))
	var location_title := _make_hud_label(location_panel, "当前地图", Vector2(3, 3), Vector2(102, 21), 13, Color("1eff3d"))
	location_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location_label = _make_hud_label(location_panel, "卡萨诺城", Vector2(3, 23), Vector2(102, 45), 13, Color("1eff3d"))
	location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _make_hud_panel(panel_position: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.custom_minimum_size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color("505050")
	style.border_color = Color("202020")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _make_hud_label(parent: Control, label_text: String, label_position: Vector2, label_size: Vector2, font_size: int, font_color: Color) -> Label:
	var label := Label.new()
	label.text = label_text
	label.position = label_position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2.ZERO
	parent.add_child(label)
	# Re-apply the intended size after tree entry so the theme default does not override it.
	label.set_deferred("size", label_size)
	return label


func _make_hud_portrait(parent: Control, portrait_path: String) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.position = Vector2(3, 3)
	portrait.size = Vector2(61, 52)
	portrait.texture = load(portrait_path)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(portrait)
	return portrait


func _add_absolute_meter(parent: Control, meter_position: Vector2, meter_size: Vector2, fill_color: Color) -> Dictionary:
	var bar := ProgressBar.new()
	bar.position = meter_position
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2.ZERO
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color("171717")
	background_style.border_color = Color("8c8c8c")
	background_style.set_border_width_all(1)
	background_style.set_content_margin_all(0.0)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.set_content_margin_all(0.0)
	bar.add_theme_stylebox_override("background", background_style)
	bar.add_theme_stylebox_override("fill", fill_style)
	parent.add_child(bar)
	# Godot resets Control.size to the theme default when the node enters the tree;
	# the intended 12px meter height only sticks if we re-apply it after tree entry.
	bar.set_deferred("size", meter_size)
	var text_label := Label.new()
	text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.add_theme_font_size_override("font_size", 9)
	text_label.add_theme_color_override("font_color", Color.WHITE)
	text_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	text_label.add_theme_constant_override("shadow_offset_x", 1)
	text_label.add_theme_constant_override("shadow_offset_y", 1)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(text_label)
	return {"bar":bar, "text":text_label}


func _build_player_status_card(card_position: Vector2) -> Dictionary:
	var panel := _make_hud_panel(card_position, Vector2(193, 72))
	var portrait := _make_hud_portrait(panel, "res://assets/extracted/images/image_0875.jpg")
	var title := _make_hud_label(panel, "魔域玩家", Vector2(66, 1), Vector2(124, 19), 14, Color("d69b21"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hp_meter := _add_absolute_meter(panel, Vector2(66, 20), Vector2(124, 12), Color("f22c24"))
	var stamina_meter := _add_absolute_meter(panel, Vector2(66, 33), Vector2(124, 12), Color("f17f19"))
	var exp_meter := _add_absolute_meter(panel, Vector2(66, 46), Vector2(124, 12), Color("2774db"))
	var footer := _make_hud_label(panel, "", Vector2(3, 56), Vector2(187, 13), 9, Color("f0f0f0"))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return {
		"panel":panel,
		"title":title,
		"portrait":portrait,
		"hp_bar":hp_meter.bar,
		"hp_text":hp_meter.text,
		"stamina_bar":stamina_meter.bar,
		"stamina_text":stamina_meter.text,
		"secondary_bar":exp_meter.bar,
		"secondary_text":exp_meter.text,
		"footer":footer,
	}


func _build_pet_status_card(card_index: int, card_position: Vector2) -> Dictionary:
	var panel := _make_hud_panel(card_position, Vector2(193, 72))
	var portrait := _make_hud_portrait(panel, "res://assets/extracted/images/image_0738.jpg")
	var title := _make_hud_label(panel, "未出征", Vector2(66, 1), Vector2(124, 19), 14, Color("d69b21"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hp_meter := _add_absolute_meter(panel, Vector2(66, 20), Vector2(124, 12), Color("f22c24"))
	var exp_meter := _add_absolute_meter(panel, Vector2(66, 34), Vector2(124, 12), Color("2774db"))
	var footer := _make_hud_label(panel, "幻兽栏空闲", Vector2(3, 55), Vector2(104, 14), 9, Color("f0f0f0"))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var recall_button := _make_hud_button(panel, "召回", Vector2(108, 50), Vector2(38, 19))
	recall_button.pressed.connect(_on_hud_pet_recall.bind(card_index))
	var combine_button := _make_hud_button(panel, "合体", Vector2(147, 50), Vector2(43, 19))
	combine_button.pressed.connect(_on_hud_pet_combine.bind(card_index))
	return {
		"panel":panel,
		"title":title,
		"portrait":portrait,
		"hp_bar":hp_meter.bar,
		"hp_text":hp_meter.text,
		"secondary_bar":exp_meter.bar,
		"secondary_text":exp_meter.text,
		"footer":footer,
		"recall_button":recall_button,
		"combine_button":combine_button,
		"instance_id":0,
	}


func _make_hud_button(parent: Control, button_text: String, button_position: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.text = button_text
	button.position = button_position
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color("f5f5f5"))
	button.add_theme_color_override("font_hover_color", Color("ffff59"))
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2.ZERO
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color("444444")
	btn_style.border_color = Color("252525")
	btn_style.set_border_width_all(1)
	btn_style.set_content_margin_all(0.0)
	button.add_theme_stylebox_override("normal", btn_style)
	button.add_theme_stylebox_override("hover", btn_style)
	button.add_theme_stylebox_override("pressed", btn_style)
	parent.add_child(button)
	# Re-apply the intended 19px button height after tree entry.
	button.set_deferred("size", button_size)
	return button


func _pet_portrait_path(template_id: String) -> String:
	match template_id:
		"strange_beast":
			return "res://assets/extracted/images/image_0744.jpg"
		"year_pig":
			return "res://assets/extracted/images/image_0748.jpg"
		"lulu_pet":
			return "res://assets/extracted/images/image_0740.jpg"
		"holy_angel":
			return "res://assets/extracted/images/image_0750.jpg"
		_:
			return "res://assets/extracted/images/image_0738.jpg"


func _set_meter(card: Dictionary, prefix: String, value: int, maximum: int, secondary: bool = false) -> void:
	var bar: ProgressBar = card.secondary_bar if secondary else card.hp_bar
	var text_label: Label = card.secondary_text if secondary else card.hp_text
	_set_meter_nodes(bar, text_label, prefix, value, maximum)


func _set_meter_nodes(bar: ProgressBar, text_label: Label, prefix: String, value: int, maximum: int) -> void:
	bar.value = clampf(float(value) * 100.0 / float(maxi(1, maximum)), 0.0, 100.0)
	text_label.text = "%s %d/%d" % [prefix, value, maximum]

func _build_status_line() -> void:
	status_label = Label.new()
	status_label.position = Vector2(4, 478)
	status_label.size = Vector2(692, 26)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("315bff"))
	status_label.add_theme_color_override("font_shadow_color", Color.WHITE)
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Status prompt must render above any open panel (inventory spans y 300..507
	# and would otherwise cover the prompt at y 478..504).
	status_label.z_index = 60
	add_child(status_label)


func _build_bottom_bar() -> void:
	# Root frame 6: sprite908 at (5.2,517.25), music at (245.7,518.75),
	# trash at (301.05,513.65), then five 62x32 buttons from x=378.
	bottom_bar = Panel.new()
	bottom_bar.position = Vector2(0, 512)
	bottom_bar.size = Vector2(700, 38)
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var footer_style := StyleBoxFlat.new()
	footer_style.bg_color = Color("9b6500")
	footer_style.border_color = Color("202020")
	footer_style.set_border_width_all(1)
	bottom_bar.add_theme_stylebox_override("panel", footer_style)
	# Footer buttons must stay clickable/visible above any open panel.
	bottom_bar.z_index = 55
	add_child(bottom_bar)

	day_label = Label.new()
	day_label.position = Vector2(5.2, 4)
	day_label.size = Vector2(176, 27)
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	day_label.add_theme_font_size_override("font_size", 12)
	day_label.add_theme_color_override("font_color", Color.BLACK)
	day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.add_child(day_label)

	time_box = Label.new()
	time_box.text = "15"
	time_box.position = Vector2(185.7, 6)
	time_box.size = Vector2(54, 22)
	time_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_box.add_theme_font_size_override("font_size", 13)
	time_box.add_theme_color_override("font_color", Color("ff2d58"))
	var time_style := StyleBoxFlat.new()
	time_style.bg_color = Color("ffb31a")
	time_style.border_color = Color.BLACK
	time_style.set_border_width_all(2)
	time_box.add_theme_stylebox_override("normal", time_style)
	time_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.add_child(time_box)

	music_toggle = CheckBox.new()
	music_toggle.text = "音乐"
	music_toggle.position = Vector2(245.7, 4)
	music_toggle.size = Vector2(55, 26)
	music_toggle.button_pressed = true
	music_toggle.focus_mode = Control.FOCUS_NONE
	music_toggle.add_theme_font_size_override("font_size", 14)
	music_toggle.add_theme_color_override("font_color", Color.WHITE)
	music_toggle.add_theme_color_override("font_hover_color", Color("ffff66"))
	music_toggle.toggled.connect(_toggle_music)
	bottom_bar.add_child(music_toggle)

	trash_button = Button.new()
	trash_button.text = "垃圾箱"
	trash_button.position = Vector2(301.05, 1.65)
	trash_button.size = Vector2(76, 32)
	trash_button.focus_mode = Control.FOCUS_NONE
	trash_button.add_theme_font_size_override("font_size", 13)
	trash_button.add_theme_color_override("font_color", Color("6fc879"))
	trash_button.add_theme_color_override("font_hover_color", Color("c8ff67"))
	trash_button.add_theme_stylebox_override("normal", _footer_style(Color("5c5c5c")))
	trash_button.add_theme_stylebox_override("hover", _footer_style(Color("777777")))
	trash_button.add_theme_stylebox_override("pressed", _footer_style(Color("444444")))
	trash_button.pressed.connect(_trash_hint)
	bottom_bar.add_child(trash_button)

	var positions := {
		"背包":378.0,
		"装备":441.7,
		"幻兽":505.2,
		"技能":568.7,
		"VIP":631.7,
	}
	for button_name: String in positions:
		var text_color := Color.WHITE
		if button_name == "幻兽":
			text_color = Color("fff200")
		elif button_name == "VIP":
			text_color = Color("00f4d5")
		var button := _make_footer_button(button_name, Vector2(float(positions[button_name]), 0), text_color)
		bottom_bar.add_child(button)
		footer_buttons[button_name] = button
		match button_name:
			"背包": button.pressed.connect(_toggle_inventory)
			"装备": button.pressed.connect(_toggle_equipment)
			"幻兽": button.pressed.connect(_toggle_pets)
			"技能": button.pressed.connect(_toggle_skills)
			"VIP": button.pressed.connect(_toggle_progression)


func _footer_style(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color("252525")
	style.set_border_width_all(1)
	return style


func _make_footer_button(button_text: String, button_position: Vector2, text_color: Color) -> Button:
	var button := Button.new()
	button.text = button_text
	button.position = button_position
	button.size = Vector2(62, 32)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", text_color)
	# DefineButton2 characters 893-897 share shape890/891/892.
	button.add_theme_stylebox_override("normal", _footer_style(Color("ff6600")))
	button.add_theme_stylebox_override("hover", _footer_style(Color("ffcc33")))
	button.add_theme_stylebox_override("pressed", _footer_style(Color("ff9900")))
	return button


func _weekday_name(day: int) -> String:
	var names := ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
	return names[posmod(day, 7)]

func _build_item_tooltip() -> void:
	item_tooltip_panel = PanelContainer.new()
	item_tooltip_panel.size = Vector2(210, 145)
	item_tooltip_panel.z_index = 50
	var style := StyleBoxFlat.new()
	style.bg_color = Color("333333e8")
	style.border_color = Color("d2a636")
	style.set_border_width_all(2)
	item_tooltip_panel.add_theme_stylebox_override("panel", style)
	add_child(item_tooltip_panel)
	item_tooltip_text = RichTextLabel.new()
	item_tooltip_text.bbcode_enabled = true
	item_tooltip_text.fit_content = false
	item_tooltip_text.scroll_active = false
	item_tooltip_panel.add_child(item_tooltip_text)
	item_tooltip_panel.hide()


func _build_monster_tooltip() -> void:
	# Native tsxs/sprite972 measures 123x74 and follows the hovered monster.
	monster_tooltip_panel = Panel.new()
	monster_tooltip_panel.size = Vector2(123, 74)
	monster_tooltip_panel.custom_minimum_size = Vector2(123, 74)
	monster_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monster_tooltip_panel.z_index = 49
	var style := StyleBoxFlat.new()
	style.bg_color = Color("777777ee")
	style.border_color = Color("202020")
	style.set_border_width_all(1)
	monster_tooltip_panel.add_theme_stylebox_override("panel", style)
	add_child(monster_tooltip_panel)
	monster_tooltip_text = Label.new()
	monster_tooltip_text.position = Vector2(5, 3)
	monster_tooltip_text.size = Vector2(113, 68)
	monster_tooltip_text.add_theme_font_size_override("font_size", 12)
	monster_tooltip_text.add_theme_color_override("font_shadow_color", Color("00000080"))
	monster_tooltip_text.add_theme_constant_override("shadow_offset_x", 1)
	monster_tooltip_text.add_theme_constant_override("shadow_offset_y", 1)
	monster_tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monster_tooltip_panel.add_child(monster_tooltip_text)
	monster_tooltip_panel.hide()


func _build_panels() -> void:
	inventory_panel = InventoryPanel.new()
	add_child(inventory_panel)
	inventory_panel.item_focused.connect(_show_item_description)
	inventory_panel.item_unfocused.connect(_hide_item_description)
	inventory_panel.hide()
	warehouse_panel = InventoryPanel.new()
	warehouse_panel.container_name = "warehouse"
	warehouse_panel.panel_title = "仓库"
	add_child(warehouse_panel)
	warehouse_panel.item_focused.connect(_show_item_description)
	warehouse_panel.item_unfocused.connect(_hide_item_description)
	warehouse_panel.hide()
	gold_shop = ShopPanel.new()
	gold_shop.shop_title = "杂货商"
	gold_shop.currency = "gold"
	gold_shop.message_changed.connect(_set_status)
	add_child(gold_shop)
	gold_shop.hide()
	stone_shop = ShopPanel.new()
	stone_shop.shop_title = "收藏家"
	stone_shop.currency = "magic_stones"
	stone_shop.message_changed.connect(_set_status)
	add_child(stone_shop)
	stone_shop.hide()
	equipment_panel = EquipmentPanel.new()
	add_child(equipment_panel)
	equipment_panel.item_focused.connect(_show_item_description)
	equipment_panel.item_unfocused.connect(_hide_item_description)
	equipment_panel.hide()
	enhancement_panel = EnhancementPanel.new()
	enhancement_panel.message_changed.connect(_set_status)
	add_child(enhancement_panel)
	enhancement_panel.hide()
	pet_panel = PetPanel.new()
	pet_panel.message_changed.connect(_set_status)
	add_child(pet_panel)
	pet_panel.hide()
	research_panel = ResearchPanel.new()
	research_panel.message_changed.connect(_set_status)
	add_child(research_panel)
	research_panel.hide()
	progression_panel = ProgressionPanel.new()
	progression_panel.message_changed.connect(_set_status)
	add_child(progression_panel)
	progression_panel.hide()
	quest_panel = QuestPanel.new()
	quest_panel.message_changed.connect(_set_status)
	add_child(quest_panel)
	quest_panel.hide()
	skill_panel = SkillPanel.new()
	skill_panel.message_changed.connect(_set_status)
	add_child(skill_panel)
	skill_panel.hide()
	scene_battle_controller = SceneBattleController.new()
	scene_battle_controller.player_actor = player
	scene_battle_controller.message_changed.connect(_set_status)
	scene_battle_controller.player_hp_changed.connect(_on_scene_player_hp_changed)
	scene_battle_controller.battle_finished.connect(_on_scene_battle_finished)
	add_child(scene_battle_controller)
	dialogue_panel = DialoguePanel.new()
	dialogue_panel.action_requested.connect(_handle_dialogue_action)
	add_child(dialogue_panel)
	dialogue_panel.hide()
	adventurer_roster_panel = AdventurerRosterPanel.new()
	adventurer_roster_panel.message_changed.connect(_set_status)
	adventurer_roster_panel.mail_requested.connect(_open_adventurer_mail)
	adventurer_roster_panel.trade_requested.connect(_open_adventurer_trade)
	add_child(adventurer_roster_panel)
	adventurer_roster_panel.hide()
	adventurer_mail_panel = AdventurerMailPanel.new()
	adventurer_mail_panel.message_changed.connect(_set_status)
	add_child(adventurer_mail_panel)
	adventurer_mail_panel.hide()
	adventurer_trade_panel = AdventurerTradePanel.new()
	adventurer_trade_panel.message_changed.connect(_set_status)
	add_child(adventurer_trade_panel)
	adventurer_trade_panel.hide()
	ranking_panel = RankingPanel.new()
	ranking_panel.message_changed.connect(_set_status)
	add_child(ranking_panel)
	ranking_panel.hide()
	arena_panel = ArenaPanel.new()
	arena_panel.message_changed.connect(_set_status)
	arena_panel.start_requested.connect(_start_arena_match)
	add_child(arena_panel)
	arena_panel.hide()
	guild_market_panel = GuildMarketPanel.new()
	guild_market_panel.message_changed.connect(_set_status)
	add_child(guild_market_panel)
	guild_market_panel.hide()
	property_territory_panel = PropertyTerritoryPanel.new()
	property_territory_panel.message_changed.connect(_set_status)
	add_child(property_territory_panel)
	property_territory_panel.hide()
	border_command_panel = BorderCommandPanel.new()
	border_command_panel.message_changed.connect(_set_status)
	add_child(border_command_panel)
	border_command_panel.hide()
	ice_codex_panel = IceCodexPanel.new()
	ice_codex_panel.message_changed.connect(_set_status)
	add_child(ice_codex_panel)
	ice_codex_panel.hide()
	abyss_board_panel = AbyssBoardPanel.new()
	abyss_board_panel.message_changed.connect(_set_status)
	add_child(abyss_board_panel)
	abyss_board_panel.hide()
	challenge_board_panel = ChallengeBoardPanel.new()
	challenge_board_panel.message_changed.connect(_set_status)
	add_child(challenge_board_panel)
	challenge_board_panel.hide()
	pet_endgame_panel = PetEndgamePanel.new()
	pet_endgame_panel.message_changed.connect(_set_status)
	add_child(pet_endgame_panel)
	pet_endgame_panel.hide()
	season_board_panel = SeasonBoardPanel.new()
	season_board_panel.message_changed.connect(_set_status)
	add_child(season_board_panel)
	season_board_panel.hide()
	arena_proxy = TextureRect.new()
	arena_proxy.name = "arena_proxy"
	arena_proxy.visible = false
	arena_proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_proxy.position = Vector2(280, 180)
	arena_proxy.size = Vector2(80, 80)
	add_child(arena_proxy)
	ending_panel = EndingPanel.new()
	add_child(ending_panel)


func _connect_state_signals() -> void:
	GameState.progression_changed.connect(_refresh_status_cards)
	GameState.equipment_changed.connect(_refresh_status_cards)
	GameState.pets_changed.connect(_refresh_status_cards)
	GameState.social_changed.connect(_refresh_status_cards)
	GameState.time_changed.connect(_refresh_status_cards)


func _refresh_status_cards() -> void:
	if player_status_card.is_empty():
		return
	var stats: Dictionary = GameState.get_player_stats()
	var military: Dictionary = GameState.get_military_rank()
	var nobility: Dictionary = GameState.get_nobility_rank()
	player_status_card.title.text = "魔域玩家"
	_set_meter(player_status_card, "生命", int(stats.current_hp), int(stats.max_hp))
	_set_meter_nodes(
		player_status_card.stamina_bar,
		player_status_card.stamina_text,
		"体力",
		GameState.player_current_stamina,
		GameState.get_player_max_stamina(),
	)
	_set_meter(player_status_card, "经验", GameState.experience, GameState.experience_to_next_level(), true)
	player_status_card.footer.text = "%d级  %s  %s" % [GameState.level, nobility.name, military.name]
	var deployed: Array[Dictionary] = []
	for pet: Dictionary in GameState.pets:
		if bool(pet.get("deployed", false)):
			deployed.append(pet)
	for index in pet_status_cards.size():
		var card: Dictionary = pet_status_cards[index]
		if index >= deployed.size():
			card.instance_id = 0
			card.title.text = "未出征"
			card.portrait.hide()
			_set_meter(card, "生命", 0, 1)
			_set_meter(card, "经验", 0, 1, true)
			card.footer.text = "幻兽栏空闲"
			card.recall_button.hide()
			card.combine_button.hide()
			continue
		var pet: Dictionary = deployed[index]
		var pet_stats: Dictionary = GameState.pet_service.get_stats(pet)
		var pet_max_hp := int(pet_stats.max_hp)
		var pet_hp := clampi(int(pet.get("current_hp", pet_max_hp)), 0, pet_max_hp)
		var next_exp := GameState.pet_service.experience_to_next_level(int(pet.level))
		card.instance_id = int(pet.get("instance_id", 0))
		card.title.text = str(pet.custom_name)
		card.portrait.texture = load(_pet_portrait_path(str(pet.get("template_id", ""))))
		card.portrait.show()
		_set_meter(card, "生命", pet_hp, pet_max_hp)
		_set_meter(card, "经验", int(pet.experience), next_exp, true)
		card.footer.text = "%d级  幻兽" % int(pet.level)
		card.recall_button.show()
		card.combine_button.text = "解体" if bool(pet.get("combined", false)) else "合体"
		card.combine_button.show()
	day_label.text = "第%d天 %s  今天时间：" % [GameState.current_day, _weekday_name(GameState.current_day)]
	time_box.text = str(GameState.remaining_time())


func _hud_pet_for_card(card_index: int) -> Dictionary:
	if card_index < 0 or card_index >= pet_status_cards.size():
		return {}
	var instance_id := int(pet_status_cards[card_index].get("instance_id", 0))
	var pet_index := GameState.get_pet_index(instance_id)
	if pet_index < 0:
		return {}
	return GameState.pets[pet_index]


func _hud_pet_change_allowed() -> bool:
	if scene_battle_controller != null and scene_battle_controller.is_active():
		if not scene_battle_controller.can_change_pet_configuration():
			_set_status("攻击动作尚未结束，现在不能切换幻兽状态。")
			return false
		scene_battle_controller.commit_active_health()
	return true


func _on_hud_pet_recall(card_index: int) -> void:
	var pet := _hud_pet_for_card(card_index)
	if pet.is_empty() or not _hud_pet_change_allowed():
		return
	var pet_name := str(pet.get("custom_name", "幻兽"))
	if not GameState.set_pet_deployed(int(pet.get("instance_id", 0)), false):
		_set_status("召回失败。")
		return
	if scene_battle_controller != null and scene_battle_controller.is_active():
		scene_battle_controller.refresh_player_configuration()
	_set_status("%s已召回；再次出征时默认处于未合体状态。" % pet_name)


func _on_hud_pet_combine(card_index: int) -> void:
	var pet := _hud_pet_for_card(card_index)
	if pet.is_empty() or not _hud_pet_change_allowed():
		return
	var will_combine := not bool(pet.get("combined", false))
	if not GameState.set_pet_combined(int(pet.get("instance_id", 0)), will_combine):
		_set_status("幻兽状态切换失败。")
		return
	if scene_battle_controller != null and scene_battle_controller.is_active():
		scene_battle_controller.refresh_player_configuration()
	_set_status("%s已%s：%s" % [
		str(pet.get("custom_name", "幻兽")),
		"合体" if will_combine else "解体",
		"攻防并入人物并优先承受伤害。" if will_combine else "仅保留战斗力加成，不再攻击或承伤。",
	])

func _show_item_description(item: Dictionary, source_panel: Control) -> void:
	var definition: Dictionary = GameState.get_item_definition(str(item.get("item_id", "")))
	var text := "[color=#ffd34d][font_size=18]%s[/font_size][/color]\n%s\n数量：%d" % [
		str(definition.get("name", "未知物品")),
		str(definition.get("description", "暂无说明")),
		int(item.get("quantity", 1)),
	]
	if item.has("enhancement"):
		var enhancement: Dictionary = item.enhancement
		text += "\n[color=#69d8ff]品质 +%d　魔魂 +%d\n天魂 %d　地魂 %d　孔洞 %d[/color]" % [
			int(enhancement.get("quality_level", 0)),
			int(enhancement.get("magic_soul_level", 0)),
			int(enhancement.get("heaven_soul_level", 0)),
			int(enhancement.get("earth_soul_level", 0)),
			int(enhancement.get("socket_count", 0)),
		]
	item_tooltip_text.text = text
	if source_panel.position.x > 240.0:
		item_tooltip_panel.position = Vector2(source_panel.position.x - 216.0, source_panel.position.y + 30.0)
	else:
		item_tooltip_panel.position = Vector2(source_panel.position.x + source_panel.size.x + 6.0, source_panel.position.y + 30.0)
	item_tooltip_panel.show()


func _hide_item_description() -> void:
	item_tooltip_panel.hide()


func _add_decoration(entity_id: String, texture_path: String, decoration_position: Vector2, decoration_size: Vector2) -> void:
	var decoration := TextureRect.new()
	decoration.texture = load(texture_path)
	decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	decoration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	decoration.position = decoration_position
	decoration.size = decoration_size
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.set_meta("world_entity_id", entity_id)
	decoration.set_meta("world_entity_kind", "decoration")
	actor_layer.add_child(decoration)


func _add_actor(actor_name: String, texture_path: String, actor_position: Vector2, actor_size: Vector2, action_id: String, label_color: Color = Color("00ff45")) -> void:
	var actor := TextureRect.new()
	actor.texture = load(texture_path)
	actor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	actor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	actor.position = actor_position
	actor.size = actor_size
	actor.mouse_filter = Control.MOUSE_FILTER_STOP
	actor.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var entity_kind := "monster" if action_id.begins_with("battle:") else ("interactive_prop" if (action_id.begins_with("lottery:") or action_id.begins_with("mine:") or action_id == "war_soul_chest" or action_id == "fuwa_reward" or action_id.begins_with("evidence:") or action_id.begins_with("scout:") or (action_id.begins_with("ice:") and not action_id.begins_with("ice_")) or (action_id.begins_with("abyss:") and not action_id.begins_with("abyss_"))) else "npc")
	actor.set_meta("world_entity_id", action_id)
	actor.set_meta("world_entity_kind", entity_kind)
	actor.set_meta("world_action_id", action_id)
	actor.gui_input.connect(_on_actor_input.bind(action_id))
	actor.mouse_entered.connect(_actor_hover.bind(actor, true, action_id))
	actor.mouse_exited.connect(_actor_hover.bind(actor, false, action_id))
	actor_layer.add_child(actor)
	var label := Label.new()
	label.text = actor_name
	label.position = actor_position + Vector2(-12, -19)
	label.size = Vector2(actor_size.x + 24, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", label_color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actor_layer.add_child(label)
	if action_id.begins_with("battle:"):
		label.hide()
	interactive_actors[action_id] = actor
	actor_labels[action_id] = label


func _actor_hover(actor: TextureRect, hovered: bool, action_id: String = "") -> void:
	actor.modulate = Color(1.2, 1.2, 0.75) if hovered else Color.WHITE
	if not action_id.begins_with("battle:"):
		return
	if hovered:
		_show_monster_tooltip(action_id, actor)
	else:
		_hide_monster_tooltip()


func _monster_tooltip_color(monster_power: int, player_power: int) -> Color:
	if monster_power > player_power + 5:
		return Color("333333")
	if monster_power > player_power:
		return Color("ff0000")
	if monster_power == player_power:
		return Color("ffffff")
	return Color("009933")


func _show_monster_tooltip(action_id: String, actor: TextureRect) -> void:
	var monster_id := _world_monster_id_from_action(action_id)
	var monster: Dictionary = combat.get_monster(monster_id)
	if monster.is_empty():
		_hide_monster_tooltip()
		return
	var level := int(monster.get("original_level", monster.get("level", 1)))
	var monster_power := int(monster.get("combat_power", level))
	var experience_multiplier := int(combat.progression.get("player_experience_multiplier", 1))
	var experience_increase := maxi(0, experience_multiplier - 1) * 100
	monster_tooltip_text.text = "%s(%d级)\n%d战斗力\n经验增加%d%%" % [
		str(monster.get("name", monster_id)),
		level,
		monster_power,
		experience_increase,
	]
	var player_power := int(GameState.get_player_stats().get("combat_power", 0))
	monster_tooltip_text.add_theme_color_override("font_color", _monster_tooltip_color(monster_power, player_power))
	monster_tooltip_panel.position = Vector2(
		clampf(actor.position.x, 0.0, 577.0),
		clampf(actor.position.y - 59.0, 72.0, 402.0)
	)
	monster_tooltip_panel.show()


func _hide_monster_tooltip() -> void:
	if monster_tooltip_panel != null:
		monster_tooltip_panel.hide()


func _on_actor_input(event: InputEvent, action_id: String) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var dispatch_result: Dictionary = _dispatch_world_action(action_id, event)
	if str(dispatch_result.get("code", "")) == "UNSUPPORTED_ACTION":
		_set_status("无法识别的交互。")


func _dispatch_world_action(action_id: String, event: InputEvent) -> Dictionary:
	# 统一dispatcher：生产点击和测试都经过此入口。
	# 只负责路由到现有handler，不复制战斗/挖矿/抽奖公式。
	# 返回 {"route": <route>, "code": "OK"或"UNSUPPORTED_ACTION"}。
	if action_id.begins_with("battle:"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_engage_world_monster(action_id)
			return {"route": "battle", "code": "OK"}
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			var skill_id := _best_quick_skill()
			if skill_id.is_empty():
				_set_status("尚未学会主动技能；左键点击怪物可普通攻击。")
			else:
				_engage_world_monster(action_id, skill_id)
			return {"route": "battle", "code": "OK"}
		return {"route": "battle", "code": "OK"}
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return {"route": "ignored", "code": "OK"}
	if action_id.begins_with("mine:"):
		_mine_at_node(action_id)
		return {"route": "mine", "code": "OK"}
	if action_id.begins_with("lottery:"):
		_open_lottery_chest(action_id)
		return {"route": "lottery", "code": "OK"}
	if action_id.begins_with("war_soul_"):
		_open_actor_dialogue(action_id)
		return {"route": "war_soul", "code": "OK"}
	if action_id.begins_with("territory:"):
		_open_actor_dialogue(action_id)
		return {"route": "territory", "code": "OK"}
	if action_id.begins_with("evidence:"):
		_collect_chapter_evidence(action_id)
		return {"route": "chapter_evidence", "code": "OK"}
	if action_id.begins_with("scout:"):
		_collect_border_scout(action_id)
		return {"route": "border_scout", "code": "OK"}
	if action_id.begins_with("ice:") and not action_id.begins_with("ice_"):
		_collect_ice_probe(action_id)
		return {"route": "ice_investigate", "code": "OK"}
	if action_id.begins_with("abyss:") and not action_id.begins_with("abyss_"):
		_collect_abyss_world(action_id)
		return {"route": "abyss_investigate", "code": "OK"}
	if action_id.begins_with("abyss_"):
		_open_actor_dialogue(action_id)
		return {"route": "npc_dialogue", "code": "OK"}
	if action_id.begins_with("ice_"):
		_open_actor_dialogue(action_id)
		return {"route": "npc_dialogue", "code": "OK"}
	if action_id.begins_with("border_"):
		_open_actor_dialogue(action_id)
		return {"route": "npc_dialogue", "code": "OK"}
	if action_id.begins_with("chapter_"):
		_open_actor_dialogue(action_id)
		return {"route": "npc_dialogue", "code": "OK"}
	# dialogue action由_handle_dialogue_action处理，不经过此处
	var known_world_actors: Array = [
		"grocery","stone_shop","collector","warehouse","daily_officer",
		"stone_synthesizer","forger","pet_master","experience_mentor",
		"research","marshal","prime_minister","princess","maid","maid_combat_stone",
		"pk_officer","lottery_officer","king","fuwa_messenger","fuwa_reward",
		"fuwa_completion","war_soul_explorer","war_soul_chest",
	]
	if action_id in known_world_actors:
		_open_actor_dialogue(action_id)
		return {"route": "npc_dialogue", "code": "OK"}
	return {"route": "UNSUPPORTED", "code": "UNSUPPORTED_ACTION"}


func _best_quick_skill() -> String:
	var best_skill := ""
	var best_multiplier := 1.0
	for skill_id: String in GameState.skill_service.learned_active_skills(GameState.learned_skills):
		var multiplier := GameState.skill_service.active_damage_multiplier(GameState.learned_skills, skill_id)
		if multiplier > best_multiplier:
			best_skill = skill_id
			best_multiplier = multiplier
	return best_skill


func _mine_at_node(_action_id: String) -> void:
	var result := GameState.mine_ore()
	var item_name := str(GameState.get_item_definition(str(result.get("item_id", ""))).get("name", "矿石"))
	if bool(result.get("success", false)):
		_set_status("获得了品质是%d的%s；今天时间剩余%d。" % [int(result.get("quality", 1)), item_name, int(result.get("time_remaining", 0))])
	else:
		_set_status("背包已满，矿石没有装下；挖矿仍消耗了1点时间。")
	if bool(result.get("day_advanced", false)):
		_set_status("新的一天开始了。获得了品质是%d的%s。" % [int(result.get("quality", 1)), item_name] if bool(result.get("success", false)) else "新的一天开始了，但背包已满。")


func _open_actor_dialogue(action_id: String) -> void:
	_hide_all_panels()
	if action_id.begins_with("chapter_"):
		_handle_dialogue_action(action_id)
		return
	if action_id.begins_with("border_"):
		_handle_dialogue_action(action_id)
		return
	if action_id.begins_with("ice_"):
		_handle_dialogue_action(action_id)
		return
	var actions: Array[Dictionary] = []
	var speaker := ""
	var words := ""
	match action_id:
		"grocery":
			speaker = "杂货商"
			words = "我这里出售日常物品，也可以直接结算金币。"
			actions = [{"label":"购买","action":"gold_buy"},{"label":"出售","action":"gold_sell"},{"label":"离开","action":"close"}]
		"stone_shop":
			speaker = "收藏商店"
			words = "这里出售珍贵物品，也可以直接结算魔石。"
			actions = [{"label":"购买","action":"stone_buy"},{"label":"出售","action":"stone_sell"},{"label":"离开","action":"close"}]
		"collector":
			speaker = "收藏家"
			words = "我们家族世代收藏稀有物品。金矿、灵魂王、电浆药水、白玫瑰、月光宝盒、满经验球和极品装备，都可以拿来与我交易。"
			actions = [{"label":"我有些好东西要卖","action":"stone_sell"},{"label":"商会事务","action":"guild_market"},{"label":"离开","action":"close"}]
		"warehouse":
			speaker = "仓库管理员"
			words = "需要存放或取出物品吗？背包和仓库可以直接拖动整理。"
			actions = [{"label":"打开仓库","action":"warehouse"},{"label":"离开","action":"close"}]
		"pet_master":
			speaker = "幻兽幻化师"
			words = "这里可以查看幻兽状态、出征与幻化。"
			actions = [{"label":"查看幻兽","action":"pets"},{"label":"离开","action":"close"}]
		"experience_mentor":
			speaker = "经验导师"
			words = "良品以上或带洞装备可以提炼为满经验球：良品至极品分别为1至4个；一洞另加2个、二洞另加5个；魔魂+9另加1个、+12另加2个。"
			actions = [{"label":"用背包中的装备换经验球","action":"exchange_equipment_exp"},{"label":"离开","action":"close"}]
		"stone_synthesizer":
			speaker = "宝石合成师"
			words = "我可以用20个对应的普通宝石合成魔魂之心、幻魔之心、灵魂王、高级经验石或高级战斗力石。"
			actions = [
				{"label":"合成灵魂王","action":"synthesize:soul_king"},
				{"label":"合成魔魂之心","action":"synthesize:magic_soul_heart"},
				{"label":"合成幻魔之心","action":"synthesize:illusion_heart"},
				{"label":"合成高级经验石","action":"synthesize:advanced_exp_stone"},
				{"label":"合成高级战斗力石","action":"synthesize:advanced_combat_stone"},
				{"label":"离开","action":"close"},
			]
		"fuwa_messenger":
			_open_fuwa_messenger_dialogue()
			return
		"fuwa_reward":
			_claim_current_fuwa_reward()
			return
		"fuwa_completion":
			_open_fuwa_completion_dialogue()
			return
		"research":
			_open_research_dialogue()
			return
		"forger":
			var quest_started := GameState.try_unlock_war_soul_quest()
			speaker = "装备锻造师"
			if bool(GameState.story_flags.get("war_soul_secret_unlocked", false)):
				words = "你已经找到了战魂之心。装备升极品、开洞或使用战魂晶石都可能激活战魂；战魂之心可以必定激活。"
			elif bool(GameState.story_flags.get("war_soul_quest_available", false)):
				words = "你的全身六件装备都是极品。听说从戈壁可以找到有关战魂的秘密，你应该去看一看。" if quest_started else "有关战魂秘密的线索就在戈壁，去找那里的探险家。"
			else:
				words = "我负责品质、魔魂、天魂与地魂锻造。全身六件装备都达到极品后，也许能发现新的秘密。"
			actions = [{"label":"开始锻造","action":"enhancement"},{"label":"离开","action":"close"}]
		"war_soul_explorer":
			_open_war_soul_explorer_dialogue()
			return
		"war_soul_chest":
			_reveal_war_soul_guardian()
			return
		"princess":
			_open_princess_dialogue()
			return
		"daily_officer":
			_open_daily_officer_dialogue()
			return
		"marshal":
			_open_marshal_dialogue()
			return
		"king":
			_open_king_dialogue()
			return
		"prime_minister":
			_open_prime_minister_dialogue()
			return
		"pk_officer":
			_open_pk_officer_dialogue()
			return
		"maid":
			_open_maid_dialogue()
			return
		"maid_combat_stone":
			_open_maid_combat_stone_dialogue()
			return
		"lottery_officer":
			_open_lottery_officer_dialogue()
			return
		_:
			if action_id.begins_with("territory:"):
				_open_territory_dialogue(action_id.trim_prefix("territory:"))
				return
			if action_id.begins_with("battle:"):
				var monster_id := action_id.trim_prefix("battle:")
				speaker = "敌对目标"
				words = "它发现了你。是否开始战斗？"
				actions = [{"label":"战斗","action":action_id},{"label":"离开","action":"close"}]
	if speaker.is_empty():
		return
	dialogue_panel.open_dialogue(speaker, words, actions)


func _exchange_equipment_for_exp_balls() -> void:
	var result := GameState.exchange_first_inventory_equipment_for_exp_balls()
	if bool(result.get("success", false)):
		_set_status("经验导师提炼完成：%s换得%d个满经验球。" % [str(result.get("item_name", "装备")), int(result.get("exp_balls", 0))])
	else:
		_set_status("背包中没有良品以上、带洞或魔魂+9以上的可提炼装备。")


func _synthesize_stone(recipe_id: String) -> void:
	var result := GameState.synthesize_stone(recipe_id)
	if bool(result.get("success", false)):
		var item_name := str(GameState.get_item_definition(recipe_id).get("name", recipe_id))
		_set_status("宝石合成成功：获得%s。" % item_name)
	else:
		var material_id := str(result.get("material_id", ""))
		var material_name := str(GameState.get_item_definition(material_id).get("name", material_id))
		_set_status("合成失败：需要20个%s。" % material_name)


func _open_territory_dialogue(map_id: String) -> void:
	var territory: Dictionary = GameState.get_territory(map_id)
	if territory.is_empty():
		return
	var territory_name := str(territory.get("name", map_id))
	var required_rank := str(territory.get("required_rank_name", ""))
	var words := "达到%s后可以挑战%s保护者。挑战胜利后，这里会成为你的唯一保护地，并每天赠与你一份发展物资。" % [required_rank, territory_name]
	if GameState.owned_territory == map_id:
		words += "\n你现在正是这里的保护者。"
	elif not GameState.owned_territory.is_empty():
		words += "\n挑战成功会放弃当前保护地。"
	var actions: Array[Dictionary] = [
		{"label":"查看每日奖励", "action":"territory_reward:%s" % map_id},
		{"label":"领取今日奖励", "action":"territory_claim:%s" % map_id},
		{"label":"我要挑战", "action":"territory_challenge:%s" % map_id},
		{"label":"领地与城堡", "action":"property_board"},
		{"label":"离开", "action":"close"},
	]
	dialogue_panel.open_dialogue("地图占领报名官", words, actions)


func _open_territory_reward_dialogue(map_id: String) -> void:
	var territory := GameState.get_territory(map_id)
	if territory.is_empty():
		return
	var reward_lines: Array[String] = []
	for raw_reward: Variant in territory.get("rewards", []):
		if not raw_reward is Dictionary:
			continue
		var item_id := str(raw_reward.get("item_id", ""))
		var item_name := str(GameState.get_item_definition(item_id).get("name", item_id))
		reward_lines.append("%s ×%d" % [item_name, int(raw_reward.get("quantity", 1))])
	var words := "%s保护者每日奖励：\n%s" % [str(territory.get("name", map_id)), "\n".join(reward_lines)]
	dialogue_panel.open_dialogue("地图占领报名官", words, [{"label":"返回", "action":"territory:%s" % map_id},{"label":"离开", "action":"close"}])


func _claim_territory_reward(map_id: String) -> void:
	var result := GameState.claim_territory_reward(map_id)
	if not bool(result.get("success", false)):
		match str(result.get("reason", "")):
			"not_owner": _set_status("你还不是这里的保护者。")
			"already_claimed": _set_status("今天的保护地奖励已经领取。")
			_: _set_status("当前无法领取保护地奖励。")
		return
	var claimed_count := 0
	for item_id: Variant in result.get("item_ids", []):
		if GameState.claim_loot(str(item_id)):
			claimed_count += 1
	var message := "保护地奖励已领取，共%d件物品。" % claimed_count
	if not GameState.loot_queue.is_empty():
		message += " 背包已满的部分保留在待领取队列。"
	_set_status(message)


func _show_territory_challenge_error(challenge: Dictionary) -> void:
	match str(challenge.get("reason", "")):
		"rank_too_low": _set_status("需要达到%s才有资格挑战。" % str(challenge.get("required_rank_name", "")))
		"already_challenged": _set_status("今天已经挑战过地图保护者。")
		"challenge_in_progress": _set_status("另一场保护地挑战仍在进行。")
		_: _set_status("当前不能发起保护地挑战。")


func _start_territory_challenge(map_id: String) -> void:
	var territory := GameState.get_territory(map_id)
	if territory.is_empty() or scene_battle_controller.is_active():
		return
	if int(GameState.get_player_stats().get("current_hp", 0)) <= 0:
		_set_status("人物没有生命值，请先双击背包中的果子恢复生命。")
		return
	var challenge := GameState.begin_territory_challenge(map_id)
	if not bool(challenge.get("success", false)):
		_show_territory_challenge_error(challenge)
		return
	var challenger_id := str(territory.get("challenger_id", ""))
	var action_id := "battle:%s" % challenger_id
	# The SWF sends isBoss=true to the battle field only after “我要挑战”.
	# Scene combat keeps that transition in the current map at a fixed battle anchor.
	if not interactive_actors.has(action_id):
		_add_actor(str(combat.get_monster(challenger_id).get("name", challenger_id)), "res://assets/extracted/images/image_1072.png", Vector2(535, 205), Vector2(101, 132), action_id, Color("ff9d35"))
	_engage_world_monster(action_id, "", true)

func _open_princess_dialogue() -> void:
	var level := int(GameState.get_affection_rank().get("level", 0))
	var greetings := [
		"你好，勇敢的人类战士。",
		"你好，勇敢的人类战士。",
		"你好，我的朋友。",
		"你好，我的好朋友，非常高兴见到你。",
		"你好，我的知己，终于等到你了。",
		"你好，我爱的人，你还好吗？",
		"你好，我的至爱。",
	]
	var actions: Array[Dictionary] = [{"label":"聊天","action":"princess_chat"},{"label":"送礼","action":"princess_gift"}]
	if bool(GameState.story_flags.get("princess_friend_gift_available", false)):
		actions.push_front({"label":"知己的礼物","action":"princess_friend_gift"})
	if GameState.current_day % 7 == 0:
		actions.append({"label":"星期天礼物","action":"princess_sunday_gift"})
	actions.append({"label":"离开","action":"close"})
	dialogue_panel.open_dialogue("公主", greetings[clampi(level, 0, 6)], actions)


func _open_princess_gift_dialogue() -> void:
	var rose_count := GameState.count_item("rose")
	var words := "送花可以增加友好度。99朵白玫瑰+50好感，999朵白玫瑰+250好感。当前白玫瑰：%d。" % rose_count
	var actions: Array[Dictionary] = [{"label":"送99朵白玫瑰","action":"give_roses:99"},{"label":"送999朵白玫瑰","action":"give_roses:999"},{"label":"返回","action":"princess"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("公主", words, actions)


func _give_princess_roses(count_str: String) -> void:
	var count := int(count_str)
	var result := GameState.give_roses(count)
	if not bool(result.get("success", false)):
		_set_status("白玫瑰不足，赠礼失败。" if str(result.get("reason", "")) == "missing_roses" else "赠礼失败。")
	else:
		var rank := GameState.get_affection_rank()
		_set_status("赠礼成功：消耗%d朵白玫瑰，好感+%d，当前关系：%s。" % [count, int(result.get("affection", 0)), str(rank.get("name", ""))])
	_open_princess_gift_dialogue()


func _chat_with_princess() -> void:
	var result := GameState.chat_with_princess()
	if not bool(result.get("success", false)):
		if str(result.get("reason", "")) == "already_chatted":
			_set_status("今天已经和公主聊过了。")
		else:
			_set_status("幻兽栏已满，无法领取公主准备的幻兽。")
		return
	var relationship_level := int(result.get("relationship_level", 0))
	var words := "听说你是位英勇的战士，我非常敬佩你的勇敢。"
	match relationship_level:
		1:
			words = "很高兴你能和我聊天。非常感谢你把我父亲救出来。" if bool(GameState.story_flags.get("king_rescued", false)) else "很高兴你能和我聊天。我最担心的是我的父亲，你有他的消息了吗？"
		2: words = "我的朋友，这些攻防型幻兽已经进化到极品1星以上。我把它赠与你，希望它能在战场上助你一臂之力。"
		3: words = "这个奇异兽是幻兽幻化时非常优秀的副幻兽，你把它带去吧。"
		4: words = "这是我精心为你培养的12星奇异兽，是非常少有的优秀幻化副幻兽。"
		5: words = "这是亚特兰蒂斯大陆非常稀有的极品19星奇异兽，你把它带上吧。"
		6: words = "你把这无比优秀的19星奇异兽带上吧。" if bool(GameState.story_flags.get("king_rescued", false)) else "你把这无比优秀的19星奇异兽带上吧，希望你早日救出我的父亲。"
	if not str(result.get("pet_template_id", "")).is_empty():
		var pet_name := str(GameState.pet_service.pet_database.get(str(result.pet_template_id), {}).get("name", "幻兽"))
		words += "\n你获得了%s（%.0f星）。" % [pet_name, float(result.get("pet_quality", 0.0)) / 100.0]
	words += "\n你与公主的友好度增加1点。"
	var actions: Array[Dictionary] = [{"label":"谢谢","action":"princess"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("公主", words, actions)


func _claim_princess_friend_gift() -> void:
	var result := GameState.claim_princess_friend_gift()
	if bool(result.get("success", false)):
		var actions: Array[Dictionary] = [{"label":"谢谢","action":"princess"},{"label":"离开","action":"close"}]
		dialogue_panel.open_dialogue("公主", "公主送给了你一只超级幻兽——年猪。", actions)
	elif str(result.get("reason", "")) == "pet_inventory_full":
		_set_status("幻兽栏已满，知己礼物尚未领取。")
	else:
		_set_status("现在没有可领取的知己礼物。")


func _claim_princess_sunday_gift() -> void:
	var result := GameState.claim_princess_sunday_gift()
	if bool(result.get("success", false)):
		var item_name := str(GameState.get_item_definition(str(result.item_id)).get("name", result.item_id))
		_set_status("公主赠送了：%s" % item_name)
	elif str(result.get("reason", "")) == "inventory_full":
		_set_status("背包已满，星期天礼物尚未领取。")
	elif str(result.get("reason", "")) == "already_claimed":
		_set_status("今天已经领取过公主的礼物。")
	else:
		_set_status("当前不能领取星期天礼物。")


func _open_maid_dialogue() -> void:
	var words := "我是公主的侍女，公主平时待我如同姐妹一样亲，无论发生什么事我都会陪着公主。"
	var actions: Array[Dictionary] = []
	if bool(GameState.story_flags.get("maid_year_pig_available", true)):
		words += "\n上次国王赏给我一只极其稀有的年猪幻兽，不知勇士能否用得上。"
		actions.append({"label":"用5888魔石交换","action":"maid_buy_year_pig"})
	actions.append({"label":"你是个好姑娘","action":"close"})
	dialogue_panel.open_dialogue("公主侍女", words, actions)


func _buy_maid_year_pig() -> void:
	var result := GameState.buy_maid_year_pig()
	if bool(result.get("success", false)):
		_set_status("消耗5,888魔石，获得幻兽年猪。")
	elif str(result.get("reason", "")) == "not_enough_magic_stones":
		_set_status("没有足够的魔石。")
	elif str(result.get("reason", "")) == "pet_inventory_full":
		_set_status("幻兽栏已满，交易没有扣除魔石。")
	else:
		_set_status("年猪已经交换过了。")


func _open_maid_combat_stone_dialogue() -> void:
	var words := "我自小跟随公主，看到公主每天都能快乐，我也就很高兴了。"
	var actions: Array[Dictionary] = []
	if bool(GameState.story_flags.get("maid_combat_stone_available", true)):
		words += "\n我每天可以给你一个高级战斗力石，只收2,800魔石。"
		actions.append({"label":"用2800魔石购买", "action":"maid_buy_combat_stone"})
	else:
		words += "\n今天的高级战斗力石已经给你了，明天再来吧。"
	actions.append({"label":"离开", "action":"close"})
	dialogue_panel.open_dialogue("公主侍女", words, actions)


func _buy_maid_combat_stone() -> void:
	var result := GameState.buy_maid_combat_stone()
	if bool(result.get("success", false)):
		_set_status("消耗2,800魔石，获得高级战斗力石。")
	elif str(result.get("reason", "")) == "not_enough_magic_stones":
		_set_status("没有足够的魔石。")
	elif str(result.get("reason", "")) == "inventory_full":
		_set_status("背包已满，交易没有扣除魔石。")
	else:
		_set_status("今天已经购买过高级战斗力石。")


func _open_lottery_officer_dialogue() -> void:
	var words := "国家为了鼓励勇士们英勇奋战，特别开设一抽奖房。抽奖房里的宝箱有各种各样的好东西，甚至是稀世极品，只要花上28魔石就能打开一个宝箱，每个宝箱都有可能得到极品。"
	var actions: Array[Dictionary] = [
		{"label":"好吧，让我来试试我的运气", "action":"enter_lottery_room"},
		{"label":"我对这事不感兴趣", "action":"close"},
	]
	dialogue_panel.open_dialogue("抽奖官", words, actions)


func _enter_lottery_room() -> void:
	_hide_all_panels()
	GameState.current_map_id = "lottery_room"
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("已进入抽奖房：每个宝箱消耗28魔石和2点时间。")


func _open_lottery_chest(action_id: String) -> void:
	var result := GameState.open_lottery_chest()
	if not bool(result.get("success", false)):
		if str(result.get("reason", "")) == "not_enough_magic_stones":
			_set_status("你不够28点魔石，不能支付抽奖费。")
		elif str(result.get("reason", "")) == "pet_inventory_full":
			_set_status("幻兽栏已满；本次宝箱仍消耗28魔石和2点时间。")
		else:
			_set_status("背包已满；本次宝箱仍消耗28魔石和2点时间。")
		return
	var reward_name := ""
	if str(result.get("reward_kind", "")) == "pet":
		reward_name = str(GameState.pet_service.pet_database.get(str(result.get("pet_template_id", "")), {}).get("name", "幻兽"))
	else:
		reward_name = str(GameState.get_item_definition(str(result.get("item_id", ""))).get("name", "装备"))
	_set_status("打开%s，获得%s（第%d档）。" % [action_id.trim_prefix("lottery:"), reward_name, int(result.get("tier", 4))])


func _open_prime_minister_dialogue() -> void:
	var actions: Array[Dictionary] = [
		{"label":"捐献金币","action":"prime_donate"},
		{"label":"功勋查询","action":"prime_merit"},
		{"label":"国王消息","action":"prime_king"},
		{"label":"关于爵位","action":"prime_nobility"},
		{"label":"没事","action":"close"},
	]
	dialogue_panel.open_dialogue("首相", "你好，我是国家首相。", actions)


func _open_prime_minister_merit() -> void:
	var rank := GameState.get_nobility_rank()
	var next_rank := GameState.progression_service.next_tier("nobility", GameState.nobility_merit)
	var words := "%s，你当前的功勋是：%s。" % [str(rank.get("name", "平民")), _format_number(GameState.nobility_merit)]
	if not next_rank.is_empty():
		words += "\n还需要%s功勋就能获得更高一级爵位。" % _format_number(int(next_rank.threshold) - GameState.nobility_merit)
	var actions: Array[Dictionary] = [{"label":"返回","action":"prime_minister"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("首相", words, actions)


func _open_prime_minister_king_news() -> void:
	var words := "感谢勇士们，我们的国王终于回来了。请听听国王对付魔族大军的策略。" if bool(GameState.story_flags.get("king_rescued", false)) else "人类的国王被魔族大军先锋部队俘虏了。亚特兰蒂斯大陆群龙无首，魔族大军不久将从北方雪狼冰原南下。人类必须尽快消灭境内先锋、救出国王并组织军队抵抗。"
	var actions: Array[Dictionary] = [{"label":"返回","action":"prime_minister"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("首相", words, actions)


func _open_prime_minister_nobility() -> void:
	var words := "国家需要大量金币。每捐献750,000金币可获得1点功勋。爵位会增加战斗力，也是参加各地图挑战赛的前提。\n1,000勋爵、3,000子爵、6,000伯爵、15,000侯爵、30,000公爵、100,000王。"
	var actions: Array[Dictionary] = [{"label":"捐献金币","action":"prime_donate"},{"label":"返回","action":"prime_minister"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("首相", words, actions)


func _open_prime_donate_dialogue() -> void:
	var words := "每捐献750,000金币可获得1点功勋。当前金币：%s。" % _format_number(GameState.gold)
	var actions: Array[Dictionary] = [{"label":"捐献750,000金币","action":"donate_gold:750000"},{"label":"返回","action":"prime_minister"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("首相", words, actions)


func _perform_prime_donation(amount_str: String) -> void:
	var amount := int(amount_str)
	var result := GameState.donate_gold_for_nobility(amount)
	if not bool(result.get("success", false)):
		_set_status("金币不足，捐献失败。")
	else:
		_set_status("捐献成功：扣除%s金币，获得%d点功勋。" % [_format_number(int(result.get("gold_cost", 0))), int(result.get("nobility_merit", 0))])
	_open_prime_donate_dialogue()


func _with_abyss_gate(actions: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inserted := false
	for entry in actions:
		if str(entry.get("action", "")) == "close" and not inserted:
			out.append({"label": "\u6df1\u6e0a\u7ec8\u5c40", "action": "enter_abyss"})
			out.append({"label": "\u7ec8\u5c40\u9762\u677f", "action": "abyss_board"})
			inserted = true
		out.append(entry)
	if not inserted:
		out.append({"label": "\u6df1\u6e0a\u7ec8\u5c40", "action": "enter_abyss"})
		out.append({"label": "\u7ec8\u5c40\u9762\u677f", "action": "abyss_board"})
	return out


func _enter_abyss() -> void:
	var gate: Dictionary = GameState.try_enter_abyss("ui:enter_abyss:%d" % GameState.current_day)
	if not bool(gate.get("success", false)):
		_set_status(str(gate.get("code", "ABYSS_PRECONDITION")))
		return
	_hide_all_panels()
	GameState.current_map_id = "abyss_gate"
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("abyss_gate")


func _open_abyss_board() -> void:
	_hide_all_panels()
	abyss_board_panel.show()
	abyss_board_panel.refresh()


func _talk_abyss_npc(action_id: String) -> void:
	var talked: Dictionary = GameState.talk_abyss_npc(action_id, "ui:talk:%s:%s" % [action_id, str(GameState.abyss_runtime().get("stage", ""))])
	var acts: Array[Dictionary] = []
	acts.append({"label": "\u7ec8\u5c40\u9762\u677f", "action": "abyss_board"})
	acts.append({"label": "close", "action": "close"})
	dialogue_panel.open_dialogue(action_id, str(talked.get("code", "OK")), acts)


func _claim_abyss_weekly() -> void:
	var result: Dictionary = GameState.claim_abyss_weekly("ui:abyss_weekly:%d" % GameState.current_day)
	_set_status(str(result.get("code", "OK")))


func _collect_abyss_world(action_id: String) -> void:
	var pid := action_id.trim_prefix("abyss:")
	if pid.begins_with("totem_"):
		var tot: Dictionary = GameState.run_abyss_totem(pid, "ui:totem:%s:%d" % [pid, GameState.current_day])
		_set_status(str(tot.get("code", "OK")))
		return
	var result: Dictionary = GameState.collect_abyss_probe(pid, "ui:abyss:%s:%d" % [pid, GameState.current_day])
	_set_status(str(result.get("code", "OK")))


func _open_king_dialogue() -> void:
	if not bool(GameState.story_flags.get("king_rescued", false)):
		_set_status("国王仍被魔族囚禁。")
		return
	var words := "经过冰宫进入雪域边境，就能到达魔族大军营地。目标是消灭魔军主帅，进而销毁“魔的能量”。"
	var actions: Array[Dictionary] = [
		{"label":"突击队","action":"king_intel:assault"},{"label":"守卫军","action":"king_intel:guard"},
		{"label":"神秘军","action":"king_intel:mystery"},{"label":"图腾兽","action":"king_intel:totem"},
		{"label":"魔的能量","action":"king_intel:energy"},{"label":"魔军主帅","action":"king_intel:commander"},
	]
	dialogue_panel.open_dialogue("国王", words, _with_abyss_gate(actions))


func _open_king_intel(intel_id: String) -> void:
	var intel := {
		"assault":"魔军突击队：700级。它的存在会使所有魔族军队的攻击力提高50%。",
		"guard":"魔军守卫军：800级。它的存在会使所有魔族军队的防御提高50%。",
		"mystery":"魔军神秘部队：900级。它的存在会使所有魔族军队的生命值提高50%。",
		"totem":"魔军图腾兽：1000级。它的存在会使所有魔族军队的战斗力提高50%。",
		"energy":"魔的能量是魔族大军的生命支柱。不消灭它，它每天都会复活所有魔族军队。",
		"commander":"魔军主帅：2000级。它守护着魔的能量，只有消灭它才能进入能量塔并取得胜利。",
	}
	var actions: Array[Dictionary] = [{"label":"返回","action":"king"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("国王", str(intel.get(intel_id, "没有这项情报。")), actions)


func _open_fuwa_messenger_dialogue() -> void:
	var found := int(GameState.fuwa_event.get("found_count", 0))
	var words := "我们的五福娃不知跑去哪玩了，我正在找它们。"
	if found > 0:
		words += "\n你已经找到了%d位，还差%d位。" % [found, GameState.FUWA_NAMES.size() - found]
	var _fuwa_actions: Array[Dictionary] = [
		{"label":"我帮你去找找吧", "action":"fuwa_start"},
		{"label":"离开", "action":"close"},
	]
	dialogue_panel.open_dialogue("2008奥运使者", words, _fuwa_actions)


func _start_fuwa_round() -> void:
	var result := GameState.start_fuwa_round()
	if not bool(result.get("success", false)):
		_set_status("现在不能开始寻找五福娃。")
		return
	_hide_all_panels()
	_apply_current_map()
	_set_status("你来到草原，一头凶悍的雷角风牙兽突然挡住了去路。")


func _claim_current_fuwa_reward() -> void:
	var result := GameState.claim_fuwa_reward()
	if not bool(result.get("success", false)):
		_set_status("背包已满，福娃的礼物还没有领取。" if str(result.get("reason", "")) == "inventory_full" else "必须先击败雷角风牙兽。")
		return
	var item_id := str(result.get("item_id", ""))
	var item_name := str(GameState.get_item_definition(item_id).get("name", item_id))
	var found_name := str(result.get("fuwa_name", "福娃"))
	_apply_current_map()
	var words := "你找到了五福娃中的%s。%s送%s给你。" % [found_name, found_name, item_name]
	if bool(result.get("all_found", false)):
		words += "\n五福娃已经全部找到，请在树心城向2008奥运使者交任务。"
	dialogue_panel.open_dialogue("五福娃", words, [{"label":"确定", "action":"close"}])
	_set_status("已找到%s（%d/5），获得%s。" % [found_name, int(result.get("found_count", 0)), item_name])


func _open_fuwa_completion_dialogue() -> void:
	if bool(GameState.fuwa_event.get("completion_claimed", false)):
		dialogue_panel.open_dialogue("2008奥运使者", "谢谢你帮我找到了五福娃。", [{"label":"离开", "action":"close"}])
		return
	var words := "谢谢你帮我找到五福娃，关于幻兽培养的技术资料已经送到幻兽研究所。\n还有100,000魔石作为报酬送给你。"
	var _fuwa_actions: Array[Dictionary] = [
		{"label":"谢谢", "action":"fuwa_complete"},
		{"label":"稍后再领", "action":"close"},
	]
	dialogue_panel.open_dialogue("2008奥运使者", words, _fuwa_actions)


func _claim_fuwa_completion() -> void:
	var result := GameState.claim_fuwa_completion()
	if not bool(result.get("success", false)):
		_set_status("五福娃任务尚未完成或奖励已经领取。")
		return
	_hide_all_panels()
	_apply_current_map()
	_set_status("完成五福娃任务：获得100,000魔石，研究所VIP提升至%d星；改版技术上限继续保持%d级。" % [int(result.get("vip_level", 0)), int(result.get("effective_technology_cap", 300))])



func _with_treeheart_gate(actions: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inserted := false
	for entry in actions:
		if str(entry.get("action", "")) == "close" and not inserted:
			out.append({"label": "树心郊区", "action": "enter_treeheart"})
			inserted = true
		out.append(entry)
	if not inserted:
		out.append({"label": "树心郊区", "action": "enter_treeheart"})
	return out




func _with_ice_gate(actions: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inserted := false
	for entry in actions:
		if str(entry.get("action", "")) == "close" and not inserted:
			out.append({"label": "\u51b0\u539f\u8bd5\u70bc", "action": "enter_ice"})
			out.append({"label": "\u5143\u7d20\u56fe\u9274", "action": "ice_codex"})
			inserted = true
		out.append(entry)
	if not inserted:
		out.append({"label": "\u51b0\u539f\u8bd5\u70bc", "action": "enter_ice"})
		out.append({"label": "\u5143\u7d20\u56fe\u9274", "action": "ice_codex"})
	return out


func _enter_ice() -> void:
	_hide_all_panels()
	GameState.current_map_id = "ice_frontier"
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("ice_frontier")


func _collect_ice_probe(action_id: String) -> void:
	var pid := action_id.trim_prefix("ice:")
	var result: Dictionary = GameState.collect_ice_probe(pid, "ui:ice:%s:%d" % [pid, GameState.current_day])
	_set_status(str(result.get("code", "OK")))


func _talk_ice_npc(action_id: String) -> void:
	var talked: Dictionary = GameState.talk_ice_npc(action_id, "ui:talk:%s:%s" % [action_id, str(GameState.ice_runtime().get("stage", ""))])
	var acts: Array[Dictionary] = []
	acts.append({"label": "\u5143\u7d20\u56fe\u9274", "action": "ice_codex"})
	acts.append({"label": "close", "action": "close"})
	dialogue_panel.open_dialogue(action_id, str(talked.get("code", "OK")), acts)


func _open_ice_codex() -> void:
	_hide_all_panels()
	ice_codex_panel.show()
	ice_codex_panel.refresh()


func _claim_ice_weekly() -> void:
	var result: Dictionary = GameState.claim_ice_weekly("ui:ice_weekly:%d" % GameState.current_day)
	_set_status(str(result.get("code", "OK")))

func _with_south_gate(actions: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inserted := false
	for entry in actions:
		if str(entry.get("action", "")) == "close" and not inserted:
			out.append({"label": "南部城邦", "action": "enter_south"})
			inserted = true
		out.append(entry)
	if not inserted:
		out.append({"label": "南部城邦", "action": "enter_south"})
	return out


func _enter_south() -> void:
	_hide_all_panels()
	GameState.current_map_id = "south_city_gate"
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("south_city_gate")


func _collect_border_scout(action_id: String) -> void:
	var sid := action_id.trim_prefix("scout:")
	var result: Dictionary = GameState.collect_border_scout(sid, "ui:scout:%s:%d" % [sid, GameState.current_day])
	_set_status(str(result.get("code", "OK")))


func _talk_border_npc(action_id: String) -> void:
	if action_id == "border_qm":
		var supply_actions: Array[Dictionary] = [
			{"label": "提交补给", "action": "border_supply"},
			{"label": "close", "action": "close"},
		]
		dialogue_panel.open_dialogue(action_id, "supply", supply_actions)
		return
	if action_id == "border_cmd":
		var result: Dictionary = GameState.talk_border_npc(action_id, "ui:talk:%s:%s" % [action_id, str(GameState.border_runtime().get("stage", ""))])
		var cmd_actions: Array[Dictionary] = [
			{"label": "指挥面板", "action": "border_board"},
			{"label": "close", "action": "close"},
		]
		dialogue_panel.open_dialogue(action_id, str(result.get("code", "OK")), cmd_actions)
		return
	var talked: Dictionary = GameState.talk_border_npc(action_id, "ui:talk:%s:%s" % [action_id, str(GameState.border_runtime().get("stage", ""))])
	_set_status(str(talked.get("code", "OK")))


func _submit_border_supply() -> void:
	var result: Dictionary = GameState.submit_border_supply("ui:supply:%d" % GameState.current_day)
	_set_status(str(result.get("code", "OK")))


func _open_border_board() -> void:
	_hide_all_panels()
	border_command_panel.show()
	border_command_panel.refresh()


func _claim_border_weekly() -> void:
	var result: Dictionary = GameState.claim_border_weekly("ui:border_weekly:%d" % GameState.current_day)
	_set_status(str(result.get("code", "OK")))

func _enter_treeheart() -> void:
	_hide_all_panels()
	GameState.current_map_id = "treeheart_outskirts"
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("treeheart_outskirts")


func _collect_chapter_evidence(action_id: String) -> void:
	var evid := action_id.trim_prefix("evidence:")
	var result: Dictionary = GameState.collect_chapter_evidence(evid, "ui:evidence:%s:%d" % [evid, GameState.current_day])
	_set_status(str(result.get("code", "OK")))


func _talk_chapter_npc(action_id: String) -> void:
	var result: Dictionary = GameState.talk_chapter_npc(action_id, "ui:talk:%s:%s" % [action_id, str(GameState.chapter_runtime().get("stage", ""))])
	if action_id == "chapter_su" and str(GameState.chapter_runtime().get("stage", "")) == "smuggler_choice" and str(GameState.chapter_runtime().get("branch", "")) == "":
		var branch_actions: Array[Dictionary] = [
			{"label": "report", "action": "chapter_report"},
			{"label": "track", "action": "chapter_track"},
			{"label": "close", "action": "close"},
		]
		dialogue_panel.open_dialogue(action_id, "branch", branch_actions)
		return
	_set_status(str(result.get("code", "OK")))


func _choose_chapter_branch(branch_id: String) -> void:
	var result: Dictionary = GameState.choose_smuggler_branch(branch_id, "ui:branch:%s" % branch_id)
	_set_status(str(result.get("code", "OK")))


func _claim_chapter_weekly() -> void:
	var result: Dictionary = GameState.claim_chapter_weekly("ui:weekly:%d" % GameState.current_day)
	_set_status(str(result.get("code", "OK")))

func _enter_dungeon() -> void:
	_hide_all_panels()
	GameState.current_map_id = "dungeon"
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("已经进入地下城一层。")

func _with_adventurer_board(actions: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inserted := false
	for entry in actions:
		if str(entry.get("action", "")) == "close" and not inserted:
			out.append({"label": "冒险者公告板", "action": "adventurer_board"})
			inserted = true
		out.append(entry)
	if not inserted:
		out.append({"label": "冒险者公告板", "action": "adventurer_board"})
	return out


func _open_adventurer_board() -> void:
	_hide_all_panels()
	adventurer_roster_panel.show()


func _open_adventurer_mail() -> void:
	_hide_all_panels()
	adventurer_mail_panel.show()


func _open_adventurer_trade() -> void:
	_hide_all_panels()
	adventurer_trade_panel.selected_id = adventurer_roster_panel.selected_id
	adventurer_trade_panel.show()


func _open_ranking_board() -> void:
	_hide_all_panels()
	ranking_panel.show()


func _open_arena_board() -> void:
	_hide_all_panels()
	arena_panel.show()


func _open_guild_market() -> void:
	_hide_all_panels()
	GameState.ensure_guild_catalog()
	guild_market_panel.show()


func _open_property_board() -> void:
	_hide_all_panels()
	property_territory_panel.show()


func _start_arena_match(monster_id: String) -> void:
	_hide_all_panels()
	if arena_proxy == null or monster_id.is_empty():
		return
	scene_battle_controller.engage(monster_id, arena_proxy)


func _open_daily_officer_dialogue() -> void:
	var weekday := ((GameState.current_day - 1) % 7) + 1
	var words := ""
	var actions: Array[Dictionary] = []
	match weekday:
		1, 2:
			words = "今天的任务是收集宝石。交付魔魂晶石或灵魂王，可以领取对应功勋。"
			actions = [{"label":"交付宝石","action":"daily_deliver"},{"label":"任务说明","action":"daily_help"},{"label":"离开","action":"close"}]
		3, 4:
			words = "今天的任务是训练幻兽。交付十星以上、未出征的攻防型幻兽可领取奖励。"
			actions = [{"label":"查看幻兽","action":"pets"},{"label":"任务说明","action":"daily_help"},{"label":"离开","action":"close"}]
		5:
			words = "周五突袭：从冰宫进入雪域边境，消灭暴雪勇士、骑士长和军官；每个目标都会直接增加军功。"
			actions = [{"label":"接受任务","action":"quest_accept:border_raid"},{"label":"任务说明","action":"daily_help"},{"label":"离开","action":"close"}]
		6:
			words = "周六王宫举行每周 PK 赛。报名后前往竞技场挑战各级擂主。"
			actions = [{"label":"前往皇宫","action":"travel:palace"},{"label":"任务说明","action":"daily_help"},{"label":"离开","action":"close"}]
		7:
			words = "周日地下城的魔族将领正在召开会议。国王悬赏勇士进入地下城，击败三层首领。"
			actions = [{"label":"接受任务","action":"quest_accept:dungeon_conquest"},{"label":"进入地下城","action":"enter_dungeon"},{"label":"任务说明","action":"daily_help"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("日常任务官", words, _with_season_gate(_with_treeheart_gate(_with_adventurer_board(actions))))



func _with_season_gate(actions: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inserted := false
	for raw: Variant in actions:
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		if not inserted and str(row.get("action", "")) == "close":
			out.append({"label": "\u8d5b\u5b63\u7c3f", "action": "season_board"})
			inserted = true
		out.append(row)
	if not inserted:
		out.append({"label": "\u8d5b\u5b63\u7c3f", "action": "season_board"})
	return out


func _open_season_board() -> void:
	_hide_all_panels()
	season_board_panel.show()
	season_board_panel.refresh()
	_set_status(GameState.season_board_lines()[0] if not GameState.season_board_lines().is_empty() else "SSN")

func _open_daily_help_dialogue() -> void:
	var words := "周一、周二：收集宝石。\n周三、周四：训练并上交高星幻兽。\n周五：突袭雪域边境。\n周六：参加王宫 PK 赛。\n周日：破坏地下城魔族将领会议。"
	var actions: Array[Dictionary] = [{"label":"知道了","action":"close"}]
	dialogue_panel.open_dialogue("日常任务官", words, actions)


func _open_daily_deliver_dialogue() -> void:
	var magic_soul := GameState.count_item("magic_soul_crystal")
	var soul_king := GameState.count_item("soul_king")
	var words := "交付材料可领取功勋。交付魔魂晶石获500功勋，交付灵魂王获2000功勋。\n当前：魔魂晶石%d，灵魂王%d。" % [magic_soul, soul_king]
	var actions: Array[Dictionary] = [{"label":"交付魔魂晶石","action":"daily_deliver:collect_magic_soul"},{"label":"交付灵魂王","action":"daily_deliver:collect_soul_king"},{"label":"返回","action":"daily_officer"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("日常任务官", words, actions)


func _perform_daily_deliver(task_id: String) -> void:
	var result := GameState.complete_daily_task(task_id)
	if not bool(result.get("success", false)):
		var reason := str(result.get("reason", ""))
		if reason == "already_completed":
			_set_status("今天的任务已经完成。")
		elif reason == "missing_item":
			_set_status("材料不足，无法交付。")
		else:
			_set_status("交付失败。")
	else:
		_set_status("交付成功：获得%d点功勋。" % int(result.get("nobility_merit", 0)))
	_open_daily_deliver_dialogue()


func _open_marshal_dialogue() -> void:
	var actions: Array[Dictionary] = [{"label":"领取军饷","action":"military_salary"},{"label":"战功查询","action":"military_status"},{"label":"国王消息","action":"marshal_info"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("元帅", "你好，我是国家元帅。战功、军衔和每周军饷都由我负责。", _with_south_gate(actions))


func _open_military_status_dialogue() -> void:
	var rank := GameState.get_military_rank()
	var next_rank := GameState.progression_service.next_tier("military", GameState.military_merit)
	var words := "%s，你当前的战功是：%s。" % [str(rank.get("name", "无军衔")), _format_number(GameState.military_merit)]
	if next_rank.is_empty():
		words += "\n你已达到最高军衔。"
	else:
		words += "\n还需要%s战功就能晋升为%s。" % [_format_number(int(next_rank.threshold) - GameState.military_merit), str(next_rank.get("name", ""))]
	words += "\n当前军衔战斗力：%d。" % int(rank.get("combat_power", 0))
	var actions: Array[Dictionary] = [{"label":"返回","action":"marshal"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("元帅", words, actions)


func _open_marshal_info_dialogue() -> void:
	var words := "人类的国王曾被魔族先锋部队俘虏，亚特大陆一度群龙无首。人类必须清除境内的魔族先锋、救出国王，并组织军队抵抗从雪狼冰原南下的魔族大军。"
	var actions: Array[Dictionary] = [{"label":"战功查询","action":"military_status"},{"label":"返回元帅","action":"marshal"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("元帅", words, actions)


func _open_pk_officer_dialogue() -> void:
	var words := "每星期六，国家竞技场都会举行例行勇士PK赛。比赛分为60级组、100级组和100级以上组，报名后会根据你的等级自动分组，每组只评出一名冠军。"
	var actions: Array[Dictionary] = [
		{"label":"\u67e5\u770b\u5956\u54c1", "action":"pk_prizes"},
		{"label":"\u6211\u6765\u62a5\u540d\u53c2\u52a0", "action":"pk_register"},
		{"label":"\u5192\u9669\u8005\u6392\u884c\u699c", "action":"ranking_board"},
		{"label":"\u5f02\u6b65\u64c2\u53f0", "action":"arena_board"},
		{"label":"\u5546\u4f1a\u4e8b\u52a1", "action":"guild_market"},
		{"label":"\u968f\u4fbf\u770b\u770b", "action":"close"},
	]
	dialogue_panel.open_dialogue("PK赛报名官", words, _with_challenge_gate(actions))



func _with_challenge_gate(actions: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inserted := false
	for raw: Variant in actions:
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		if not inserted and str(row.get("action", "")) == "close":
			out.append({"label": "\u6311\u6218\u7c3f", "action": "challenge_board"})
			out.append({"label": "\u6218\u58eb\u7cbe\u901a", "action": "challenge_mastery"})
			inserted = true
		out.append(row)
	if not inserted:
		out.append({"label": "\u6311\u6218\u7c3f", "action": "challenge_board"})
		out.append({"label": "\u6218\u58eb\u7cbe\u901a", "action": "challenge_mastery"})
	return out


func _open_challenge_board() -> void:
	_hide_all_panels()
	challenge_board_panel.show()
	challenge_board_panel.refresh()
	_set_status(GameState.challenge_board_lines()[0] if not GameState.challenge_board_lines().is_empty() else "CH")


func _open_challenge_mastery() -> void:
	var acts: Array[Dictionary] = [
		{"label": "\u98de\u5929\u8fde\u65a9", "action": "unlock_mastery:mastery_flying_slash"},
		{"label": "\u661f\u9b54\u5251", "action": "unlock_mastery:mastery_star_sword"},
		{"label": "\u6597\u5fd7", "action": "unlock_mastery:mastery_fighting_spirit"},
		{"label": "\u8fde\u51fb", "action": "unlock_mastery:mastery_combo"},
		{"label": "\u8fd4\u56de", "action": "pk_officer"},
		{"label": "\u79bb\u5f00", "action": "close"},
	]
	dialogue_panel.open_dialogue("\u6218\u58eb\u7cbe\u901a", "unlock warrior mastery", acts)



func _set_pet_support_ui() -> void:
	var pick := 0
	for pet: Dictionary in GameState.pets:
		if not bool(pet.get("deployed", false)):
			pick = int(pet.get("instance_id", 0))
			break
	var r: Dictionary = GameState.set_pet_support(pick, "ui:sup:%d" % GameState.current_day)
	_set_status(str(r.get("code", "PET_SUPPORT_OWNED")))

func _start_named_challenge(challenge_id: String, training: bool) -> void:
	var mode := "training" if training else "official"
	var result: Dictionary = GameState.try_start_challenge(challenge_id, mode, "ui:ch:%s:%s:%d" % [challenge_id, mode, GameState.current_day])
	if not bool(result.get("success", false)):
		_set_status(str(result.get("code", "CHALLENGE_LOCKED")))
		return
	_apply_current_map()
	_set_status("CH %s" % challenge_id)


func _open_pk_prizes_dialogue() -> void:
	var words := "奖品是：\n60级组：高级飞天连斩、40,000基础经验、27,000魔石。\n100级组：高级飞天连斩、150,000基础经验、56,000魔石、月光宝盒增强版。\n100级以上组：高级斗志抑扬、250,000基础经验、82,800魔石、月光宝盒增强版、电浆药水、999朵白玫瑰。\n报名比赛前请整理背包，确保有足够空间。"
	dialogue_panel.open_dialogue("PK赛报名官", words, [{"label":"返回", "action":"pk_officer"}, {"label":"离开", "action":"close"}] as Array[Dictionary])


func _register_pk_race() -> void:
	var result := GameState.register_pk_race()
	if not bool(result.get("success", false)):
		_set_status("比赛在星期六才进行，请到时再来报名。" if str(result.get("reason", "")) == "not_saturday" else "今天的比赛已经结束了，下次再来吧。")
		return
	_hide_all_panels()
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("报名成功，已进入%s。" % world.get_map(str(result.map_id)).name)


func _open_war_soul_explorer_dialogue() -> void:
	var words := "小伙子，看你东张西望的，是不是在寻找有关战魂的秘密？这里有条路通往一个地方，我在那里见过一个箱子，也许秘密就在里面。\n如果你愿意付给我50,000魔石作路费，我可以带你去。不过，还要看你有没有本事拿到箱子里的东西。"
	var actions: Array[Dictionary] = [
		{"label":"太好了，那正是我要找的地方", "action":"war_soul_enter"},
		{"label":"要那么多钱啊，我还是自己找算了", "action":"close"},
	]
	dialogue_panel.open_dialogue("探险家", words, actions)


func _enter_war_soul_maze() -> void:
	var result := GameState.enter_war_soul_maze()
	if not bool(result.get("success", false)):
		_set_status("你的魔石不足50,000。" if str(result.get("reason", "")) == "not_enough_stones" else "当前没有可追寻的战魂秘密。")
		return
	_hide_all_panels()
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("经过一天跋涉，探险家把你带到了战魂封印谜宫。点击箱子寻找秘密。")


func _reveal_war_soul_guardian() -> void:
	if not GameState.reveal_war_soul_guardian():
		_set_status("箱子已经没有反应。")
		return
	_rebuild_map_actors(GameState.current_map_id)
	_set_status("小子，你的装备也不错。想打探战魂的秘密，先打赢我再说！")


func _claim_military_salary() -> void:
	var result := GameState.claim_military_salary()
	if result.get("success", false):
		_set_status("%s军饷：获得 %s 魔石" % [result.rank_name, _format_number(int(result.magic_stones))])
	elif result.get("reason", "") == "not_sunday":
		_set_status("星期天才发军饷，到时候记得来领取。")
	elif result.get("reason", "") == "no_rank":
		_set_status("你还没有军衔，所以没有军饷。")
	else:
		_set_status("这个星期的军饷已经领取过了。")


func _accept_daily_quest(quest_id: String) -> void:
	var accepted := GameState.accept_quest(quest_id)
	_hide_all_panels()
	quest_panel.show()
	if accepted:
		_set_status("已接取：%s" % GameState.quest_service.quests[quest_id].name)
	else:
		_set_status("任务已经接取或完成，请查看当前进度。")


func _world_action_route(action_id: String) -> String:
	# 只读action路由分类器，供测试和审计使用。
	if action_id.begins_with("battle:"):
		return "battle"
	if action_id.begins_with("mine:"):
		return "mine"
	if action_id.begins_with("lottery:"):
		return "lottery"
	if action_id.begins_with("territory:"):
		return "territory"
	if action_id.begins_with("war_soul_"):
		return "war_soul"
	if action_id.begins_with("evidence:"):
		return "chapter_evidence"
	if action_id.begins_with("scout:"):
		return "border_scout"
	if action_id.begins_with("ice:") and not action_id.begins_with("ice_"):
		return "ice_investigate"
	if action_id.begins_with("abyss:") and not action_id.begins_with("abyss_"):
		return "abyss_investigate"
	if action_id.begins_with("challenge:"):
		return "challenge_run"
	if action_id.begins_with("start_challenge:") or action_id.begins_with("train_challenge:"):
		return "challenge_run"
	if action_id.begins_with("ptrial:") or action_id.begins_with("start_ptrial:"):
		return "pet_trial_run"
	if action_id.begins_with("ssn:"):
		return "season_cycle"
	if action_id.begins_with("travel:"):
		return "travel"
	if action_id.begins_with("synthesize:"):
		return "synthesize"
	if action_id.begins_with("king_intel:"):
		return "npc_dialogue"
	if action_id.begins_with("quest_accept:"):
		return "quest"
	if action_id.begins_with("donate_gold:"):
		return "npc_action"
	if action_id.begins_with("give_roses:"):
		return "npc_action"
	if action_id.begins_with("daily_deliver:"):
		return "npc_action"
	var known_npc: Array = ["grocery","stone_shop","collector","warehouse","daily_officer","stone_synthesizer","forger","pet_master","experience_mentor","research","marshal","prime_minister","princess","maid","maid_combat_stone","pk_officer","lottery_officer","king","daily_officer","fuwa_messenger","fuwa_reward","fuwa_completion","war_soul_explorer","war_soul_chest","enter_dungeon","enter_lottery_room","military_salary","military_status","marshal_info","prime_donate","prime_merit","prime_king","prime_nobility","princess_gift","princess_chat","princess_friend_gift","princess_sunday_gift","research_info","research_olympic_info","research_production_task","research_npc","daily_help","daily_deliver","pk_prizes","pk_register","adventurer_board","ranking_board","arena_board","guild_market","property_board","enter_treeheart","enter_south","border_cmd","border_qm","border_scout_npc","border_tang","border_liang","border_weekly","border_board","border_supply","enter_ice","ice_codex","ice_shen","ice_bai","ice_weekly","enter_abyss","abyss_board","abyss_he","abyss_jiang","abyss_gu","abyss_weekly","challenge_board","challenge_mastery","pet_endgame_board","pet_endgame_menu","set_support","season_board","chapter_lin","chapter_qin","chapter_su","chapter_ye","chapter_weekly","chapter_report","chapter_track"]
	if action_id in known_npc:
		return "npc_dialogue"
	return "UNSUPPORTED"


func _handle_dialogue_action(action: String) -> void:
	match action:
		"gold_buy": gold_shop.open_mode("buy")
		"gold_sell": gold_shop.open_mode("sell")
		"stone_buy": stone_shop.open_mode("buy")
		"stone_sell": stone_shop.open_mode("sell")
		"warehouse": _toggle_warehouse()
		"pets": _toggle_pets()
		"research": _toggle_research()
		"research_npc": _open_research_dialogue()
		"research_info": _open_research_info()
		"research_olympic_info": _open_research_olympic_info()
		"research_production_task": _perform_research_production_task()
		"exchange_equipment_exp": _exchange_equipment_for_exp_balls()
		"enhancement": _toggle_enhancement()
		"progression": _toggle_progression()
		"quests": _toggle_quests()
		"daily_help": _open_daily_help_dialogue()
		"fuwa_start": _start_fuwa_round()
		"fuwa_complete": _claim_fuwa_completion()
		"enter_dungeon": _enter_dungeon()
		"marshal_info": _open_marshal_info_dialogue()
		"military_salary": _claim_military_salary()
		"princess": _open_princess_dialogue()
		"princess_chat": _chat_with_princess()
		"princess_friend_gift": _claim_princess_friend_gift()
		"princess_sunday_gift": _claim_princess_sunday_gift()
		"maid": _open_maid_dialogue()
		"maid_buy_year_pig": _buy_maid_year_pig()
		"maid_buy_combat_stone": _buy_maid_combat_stone()
		"enter_lottery_room": _enter_lottery_room()
		"pk_officer": _open_pk_officer_dialogue()
		"pk_prizes": _open_pk_prizes_dialogue()
		"pk_register": _register_pk_race()
		"ranking_board": _open_ranking_board()
		"arena_board": _open_arena_board()
		"guild_market": _open_guild_market()
		"property_board": _open_property_board()
		"enter_treeheart": _enter_treeheart()
		"enter_south": _enter_south()
		"border_cmd": _talk_border_npc("border_cmd")
		"border_qm": _talk_border_npc("border_qm")
		"border_scout_npc": _talk_border_npc("border_scout_npc")
		"border_tang": _talk_border_npc("border_tang")
		"border_liang": _talk_border_npc("border_liang")
		"border_weekly": _claim_border_weekly()
		"border_board": _open_border_board()
		"border_supply": _submit_border_supply()
		"enter_ice": _enter_ice()
		"ice_codex": _open_ice_codex()
		"ice_shen": _talk_ice_npc("ice_shen")
		"ice_bai": _talk_ice_npc("ice_bai")
		"ice_weekly": _claim_ice_weekly()
		"enter_abyss": _enter_abyss()
		"abyss_board": _open_abyss_board()
		"challenge_board": _open_challenge_board()
		"challenge_mastery": _open_challenge_mastery()
		"pet_endgame_board": _open_pet_endgame_board()
		"pet_endgame_menu": _open_pet_endgame_menu()
		"set_support": _set_pet_support_ui()
		"season_board": _open_season_board()
		"abyss_he": _talk_abyss_npc("abyss_he")
		"abyss_jiang": _talk_abyss_npc("abyss_jiang")
		"abyss_gu": _talk_abyss_npc("abyss_gu")
		"abyss_weekly": _claim_abyss_weekly()
		"chapter_lin": _talk_chapter_npc("chapter_lin")
		"chapter_qin": _talk_chapter_npc("chapter_qin")
		"chapter_su": _talk_chapter_npc("chapter_su")
		"chapter_ye": _talk_chapter_npc("chapter_ye")
		"chapter_weekly": _claim_chapter_weekly()
		"chapter_report": _choose_chapter_branch("report")
		"chapter_track": _choose_chapter_branch("track")
		"war_soul_enter": _enter_war_soul_maze()
		"prime_minister": _open_prime_minister_dialogue()
		"prime_donate": _open_prime_donate_dialogue()
		"marshal": _open_marshal_dialogue()
		"military_status": _open_military_status_dialogue()
		"princess_gift": _open_princess_gift_dialogue()
		"daily_officer": _open_daily_officer_dialogue()
		"adventurer_board": _open_adventurer_board()
		"daily_deliver": _open_daily_deliver_dialogue()
		"prime_merit": _open_prime_minister_merit()
		"prime_king": _open_prime_minister_king_news()
		"prime_nobility": _open_prime_minister_nobility()
		"king": _open_king_dialogue()
		_:
			if action.begins_with("synthesize:"):
				_synthesize_stone(action.trim_prefix("synthesize:"))
			elif action.begins_with("donate_gold:"):
				_perform_prime_donation(action.trim_prefix("donate_gold:"))
			elif action.begins_with("give_roses:"):
				_give_princess_roses(action.trim_prefix("give_roses:"))
			elif action.begins_with("daily_deliver:"):
				_perform_daily_deliver(action.trim_prefix("daily_deliver:"))
			elif action.begins_with("king_intel:"):
				_open_king_intel(action.trim_prefix("king_intel:"))
			elif action.begins_with("territory_reward:"):
				_open_territory_reward_dialogue(action.trim_prefix("territory_reward:"))
			elif action.begins_with("territory_claim:"):
				_claim_territory_reward(action.trim_prefix("territory_claim:"))
			elif action.begins_with("territory_challenge:"):
				_start_territory_challenge(action.trim_prefix("territory_challenge:"))
			elif action.begins_with("territory:"):
				_open_territory_dialogue(action.trim_prefix("territory:"))
			elif action.begins_with("quest_accept:"):
				_accept_daily_quest(action.trim_prefix("quest_accept:"))
			elif action.begins_with("travel:"):
				_travel_to(action.trim_prefix("travel:"))
			elif action.begins_with("battle:"):
				_start_battle(action.trim_prefix("battle:"))
			elif action.begins_with("start_challenge:"):
				_start_named_challenge(action.trim_prefix("start_challenge:"), false)
			elif action.begins_with("train_challenge:"):
				_start_named_challenge(action.trim_prefix("train_challenge:"), true)
			elif action.begins_with("start_ptrial:"):
				_start_named_pet_trial(action.trim_prefix("start_ptrial:"))
			elif action.begins_with("claim_col:"):
				var cr: Dictionary = GameState.claim_collection_reward(action.trim_prefix("claim_col:"), "ui:col:%d" % GameState.current_day)
				_set_status(str(cr.get("code", "PET_COLLECTION_UNKNOWN")))
			elif action.begins_with("claim_rc:"):
				var rr: Dictionary = GameState.claim_research_contract(action.trim_prefix("claim_rc:"), "ui:rc:%d" % GameState.current_day)
				_set_status(str(rr.get("code", "RESEARCH_CONTRACT_COST")))
			elif action.begins_with("unlock_mastery:"):
				var mid := action.trim_prefix("unlock_mastery:")
				var ur: Dictionary = GameState.unlock_warrior_mastery(mid, "ui:ms:%s:%d" % [mid, GameState.current_day])
				_set_status(str(ur.get("code", "MASTERY_CAP")))


func _apply_current_map() -> void:
	var map_data: Dictionary = world.get_map(GameState.current_map_id)
	if map_data.is_empty():
		GameState.current_map_id = "cassano_city"
		map_data = world.get_map(GameState.current_map_id)
	background.texture = load(str(map_data.get("background", "")))
	_rebuild_map_actors(GameState.current_map_id)
	var spawn: Array = map_data.get("spawn", [310, 270])
	player.position = Vector2(float(spawn[0]), float(spawn[1]))
	location_label.text = str(map_data.get("name", "未知"))
	# map_change 事件生命周期（整改06）：真实地图切换统一处理 on_map_change 时间轴——
	# scene_battle_controller.handle_map_change() 取消其活动资源（kill/stop + 解除跟踪），
	# player_motion（帧驱动）按策略重置移动动画状态（回到 idle 首帧）。
	if scene_battle_controller != null:
		scene_battle_controller.handle_map_change()
		if scene_battle_controller.timeline_cancelled_by("player_motion", scene_battle_controller.EVENT_MAP_CHANGE):
			player_animation_elapsed = 0.0
			player_animation_index = 0
			player_animation_clip = "idle"
			player.texture = player_idle_frames[0]
	_refresh_map_navigation(map_data)
	GameState.note_map_visit()


func _rebuild_map_actors(map_id: String) -> void:
	_hide_monster_tooltip()
	if scene_battle_controller != null:
		scene_battle_controller.cancel_battle()
	interactive_actors.clear()
	actor_labels.clear()
	for child in actor_layer.get_children():
		actor_layer.remove_child(child)
		child.queue_free()
	match map_id:
		"cassano_city":
			_add_actor("杂货商", "res://assets/extracted/images/image_1156.png", Vector2(166.8, 120.3), Vector2(52, 114), "grocery")
			_add_actor("收藏商店", "res://assets/extracted/images/image_1134.png", Vector2(290, 123.3), Vector2(54, 111), "stone_shop")
			_add_actor("收藏家", "res://assets/extracted/images/image_1138.png", Vector2(446.15, 124.3), Vector2(32, 116), "collector")
			_add_actor("仓库管理员", "res://assets/extracted/images/image_1130.png", Vector2(533.6, 120.85), Vector2(51, 111), "warehouse")
			_add_actor("日常任务官", "res://assets/extracted/images/image_1076.png", Vector2(620.45, 119.3), Vector2(58, 111), "daily_officer", Color("55ff55"))
			_add_actor("宝石合成师", "res://assets/extracted/images/image_1151.png", Vector2(130.5, 373.55), Vector2(39, 108), "stone_synthesizer")
			_add_actor("装备打造师", "res://assets/extracted/images/image_1142.png", Vector2(207.5, 377.95), Vector2(52, 115), "forger")
			_add_actor("幻兽幻化师", "res://assets/extracted/images/image_1147.png", Vector2(410.45, 385.95), Vector2(52, 102), "pet_master")
			_add_actor("经验导师", "res://assets/extracted/images/image_1126.png", Vector2(517.65, 377.9), Vector2(55, 108), "experience_mentor")
			_add_actor("幻兽研究所", "res://assets/extracted/images/image_1171.png", Vector2(470, 203), Vector2(42, 130), "research")
			_add_actor("地图占领报名官", "res://assets/extracted/images/image_1076.png", Vector2(33.95, 365.55), Vector2(58, 111), "territory:cassano_city", Color("55ff55"))
		"palace":
			_add_decoration("decoration:palace:image_1197", "res://assets/extracted/images/image_1197.png", Vector2(78, 300), Vector2(177, 119))
			_add_decoration("decoration:palace:image_1198", "res://assets/extracted/images/image_1198.png", Vector2(448, 290), Vector2(184, 146))
			_add_actor("元帅", "res://assets/extracted/images/image_1177.png", Vector2(105, 128), Vector2(67, 145), "marshal", Color("55ff55"))
			_add_actor("首相", "res://assets/extracted/images/image_1142.png", Vector2(210, 155), Vector2(52, 115), "prime_minister", Color("55ff55"))
			if bool(GameState.story_flags.get("king_rescued", false)):
				_add_actor("国王", "res://assets/extracted/images/image_1191.png", Vector2(300, 120), Vector2(79, 150), "king", Color("ffd34d"))
			_add_actor("公主", "res://assets/extracted/images/image_1201.png", Vector2(430, 135), Vector2(79, 136), "princess", Color("ff8dd8"))
			_add_actor("公主侍女", "res://assets/extracted/images/image_1134.png", Vector2(520, 160), Vector2(54, 111), "maid", Color("ffb0e6"))
			_add_actor("PK赛报名官", "res://assets/extracted/images/image_1076.png", Vector2(620, 300), Vector2(58, 111), "pk_officer", Color("55ff55"))
			_add_actor("抽奖官", "res://assets/extracted/images/image_1147.png", Vector2(152, 398.4), Vector2(52, 102), "lottery_officer", Color("55ff55"))
		"palace_garden":
			_add_decoration("decoration:palace_garden:image_1198", "res://assets/extracted/images/image_1198.png", Vector2(0, 0), Vector2(184, 146))
			_add_actor("丫环2", "res://assets/extracted/images/image_1134.png", Vector2(251.5, 220.95), Vector2(58, 104), "maid", Color("55ff55"))
			_add_actor("公主", "res://assets/extracted/images/image_1201.png", Vector2(310.3, 169.45), Vector2(79, 136), "princess", Color("55ff55"))
			_add_actor("丫环1", "res://assets/extracted/images/image_1134.png", Vector2(447.55, 219.95), Vector2(58, 104), "maid_combat_stone", Color("55ff55"))
		"lottery_room":
			_add_decoration("decoration:lottery_room:image_1198", "res://assets/extracted/images/image_1198.png", Vector2(0, 0), Vector2(184, 146))
			_add_actor("", "res://assets/extracted/images/image_1213.png", Vector2(39.35, 118.9), Vector2(100, 100), "lottery:绿宝箱1")
			_add_actor("", "res://assets/extracted/images/image_1213.png", Vector2(284.3, 118.9), Vector2(100, 100), "lottery:红宝箱1")
			_add_actor("", "res://assets/extracted/images/image_1213.png", Vector2(529.3, 118.9), Vector2(100, 100), "lottery:蓝宝箱1")
			_add_actor("", "res://assets/extracted/images/image_1213.png", Vector2(46.35, 372.85), Vector2(100, 100), "lottery:绿宝箱2")
			_add_actor("", "res://assets/extracted/images/image_1213.png", Vector2(291.3, 372.85), Vector2(100, 100), "lottery:红宝箱2")
			_add_actor("", "res://assets/extracted/images/image_1213.png", Vector2(536.3, 372.85), Vector2(100, 100), "lottery:蓝宝箱2")
			_add_actor("", "res://assets/extracted/images/image_1213.png", Vector2(146.35, 248.95), Vector2(100, 100), "lottery:灰宝箱")
			_add_actor("", "res://assets/extracted/images/image_1213.png", Vector2(438, 253.9), Vector2(100, 100), "lottery:黄宝箱")
		"green_field":
			_add_actor("雷角风牙兽", "res://assets/extracted/images/image_0051.png", Vector2(483.55, 243), Vector2(92, 100), "battle:fuwa_beast", Color("ffcc35"))
		"grass_reward":
			_add_actor(GameState.current_fuwa_name(), GameState.current_fuwa_image_path(), Vector2(547.5, 244.05), Vector2(80, 92), "fuwa_reward", Color("55ff55"))
		"south_city_gate":
			_add_actor("cmd", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "border_cmd", Color("55ff55"))
		"south_city_square":
			_add_actor("qm", "res://assets/extracted/images/image_1076.png", Vector2(480, 260), Vector2(58, 111), "border_qm", Color("55ff55"))
			_add_actor("banner", "res://assets/extracted/images/image_1213.png", Vector2(300, 240), Vector2(48, 48), "scout:scout_banner")
		"border_watchpost":
			_add_actor("scout", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "border_scout_npc", Color("55ff55"))
			_add_actor("tang", "res://assets/extracted/images/image_1076.png", Vector2(500, 260), Vector2(58, 111), "border_tang", Color("55ff55"))
			_add_actor("tracks", "res://assets/extracted/images/image_1213.png", Vector2(300, 240), Vector2(48, 48), "scout:scout_tracks")
		"border_supply_route":
			if GameState.border_unit_visible("border_skirmish_a"):
				_add_actor("skirmish", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:border_skirmish_a", Color("ffcc35"))
		"border_ruins":
			_add_actor("liang", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "border_liang", Color("55ff55"))
			if GameState.border_unit_visible("border_skirmish_b"):
				_add_actor("skirmish", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:border_skirmish_b", Color("ffcc35"))
		"border_command_tent":
			_add_actor("weekly", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "border_weekly", Color("55ff55"))
			if GameState.border_unit_visible("border_command_boss"):
				_add_actor("boss", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:border_command_boss", Color("ffcc35"))
		"ice_frontier":
			_add_actor("shen", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "ice_shen", Color("55ff55"))
			_add_actor("shard", "res://assets/extracted/images/image_1213.png", Vector2(300, 240), Vector2(48, 48), "ice:signal_shard")
		"frozen_pass":
			_add_actor("bai", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "ice_bai", Color("55ff55"))
			_add_actor("charm", "res://assets/extracted/images/image_1213.png", Vector2(300, 240), Vector2(48, 48), "ice:rescue_charm")
		"crystal_cavern":
			_add_actor("key", "res://assets/extracted/images/image_1213.png", Vector2(300, 240), Vector2(48, 48), "ice:crystal_key")
		"elemental_laboratory":
			_add_actor("weekly", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "ice_weekly", Color("55ff55"))
			if GameState.ice_unit_visible("ice_lab_boss"):
				_add_actor("boss", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:ice_lab_boss", Color("ffcc35"))
			if GameState.ice_unit_visible("ice_weekly_trial"):
				_add_actor("trial", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:ice_weekly_trial", Color("ffcc35"))
		"aurora_sanctum":
			if GameState.ice_unit_visible("ice_aurora_boss"):
				_add_actor("boss", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:ice_aurora_boss", Color("ffcc35"))
		"abyss_gate":
			_add_actor("he", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "abyss_he", Color("55ff55"))
			_add_actor("seal", "res://assets/extracted/images/image_1213.png", Vector2(300, 240), Vector2(48, 48), "abyss:gate_seal")
		"abyss_outer_ring":
			_add_actor("jiang", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "abyss_jiang", Color("55ff55"))
		"abyss_echo_halls":
			if GameState.abyss_unit_visible("abyss_echo_assault"):
				_add_actor("ea", "res://assets/extracted/images/image_1072.png", Vector2(180, 220), Vector2(101, 132), "battle:abyss_echo_assault", Color("ffcc35"))
			if GameState.abyss_unit_visible("abyss_echo_guard"):
				_add_actor("eg", "res://assets/extracted/images/image_1072.png", Vector2(330, 220), Vector2(101, 132), "battle:abyss_echo_guard", Color("ffcc35"))
			if GameState.abyss_unit_visible("abyss_echo_mystery"):
				_add_actor("em", "res://assets/extracted/images/image_1072.png", Vector2(480, 220), Vector2(101, 132), "battle:abyss_echo_mystery", Color("ffcc35"))
			if GameState.abyss_unit_visible("abyss_echo_totem"):
				_add_actor("et", "res://assets/extracted/images/image_1072.png", Vector2(240, 340), Vector2(101, 132), "battle:abyss_echo_totem", Color("ffcc35"))
			if GameState.abyss_unit_visible("abyss_echo_commander"):
				_add_actor("ec", "res://assets/extracted/images/image_1072.png", Vector2(420, 340), Vector2(101, 132), "battle:abyss_echo_commander", Color("ffcc35"))
		"totem_sanctum":
			_add_actor("gu", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "abyss_gu", Color("55ff55"))
			_add_actor("tg", "res://assets/extracted/images/image_1213.png", Vector2(220, 240), Vector2(48, 48), "abyss:totem_guild")
			_add_actor("tt", "res://assets/extracted/images/image_1213.png", Vector2(320, 240), Vector2(48, 48), "abyss:totem_territory")
			_add_actor("tb", "res://assets/extracted/images/image_1213.png", Vector2(420, 240), Vector2(48, 48), "abyss:totem_bond")
		"abyss_heart":
			_add_actor("weekly", "res://assets/extracted/images/image_1076.png", Vector2(80, 260), Vector2(58, 111), "abyss_weekly", Color("55ff55"))
			_add_actor("hs", "res://assets/extracted/images/image_1213.png", Vector2(300, 240), Vector2(48, 48), "abyss:heart_seal")
			if GameState.abyss_unit_visible("abyss_heart_boss"):
				_add_actor("boss", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:abyss_heart_boss", Color("ffcc35"))
			if GameState.abyss_unit_visible("abyss_weekly_trial"):
				_add_actor("trial", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:abyss_weekly_trial", Color("ffcc35"))
		"treeheart_outskirts":
			_add_actor("林夏", "res://assets/extracted/images/image_1076.png", Vector2(80, 280), Vector2(58, 111), "chapter_lin", Color("55ff55"))
			_add_actor("bark", "res://assets/extracted/images/image_1213.png", Vector2(250, 200), Vector2(48, 48), "evidence:root_bark")
			_add_actor("leaf", "res://assets/extracted/images/image_1213.png", Vector2(400, 320), Vector2(48, 48), "evidence:sick_leaf")
		"treeheart_core":
			_add_actor("秦河", "res://assets/extracted/images/image_1076.png", Vector2(120, 260), Vector2(58, 111), "chapter_qin", Color("55ff55"))
			_add_actor("resin", "res://assets/extracted/images/image_1213.png", Vector2(480, 280), Vector2(48, 48), "evidence:core_resin")
		"harbor_quay":
			_add_actor("苏颜", "res://assets/extracted/images/image_1076.png", Vector2(500, 260), Vector2(58, 111), "chapter_su", Color("55ff55"))
			_add_actor("ledger", "res://assets/extracted/images/image_1213.png", Vector2(300, 250), Vector2(48, 48), "evidence:smuggler_ledger")
		"harbor_market":
			_add_actor("苏颜", "res://assets/extracted/images/image_1076.png", Vector2(200, 280), Vector2(58, 111), "chapter_weekly", Color("55ff55"))
		"sea_cave":
			_add_actor("叶飞", "res://assets/extracted/images/image_1076.png", Vector2(80, 280), Vector2(58, 111), "chapter_ye", Color("55ff55"))
			if GameState.chapter_boss_visible("chapter_sea_boss"):
				_add_actor("boss", "res://assets/extracted/images/image_1072.png", Vector2(480, 280), Vector2(101, 132), "battle:chapter_sea_boss", Color("ffcc35"))
		"tide_shrine":
			if GameState.chapter_boss_visible("chapter_tide_boss"):
				_add_actor("boss", "res://assets/extracted/images/image_1072.png", Vector2(450, 250), Vector2(101, 132), "battle:chapter_tide_boss", Color("ffcc35"))
		"treeheart_city":
			_add_decoration("decoration:treeheart_city:image_1101", "res://assets/extracted/images/image_1101.png", Vector2(434.45, 107.2), Vector2(72, 82))
			_add_decoration("decoration:treeheart_city:image_1104", "res://assets/extracted/images/image_1104.png", Vector2(517.7, 150.2), Vector2(72, 82))
			_add_decoration("decoration:treeheart_city:image_1106", "res://assets/extracted/images/image_1106.png", Vector2(544.7, 260), Vector2(72, 82))
			_add_decoration("decoration:treeheart_city:image_1108", "res://assets/extracted/images/image_1108.png", Vector2(501.7, 357.85), Vector2(72, 82))
			_add_decoration("decoration:treeheart_city:image_1110", "res://assets/extracted/images/image_1110.png", Vector2(403.7, 390.85), Vector2(72, 82))
			_add_actor("2008奥运使者", "res://assets/extracted/images/image_1086.png", Vector2(463.3, 217), Vector2(70, 115), "fuwa_completion", Color("55ff55"))
		"thunder_continent":
			_add_actor("巨杰士", "res://assets/extracted/images/image_0049.png", Vector2(374.1, 146.3), Vector2(152, 115), "battle:thunder_giant@1", Color("f3dc77"))
			_add_actor("龙怪", "res://assets/extracted/images/image_0051.png", Vector2(539.7, 96.55), Vector2(152, 115), "battle:thunder_dragon@1", Color("f3dc77"))
			_add_actor("10级BOSS", "res://assets/extracted/images/image_1072.png", Vector2(543.1, 386.55), Vector2(101, 132), "battle:thunder_boss_10", Color("ffcc35"))
			_add_actor("巨杰士", "res://assets/extracted/images/image_0049.png", Vector2(398.45, 365.25), Vector2(152, 115), "battle:thunder_giant@2", Color("f3dc77"))
			_add_actor("地图占领报名官", "res://assets/extracted/images/image_1076.png", Vector2(100, 285), Vector2(58, 111), "territory:thunder_continent", Color("55ff55"))
		"thunder_mine":
			_add_actor("挖矿", "res://assets/extracted/images/image_0038.jpg", Vector2(611, 273), Vector2(48, 48), "mine:0", Color("ffe45c"))
			_add_actor("挖矿", "res://assets/extracted/images/image_0038.jpg", Vector2(427, 162), Vector2(48, 48), "mine:1", Color("ffe45c"))
			_add_actor("挖矿", "res://assets/extracted/images/image_0038.jpg", Vector2(192, 100), Vector2(48, 48), "mine:2", Color("ffe45c"))
			_add_actor("挖矿", "res://assets/extracted/images/image_0038.jpg", Vector2(489, 430), Vector2(48, 48), "mine:3", Color("ffe45c"))
		"desert":
			_add_actor("冰妖剑士", "res://assets/extracted/images/image_0053.png", Vector2(546, 90.55), Vector2(152, 115), "battle:desert_ice_swordsman@1", Color("f3dc77"))
			_add_actor("杰克灯笼", "res://assets/extracted/images/image_0055.png", Vector2(543.5, 240.55), Vector2(152, 115), "battle:desert_jack_lantern@1", Color("f3dc77"))
			_add_actor("提风", "res://assets/extracted/images/image_0057.png", Vector2(386.55, 385.55), Vector2(152, 115), "battle:desert_typhon@1", Color("f3dc77"))
			_add_actor("20级BOSS", "res://assets/extracted/images/image_1072.png", Vector2(539.7, 385.55), Vector2(101, 132), "battle:desert_boss_20", Color("ffcc35"))
			_add_actor("冰妖剑士", "res://assets/extracted/images/image_0053.png", Vector2(391.5, 89.55), Vector2(152, 115), "battle:desert_ice_swordsman@2", Color("f3dc77"))
			_add_actor("杰克灯笼", "res://assets/extracted/images/image_0055.png", Vector2(387.7, 239.55), Vector2(152, 115), "battle:desert_jack_lantern@2", Color("f3dc77"))
			_add_actor("地图占领报名官", "res://assets/extracted/images/image_1076.png", Vector2(100, 285), Vector2(58, 111), "territory:desert", Color("55ff55"))
			if bool(GameState.story_flags.get("war_soul_quest_available", false)) and not bool(GameState.story_flags.get("war_soul_secret_unlocked", false)):
				_add_actor("探险家", "res://assets/extracted/images/image_1231.png", Vector2(18, 325.1), Vector2(70, 130), "war_soul_explorer", Color("55ff55"))
		"war_soul_seal_maze":
			if GameState.war_soul_maze_active:
				_add_actor("封印之箱", "res://assets/extracted/images/image_1213.png", Vector2(649.95, 217.95), Vector2(100, 100), "war_soul_chest", Color("ffcc35"))
				if GameState.war_soul_guardian_revealed:
					_add_actor("无名氏", "res://assets/extracted/images/image_0101.png", Vector2(505.2, 175.95), Vector2(91, 167), "battle:nameless_war_soul_keeper", Color("ff5035"))
		"dream_swamp":
			_add_actor("望齿魔人", "res://assets/extracted/images/image_0059.png", Vector2(444.2, 198), Vector2(152, 115), "battle:swamp_fanged_demon@1", Color("f3dc77"))
			_add_actor("30级BOSS", "res://assets/extracted/images/image_1072.png", Vector2(191, 371), Vector2(101, 132), "battle:swamp_boss_30", Color("ffcc35"))
			_add_actor("蜘蛛", "res://assets/extracted/images/image_0063.png", Vector2(27, 371), Vector2(152, 115), "battle:spider", Color("ffcc35"))
			_add_actor("角蜥", "res://assets/extracted/images/image_0061.png", Vector2(355.2, 371), Vector2(152, 115), "battle:swamp_horned_lizard@1", Color("f3dc77"))
			_add_actor("望齿魔人", "res://assets/extracted/images/image_0059.png", Vector2(446.3, 80), Vector2(152, 115), "battle:swamp_fanged_demon@2", Color("f3dc77"))
			_add_actor("角蜥", "res://assets/extracted/images/image_0061.png", Vector2(515.3, 387), Vector2(152, 115), "battle:swamp_horned_lizard@2", Color("f3dc77"))
			_add_actor("地图占领报名官", "res://assets/extracted/images/image_1076.png", Vector2(100, 285), Vector2(58, 111), "territory:dream_swamp", Color("55ff55"))
		"ice_palace":
			_add_actor("塔亚龙", "res://assets/extracted/images/image_0065.png", Vector2(328.85, 366), Vector2(152, 115), "battle:ice_taya_dragon@1", Color("f3dc77"))
			_add_actor("50级BOSS", "res://assets/extracted/images/image_1072.png", Vector2(543.5, 96), Vector2(101, 132), "battle:ice_boss_50", Color("ffcc35"))
			_add_actor("死亡骑士", "res://assets/extracted/images/image_0067.png", Vector2(467.2, 246.4), Vector2(152, 115), "battle:ice_death_knight@1", Color("f3dc77"))
			_add_actor("塔亚龙", "res://assets/extracted/images/image_0065.png", Vector2(382.3, 124.3), Vector2(152, 115), "battle:ice_taya_dragon@2", Color("f3dc77"))
			_add_actor("死亡骑士", "res://assets/extracted/images/image_0067.png", Vector2(539.7, 378.9), Vector2(152, 115), "battle:ice_death_knight@2", Color("f3dc77"))
			_add_actor("地图占领报名官", "res://assets/extracted/images/image_1076.png", Vector2(100, 285), Vector2(58, 111), "territory:ice_palace", Color("55ff55"))
		"avit_island":
			_add_actor("鱼妖", "res://assets/extracted/images/image_0069.png", Vector2(305, 339.55), Vector2(152, 115), "battle:avit_fish_demon@1", Color("f3dc77"))
			_add_actor("70级BOSS", "res://assets/extracted/images/image_1072.png", Vector2(543.3, 382.85), Vector2(101, 132), "battle:avit_boss_70", Color("ffcc35"))
			_add_actor("恐兽", "res://assets/extracted/images/image_0071.png", Vector2(203.9, 87), Vector2(152, 115), "battle:avit_terror_beast@1", Color("f3dc77"))
			_add_actor("巨斧怪", "res://assets/extracted/images/image_0073.png", Vector2(361, 115.15), Vector2(152, 115), "battle:avit_giant_axe@1", Color("f3dc77"))
			_add_actor("蜘蛛王后艾达", "res://assets/extracted/images/image_0075.png", Vector2(539.7, 90), Vector2(152, 115), "battle:spider_queen", Color("ff5735"))
			_add_actor("刺虫人", "res://assets/extracted/images/image_0077.png", Vector2(457, 243), Vector2(152, 115), "battle:avit_thorn_bug@1", Color("f3dc77"))
			_add_actor("地图占领报名官", "res://assets/extracted/images/image_1076.png", Vector2(100, 285), Vector2(58, 111), "territory:avit_island", Color("55ff55"))
		"volcano":
			_add_actor("四牙怪", "res://assets/extracted/images/image_0079.png", Vector2(470, 361.4), Vector2(152, 115), "battle:volcano_four_fang@1", Color("f3dc77"))
			_add_actor("90级BOSS", "res://assets/extracted/images/image_1072.png", Vector2(379.45, 91.3), Vector2(101, 132), "battle:volcano_boss_90", Color("ff5035"))
			_add_actor("蝎怪", "res://assets/extracted/images/image_0083.png", Vector2(539.7, 91.3), Vector2(152, 115), "battle:volcano_scorpion@1", Color("f3dc77"))
			_add_actor("炎女", "res://assets/extracted/images/image_0081.png", Vector2(495.1, 225.85), Vector2(152, 115), "battle:volcano_fire_woman@1", Color("f3dc77"))
			_add_actor("四牙怪", "res://assets/extracted/images/image_0079.png", Vector2(262.7, 351.85), Vector2(152, 115), "battle:volcano_four_fang@2", Color("f3dc77"))
			_add_actor("炎女", "res://assets/extracted/images/image_0081.png", Vector2(318, 210.85), Vector2(152, 115), "battle:volcano_fire_woman@2", Color("f3dc77"))
		"abyss_maze":
			_add_actor("100级BOSS", "res://assets/extracted/images/image_1072.png", Vector2(209.8, 389.55), Vector2(101, 132), "battle:abyss_boss_100", Color("ff3030"))
			_add_actor("暗黑弥塞亚", "res://assets/extracted/images/image_0085.png", Vector2(345, 141.3), Vector2(152, 115), "battle:abyss_dark_messiah@1", Color("f3dc77"))
			_add_actor("暗黑格拉斯", "res://assets/extracted/images/image_0087.png", Vector2(522.9, 233), Vector2(152, 115), "battle:abyss_dark_grass@1", Color("f3dc77"))
			_add_actor("叹息骑士", "res://assets/extracted/images/image_0089.png", Vector2(370.9, 389.55), Vector2(152, 115), "battle:abyss_sigh_knight@1", Color("f3dc77"))
			_add_actor("暗黑弥塞亚", "res://assets/extracted/images/image_0085.png", Vector2(505.2, 97.3), Vector2(152, 115), "battle:abyss_dark_messiah@2", Color("f3dc77"))
			_add_actor("暗黑格拉斯", "res://assets/extracted/images/image_0087.png", Vector2(349, 270.5), Vector2(152, 115), "battle:abyss_dark_grass@2", Color("f3dc77"))
			_add_actor("叹息骑士", "res://assets/extracted/images/image_0089.png", Vector2(537.7, 378.9), Vector2(152, 115), "battle:abyss_sigh_knight@2", Color("f3dc77"))
		"ice_border":
			_add_actor("雪原战士", "res://assets/extracted/images/image_0127.png", Vector2(390, 215), Vector2(96, 112), "battle:snow_warrior", Color("80d8ff"))
			_add_actor("雪原骑兵", "res://assets/extracted/images/image_0129.png", Vector2(520, 175), Vector2(96, 112), "battle:snow_cavalry", Color("80d8ff"))
			_add_actor("雪原统领", "res://assets/extracted/images/image_0049.png", Vector2(585, 275), Vector2(96, 112), "battle:snow_officer", Color("ffcc35"))
		"demon_camp":
			if GameState.is_final_campaign_enemy_alive("demon_guard"):
				_add_actor("魔军守卫军", "res://assets/extracted/images/image_0099.png", Vector2(430, 235), Vector2(92, 118), "battle:demon_guard", Color("ff7d35"))
			if GameState.is_final_campaign_enemy_alive("demon_assault"):
				_add_actor("魔军突击队", "res://assets/extracted/images/image_0097.png", Vector2(430, 78), Vector2(92, 118), "battle:demon_assault", Color("ff5d35"))
		"demon_left":
			if GameState.is_final_campaign_enemy_alive("demon_totem"):
				_add_actor("魔军图腾兽", "res://assets/extracted/images/image_0103.png", Vector2(465, 270), Vector2(105, 130), "battle:demon_totem", Color("ffb135"))
		"demon_right":
			if GameState.is_final_campaign_enemy_alive("demon_mystery"):
				_add_actor("魔军神秘部队", "res://assets/extracted/images/image_0101.png", Vector2(475, 275), Vector2(100, 128), "battle:demon_mystery", Color("d85dff"))
		"demon_banner":
			if GameState.is_final_campaign_enemy_alive("demon_commander"):
				_add_actor("魔军主帅", "res://assets/extracted/images/image_0105.png", Vector2(455, 145), Vector2(90, 140), "battle:demon_commander", Color("ff3030"))
		"energy_tower":
			if GameState.is_final_campaign_enemy_alive("demon_energy"):
				_add_actor("魔的能量", "res://assets/extracted/images/image_0116.png", Vector2(455, 135), Vector2(130, 175), "battle:demon_energy", Color("ff35e7"))
		"pk_arena":
			if GameState.pk_race_active:
				_add_actor("60级PK赛BOSS", "res://assets/extracted/images/image_1072.png", Vector2(539.7, 218.85), Vector2(101, 132), "battle:pk_champion_60", Color("ffcc35"))
		"pk_arena_2":
			if GameState.pk_race_active:
				_add_actor("100级PK赛BOSS", "res://assets/extracted/images/image_1072.png", Vector2(479.7, 197.85), Vector2(101, 132), "battle:pk_champion_100", Color("ff9d35"))
		"pk_arena_3":
			if GameState.pk_race_active:
				_add_actor("130级PK赛BOSS", "res://assets/extracted/images/image_1072.png", Vector2(403.6, 159.45), Vector2(101, 132), "battle:pk_champion_130", Color("ff5035"))
		"dungeon":
			_add_actor("地下城首领", "res://assets/extracted/images/image_0049.png", Vector2(470, 205), Vector2(110, 125), "battle:dungeon_boss", Color("ff3030"))
		"dungeon_floor_2":
			_add_actor("地下城二层首领", "res://assets/extracted/images/image_0127.png", Vector2(470, 205), Vector2(110, 125), "battle:dungeon_boss_2", Color("ff3030"))
		"dungeon_floor_3":
			_add_actor("地下城三层首领", "res://assets/extracted/images/image_0129.png", Vector2(470, 205), Vector2(110, 125), "battle:dungeon_boss_3", Color("ff3030"))
	var ch_mid := GameState.active_challenge_monster()
	if not ch_mid.is_empty() and GameState.challenge_unit_visible(ch_mid):
		_add_actor("ch_boss", "res://assets/extracted/images/image_1072.png", Vector2(380, 280), Vector2(101, 132), "battle:%s" % ch_mid, Color("ffcc35"))
	var pt_mid := GameState.active_pet_trial_monster()
	if not pt_mid.is_empty() and GameState.pet_trial_unit_visible(pt_mid):
		_add_actor("pt_boss", "res://assets/extracted/images/image_1072.png", Vector2(180, 120), Vector2(101, 132), "battle:%s" % pt_mid, Color("ffcc35"))
	if GameState.should_show_fuwa_messenger(map_id):
		var messenger_positions := {
			"thunder_continent":Vector2(160, 330), "palace":Vector2(137.05, 244.95),
			"desert":Vector2(115, 220), "dream_swamp":Vector2(115, 220),
			"ice_palace":Vector2(30.15, 122), "avit_island":Vector2(34.05, 339.55),
			"volcano":Vector2(23, 122), "abyss_maze":Vector2(23, 122),
		}
		_add_actor("2008奥运使者", "res://assets/extracted/images/image_1086.png", messenger_positions.get(map_id, Vector2(160, 330)), Vector2(70, 115), "fuwa_messenger", Color("55ff55"))


func _refresh_map_navigation(map_data: Dictionary) -> void:
	for button: Button in direction_buttons.values():
		button.hide()
		var connections: Array = button.pressed.get_connections()
		for connection: Dictionary in connections:
			button.pressed.disconnect(connection["callable"] as Callable)
	var exits: Array = map_data.get("exits", [])
	var fallback := ["left", "right", "top", "bottom"]
	for index in mini(exits.size(), 4):
		var exit_data: Dictionary = exits[index]
		var map_id := str(map_data.get("id", ""))
		var target_id := str(exit_data.get("target", ""))
		var profile := _native_exit_profile(map_id, target_id, fallback[index])
		var direction := str(profile.get("direction", fallback[index]))
		var button = direction_buttons[direction]
		var rect: Rect2 = profile.get("rect", _fallback_exit_rect(direction))
		var target_map: Dictionary = world.get_map(target_id)
		var target_name := str(target_map.get("name", exit_data.get("name", target_id)))
		var exit_name := str(exit_data.get("name", target_name))
		var verb := "返回" if exit_name.begins_with("返回") else "进入"
		button.position = rect.position
		button.size = rect.size
		# Locked (gated) exits stay clickable so the player gets the block reason
		# via _travel_to instead of a silently disabled button.
		var blocked: bool = not GameState.can_enter_map(target_id)
		button.disabled = false
		button.locked = blocked
		button.configure(target_id, target_name, direction, verb)
		button.set_meta("world_entity_kind", "exit")
		button.set_meta("world_entity_id", "exit:" + target_id)
		button.set_meta("world_direction", direction)
		button.set_meta("world_target_map", target_id)
		button.set_meta("world_action_route", "edge_exit")
		button.set_meta("world_current_map", map_id)
		button.set_meta("world_required_level", GameState.map_entry_required_level(target_id))
		button.set_meta("world_locked", blocked)
		button.pressed.connect(_travel_to.bind(target_id))
		button.show()


func _native_exit_profile(map_id: String, target_id: String, fallback: String) -> Dictionary:
	# Root positions and rotations measured from character 1071 in the original SWF.
	# Rectangles below are the transformed 41x90 hit bounds, not invented UI slots.
	var profiles := {
		"cassano_city>avit_island":{"direction":"right", "rect":Rect2(654.5, 264.95, 41.0, 90.0)},
		"cassano_city>palace":{"direction":"top", "rect":Rect2(211.05, 124.3, 90.0, 41.0)},
		"cassano_city>thunder_continent":{"direction":"left", "rect":Rect2(2.1, 264.95, 41.0, 90.0)},
		"cassano_city>desert":{"direction":"bottom", "rect":Rect2(391.05, 403.9, 90.0, 41.0)},
		"thunder_continent>cassano_city":{"direction":"right", "rect":Rect2(657.7, 219.5, 41.0, 90.0)},
		"thunder_continent>thunder_mine":{"direction":"top", "rect":Rect2(206.8, 124.3, 90.0, 41.0)},
		"thunder_continent>desert":{"direction":"bottom", "rect":Rect2(386.8, 400.45, 90.0, 41.0)},
		"thunder_mine>thunder_continent":{"direction":"bottom", "rect":Rect2(386.8, 400.45, 90.0, 41.0)},
		"green_field>cassano_city":{"direction":"left", "rect":Rect2(10.0, 256.3, 41.0, 90.0)},
		"grass_reward>cassano_city":{"direction":"left", "rect":Rect2(10.0, 256.3, 41.0, 90.0)},
		"palace>palace_garden":{"direction":"right", "rect":Rect2(650.7, 393.95, 41.0, 90.0)},
		"palace>cassano_city":{"direction":"bottom", "rect":Rect2(323.75, 406.5, 90.0, 41.0)},
		"palace>ice_palace":{"direction":"left", "rect":Rect2(2.0, 218.0, 41.0, 90.0)},
		"palace_garden>palace":{"direction":"left", "rect":Rect2(5.2, 202.95, 41.0, 90.0)},
		"lottery_room>palace":{"direction":"right", "rect":Rect2(656.5, 221.1, 41.0, 90.0)},
		"desert>thunder_continent":{"direction":"top", "rect":Rect2(206.0, 124.3, 90.0, 41.0)},
		"desert>dream_swamp":{"direction":"bottom", "rect":Rect2(386.0, 402.85, 90.0, 41.0)},
		"dream_swamp>desert":{"direction":"top", "rect":Rect2(255.65, 124.3, 90.0, 41.0)},
		"dream_swamp>ice_palace":{"direction":"right", "rect":Rect2(653.25, 324.85, 41.0, 90.0)},
		"ice_palace>dream_swamp":{"direction":"left", "rect":Rect2(1.5, 245.85, 41.0, 90.0)},
		"ice_palace>avit_island":{"direction":"top", "rect":Rect2(211.8, 124.3, 90.0, 41.0)},
		"ice_palace>palace":{"direction":"bottom", "rect":Rect2(301.8, 402.0, 90.0, 41.0)},
		"ice_palace>ice_border":{"direction":"right", "rect":Rect2(657.0, 245.85, 41.0, 90.0)},
		"avit_island>ice_palace":{"direction":"bottom", "rect":Rect2(308.35, 406.5, 90.0, 41.0)},
		"avit_island>volcano":{"direction":"right", "rect":Rect2(659.0, 225.85, 41.0, 90.0)},
		"volcano>avit_island":{"direction":"left", "rect":Rect2(0.0, 261.85, 41.0, 90.0)},
		"volcano>abyss_maze":{"direction":"bottom", "rect":Rect2(218.35, 401.5, 90.0, 41.0)},
		"abyss_maze>volcano":{"direction":"top", "rect":Rect2(105.45, 128.0, 90.0, 41.0)},
		"ice_border>ice_palace":{"direction":"left", "rect":Rect2(0.0, 216.0, 41.0, 90.0)},
		"ice_border>demon_camp":{"direction":"right", "rect":Rect2(659.0, 225.85, 41.0, 90.0)},
		"demon_camp>ice_border":{"direction":"left", "rect":Rect2(0.0, 216.0, 41.0, 90.0)},
		"demon_camp>demon_right":{"direction":"bottom", "rect":Rect2(386.0, 402.85, 90.0, 41.0)},
		"demon_camp>demon_left":{"direction":"top", "rect":Rect2(255.65, 124.3, 90.0, 41.0)},
		"demon_camp>demon_banner":{"direction":"right", "rect":Rect2(659.0, 225.85, 41.0, 90.0)},
		"demon_right>demon_camp":{"direction":"bottom", "rect":Rect2(386.0, 402.85, 90.0, 41.0)},
		"demon_left>demon_camp":{"direction":"top", "rect":Rect2(277.8, 96.85, 90.0, 41.0)},
		"demon_banner>demon_camp":{"direction":"left", "rect":Rect2(0.0, 216.0, 41.0, 90.0)},
		"demon_banner>energy_tower":{"direction":"right", "rect":Rect2(659.0, 225.85, 41.0, 90.0)},
		"energy_tower>demon_banner":{"direction":"left", "rect":Rect2(0.0, 216.0, 41.0, 90.0)},
		"dungeon>cassano_city":{"direction":"top", "rect":Rect2(206.0, 124.3, 90.0, 41.0)},
		"dungeon>dungeon_floor_2":{"direction":"right", "rect":Rect2(657.0, 228.95, 41.0, 90.0)},
		"dungeon_floor_2>dungeon":{"direction":"left", "rect":Rect2(2.0, 228.95, 41.0, 90.0)},
		"dungeon_floor_2>dungeon_floor_3":{"direction":"right", "rect":Rect2(657.0, 228.95, 41.0, 90.0)},
		"dungeon_floor_3>dungeon_floor_2":{"direction":"top", "rect":Rect2(206.0, 124.3, 90.0, 41.0)},
		"south_city_gate>south_city_square":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"south_city_square>south_city_gate":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"south_city_gate>border_watchpost":{"direction":"bottom", "rect":Rect2(305.0, 403.0, 90.0, 41.0)},
		"border_watchpost>south_city_gate":{"direction":"top", "rect":Rect2(305.0, 124.3, 90.0, 41.0)},
		"border_watchpost>border_supply_route":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"border_supply_route>border_watchpost":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"border_watchpost>border_ruins":{"direction":"bottom", "rect":Rect2(305.0, 403.0, 90.0, 41.0)},
		"border_ruins>border_watchpost":{"direction":"top", "rect":Rect2(305.0, 124.3, 90.0, 41.0)},
		"border_ruins>border_command_tent":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"border_command_tent>border_ruins":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"ice_frontier>frozen_pass":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"frozen_pass>ice_frontier":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"ice_frontier>crystal_cavern":{"direction":"bottom", "rect":Rect2(305.0, 403.0, 90.0, 41.0)},
		"crystal_cavern>ice_frontier":{"direction":"top", "rect":Rect2(305.0, 124.3, 90.0, 41.0)},
		"frozen_pass>elemental_laboratory":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"elemental_laboratory>frozen_pass":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"elemental_laboratory>aurora_sanctum":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"aurora_sanctum>elemental_laboratory":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"abyss_gate>abyss_outer_ring":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"abyss_outer_ring>abyss_gate":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"abyss_gate>abyss_echo_halls":{"direction":"bottom", "rect":Rect2(305.0, 403.0, 90.0, 41.0)},
		"abyss_echo_halls>abyss_gate":{"direction":"top", "rect":Rect2(305.0, 124.3, 90.0, 41.0)},
		"abyss_outer_ring>totem_sanctum":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"totem_sanctum>abyss_outer_ring":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"totem_sanctum>abyss_heart":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"abyss_heart>totem_sanctum":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"treeheart_city>cassano_city":{"direction":"left", "rect":Rect2(10.0, 256.3, 41.0, 90.0)},
		"treeheart_city>treeheart_outskirts":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"treeheart_outskirts>treeheart_city":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"treeheart_outskirts>treeheart_core":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"treeheart_outskirts>harbor_quay":{"direction":"bottom", "rect":Rect2(305.0, 403.0, 90.0, 41.0)},
		"treeheart_core>treeheart_outskirts":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"harbor_quay>treeheart_outskirts":{"direction":"top", "rect":Rect2(305.0, 124.3, 90.0, 41.0)},
		"harbor_quay>harbor_market":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"harbor_quay>sea_cave":{"direction":"bottom", "rect":Rect2(305.0, 403.0, 90.0, 41.0)},
		"harbor_market>harbor_quay":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"sea_cave>harbor_quay":{"direction":"top", "rect":Rect2(305.0, 124.3, 90.0, 41.0)},
		"sea_cave>tide_shrine":{"direction":"right", "rect":Rect2(657.0, 230.0, 41.0, 90.0)},
		"tide_shrine>sea_cave":{"direction":"left", "rect":Rect2(2.0, 230.0, 41.0, 90.0)},
		"pk_arena>cassano_city":{"direction":"top", "rect":Rect2(211.05, 124.3, 90.0, 41.0)},
		"pk_arena_2>cassano_city":{"direction":"top", "rect":Rect2(211.05, 124.3, 90.0, 41.0)},
		"pk_arena_3>cassano_city":{"direction":"top", "rect":Rect2(211.05, 124.3, 90.0, 41.0)},
	}
	var key := "%s>%s" % [map_id, target_id]
	if profiles.has(key):
		return profiles[key]
	var direction := _direction_for_exit(map_id, target_id, fallback)
	return {"direction":direction, "rect":_fallback_exit_rect(direction)}


func _fallback_exit_rect(direction: String) -> Rect2:
	return {
		"top":Rect2(305.0, 124.3, 90.0, 41.0),
		"bottom":Rect2(305.0, 403.0, 90.0, 41.0),
		"left":Rect2(2.0, 230.0, 41.0, 90.0),
		"right":Rect2(657.0, 230.0, 41.0, 90.0),
	}.get(direction, Rect2(657.0, 230.0, 41.0, 90.0))


func _direction_for_exit(map_id: String, target_id: String, fallback: String) -> String:
	var routes := {
		"cassano_city":{"avit_island":"right", "palace":"top", "thunder_continent":"left", "desert":"bottom"},
		"palace":{"ice_palace":"left", "cassano_city":"bottom", "palace_garden":"right"},
		"palace_garden":{"palace":"left"},
		"lottery_room":{"palace":"right"},
		"green_field":{"cassano_city":"left"},
		"grass_reward":{"cassano_city":"left"},
		"south_city_gate":{"south_city_square":"right", "border_watchpost":"bottom"},
		"south_city_square":{"south_city_gate":"left"},
		"border_watchpost":{"south_city_gate":"top", "border_supply_route":"right", "border_ruins":"bottom"},
		"border_supply_route":{"border_watchpost":"left"},
		"border_ruins":{"border_watchpost":"top", "border_command_tent":"right"},
		"border_command_tent":{"border_ruins":"left"},
		"ice_frontier":{"frozen_pass":"right", "crystal_cavern":"bottom"},
		"frozen_pass":{"ice_frontier":"left", "elemental_laboratory":"right"},
		"crystal_cavern":{"ice_frontier":"top"},
		"elemental_laboratory":{"frozen_pass":"left", "aurora_sanctum":"right"},
		"aurora_sanctum":{"elemental_laboratory":"left"},
		"abyss_gate":{"abyss_outer_ring":"right", "abyss_echo_halls":"bottom"},
		"abyss_outer_ring":{"abyss_gate":"left", "totem_sanctum":"right"},
		"abyss_echo_halls":{"abyss_gate":"top"},
		"totem_sanctum":{"abyss_outer_ring":"left", "abyss_heart":"right"},
		"abyss_heart":{"totem_sanctum":"left"},
		"treeheart_city":{"cassano_city":"left", "treeheart_outskirts":"right"},
		"treeheart_outskirts":{"treeheart_city":"left", "treeheart_core":"right", "harbor_quay":"bottom"},
		"treeheart_core":{"treeheart_outskirts":"left"},
		"harbor_quay":{"treeheart_outskirts":"top", "harbor_market":"right", "sea_cave":"bottom"},
		"harbor_market":{"harbor_quay":"left"},
		"sea_cave":{"harbor_quay":"top", "tide_shrine":"right"},
		"tide_shrine":{"sea_cave":"left"},
		"dungeon":{"cassano_city":"top", "dungeon_floor_2":"right"},
		"dungeon_floor_2":{"dungeon":"left", "dungeon_floor_3":"right"},
		"dungeon_floor_3":{"dungeon_floor_2":"top"},
		"thunder_continent":{"cassano_city":"right", "thunder_mine":"top", "desert":"bottom"},
		"thunder_mine":{"thunder_continent":"bottom"},
		"desert":{"thunder_continent":"top", "dream_swamp":"bottom"},
		"dream_swamp":{"desert":"top", "ice_palace":"right"},
		"ice_palace":{"dream_swamp":"left", "avit_island":"top", "ice_border":"right", "palace":"bottom"},
		"ice_border":{"ice_palace":"left", "demon_camp":"right"},
		"demon_camp":{"ice_border":"left", "demon_right":"bottom", "demon_left":"top", "demon_banner":"right"},
		"demon_left":{"demon_camp":"top"},
		"demon_right":{"demon_camp":"bottom"},
		"demon_banner":{"demon_camp":"left", "energy_tower":"right"},
		"energy_tower":{"demon_banner":"left"},
		"avit_island":{"ice_palace":"bottom", "volcano":"right"},
		"volcano":{"avit_island":"left", "abyss_maze":"bottom"},
		"abyss_maze":{"volcano":"top"},
		"pk_arena":{"cassano_city":"top"},
		"pk_arena_2":{"cassano_city":"top"},
		"pk_arena_3":{"cassano_city":"top"},
	}
	if routes.has(map_id):
		return str(routes[map_id].get(target_id, fallback))
	return fallback

func _travel_to(map_id: String) -> void:
	if scene_battle_controller != null and scene_battle_controller.is_active():
		return
	if not world.can_travel(GameState.current_map_id, map_id):
		_set_status("无法到达该地图。")
		return
	if not GameState.can_enter_map(map_id):
		var required_level := GameState.map_entry_required_level(map_id)
		if GameState.level < required_level:
			_set_status("需要达到%d级才能进入。" % required_level)
		elif map_id == "palace_garden":
			_set_status("只有爵位达到勋爵以上才可以进入后花园。")
		elif map_id == "ice_border":
			_set_status("雪域边境极其危险：星期五可执行突袭任务，救出国王后将永久开放。")
		elif map_id in ["demon_camp", "demon_left", "demon_right", "demon_banner"]:
			_set_status("必须先救出国王并取得最终战役情报。")
		elif map_id == "energy_tower":
			_set_status("魔军主帅仍在保护能量塔禁地，必须先将其消灭。")
		elif map_id in ["treeheart_core", "harbor_quay", "harbor_market", "sea_cave", "tide_shrine", "south_city_square", "border_watchpost", "border_supply_route", "border_ruins", "border_command_tent", "frozen_pass", "crystal_cavern", "elemental_laboratory", "aurora_sanctum", "abyss_outer_ring", "abyss_echo_halls", "totem_sanctum", "abyss_heart"]:
			_set_status("chapter_locked")
		else:
			_set_status("需要先击败前一层首领才能进入。")
		return
	_hide_all_panels()
	if GameState.current_map_id in ["pk_arena", "pk_arena_2", "pk_arena_3"] and map_id == "cassano_city":
		GameState.finish_pk_race(false)
	GameState.current_map_id = map_id
	AudioService.play("change_map")
	_apply_current_map()
	_set_status("已经前往：%s" % world.get_map(map_id).get("name", map_id))


func _toggle_inventory() -> void:
	var should_show := not inventory_panel.visible or warehouse_panel.visible
	_hide_all_panels()
	if should_show:
		inventory_panel.position = Vector2(453, 300)
		inventory_panel.show()


func _toggle_warehouse() -> void:
	var should_show := not warehouse_panel.visible
	_hide_all_panels()
	if should_show:
		inventory_panel.position = Vector2(453, 300)
		warehouse_panel.position = Vector2(208, 220)
		inventory_panel.show()
		warehouse_panel.show()


func _toggle_gold_shop() -> void:
	_toggle_exclusive_panel(gold_shop)


func _toggle_stone_shop() -> void:
	_toggle_exclusive_panel(stone_shop)


func _toggle_equipment() -> void:
	_toggle_exclusive_panel(equipment_panel)


func _toggle_enhancement() -> void:
	_toggle_exclusive_panel(enhancement_panel)


func _toggle_pets() -> void:
	_toggle_exclusive_panel(pet_panel)


func _toggle_research() -> void:
	_toggle_exclusive_panel(research_panel)


func _open_research_dialogue() -> void:
	var words := "为了提升勇士们幻兽的战斗力，国家投资100,000魔石成立了幻兽研究所。技术每星期提升10%，每资助10,000魔石可以提高1级技术，20级以上可生产奇异兽。"
	var actions: Array[Dictionary] = [
		{"label":"进入","action":"research"},
		{"label":"研究所的当前信息","action":"research_info"},
		{"label":"关于2008奥运使者","action":"research_olympic_info"},
		{"label":"提高产量任务","action":"research_production_task"},
		{"label":"离开","action":"close"},
	]
	dialogue_panel.open_dialogue("幻兽研究所", words, _with_pet_endgame_gate(_with_ice_gate(actions)))



func _with_pet_endgame_gate(actions: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inserted := false
	for raw: Variant in actions:
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		if not inserted and str(row.get("action", "")) == "close":
			out.append({"label": "\u5e7b\u517d\u7ec8\u5c40", "action": "pet_endgame_board"})
			out.append({"label": "\u5e7b\u517d\u8bd5\u70bc", "action": "pet_endgame_menu"})
			inserted = true
		out.append(row)
	if not inserted:
		out.append({"label": "\u5e7b\u517d\u7ec8\u5c40", "action": "pet_endgame_board"})
		out.append({"label": "\u5e7b\u517d\u8bd5\u70bc", "action": "pet_endgame_menu"})
	return out


func _open_pet_endgame_board() -> void:
	_hide_all_panels()
	pet_endgame_panel.show()
	pet_endgame_panel.refresh()
	_set_status(GameState.pet_endgame_lines()[0] if not GameState.pet_endgame_lines().is_empty() else "PE")


func _open_pet_endgame_menu() -> void:
	var acts: Array[Dictionary] = [
		{"label": "col_light", "action": "claim_col:col_ad_light"},
		{"label": "support", "action": "set_support"},
		{"label": "t1", "action": "start_ptrial:pet_trial_1"},
		{"label": "t2", "action": "start_ptrial:pet_trial_2"},
		{"label": "t3", "action": "start_ptrial:pet_trial_3"},
		{"label": "king", "action": "start_ptrial:pet_king"},
		{"label": "rc_note", "action": "claim_rc:rc_note"},
		{"label": "\u8fd4\u56de", "action": "research_npc"},
		{"label": "\u79bb\u5f00", "action": "close"},
	]
	dialogue_panel.open_dialogue("\u5e7b\u517d\u8bd5\u70bc", "pet endgame", acts)


func _start_named_pet_trial(trial_id: String) -> void:
	var result: Dictionary = GameState.try_start_pet_trial(trial_id, "ui:pt:%s:%d" % [trial_id, GameState.current_day])
	if not bool(result.get("success", false)):
		_set_status(str(result.get("code", "PET_TRIAL_KING")))
		return
	_apply_current_map()
	_set_status("PT %s" % trial_id)

func _open_research_info() -> void:
	var tech := float(GameState.research.get("technology_level", 0.0))
	var rate := int(GameState.research.get("production_rate", 0))
	var stock := int(GameState.research.get("stock", 0))
	var vip := int(GameState.research.get("vip_level", 0))
	var words := "幻兽研究所现在技术等级为%d级。生产量为%d个/天。现在还有%d个库存。" % [int(round(tech)), rate, stock]
	if vip > 0:
		words += "\n你是我们的%d星VIP，享受优惠价购买奇异兽。" % vip
	if tech < 20.0:
		words += "\n在20级之前未能生产幻兽。"
	else:
		words += "\n当前可生产奇异兽，售价%d魔石。" % GameState.pet_service.research_pet_price(GameState.research)
	var actions: Array[Dictionary] = [{"label":"返回","action":"research_npc"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("幻兽研究所", words, actions)


func _open_research_olympic_info() -> void:
	var words := ""
	var found_count := int(GameState.fuwa_event.get("found_count", 0))
	var completion_claimed := bool(GameState.fuwa_event.get("completion_claimed", false))
	if completion_claimed:
		var cap := int(GameState.pet_service.config.get("research", {}).get("technology_level_cap", 300))
		words = "非常感谢2008奥运使者给我们的技术，现在我们的技术等级最高可以提高到%d级。" % cap
	elif found_count >= GameState.FUWA_NAMES.size() and not completion_claimed:
		words = "2008奥运使者的技术资料已经到手，请先向2008奥运使者完成最终交付。"
	else:
		words = "听说2008奥运使者对幻兽培养技术很有研究。如果你见到他，帮我打听一些有关幻兽培养的技术。"
	var actions: Array[Dictionary] = [{"label":"放心，我会的","action":"research_npc"},{"label":"离开","action":"close"}]
	dialogue_panel.open_dialogue("幻兽研究所", words, actions)


func _perform_research_production_task() -> void:
	var result := GameState.complete_research_production_task()
	if bool(result.get("success", false)):
		_set_status("产量任务完成：日产量+2。")
	elif str(result.get("reason", "")) == "rate_cap":
		_set_status("日产量已经达到上限6。")
	else:
		_set_status("需要%d个灵魂王。" % int(result.get("required", GameState.pet_service.production_task_cost(GameState.research))))
	_open_research_dialogue()


func _toggle_progression() -> void:
	_toggle_exclusive_panel(progression_panel)


func _toggle_quests() -> void:
	_toggle_exclusive_panel(quest_panel)


func _toggle_skills() -> void:
	_toggle_exclusive_panel(skill_panel)


func _toggle_map() -> void:
	_set_status("地图切换请使用场景四周的方向按钮。")


func _toggle_exclusive_panel(panel: Control) -> void:
	var should_show := not panel.visible
	_hide_all_panels()
	if should_show:
		panel.show()


func _hide_all_panels() -> void:
	for candidate in [inventory_panel, warehouse_panel, gold_shop, stone_shop, equipment_panel, enhancement_panel, pet_panel, research_panel, progression_panel, quest_panel, skill_panel, dialogue_panel, adventurer_roster_panel, adventurer_mail_panel, adventurer_trade_panel, ranking_panel, arena_panel, guild_market_panel, property_territory_panel, border_command_panel, ice_codex_panel, abyss_board_panel, challenge_board_panel, pet_endgame_panel, season_board_panel]:
		if candidate != null:
			candidate.hide()
	_hide_item_description()
	_hide_monster_tooltip()


func _world_monster_id_from_action(action_id: String) -> String:
	return action_id.trim_prefix("battle:").get_slice("@", 0)


func _engage_world_monster(action_id: String, skill_id: String = "", territory_challenge_started: bool = false) -> void:
	var monster_id := _world_monster_id_from_action(action_id)
	if int(GameState.get_player_stats().get("current_hp", 0)) <= 0:
		_set_status("人物没有生命值，请先双击背包中的果子恢复生命。")
		return
	var actor: TextureRect = interactive_actors.get(action_id)
	var label: Label = actor_labels.get(action_id)
	if GameState.expansion_state_service.chapter_encounter_service.is_chapter_boss(monster_id) and not GameState.expansion_state_service.chapter_encounter_service.allow_engage(GameState.expansion_state, monster_id):
		_set_status("CHAPTER_PRECONDITION")
		return
	if GameState.expansion_state_service.border_defense_service.is_border_unit(monster_id):
		var sess: Dictionary = GameState.begin_border_session(monster_id, "sess:%s:%d" % [monster_id, GameState.current_day])
		if not bool(sess.get("success", false)):
			_set_status(str(sess.get("code", "BORDER_PRECONDITION")))
			return
	if GameState.expansion_state_service.ice_encounter_service.is_ice_unit(monster_id):
		var ice_sess: Dictionary = GameState.begin_ice_session(monster_id, "ice:%s:%d" % [monster_id, GameState.current_day])
		if not bool(ice_sess.get("success", false)):
			_set_status(str(ice_sess.get("code", "ICE_BOSS_STAGE")))
			return
	if GameState.expansion_state_service.echo_encounter_service.is_abyss_unit(monster_id):
		var abyss_sess: Dictionary = GameState.begin_abyss_session(monster_id, "abyss:%s:%d" % [monster_id, GameState.current_day])
		if not bool(abyss_sess.get("success", false)):
			_set_status(str(abyss_sess.get("code", "ABYSS_ECHO_UNKNOWN")))
			return
	if GameState.expansion_state_service.challenge_service.is_challenge_unit(monster_id):
		var ch_sess: Dictionary = GameState.begin_challenge_session(monster_id, "ch:%s:%d" % [monster_id, GameState.current_day])
		if not bool(ch_sess.get("success", false)):
			_set_status(str(ch_sess.get("code", "CHALLENGE_SESSION")))
			return
	if GameState.expansion_state_service.pet_trial_service.is_trial_unit(monster_id):
		var pt_sess: Dictionary = GameState.begin_pet_trial_session(monster_id, "pt:%s:%d" % [monster_id, GameState.current_day])
		if not bool(pt_sess.get("success", false)):
			_set_status(str(pt_sess.get("code", "PET_TRIAL_CANCEL")))
			return
	if scene_battle_controller.is_active():
		_hide_all_panels()
		if scene_battle_controller.engage(monster_id, actor, label, skill_id):
			for button: Button in direction_buttons.values():
				button.disabled = true
		return
	var territory_map := GameState.territory_service.map_for_challenger(monster_id)
	if not territory_map.is_empty() and not territory_challenge_started:
		var challenge := GameState.begin_territory_challenge(territory_map)
		if not bool(challenge.get("success", false)):
			_show_territory_challenge_error(challenge)
			return
	_hide_all_panels()
	if scene_battle_controller.engage(monster_id, actor, label, skill_id):
		for button: Button in direction_buttons.values():
			button.disabled = true

func _on_scene_player_hp_changed(current_hp: int, maximum_hp: int) -> void:
	current_player_hp = clampi(current_hp, 0, maxi(1, maximum_hp))
	_set_meter_nodes(
		player_status_card.hp_bar,
		player_status_card.hp_text,
		"生命",
		current_player_hp,
		maxi(1, maximum_hp),
	)

func _on_scene_battle_finished(monster_id: String, victory: bool) -> void:
	current_player_hp = -1
	var chapter_boss := GameState.settle_chapter_boss(monster_id, victory, "battle:%s:%s" % [monster_id, str(victory)])
	var border_battle := GameState.settle_border_battle(monster_id, victory, str(GameState.border_runtime().get("active_session_id", "")))
	var ice_battle := GameState.settle_ice_battle(monster_id, victory, str(GameState.ice_runtime().get("active_session_id", "")))
	var abyss_battle := GameState.settle_abyss_battle(monster_id, victory, str(GameState.abyss_runtime().get("active_session_id", "")), not victory and int(GameState.player_current_hp) <= 0)
	var ch_battle := GameState.settle_challenge_battle(monster_id, victory, str(GameState.challenge_runtime().get("active_session_id", "")))
	var pt_battle := GameState.settle_pet_trial_battle(monster_id, victory, str(GameState.pet_endgame_runtime().get("active_session_id", "")))
	if str(monster_id).begins_with("arena_npc:"):
		if victory:
			var match_id := str(GameState.expansion_state.get("rankings", {}).get("active_match_id", ""))
			if not match_id.is_empty():
				GameState.settle_arena_match(match_id, true, "battle_finished:%s" % match_id)
		else:
			GameState.abandon_active_arena_match("defeat")
	var territory_result := GameState.resolve_territory_challenge(monster_id, victory)
	if monster_id in ["pk_champion_60", "pk_champion_100", "pk_champion_130"]:
		GameState.finish_pk_race(victory)
	if monster_id == "nameless_war_soul_keeper" and not victory:
		GameState.leave_war_soul_maze()
	if not victory:
		GameState.current_map_id = "cassano_city"
		_apply_current_map()
	else:
		if monster_id == "fuwa_beast" and bool(GameState.fuwa_event.get("beast_defeated", false)):
			GameState.current_map_id = "grass_reward"
			_apply_current_map()
			_set_status("你击败了挡道的雷角风牙兽，来到了草原2。点击福娃领取礼物。")
		elif GameState.is_final_campaign_monster(monster_id):
			_rebuild_map_actors(GameState.current_map_id)
		elif monster_id == "nameless_war_soul_keeper":
			GameState.current_map_id = "cassano_city"
			_apply_current_map()
			_set_status("获得了战魂之心。终于找到战魂的秘密，去找装备锻造师吧。")
		elif monster_id in ["pk_champion_60", "pk_champion_100", "pk_champion_130"]:
			_rebuild_map_actors(GameState.current_map_id)
			_refresh_map_navigation(world.get_map(GameState.current_map_id))
			_set_status("恭喜获得本届PK赛冠军，请从左侧返回卡萨诺城。")
		elif bool(territory_result.get("resolved", false)):
			_rebuild_map_actors(GameState.current_map_id)
			_refresh_map_navigation(world.get_map(GameState.current_map_id))
		else:
			_refresh_map_navigation(world.get_map(GameState.current_map_id))
	if bool(territory_result.get("resolved", false)):
		if victory:
			var territory := GameState.get_territory(str(territory_result.get("map_id", "")))
			_set_status("挑战成功！你已成为%s保护者。" % str(territory.get("name", "该地图")))
		else:
			_set_status("保护地挑战失败，今天不能再次挑战。")
	_refresh_status_cards()
	if victory and monster_id == "demon_energy" and bool(GameState.story_flags.get("game_won", false)):
		_show_ending()


func _show_ending() -> void:
	if ending_panel == null:
		return
	var stats: Dictionary = GameState.get_player_stats()
	var military: Dictionary = GameState.get_military_rank()
	var nobility: Dictionary = GameState.get_nobility_rank()
	var relationship: Dictionary = GameState.get_affection_rank()
	AudioService.stop_music()
	ending_panel.show_snapshot({
		"won":bool(GameState.story_flags.get("game_won", false)),
		"day":GameState.current_day,
		"combat_power":int(stats.get("combat_power", 0)),
		"level":GameState.level,
		"equipment_combat_power":int(stats.get("equipment_combat_power", 0)),
		"pet_combat_power":int(stats.get("pet_combat_power", 0)),
		"military_level":int(military.get("level", 0)),
		"military_name":str(military.get("name", "无军衔")),
		"nobility_level":int(nobility.get("level", 0)),
		"nobility_name":str(nobility.get("name", "平民")),
		"affection_level":int(relationship.get("level", 0)),
		"affection_name":str(relationship.get("name", "未认识")),
		"gold":GameState.gold,
		"magic_stones":GameState.magic_stones,
	})


func _start_battle(monster_id: String) -> void:
	for candidate: Variant in interactive_actors.keys():
		var action_id := str(candidate)
		if action_id.begins_with("battle:") and _world_monster_id_from_action(action_id) == monster_id:
			_engage_world_monster(action_id)
			return
	_set_status("当前场景中找不到该怪物。")


func _set_status(text: String) -> void:
	status_label.text = "提示信息：" + text


func _save_game() -> void:
	_set_status("保存成功" if GameState.save_game() else "保存失败")


func _load_game() -> void:
	if GameState.load_game():
		_apply_current_map()
		_set_status("读取成功")
	else:
		_set_status("没有可读取的存档")


func _trash_hint() -> void:
	_set_status("将不要的物品拖到垃圾箱即可丢弃。")


func _toggle_music(enabled: bool) -> void:
	AudioServer.set_bus_mute(0, not enabled)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			_save_game()
		elif event.keycode == KEY_F9:
			_load_game()


func _format_number(value: int) -> String:
	var digits := str(value)
	var output := ""
	while digits.length() > 3:
		output = "," + digits.right(3) + output
		digits = digits.left(digits.length() - 3)
	return digits + output

func _process(delta: float) -> void:
	if scene_battle_controller != null and scene_battle_controller.is_active():
		return
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_update_player_animation(direction, delta)
	if direction.is_zero_approx():
		return
	player.position += direction * 150.0 * delta
	player.position.x = clampf(player.position.x, 0.0, 700.0 - player.size.x)
	player.position.y = clampf(player.position.y, 72.0, 476.0 - player.size.y)


func _update_player_animation(direction: Vector2, delta: float) -> void:
	var next_clip := "idle"
	var frames: Array = player_idle_frames
	if not direction.is_zero_approx():
		if absf(direction.y) > absf(direction.x):
			next_clip = "down" if direction.y > 0.0 else "up"
		else:
			next_clip = "right" if direction.x > 0.0 else "left"
		player_facing = next_clip
		frames = player_walk_frames[next_clip]
	if next_clip != player_animation_clip:
		player_animation_clip = next_clip
		player_animation_index = 0
		player_animation_elapsed = 0.0
	player_animation_elapsed += maxf(0.0, delta)
	var frame_duration := 1.0 / 12.0
	while player_animation_elapsed >= frame_duration:
		player_animation_elapsed -= frame_duration
		player_animation_index = (player_animation_index + 1) % frames.size()
	player.texture = frames[player_animation_index]


