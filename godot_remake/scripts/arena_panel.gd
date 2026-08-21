extends PanelContainer

signal message_changed(text: String)
signal start_requested(monster_id: String)

var close_button: Button
var npc_list: ItemList
var report_list: ItemList
var practice_button: Button
var challenge_button: Button
var season_button: Button
var _npc_ids: Array[String] = []
var _op := 0


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
	title.text = "\u5f02\u6b65\u64c2\u53f0"
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

	npc_list = ItemList.new()
	npc_list.position = Vector2(6, 30)
	npc_list.size = Vector2(170, 200)
	root.add_child(npc_list)

	practice_button = Button.new()
	practice_button.text = "\u7ec3\u4e60\u8d5b"
	practice_button.position = Vector2(182, 30)
	practice_button.size = Vector2(174, 24)
	practice_button.focus_mode = Control.FOCUS_NONE
	practice_button.pressed.connect(func() -> void: _begin("practice"))
	root.add_child(practice_button)

	challenge_button = Button.new()
	challenge_button.text = "\u6311\u6218\u8d5b"
	challenge_button.position = Vector2(182, 58)
	challenge_button.size = Vector2(174, 24)
	challenge_button.focus_mode = Control.FOCUS_NONE
	challenge_button.pressed.connect(func() -> void: _begin("challenge"))
	root.add_child(challenge_button)

	season_button = Button.new()
	season_button.text = "\u8d5b\u5b63\u8d5b"
	season_button.position = Vector2(182, 86)
	season_button.size = Vector2(174, 24)
	season_button.focus_mode = Control.FOCUS_NONE
	season_button.pressed.connect(func() -> void: _begin("season"))
	root.add_child(season_button)

	report_list = ItemList.new()
	report_list.position = Vector2(6, 238)
	report_list.size = Vector2(350, 128)
	root.add_child(report_list)

	visibility_changed.connect(_refresh)
	GameState.social_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	_npc_ids.clear()
	npc_list.clear()
	var svc = GameState.expansion_state_service.adventurer_service
	for adv_id in svc.all_ids():
		_npc_ids.append(adv_id)
		var row: Dictionary = svc.get_adventurer(adv_id)
		npc_list.add_item(str(row.get("display_name", adv_id)))
	if not _npc_ids.is_empty() and npc_list.get_selected_items().is_empty():
		npc_list.select(0)
	report_list.clear()
	for raw_report: Variant in GameState.get_arena_reports():
		if not raw_report is Dictionary:
			continue
		report_list.add_item("%s %s %+d" % [
			str(raw_report.get("mode", "")),
			str(raw_report.get("opponent_id", "")),
			int(raw_report.get("score_delta", 0)),
		])


func _begin(mode: String) -> void:
	if _npc_ids.is_empty():
		message_changed.emit("ERR_ARENA_BAD_OPPONENT")
		return
	if npc_list.get_selected_items().is_empty():
		npc_list.select(0)
	var index: int = npc_list.get_selected_items()[0]
	var adv_id := _npc_ids[index]
	_op += 1
	var result: Dictionary = GameState.begin_arena_match(adv_id, mode, "ui:%s:%d" % [mode, _op])
	if not bool(result.get("success", false)):
		message_changed.emit(str(result.get("code", "ERR")))
		return
	start_requested.emit(str(result.get("monster_id", "")))
