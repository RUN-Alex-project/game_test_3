extends Panel

const EndingService = preload("res://scripts/ending_service.gd")

var report: RichTextLabel


func _ready() -> void:
	name = "EndingPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1000
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color("14100d")
	backdrop.border_color = Color("b28b45")
	backdrop.set_border_width_all(5)
	add_theme_stylebox_override("panel", backdrop)
	report = RichTextLabel.new()
	report.name = "Report"
	report.position = Vector2(50, 32)
	report.size = Vector2(600, 486)
	report.bbcode_enabled = true
	report.fit_content = false
	report.scroll_active = true
	report.add_theme_font_size_override("normal_font_size", 18)
	report.add_theme_constant_override("line_separation", 4)
	add_child(report)
	hide()


func show_snapshot(snapshot: Dictionary) -> void:
	report.text = EndingService.format_report(snapshot)
	report.scroll_to_line(0)
	show()


func is_showing_ending() -> bool:
	return visible
