extends Node


func _ensure_item(item_id: String, target_count: int) -> void:
	var missing := target_count - GameState.count_item(item_id)
	if missing > 0:
		assert(GameState.add_item(item_id, missing), "fixture item could not be added: " + item_id)


func _ready() -> void:
	GameState._initialize_inventory()
	GameState.current_day = 7
	GameState.gold = 100000000
	GameState.magic_stones = 0
	GameState.military_merit = 1000
	GameState.nobility_merit = 0
	GameState.affection = 1
	GameState.last_military_salary_day = 0
	GameState.last_princess_gift_day = 0
	GameState.completed_daily_tasks.clear()
	_ensure_item("rose", 99)
	_ensure_item("magic_soul_crystal", 1)
	_ensure_item("soul_king", 1)
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_progression()
	var panel = main.progression_panel
	assert(panel.visible, "VIP footer did not open growth flow sheet")
	assert(panel.position == Vector2(450, 215) and panel.size == Vector2(243, 289), "growth sheet no longer fits the right-side native area")
	assert(panel.position.y + panel.size.y <= 506.0, "growth sheet overlaps native footer")
	assert(panel.get_theme_stylebox("panel").bg_color == Color("666666"), "growth sheet does not use native gray fill")
	assert("少尉" in panel.summary_label.text and "平民" in panel.summary_label.text, "rank summary is incomplete")
	assert(not panel.salary_button.disabled and not panel.sunday_gift_button.disabled, "Sunday salary/gift flow should be available")
	panel._claim_salary()
	assert(GameState.magic_stones == 999999999 and GameState.last_military_salary_day == 7, "military salary did not settle")
	panel._donate(750000)
	assert(GameState.nobility_merit == 1 and GameState.gold == 99250000, "gold donation did not settle")
	panel._give_roses(99)
	assert(GameState.affection == 51 and GameState.count_item("rose") == 0, "rose relationship flow did not settle")
	panel._complete_task("collect_magic_soul")
	panel._complete_task("collect_soul_king")
	assert(GameState.nobility_merit == 2501, "daily merit tasks did not settle")
	panel._claim_sunday_gift()
	assert(GameState.last_princess_gift_day == 7, "Sunday princess gift did not settle")
	assert(panel.salary_button.disabled and panel.sunday_gift_button.disabled, "claimed Sunday actions were not disabled")
	panel.close_button.emit_signal("pressed")
	assert(not panel.visible, "growth sheet close control failed")
	print("PASS compact military, nobility, relationship, daily merit, Sunday salary and gift flow")
	get_tree().quit(0)