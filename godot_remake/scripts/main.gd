extends Control

const InventoryPanel = preload("res://scripts/inventory_panel.gd")
const ShopPanel = preload("res://scripts/shop_panel.gd")
const EquipmentPanel = preload("res://scripts/equipment_panel.gd")
const EnhancementPanel = preload("res://scripts/enhancement_panel.gd")
const PetPanel = preload("res://scripts/pet_panel.gd")
const ResearchPanel = preload("res://scripts/research_panel.gd")
const ProgressionPanel = preload("res://scripts/progression_panel.gd")
const QuestPanel = preload("res://scripts/quest_panel.gd")
const SkillPanel = preload("res://scripts/skill_panel.gd")
const MapPanel = preload("res://scripts/map_panel.gd")
const BattlePanel = preload("res://scripts/battle_panel.gd")
const WorldService = preload("res://scripts/world_service.gd")

var player: TextureRect
var background: TextureRect
var actor_layer: Control
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
var map_panel: PanelContainer
var battle_panel: PanelContainer
var status_label: Label
var player_status_card: Dictionary = {}
var pet_status_cards: Array[Dictionary] = []
var world := WorldService.new()
var player_walk_frames: Dictionary = {}
var player_animation_elapsed: float = 0.0
var player_animation_index: int = 0
var player_facing: String = "down"


func _ready() -> void:
	_build_world()
	_build_hud()
	_build_bottom_bar()
	inventory_panel = InventoryPanel.new()
	add_child(inventory_panel)
	warehouse_panel = InventoryPanel.new()
	warehouse_panel.container_name = "warehouse"
	warehouse_panel.panel_title = "仓库"
	add_child(warehouse_panel)
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
	map_panel = MapPanel.new()
	map_panel.travel_requested.connect(_travel_to)
	map_panel.battle_requested.connect(_start_battle)
	add_child(map_panel)
	map_panel.hide()
	battle_panel = BattlePanel.new()
	battle_panel.message_changed.connect(_set_status)
	add_child(battle_panel)
	battle_panel.hide()
	_apply_current_map()
	GameState.progression_changed.connect(_refresh_status_cards)
	GameState.equipment_changed.connect(_refresh_status_cards)
	GameState.pets_changed.connect(_refresh_status_cards)
	_refresh_status_cards()
	status_label.text = "Godot 重制首版：方向键/WASD移动，背包物品可安全拖动"


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
	add_child(actor_layer)

	player = TextureRect.new()
	player_walk_frames = {
		"down":[load("res://assets/extracted/images/image_0465.png"), load("res://assets/extracted/images/image_0467.png")],
		"up":[load("res://assets/extracted/images/image_0470.png"), load("res://assets/extracted/images/image_0472.png")],
		"side":[load("res://assets/extracted/images/image_0475.png"), load("res://assets/extracted/images/image_0477.png")],
	}
	player.texture = player_walk_frames.down[0]
	player.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player.position = Vector2(292, 225)
	player.size = Vector2(118, 170)
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(player)


