extends Button

var destination: String = ""
var travel_verb: String = "进入"
var native_direction: String = "right"
var target_map_id: String = ""
var locked: bool = false

const DESTINATION_COLOR := Color("20ff46")
const VERB_COLOR := Color("ff3b30")
const HOVER_COLOR := Color("ffff45")
const DISABLED_COLOR := Color("777777")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.9)

## 靠屏幕边缘一侧保留给出口的独占命中带宽度。
## 演员层（z=1）压在出口之上以便怪物与 NPC 可点，但全世界有 13 处演员贴图与
## 出口命中区重叠，其中亚维特岛的鱼妖把「回冰宫」出口盖满 100%——那是该图簇
## 回主世界的唯一门，不留独占带就会把玩家永久困在亚维特岛/火山/深渊迷宫。
## 本带 z=2 高于演员层，保证每个出口至少有一条贴边可点区域。
const EDGE_PRIORITY_BAND := 12.0

var edge_strip: Control


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	edge_strip = Control.new()
	edge_strip.name = "EdgePriorityStrip"
	edge_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	edge_strip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	edge_strip.z_index = 2
	edge_strip.gui_input.connect(_on_edge_strip_input)
	add_child(edge_strip)
	resized.connect(_layout_edge_strip)
	_layout_edge_strip()


## 独占带自身不持有状态：直接读父按钮的 disabled/visible，
## 避免战斗中出口被禁用时这条带子成为绕过封锁的后门。
func _on_edge_strip_input(event: InputEvent) -> void:
	if disabled or not visible:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	emit_signal("pressed")


func _layout_edge_strip() -> void:
	if edge_strip == null:
		return
	var band := minf(EDGE_PRIORITY_BAND, minf(size.x, size.y))
	match native_direction:
		"top":
			edge_strip.position = Vector2.ZERO
			edge_strip.size = Vector2(size.x, band)
		"bottom":
			edge_strip.position = Vector2(0.0, size.y - band)
			edge_strip.size = Vector2(size.x, band)
		"left":
			edge_strip.position = Vector2.ZERO
			edge_strip.size = Vector2(band, size.y)
		_:
			edge_strip.position = Vector2(size.x - band, 0.0)
			edge_strip.size = Vector2(band, size.y)


func configure(target_id: String, target_name: String, direction: String, verb: String = "进入") -> void:
	target_map_id = target_id
	destination = target_name
	native_direction = direction
	travel_verb = verb
	tooltip_text = "%s%s" % [travel_verb, destination]
	_layout_edge_strip()
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var destination_color := _state_color(DESTINATION_COLOR)
	var verb_color := _state_color(VERB_COLOR)
	var arrow_color := _state_color(DESTINATION_COLOR)
	if native_direction in ["top", "bottom"]:
		_draw_horizontal(font, destination_color, verb_color, arrow_color)
	else:
		_draw_vertical(font, destination_color, verb_color, arrow_color)


func _state_color(normal_color: Color) -> Color:
	# A locked exit stays dim so the player sees it is gated, but it is NOT
	# Godot-disabled: pressed still fires so _travel_to can show the reason.
	if locked:
		return DISABLED_COLOR
	if is_hovered() or button_pressed:
		return HOVER_COLOR
	return normal_color


func _draw_horizontal(font: Font, destination_color: Color, verb_color: Color, arrow_color: Color) -> void:
	var font_size := 13
	var destination_width := font.get_string_size(destination, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var verb_width := font.get_string_size(travel_verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var destination_x := (size.x - destination_width) * 0.5
	var verb_x := (size.x - verb_width) * 0.5
	var destination_y := 17.0 if native_direction == "top" else 14.0
	var verb_y := 33.0 if native_direction == "top" else 29.0
	_draw_shadowed_string(font, Vector2(destination_x, destination_y), destination, font_size, destination_color)
	_draw_shadowed_string(font, Vector2(verb_x, verb_y), travel_verb, 12, verb_color)
	var center_x := size.x * 0.5
	if native_direction == "top":
		draw_colored_polygon(PackedVector2Array([
			Vector2(center_x, 0), Vector2(center_x - 7, 7), Vector2(center_x + 7, 7)
		]), arrow_color)
	else:
		draw_colored_polygon(PackedVector2Array([
			Vector2(center_x, size.y), Vector2(center_x - 7, size.y - 7), Vector2(center_x + 7, size.y - 7)
		]), arrow_color)


func _draw_vertical(font: Font, destination_color: Color, verb_color: Color, arrow_color: Color) -> void:
	var font_size := 12
	var line_height := 14.0
	var destination_height := destination.length() * line_height
	var destination_y := maxf(11.0, (size.y - destination_height) * 0.5 + 10.0)
	var destination_x := 20.0 if native_direction == "left" else 4.0
	var verb_x := 4.0 if native_direction == "left" else 21.0
	var verb_y := maxf(18.0, (size.y - travel_verb.length() * line_height) * 0.5 + 10.0)
	for index in destination.length():
		_draw_shadowed_string(font, Vector2(destination_x, destination_y + index * line_height), destination.substr(index, 1), font_size, destination_color)
	for index in travel_verb.length():
		_draw_shadowed_string(font, Vector2(verb_x, verb_y + index * line_height), travel_verb.substr(index, 1), font_size, verb_color)
	var center_y := size.y * 0.5
	if native_direction == "left":
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, center_y), Vector2(7, center_y - 7), Vector2(7, center_y + 7)
		]), arrow_color)
	else:
		draw_colored_polygon(PackedVector2Array([
			Vector2(size.x, center_y), Vector2(size.x - 7, center_y - 7), Vector2(size.x - 7, center_y + 7)
		]), arrow_color)


func _draw_shadowed_string(font: Font, draw_position: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(font, draw_position + Vector2(1, 1), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SHADOW_COLOR)
	draw_string(font, draw_position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
