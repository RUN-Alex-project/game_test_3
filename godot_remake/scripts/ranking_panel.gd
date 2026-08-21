extends PanelContainer

signal message_changed(text: String)

var close_button: Button
var board_list: ItemList
var entry_list: ItemList
var _board_ids: Array[String] = []


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
	title.text = "\u5192\u9669\u8005\u6392\u884c\u699c"
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

	board_list = ItemList.new()
	board_list.position = Vector2(6, 30)
	board_list.size = Vector2(140, 310)
	board_list.item_selected.connect(_on_board_selected)
	root.add_child(board_list)

	entry_list = ItemList.new()
	entry_list.position = Vector2(152, 30)
	entry_list.size = Vector2(204, 310)
	root.add_child(entry_list)

	visibility_changed.connect(_refresh)
	GameState.social_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	GameState.refresh_rankings()
	_board_ids.clear()
	board_list.clear()
	var rules: Dictionary = GameState.expansion_state_service.ranking_service.rules
	for raw_board: Variant in rules.get("boards", []):
		if not raw_board is Dictionary:
			continue
		var board_id := str(raw_board.get("id", ""))
		if board_id.is_empty():
			continue
		_board_ids.append(board_id)
		var label := str(raw_board.get("display_name", board_id))
		if bool(raw_board.get("preview", false)):
			label += " *"
		board_list.add_item(label)
	if _board_ids.is_empty():
		entry_list.clear()
		return
	if board_list.get_selected_items().is_empty():
		board_list.select(0)
	_render_board(board_list.get_selected_items()[0])


func _on_board_selected(index: int) -> void:
	_render_board(index)


func _render_board(index: int) -> void:
	entry_list.clear()
	if index < 0 or index >= _board_ids.size():
		return
	var board: Dictionary = GameState.get_ranking_board(_board_ids[index])
	for raw_entry: Variant in board.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		entry_list.add_item("%d  %s  %d" % [
			int(raw_entry.get("rank", 0)),
			str(raw_entry.get("id", "")),
			int(raw_entry.get("primary", 0)),
		])
