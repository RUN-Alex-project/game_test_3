extends PanelContainer

signal item_focused(item: Dictionary)
signal item_unfocused

var slot_index: int = -1
var container_name: String = "inventory"
var slot_data: Dictionary = {}
var icon_rect: TextureRect
var quantity_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(36, 36)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("333333")
	style.border_color = Color("999999")
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	mouse_entered.connect(_emit_item_focused)
	mouse_exited.connect(_emit_item_unfocused)

	icon_rect = TextureRect.new()
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon_rect)

	quantity_label = Label.new()
	quantity_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quantity_label.position = Vector2(-28, -21)
	quantity_label.size = Vector2(24, 18)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.add_theme_color_override("font_color", Color.WHITE)
	quantity_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quantity_label)
	refresh()


func configure(index: int, source_container: String = "inventory") -> void:
	slot_index = index
	container_name = source_container
	refresh()


func refresh() -> void:
	if not is_node_ready() or slot_index < 0:
		return
	slot_data = GameState.get_slot(slot_index, container_name)
	if slot_data.is_empty():
		icon_rect.texture = null
		quantity_label.text = ""
		tooltip_text = ""
		return
	var definition := GameState.get_item_definition(slot_data.get("item_id", ""))
	var icon_path: String = definition.get("icon", "")
	icon_rect.texture = load(icon_path) if not icon_path.is_empty() else null
	var quantity := int(slot_data.get("quantity", 1))
	quantity_label.text = str(quantity) if quantity > 1 else ""
	tooltip_text = "%s\n%s" % [definition.get("name", "未知物品"), definition.get("description", "")]
	if slot_data.has("enhancement"):
		var instance: Dictionary = slot_data.enhancement
		tooltip_text += "\n品质 +%d　魔魂 +%d　天魂 %d　地魂 %d" % [
			int(instance.get("quality_level", 0)),
			int(instance.get("magic_soul_level", 0)),
			int(instance.get("heaven_soul_level", 0)),
			int(instance.get("earth_soul_level", 0)),
		]
	tooltip_text = ""



func _emit_item_focused() -> void:
	if not slot_data.is_empty():
		item_focused.emit(slot_data)


func _emit_item_unfocused() -> void:
	item_unfocused.emit()
func _get_drag_data(_at_position: Vector2) -> Variant:
	if slot_data.is_empty():
		return null
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(36, 30)
	preview.texture = icon_rect.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.9)
	set_drag_preview(preview)
	return {"kind": "inventory_item", "source_index": slot_index, "source_container": container_name}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind", "") == "inventory_item" and int(data.get("source_index", -1)) >= 0


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	GameState.move_item_between(str(data.get("source_container", "inventory")), int(data.get("source_index", -1)), container_name, slot_index)


func _gui_input(event: InputEvent) -> void:
	if container_name != "inventory" or slot_data.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		if not GameState.equip_from_inventory(slot_index):
			GameState.use_inventory_item(slot_index)
		accept_event()

