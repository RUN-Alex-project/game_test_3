extends PanelContainer

signal message_changed(text: String)

var close_button: Button
var rows: ItemList


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
	title.text = "\u8d5b\u5b63\u7c3f"
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
	for state_name in ["normal", "hover", "pressed"]:
		close_button.add_theme_stylebox_override(state_name, close_style)
	close_button.pressed.connect(hide)
	root.add_child(close_button)
	rows = ItemList.new()
	rows.position = Vector2(6, 32)
	rows.size = Vector2(350, 330)
	root.add_child(rows)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh()
	)


const TITLE_COLOR := Color("7a3200")
const HEADER_COLOR := Color("3d2a12")
const ITEM_COLOR := Color("241a0c")
const DIM_COLOR := Color("6b5a44")


## 用 GameState.season_board_view()（人话版）而不是 season_board_lines()
## （给测试断言的 key=value 串）——后者直接显示会让玩家看到调试文本。
func refresh() -> void:
	rows.clear()
	for raw: Variant in GameState.season_board_view():
		var entry: Dictionary = raw if raw is Dictionary else {}
		var index := rows.add_item(str(entry.get("text", "")))
		rows.set_item_selectable(index, false)
		match str(entry.get("kind", "info")):
			"title":
				rows.set_item_custom_fg_color(index, TITLE_COLOR)
			"header":
				rows.set_item_custom_fg_color(index, HEADER_COLOR)
			"dim":
				rows.set_item_custom_fg_color(index, DIM_COLOR)
			_:
				rows.set_item_custom_fg_color(index, ITEM_COLOR)
