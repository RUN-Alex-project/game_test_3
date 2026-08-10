extends PanelContainer

signal item_focused(item: Dictionary, source_panel: Control)
signal item_unfocused

const InventorySlot = preload("res://scripts/inventory_slot.gd")

var container_name: String = "inventory"
var panel_title: String = "背包"
var current_page: int = 0
var visible_slot_count: int = 24
var gold_label: Label
var magic_stone_label: Label
var page_label: Button
var title_label: Label
var close_button: Button
var slots: Array[PanelContainer] = []


func _ready() -> void:
	var is_warehouse := container_name == "warehouse"
	visible_slot_count = 36 if is_warehouse else 24
	position = Vector2(208, 220) if is_warehouse else Vector2(453, 300)
	size = Vector2(247, 287) if is_warehouse else Vector2(247, 207)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_native_panel_style()

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	var grid_y := 44.0 if is_warehouse else 4.0
	for local_index in visible_slot_count:
		var slot := InventorySlot.new()
		root.add_child(slot)
		slot.position = Vector2(4 + (local_index % 6) * 40, grid_y + (local_index / 6) * 40)
		slot.size = Vector2(36, 36)
		slot.custom_minimum_size = Vector2(36, 36)
		slot.configure(local_index, container_name)
		slots.append(slot)
		slot.item_focused.connect(_forward_item_focused)
		slot.item_unfocused.connect(_forward_item_unfocused)

	title_label = Label.new()
	title_label.text = panel_title
	title_label.position = Vector2(102.3, 11.9) if is_warehouse else Vector2(177.95, 172.4)
	title_label.size = Vector2(110, 28) if is_warehouse else Vector2(44, 28)
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	title_label.add_theme_constant_override("shadow_offset_x", 1)
	title_label.add_theme_constant_override("shadow_offset_y", 1)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_label)

	close_button = Button.new()
	close_button.position = Vector2(220.4, 4.95) if is_warehouse else Vector2(221.25, 172.15)
	close_button.size = Vector2(21, 21)
	close_button.custom_minimum_size = Vector2(21, 21)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "关闭"
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_native_close_styles(close_button)
	close_button.pressed.connect(hide)
	root.add_child(close_button)

	page_label = Button.new()
	page_label.position = Vector2(160, 7) if is_warehouse else Vector2(132, 172)
	page_label.size = Vector2(42, 21)
	page_label.focus_mode = Control.FOCUS_NONE
	page_label.flat = true
	page_label.add_theme_font_size_override("font_size", 10)
	page_label.add_theme_color_override("font_color", Color("dddddd"))
	page_label.add_theme_color_override("font_hover_color", Color("ffff66"))
	page_label.tooltip_text = "切换下一页（保留旧版48格存档兼容）"
	page_label.pressed.connect(_cycle_page)
	root.add_child(page_label)

	if not is_warehouse:
		gold_label = _make_currency_label(root, Vector2(4, 165), Color("ff9900"))
		magic_stone_label = _make_currency_label(root, Vector2(4, 186.4), Color("00cc33"))

	GameState.inventory_changed.connect(_refresh_inventory)
	GameState.currency_changed.connect(_refresh_currency)
	_set_page(0)
	_refresh_currency()


func _build_native_panel_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("666666")
	panel_style.border_color = Color("202020")
	panel_style.set_border_width_all(2)
	panel_style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", panel_style)


func _apply_native_close_styles(button: Button) -> void:
	var states := [
		["normal", Color("333333")],
		["hover", Color("999999")],
		["pressed", Color("000000")],
		["disabled", Color("333333")],
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


func _make_currency_label(parent: Control, label_position: Vector2, label_color: Color) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = Vector2(174, 20)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", label_color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _cycle_page() -> void:
	var page_count := _page_count()
	_set_page((current_page + 1) % page_count)


func _page_count() -> int:
	return maxi(1, ceili(float(GameState.get_container(container_name).size()) / visible_slot_count))


func _set_page(page: int) -> void:
	var page_count := _page_count()
	current_page = clampi(page, 0, page_count - 1)
	page_label.text = "%d/%d" % [current_page + 1, page_count]
	page_label.visible = page_count > 1
	_refresh_inventory()


func _refresh_inventory() -> void:
	for local_index in slots.size():
		slots[local_index].configure(current_page * visible_slot_count + local_index, container_name)


func _refresh_currency() -> void:
	if gold_label == null or magic_stone_label == null:
		return
	gold_label.text = "金币：%s" % _format_number(GameState.gold)
	magic_stone_label.text = "魔石：%s" % _format_number(GameState.magic_stones)


func _forward_item_focused(item: Dictionary) -> void:
	item_focused.emit(item, self)


func _forward_item_unfocused() -> void:
	item_unfocused.emit()


func _format_number(value: int) -> String:
	var digits := str(value)
	var output := ""
	while digits.length() > 3:
		output = "," + digits.right(3) + output
		digits = digits.left(digits.length() - 3)
	return digits + output
