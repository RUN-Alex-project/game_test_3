extends PanelContainer

signal travel_requested(map_id: String)
signal battle_requested(monster_id: String)

const CombatService = preload("res://scripts/combat_service.gd")

var content: VBoxContainer
var combat := CombatService.new(1)


func _ready() -> void:
	position = Vector2(170, 120)
	size = Vector2(360, 382)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("555555")
	style.border_color = Color("202020")
	style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	add_child(content)


func show_map(map_data: Dictionary) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "地图：%s" % map_data.get("name", "未知")
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "—"
	close.pressed.connect(func() -> void: hide())
	header.add_child(close)

	var exit_title := Label.new()
	exit_title.text = "传送点"
	exit_title.add_theme_color_override("font_color", Color("50ff50"))
	content.add_child(exit_title)
	for exit_data: Dictionary in map_data.get("exits", []):
		var button := Button.new()
		var target_map_id := str(exit_data.get("target", ""))
		button.text = str(exit_data.get("name", target_map_id))
		if not GameState.can_enter_map(target_map_id):
			button.text += "（需击败本层首领）"
			button.disabled = true
		else:
			button.pressed.connect(_request_travel.bind(target_map_id))
		content.add_child(button)

	var encounters: Array = map_data.get("encounters", [])
	var encounter_title := Label.new()
	encounter_title.text = "附近怪物"
	encounter_title.add_theme_color_override("font_color", Color("ffcc35"))
	content.add_child(encounter_title)
	if encounters.is_empty():
		var empty := Label.new()
		empty.text = "安全区域"
		content.add_child(empty)
	for monster_id: Variant in encounters:
		var monster := combat.get_monster(str(monster_id))
		var battle := Button.new()
		battle.text = "挑战 %s（%d级）" % [monster.get("name", monster_id), int(monster.get("level", 1))]
		battle.pressed.connect(_request_battle.bind(str(monster_id)))
		content.add_child(battle)
	show()


func _request_travel(map_id: String) -> void:
	travel_requested.emit(map_id)


func _request_battle(monster_id: String) -> void:
	battle_requested.emit(monster_id)
