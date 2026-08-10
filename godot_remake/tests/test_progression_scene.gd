extends Node

const ProgressionService = preload("res://scripts/progression_service.gd")


func _ready() -> void:
	var service := ProgressionService.new()
	assert(service.tier_for("military", 999).name == "无军衔", "military rank lower boundary is incorrect")
	assert(service.tier_for("military", 1000).name == "少尉", "first military rank threshold is incorrect")
	assert(service.tier_for("military", 54000).combat_power == 50, "general combat power is incorrect")
	assert(service.tier_for("military", 100000).name == "元帅", "marshal threshold is incorrect")
	assert(service.tier_for("nobility", 29999).name == "侯爵", "nobility threshold ordering is incorrect")
	assert(service.tier_for("nobility", 30000).name == "公爵", "duke threshold is incorrect")
	assert(service.combat_power_bonus(100000, 100000) == 110, "rank combat power total is incorrect")
	assert(service.donation_result(1499999, 1499999) == {"gold_cost":750000, "nobility_merit":1}, "gold donation floor is incorrect")
	assert(service.rose_affection(99) == 50 and service.rose_affection(999) == 250, "x10 rose affection is incorrect")

	GameState.military_merit = 0
	GameState.nobility_merit = 0
	GameState.affection = 0
	GameState.current_day = 1
	GameState.completed_daily_tasks.clear()
	GameState.gold = 100000000
	var donation := GameState.donate_gold_for_nobility(75000000)
	assert(donation.success and donation.nobility_merit == 100, "integrated gold donation failed")
	assert(GameState.gold == 25000000 and GameState.nobility_merit == 100, "gold donation settlement is incorrect")

	assert(GameState.add_item("rose", 89), "99-rose fixture failed")
	var roses_99 := GameState.give_roses(99)
	assert(roses_99.success and GameState.affection == 50 and GameState.count_item("rose") == 0, "99 roses were not consumed atomically")
	assert(GameState.add_item("rose", 999), "999-rose fixture failed")
	var roses_999 := GameState.give_roses(999)
	assert(roses_999.success and GameState.affection == 300, "999 rose affection is incorrect")
	assert(GameState.get_affection_rank().name == "亲密爱人", "affection relationship tier is incorrect")

	assert(GameState.add_item("magic_soul_crystal"), "daily magic-soul fixture failed")
	assert(GameState.add_item("soul_king"), "daily Soul King fixture failed")
	assert(GameState.complete_daily_task("collect_magic_soul").nobility_merit == 500, "magic-soul daily reward is incorrect")
	assert(not GameState.complete_daily_task("collect_magic_soul").success, "daily task could be claimed twice")
	assert(GameState.complete_daily_task("collect_soul_king").nobility_merit == 2000, "Soul King daily reward is incorrect")
	assert(GameState.nobility_merit == 2600 and GameState.get_nobility_rank().name == "勋爵", "daily merit did not update nobility")
	GameState.advance_day()
	assert(GameState.current_day == 2 and GameState.completed_daily_tasks.is_empty(), "daily reset failed")
	print("PASS exact military/nobility ranks, combat power, donation, daily merit, and x10 rose affection")
	get_tree().quit(0)
