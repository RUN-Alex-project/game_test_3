extends Node


func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._toggle_pets()
	await get_tree().process_frame
	assert(main.pet_panel.visible, "pet panel did not remain visible")
	assert(main.pet_panel.position.y + main.pet_panel.size.y <= 506.0, "pet panel overlaps the bottom bar")
	main._toggle_research()
	await get_tree().process_frame
	assert(main.research_panel.visible and not main.pet_panel.visible, "research panel exclusivity failed")
	assert(main.research_panel.position.y + main.research_panel.size.y <= 506.0, "research panel overlaps the bottom bar")
	print("PASS pet and research panels fit the playable viewport")
	get_tree().quit(0)