func _add_actor(actor_name: String, texture_path: String, actor_position: Vector2, actor_size: Vector2, label_color: Color) -> void:
	var actor := TextureRect.new()
	actor.texture = load(texture_path)
	actor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	actor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	actor.position = actor_position
	actor.size = actor_size
	actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actor_layer.add_child(actor)
	var idle_tween := actor.create_tween().set_loops()
	idle_tween.tween_property(actor, "position:y", actor_position.y - 4.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(actor, "position:y", actor_position.y, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var label := Label.new()
	label.text = actor_name
	label.position = actor_position + Vector2(-8, -20)
	label.size = Vector2(actor_size.x + 30, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", label_color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	actor_layer.add_child(label)


func _build_hud() -> void:
	var hud := HBoxContainer.new()
	hud.position = Vector2(4, 4)
	hud.size = Vector2(690, 70)
	hud.add_theme_constant_override("separation", 4)
	add_child(hud)
	player_status_card = _add_status_card(hud, "魔域玩家", "生命 550/550\n等级 1", Color("d34538"))
	pet_status_cards.append(_add_status_card(hud, "攻防型", "生命 20/20\n经验 0%", Color("c95a35")))
	pet_status_cards.append(_add_status_card(hud, "攻防型", "生命 30/30\n经验 0%", Color("c95a35")))
	location_label = Label.new()
	location_label.text = "当前地图\n卡萨诺城"
	location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	location_label.custom_minimum_size = Vector2(100, 66)
	location_label.add_theme_color_override("font_color", Color("48d340"))
	hud.add_child(location_label)


func _add_status_card(parent: HBoxContainer, title_text: String, details: String, bar_color: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(190, 66)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("515151")
	style.border_color = Color("202020")
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("d49b20"))
	box.add_child(title)
	var details_label := Label.new()
	details_label.text = details
	details_label.add_theme_color_override("font_color", bar_color)
	box.add_child(details_label)
	return {"title":title, "details":details_label}


func _refresh_status_cards() -> void:
	if player_status_card.is_empty():
		return
	var player_stats := GameState.get_player_stats()
	player_status_card.title.text = "魔域玩家"
	player_status_card.details.text = "生命 %d/%d\n等级 %d　战力 %d" % [int(player_stats.current_hp), int(player_stats.max_hp), GameState.level, int(player_stats.combat_power)]
	var deployed_pets: Array[Dictionary] = []
	for pet: Dictionary in GameState.pets:
		if bool(pet.get("deployed", false)):
			deployed_pets.append(pet)
	for index in pet_status_cards.size():
		var card: Dictionary = pet_status_cards[index]
		if index >= deployed_pets.size():
			card.title.text = "未出征"
			card.details.text = "生命 --\n经验 --"
			continue
		var pet: Dictionary = deployed_pets[index]
		var pet_stats := GameState.pet_service.get_stats(pet)
		var required_exp := GameState.pet_service.experience_to_next_level(int(pet.level))
		var experience_percent := clampi(roundi(float(pet.experience) * 100.0 / float(required_exp)), 0, 99)
		card.title.text = str(pet.custom_name)
		card.details.text = "生命 %d/%d\n%d级　经验 %d%%" % [int(pet.get("current_hp", pet_stats.max_hp)), int(pet_stats.max_hp), int(pet.level), experience_percent]


func _build_bottom_bar() -> void:
	var footer := PanelContainer.new()
	footer.position = Vector2(0, 506)
	footer.size = Vector2(700, 44)
	var footer_style := StyleBoxFlat.new()
	footer_style.bg_color = Color("303030")
	footer_style.border_color = Color("111111")
	footer_style.set_border_width_all(2)
	footer.add_theme_stylebox_override("panel", footer_style)
	add_child(footer)
	var bar := HBoxContainer.new()
	footer.add_child(bar)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.custom_minimum_size = Vector2(70, 0)
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size", 12)
	bar.add_child(status_label)
	for button_name in ["地图", "背包", "仓库", "杂货", "收藏", "装备", "养成", "幻兽", "研究", "技能", "任务", "功勋", "保存", "读取"]:
		var button := Button.new()
		button.text = button_name
		button.custom_minimum_size = Vector2(36, 36)
		button.add_theme_font_size_override("font_size", 12)
		bar.add_child(button)
		match button_name:
			"地图": button.pressed.connect(_toggle_map)
			"背包": button.pressed.connect(_toggle_inventory)
			"仓库": button.pressed.connect(_toggle_warehouse)
			"杂货": button.pressed.connect(_toggle_gold_shop)
			"收藏": button.pressed.connect(_toggle_stone_shop)
			"装备": button.pressed.connect(_toggle_equipment)
			"养成": button.pressed.connect(_toggle_enhancement)
			"幻兽": button.pressed.connect(_toggle_pets)
			"研究": button.pressed.connect(_toggle_research)
			"功勋": button.pressed.connect(_toggle_progression)
			"任务": button.pressed.connect(_toggle_quests)
			"技能": button.pressed.connect(_toggle_skills)
			"保存": button.pressed.connect(_save_game)
			"读取": button.pressed.connect(_load_game)


func _toggle_inventory() -> void:
	var should_show := not inventory_panel.visible or warehouse_panel.visible
	_hide_all_panels()
	if should_show:
		inventory_panel.position = Vector2(390, 124)
		inventory_panel.show()


func _toggle_warehouse() -> void:
	var should_show := not warehouse_panel.visible
	_hide_all_panels()
	if should_show:
		inventory_panel.position = Vector2(44, 124)
		warehouse_panel.position = Vector2(352, 124)
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


func _toggle_progression() -> void:
	_toggle_exclusive_panel(progression_panel)


func _toggle_quests() -> void:
	_toggle_exclusive_panel(quest_panel)


func _toggle_skills() -> void:
	_toggle_exclusive_panel(skill_panel)


func _toggle_map() -> void:
	var should_show := not map_panel.visible
	_hide_all_panels()
	if should_show:
		map_panel.show_map(world.get_map(GameState.current_map_id))


func _toggle_exclusive_panel(panel: Control) -> void:
	var should_show := not panel.visible
	_hide_all_panels()
	if should_show:
		panel.show()


func _hide_all_panels() -> void:
	for candidate in [inventory_panel, warehouse_panel, gold_shop, stone_shop, equipment_panel, enhancement_panel, pet_panel, research_panel, progression_panel, quest_panel, skill_panel, map_panel, battle_panel]:
		candidate.hide()

func _set_status(text: String) -> void:
	status_label.text = text


func _save_game() -> void:
	status_label.text = "保存成功：%s" % GameState.save_path if GameState.save_game() else "保存失败"


func _load_game() -> void:
	if GameState.load_game():
		_apply_current_map()
		status_label.text = "读取成功"
	else:
		status_label.text = "没有可读取的存档"


func _travel_to(map_id: String) -> void:
	if not world.can_travel(GameState.current_map_id, map_id):
		status_label.text = "无法到达该地图"
		return
	if not GameState.can_enter_map(map_id):
		status_label.text = "请先击败本层地下城首领"
		return
	GameState.current_map_id = map_id
	AudioService.play("change_map")
	_apply_current_map()
	map_panel.show_map(world.get_map(map_id))
	status_label.text = "已到达：%s" % world.get_map(map_id).get("name", map_id)


func _apply_current_map() -> void:
	var map_data := world.get_map(GameState.current_map_id)
	if map_data.is_empty():
		GameState.current_map_id = "cassano_city"
		map_data = world.get_map(GameState.current_map_id)
	background.texture = load(str(map_data.get("background", "")))
	_rebuild_map_actors(GameState.current_map_id)
	var spawn: Array = map_data.get("spawn", [292, 225])
	player.position = Vector2(float(spawn[0]), float(spawn[1]))
	location_label.text = "当前地图\n%s" % map_data.get("name", "未知")


func _rebuild_map_actors(map_id: String) -> void:
	for child in actor_layer.get_children():
		actor_layer.remove_child(child)
		child.queue_free()
	match map_id:
		"cassano_city":
			_add_actor("幻兽师", "res://assets/extracted/images/image_0431.png", Vector2(430, 160), Vector2(76, 86), Color("00ff45"))
			_add_actor("仓库管理员", "res://assets/extracted/images/image_0101.png", Vector2(575, 120), Vector2(82, 92), Color("00ff45"))
		"green_field":
			_add_actor("蜘蛛", "res://assets/extracted/images/image_0049.png", Vector2(500, 260), Vector2(84, 94), Color("ffcc35"))
		"ice_border":
			_add_actor("暴雪勇士", "res://assets/extracted/images/image_0127.png", Vector2(420, 205), Vector2(88, 105), Color("80d8ff"))
			_add_actor("暴雪骑士长", "res://assets/extracted/images/image_0051.png", Vector2(520, 165), Vector2(92, 112), Color("80d8ff"))
			_add_actor("暴雪军官", "res://assets/extracted/images/image_0049.png", Vector2(590, 245), Vector2(96, 118), Color("ffcc35"))
		"pk_arena":
			_add_actor("PK赛冠军", "res://assets/extracted/images/image_0127.png", Vector2(480, 185), Vector2(105, 125), Color("ffcc35"))
		"spider_cave":
			_add_actor("蜘蛛王后艾达", "res://assets/extracted/images/image_0051.png", Vector2(470, 210), Vector2(96, 110), Color("ff7035"))
		"dungeon":
			_add_actor("地下城首领", "res://assets/extracted/images/image_0127.png", Vector2(465, 190), Vector2(108, 120), Color("ff3030"))
		"dungeon_floor_2":
			_add_actor("地下城二层首领", "res://assets/extracted/images/image_0127.png", Vector2(465, 190), Vector2(108, 120), Color("ff3030"))
		"dungeon_floor_3":
			_add_actor("地下城三层首领", "res://assets/extracted/images/image_0127.png", Vector2(465, 190), Vector2(108, 120), Color("ff3030"))


func _start_battle(monster_id: String) -> void:
	_hide_all_panels()
	battle_panel.start_battle(monster_id)


func _process(delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_update_player_animation(direction, delta)
	if direction.is_zero_approx():
		return
	player.position += direction * 150.0 * delta
	player.position.x = clampf(player.position.x, 0.0, 700.0 - player.size.x)
	player.position.y = clampf(player.position.y, 72.0, 506.0 - player.size.y)


func _update_player_animation(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx():
		player_animation_elapsed = 0.0
		player_animation_index = 0
		player.texture = player_walk_frames[player_facing][0]
		return
	var next_facing := "side"
	if absf(direction.y) > absf(direction.x):
		next_facing = "down" if direction.y > 0.0 else "up"
	if next_facing != player_facing:
		player_facing = next_facing
		player_animation_index = 0
		player_animation_elapsed = 0.0
	player_animation_elapsed += delta
	if player_animation_elapsed >= 0.13:
		player_animation_elapsed = fmod(player_animation_elapsed, 0.13)
		player_animation_index = (player_animation_index + 1) % 2
	player.texture = player_walk_frames[player_facing][player_animation_index]
