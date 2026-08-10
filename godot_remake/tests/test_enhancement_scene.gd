extends Node

const EnhancementService = preload("res://scripts/enhancement_service.gd")


func _ready() -> void:
	var service := EnhancementService.new()
	var equipment := service.create_equipment_instance("novice_sword")
	var quality := service.refine_quality(equipment)
	assert(quality.success and quality.equipment.quality_level == 1, "quality refining is not guaranteed")
	assert(equipment.quality_level == 0, "quality refining mutated the input instance")
	var magic_soul := service.upgrade_magic_soul(quality.equipment)
	assert(magic_soul.success and magic_soul.equipment.magic_soul_level == 1, "magic soul upgrade is not guaranteed")

	var failed_war_soul := service.activate_war_soul(magic_soul.equipment, 0.50)
	assert(not failed_war_soul.success and not failed_war_soul.equipment.war_soul_active, "war soul 50 percent boundary is incorrect")
	var successful_war_soul := service.activate_war_soul(magic_soul.equipment, 0.4999)
	assert(successful_war_soul.success and successful_war_soul.equipment.war_soul_active, "war soul success branch is incorrect")
	assert(is_equal_approx(service.stat_multiplier(successful_war_soul.equipment), 1.08), "war soul incorrectly changed base equipment stats")

	var souls := service.set_soul_levels(successful_war_soul.equipment, 5, 5)
	var bonuses := service.soul_bonuses(souls)
	assert(bonuses.attack_percent == 50 and bonuses.dodge_percent == 20, "heaven/earth soul bonuses are incorrect")
	assert(service.war_soul_combat_power_percent(souls) == 50, "lowest soul level combat power bonus is incorrect")
	assert(service.rose_affection(99) == 50 and service.rose_affection(999) == 250, "rose affection x10 values are incorrect")
	print("PASS guaranteed refining, magic soul, war soul boundary, doubled soul bonuses, and roses")
	get_tree().quit(0)
