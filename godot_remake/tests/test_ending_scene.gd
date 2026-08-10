extends Node

const EndingService = preload("res://scripts/ending_service.gd")
const EndingPanel = preload("res://scripts/ending_panel.gd")


func _ready() -> void:
	var maximum := {
		"won":true, "day":60, "combat_power":1200, "level":132,
		"equipment_combat_power":126, "pet_combat_power":400,
		"military_level":11, "military_name":"元帅",
		"nobility_level":6, "nobility_name":"王",
		"affection_level":6, "affection_name":"亲密爱人",
		"gold":0, "magic_stones":499999,
	}
	var best := EndingService.evaluate(maximum)
	assert(best.highest_count == 7, "ending did not count the original seven highest ratings")
	assert("绝世高手" in best.review, "highest composite ending is missing")
	var all_eight := maximum.duplicate(true)
	all_eight.magic_stones = 500000
	var original_quirk := EndingService.evaluate(all_eight)
	assert(original_quirk.highest_count == 8 and "天啊" in original_quirk.review, "the original maxprice equals-seven quirk was not preserved")
	var ordinary := maximum.duplicate(true)
	ordinary.combat_power = 299
	ordinary.level = 69
	ordinary.equipment_combat_power = 47
	ordinary.pet_combat_power = 99
	ordinary.military_level = 0
	ordinary.nobility_level = 0
	ordinary.affection_level = 0
	ordinary.magic_stones = 0
	var low := EndingService.evaluate(ordinary)
	assert(low.combat_rating == "无" and low.level_rating == "低级菜鸟", "low ending thresholds drifted")
	assert(low.equipment_rating == "装备打造傻鸟" and low.pet_rating == "不会培养幻兽", "low build ratings drifted")

	var panel := EndingPanel.new()
	add_child(panel)
	panel.show_snapshot(maximum)
	assert(panel.visible and "游戏结束" in panel.report.text and "亲密爱人" in panel.report.text, "ending panel did not render the original evaluation fields")
	GameState.story_flags["game_won"] = true
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	assert(main.ending_panel.visible and "游戏结束" in main.ending_panel.report.text, "loaded victory state did not automatically enter the ending panel")
	print("PASS original ending evaluation thresholds, terminal panel, and main-scene integration")
	get_tree().quit(0)
